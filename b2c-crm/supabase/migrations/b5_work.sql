-- B2C CRM b5: the counsellor's work (spec B5, B8). Staging first.
--   activities, tasks, calls, saved_views
--   set_stage()    Eduwit stages: sub-stage required, forward by default, required fields, next follow-up, Lost → pool (B5.2, B6.4)
--   call_tap() / call_log()   phone dialler flow with a required log, auto stage moves, suggested next task (B8.4)
--   tasks          follow-ups: add, done (asks for the next one), snooze, reschedule; reminders and escalation (B8.2, B8.7)
--   contacts       add, set primary; Admin edit (B8.3)
--   correct_lead() profile and interest corrections, cross-sell with a reason (B3.3, B8.3)
--   lead_list() / lead_detail() / today() / followups()   what the screens read
--   sla_tick() / reminder_tick()   the minute jobs

create table if not exists b2c.activities (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  kind text not null,          -- handoff, assignment, stage, call, whatsapp, email, note, coaching, reenquiry, reengaged, system, contact, correction, application, enrollment, programme_shared
  direction text check (direction in ('in', 'out')),
  outcome text,
  duration_s int,
  body text,
  meta jsonb not null default '{}'::jsonb,
  internal boolean not null default false,
  actor_id uuid,
  at timestamptz not null default now()
);
create index if not exists activities_lead_at on b2c.activities (lead_id, at desc);
create index if not exists activities_kind_at on b2c.activities (kind, at desc);

