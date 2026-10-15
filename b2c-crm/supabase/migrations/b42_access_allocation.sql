-- B2C CRM b42: completing access, stages and allocation (docs/completion-gaps.md, section E, plus D4 and D13). Staging first. Idempotent.
--   sales head          sees and works their own team's leads; approves counsellors' stage overrides (B3.1)
--   stages editor       the Admin renames stages and edits sub-stages, with a change history (B5.1, B15)
--   assignment message  by email when WhatsApp cannot reach the student or fails; Witty's idle wait checked at send time (B7.6)
--   on-call             a hot lead outside hours goes to the on-call counsellor, whatever the rule's fallbacks (B7.1, B7.3)
--   queues              unassigned, waiting for hours and manual queues apart; the manual queue waits for a person (B7.3, B7.4)
--   calendar            breaks and lunch (hot leads only then), holiday import, a week view with "nobody on duty" (B7.1, B7.4)
--   capacity            alerts to the Admin at 90% of a cap and at the hiring trigger; today's intake (B7.5)
--   Teams               every Workspace account not yet added; invitations that expire after 7 days (B3.2)
--   sessions            trusted devices for 7 days, a list of signed-in sessions and devices, remote sign-out (B3.2)
--   rules               simulation can include disabled or future rules (B7.4)
--   student_leads       team_id and expected / realised net revenue through the B2B write API, once the B2B CRM accepts them (B3.3)
--   view as Sales       the Admin sees a chosen counsellor's list, logged (B3.1, B15)

-- ---------- the sales head's team (E15) ----------
/* True when the lead's owner is in the sales head's team (a sales head without a team sees everyone). Others: true. */
create or replace function b2c.in_my_team(p_owner uuid) returns boolean language sql stable security definer set search_path = '' as $f$
  select case when b2c.my_role() <> 'sales_head' then true
              when (select team from b2c.users where user_id = b2c.uid()) is null then true
              when p_owner is null then false
              else (select u.team from b2c.users u where u.user_id = p_owner) is not distinct from (select team from b2c.users where user_id = b2c.uid()) end
$f$;

create or replace function b2c.can_see(p_lead bigint) returns boolean language sql stable security definer set search_path = '' as $f$
  select case b2c.my_role()
    when 'admin' then true when 'marketing' then true
    when 'sales_head' then b2c.in_my_team((select s.owner_id from b2c.leads_state s where s.lead_id = p_lead))
    when 'counsellor' then exists (select 1 from b2c.leads_state s where s.lead_id = p_lead and s.owner_id = b2c.uid() and s.deleted_at is null)
                        or exists (select 1 from b2c.tasks t where t.lead_id = p_lead and t.owner_id = b2c.uid() and t.kind = 'qualify' and t.status = 'open')
                        or (b2c.replies_delegate(b2c.uid()) and exists (select 1 from b2c.replies x where x.lead_id = p_lead and x.status in ('inbox', 'pending_ai')))
    else false end
$f$;

create or replace function b2c.require_lead(p_lead bigint) returns uuid language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads');
begin
  if b2c.my_role() = 'admin' then return me; end if;
  if b2c.my_role() = 'sales_head' then
    if b2c.in_my_team((select owner_id from b2c.leads_state where lead_id = p_lead)) then return me; end if;
    raise exception 'not your team''s lead' using errcode = '42501';
  end if;
  if not exists (select 1 from b2c.leads_state s where s.lead_id = p_lead and s.owner_id = me and s.deleted_at is null) then
    raise exception 'not your lead' using errcode = '42501';
  end if;
  return me;
end $f$;

create or replace function b2c.lead_scope_sql(p_user uuid, p_role text) returns text language plpgsql stable security definer set search_path = '' as $f$
declare v_team text;
begin
  if p_role = 'counsellor' then return format('owner_id = %L', p_user); end if;
  if p_role = 'sales_head' then
    select team into v_team from b2c.users where user_id = p_user;
    if v_team is not null then
      return format('owner_id in (select tu.user_id from b2c.users tu where tu.team = %L)', v_team);
    end if;
  end if;
  return 'true';
end $f$;

/* Moving a lead back a stage needs the sales head or the Admin: a counsellor asks, they approve (B3.1, B5). */
create table if not exists b2c.stage_requests (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  requested_by uuid not null,
  from_stage smallint,
  to_stage smallint not null,
  sub_stage text not null,
  comment text not null,
  next_due timestamptz,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'withdrawn')),
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);
create index if not exists stage_requests_pending on b2c.stage_requests (status, created_at) where status = 'pending';
alter table b2c.stage_requests enable row level security;

create or replace function b2c.stage_override_request(p_lead bigint, p_stage smallint, p_sub text, p_comment text, p_next_due timestamptz default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); s b2c.leads_state; v bigint; v_team text; r record;
begin
  select * into s from b2c.leads_state where lead_id = p_lead;
  if length(coalesce(trim(p_comment), '')) < 3 then raise exception 'give a reason for moving back'; end if;
  if not exists (select 1 from b2c.sub_stages where stage_id = p_stage and name = p_sub and active) then raise exception 'choose a sub-stage'; end if;
  if not exists (select 1 from b2c.stages a join b2c.stages b on b.id = s.stage_id where a.id = p_stage and a.rank < b.rank and not a.reachable_from_any) then
    raise exception 'only a move back needs approval: change the stage yourself';
  end if;
  if p_stage not in (9, 10) and p_next_due is null then raise exception 'set the next follow-up'; end if;
  if exists (select 1 from b2c.stage_requests where lead_id = p_lead and status = 'pending') then raise exception 'a request for this lead is already waiting'; end if;
  insert into b2c.stage_requests (lead_id, requested_by, from_stage, to_stage, sub_stage, comment, next_due)
  values (p_lead, me, s.stage_id, p_stage, p_sub, trim(p_comment), p_next_due) returning id into v;
  select team into v_team from b2c.users where user_id = me;
  for r in select user_id from b2c.users where role = 'sales_head' and is_active and (team is null or team is not distinct from v_team) loop
    perform b2c.notify(r.user_id, 'stage_request', 'Stage change to approve', trim(p_comment), '/s/leads/' || p_lead, p_lead, 'stagereq:' || v);
  end loop;
  if not found then
    perform b2c.notify_admins('stage_request', 'Stage change to approve', trim(p_comment), '/w/leads/' || p_lead, p_lead, 'stagereq:' || v, false);
  end if;
  insert into b2c.activities (lead_id, kind, body, actor_id) values (p_lead, 'stage', 'Asked to move back: ' || trim(p_comment), me);
  return v;
end $f$;

create or replace function b2c.stage_override_decide(p_request bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('stage_override'); q b2c.stage_requests; j jsonb;
begin
  select * into q from b2c.stage_requests where id = p_request for update;
  if q.id is null or q.status <> 'pending' then raise exception 'this request was already decided'; end if;
  perform b2c.require_lead(q.lead_id);
  if p_approve then
    j := b2c.set_stage(q.lead_id, q.to_stage, q.sub_stage, q.comment || coalesce(' (approved: ' || nullif(trim(p_note), '') || ')', ' (approved)'), q.next_due);
  end if;
  update b2c.stage_requests set status = case when p_approve then 'approved' else 'declined' end, decided_by = me, decided_at = now(), decision_note = left(p_note, 300)
   where id = p_request;
  perform b2c.notify(q.requested_by, 'stage_request', case when p_approve then 'Stage change approved' else 'Stage change declined' end,
                     p_note, '/s/leads/' || q.lead_id, q.lead_id, 'stagedec:' || p_request);
  return coalesce(j, '{}'::jsonb) || jsonb_build_object('approved', p_approve);
end $f$;

create or replace function b2c.stage_requests_list() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_role text := b2c.my_role();
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'lead_id', q.lead_id, 'name', v.name, 'from', fs.name, 'to', ts.name, 'sub_stage', q.sub_stage,
            'comment', q.comment, 'by', u.full_name, 'created_at', q.created_at, 'mine', q.requested_by = me) order by q.created_at), '[]')
    from b2c.stage_requests q join b2c.leads_v v on v.lead_id = q.lead_id
    left join b2c.stages fs on fs.id = q.from_stage left join b2c.stages ts on ts.id = q.to_stage left join b2c.users u on u.user_id = q.requested_by
   where q.status = 'pending' and (q.requested_by = me or (v_role in ('admin', 'sales_head') and b2c.in_my_team(v.owner_id))));
end $f$;

-- ---------- stages and sub-stages (E2, D4) ----------
/* The Admin renames a stage, changes what it requires, or switches it off. Ids and the canonical stage never change
   (they are the contract with the B2B CRM). Each change is kept in the audit log. */
