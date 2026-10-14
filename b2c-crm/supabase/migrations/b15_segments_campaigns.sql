-- B2C CRM b15 (Phase 2): segments and campaigns (B9.1, B9.3). Staging first. Idempotent.
--   segments, segment_members     dynamic (rules in the views' filter language) and static (CSV or a snapshot); live counts, overlap
--   campaigns, campaign_sends     one-off or recurring broadcasts with a send window, throttling and an A/B test; results
--   campaign_tick()               every minute: starts due campaigns, sends within the window and the throttle, picks the A/B winner

create table if not exists b2c.segments (
  id bigint generated always as identity primary key,
  name text not null,
  description text,
  kind text not null default 'dynamic' check (kind in ('dynamic', 'static')),
  filters jsonb not null default '{}'::jsonb,
  created_by uuid,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists b2c.segment_members (
  segment_id bigint not null references b2c.segments (id),
  lead_id bigint not null,
  added_at timestamptz not null default now(),
  removed_at timestamptz,
  primary key (segment_id, lead_id)
);

create table if not exists b2c.campaigns (
  id bigint generated always as identity primary key,
  name text not null,
  channel text not null check (channel in ('whatsapp', 'email')),
  segment_id bigint references b2c.segments (id),
  template_id bigint not null,               -- wa_templates.id or email_templates.id by channel
  template_b_id bigint,                      -- A/B: the other template
  ab_pct int not null default 0 check (ab_pct between 0 and 50),  -- share of the audience in the test (split evenly)
  schedule_at timestamptz,
  window_start time,                         -- IST; default the messaging window
  window_end time,
  throttle_per_min int not null default 60 check (throttle_per_min between 1 and 1000),
  recurring text check (recurring in ('daily', 'weekly', 'monthly')),
  allow_active_sales boolean not null default false,
  test_only boolean not null default false,  -- test mode: only test leads, nothing reaches a student
  status text not null default 'draft' check (status in ('draft', 'scheduled', 'running', 'paused', 'done', 'cancelled')),
  run_no int not null default 0,
  winner text check (winner in ('a', 'b')),
  started_at timestamptz,
  finished_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists b2c.campaign_sends (
  id bigint generated always as identity primary key,
  campaign_id bigint not null references b2c.campaigns (id),
  run_no int not null default 1,
  lead_id bigint not null,
  variant text check (variant in ('a', 'b')),
  status text not null default 'pending' check (status in ('pending', 'held', 'queued', 'blocked', 'skipped')),
  reason text,
  not_before timestamptz not null default now(),
  wa_message_id bigint,
  email_id bigint,
  created_at timestamptz not null default now(),
  done_at timestamptz,
  unique (campaign_id, run_no, lead_id)
);
create index if not exists campaign_sends_pending on b2c.campaign_sends (campaign_id, status, not_before) where status in ('pending', 'held');

-- ---------- segments ----------
/* The fields a segment may use: everything the lead list filters on. */
create or replace function b2c.segment_fields() returns text[] language sql immutable set search_path = '' as $f$
  select array['lead_id','name','phone','email','city','state','language','course','specialization','university','programme_level','study_mode',
    'qualification','source','campaign','lead_status','partner_consent_state','marketing_consent','opted_out','lane','status','handoff_reason','cause',
    'partner_bar_reason','owner_id','owner_name','assigned_at','stage_id','stage','canonical_stage','sub_stage','stage_changed_at','hot','temperature','score',
    'next_task_due_at','first_contacted_at','last_contacted_at','contact_attempts','last_activity_at','sla_due_at','sla_met_at','sla_breached_at',
    'pool_entered_at','pool_reason','journey','lost_by','reengaged_at','flagged','reenquired_at','tags','is_test','handed_off_at','updated_at','closed_at']
$f$;

create or replace function b2c.filters_where(f jsonb) returns text language plpgsql stable set search_path = '' as $f$
declare w text := 'true'; c jsonb; v_any text;
begin
  for c in select * from jsonb_array_elements(coalesce(f -> 'all', '[]')) loop
    w := w || ' and ' || b2c.filter_sql(c, b2c.segment_fields());
  end loop;
  if jsonb_array_length(coalesce(f -> 'any', '[]')) > 0 then
    select string_agg(b2c.filter_sql(x, b2c.segment_fields()), ' or ') into v_any from jsonb_array_elements(f -> 'any') x;
    w := w || ' and (' || v_any || ')';
  end if;
  return w;
end $f$;

/* The leads of a segment (or of a filter not yet saved). Test leads only in test mode, never otherwise. */
create or replace function b2c.segment_leads(p_segment bigint, p_filters jsonb default null, p_test boolean default false) returns setof bigint
language plpgsql stable security definer set search_path = '' as $f$
declare g b2c.segments;
begin
  if p_segment is not null then select * into g from b2c.segments where id = p_segment; end if;
  if g.kind = 'static' then
    return query select m.lead_id from b2c.segment_members m join b2c.leads_state s on s.lead_id = m.lead_id
                  where m.segment_id = g.id and m.removed_at is null and s.deleted_at is null and s.is_test = p_test;
  else
    return query execute format('select v.lead_id from b2c.leads_v v where v.deleted_at is null and v.is_test = %L and %s',
                                p_test, b2c.filters_where(coalesce(p_filters, g.filters, '{}')));
  end if;
end $f$;

/* Live count before saving (B9.1): how many, and how many each channel may reach today. */
create or replace function b2c.segment_count(p_segment bigint default null, p_filters jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('marketing');
  return (select jsonb_build_object('leads', count(*),
            'whatsapp_consent', count(*) filter (where b2c.has_marketing_consent(l, 'whatsapp')),
            'email_consent', count(*) filter (where b2c.has_marketing_consent(l, 'email')),
            'opted_out', count(*) filter (where b2c.may_message(l) = 'opted out'),
            'in_active_sales', count(*) filter (where exists (select 1 from b2c.leads_state s where s.lead_id = l and s.status = 'active' and s.owner_id is not null)))
            from b2c.segment_leads(p_segment, p_filters) l);
end $f$;

create or replace function b2c.segment_overlap(p_a bigint, p_b bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('marketing');
  return (with a as (select * from b2c.segment_leads(p_a) x), b as (select * from b2c.segment_leads(p_b) y)
          select jsonb_build_object('a', (select count(*) from a), 'b', (select count(*) from b),
                                    'both', (select count(*) from a join b on a.x = b.y)));
end $f$;

create or replace function b2c.segment_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing'); v bigint := nullif(p ->> 'id', '')::bigint;
begin
  if v is null and coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the segment'; end if;
  if p ? 'filters' then perform b2c.filters_where(p -> 'filters'); end if;   -- refuses an unknown field
  if v is null then
    insert into b2c.segments (name, description, kind, filters, created_by)
    values (trim(p ->> 'name'), p ->> 'description', coalesce(p ->> 'kind', 'dynamic'), coalesce(p -> 'filters', '{}'), me) returning id into v;
  else
    update b2c.segments set name = coalesce(nullif(trim(p ->> 'name'), ''), name), description = case when p ? 'description' then p ->> 'description' else description end,
           filters = coalesce(p -> 'filters', filters),
           archived_at = case when p ? 'archived' then case when (p ->> 'archived')::boolean then coalesce(archived_at, now()) end else archived_at end,
           updated_at = now()
     where id = v;
    if not found then raise exception 'unknown segment'; end if;
  end if;
  return v;
end $f$;

/* Static list from a filter snapshot or from phone numbers (a CSV). Returns how many leads are now in it. */
create or replace function b2c.segment_add(p_segment bigint, p_leads bigint[] default null, p_phones text[] default null, p_filters jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare n_before int; n_after int; v_unknown int := 0;
begin
  perform b2c.require('marketing');
  if (select kind from b2c.segments where id = p_segment) <> 'static' then raise exception 'only a static list takes members'; end if;
  select count(*) into n_before from b2c.segment_members where segment_id = p_segment and removed_at is null;
  insert into b2c.segment_members (segment_id, lead_id)
  select p_segment, l from (
    select unnest(coalesce(p_leads, '{}')) l
    union select c.lead_id from b2c.lead_contacts c where c.kind = 'phone' and c.removed_at is null and c.value_norm = any (array(select b2c.norm_phone(x) from unnest(coalesce(p_phones, '{}')) x))
    union select x from b2c.segment_leads(null, p_filters) x where p_filters is not null) q
   where exists (select 1 from b2c.leads_state s where s.lead_id = q.l)
  on conflict (segment_id, lead_id) do update set removed_at = null, added_at = now();
  if p_phones is not null then
    select count(*) into v_unknown from unnest(p_phones) x
     where not exists (select 1 from b2c.lead_contacts c where c.kind = 'phone' and c.removed_at is null and c.value_norm = b2c.norm_phone(x));
  end if;
  select count(*) into n_after from b2c.segment_members where segment_id = p_segment and removed_at is null;
  return jsonb_build_object('added', n_after - n_before, 'total', n_after, 'not_found', v_unknown);
end $f$;

create or replace function b2c.segment_remove(p_segment bigint, p_leads bigint[]) returns int language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  perform b2c.require('marketing');
  update b2c.segment_members set removed_at = now() where segment_id = p_segment and lead_id = any (p_leads) and removed_at is null;
  get diagnostics n = row_count;
  return n;
end $f$;

-- ---------- campaigns ----------
create or replace function b2c.campaign_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing'); v bigint := nullif(p ->> 'id', '')::bigint; c b2c.campaigns; v_ch text;
begin
  if v is not null then
    select * into c from b2c.campaigns where id = v;
    if c.id is null then raise exception 'unknown campaign'; end if;
    if c.status not in ('draft', 'paused', 'scheduled') then raise exception 'a running or finished campaign cannot change; pause it or clone it'; end if;
  end if;
  v_ch := coalesce(p ->> 'channel', c.channel);
  if v_ch not in ('whatsapp', 'email') then raise exception 'choose WhatsApp or email'; end if;
  if coalesce(p ->> 'allow_active_sales', 'false')::boolean and b2c.my_role() <> 'admin' then raise exception 'only the Admin lets a campaign reach leads in active sales'; end if;
  if v_ch = 'whatsapp' and not exists (select 1 from b2c.wa_templates t where t.id = coalesce((p ->> 'template_id')::bigint, c.template_id) and t.audience = 'marketing' and t.archived_at is null) then
    raise exception 'choose a marketing WhatsApp template';
  end if;
  if v_ch = 'email' and not exists (select 1 from b2c.email_templates t where t.id = coalesce((p ->> 'template_id')::bigint, c.template_id) and t.archived_at is null) then
    raise exception 'choose a marketing email template';
  end if;
  if v is null then
    insert into b2c.campaigns (name, channel, segment_id, template_id, template_b_id, ab_pct, schedule_at, window_start, window_end, throttle_per_min, recurring,
                               allow_active_sales, test_only, created_by)
    values (coalesce(nullif(trim(p ->> 'name'), ''), 'Campaign'), v_ch, (p ->> 'segment_id')::bigint, (p ->> 'template_id')::bigint, (p ->> 'template_b_id')::bigint,
            coalesce((p ->> 'ab_pct')::int, 0), (p ->> 'schedule_at')::timestamptz, (p ->> 'window_start')::time, (p ->> 'window_end')::time,
            coalesce((p ->> 'throttle_per_min')::int, 60), p ->> 'recurring', coalesce((p ->> 'allow_active_sales')::boolean, false),
            coalesce((p ->> 'test_only')::boolean, false), me)
    returning id into v;
  else
    update b2c.campaigns set name = coalesce(nullif(trim(p ->> 'name'), ''), name), segment_id = coalesce((p ->> 'segment_id')::bigint, segment_id),
           template_id = coalesce((p ->> 'template_id')::bigint, template_id), template_b_id = case when p ? 'template_b_id' then (p ->> 'template_b_id')::bigint else template_b_id end,
           ab_pct = coalesce((p ->> 'ab_pct')::int, ab_pct), schedule_at = case when p ? 'schedule_at' then (p ->> 'schedule_at')::timestamptz else schedule_at end,
           window_start = case when p ? 'window_start' then (p ->> 'window_start')::time else window_start end,
           window_end = case when p ? 'window_end' then (p ->> 'window_end')::time else window_end end,
           throttle_per_min = coalesce((p ->> 'throttle_per_min')::int, throttle_per_min), recurring = case when p ? 'recurring' then p ->> 'recurring' else recurring end,
           allow_active_sales = coalesce((p ->> 'allow_active_sales')::boolean, allow_active_sales), test_only = coalesce((p ->> 'test_only')::boolean, test_only),
           updated_at = now()
     where id = v;
  end if;
  if (select segment_id from b2c.campaigns where id = v) is null then raise exception 'choose a segment'; end if;
  return v;
end $f$;

/* schedule (now when no time is set), pause, resume, cancel. */
create or replace function b2c.campaign_set(p_id bigint, p_action text) returns text language plpgsql security definer set search_path = '' as $f$
declare c b2c.campaigns;
begin
  perform b2c.require('marketing');
  select * into c from b2c.campaigns where id = p_id for update;
  if c.id is null then raise exception 'unknown campaign'; end if;
  if p_action = 'schedule' and c.status in ('draft', 'paused') then
    update b2c.campaigns set status = case when c.started_at is not null and c.status = 'paused' then 'running' else 'scheduled' end,
           schedule_at = coalesce(c.schedule_at, now()), updated_at = now() where id = p_id;
  elsif p_action = 'pause' and c.status in ('scheduled', 'running') then
    update b2c.campaigns set status = 'paused', updated_at = now() where id = p_id;
  elsif p_action = 'cancel' and c.status not in ('done', 'cancelled') then
    update b2c.campaigns set status = 'cancelled', finished_at = now(), updated_at = now() where id = p_id;
    update b2c.campaign_sends set status = 'skipped', reason = 'campaign cancelled', done_at = now() where campaign_id = p_id and status in ('pending', 'held');
  else
    raise exception 'cannot % a % campaign', p_action, c.status;
  end if;
  perform b2c.log('campaign.' || p_action, null, jsonb_build_object('campaign_id', p_id));
  return (select status from b2c.campaigns where id = p_id);
end $f$;

create or replace function b2c.campaign_clone(p_id bigint) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing'); v bigint;
begin
  insert into b2c.campaigns (name, channel, segment_id, template_id, template_b_id, ab_pct, window_start, window_end, throttle_per_min, recurring, allow_active_sales, test_only, created_by)
  select name || ' (copy)', channel, segment_id, template_id, template_b_id, ab_pct, window_start, window_end, throttle_per_min, recurring,
         allow_active_sales and b2c.my_role() = 'admin', test_only, me from b2c.campaigns where id = p_id
  returning id into v;
  if v is null then raise exception 'unknown campaign'; end if;
  return v;
end $f$;

/* Every minute (service): start due campaigns, send within the window and the throttle, decide A/B, finish. */
create or replace function b2c.campaign_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare c b2c.campaigns; s record; r jsonb; v_sent int := 0; v_blocked int := 0; v_now time := (now() at time zone 'Asia/Kolkata')::time; v_n int; v_total int;
        v_tpl bigint; v_rate_a numeric; v_rate_b numeric; v_wait int := coalesce((b2c.setting('nurture') ->> 'ab_wait_hours')::int, 4);
begin
  -- start: materialise the audience once per run
  for c in select * from b2c.campaigns where status = 'scheduled' and schedule_at <= now() for update skip locked loop
    update b2c.campaigns set status = 'running', started_at = now(), run_no = run_no + 1, winner = null, updated_at = now() where id = c.id returning * into c;
    insert into b2c.campaign_sends (campaign_id, run_no, lead_id, variant, status)
    select c.id, c.run_no, l, case when c.template_b_id is null or c.ab_pct = 0 then 'a' when rn <= cnt * c.ab_pct / 100.0 then case when rn % 2 = 0 then 'a' else 'b' end end,
           case when c.template_b_id is null or c.ab_pct = 0 or rn <= cnt * c.ab_pct / 100.0 then 'pending' else 'held' end
      from (select l, row_number() over (order by random()) rn, count(*) over () cnt from b2c.segment_leads(c.segment_id, null, c.test_only) l) q
    on conflict do nothing;
  end loop;

  -- send, within each campaign's window and throttle
  for c in select * from b2c.campaigns where status = 'running' order by id loop
    continue when c.window_start is not null and (v_now < c.window_start or v_now >= coalesce(c.window_end, '20:00'));
    continue when not b2c.in_send_window();
    v_n := 0;
    for s in select * from b2c.campaign_sends where campaign_id = c.id and run_no = c.run_no and status = 'pending' and not_before <= now()
              order by id limit c.throttle_per_min for update skip locked loop
      if c.channel = 'email' and b2c.email_allowance_left() <= 0 then exit; end if;
      v_tpl := case when s.variant = 'b' then c.template_b_id else c.template_id end;
      r := case c.channel when 'whatsapp' then b2c.queue_marketing_wa(s.lead_id, v_tpl, 'campaign', jsonb_build_object('campaign_id', c.id), c.allow_active_sales)
                          else b2c.queue_marketing_email(s.lead_id, v_tpl, 'campaign', jsonb_build_object('campaign_id', c.id), c.allow_active_sales) end;
      if r ? 'blocked' then
        if r ->> 'blocked' = 'wait: in a Witty chat' then
          update b2c.campaign_sends set not_before = now() + interval '30 minutes', reason = r ->> 'blocked' where id = s.id;
        else
          update b2c.campaign_sends set status = case when r ->> 'blocked' like 'wait:%' then 'skipped' else 'blocked' end, reason = r ->> 'blocked', done_at = now() where id = s.id;
          v_blocked := v_blocked + 1;
        end if;
      else
        update b2c.campaign_sends set status = 'queued', wa_message_id = (r ->> 'message_id')::bigint, email_id = (r ->> 'email_id')::bigint, done_at = now() where id = s.id;
        v_sent := v_sent + 1; v_n := v_n + 1;
      end if;
    end loop;

    -- A/B: once the sample is out and the wait has passed, the better variant goes to everyone held back
    if c.template_b_id is not null and c.ab_pct > 0 and c.winner is null
       and not exists (select 1 from b2c.campaign_sends where campaign_id = c.id and run_no = c.run_no and status = 'pending')
       and c.started_at <= now() - make_interval(hours => v_wait) then
      if c.channel = 'whatsapp' then
        select avg(case when m.status = 'read' or exists (select 1 from b2c.wa_messages i where i.lead_id = x.lead_id and i.direction = 'in' and i.created_at > m.created_at) then 1 else 0 end) filter (where x.variant = 'a'),
               avg(case when m.status = 'read' or exists (select 1 from b2c.wa_messages i where i.lead_id = x.lead_id and i.direction = 'in' and i.created_at > m.created_at) then 1 else 0 end) filter (where x.variant = 'b')
          into v_rate_a, v_rate_b
          from b2c.campaign_sends x join b2c.wa_messages m on m.id = x.wa_message_id where x.campaign_id = c.id and x.run_no = c.run_no;
      else
        select avg(case when e.opened_at is not null or e.clicked_at is not null then 1 else 0 end) filter (where x.variant = 'a'),
               avg(case when e.opened_at is not null or e.clicked_at is not null then 1 else 0 end) filter (where x.variant = 'b')
          into v_rate_a, v_rate_b
          from b2c.campaign_sends x join b2c.emails e on e.id = x.email_id where x.campaign_id = c.id and x.run_no = c.run_no;
      end if;
      update b2c.campaigns set winner = case when coalesce(v_rate_b, 0) > coalesce(v_rate_a, 0) then 'b' else 'a' end where id = c.id returning * into c;
      update b2c.campaign_sends set variant = c.winner, status = 'pending' where campaign_id = c.id and run_no = c.run_no and status = 'held';
    end if;

    -- finished?
    if not exists (select 1 from b2c.campaign_sends where campaign_id = c.id and run_no = c.run_no and status in ('pending', 'held')) then
      if c.recurring is null then
        update b2c.campaigns set status = 'done', finished_at = now(), updated_at = now() where id = c.id;
      else
        update b2c.campaigns set status = 'scheduled', finished_at = now(), updated_at = now(),
               schedule_at = c.schedule_at + case c.recurring when 'daily' then interval '1 day' when 'weekly' then interval '7 days' else interval '1 month' end
         where id = c.id;
      end if;
    end if;
  end loop;
  return jsonb_build_object('sent', v_sent, 'blocked', v_blocked);
end $f$;

/* Results (B9.3): sent, delivered, read or opened, clicked, replied by class, opted out, bounced, re-engaged, enrolled, cost. */
create or replace function b2c.campaign_stats(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare c b2c.campaigns;
begin
  perform b2c.require('marketing');
  select * into c from b2c.campaigns where id = p_id;
  if c.id is null then raise exception 'unknown campaign'; end if;
  return (select jsonb_build_object(
    'audience', count(*), 'queued', count(*) filter (where x.status = 'queued'), 'pending', count(*) filter (where x.status in ('pending', 'held')),
    'blocked', count(*) filter (where x.status in ('blocked', 'skipped')),
    'blocked_by', (select coalesce(jsonb_object_agg(reason, n), '{}') from (select reason, count(*) n from b2c.campaign_sends where campaign_id = p_id and status in ('blocked', 'skipped') group by reason) b),
    'by_variant', (select coalesce(jsonb_object_agg(variant, n), '{}') from (select variant, count(*) n from b2c.campaign_sends where campaign_id = p_id and status = 'queued' and variant is not null group by variant) v),
    'delivered', count(*) filter (where m.status in ('delivered', 'read')), 'read', count(*) filter (where m.status = 'read'),
    'test_mode', count(*) filter (where m.status = 'dry_run' or e.status = 'dry_run'),
    'opened', count(*) filter (where e.opened_at is not null), 'clicked', count(*) filter (where e.clicked_at is not null),
    'bounced', count(*) filter (where e.bounced_at is not null),
    'replied', count(*) filter (where exists (select 1 from b2c.wa_messages i where i.lead_id = x.lead_id and i.direction = 'in' and i.created_at > x.done_at)),
    'opted_out', count(*) filter (where exists (select 1 from b2c.events ev where ev.lead_id = x.lead_id and ev.type = 'lead.opted_out' and ev.at > x.done_at)),
    're_engaged', count(*) filter (where exists (select 1 from b2c.leads_state ls where ls.lead_id = x.lead_id and ls.reengaged_at > x.done_at)),
    'enrolled', count(*) filter (where exists (select 1 from b2c.enrollments en where en.lead_id = x.lead_id and en.created_at > x.done_at)),
    'cost', coalesce(sum(m.cost_estimate) filter (where m.status in ('sent', 'delivered', 'read')), 0),
    'winner', c.winner)
    from b2c.campaign_sends x left join b2c.wa_messages m on m.id = x.wa_message_id left join b2c.emails e on e.id = x.email_id
   where x.campaign_id = p_id);
end $f$;

alter table b2c.segments enable row level security;
alter table b2c.segment_members enable row level security;
alter table b2c.campaigns enable row level security;
alter table b2c.campaign_sends enable row level security;
grant select on b2c.segments, b2c.campaigns to authenticated;
do $p$
begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'segments' and policyname = 'marketing read') then
    create policy "marketing read" on b2c.segments for select to authenticated using ((select b2c.can('marketing')));
    create policy "marketing read" on b2c.campaigns for select to authenticated using ((select b2c.can('marketing')));
  end if;
end $p$;
grant execute on function b2c.segment_count(bigint, jsonb), b2c.segment_overlap(bigint, bigint), b2c.segment_save(jsonb), b2c.segment_add(bigint, bigint[], text[], jsonb),
  b2c.segment_remove(bigint, bigint[]), b2c.campaign_save(jsonb), b2c.campaign_set(bigint, text), b2c.campaign_clone(bigint), b2c.campaign_stats(bigint) to authenticated;
revoke execute on function b2c.segment_leads(bigint, jsonb, boolean), b2c.campaign_tick(), b2c.filters_where(jsonb) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
