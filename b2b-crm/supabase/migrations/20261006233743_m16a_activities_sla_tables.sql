-- M16a: status and activity sync (spec B8.2), SLAs in working hours (B8.5), health and reconciliation (B8.4): tables
-- and the working-time functions.
--   partner_activities     every sales activity a partner reports (calls, messages, meetings, notes, stage changes)
--   sla_checks             one row per allocation, SLA and clock start: due time, when it was met, breach
--   reconciliation_runs    a comparison of B2B's view with the partner's (nightly, or from the partner's export)
--   reconciliation_items   each mismatch, as a task for the Admin
-- Working time is the partner's working hours and holidays in India time; partners without hours use Mon–Fri 10:00–19:00
-- and Sat 10:00–17:00 (the form's default).

create table if not exists b2b.partner_activities (
  id                     bigint generated always as identity primary key,
  allocation_id          bigint not null references b2b.allocations (id),
  lead_id                bigint not null,
  partner_id             bigint not null references b2b.partners (id),
  partner_event_id       bigint references b2b.partner_events (id),
  kind                   text not null check (kind in ('call', 'whatsapp', 'email', 'sms', 'meeting', 'note', 'task', 'stage_change')),
  direction              text check (direction in ('outbound', 'inbound')),
  outcome                text,
  duration_sec           int check (duration_sec is null or duration_sec between 0 and 86400),
  counsellor_name        text,
  counsellor_external_id text,
  occurred_at            timestamptz not null,
  raw                    jsonb,
  mapped                 jsonb,
  created_at             timestamptz not null default now()
);
create index if not exists partner_activities_lead_idx on b2b.partner_activities (lead_id, occurred_at desc);
create index if not exists partner_activities_alloc_idx on b2b.partner_activities (allocation_id, kind, occurred_at);
create unique index if not exists partner_activities_event_once on b2b.partner_activities (partner_event_id) where partner_event_id is not null;

create table if not exists b2b.sla_checks (
  id             bigint generated always as identity primary key,
  allocation_id  bigint not null references b2b.allocations (id),
  lead_id        bigint not null,
  partner_id     bigint not null references b2b.partners (id),
  sla            text not null check (sla in ('first_attempt', 'first_connect', 'counselling_outcome', 'status_update', 'enrollment_proof')),
  started_at     timestamptz not null,
  due_at         timestamptz not null,
  met_at         timestamptz,
  status         text not null default 'pending' check (status in ('pending', 'met', 'met_late', 'breached', 'void')),
  breached_at    timestamptz,
  is_test        boolean not null default false,
  updated_at     timestamptz not null default now(),
  unique (allocation_id, sla, started_at)
);
create index if not exists sla_checks_open_idx on b2b.sla_checks (status, due_at) where status in ('pending', 'breached');
create index if not exists sla_checks_partner_idx on b2b.sla_checks (partner_id, due_at desc);

create table if not exists b2b.reconciliation_runs (
  id           bigint generated always as identity primary key,
  partner_id   bigint not null references b2b.partners (id),
  source       text not null check (source in ('nightly', 'manual', 'export')),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  summary      jsonb,
  created_by   text
);
create index if not exists reconciliation_runs_partner_idx on b2b.reconciliation_runs (partner_id, id desc);

create table if not exists b2b.reconciliation_items (
  id             bigint generated always as identity primary key,
  partner_id     bigint not null references b2b.partners (id),
  run_id         bigint references b2b.reconciliation_runs (id),
  kind           text not null check (kind in ('no_record_id', 'unknown_record', 'stale', 'held_events', 'missing_at_partner', 'missing_at_eduwit', 'status_mismatch')),
  item_key       text not null,          -- allocation id, partner record id or event id: one open item per partner, kind and key
  allocation_id  bigint,
  lead_id        bigint,
  detail         jsonb not null default '{}',
  status         text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  note           text,
  first_seen     timestamptz not null default now(),
  last_seen      timestamptz not null default now(),
  resolved_at    timestamptz
);
create unique index if not exists reconciliation_items_one_open on b2b.reconciliation_items (partner_id, kind, item_key) where status = 'open';
create index if not exists reconciliation_items_partner_idx on b2b.reconciliation_items (partner_id, status, last_seen desc);

-- dead letters: an event that failed to apply can be discarded with a reason (rows are kept)
alter table b2b.partner_events add column if not exists discarded_at timestamptz;
alter table b2b.partner_events add column if not exists discard_reason text;
alter table public.student_leads add column if not exists partner_stale_at timestamptz;

do $rls$
declare t text;
begin
  foreach t in array array['partner_activities', 'sla_checks', 'reconciliation_runs', 'reconciliation_items'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- ---------- working time ----------
/* The partner's working hours, or the default week. */
create or replace function b2b.partner_hours(p_partner_id bigint)
returns jsonb language sql stable set search_path = '' as $fn$
  select case when exists (select 1 from jsonb_each(coalesce(p.working_hours, '{}')) d where jsonb_typeof(d.value) = 'object') then p.working_hours
              else '{"mon":{"open":"10:00","close":"19:00"},"tue":{"open":"10:00","close":"19:00"},"wed":{"open":"10:00","close":"19:00"},
                     "thu":{"open":"10:00","close":"19:00"},"fri":{"open":"10:00","close":"19:00"},"sat":{"open":"10:00","close":"17:00"},"sun":null}'::jsonb end
    from b2b.partners p where p.id = p_partner_id;
$fn$;

/* The partner's open windows from the day of p_from, for p_days days, in India time; holidays are skipped. */
create or replace function b2b.working_windows(p_partner_id bigint, p_from timestamptz, p_days int)
returns table (win_start timestamptz, win_end timestamptz) language plpgsql stable set search_path = '' as $fn$
declare
  v_hours jsonb := b2b.partner_hours(p_partner_id);
  v_hol date[] := coalesce((select holidays from b2b.partners where id = p_partner_id), '{}');
  d date := (p_from at time zone 'Asia/Kolkata')::date;
  i int;
  h jsonb;
begin
  for i in 0 .. greatest(p_days, 1) - 1 loop
    h := v_hours -> (array['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'])[extract(dow from d + i)::int + 1];
    if jsonb_typeof(h) = 'object' and not ((d + i) = any (v_hol)) and (h ->> 'open') < (h ->> 'close') then
      win_start := ((d + i) + (h ->> 'open')::time) at time zone 'Asia/Kolkata';
      win_end := ((d + i) + (h ->> 'close')::time) at time zone 'Asia/Kolkata';
      if win_end > p_from then return next; end if;
    end if;
  end loop;
end $fn$;

/* When p_minutes of the partner's working time have passed after p_from. */
create or replace function b2b.working_deadline(p_partner_id bigint, p_from timestamptz, p_minutes int)
returns timestamptz language plpgsql stable set search_path = '' as $fn$
declare w record; v_left numeric := greatest(p_minutes, 0); v_avail numeric; s timestamptz;
begin
  if v_left = 0 then return p_from; end if;
  for w in select * from b2b.working_windows(p_partner_id, p_from, 90) order by win_start loop
    s := greatest(w.win_start, p_from);
    v_avail := extract(epoch from w.win_end - s) / 60;
    if v_avail >= v_left then return s + make_interval(mins => v_left::int); end if;
    v_left := v_left - v_avail;
  end loop;
  return p_from + make_interval(mins => p_minutes);   -- a partner with no working time at all: plain clock time
end $fn$;

/* The close of the partner's n-th working day after the day of p_from (a lead pushed on Monday has until Tuesday's close for one day). */
create or replace function b2b.working_days_deadline(p_partner_id bigint, p_from timestamptz, p_days int)
returns timestamptz language sql stable set search_path = '' as $fn$
  select coalesce(
    (select w.win_end from b2b.working_windows(p_partner_id, p_from, 120) w
      where (w.win_start at time zone 'Asia/Kolkata')::date > (p_from at time zone 'Asia/Kolkata')::date
      order by w.win_start offset greatest(p_days, 1) - 1 limit 1),
    p_from + make_interval(days => p_days));
$fn$;

/* Working minutes between two times (for SLA reporting). */
create or replace function b2b.working_minutes_between(p_partner_id bigint, p_from timestamptz, p_to timestamptz)
returns int language sql stable set search_path = '' as $fn$
  select coalesce(sum(greatest(0, extract(epoch from least(w.win_end, p_to) - greatest(w.win_start, p_from)) / 60))::int, 0)
    from b2b.working_windows(p_partner_id, p_from, greatest(1, ((p_to at time zone 'Asia/Kolkata')::date - (p_from at time zone 'Asia/Kolkata')::date) + 1)) w
   where w.win_start < p_to and p_to > p_from;
$fn$;

/* One SLA setting for a partner: its own value, else the default. */
create or replace function b2b.partner_sla(p_partner_id bigint, p_key text)
returns int language sql stable set search_path = '' as $fn$
  select coalesce((p.sla ->> p_key)::int,
    case p_key when 'first_contact_hours' then 2 when 'first_connect_days' then 1 when 'status_update_days' then 7
               when 'outcome_days' then 5 when 'proof_days' then 7 when 'duplicate_hours' then 24 end)
    from b2b.partners p where p.id = p_partner_id;
$fn$;

revoke execute on function b2b.partner_hours(bigint), b2b.working_windows(bigint, timestamptz, int), b2b.working_deadline(bigint, timestamptz, int),
                           b2b.working_days_deadline(bigint, timestamptz, int), b2b.working_minutes_between(bigint, timestamptz, timestamptz),
                           b2b.partner_sla(bigint, text)
  from public, anon, authenticated;
grant execute on function b2b.partner_hours(bigint), b2b.working_windows(bigint, timestamptz, int), b2b.working_deadline(bigint, timestamptz, int),
                          b2b.working_days_deadline(bigint, timestamptz, int), b2b.working_minutes_between(bigint, timestamptz, timestamptz),
                          b2b.partner_sla(bigint, text)
  to service_role;