create or replace function b2c.stage_save(p jsonb) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); st b2c.stages; v_req jsonb := p -> 'required';
begin
  select * into st from b2c.stages where id = (p ->> 'id')::smallint for update;
  if st.id is null then raise exception 'unknown stage'; end if;
  if p ? 'name' and coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the stage'; end if;
  if v_req is not null and (jsonb_typeof(v_req) <> 'array' or exists (select 1 from jsonb_array_elements_text(v_req) x
        where x not in ('call_attempt', 'contact', 'profile', 'followup', 'programme_shared', 'application', 'checklist', 'enrollment', 'comment'))) then
    raise exception 'unknown requirement';
  end if;
  if p ? 'active' and not (p ->> 'active')::boolean and (st.id in (1, 9, 10) or exists (select 1 from b2c.leads_state s where s.stage_id = st.id and s.status = 'active')) then
    raise exception 'this stage is in use: move its leads first';
  end if;
  update b2c.stages set name = coalesce(nullif(trim(p ->> 'name'), ''), name), required = coalesce(v_req, required),
         reachable_from_any = coalesce((p ->> 'reachable_from_any')::boolean, reachable_from_any), active = coalesce((p ->> 'active')::boolean, active)
   where id = st.id;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'stage_changed', jsonb_build_object('stage', st.id, 'old', to_jsonb(st), 'new', p, 'reason', p ->> 'reason'));
end $f$;

create or replace function b2c.sub_stage_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v bigint := nullif(p ->> 'id', '')::bigint; old b2c.sub_stages;
begin
  if v is null then
    if not exists (select 1 from b2c.stages where id = (p ->> 'stage_id')::smallint) then raise exception 'unknown stage'; end if;
    if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the sub-stage'; end if;
    if exists (select 1 from b2c.sub_stages where stage_id = (p ->> 'stage_id')::smallint and lower(name) = lower(trim(p ->> 'name'))) then raise exception 'that sub-stage exists'; end if;
    insert into b2c.sub_stages (stage_id, name, rank, returns_to_pool, journey, first_message_days, comment_required, active)
    values ((p ->> 'stage_id')::smallint, trim(p ->> 'name'),
            coalesce((p ->> 'rank')::int, (select coalesce(max(rank), 0) + 10 from b2c.sub_stages where stage_id = (p ->> 'stage_id')::smallint)),
            coalesce((p ->> 'returns_to_pool')::boolean, false), nullif(p ->> 'journey', ''), nullif(p ->> 'first_message_days', '')::int,
            coalesce((p ->> 'comment_required')::boolean, false), true)
    returning id into v;
  else
    select * into old from b2c.sub_stages where id = v for update;
    if old.id is null then raise exception 'unknown sub-stage'; end if;
    if p ? 'name' and trim(p ->> 'name') <> old.name and exists (select 1 from b2c.leads_state s where s.stage_id = old.stage_id and s.sub_stage = old.name and s.status = 'active') then
      raise exception 'leads are in "%": add a new sub-stage and switch this one off instead', old.name;
    end if;
    update b2c.sub_stages set name = coalesce(nullif(trim(p ->> 'name'), ''), name), rank = coalesce((p ->> 'rank')::int, rank),
           returns_to_pool = coalesce((p ->> 'returns_to_pool')::boolean, returns_to_pool),
           journey = case when p ? 'journey' then nullif(p ->> 'journey', '') else journey end,
           first_message_days = case when p ? 'first_message_days' then nullif(p ->> 'first_message_days', '')::int else first_message_days end,
           comment_required = coalesce((p ->> 'comment_required')::boolean, comment_required), active = coalesce((p ->> 'active')::boolean, active)
     where id = v;
  end if;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'sub_stage_changed', jsonb_build_object('sub_stage', v, 'old', to_jsonb(old), 'new', p));
  return v;
end $f$;

create or replace function b2c.stages_admin() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return jsonb_build_object(
    'stages', (select coalesce(jsonb_agg(to_jsonb(st) || jsonb_build_object('leads', (select count(*) from b2c.leads_state s where s.stage_id = st.id and s.status = 'active'),
                 'sub_stages', (select coalesce(jsonb_agg(to_jsonb(ss) || jsonb_build_object('leads', (select count(*) from b2c.leads_state s where s.stage_id = st.id and s.sub_stage = ss.name and s.status = 'active')) order by ss.rank), '[]')
                                  from b2c.sub_stages ss where ss.stage_id = st.id)) order by st.rank), '[]') from b2c.stages st),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'by', u.full_name, 'action', a.action, 'detail', a.detail) order by a.at desc), '[]')
                  from (select * from b2c.audit_log where action in ('stage_changed', 'sub_stage_changed') order by at desc limit 100) a left join b2c.users u on u.user_id = a.actor_id));
end $f$;

-- ---------- queues (E6) ----------
/* Leads without a counsellor, apart: unassigned (nobody eligible), waiting for working hours, the manual queue. */
create or replace function b2c.queues() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not (b2c.can('read_all') or b2c.can('reassign')) then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select jsonb_build_object(
      'unassigned', coalesce(jsonb_agg(x) filter (where x ->> 'queue' = 'unassigned'), '[]'),
      'waiting_hours', coalesce(jsonb_agg(x) filter (where x ->> 'queue' = 'waiting_hours'), '[]'),
      'manual', coalesce(jsonb_agg(x) filter (where x ->> 'queue' = 'manual'), '[]'))
    from (select jsonb_build_object('lead_id', s.lead_id, 'name', v.name, 'course', v.course, 'hot', s.hot, 'temperature', s.temperature, 'source', v.source,
                   'waiting_since', s.handed_off_at, 'is_test', s.is_test,
                   'queue', case d.outcome when 'manual_queue' then 'manual' when 'waiting_hours' then 'waiting_hours' else 'unassigned' end,
                   'rule', d.rule_name, 'why', d.why, 'eligible', d.eligible, 'decided_at', d.at) x
            from b2c.leads_state s join b2c.leads_v v on v.lead_id = s.lead_id
            left join lateral (select * from b2c.allocation_decisions ad where ad.lead_id = s.lead_id and not ad.simulated order by ad.at desc limit 1) d on true
           where s.status = 'active' and s.owner_id is null and s.deleted_at is null
           order by s.hot desc, s.handed_off_at) q);
end $f$;

/* One click: decide again now (the manual queue included, which the minute timer leaves for a person). */
create or replace function b2c.queue_allocate(p_lead bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('reassign');
  if not exists (select 1 from b2c.leads_state where lead_id = p_lead and status = 'active' and owner_id is null) then raise exception 'this lead already has a counsellor'; end if;
  return b2c.allocate(p_lead, 'manual');
end $f$;

-- ---------- working calendar (E7) ----------
create table if not exists b2c.work_breaks (
  id bigint generated always as identity primary key,
  user_id uuid references b2c.users (user_id),   -- null: everyone
  isodow smallint check (isodow between 1 and 7), -- null: every day
  start_t time not null,
  end_t time not null check (end_t > start_t),
  label text not null default 'Lunch',
  active boolean not null default true
);
alter table b2c.work_breaks enable row level security;

create or replace function b2c.on_break(p_user uuid, p_at timestamptz default now()) returns boolean language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from b2c.work_breaks b
                  where b.active and (b.user_id is null or b.user_id = p_user)
                    and (b.isodow is null or b.isodow = extract(isodow from (p_at at time zone coalesce((select u.tz from b2c.users u where u.user_id = p_user), 'Asia/Kolkata'))))
                    and (p_at at time zone coalesce((select u.tz from b2c.users u where u.user_id = p_user), 'Asia/Kolkata'))::time >= b.start_t
                    and (p_at at time zone coalesce((select u.tz from b2c.users u where u.user_id = p_user), 'Asia/Kolkata'))::time < b.end_t)
$f$;

create or replace function b2c.breaks_save(p jsonb) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); x jsonb; n int := 0;
begin
  if jsonb_typeof(p) <> 'array' then raise exception 'a list of breaks'; end if;
  update b2c.work_breaks set active = false where active;
  for x in select * from jsonb_array_elements(p) loop
    if (x ->> 'end')::time <= (x ->> 'start')::time then raise exception 'a break ends after it starts'; end if;
    insert into b2c.work_breaks (user_id, isodow, start_t, end_t, label)
    values (nullif(x ->> 'user_id', '')::uuid, nullif(x ->> 'isodow', '')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(nullif(trim(x ->> 'label'), ''), 'Break'));
    n := n + 1;
  end loop;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'breaks_changed', jsonb_build_object('breaks', p));
  return n;
end $f$;

