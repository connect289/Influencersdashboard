-- M17a: lead intake (spec B4, B4.1, B17): tables, settings, and how an intake choice reaches routing.
--   intake_requests     every lead that arrived through the Intake API, Meta Lead Ads or Google lead forms, raw, with its
--                       result; idempotent per source and key
--   lead_forms          per Meta or Google form: which question is which lead field, the consent line, the campaign label
--   imports, import_rows, import_templates   the Excel/CSV import wizard: a job with per-row results and saved mappings
--   intake_directives   what the source decided about routing a lead: route (phone trusted), hold for review, or send to
--                       B2C; read by lead_class, lead_readiness, pool_lead, route_ready_leads and route_decide (m17b)
-- Settings key 'intake' holds the Meta and Google connection (secrets in Vault, only their ids here).

create table if not exists b2b.intake_requests (
  id              bigint generated always as identity primary key,
  source          text not null check (source in ('api', 'meta', 'google', 'manual')),
  idempotency_key text not null,
  api_key_id      bigint,
  form_ref        text,                 -- Meta form id or Google form id
  raw             jsonb not null,
  status          text not null default 'received' check (status in ('received', 'fetching', 'held', 'done', 'error', 'discarded')),
  result          jsonb,
  lead_id         bigint,
  error           text,
  net_request_id  bigint,
  attempts        int not null default 0,
  is_test         boolean not null default false,
  received_at     timestamptz not null default now(),
  done_at         timestamptz,
  unique (source, idempotency_key)
);
create index if not exists intake_requests_recent_idx on b2b.intake_requests (received_at desc);
create index if not exists intake_requests_open_idx on b2b.intake_requests (status) where status in ('received', 'fetching', 'held', 'error');

create table if not exists b2b.lead_forms (
  id            bigint generated always as identity primary key,
  platform      text not null check (platform in ('meta', 'google')),
  form_ref      text not null,
  name          text not null,
  page_ref      text,
  field_map     jsonb not null default '{}',   -- {"question key": "lead field"}
  defaults      jsonb not null default '{}',   -- fixed lead fields for every lead of the form (course, level, mode…)
  campaign      text,
  consent_text  text,
  consent_version text,
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    text,
  unique (platform, form_ref)
);

create table if not exists b2b.import_templates (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  mapping     jsonb not null,                  -- {"file column": "lead field"}
  created_at  timestamptz not null default now(),
  used_at     timestamptz
);

create table if not exists b2b.imports (
  id              bigint generated always as identity primary key,
  file_name       text not null,
  status          text not null default 'staging' check (status in ('staging', 'committing', 'done', 'rolled_back', 'abandoned')),
  mapping         jsonb not null default '{}',
  template_id     bigint references b2b.import_templates (id),
  source_label    text,
  campaign        text,
  consent         jsonb,                       -- {where, when, text}
  routing_choice  text check (routing_choice in ('route', 'hold', 'b2c')),
  b2c_lane        text check (b2c_lane in ('sales', 'nurture')),
  course_choices  jsonb not null default '{}', -- {"course text as written": "catalogue course key" | null (keep as written)}
  total_rows      int not null default 0,
  counts          jsonb not null default '{}',
  created_by      text,
  created_at      timestamptz not null default now(),
  committed_at    timestamptz,
  finished_at     timestamptz,
  rolled_back_at  timestamptz,
  rollback_note   text
);
create index if not exists imports_recent_idx on b2b.imports (id desc);

create table if not exists b2b.import_rows (
  id          bigint generated always as identity primary key,
  import_id   bigint not null references b2b.imports (id),
  row_no      int not null,
  raw         jsonb not null,
  lead        jsonb not null default '{}',      -- mapped standard fields, normalised
  phone       text,
  problems    text[] not null default '{}',
  preview     text check (preview in ('new', 'merge', 'reopen', 'blocked', 'test', 'invalid', 'duplicate_in_file')),
  existing_lead_id bigint,
  status      text not null default 'staged' check (status in ('staged', 'imported', 'skipped', 'error', 'rolled_back')),
  lead_id     bigint,
  action      text,
  error       text,
  done_at     timestamptz,
  unique (import_id, row_no)
);
create index if not exists import_rows_todo_idx on b2b.import_rows (import_id, status, row_no);
create index if not exists import_rows_phone_idx on b2b.import_rows (import_id, phone);

create table if not exists b2b.intake_directives (
  lead_id       bigint primary key,
  source        text not null check (source in ('import', 'manual', 'api')),
  import_id     bigint references b2b.imports (id),
  directive     text not null check (directive in ('route', 'hold', 'b2c')),
  b2c_lane      text check (b2c_lane in ('sales', 'nurture')),
  phone_trusted boolean not null default false,
  created_at    timestamptz not null default now(),
  released_at   timestamptz,
  released_by   text
);
create index if not exists intake_directives_held_idx on b2b.intake_directives (directive) where released_at is null;