create table if not exists b2c.tasks (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  owner_id uuid references b2c.users (user_id),
  kind text not null default 'call' check (kind in ('call', 'whatsapp', 'email', 'document', 'followup', 'qualify')),
  title text not null,
  note text,
  due_at timestamptz not null,
  status text not null default 'open' check (status in ('open', 'done', 'cancelled')),
  done_at timestamptz,
  outcome text,
  suggested boolean not null default false,
  source text,
  reminded_at timestamptz,
  overdue_alerted_at timestamptz,
  escalated_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists tasks_owner_due on b2c.tasks (owner_id, status, due_at);
create index if not exists tasks_lead on b2c.tasks (lead_id, status);

create table if not exists b2c.calls (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  user_id uuid not null references b2c.users (user_id),
  provider text not null default 'manual',
  number text not null,
  tapped_at timestamptz not null default now(),
  logged_at timestamptz,
  outcome text check (outcome in ('connected', 'no_answer', 'busy', 'switched_off', 'wrong_number', 'call_back')),
  duration_s int,
  note text,
  unlogged_flagged_at timestamptz,
  provider_ref text,
  recording_url text
);
create index if not exists calls_lead on b2c.calls (lead_id, tapped_at desc);
create index if not exists calls_unlogged on b2c.calls (tapped_at) where logged_at is null;

create table if not exists b2c.saved_views (
  id bigint generated always as identity primary key,
  owner_id uuid references b2c.users (user_id),     -- null = standard view
  role text,                                        -- standard views: which interface shows them
  name text not null,
  filters jsonb not null default '{}'::jsonb,       -- {"all":[{field,op,value}], "any":[…], "search":…}
  columns jsonb not null default '[]'::jsonb,
  sort jsonb not null default '{"field":"next_task_due_at","dir":"asc"}'::jsonb,
  group_by text,
  layout text not null default 'list' check (layout in ('list', 'kanban')),
  is_standard boolean not null default false,
  is_default boolean not null default false,
  shared_with_role text,
  position int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $d$
declare t text;
begin
  foreach t in array array['activities', 'tasks', 'calls', 'saved_views'] loop
    execute format('alter table b2c.%I enable row level security', t);
    execute format('grant select on b2c.%I to authenticated', t);
  end loop;
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'activities' and policyname = 'who may see') then
    create policy "who may see" on b2c.activities for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "who may see" on b2c.tasks for select to authenticated using ((select b2c.can_see(lead_id)) or owner_id = (select b2c.uid()));
    create policy "who may see" on b2c.calls for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "own or standard" on b2c.saved_views for select to authenticated
      using ((select b2c.is_staff()) and (owner_id = (select b2c.uid()) or is_standard or shared_with_role = (select b2c.my_role())));
  end if;
end $d$;

insert into b2c.saved_views (name, role, filters, sort, is_standard, position)
select n, r, f::jsonb, s::jsonb, true, p from (values
  ('Due now', 'sales', '{"all":[{"field":"next_task_due_at","op":"lte_now"}]}', '{"field":"next_task_due_at","dir":"asc"}', 1),
  ('New for me', 'sales', '{"all":[{"field":"stage_id","op":"eq","value":1}]}', '{"field":"assigned_at","dir":"desc"}', 2),
  ('Hot', 'sales', '{"all":[{"field":"temperature","op":"eq","value":"hot"}]}', '{"field":"next_task_due_at","dir":"asc"}', 3),
  ('Applicants', 'sales', '{"all":[{"field":"stage_id","op":"in","value":[7,8]}]}', '{"field":"stage_changed_at","dir":"desc"}', 4),
  ('Waiting for documents', 'sales', '{"all":[{"field":"sub_stage","op":"in","value":["Awaiting documents","Partial","Verification query"]}]}', '{"field":"next_task_due_at","dir":"asc"}', 5),
  ('All mine', 'sales', '{}', '{"field":"assigned_at","dir":"desc"}', 6),
  ('Not worked yet', 'sales', '{"all":[{"field":"contact_attempts","op":"eq","value":0},{"field":"stage_id","op":"eq","value":1}]}', '{"field":"assigned_at","dir":"asc"}', 7),
  ('All B2C leads', 'workspace', '{}', '{"field":"handed_off_at","dir":"desc"}', 1),
  ('Sales lane', 'workspace', '{"all":[{"field":"status","op":"eq","value":"active"}]}', '{"field":"handed_off_at","dir":"desc"}', 2),
  ('Nurture pool', 'workspace', '{"all":[{"field":"status","op":"eq","value":"pool"}]}', '{"field":"pool_entered_at","dir":"desc"}', 3),
  ('Unassigned', 'workspace', '{"all":[{"field":"status","op":"eq","value":"active"},{"field":"owner_id","op":"is_null"}]}', '{"field":"handed_off_at","dir":"asc"}', 4),
  ('SLA breaches', 'workspace', '{"all":[{"field":"sla_breached_at","op":"not_null"},{"field":"first_contacted_at","op":"is_null"}]}', '{"field":"sla_due_at","dir":"asc"}', 5),
  ('Partner-barred', 'workspace', '{"all":[{"field":"partner_bar_reason","op":"not_null"}]}', '{"field":"handed_off_at","dir":"desc"}', 6),
  ('Enrolled', 'workspace', '{"all":[{"field":"stage_id","op":"eq","value":9}]}', '{"field":"stage_changed_at","dir":"desc"}', 7)
) v(n, r, f, s, p)
where not exists (select 1 from b2c.saved_views where is_standard);

-- ---------- helpers ----------
/* The signed-in person may work this lead: their own lead, or Admin / sales head. */
create or replace function b2c.require_lead(p_lead bigint) returns uuid language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads');
begin
  if b2c.my_role() in ('admin', 'sales_head') then return me; end if;
  if not exists (select 1 from b2c.leads_state s where s.lead_id = p_lead and s.owner_id = me and s.deleted_at is null) then
    raise exception 'not your lead' using errcode = '42501';
  end if;
  return me;
end $f$;

create or replace function b2c.add_task(p_lead bigint, p_owner uuid, p_kind text, p_title text, p_due timestamptz, p_note text default null,
                                        p_suggested boolean default false, p_source text default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare v bigint;
begin
  if p_due is null then raise exception 'a follow-up needs a date and time'; end if;
  insert into b2c.tasks (lead_id, owner_id, kind, title, note, due_at, suggested, source, created_by)
  values (p_lead, p_owner, coalesce(p_kind, 'call'), coalesce(nullif(trim(p_title), ''), 'Follow up'), p_note, p_due, p_suggested, p_source, b2c.uid())
  returning id into v;
  update b2c.leads_state set next_task_due_at = (select min(t.due_at) from b2c.tasks t where t.lead_id = p_lead and t.status = 'open'), updated_at = now()
   where lead_id = p_lead;
  return v;
end $f$;

create or replace function b2c.refresh_next_task(p_lead bigint) returns timestamptz language plpgsql security definer set search_path = '' as $f$
declare v timestamptz;
begin
  select min(due_at) into v from b2c.tasks where lead_id = p_lead and status = 'open';
  update b2c.leads_state set next_task_due_at = v, updated_at = now() where lead_id = p_lead and next_task_due_at is distinct from v;
  return v;
end $f$;

-- ---------- stages ----------
create or replace function b2c.set_stage(p_lead bigint, p_stage smallint, p_sub text, p_comment text default null,
                                         p_next_due timestamptz default null, p_next_kind text default 'call', p_next_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  me uuid := b2c.require_lead(p_lead);
  s b2c.leads_state; st b2c.stages; cur b2c.stages; sub b2c.sub_stages; r jsonb; req text; v_override boolean := false; v_set jsonb;
begin
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  if s.status <> 'active' then raise exception 'this lead is not in active sales'; end if;
  select * into st from b2c.stages where id = p_stage and active;
  if st.id is null then raise exception 'unknown stage'; end if;
  select * into sub from b2c.sub_stages where stage_id = p_stage and name = p_sub and active;
  if sub.id is null then raise exception 'choose a sub-stage for %', st.name; end if;
  if sub.comment_required and length(coalesce(trim(p_comment), '')) < 3 then raise exception 'add a comment for "%"', p_sub; end if;
  select * into cur from b2c.stages where id = s.stage_id;
  if cur.id is not null and st.rank < cur.rank and not st.reachable_from_any then
    if b2c.my_role() not in ('admin', 'sales_head') then raise exception 'moving back from % to % needs the Admin', cur.name, st.name; end if;
    if length(coalesce(trim(p_comment), '')) < 3 then raise exception 'give a reason for moving back'; end if;
    v_override := true;
  end if;
  if p_stage not in (9, 10) and p_next_due is null then raise exception 'set the next follow-up'; end if;
  select record into r from b2c.lead_records where lead_id = p_lead;
  for req in select jsonb_array_elements_text(st.required) loop
    if req = 'call_attempt' and not exists (select 1 from b2c.calls c where c.lead_id = p_lead and c.logged_at is not null) then
      raise exception 'log a call attempt first';
    elsif req = 'contact' and not exists (select 1 from b2c.calls c where c.lead_id = p_lead and c.outcome = 'connected')
                          and not exists (select 1 from b2c.activities a where a.lead_id = p_lead and a.kind = 'whatsapp' and a.direction = 'in') then
      raise exception 'log a connected call or an inbound reply first';
    elsif req = 'profile' and (coalesce(r -> 'interest' ->> 'course', '') = '' or coalesce(r -> 'education' ->> 'highest_qualification', '') = ''
                               or coalesce(r -> 'interest' ->> 'enrollment_timeline', '') = '')
          and not exists (select 1 from b2c.outbox o where o.lead_id = p_lead and o.kind = 'update' and o.status in ('queued', 'sending')
                           and o.body -> 'set' ?& array['course', 'highest_qualification', 'enrollment_timeline']) then
      raise exception 'record the course, qualification and timeline first';
    elsif req = 'programme_shared' and not exists (select 1 from b2c.activities a where a.lead_id = p_lead and a.kind = 'programme_shared') then
      raise exception 'share or explain at least one programme first (from Programme fit)';
    elsif req = 'application' and not exists (select 1 from b2c.applications a where a.lead_id = p_lead) then
      raise exception 'record the application first';
    elsif req = 'checklist' and not exists (select 1 from b2c.applications a where a.lead_id = p_lead and a.checklist <> '{}'::jsonb) then
      raise exception 'update the document checklist first';
    elsif req = 'enrollment' and not exists (select 1 from b2c.enrollments e where e.lead_id = p_lead and e.status in ('reported', 'verified')) then
      raise exception 'record the enrolment (fee, date and proof) first';
    end if;
  end loop;

  update b2c.leads_state set stage_id = p_stage, sub_stage = p_sub, stage_comment = nullif(trim(p_comment), ''), stage_changed_at = now(),
         last_activity_at = now(), updated_at = now()
   where lead_id = p_lead;
  insert into b2c.activities (lead_id, kind, body, meta, actor_id)
  values (p_lead, 'stage', st.name || ' · ' || p_sub || coalesce(': ' || nullif(trim(p_comment), ''), ''),
          jsonb_build_object('from', cur.name, 'to', st.name, 'sub_stage', p_sub, 'override', v_override), me);
  v_set := jsonb_build_object('stage', st.canon, 'sub_stage', left(p_sub, 80), 'stage_changed_at', now(),
                              'b2c_stage', st.name, 'b2c_sub_stage', p_sub, 'b2c_stage_comment', nullif(trim(p_comment), ''));

  if p_stage = 10 then
    update b2c.tasks set status = 'cancelled', done_at = now(), outcome = 'lead lost' where lead_id = p_lead and status = 'open';
    update b2c.assignments set ended_at = now(), end_reason = 'lost' where lead_id = p_lead and ended_at is null;
    update b2c.leads_state set
      status = case when sub.returns_to_pool then 'pool' else 'closed' end,
      closed_at = case when sub.returns_to_pool then null else now() end,
      closed_reason = case when sub.returns_to_pool then null else 'lost: ' || p_sub end,
      lost_by = 'counsellor', lost_by_user = s.owner_id, previous_owner_id = s.owner_id, owner_id = null,
      pool_entered_at = case when sub.returns_to_pool then now() end, pool_reason = case when sub.returns_to_pool then 'counsellor_lost' end,
      journey = sub.journey, first_message_due_at = case when sub.returns_to_pool then now() + make_interval(days => coalesce(sub.first_message_days, 30)) end,
      hot = false, next_task_due_at = null, sla_due_at = null
     where lead_id = p_lead;
    v_set := v_set || jsonb_build_object('lost_reason', p_sub, 'lost_at', now(), 'owner_user_id', null, 'owner_name', null, 'next_task_due_at', null);
  elsif p_next_due is not null then
    perform b2c.add_task(p_lead, coalesce(s.owner_id, me), p_next_kind, coalesce(p_next_note, 'Follow up after ' || st.name), p_next_due, null, false, 'stage');
    v_set := v_set || jsonb_build_object('next_task_due_at', b2c.refresh_next_task(p_lead));
  end if;
  perform b2c.queue_update(p_lead, v_set, false);
  perform b2c.queue_event('b2ccrm.stage_changed', p_lead, jsonb_build_object('stage', st.canon, 'b2c_stage', st.name, 'b2c_sub_stage', p_sub,
                          'comment', nullif(trim(p_comment), ''), 'canonical_stage', st.canon), false);
  return jsonb_build_object('stage', st.name, 'sub_stage', p_sub, 'canonical', st.canon,
                            'pool', p_stage = 10 and sub.returns_to_pool, 'closed', p_stage = 10 and not sub.returns_to_pool);
end $f$;

-- ---------- calling (B8.4) ----------
create or replace function b2c.call_tap(p_lead bigint, p_contact bigint default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v_num text; v_id bigint;
begin
  select value into v_num from b2c.lead_contacts
   where lead_id = p_lead and kind = 'phone' and removed_at is null and (id = p_contact or (p_contact is null and primary_call))
   order by (id = p_contact) desc nulls last limit 1;
  if v_num is null then raise exception 'this lead has no phone number'; end if;
  insert into b2c.calls (lead_id, user_id, number) values (p_lead, me, v_num) returning id into v_id;
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (me, 'call_tap', p_lead, jsonb_build_object('call_id', v_id));
  return jsonb_build_object('call_id', v_id, 'number', v_num, 'tel', 'tel:+' || b2c.norm_phone(v_num));
end $f$;

/* The next step a call outcome suggests (B8.4): no answer → retry in 3 h; 3 no-answers in 48 h → a WhatsApp template. */
create or replace function b2c.call_suggestion(p_lead bigint, p_outcome text) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_na int;
begin
  select count(*) into v_na from b2c.calls where lead_id = p_lead and outcome in ('no_answer', 'busy', 'switched_off') and logged_at > now() - interval '48 hours';
  return case
    when p_outcome in ('no_answer', 'busy', 'switched_off') and v_na >= 2 then jsonb_build_object('kind', 'whatsapp', 'in_minutes', 30, 'note', 'Three tries without an answer: send a WhatsApp template')
    when p_outcome in ('no_answer', 'busy', 'switched_off') then jsonb_build_object('kind', 'call', 'in_minutes', 180, 'note', 'Retry the call')
    when p_outcome = 'call_back' then jsonb_build_object('kind', 'call', 'in_minutes', 120, 'note', 'Call back as asked')
    when p_outcome = 'connected' then jsonb_build_object('kind', 'call', 'in_minutes', 1440, 'note', 'Follow-up call')
    when p_outcome = 'wrong_number' then jsonb_build_object('kind', 'whatsapp', 'in_minutes', 60, 'note', 'Check the number on WhatsApp or ask for another')
    else jsonb_build_object('kind', 'call', 'in_minutes', 1440, 'note', 'Follow up') end;
end $f$;

create or replace function b2c.call_log(p_call bigint, p_outcome text, p_duration_s int, p_note text, p_next_due timestamptz,
                                        p_next_kind text default 'call', p_next_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare c b2c.calls; s b2c.leads_state; me uuid; v_attempt boolean; v_new_stage smallint; v_new_sub text; v_label text; v_set jsonb := '{}'::jsonb;
begin
  select * into c from b2c.calls where id = p_call for update;
  if c.id is null then raise exception 'no such call'; end if;
  me := b2c.require_lead(c.lead_id);
  if c.logged_at is not null then raise exception 'this call is already logged'; end if;
  if p_outcome not in ('connected', 'no_answer', 'busy', 'switched_off', 'wrong_number', 'call_back') then raise exception 'choose the call outcome'; end if;
  if p_next_due is null then raise exception 'set the next follow-up'; end if;
  v_label := case p_outcome when 'connected' then 'Connected' when 'no_answer' then 'No answer' when 'busy' then 'Busy' when 'switched_off' then 'Switched off'
                            when 'wrong_number' then 'Wrong number' else 'Call back requested' end;
  update b2c.calls set logged_at = now(), outcome = p_outcome, duration_s = case when p_outcome = 'connected' then greatest(coalesce(p_duration_s, 0), 0) else 0 end,
         note = left(p_note, 2000) where id = p_call;
  select * into s from b2c.leads_state where lead_id = c.lead_id for update;
  v_attempt := true;
  update b2c.leads_state set contact_attempts = contact_attempts + 1,
         first_contacted_at = coalesce(first_contacted_at, c.tapped_at), last_contacted_at = greatest(coalesce(last_contacted_at, c.tapped_at), c.tapped_at),
         last_activity_at = now(), sla_met_at = coalesce(sla_met_at, case when sla_due_at is not null then now() end), updated_at = now()
   where lead_id = c.lead_id;
  -- automatic moves (B5.2)
  if s.stage_id = 1 and p_outcome in ('no_answer', 'busy', 'switched_off', 'wrong_number', 'call_back') then
    v_new_stage := 2; v_new_sub := case p_outcome when 'call_back' then 'Call back requested' else v_label end;
  elsif s.stage_id in (1, 2) and p_outcome = 'connected' then
    v_new_stage := 3; v_new_sub := 'Spoke briefly';
  end if;
  if v_new_stage is not null then
    update b2c.leads_state set stage_id = v_new_stage, sub_stage = v_new_sub, stage_changed_at = now() where lead_id = c.lead_id;
    insert into b2c.activities (lead_id, kind, body, meta, actor_id)
    values (c.lead_id, 'stage', (select name from b2c.stages where id = v_new_stage) || ' · ' || v_new_sub || ' (automatic, from the call)',
            jsonb_build_object('auto', true, 'call_id', p_call), me);
    v_set := jsonb_build_object('stage', (select canon from b2c.stages where id = v_new_stage), 'sub_stage', v_new_sub, 'stage_changed_at', now(),
                                'b2c_stage', (select name from b2c.stages where id = v_new_stage), 'b2c_sub_stage', v_new_sub);
  end if;
  insert into b2c.activities (lead_id, kind, direction, outcome, duration_s, body, meta, actor_id, at)
  values (c.lead_id, 'call', 'out', p_outcome, case when p_outcome = 'connected' then p_duration_s else 0 end,
          'Call: ' || v_label || coalesce(' · ' || nullif(trim(p_note), ''), ''), jsonb_build_object('call_id', p_call), me, c.tapped_at);
  -- the call that was the open first-call task is done
  update b2c.tasks set status = 'done', done_at = now(), outcome = v_label
   where id = (select t.id from b2c.tasks t where t.lead_id = c.lead_id and t.status = 'open' and t.kind = 'call' order by t.due_at limit 1);
  perform b2c.add_task(c.lead_id, coalesce(s.owner_id, me), coalesce(p_next_kind, 'call'),
                       coalesce(p_next_note, (b2c.call_suggestion(c.lead_id, p_outcome) ->> 'note')), p_next_due, null, false, 'call_log');
  perform b2c.queue_activity(c.lead_id, 'call', c.tapped_at, p_outcome, case when p_outcome = 'connected' then p_duration_s else 0 end, p_note);
  perform b2c.queue_update(c.lead_id, v_set || jsonb_build_object('next_task_due_at', b2c.refresh_next_task(c.lead_id)), false);
  return jsonb_build_object('logged', true, 'moved_to', (select name from b2c.stages where id = v_new_stage), 'sub_stage', v_new_sub,
                            'suggestion', b2c.call_suggestion(c.lead_id, p_outcome));
end $f$;

-- ---------- follow-ups ----------
create or replace function b2c.task_add(p_lead bigint, p_kind text, p_title text, p_due timestamptz, p_note text default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v bigint;
begin
  v := b2c.add_task(p_lead, coalesce((select owner_id from b2c.leads_state where lead_id = p_lead), me), p_kind, p_title, p_due, p_note, false, 'manual');
  perform b2c.queue_update(p_lead, jsonb_build_object('next_task_due_at', b2c.refresh_next_task(p_lead)), false);
  return v;
end $f$;

/* Done asks for the outcome and the next follow-up (B8.2). */
create or replace function b2c.task_done(p_task bigint, p_outcome text, p_next_due timestamptz, p_next_kind text default 'call', p_next_note text default null)
returns void language plpgsql security definer set search_path = '' as $f$
declare t b2c.tasks; me uuid;
begin
  select * into t from b2c.tasks where id = p_task for update;
  if t.id is null or t.status <> 'open' then raise exception 'this follow-up is not open'; end if;
  me := b2c.require_lead(t.lead_id);
  if p_next_due is null and exists (select 1 from b2c.leads_state where lead_id = t.lead_id and status = 'active' and coalesce(stage_id, 1) not in (9, 10)) then
    raise exception 'set the next follow-up';
  end if;
  update b2c.tasks set status = 'done', done_at = now(), outcome = left(p_outcome, 300) where id = p_task;
  insert into b2c.activities (lead_id, kind, body, actor_id) values (t.lead_id, 'note', 'Done: ' || t.title || coalesce(' · ' || p_outcome, ''), me);
  if p_next_due is not null then perform b2c.add_task(t.lead_id, t.owner_id, p_next_kind, coalesce(p_next_note, 'Follow up'), p_next_due, null, false, 'task_done'); end if;
  update b2c.leads_state set last_activity_at = now() where lead_id = t.lead_id;
  perform b2c.queue_update(t.lead_id, jsonb_build_object('next_task_due_at', b2c.refresh_next_task(t.lead_id)), false);
end $f$;

create or replace function b2c.task_move(p_task bigint, p_due timestamptz) returns void language plpgsql security definer set search_path = '' as $f$
declare t b2c.tasks;
begin
  select * into t from b2c.tasks where id = p_task for update;
  if t.id is null or t.status <> 'open' then raise exception 'this follow-up is not open'; end if;
  perform b2c.require_lead(t.lead_id);
  if p_due is null or p_due < now() - interval '1 minute' then raise exception 'pick a time in the future'; end if;
  update b2c.tasks set due_at = p_due, reminded_at = null, overdue_alerted_at = null, escalated_at = null where id = p_task;
  perform b2c.queue_update(t.lead_id, jsonb_build_object('next_task_due_at', b2c.refresh_next_task(t.lead_id)), false);
end $f$;

create or replace function b2c.add_note(p_lead bigint, p_body text, p_internal boolean default false) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare me uuid; v bigint;
begin
  if p_internal then me := b2c.require('settings'); else me := b2c.require_lead(p_lead); end if;   -- coaching notes: Admin
  if length(coalesce(trim(p_body), '')) = 0 then raise exception 'write the note'; end if;
  insert into b2c.activities (lead_id, kind, body, internal, actor_id) values (p_lead, case when p_internal then 'coaching' else 'note' end, left(p_body, 4000), p_internal, me)
  returning id into v;
  update b2c.leads_state set last_activity_at = now() where lead_id = p_lead;
  if not p_internal then perform b2c.queue_activity(p_lead, 'note', now(), null, null, p_body); end if;
  return v;
end $f$;

-- ---------- contacts (B8.3) ----------
create or replace function b2c.add_contact(p_lead bigint, p_kind text, p_value text, p_label text, p_primary text[] default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v_norm text; v_id bigint; v_dup bigint;
begin
  if p_kind not in ('phone', 'email') then raise exception 'a phone number or an email'; end if;
  v_norm := case when p_kind = 'phone' then b2c.norm_phone(p_value) else lower(trim(p_value)) end;
  if p_kind = 'phone' and (v_norm is null or length(v_norm) not between 11 and 13) then raise exception 'enter a valid phone number'; end if;
  if p_kind = 'email' and v_norm !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'enter a valid email'; end if;
  select c.lead_id into v_dup from b2c.lead_contacts c where c.value_norm = v_norm and c.lead_id <> p_lead and c.removed_at is null limit 1;
  insert into b2c.lead_contacts (lead_id, kind, value, value_norm, label, origin, added_by)
  values (p_lead, p_kind, trim(p_value), v_norm, coalesce(p_label, 'alternate'), case when b2c.my_role() = 'admin' then 'admin' else 'counsellor' end, me)
  on conflict (lead_id, kind, value_norm) do nothing
  returning id into v_id;
  if v_id is null then raise exception 'this lead already has that %', p_kind; end if;
  if cardinality(coalesce(p_primary, '{}')) > 0 then perform b2c.set_primary(v_id, p_primary); end if;
  insert into b2c.field_history (lead_id, field, new_value, kind, actor_id) values (p_lead, p_kind, to_jsonb(trim(p_value)), 'contact', me);
  perform b2c.queue_event('b2ccrm.contact_added', p_lead, jsonb_build_object('kind', p_kind, 'value', v_norm, 'label', coalesce(p_label, 'alternate'),
                          'primary_for', to_jsonb(coalesce(p_primary, '{}'))), false);
  return jsonb_build_object('id', v_id, 'duplicate_of_lead', v_dup);
end $f$;

create or replace function b2c.set_primary(p_contact bigint, p_for text[]) returns void language plpgsql security definer set search_path = '' as $f$
declare c b2c.lead_contacts; f text;
begin
  select * into c from b2c.lead_contacts where id = p_contact and removed_at is null;
  if c.id is null then raise exception 'no such contact detail'; end if;
  perform b2c.require_lead(c.lead_id);
  foreach f in array p_for loop
    if f = 'call' and c.kind = 'phone' then
      update b2c.lead_contacts set primary_call = false where lead_id = c.lead_id and primary_call;
      update b2c.lead_contacts set primary_call = true where id = c.id;
    elsif f = 'whatsapp' and c.kind = 'phone' then
      update b2c.lead_contacts set primary_wa = false where lead_id = c.lead_id and primary_wa;
      update b2c.lead_contacts set primary_wa = true where id = c.id;
    elsif f = 'email' and c.kind = 'email' then
      update b2c.lead_contacts set primary_email = false where lead_id = c.lead_id and primary_email;
      update b2c.lead_contacts set primary_email = true where id = c.id;
    else raise exception 'a % cannot be primary for %', c.kind, f;
    end if;
  end loop;
end $f$;

/* Admin only: change or remove an existing contact detail (the guard trigger enforces it too). */
create or replace function b2c.admin_edit_contact(p_contact bigint, p_value text, p_remove boolean default false) returns void
language plpgsql security definer set search_path = '' as $f$
declare c b2c.lead_contacts; me uuid := b2c.require('settings');
begin
  select * into c from b2c.lead_contacts where id = p_contact;
  if c.id is null then raise exception 'no such contact detail'; end if;
  if p_remove then
    update b2c.lead_contacts set removed_at = now(), primary_call = false, primary_wa = false, primary_email = false where id = c.id;
  else
    update b2c.lead_contacts set value = trim(p_value), value_norm = case when c.kind = 'phone' then b2c.norm_phone(p_value) else lower(trim(p_value)) end where id = c.id;
  end if;
  insert into b2c.field_history (lead_id, field, old_value, new_value, kind, reason, actor_id)
  values (c.lead_id, c.kind, to_jsonb(c.value), case when p_remove then null else to_jsonb(trim(p_value)) end, 'admin_edit', case when p_remove then 'removed' end, me);
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (me, 'contact_edit', c.lead_id, jsonb_build_object('contact', c.id, 'removed', p_remove));
  if c.origin = 'intake' and not p_remove then
    perform b2c.queue_update(c.lead_id, jsonb_build_object(case when c.kind = 'email' then 'email' else 'alternate_phone' end, trim(p_value)), false);
  end if;
end $f$;

-- ---------- corrections and cross-sell ----------
/* Profile and interest fields a counsellor may correct (B3.3); contact fields go through contacts. */
create or replace function b2c.correctable_fields() returns text[] language sql immutable set search_path = '' as $f$
  select array['name', 'city', 'state', 'country', 'preferred_language', 'enquirer_relation', 'guardian_name', 'guardian_phone',
               'highest_qualification', 'current_study', 'academic_score_pct', 'work_experience_years', 'current_job_role',
               'course', 'specialization', 'university', 'programme_level', 'study_mode', 'field_of_interest',
               'enrollment_timeline', 'annual_budget_inr', 'preferred_counseling_time', 'other_courses']
$f$;

create or replace function b2c.correct_lead(p_lead bigint, p_fields jsonb, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); k text; r jsonb; v_old jsonb; v_cross boolean; v_set jsonb := '{}'::jsonb; v_group text;
begin
  if p_fields is null or p_fields = '{}'::jsonb then return '{}'::jsonb; end if;
  select record into r from b2c.lead_records where lead_id = p_lead;
  v_cross := p_fields ?| array['course', 'specialization', 'university', 'programme_level', 'study_mode'];
  if v_cross and length(coalesce(trim(p_reason), '')) < 3 then raise exception 'give a reason for changing the programme or university'; end if;
  for k in select jsonb_object_keys(p_fields) loop
    if not k = any (b2c.correctable_fields()) and not (k = 'email' and b2c.my_role() = 'admin') then raise exception 'you cannot change %', k; end if;
    v_group := case when k in ('name', 'city', 'state', 'country', 'preferred_language', 'enquirer_relation', 'guardian_name', 'guardian_phone', 'email') then 'student'
                    when k in ('highest_qualification', 'current_study', 'academic_score_pct', 'work_experience_years', 'current_job_role') then 'education'
                    else 'interest' end;
    v_old := r -> v_group -> k;
    continue when v_old is not distinct from p_fields -> k;
    insert into b2c.field_history (lead_id, field, old_value, new_value, kind, reason, actor_id)
    values (p_lead, k, v_old, p_fields -> k,
            case when k in ('course', 'specialization', 'university', 'programme_level', 'study_mode') then 'cross_sell'
                 when b2c.my_role() = 'admin' then 'admin_edit' else 'human_correction' end, p_reason, me);
    v_set := v_set || jsonb_build_object(k, p_fields -> k);
  end loop;
  if v_set <> '{}'::jsonb then
    perform b2c.queue_update(p_lead, v_set, false);
    insert into b2c.activities (lead_id, kind, body, meta, actor_id)
    values (p_lead, 'correction', case when v_cross then 'Interest changed (cross-sell)' else 'Profile corrected' end || coalesce(': ' || p_reason, ''), v_set, me);
  end if;
  return jsonb_build_object('changed', v_set);
end $f$;

-- ---------- what the screens read ----------
/* The changes waiting for the next sync, so a person always sees their own latest edit (decision K1). */
create or replace function b2c.pending_set(p_lead bigint) returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from (
    select e.key k, e.value v, row_number() over (partition by e.key order by o.occurred_at desc) rn
      from b2c.outbox o, jsonb_each(o.body -> 'set') e
     where o.lead_id = p_lead and o.kind = 'update' and o.status in ('queued', 'sending')) x where rn = 1
$f$;

/* Filtered, sorted, paged lead list for a view (B8.2, B10.1). Fields and operators are whitelisted. */
create or replace function b2c.lead_list(p jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_role text := b2c.my_role(); me uuid := b2c.uid(); w text := 'true'; c jsonb; v_field text; v_op text; v_sql text; v_rows jsonb; v_total int;
  v_any text; f jsonb := coalesce(p -> 'filters', '{}'); v_sort text; v_dir text; v_limit int := least(coalesce((p ->> 'limit')::int, 50), 500); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0);
  allowed text[] := array['lead_id','name','phone','email','city','state','language','course','specialization','university','programme_level','study_mode',
    'qualification','source','campaign','lead_status','partner_consent_state','marketing_consent','opted_out','lane','status','handoff_reason','cause',
    'partner_bar_reason','owner_id','owner_name','assigned_at','stage_id','stage','canonical_stage','sub_stage','stage_changed_at','hot','temperature','score',
    'next_task_due_at','first_contacted_at','last_contacted_at','contact_attempts','last_activity_at','sla_due_at','sla_met_at','sla_breached_at',
    'pool_entered_at','pool_reason','journey','lost_by','reengaged_at','flagged','reenquired_at','tags','is_test','handed_off_at','updated_at','closed_at'];
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_role = 'counsellor' then w := format('owner_id = %L', me); end if;
  w := w || case when coalesce((p ->> 'deleted')::boolean, false) then ' and deleted_at is not null' else ' and deleted_at is null' end;
  if not coalesce((p ->> 'include_test')::boolean, v_role = 'admin') then w := w || ' and not is_test'; end if;
  for c in select * from jsonb_array_elements(coalesce(f -> 'all', '[]')) loop
    w := w || ' and ' || b2c.filter_sql(c, allowed);
  end loop;
  if jsonb_array_length(coalesce(f -> 'any', '[]')) > 0 then
    select string_agg(b2c.filter_sql(x, allowed), ' or ') into v_any from jsonb_array_elements(f -> 'any') x;
    w := w || ' and (' || v_any || ')';
  end if;
  if coalesce(trim(p ->> 'search'), '') <> '' then
    w := w || format(' and (name ilike %1$L or email ilike %1$L or b2c.norm_phone(phone) like %2$L or lead_id::text = %3$L
                       or exists (select 1 from b2c.lead_contacts lc where lc.lead_id = v.lead_id and lc.value_norm like %2$L)
                       or exists (select 1 from b2c.applications ap where ap.lead_id = v.lead_id and ap.application_ref ilike %1$L))',
                     '%' || trim(p ->> 'search') || '%', '%' || coalesce(nullif(regexp_replace(p ->> 'search', '\D', '', 'g'), ''), '~none~') || '%', trim(p ->> 'search'));
  end if;
  v_sort := coalesce(p -> 'sort' ->> 'field', 'next_task_due_at');
  if not v_sort = any (allowed) then v_sort := 'next_task_due_at'; end if;
  v_dir := case when lower(coalesce(p -> 'sort' ->> 'dir', 'asc')) = 'desc' then 'desc' else 'asc' end;
  v_sql := format('select count(*) over () total, to_jsonb(v) - ''providers'' - ''handling'' as row from b2c.leads_v v where %s order by %I %s nulls last, lead_id desc limit %s offset %s',
                  w, v_sort, v_dir, v_limit, v_offset);
  execute format('select coalesce(max(total), 0), coalesce(jsonb_agg(row), ''[]'') from (%s) q', v_sql) into v_total, v_rows;
  return jsonb_build_object('total', v_total, 'rows', v_rows);
end $f$;

create or replace function b2c.filter_sql(c jsonb, allowed text[]) returns text language plpgsql stable set search_path = '' as $f$
declare fld text := c ->> 'field'; op text := c ->> 'op'; val jsonb := c -> 'value';
begin
  if not fld = any (allowed) then raise exception 'cannot filter on %', fld; end if;
  return case op
    when 'eq' then format('%I::text = %L', fld, val #>> '{}')
    when 'neq' then format('%I::text is distinct from %L', fld, val #>> '{}')
    when 'in' then format('%I::text = any (%L::text[])', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'not_in' then format('not (%I::text = any (%L::text[]))', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'contains' then format('%I::text ilike %L', fld, '%' || (val #>> '{}') || '%')
    when 'gte' then format('%I >= %L', fld, val #>> '{}')
    when 'lte' then format('%I <= %L', fld, val #>> '{}')
    when 'is_null' then format('%I is null', fld)
    when 'not_null' then format('%I is not null', fld)
    when 'is_true' then format('%I is true', fld)
    when 'is_false' then format('%I is not true', fld)
    when 'lte_now' then format('%I <= now()', fld)
    when 'older_than_days' then format('%I < now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'within_days' then format('%I >= now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'has_tag' then format('%L = any (tags)', val #>> '{}')
    else 'false' end;
end $f$;

/* Everything the lead screen shows (B8.3). */
create or replace function b2c.lead_detail(p_lead bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb;
begin
  if not b2c.can_see(p_lead) then raise exception 'not allowed' using errcode = '42501'; end if;
  select jsonb_build_object(
    'lead', (select to_jsonb(x) from b2c.leads_v x where x.lead_id = p_lead),
    'record', (select r.record from b2c.lead_records r where r.lead_id = p_lead),
    'pending', b2c.pending_set(p_lead),
    'contacts', (select coalesce(jsonb_agg(to_jsonb(c) order by c.origin = 'intake' desc, c.created_at), '[]') from b2c.lead_contacts c where c.lead_id = p_lead and c.removed_at is null),
    'tasks', (select coalesce(jsonb_agg(to_jsonb(t) order by t.due_at), '[]') from b2c.tasks t where t.lead_id = p_lead and t.status = 'open'),
    'timeline', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'direction', a.direction, 'outcome', a.outcome, 'body', a.body,
                                 'internal', a.internal, 'at', a.at, 'actor', (select u.full_name from b2c.users u where u.user_id = a.actor_id), 'meta', a.meta) order by a.at desc), '[]')
                  from (select * from b2c.activities a where a.lead_id = p_lead and (not a.internal or b2c.my_role() in ('admin', 'sales_head')) order by a.at desc limit 150) a),
    'unlogged_call', (select to_jsonb(c) from b2c.calls c where c.lead_id = p_lead and c.logged_at is null and c.user_id = b2c.uid() order by c.tapped_at desc limit 1),
    'applications', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]') from b2c.applications a where a.lead_id = p_lead),
    'enrollments', (select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at), '[]') from b2c.enrollments e where e.lead_id = p_lead),
    'decision', (select to_jsonb(d) from b2c.allocation_decisions d where d.lead_id = p_lead and not d.simulated order by d.at desc limit 1),
    'consent_request', (select to_jsonb(q) from b2c.consent_requests q where q.lead_id = p_lead order by q.created_at desc limit 1),
    'history', (select coalesce(jsonb_agg(to_jsonb(h) order by h.at desc), '[]') from b2c.field_history h where h.lead_id = p_lead))
  into v;
  return v;
end $f$;

/* The counsellor's home (B8.1): queue in order, the four follow-up counts, today's numbers against target. */
create or replace function b2c.today() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads'); d0 timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
        d1 timestamptz := d0 + interval '1 day'; m0 timestamptz := date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  return jsonb_build_object(
    'queue', (select coalesce(jsonb_agg(q order by q.ord, q.due), '[]') from (
        select 1 ord, t.due_at due, jsonb_build_object('why', 'Overdue follow-up', 'task_id', t.id, 'task', t.title, 'due_at', t.due_at, 'lead', to_jsonb(v)) q
          from b2c.tasks t join b2c.leads_v v on v.lead_id = t.lead_id where t.owner_id = me and t.status = 'open' and t.due_at < now() and v.status = 'active'
        union all
        select 2, coalesce(v.sla_due_at, v.assigned_at), jsonb_build_object('why', 'New, not worked', 'lead', to_jsonb(v))
          from b2c.leads_v v where v.owner_id = me and v.status = 'active' and v.contact_attempts = 0 and v.stage_id = 1
           and not exists (select 1 from b2c.tasks t where t.lead_id = v.lead_id and t.status = 'open' and t.due_at < now())
        union all
        select 3, t.due_at, jsonb_build_object('why', 'Due today', 'task_id', t.id, 'task', t.title, 'due_at', t.due_at, 'lead', to_jsonb(v))
          from b2c.tasks t join b2c.leads_v v on v.lead_id = t.lead_id where t.owner_id = me and t.status = 'open' and t.due_at >= now() and t.due_at < d1
           and not (v.contact_attempts = 0 and v.stage_id = 1)
        union all
        select 4, v.last_activity_at, jsonb_build_object('why', 'Hot, no activity in 24 h', 'lead', to_jsonb(v))
          from b2c.leads_v v where v.owner_id = me and v.status = 'active' and v.temperature = 'hot' and coalesce(v.last_activity_at, v.assigned_at) < now() - interval '24 hours'
           and not exists (select 1 from b2c.tasks t where t.lead_id = v.lead_id and t.status = 'open' and t.due_at < d1)
      ) q),
    'counts', b2c.followup_counts(me),
    'numbers', jsonb_build_object(
      'calls', (select count(*) from b2c.calls c where c.user_id = me and c.logged_at >= d0),
      'connected', (select count(*) from b2c.calls c where c.user_id = me and c.logged_at >= d0 and c.outcome = 'connected'),
      'counselled', (select count(*) from b2c.activities a where a.actor_id = me and a.kind = 'stage' and a.at >= d0 and a.meta ->> 'to' in ('Qualified', 'Follow Up', 'Program Details Explained')),
      'applications', (select count(*) from b2c.applications a where a.created_by = me and a.created_at >= m0),
      'enrollments', (select count(*) from b2c.enrollments e where e.counsellor_id = me and e.created_at >= m0 and e.status in ('reported', 'verified')),
      'target', (select u.monthly_target from b2c.users u where u.user_id = me)),
    'me', (select jsonb_build_object('name', u.full_name, 'away_until', u.away_until, 'working_now', b2c.working_now(me, now())) from b2c.users u where u.user_id = me));
end $f$;

create or replace function b2c.followup_counts(p_user uuid) returns jsonb language sql stable security definer set search_path = '' as $f$
  with d as (select date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' + interval '1 day' as d1)
  select jsonb_build_object(
    'not_worked', (select count(*) from b2c.leads_state s where s.owner_id = p_user and s.status = 'active' and s.contact_attempts = 0 and s.stage_id = 1),
    'overdue', (select count(*) from b2c.tasks t where t.owner_id = p_user and t.status = 'open' and t.due_at < now()),
    'today', (select count(*) from b2c.tasks t, d where t.owner_id = p_user and t.status = 'open' and t.due_at >= now() and t.due_at < d.d1),
    'upcoming', (select count(*) from b2c.tasks t, d where t.owner_id = p_user and t.status = 'open' and t.due_at >= d.d1))
$f$;

/* The Follow-ups page (B8.2). The Admin may pass another person (or null for everyone). */
create or replace function b2c.followups(p_bucket text, p_user uuid default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.require('work_leads'); v_user uuid; d1 timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata' + interval '1 day';
begin
  v_user := case when b2c.my_role() in ('admin', 'sales_head') then p_user else me end;
  if p_bucket = 'not_worked' then
    return (select coalesce(jsonb_agg(jsonb_build_object('lead', to_jsonb(v)) order by v.sla_due_at nulls last), '[]') from b2c.leads_v v
             where (v_user is null or v.owner_id = v_user) and v.status = 'active' and v.contact_attempts = 0 and v.stage_id = 1);
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('task', to_jsonb(t), 'lead', to_jsonb(v)) order by t.due_at), '[]')
            from b2c.tasks t join b2c.leads_v v on v.lead_id = t.lead_id
           where (v_user is null or t.owner_id = v_user) and t.status = 'open'
             and case p_bucket when 'overdue' then t.due_at < now() when 'today' then t.due_at >= now() and t.due_at < d1 else t.due_at >= d1 end);
end $f$;

create or replace function b2c.view_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v bigint := nullif(p ->> 'id', '')::bigint; v_std boolean := coalesce((p ->> 'is_standard')::boolean, false);
begin
  if not b2c.is_staff() then raise exception 'not allowed'; end if;
  if v_std and b2c.my_role() <> 'admin' then raise exception 'only the Admin publishes standard views'; end if;
  if v is null then
    insert into b2c.saved_views (owner_id, role, name, filters, columns, sort, group_by, layout, is_standard, is_default, shared_with_role)
    values (case when v_std then null else me end, p ->> 'role', p ->> 'name', coalesce(p -> 'filters', '{}'), coalesce(p -> 'columns', '[]'),
            coalesce(p -> 'sort', '{"field":"next_task_due_at","dir":"asc"}'), p ->> 'group_by', coalesce(p ->> 'layout', 'list'), v_std,
            coalesce((p ->> 'is_default')::boolean, false), p ->> 'shared_with_role')
    returning id into v;
  else
    update b2c.saved_views set name = coalesce(p ->> 'name', name), filters = coalesce(p -> 'filters', filters), columns = coalesce(p -> 'columns', columns),
           sort = coalesce(p -> 'sort', sort), group_by = p ->> 'group_by', layout = coalesce(p ->> 'layout', layout),
           is_default = coalesce((p ->> 'is_default')::boolean, is_default), shared_with_role = p ->> 'shared_with_role', updated_at = now()
     where id = v and (owner_id = me or (is_standard and b2c.my_role() = 'admin'));
  end if;
  return v;
end $f$;

-- ---------- minute jobs ----------
/* First-contact SLA breaches: red in queues, alert to the counsellor and the Admin (B8.7). */
create or replace function b2c.sla_tick() returns int language plpgsql security definer set search_path = '' as $f$
declare r record; n int := 0;
begin
  for r in select lead_id, owner_id, is_test from b2c.leads_state
            where status = 'active' and sla_due_at < now() and sla_met_at is null and sla_breached_at is null and first_contacted_at is null limit 200 loop
    update b2c.leads_state set sla_breached_at = now() where lead_id = r.lead_id;
    perform b2c.notify(r.owner_id, 'sla_breach', 'First-contact SLA breached', 'Call now.', '/s/leads/' || r.lead_id, r.lead_id, 'sla:' || r.lead_id);
    if not r.is_test then
      perform b2c.notify_admins('sla_breach', 'First-contact SLA breached', null, '/w/leads/' || r.lead_id, r.lead_id, 'sla:' || r.lead_id, true);
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

/* Reminders 10 minutes before, overdue alerts, escalation to the Admin after 2 hours, unlogged calls (B8.2, B8.4, B8.7). */
create or replace function b2c.reminder_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare f jsonb := b2c.setting('followups'); r record; a int := 0; b int := 0; c int := 0; d int := 0;
begin
  for r in select t.id, t.lead_id, t.owner_id, t.title, t.due_at, v.name from b2c.tasks t join b2c.leads_v v on v.lead_id = t.lead_id
            where t.status = 'open' and t.reminded_at is null and t.due_at <= now() + make_interval(mins => coalesce((f ->> 'reminder_minutes_before')::int, 10))
              and t.due_at > now() - interval '5 minutes' limit 500 loop
    perform b2c.notify(r.owner_id, 'reminder', 'In 10 minutes: ' || r.title, coalesce(r.name, ''), '/s/leads/' || r.lead_id, r.lead_id, 'rem:' || r.id);
    update b2c.tasks set reminded_at = now() where id = r.id; a := a + 1;
  end loop;
  for r in select t.id, t.lead_id, t.owner_id, t.title from b2c.tasks t where t.status = 'open' and t.due_at < now() and t.overdue_alerted_at is null limit 500 loop
    perform b2c.notify(r.owner_id, 'overdue', 'Overdue: ' || r.title, null, '/s/leads/' || r.lead_id, r.lead_id, 'over:' || r.id);
    update b2c.tasks set overdue_alerted_at = now() where id = r.id; b := b + 1;
  end loop;
  for r in select t.id, t.lead_id, t.title, u.full_name from b2c.tasks t left join b2c.users u on u.user_id = t.owner_id
            where t.status = 'open' and t.escalated_at is null and t.due_at < now() - make_interval(mins => coalesce((f ->> 'escalate_after_minutes')::int, 120)) limit 500 loop
    perform b2c.notify_admins('escalation', 'Missed follow-up: ' || r.title, coalesce(r.full_name, '') || ' has not done it', '/w/leads/' || r.lead_id, r.lead_id, 'esc:' || r.id, true);
    update b2c.tasks set escalated_at = now() where id = r.id; c := c + 1;
  end loop;
  for r in select x.id, x.lead_id, x.user_id from b2c.calls x where x.logged_at is null and x.unlogged_flagged_at is null
              and x.tapped_at < now() - make_interval(mins => coalesce((f ->> 'call_unlogged_minutes')::int, 10)) limit 500 loop
    perform b2c.notify(r.user_id, 'call_not_logged', 'Call not logged', 'Log the outcome of your call.', '/s/leads/' || r.lead_id, r.lead_id, 'unlogged:' || r.id);
    update b2c.calls set unlogged_flagged_at = now() where id = r.id; d := d + 1;
  end loop;
  return jsonb_build_object('reminders', a, 'overdue', b, 'escalated', c, 'unlogged', d);
end $f$;

grant execute on function b2c.set_stage(bigint, smallint, text, text, timestamptz, text, text), b2c.call_tap(bigint, bigint), b2c.call_suggestion(bigint, text),
  b2c.call_log(bigint, text, int, text, timestamptz, text, text), b2c.task_add(bigint, text, text, timestamptz, text),
  b2c.task_done(bigint, text, timestamptz, text, text), b2c.task_move(bigint, timestamptz), b2c.add_note(bigint, text, boolean),
  b2c.add_contact(bigint, text, text, text, text[]), b2c.set_primary(bigint, text[]), b2c.admin_edit_contact(bigint, text, boolean),
  b2c.correct_lead(bigint, jsonb, text), b2c.correctable_fields(), b2c.lead_list(jsonb), b2c.lead_detail(bigint), b2c.today(), b2c.followups(text, uuid),
  b2c.followup_counts(uuid), b2c.view_save(jsonb), b2c.pending_set(bigint) to authenticated;
revoke execute on function b2c.add_task(bigint, uuid, text, text, timestamptz, text, boolean, text), b2c.refresh_next_task(bigint),
  b2c.sla_tick(), b2c.reminder_tick(), b2c.filter_sql(jsonb, text[]) from public, authenticated;
grant execute on function b2c.sla_tick(), b2c.reminder_tick() to service_role;
grant all on all tables in schema b2c to service_role;