/* Holidays from a pasted list or a CSV: [{day, name, kind}]. */
create or replace function b2c.holidays_import(p jsonb) returns int language plpgsql security definer set search_path = '' as $f$
declare x jsonb; n int := 0;
begin
  perform b2c.require('settings');
  if jsonb_typeof(p) <> 'array' or jsonb_array_length(p) > 200 then raise exception 'at most 200 holidays at a time'; end if;
  for x in select * from jsonb_array_elements(p) loop
    perform b2c.holiday_save((x ->> 'day')::date, coalesce(nullif(trim(x ->> 'name'), ''), 'Holiday'), coalesce(nullif(x ->> 'kind', ''), 'company'));
    n := n + 1;
  end loop;
  return n;
end $f$;

/* The week: each person's hours, leave and overrides per day; holidays; days or hours with nobody on duty. */
create or replace function b2c.calendar_week(p_from date default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare d0 date := coalesce(p_from, date_trunc('week', now() at time zone 'Asia/Kolkata')::date);
begin
  if not (b2c.can('read_all') or b2c.can('read_team')) then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('from', d0, 'days', (
    select jsonb_agg(jsonb_build_object('day', d, 'holiday', (select h.name from b2c.holidays h where h.day = d),
             'people', (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'on_call', u.on_call,
                           'start', w.w_start, 'end', w.w_end,
                           'leave', exists (select 1 from b2c.leaves lv where lv.user_id = u.user_id and d between lv.from_day and lv.to_day),
                           'override', exists (select 1 from b2c.shift_overrides o where o.user_id = u.user_id and o.day = d)) order by u.full_name), '[]')
                          from b2c.users u, lateral b2c.working_window(u.user_id, d) w
                         where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head') and not u.is_test_user),
             'nobody_on_duty', not exists (select 1 from b2c.users u, lateral b2c.working_window(u.user_id, d) w
                                            where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head') and not u.is_test_user and w.w_start is not null))
           order by d)
      from generate_series(d0, d0 + 6, interval '1 day') g(ts), lateral (select g.ts::date d) dd),
    'breaks', (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'user_id', b.user_id, 'isodow', b.isodow, 'start', b.start_t, 'end', b.end_t, 'label', b.label)), '[]')
                 from b2c.work_breaks b where b.active));
end $f$;

-- ---------- capacity (E8) ----------
/* Daily: the Admin hears when someone passes the alert share of their monthly cap, and when the team reaches the hiring trigger. */
create or replace function b2c.capacity_tick() returns int language plpgsql security definer set search_path = '' as $f$
declare c jsonb; x jsonb; n int := 0; v_month text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM');
begin
  select jsonb_build_object('rows', jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'cap', u.monthly_cap,
           'assigned', (select count(*) from b2c.assignments g where g.user_id = u.user_id and g.at <@ b2c.ist_month((now() at time zone 'Asia/Kolkata')::date)))))
    into c from b2c.users u where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head', 'admin') and not u.is_test_user;
  for x in select * from jsonb_array_elements(coalesce(c -> 'rows', '[]')) loop
    if (x ->> 'cap')::numeric > 0 and (x ->> 'assigned')::numeric / (x ->> 'cap')::numeric * 100 >= coalesce((b2c.setting('allocation') ->> 'capacity_alert_pct')::int, 90) then
      perform b2c.notify_admins('capacity', (x ->> 'name') || ' is at ' || round((x ->> 'assigned')::numeric / (x ->> 'cap')::numeric * 100) || '% of their monthly cap',
                                (x ->> 'assigned') || ' of ' || (x ->> 'cap') || ' leads this month', '/w/allocation', null, 'cap:' || (x ->> 'user_id') || ':' || v_month, false);
      n := n + 1;
    end if;
  end loop;
  if (select avg((y ->> 'assigned')::numeric / nullif((y ->> 'cap')::numeric, 0)) from jsonb_array_elements(coalesce(c -> 'rows', '[]')) y) * 100
       >= coalesce((b2c.setting('allocation') ->> 'capacity_alert_pct')::int, 90) then
    perform b2c.notify_admins('capacity', 'The team is near capacity: time to hire', null, '/w/allocation', null, 'hire:' || v_month, true);
    n := n + 1;
  end if;
  return n;
end $f$;

-- ---------- Teams: the Workspace directory and invitations (E9) ----------
create table if not exists b2c.directory_people (
  email text primary key,
  name text,
  job_title text,
  photo_url text,
  workspace_user_id text,
  suspended boolean not null default false,
  seen_at timestamptz not null default now()
);
alter table b2c.directory_people enable row level security;
alter table b2c.users add column if not exists invite_expires_at timestamptz;
alter table b2c.users add column if not exists first_sign_in_at timestamptz;

/* Every Workspace account the CRM has not been given yet, for one-click adding with a role. */
create or replace function b2c.directory_unadded() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return (select coalesce(jsonb_agg(jsonb_build_object('email', d.email, 'name', d.name, 'job_title', d.job_title, 'photo_url', d.photo_url, 'seen_at', d.seen_at) order by d.name, d.email), '[]')
            from b2c.directory_people d where not d.suspended and d.seen_at > now() - interval '3 days'
             and not exists (select 1 from b2c.users u where u.email = d.email));
end $f$;

/* An invitation is good for 7 days (setting access.invite_days) until the first sign-in. The app checks at sign-in. */
create or replace function b2c.invite_ok(p_email text) returns boolean language sql stable security definer set search_path = '' as $f$
  select coalesce((select u.first_sign_in_at is not null or u.invite_expires_at is null or u.invite_expires_at > now()
                     from b2c.users u where u.email = lower(trim(p_email))), true)
$f$;

create or replace function b2c.invite_sent(p_user uuid) returns timestamptz language plpgsql security definer set search_path = '' as $f$
declare v timestamptz := now() + make_interval(days => coalesce((b2c.setting('access') ->> 'invite_days')::int, 7));
begin
  perform b2c.require('settings');
  update b2c.users set invited_at = now(), invite_expires_at = v, updated_at = now() where user_id = p_user and first_sign_in_at is null;
  return v;
end $f$;

-- ---------- sessions and devices (E10) ----------
insert into b2c.settings (key, value) values ('access', '{"trusted_days": 7, "invite_days": 7}') on conflict (key) do nothing;
alter table b2c.session_checks add column if not exists user_agent text;
alter table b2c.session_checks add column if not exists ip text;
alter table b2c.session_checks add column if not exists last_seen_at timestamptz;
alter table b2c.session_checks add column if not exists revoked_at timestamptz;
alter table b2c.trusted_devices add column if not exists last_used_at timestamptz;

/* A revoked session is signed out of the CRM at its next request. */
create or replace function b2c.my_role() returns text language sql stable security definer set search_path = '' as $f$
  select u.role from b2c.users u
   where u.user_id = b2c.uid() and u.is_active
     and exists (select 1 from b2c.session_checks c where c.session_id = b2c.session_id() and c.user_id = u.user_id and c.revoked_at is null)
$f$;

/* Trusted devices last 7 days (setting access.trusted_days), whatever the code path that created them. */
create or replace function b2c.trusted_device_days() returns trigger language plpgsql set search_path = '' as $f$
begin
  new.expires_at := least(new.expires_at, now() + make_interval(days => coalesce((b2c.setting('access') ->> 'trusted_days')::int, 7)));
  return new;
end $f$;
drop trigger if exists trusted_device_days on b2c.trusted_devices;
create trigger trusted_device_days before insert on b2c.trusted_devices for each row execute function b2c.trusted_device_days();

/* The app notes the browser and address of the current session, and the first sign-in. */
create or replace function b2c.session_note(p_user_agent text, p_ip text) returns void language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.session_checks set user_agent = coalesce(left(p_user_agent, 300), user_agent), ip = coalesce(left(p_ip, 60), ip), last_seen_at = now()
   where session_id = b2c.session_id() and user_id = b2c.uid();
  update b2c.users set first_sign_in_at = now() where user_id = b2c.uid() and first_sign_in_at is null;
end $f$;