do $rls$
declare t text;
begin
  foreach t in array array['intake_requests', 'lead_forms', 'import_templates', 'imports', 'import_rows', 'intake_directives'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

insert into b2b.settings (key, value)
values ('intake', '{"meta": {"api_version": "v21.0"}, "google": {}, "import_max_rows": 50000, "rollback_hours": 24}')
on conflict (key) do nothing;

-- ---------- how a directive changes routing ----------
/* The lead's open intake directive, if any. */
create or replace function b2b.lead_directive(p_lead_id bigint)
returns b2b.intake_directives language sql stable set search_path = '' as $fn$
  select d.* from b2b.intake_directives d where d.lead_id = p_lead_id and d.released_at is null;
$fn$;

/* As in m7a, plus: a phone the source vouches for (an import with a consent basis, a manual entry, an API caller that
   verified it) counts as trusted. */
create or replace function b2b.lead_class(l public.student_leads)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_test boolean := coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number);
  v_chat boolean := b2b.is_chat_lead(l);
  v_status text := upper(coalesce(nullif(trim(l.lead_status), ''), ''));
  v_course text := coalesce(nullif(trim(l.interested_course), ''), nullif(trim(l.field_of_interest), ''));
  v_phone text := case when v_test then null else b2b.phone_problem(l.whatsapp_number) end;
  m text[] := '{}';
begin
  if v_status = 'JUNK' then return jsonb_build_object('class', 'junk', 'reason', 'junk', 'missing', '[]'::jsonb); end if;
  if v_phone is not null then return jsonb_build_object('class', 'junk', 'reason', v_phone, 'missing', '[]'::jsonb); end if;
  if v_status = 'PROGRAM_MISMATCH' or (not v_chat and v_course is not null and not b2b.course_in_catalogue(v_course)) then
    return jsonb_build_object('class', 'mismatch', 'reason', 'program_mismatch', 'missing', '[]'::jsonb);
  end if;

  if v_course is null then m := array_append(m, 'no course'); end if;
  if l.phone_verified_at is null and not (coalesce(l.lead_source, '') in (select jsonb_array_elements_text(coalesce(e -> 'trusted_sources', '[]'))))
     and not exists (select 1 from b2b.intake_directives d where d.lead_id = l.id and d.phone_trusted) then
    m := array_append(m, 'phone not verified');
  end if;
  if v_chat and v_status not in ('HOT', 'WARM', 'COLD') then
    m := array_append(m, case when v_status = '' then 'Witty has not classified the lead' else 'Witty classified it ' || v_status end);
  end if;
  return jsonb_build_object('class', case when cardinality(m) = 0 then 'qualified' else 'unqualified' end,
                            'reason', case when cardinality(m) = 0 then null else 'not_qualified' end, 'missing', to_jsonb(m));
end $fn$;

/* As in m7a, plus: a lead held for review by its import or manual entry waits until the Admin releases or routes it. */
create or replace function b2b.lead_readiness(l public.student_leads)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  m text[] := '{}';
  v_idle int := coalesce((e ->> 'witty_idle_minutes')::int, 30);
  v_class jsonb := b2b.lead_class(l);
begin
  if l.deleted_at is not null or l.merged_into_id is not null then m := array_append(m, 'deleted or merged'); end if;
  if coalesce(l.is_opted_out, false) then m := array_append(m, 'opted out'); end if;
  if l.destination_type is not null then m := array_append(m, 'already routed'); end if;
  if exists (select 1 from b2b.intake_directives d where d.lead_id = l.id and d.directive = 'hold' and d.released_at is null) then
    m := array_append(m, 'held for review');
  end if;
  if b2b.is_chat_lead(l)
     and not (coalesce(l.lead_stage, '') = 'ESCALATION' or coalesce(l.is_bot_paused, false)
              or exists (select 1 from public.touchpoints t where t.lead_id = l.id and t.event_type = 'lead.escalated')
              or coalesce(l.last_agent_message_at, l.last_activity_at, l.created_at) < now() - make_interval(mins => v_idle)) then
    m := array_append(m, 'still chatting with Witty');
  end if;
  return jsonb_build_object('ready', cardinality(m) = 0, 'missing', to_jsonb(m),
                            'is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number),
                            'class', v_class ->> 'class', 'class_reason', v_class ->> 'reason', 'not_qualified', v_class -> 'missing',
                            'paid', b2b.paid_signal(l));
end $fn$;