create or replace function b2c.my_devices(p_user uuid default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_user uuid := b2c.uid();
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_user is not null and p_user <> v_user then perform b2c.require('settings'); v_user := p_user; end if;
  return jsonb_build_object(
    'sessions', (select coalesce(jsonb_agg(jsonb_build_object('session_id', c.session_id, 'method', c.method, 'signed_in_at', c.at, 'last_seen_at', c.last_seen_at,
                   'user_agent', c.user_agent, 'ip', c.ip, 'current', c.session_id = b2c.session_id()) order by coalesce(c.last_seen_at, c.at) desc), '[]')
                   from b2c.session_checks c where c.user_id = v_user and c.revoked_at is null and c.at > now() - interval '30 days'),
    'devices', (select coalesce(jsonb_agg(jsonb_build_object('id', left(d.token_hash, 16), 'label', d.label, 'created_at', d.created_at, 'expires_at', d.expires_at,
                   'last_used_at', d.last_used_at) order by d.created_at desc), '[]')
                  from b2c.trusted_devices d where d.user_id = v_user and d.revoked_at is null and d.expires_at > now()));
end $f$;

/* Sign out one session or forget one device (one's own; the Admin anyone's), or everything for a person. */
create or replace function b2c.session_revoke(p_session uuid default null, p_device text default null, p_user uuid default null) returns int
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_user uuid := coalesce(p_user, b2c.uid()); n int := 0; m int;
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_user <> me then perform b2c.require('settings'); end if;
  if p_session is null and p_device is null then
    update b2c.session_checks set revoked_at = now() where user_id = v_user and revoked_at is null and session_id is distinct from case when v_user = me then b2c.session_id() end;
    get diagnostics n = row_count;
    update b2c.trusted_devices set revoked_at = now() where user_id = v_user and revoked_at is null;
    get diagnostics m = row_count;
    n := n + m;
  else
    if p_session is not null then
      update b2c.session_checks set revoked_at = now() where session_id = p_session and user_id = v_user and revoked_at is null;
      get diagnostics n = row_count;
    end if;
    if p_device is not null then
      update b2c.trusted_devices set revoked_at = now() where left(token_hash, 16) = p_device and user_id = v_user and revoked_at is null;
      get diagnostics m = row_count;
      n := n + m;
    end if;
  end if;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'sign_out_remote', jsonb_build_object('user', v_user, 'session', p_session, 'device', p_device, 'count', n));
  return n;
end $f$;

-- ---------- team and revenue on student_leads (E14) ----------
insert into b2c.settings (key, value) values ('b2b_writes', '{"team_and_revenue": false}') on conflict (key) do nothing;

/* Off until the B2B CRM's write API accepts team_id, expected_net_revenue_inr and realised_net_revenue_inr
   (docs/b2b-developer-notes.md): a refused field would hold back the other changes in the same update. */
create or replace function b2c.write_team_revenue() returns trigger language plpgsql security definer set search_path = '' as $f$
declare v_lead bigint; v_exp numeric; v_real numeric;
begin
  if not coalesce((b2c.setting('b2b_writes') ->> 'team_and_revenue')::boolean, false) then return null; end if;
  if tg_table_name = 'assignments' then
    perform b2c.queue_update(new.lead_id, jsonb_build_object('team_id', (select team from b2c.users where user_id = new.user_id)), false);
  else
    select e.lead_id into v_lead from b2c.enrollments e where e.id = new.enrollment_id;
    select sum(g.net), sum(g.net) filter (where g.realised_at is not null) into v_exp, v_real
      from b2c.earnings g join b2c.enrollments e on e.id = g.enrollment_id where e.lead_id = v_lead;
    perform b2c.queue_update(v_lead, jsonb_build_object('expected_net_revenue_inr', v_exp, 'realised_net_revenue_inr', coalesce(v_real, 0)), false);
  end if;
  return null;
end $f$;
drop trigger if exists write_team on b2c.assignments;
create trigger write_team after insert on b2c.assignments for each row execute function b2c.write_team_revenue();
drop trigger if exists write_revenue on b2c.earnings;
create trigger write_revenue after insert or update of net, realised_at on b2c.earnings for each row execute function b2c.write_team_revenue();

-- ---------- view as Sales for a chosen counsellor (D13) ----------
create or replace function b2c.view_as_sales(p_user uuid, p jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); u b2c.users;
begin
  select * into u from b2c.users where user_id = p_user and role in ('counsellor', 'sales_head');
  if u.user_id is null then raise exception 'choose a counsellor'; end if;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'view_as_sales', jsonb_build_object('as', p_user, 'name', u.full_name));
  return jsonb_build_object('user', jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'role', u.role),
    'leads', b2c.lead_list_as(p || jsonb_build_object('include_test', u.is_test_user), u.user_id, u.role),
    'followups', (select jsonb_build_object('overdue', count(*) filter (where t.due_at < now()), 'today', count(*) filter (where t.due_at >= now() and t.due_at < now() + interval '1 day'))
                    from b2c.tasks t where t.owner_id = p_user and t.status = 'open'));
end $f$;

-- ---------- the assignment message (E4) ----------
/* Witty is still talking to the student: its last message is within the idle wait (read-only: w2_messages belongs to Witty). */
create or replace function b2c.witty_busy(p_lead bigint) returns boolean language plpgsql stable security definer set search_path = '' as $f$
declare v_last timestamptz; v_idle int := coalesce((b2c.setting('messaging') ->> 'witty_idle_minutes')::int, 10);
begin
  if to_regclass('public.w2_messages') is null then return false; end if;
  execute 'select max(m.created_at) from public.w2_messages m where m.phone = $1' into v_last using b2c.wa_phone(p_lead);
  return v_last is not null and v_last > now() - make_interval(mins => v_idle);
end $f$;

/* The assignment message by email: when the student has no WhatsApp the CRM may use, no template, or WhatsApp failed. */
create or replace function b2c.assignment_email(p_lead bigint, p_next timestamptz) returns bigint language plpgsql security definer set search_path = '' as $f$
declare u b2c.users; v_course text; v_assign bigint;
begin
  select * into u from b2c.users where user_id = (select owner_id from b2c.leads_state where lead_id = p_lead);
  if u.user_id is null then return null; end if;
  select coalesce(max(id), 0) into v_assign from b2c.assignments where lead_id = p_lead;
  select coalesce(nullif(course, ''), 'your programme') into v_course from b2c.leads_v where lead_id = p_lead;
  return b2c.queue_system_email(p_lead, 'Your Eduwit counsellor: ' || coalesce(u.full_name, 'Eduwit'),
    'Hi ' || coalesce(b2c.first_name(p_lead), 'there') || ',' || E'\n\n' ||
    'I am ' || coalesce(u.full_name, 'your counsellor') || ' from Eduwit. I will call you ' ||
    case when p_next is not null and p_next > now() + interval '10 minutes' then 'at ' || to_char(p_next at time zone 'Asia/Kolkata', 'HH12:MI am "on" Dy DD Mon') else 'shortly' end ||
    ' about ' || v_course || '.' || coalesce(E'\n' || 'You can also reach me on ' || nullif(u.phone, '') || '.', '') || E'\n\n' || 'Eduwit',
    'assignment', 'assign-mail:' || p_lead || ':' || v_assign);
end $f$;

create or replace function b2c.queue_assignment_message(p_lead bigint, p_user uuid, p_in_hours boolean, p_next timestamptz) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare t b2c.wa_templates; v_wait timestamptz := now(); v_dedupe text; v bigint; v_idle int := coalesce((b2c.setting('messaging') ->> 'witty_idle_minutes')::int, 10);
begin
  v_dedupe := 'assign:' || p_lead || ':' || (select coalesce(max(a.id), 0) from b2c.assignments a where a.lead_id = p_lead);
  if exists (select 1 from b2c.send_queue where dedupe_key = v_dedupe) then return null; end if;
  select * into t from b2c.wa_templates where purpose = case when p_in_hours then 'assignment_hours' else 'assignment_after_hours' end and archived_at is null
   order by status = 'approved' desc, id limit 1;
  if b2c.witty_busy(p_lead) then v_wait := now() + make_interval(mins => v_idle); end if;
  if t.id is not null and b2c.wa_phone(p_lead) is not null then
    v := b2c.enqueue_template(p_lead, t, p_user, 'assignment',
           jsonb_build_object('next_working_time', to_char(coalesce(p_next, now()) at time zone 'Asia/Kolkata', 'HH12:MI am "on" Dy DD Mon')), v_wait, v_dedupe);
  end if;
  if v is null then v := b2c.assignment_email(p_lead, p_next); end if;
  return v;
end $f$;

-- ---------- redefined: pipeline: the sales head sees their team ----------
CREATE OR REPLACE FUNCTION b2c.pipeline_board(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_owner uuid; v_money boolean;
begin
  if v_role is null or v_role = 'marketing' then raise exception 'not allowed' using errcode = '42501'; end if;
  v_money := true;
  v_owner := case when v_role in ('admin', 'sales_head') then nullif(p ->> 'owner', '')::uuid else me end;
  return (with l as (
      select v.lead_id, v.name, v.course, v.university, v.stage_id, v.sub_stage, v.temperature, v.hot, v.next_task_due_at, v.owner_id, v.owner_name, v.source,
             v.sla_due_at, v.sla_met_at, v.sla_breached_at, v.stage_changed_at, v.is_test,
             coalesce(v.next_task_due_at < now(), false) overdue,
             case when v.sla_breached_at is not null and v.sla_met_at is null then 'red'
                  when v.sla_met_at is null and v.sla_due_at is not null and v.sla_due_at < now() + interval '15 minutes' then 'amber'
                  when v.sla_met_at is null and v.sla_due_at is not null then 'green' end sla,
             b2c.lead_expected_value(v.lead_id) expected
        from b2c.leads_v v
       where v.status = 'active' and v.deleted_at is null and v.stage_id is not null
         and (v_owner is null or v.owner_id = v_owner)
         and (v_role <> 'counsellor' or v.owner_id = me) and b2c.in_my_team(v.owner_id)
         and (coalesce((p ->> 'include_test')::boolean, v_role = 'admin') or not v.is_test)
         and (p ->> 'temperature' is null or v.temperature = p ->> 'temperature')
         and (p ->> 'source' is null or v.source = p ->> 'source')
         and (not coalesce((p ->> 'hot')::boolean, false) or v.hot)
         and (not coalesce((p ->> 'overdue')::boolean, false) or v.next_task_due_at < now())
         and (coalesce(trim(p ->> 'search'), '') = '' or v.name ilike '%' || trim(p ->> 'search') || '%' or v.course ilike '%' || trim(p ->> 'search') || '%'))
    select jsonb_build_object('columns', coalesce(jsonb_agg(jsonb_build_object('stage_id', st.id, 'name', st.name, 'canon', st.canon,
             'count', coalesce(c.n, 0), 'expected', case when v_money then coalesce(c.x, 0) end, 'cards', coalesce(c.cards, '[]')) order by st.id), '[]'))
      from b2c.stages st
      left join lateral (select count(*) n, sum(l.expected) x,
                                (select jsonb_agg(jsonb_build_object('lead_id', k.lead_id, 'name', k.name, 'course', k.course, 'university', k.university, 'sub_stage', k.sub_stage,
                                          'temperature', k.temperature, 'hot', k.hot, 'next_task_due_at', k.next_task_due_at, 'overdue', k.overdue, 'sla', k.sla,
                                          'expected', k.expected, 'owner_name', k.owner_name, 'days_in_stage', floor(extract(epoch from now() - k.stage_changed_at) / 86400)::int)
                                          order by k.overdue desc, k.hot desc, (k.sla in ('red', 'amber')) desc nulls last, k.expected desc nulls last, k.next_task_due_at nulls last)
                                   from (select * from l l2 where l2.stage_id = st.id
                                          order by l2.overdue desc, l2.hot desc, (l2.sla in ('red', 'amber')) desc nulls last, l2.expected desc nulls last limit 100) k) cards
                           from l where l.stage_id = st.id) c on true
     where st.id not in (9, 10) or coalesce((p ->> 'closed')::boolean, false));
end $f$;

-- ---------- redefined: inbox: the sales head sees their team ----------
CREATE OR REPLACE FUNCTION b2c.inbox_list(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_q text := nullif(trim(p ->> 'search'), ''); v_digits text;
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_digits := nullif(regexp_replace(coalesce(v_q, ''), '\D', '', 'g'), '');
  return (select coalesce(jsonb_agg(x order by x ->> 'last_at' desc nulls last), '[]') from (
    select jsonb_build_object('phone', c.phone, 'lead_id', c.lead_id, 'name', v.name, 'course', v.course, 'owner_id', v.owner_id, 'owner_name', v.owner_name,
                              'status', v.status, 'unread', c.unread,
                              'window_open', c.last_inbound_at > now() - interval '24 hours', 'window_closes_at', c.last_inbound_at + interval '24 hours',
                              'awaiting_reply', coalesce(lm.direction = 'in', false),
                              'last_at', greatest(c.last_inbound_at, c.last_outbound_at), 'read_only', v_role = 'marketing',
                              'last', lm.body, 'last_template', lm.template_name, 'last_direction', lm.direction,
                              'match', case when v_q is not null then (select left(m.body, 160) from b2c.wa_messages m where m.phone = c.phone and m.body ilike '%' || v_q || '%' order by m.created_at desc limit 1) end) x
      from b2c.wa_conversations c
      left join b2c.leads_v v on v.lead_id = c.lead_id
      left join lateral (select m.body, m.template_name, m.direction from b2c.wa_messages m where m.phone = c.phone order by m.created_at desc, m.id desc limit 1) lm on true
     where (v_role in ('admin', 'marketing') or (v_role = 'sales_head' and b2c.in_my_team(v.owner_id)) or v.owner_id = me)
       and (v_q is null or v.name ilike '%' || v_q || '%' or (v_digits is not null and c.phone like '%' || v_digits || '%')
            or exists (select 1 from b2c.wa_messages m where m.phone = c.phone and (m.body ilike '%' || v_q || '%' or m.template_name ilike '%' || v_q || '%')))
       and (not coalesce((p ->> 'unread')::boolean, false) or c.unread > 0)
       and (p ->> 'owner' is null or v_role = 'counsellor' or (p ->> 'owner' = 'none' and v.owner_id is null) or v.owner_id::text = p ->> 'owner')
       and (p ->> 'window' is null or (p ->> 'window' = 'open') = coalesce(c.last_inbound_at > now() - interval '24 hours', false))
       and (not coalesce((p ->> 'awaiting')::boolean, false) or lm.direction = 'in')
     order by greatest(c.last_inbound_at, c.last_outbound_at) desc nulls last
     limit least(coalesce((p ->> 'limit')::int, 200), 500)) q);
end $f$;

-- ---------- redefined: sending: the assignment message waits while Witty is still talking to the student (checked at send time) ----------
CREATE OR REPLACE FUNCTION b2c.send_take(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v jsonb;
begin
  with c as (select id from b2c.send_queue where status = 'queued' and not_before <= now()
                and not (purpose = 'assignment' and channel = 'whatsapp' and lead_id is not null and b2c.witty_busy(lead_id))
              order by not_before limit p_limit for update skip locked),
  u as (update b2c.send_queue q set status = 'sending', attempts = attempts + 1 from c where q.id = c.id
        returning q.id, q.channel, q.lead_id, q.to_address, q.payload, q.purpose, q.wa_message_id)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'channel', u.channel, 'lead_id', u.lead_id, 'to', u.to_address, 'payload', u.payload,
                  'purpose', u.purpose, 'wa_message_id', u.wa_message_id,
                  'live', b2c.live(u.channel) and not b2c.is_test_phone(u.to_address) and not coalesce((select s.is_test from b2c.leads_state s where s.lead_id = u.lead_id), false))), '[]')
    into v from u;
  return v;
end $f$;

-- ---------- redefined: sending: a failed assignment WhatsApp falls back to email ----------
CREATE OR REPLACE FUNCTION b2c.send_done(p_results jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare r jsonb; q b2c.send_queue; n int := 0; v_status text;
begin
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]')) loop
    select * into q from b2c.send_queue where id = (r ->> 'id')::bigint for update;
    continue when q.id is null or q.status <> 'sending';
    v_status := case when coalesce((r ->> 'ok')::boolean, false) then case when coalesce((r ->> 'dry_run')::boolean, false) then 'dry_run' else 'sent' end
                     when q.attempts >= 5 then 'failed' else 'queued' end;
    update b2c.send_queue set status = v_status, error = r ->> 'error', sent_at = case when v_status in ('sent', 'dry_run') then now() end,
           not_before = case when v_status = 'queued' then now() + make_interval(mins => 2 * q.attempts) else not_before end
     where id = q.id;
    if q.wa_message_id is not null then
      update b2c.wa_messages set status = case v_status when 'queued' then 'queued' else v_status end, wamid = coalesce(r ->> 'wamid', wamid),
             error = r ->> 'error', status_at = now() where id = q.wa_message_id;
      if v_status in ('sent', 'dry_run') then
        update b2c.wa_conversations set last_outbound_at = now(), updated_at = now() where phone = q.to_address;
      end if;
    end if;
    if q.consent_request_id is not null and v_status in ('sent', 'dry_run') then
      update b2c.consent_requests set status = 'sent', sent_at = now(), sent_wamid = r ->> 'wamid' where request_id = q.consent_request_id;
      perform b2c.queue_event('b2ccrm.consent_request_sent', q.lead_id, jsonb_build_object('request_id', q.consent_request_id, 'sent_at', now(),
                              'message_id', coalesce(r ->> 'wamid', 'dry-run-' || q.id)), true);
    end if;
    if v_status = 'failed' and q.purpose = 'assignment' and q.channel = 'whatsapp' then
      perform b2c.assignment_email(q.lead_id, null);
    end if;
    if v_status = 'failed' then
      perform b2c.notify_admins('send_failed', 'A message could not be sent', coalesce(r ->> 'error', ''), '/w/connectors', q.lead_id, 'sendfail:' || q.id);
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