/* As in m10a, plus the group 'held' (held for review by an import or manual entry) and the outlook 'b2c' for leads an
   import sends to B2C. Fixes m10a reading the paid signal (a reason, e.g. 'source meta_lead_ad') as a boolean, which
   failed for every paid lead in the pool. */
create or replace function b2b.pool_lead(l public.student_leads, p_routing_on boolean)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  r jsonb := b2b.lead_readiness(l);
  d b2b.intake_directives := b2b.lead_directive(l.id);
  v_group text;
begin
  v_group := case
    when (r ->> 'is_test')::boolean then 'test'
    when coalesce(l.is_opted_out, false) then 'opted_out'
    when r -> 'missing' ? 'held for review' then 'held'
    when r -> 'missing' ? 'still chatting with Witty' then 'chatting'
    when l.created_at <= now() - interval '90 days' then 'too_old'
    when not p_routing_on then 'routing_off'
    else 'due' end;
  return jsonb_build_object('group', v_group, 'class', r ->> 'class', 'class_reason', r ->> 'class_reason',
                            'not_qualified', coalesce(r -> 'not_qualified', '[]'), 'paid', (r ->> 'paid') is not null,
                            'import_id', d.import_id,
                            'outlook', case
                              when r ->> 'class' in ('junk', 'mismatch') then 'not_passed'
                              when d.directive = 'b2c' then case when d.b2c_lane = 'nurture' then 'b2c_nurture' else 'b2c_sales' end
                              when (r ->> 'paid') is not null then 'b2c_sales'
                              when r ->> 'class' = 'unqualified' then 'b2c_nurture'
                              else 'partners' end);
end $fn$;

/* As in m7b2; held leads are skipped (lead_readiness says why). Also releases directives of leads that were routed. */
create or replace function b2b.route_ready_leads(p_limit int default 50)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  r record;
  n int := 0;
begin
  perform set_config('b2b.actor', 'engine', true);

  for r in
    insert into b2b.review_flags (lead_id, allocation_id, lead_status, destination_type)
    select l.id, a.id, l.lead_status, a.destination_type
      from public.student_leads l join b2b.allocations a on a.id = l.allocation_id
     where l.destination_type is not null and l.deleted_at is null and upper(coalesce(l.lead_status, '')) in ('JUNK', 'PROGRAM_MISMATCH')
       and a.status in ('queued', 'pushing', 'pushed', 'accepted', 'handed_off') and not a.override and not a.is_test
    on conflict (allocation_id, kind) do nothing
    returning lead_id, allocation_id, lead_status, destination_type
  loop
    perform b2b.log_event('lead.flagged', r.lead_id, r.allocation_id, null, jsonb_build_object('lead_status', r.lead_status, 'destination', r.destination_type));
    if r.destination_type = 'in_house' then
      perform b2b.log_event('b2c.lead_flagged', r.lead_id, r.allocation_id, null,
                            jsonb_build_object('lead_id', r.lead_id, 'classification', r.lead_status, 'allocation_id', r.allocation_id));
    end if;
  end loop;

  if not b2b.is_live('routing') or not coalesce((e ->> 'enabled')::boolean, true) or coalesce((e ->> 'kill_switch')::boolean, false) then
    return 0;
  end if;
  for r in
    select l.id from public.student_leads l
     where l.destination_type is null and l.deleted_at is null and l.merged_into_id is null
       and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
       and l.created_at > now() - interval '90 days'
       and not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null
                         and np.fingerprint = md5(concat_ws('|', upper(coalesce(l.lead_status, '')), coalesce(nullif(l.interested_course, ''), l.field_of_interest, ''), l.whatsapp_number)))
       and not exists (select 1 from b2b.intake_directives d where d.lead_id = l.id and d.directive = 'hold' and d.released_at is null)
     order by l.created_at
     limit 500
  loop
    exit when n >= least(greatest(p_limit, 1), 200);
    begin
      if (b2b.lead_readiness((select x from public.student_leads x where x.id = r.id)) ->> 'ready')::boolean then
        perform b2b.route_decide(r.id, true, null, 'auto');
        n := n + 1;
      end if;
    exception when others then
      perform b2b.log_event('routing.error', r.id, null, null, jsonb_build_object('error', left(sqlerrm, 300), 'code', sqlstate));
    end;
  end loop;
  return n;
end $fn$;

revoke execute on function b2b.lead_directive(bigint), b2b.lead_class(public.student_leads), b2b.lead_readiness(public.student_leads),
                           b2b.pool_lead(public.student_leads, boolean), b2b.route_ready_leads(int)
  from public, anon, authenticated;
grant execute on function b2b.lead_directive(bigint), b2b.lead_class(public.student_leads), b2b.lead_readiness(public.student_leads),
                          b2b.pool_lead(public.student_leads, boolean), b2b.route_ready_leads(int)
  to service_role;