-- ---------- redefined: allocation: on-call for hot leads outside hours; simulation may include disabled or future rules ----------
CREATE OR REPLACE FUNCTION b2c.decide(p_lead bigint, p_trigger text, p_at timestamp with time zone DEFAULT now(), p_exclude uuid DEFAULT NULL::uuid, p_sim boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare
  f jsonb := b2c.lead_facts(p_lead, p_trigger, p_at);
  s b2c.leads_state; r b2c.allocation_rules; u b2c.users;
  v_hot boolean; v_why text; v_cands jsonb; v_skip jsonb; v_chosen uuid; v_turn int; v_n int; v_i int; v_fb text;
  v_ids uuid[]; v_ok uuid[]; v_match text[]; v_pool text; v_tried jsonb := '[]'::jsonb; v_perf jsonb;
begin
  if f is null then return jsonb_build_object('outcome', 'skipped', 'why', 'unknown lead'); end if;
  select * into s from b2c.leads_state where lead_id = p_lead;
  v_hot := coalesce(s.hot, false) or p_trigger in ('reengaged', 're_enquiry_hot');
  for r in select * from b2c.allocation_rules
             where (enabled and applies_from <= p_at)
                or (p_sim and id = any (coalesce(nullif(current_setting('b2c.sim_rules', true), '')::bigint[], '{}')))
             order by position, id loop
    continue when not b2c.rule_matches(r.condition, f);
    v_pool := coalesce((select p.name from b2c.pools p where p.id = r.pool_id), 'Everyone');
    -- the pool, in a stable order
    select array_agg(x.user_id order by x.pos, x.email) into v_ids from (
      select u2.user_id, coalesce(pm.position, 0) pos, u2.email from b2c.users u2
        left join b2c.pool_members pm on pm.pool_id = r.pool_id and pm.user_id = u2.user_id
       where (r.pool_id is null or pm.user_id is not null) and u2.user_id is distinct from p_exclude) x;
    v_cands := '[]'; v_skip := '[]'; v_ok := '{}';
    foreach v_chosen in array coalesce(v_ids, '{}') loop
      select * into u from b2c.users where user_id = v_chosen;
      v_why := b2c.ineligible(u, f, p_at, v_hot, p_sim);
      -- skill and territory logics narrow the pool
      if v_why is null and r.logic = 'skill_match' then
        v_match := array(select jsonb_array_elements_text(coalesce(r.params -> 'match', '["language"]')));
        if 'language' = any (v_match) and f ->> 'language' is not null and not exists (select 1 from unnest(u.languages) g where lower(g) = lower(f ->> 'language')) then v_why := 'language'; end if;
        if v_why is null and 'programme' = any (v_match) and f ->> 'course' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'programmes', '[]')) g where lower(f ->> 'course') like '%' || lower(g) || '%') then v_why := 'programme skill'; end if;
        if v_why is null and 'university' = any (v_match) and f ->> 'university' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'universities', '[]')) g where lower(g) = lower(f ->> 'university')) then v_why := 'university skill'; end if;
        if v_why is null and 'level' = any (v_match) and f ->> 'level' is not null and not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'levels', '[]')) g where lower(g) = lower(f ->> 'level')) then v_why := 'level skill'; end if;
      elsif v_why is null and r.logic = 'territory' then
        if not exists (select 1 from jsonb_array_elements_text(coalesce(u.skills -> 'territories', '[]')) g where lower(g) in (lower(f ->> 'city'), lower(f ->> 'state'))) then v_why := 'territory'; end if;
      end if;
      if v_why is null then v_ok := v_ok || v_chosen; v_cands := v_cands || jsonb_build_object('user_id', v_chosen, 'name', u.full_name);
      else v_skip := v_skip || jsonb_build_object('user_id', v_chosen, 'name', u.full_name, 'why', v_why); end if;
    end loop;

    v_chosen := null; v_turn := null;
    if r.logic = 'manual' then
      return jsonb_build_object('outcome', 'manual_queue', 'rule_id', r.id, 'rule_name', r.name, 'logic', r.logic, 'pool', v_pool,
                                'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'manual queue');
    elsif r.logic = 'returning' then
      if coalesce(s.previous_owner_id, s.lost_by_user) = any (v_ok) then v_chosen := coalesce(s.previous_owner_id, s.lost_by_user); end if;
      if v_chosen is null then v_tried := v_tried || jsonb_build_object('rule', r.name, 'why', 'previous counsellor not eligible'); continue; end if;
    elsif cardinality(v_ok) > 0 then
      if r.logic in ('round_robin', 'pinning', 'skill_match', 'territory') then
        v_turn := r.turn;
        if p_sim then
          execute 'select turn from pg_temp.sim_turns where rule_id = $1' into v_turn using r.id;
          v_turn := coalesce(v_turn, r.turn);
        end if;
        v_n := cardinality(v_ids);
        for v_i in 1 .. v_n loop
          if v_ids[((v_turn + v_i) % v_n) + 1] = any (v_ok) then v_chosen := v_ids[((v_turn + v_i) % v_n) + 1]; v_turn := (v_turn + v_i) % v_n; exit; end if;
        end loop;
      elsif r.logic = 'performance' then
        -- B7.3 performance-weighted: each eligible counsellor's share of turns follows their conversion (b2c.perf_weights),
        -- within the floor and cap; the next lead goes to whoever is furthest below their share this month
        v_perf := b2c.perf_weights(v_ok, r.params, p_at);
        select x.uid into v_chosen from (
          select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(coalesce((w.e ->> 'weight')::numeric, 1), 0.01) score, uu.email
            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid
            left join lateral (select e from jsonb_array_elements(v_perf -> 'rows') e where (e ->> 'user_id')::uuid = c.uid) w on true) x
         order by x.score, x.email limit 1;
        select coalesce(jsonb_agg(c || coalesce((select e - 'user_id' - 'name' from jsonb_array_elements(v_perf -> 'rows') e where e ->> 'user_id' = c ->> 'user_id'), '{}')), '[]')
          into v_cands from jsonb_array_elements(v_cands) c;
      elsif r.logic = 'weighted_round_robin' then
        select x.uid into v_chosen from (
          select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(coalesce(pm.weight, uu.weight, 1), 1) score, uu.email
            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid
            left join b2c.pool_members pm on pm.pool_id = r.pool_id and pm.user_id = c.uid) x
         order by x.score, x.email limit 1;
      elsif r.logic = 'least_loaded' then
        select x.uid into v_chosen from (select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> case when p_sim then 'month' else 'open' end)::int n, uu.email
                                            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid) x order by x.n, x.email limit 1;
      elsif r.logic = 'capacity' then
        select x.uid into v_chosen from (select c.uid, (b2c.load_of(c.uid, p_at, p_sim) ->> 'month')::numeric / greatest(uu.monthly_cap, 1) n, uu.email
                                            from unnest(v_ok) c(uid) join b2c.users uu on uu.user_id = c.uid) x order by x.n, x.email limit 1;
      end if;
    end if;

    if v_chosen is not null then
      return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', r.logic, 'pool', v_pool,
                                'eligible', v_cands, 'skipped', v_skip, 'turn', v_turn, 'hot', v_hot, 'facts', f, 'tried', v_tried)
             || case when v_perf is not null then jsonb_build_object('performance', v_perf - 'rows',
                       'why', format('performance over %s days: team conversion %s%%, shares kept between %s and %s of an equal share',
                                     v_perf ->> 'window_days', round((v_perf ->> 'team_rate')::numeric * 100, 1), v_perf ->> 'floor', v_perf ->> 'cap')) else '{}'::jsonb end;
    end if;
    -- a hot lead outside hours goes to the on-call counsellor, whatever the rule's fallbacks (B7.1)
    if v_hot and cardinality(v_ok) = 0 and exists (select 1 from jsonb_array_elements(v_skip) x where x ->> 'why' = 'off hours') then
      select uu.user_id into v_chosen from b2c.users uu
       where uu.on_call and uu.is_active and uu.role in ('counsellor', 'sales_head') and uu.user_id is distinct from p_exclude
         and uu.is_test_user = coalesce((f ->> 'is_test')::boolean, false)
         and not exists (select 1 from b2c.leaves lv where lv.user_id = uu.user_id and b2c.local_day(uu.user_id, p_at) between lv.from_day and lv.to_day)
       order by uu.email limit 1;
      if v_chosen is not null then
        return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'on_call',
                                  'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'hot lead outside hours: on call', 'tried', v_tried);
      end if;
    end if;
    -- nobody eligible under this rule: its fallbacks, in order
    v_tried := v_tried || jsonb_build_object('rule', r.name, 'skipped', v_skip);
    for v_fb in select jsonb_array_elements_text(r.fallbacks) loop
      if v_fb = 'next_rule' then exit;
      elsif v_fb = 'on_call' then
        select uu.user_id into v_chosen from b2c.users uu
         where uu.on_call and uu.is_active and uu.role in ('counsellor', 'sales_head') and uu.user_id is distinct from p_exclude
           and uu.is_test_user = coalesce((f ->> 'is_test')::boolean, false)
           and not exists (select 1 from b2c.leaves lv where lv.user_id = uu.user_id and b2c.local_day(uu.user_id, p_at) between lv.from_day and lv.to_day)
         order by uu.email limit 1;
        if v_chosen is not null then
          return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'on_call',
                                    'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'on-call fallback', 'tried', v_tried);
        end if;
      elsif v_fb = 'admin' then
        select uu.user_id into v_chosen from b2c.users uu where uu.role = 'admin' and uu.is_active and uu.takes_leads and uu.user_id is distinct from p_exclude order by uu.email limit 1;
        if v_chosen is not null then
          return jsonb_build_object('outcome', 'assigned', 'chosen', v_chosen, 'rule_id', r.id, 'rule_name', r.name, 'logic', 'admin',
                                    'pool', v_pool, 'eligible', v_cands, 'skipped', v_skip, 'hot', v_hot, 'facts', f, 'why', 'Admin fallback', 'tried', v_tried);
        end if;
      elsif v_fb = 'unassigned' then
        return b2c.decide_none(f, v_hot, v_tried, r, v_pool, v_cands, v_skip, p_exclude, p_at);
      end if;
    end loop;
  end loop;
  return b2c.decide_none(f, v_hot, v_tried, null, null, '[]', '[]', p_exclude, p_at);
end $f$;

-- ---------- redefined: allocation: the minute timer leaves the manual queue alone ----------
CREATE OR REPLACE FUNCTION b2c.allocation_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare r record; n int := 0; v_alert int := coalesce((b2c.setting('allocation') ->> 'unassigned_alert_minutes')::int, 5);
begin
  for r in select s.lead_id, s.handed_off_at from b2c.leads_state s
            where s.status = 'active' and s.owner_id is null and s.deleted_at is null
              -- the manual queue waits for a person, unless the rules changed since it was decided
              and not exists (select 1 from (select d.outcome, d.at from b2c.allocation_decisions d where d.lead_id = s.lead_id and not d.simulated order by d.at desc limit 1) d
                               where d.outcome = 'manual_queue' and d.at > coalesce((select max(coalesce(ar.updated_at, ar.created_at)) from b2c.allocation_rules ar), '-infinity'))
            order by s.handed_off_at limit 100 loop
    perform b2c.allocate(r.lead_id, 'retry'); n := n + 1;
    if not exists (select 1 from b2c.leads_state where lead_id = r.lead_id and owner_id is not null)
       and r.handed_off_at < now() - make_interval(mins => v_alert) and b2c.working_now(null, now()) then
      perform b2c.notify_admins('unassigned', 'A sales lead is waiting unassigned', 'Waiting since ' || to_char(r.handed_off_at at time zone 'Asia/Kolkata', 'HH24:MI'),
                                '/w/allocation', r.lead_id, 'unassigned:' || r.lead_id || ':' || to_char(now(), 'YYYYMMDDHH24'));
    end if;
  end loop;
  for r in select lv.id, lv.user_id from b2c.leaves lv
            where lv.mode = 'reassign' and lv.reassigned_at is null and current_date between lv.from_day and lv.to_day
              and (lv.from_day::timestamp at time zone 'Asia/Kolkata') + make_interval(hours => coalesce(lv.reassign_after_hours, 0)) <= now() loop
    perform b2c.allocate(s.lead_id, 'leave', r.user_id) from b2c.leads_state s where s.owner_id = r.user_id and s.status = 'active';
    update b2c.leaves set reassigned_at = now() where id = r.id;
  end loop;
  return jsonb_build_object('retried', n);
end $f$;

-- ---------- redefined: allocation: breaks and lunch take hot leads only ----------
CREATE OR REPLACE FUNCTION b2c.ineligible(u b2c.users, p_facts jsonb, p_at timestamp with time zone, p_hot boolean, p_sim boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare l jsonb; v_test boolean := coalesce((p_facts ->> 'is_test')::boolean, false); a jsonb := b2c.setting('allocation');
begin
  if not u.is_active then return 'inactive'; end if;
  if u.role = 'marketing' then return 'marketing'; end if;
  if u.role = 'admin' and not (u.takes_leads and coalesce((a ->> 'admin_takes_leads')::boolean, true)) then return 'admin does not take leads'; end if;
  if v_test and not (u.is_test_user or u.role = 'admin') then return 'test lead'; end if;
  if not v_test and u.is_test_user then return 'test user'; end if;
  if exists (select 1 from b2c.leaves lv where lv.user_id = u.user_id and b2c.local_day(u.user_id, p_at) between lv.from_day and lv.to_day) then return 'on leave'; end if;
  if u.away_until > p_at then return 'away'; end if;
  l := b2c.load_of(u.user_id, p_at, p_sim);
  if (l ->> 'month')::int >= u.monthly_cap then return 'monthly cap'; end if;
  if u.open_cap is not null and (l ->> 'open')::int >= u.open_cap then return 'open-lead cap'; end if;
  if u.daily_cap is not null and (l ->> 'day')::int >= u.daily_cap then return 'daily cap'; end if;
  if not b2c.working_now(u.user_id, p_at) then
    if p_hot then return 'off hours'; end if;
    if not coalesce((a ->> 'allow_outside_hours_non_hot')::boolean, true) then return 'off hours'; end if;
  end if;
  if not p_hot and b2c.on_break(u.user_id, p_at) then return 'on break'; end if;
  return null;
end $f$;

-- ---------- redefined: capacity: today's intake beside each person's load ----------
CREATE OR REPLACE FUNCTION b2c.capacity()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare m tstzrange := b2c.ist_month((now() at time zone 'Asia/Kolkata')::date); a jsonb := b2c.setting('allocation'); v jsonb;
begin
  if not (b2c.can('read_all') or b2c.can('read_team')) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(x order by x ->> 'name'), '[]') into v from (
    select jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'cap', u.monthly_cap,
             'assigned', (select count(*) from b2c.assignments g where g.user_id = u.user_id and g.at <@ m),
             'open', (select count(*) from b2c.leads_state s where s.owner_id = u.user_id and s.status = 'active' and s.deleted_at is null),
             'enrollments', (select count(*) from b2c.enrollments e where e.counsellor_id = u.user_id and e.status in ('reported', 'verified')
                               and (e.enrolled_on::timestamp at time zone 'Asia/Kolkata') <@ m)) x
      from b2c.users u where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head', 'admin') and not u.is_test_user) s;
  return jsonb_build_object('rows', v,
    'today', jsonb_build_object('handed_off', (select count(*) from b2c.leads_state s where s.handed_off_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' and not s.is_test),
                                'assigned', (select count(*) from b2c.assignments g join b2c.leads_state s on s.lead_id = g.lead_id
                                              where g.at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' and not s.is_test),
                                'waiting', (select count(*) from b2c.leads_state s where s.status = 'active' and s.owner_id is null and s.deleted_at is null and not s.is_test)),
    'capacity_alert_pct', coalesce((a ->> 'capacity_alert_pct')::int, 90),
    'hiring_trigger_enrollments', coalesce((a ->> 'hiring_trigger_enrollments')::int, 10),
    'hiring', coalesce((select avg((x ->> 'enrollments')::numeric) from jsonb_array_elements(v) x), 0) >= coalesce((a ->> 'hiring_trigger_enrollments')::int, 10)
              or coalesce((select avg((x ->> 'assigned')::numeric / nullif((x ->> 'cap')::numeric, 0)) from jsonb_array_elements(v) x), 0) * 100 >= coalesce((a ->> 'capacity_alert_pct')::int, 90));
end $f$;

-- ---------- redefined: directory: every Workspace account is kept, for "not yet added" ----------
CREATE OR REPLACE FUNCTION b2c.directory_sync(p_users jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare x jsonb; n int := 0; d int := 0; v_user uuid; r record; moved int := 0; m int;
begin
  for x in select * from jsonb_array_elements(coalesce(p_users, '[]')) loop
    if coalesce(x ->> 'email', '') <> '' then
      insert into b2c.directory_people (email, name, job_title, photo_url, workspace_user_id, suspended, seen_at)
      values (lower(x ->> 'email'), x ->> 'name', x ->> 'job_title', x ->> 'photo_url', x ->> 'id', coalesce((x ->> 'suspended')::boolean, false), now())
      on conflict (email) do update set name = excluded.name, job_title = excluded.job_title, photo_url = excluded.photo_url,
             workspace_user_id = excluded.workspace_user_id, suspended = excluded.suspended, seen_at = now();
    end if;
    update b2c.users set full_name = coalesce(nullif(x ->> 'name', ''), full_name), photo_url = coalesce(nullif(x ->> 'photo_url', ''), photo_url),
           job_title = coalesce(nullif(x ->> 'job_title', ''), job_title), workspace_user_id = coalesce(x ->> 'id', workspace_user_id), synced_at = now()
     where email = lower(x ->> 'email')
    returning user_id into v_user;
    if v_user is null then continue; end if;
    n := n + 1;
    if coalesce((x ->> 'suspended')::boolean, false)
       and exists (select 1 from b2c.users where user_id = v_user and is_active)
       and not ((select role from b2c.users where user_id = v_user) = 'admin'
                and (select count(*) from b2c.users where role = 'admin' and is_active) <= 1) then
      update b2c.users set is_active = false, deactivated_at = now(), on_call = false, updated_at = now() where user_id = v_user;
      update b2c.trusted_devices set revoked_at = now() where user_id = v_user and revoked_at is null;
      m := 0;
      for r in select lead_id from b2c.leads_state where owner_id = v_user and status = 'active' loop
        perform b2c.allocate(r.lead_id, 'deactivated', v_user); m := m + 1;
      end loop;
      perform b2c.log('team.user_deactivated', null, jsonb_build_object('user_id', v_user, 'reason', 'suspended in Google Workspace', 'reassigned', m), 'system');
      d := d + 1; moved := moved + m;
    end if;
    v_user := null;
  end loop;
  perform b2c.sync_set('directory_at', to_jsonb(now()));
  return jsonb_build_object('updated', n, 'deactivated', d, 'reassigned', moved);
end $f$;

-- ---------- redefined: reassign: the sales head within their team ----------
CREATE OR REPLACE FUNCTION b2c.reassign(p_leads bigint[], p_user uuid, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v bigint; n int := 0; v_d bigint;
begin
  perform b2c.require('reassign');
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'give a reason'; end if;
  if b2c.my_role() = 'sales_head' then
    if exists (select 1 from b2c.leads_state s where s.lead_id = any (p_leads) and not b2c.in_my_team(s.owner_id)) then raise exception 'not your team''s lead' using errcode = '42501'; end if;
    if p_user is not null and not b2c.in_my_team(p_user) then raise exception 'choose someone in your team'; end if;
  end if;
  foreach v in array p_leads loop
    if p_user is null then perform b2c.allocate(v, 'reassign', (select owner_id from b2c.leads_state where lead_id = v));
    else
      if not exists (select 1 from b2c.users where user_id = p_user and is_active and role in ('counsellor', 'sales_head', 'admin')) then raise exception 'not an active counsellor'; end if;
      insert into b2c.allocation_decisions (lead_id, trigger, chosen, outcome, why) values (v, 'reassign', p_user, 'assigned', 'manual: ' || p_reason) returning id into v_d;
      perform b2c.assign(v, p_user, v_d, 'reassign', p_reason);
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

-- ---------- redefined: devices: last used ----------
CREATE OR REPLACE FUNCTION b2c.device_trust_check(p_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v_ok boolean;
begin
  if b2c.uid() is null or b2c.session_id() is null or p_token is null then return false; end if;
  select true into v_ok from b2c.trusted_devices d join b2c.users u on u.user_id = d.user_id and u.is_active
   where d.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and d.user_id = b2c.uid()
     and d.revoked_at is null and d.expires_at > now();
  if coalesce(v_ok, false) then
    update b2c.trusted_devices set last_used_at = now() where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');
    insert into b2c.session_checks (session_id, user_id, method) values (b2c.session_id(), b2c.uid(), 'trusted_device') on conflict (session_id) do nothing;
  end if;
  return coalesce(v_ok, false);
end $f$;

drop function if exists b2c.simulate(date, date);
CREATE OR REPLACE FUNCTION b2c.simulate(p_from date, p_to date, p_include bigint[] DEFAULT NULL::bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare r record; d jsonb; v_rows jsonb;
begin
  perform b2c.require('settings');
  -- disabled or future rules to try as if they were live
  perform set_config('b2c.sim_rules', coalesce(p_include, '{}')::text, true);
  -- fresh scratch tables, dropped at commit: one simulation per transaction (each RPC call is its own transaction)
  if to_regclass('pg_temp.sim_out') is not null then raise exception 'a simulation already ran in this transaction'; end if;
  create temp table sim_load (user_id uuid, m date, d date, n int) on commit drop;
  create temp table sim_turns (rule_id bigint primary key, turn int) on commit drop;
  create temp table sim_out (lead_id bigint, actual uuid, simulated uuid, outcome text, rule text) on commit drop;
  for r in select s.lead_id, coalesce(a.at, s.handed_off_at) at, a.user_id actual, a.trigger
             from b2c.leads_state s
             left join lateral (select x.at, x.user_id, x.trigger from b2c.assignments x where x.lead_id = s.lead_id order by x.at limit 1) a on true
            where coalesce(a.at, s.handed_off_at) >= p_from and coalesce(a.at, s.handed_off_at) < p_to + 1 and not s.is_test
            order by 2 loop
    d := b2c.decide(r.lead_id, coalesce(r.trigger, 'handoff'), r.at, null, true);
    if d ->> 'outcome' = 'assigned' then
      insert into pg_temp.sim_load values ((d ->> 'chosen')::uuid, date_trunc('month', r.at at time zone 'Asia/Kolkata')::date, (r.at at time zone 'Asia/Kolkata')::date, 1);
      if d ->> 'turn' is not null then
        insert into pg_temp.sim_turns values ((d ->> 'rule_id')::bigint, (d ->> 'turn')::int) on conflict (rule_id) do update set turn = excluded.turn;
      end if;
    end if;
    insert into pg_temp.sim_out values (r.lead_id, r.actual, (d ->> 'chosen')::uuid, d ->> 'outcome', d ->> 'rule_name');
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('user_id', x.uid, 'name', u.full_name, 'actual', x.actual, 'simulated', x.simulated) order by u.full_name), '[]')
    into v_rows
    from (select coalesce(a.uid, s.uid) uid, coalesce(a.n, 0) actual, coalesce(s.n, 0) simulated
            from (select actual uid, count(*) n from pg_temp.sim_out where actual is not null group by 1) a
            full join (select simulated uid, count(*) n from pg_temp.sim_out where simulated is not null group by 1) s on s.uid = a.uid) x
    left join b2c.users u on u.user_id = x.uid;
  return jsonb_build_object('leads', (select count(*) from pg_temp.sim_out), 'unassigned', (select count(*) from pg_temp.sim_out where simulated is null),
                            'by_person', v_rows);
end $f$;

-- ---------- timers ----------
do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-capacity') then
    perform cron.schedule('b2c-capacity', '15 4 * * *', 'select b2c.capacity_tick()');
  end if;
end $d$;

-- ---------- grants ----------
grant execute on function b2c.stage_override_request(bigint, smallint, text, text, timestamptz), b2c.stage_override_decide(bigint, boolean, text), b2c.stage_requests_list(),
  b2c.stage_save(jsonb), b2c.sub_stage_save(jsonb), b2c.stages_admin(), b2c.queues(), b2c.queue_allocate(bigint), b2c.breaks_save(jsonb), b2c.holidays_import(jsonb),
  b2c.calendar_week(date), b2c.directory_unadded(), b2c.invite_sent(uuid), b2c.session_note(text, text), b2c.my_devices(uuid), b2c.session_revoke(uuid, text, uuid),
  b2c.view_as_sales(uuid, jsonb), b2c.simulate(date, date, bigint[]), b2c.pipeline_board(jsonb), b2c.inbox_list(jsonb), b2c.capacity(), b2c.reassign(bigint[], uuid, text),
  b2c.device_trust_check(text) to authenticated;
grant execute on function b2c.invite_ok(text), b2c.capacity_tick(), b2c.directory_sync(jsonb) to service_role;
revoke execute on function b2c.invite_ok(text), b2c.capacity_tick(), b2c.witty_busy(bigint), b2c.assignment_email(bigint, timestamptz), b2c.on_break(uuid, timestamptz),
  b2c.write_team_revenue(), b2c.trusted_device_days(), b2c.in_my_team(uuid) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
