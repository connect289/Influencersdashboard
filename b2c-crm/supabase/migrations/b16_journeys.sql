-- B2C CRM b16 (Phase 2): journeys, automated nurture (B9.4, B6.4). Staging first. Idempotent.
--   journeys, journey_versions   a draft is edited, a version is published; running leads stay on their version or move
--   journey_runs, journey_log    one journey at a time per lead; every step's outcome is kept
--   journey_enroll_tick()        pooled leads enter their journey when the first message is due (the lost sub-stage's delay)
--   journey_tick()               every minute: sends, waits, branches, scores, tags, Admin tasks, assignment, exits
-- Steps (jsonb array, each with an "id"):
--   {"type":"send","channel":"whatsapp"|"email","template":"<name>"|<id>}   {"type":"wait","days":3}|{"hours":4}|{"until":"10:00"}
--   {"type":"branch","on":"reply","classes":["positive"],"then":"<id>","else":"<id>"}   {"on":"condition","filters":{…}}   {"on":"ab","pct":50}
--   {"type":"score","delta":10}  {"type":"tag","tag":"x"}  {"type":"task","title":"…"}  {"type":"assign"}  {"type":"move","journey":"<key>"}  {"type":"exit","reason":"…"}

create table if not exists b2c.journeys (
  id bigint generated always as identity primary key,
  key text not null unique,
  name text not null,
  description text,
  trigger jsonb not null default '{"type":"pool_entry"}'::jsonb,   -- pool_entry {reasons, sub_stages} | segment {segment_id} | tag {tag} | inactive {days} | manual
  priority int not null default 100,
  allow_active_sales boolean not null default false,
  test_mode boolean not null default false,                         -- only test leads enter
  status text not null default 'draft' check (status in ('draft', 'active', 'paused', 'archived')),
  draft_steps jsonb not null default '[]'::jsonb,
  current_version int not null default 0,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists b2c.journey_versions (
  journey_id bigint not null references b2c.journeys (id),
  version int not null,
  steps jsonb not null,
  published_at timestamptz not null default now(),
  published_by uuid,
  primary key (journey_id, version)
);
create table if not exists b2c.journey_runs (
  id bigint generated always as identity primary key,
  journey_id bigint not null references b2c.journeys (id),
  version int not null,
  lead_id bigint not null,
  step_idx int not null default 0,
  step_started_at timestamptz not null default now(),
  status text not null default 'running' check (status in ('running', 'paused', 'done', 'exited')),
  next_at timestamptz not null default now(),
  entered_at timestamptz not null default now(),
  entered_by text,                              -- pool_entry, segment, tag, inactive, manual, move, test
  exited_at timestamptz,
  exit_reason text,
  is_test boolean not null default false
);
create unique index if not exists journey_runs_one_live on b2c.journey_runs (lead_id) where status in ('running', 'paused');
create index if not exists journey_runs_due on b2c.journey_runs (next_at) where status = 'running';
create index if not exists journey_runs_journey on b2c.journey_runs (journey_id, status);
create table if not exists b2c.journey_log (
  id bigint generated always as identity primary key,
  run_id bigint not null,
  lead_id bigint not null,
  step_idx int,
  step_type text,
  outcome text not null,                        -- sent, blocked, waiting, skipped, branch:then, branch:else, scored, tagged, task, assigned, moved, exited
  detail jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
create index if not exists journey_log_run on b2c.journey_log (run_id, at);
create index if not exists journey_log_at on b2c.journey_log (at, outcome);

insert into b2c.settings (key, value) values
  ('partner_lost_map', '{"budget": "lower_fee_emi", "fee": "lower_fee_emi", "emi": "lower_fee_emi", "loan": "lower_fee_emi", "eligib": "eligible_programmes",
                         "not reachable": "we_tried_to_reach_you", "unreachable": "we_tried_to_reach_you", "no answer": "we_tried_to_reach_you",
                         "not interested": "reengage_60d", "later": "monthly_update", "next year": "monthly_update", "competitor": "long_term_update",
                         "other provider": "long_term_update", "document": "fix_and_reapply", "default": "partner_lost_reengage"}')
on conflict (key) do nothing;

-- ---------- run control ----------
/* Ends the lead's running journey (opt-out, re-engagement, assignment, negative reply, manual). Returns how many ended. */
create or replace function b2c.journey_exit(p_lead bigint, p_reason text) returns int language plpgsql security definer set search_path = '' as $f$
declare n int := 0; r record;
begin
  for r in update b2c.journey_runs set status = 'exited', exited_at = now(), exit_reason = p_reason
            where lead_id = p_lead and status in ('running', 'paused') returning id, step_idx loop
    insert into b2c.journey_log (run_id, lead_id, step_idx, outcome, detail) values (r.id, p_lead, r.step_idx, 'exited', jsonb_build_object('reason', p_reason));
    n := n + 1;
  end loop;
  update b2c.leads_state set journey = null where lead_id = p_lead and journey is not null;
  return n;
end $f$;

/* Starts a journey for a lead (one at a time: a running one ends first). */
create or replace function b2c.journey_start(p_lead bigint, p_journey bigint, p_by text) returns bigint language plpgsql security definer set search_path = '' as $f$
declare j b2c.journeys; v bigint; v_test boolean := coalesce((select is_test from b2c.leads_state where lead_id = p_lead), false);
begin
  select * into j from b2c.journeys where id = p_journey;
  if j.id is null or j.current_version = 0 then raise exception 'the journey has no published version'; end if;
  if j.test_mode and not v_test then raise exception 'this journey is in test mode: test leads only'; end if;
  perform b2c.journey_exit(p_lead, 'moved');
  insert into b2c.journey_runs (journey_id, version, lead_id, entered_by, is_test) values (j.id, j.current_version, p_lead, p_by, v_test) returning id into v;
  insert into b2c.journey_log (run_id, lead_id, step_idx, outcome, detail) values (v, p_lead, 0, 'entered', jsonb_build_object('journey', j.key, 'by', p_by));
  update b2c.leads_state set journey = j.key where lead_id = p_lead;
  insert into b2c.activities (lead_id, kind, body, meta) values (p_lead, 'system', 'Nurture journey started: ' || j.name, jsonb_build_object('journey', j.key, 'run_id', v));
  perform b2c.queue_update(p_lead, jsonb_build_object('active_journey_id', j.key), false);
  return v;
end $f$;

/* Lead-level control from the Nurture page (B9.0): start or move, stop, pause, resume. */
create or replace function b2c.journey_lead(p_lead bigint, p_action text, p_journey bigint default null) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v bigint; n int;
begin
  perform b2c.require('journey_membership');
  if p_action = 'start' then
    if b2c.may_message(p_lead) is not null then raise exception 'cannot message this student: %', b2c.may_message(p_lead); end if;
    v := b2c.journey_start(p_lead, p_journey, 'manual');
    return jsonb_build_object('run_id', v);
  elsif p_action = 'stop' then
    n := b2c.journey_exit(p_lead, 'stopped by ' || coalesce(b2c.my_role(), 'staff'));
  elsif p_action = 'pause' then
    update b2c.journey_runs set status = 'paused' where lead_id = p_lead and status = 'running'; get diagnostics n = row_count;
  elsif p_action = 'resume' then
    update b2c.journey_runs set status = 'running', next_at = greatest(next_at, now()) where lead_id = p_lead and status = 'paused'; get diagnostics n = row_count;
  else
    raise exception 'unknown action';
  end if;
  return jsonb_build_object('changed', n);
end $f$;

-- ---------- editing and publishing ----------
create or replace function b2c.journey_check_steps(p_steps jsonb) returns void language plpgsql stable set search_path = '' as $f$
declare s jsonb; v_ids text[] := '{}'; t text;
begin
  if jsonb_typeof(p_steps) <> 'array' or jsonb_array_length(p_steps) = 0 then raise exception 'a journey needs at least one step'; end if;
  if jsonb_array_length(p_steps) > 60 then raise exception 'at most 60 steps'; end if;
  for s in select * from jsonb_array_elements(p_steps) loop
    if coalesce(s ->> 'id', '') = '' then raise exception 'every step needs an id'; end if;
    if s ->> 'id' = any (v_ids) then raise exception 'step id % is used twice', s ->> 'id'; end if;
    v_ids := v_ids || (s ->> 'id');
    t := s ->> 'type';
    if t not in ('send', 'wait', 'branch', 'score', 'tag', 'task', 'assign', 'move', 'exit') then raise exception 'unknown step type %', t; end if;
    if t = 'send' and (s ->> 'channel' not in ('whatsapp', 'email') or s -> 'template' is null) then raise exception 'step %: choose the channel and the template', s ->> 'id'; end if;
    if t = 'wait' and coalesce((s ->> 'days')::numeric, (s ->> 'hours')::numeric, (s ->> 'minutes')::numeric) is null and s ->> 'until' is null then raise exception 'step %: how long to wait', s ->> 'id'; end if;
    if t = 'branch' and s ->> 'on' not in ('reply', 'condition', 'ab') then raise exception 'step %: branch on a reply, a condition or an A/B split', s ->> 'id'; end if;
    if t = 'branch' and s ->> 'on' = 'condition' then perform b2c.filters_where(coalesce(s -> 'filters', '{}')); end if;
  end loop;
  for s in select * from jsonb_array_elements(p_steps) loop
    if s ->> 'then' is not null and not (s ->> 'then' = any (v_ids)) then raise exception 'step % goes to a missing step %', s ->> 'id', s ->> 'then'; end if;
    if s ->> 'else' is not null and not (s ->> 'else' = any (v_ids)) then raise exception 'step % goes to a missing step %', s ->> 'id', s ->> 'else'; end if;
  end loop;
end $f$;

create or replace function b2c.journey_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing'); v bigint := nullif(p ->> 'id', '')::bigint;
begin
  if p ? 'draft_steps' then perform b2c.journey_check_steps(p -> 'draft_steps'); end if;
  if coalesce((p ->> 'allow_active_sales')::boolean, false) and b2c.my_role() <> 'admin' then raise exception 'only the Admin lets a journey reach leads in active sales'; end if;
  if v is null then
    if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name the journey'; end if;
    insert into b2c.journeys (key, name, description, trigger, priority, allow_active_sales, test_mode, draft_steps, created_by)
    values (coalesce(nullif(p ->> 'key', ''), trim(both '_' from regexp_replace(lower(p ->> 'name'), '[^a-z0-9]+', '_', 'g')) || '_' || to_char(now(), 'YYMMDDHH24MISS')),
            trim(p ->> 'name'), p ->> 'description', coalesce(p -> 'trigger', '{"type":"manual"}'), coalesce((p ->> 'priority')::int, 100),
            coalesce((p ->> 'allow_active_sales')::boolean, false), coalesce((p ->> 'test_mode')::boolean, true), coalesce(p -> 'draft_steps', '[]'), me)
    returning id into v;
  else
    update b2c.journeys set name = coalesce(nullif(trim(p ->> 'name'), ''), name), description = case when p ? 'description' then p ->> 'description' else description end,
           trigger = coalesce(p -> 'trigger', trigger), priority = coalesce((p ->> 'priority')::int, priority),
           allow_active_sales = coalesce((p ->> 'allow_active_sales')::boolean, allow_active_sales), test_mode = coalesce((p ->> 'test_mode')::boolean, test_mode),
           draft_steps = coalesce(p -> 'draft_steps', draft_steps), updated_at = now()
     where id = v;
    if not found then raise exception 'unknown journey'; end if;
  end if;
  return v;
end $f$;

/* Publishes the draft as a new version. p_migrate: running leads move to it (same step position, or the last step). */
create or replace function b2c.journey_publish(p_id bigint, p_migrate boolean default false) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing'); j b2c.journeys; v int;
begin
  select * into j from b2c.journeys where id = p_id for update;
  if j.id is null then raise exception 'unknown journey'; end if;
  perform b2c.journey_check_steps(j.draft_steps);
  v := j.current_version + 1;
  insert into b2c.journey_versions (journey_id, version, steps, published_by) values (p_id, v, j.draft_steps, me);
  update b2c.journeys set current_version = v, status = case when status = 'draft' then 'active' else status end, updated_at = now() where id = p_id;
  if p_migrate then
    update b2c.journey_runs set version = v, step_idx = least(step_idx, jsonb_array_length(j.draft_steps) - 1) where journey_id = p_id and status in ('running', 'paused');
  end if;
  perform b2c.log('journey.published', null, jsonb_build_object('journey_id', p_id, 'version', v, 'migrate', p_migrate));
  return v;
end $f$;

create or replace function b2c.journey_set(p_id bigint, p_status text) returns void language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('marketing');
  if p_status not in ('active', 'paused', 'archived') then raise exception 'unknown status'; end if;
  if p_status = 'active' and (select current_version from b2c.journeys where id = p_id) = 0 then raise exception 'publish the journey first'; end if;
  update b2c.journeys set status = p_status, updated_at = now() where id = p_id;
  if p_status = 'archived' then
    perform b2c.journey_exit(r.lead_id, 'journey archived') from b2c.journey_runs r where r.journey_id = p_id and r.status in ('running', 'paused');
  end if;
end $f$;

create or replace function b2c.journey_clone(p_id bigint) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing'); v bigint;
begin
  insert into b2c.journeys (key, name, description, trigger, priority, allow_active_sales, test_mode, draft_steps, created_by)
  select key || '_copy_' || to_char(now(), 'YYMMDDHH24MISS'), name || ' (copy)', description, jsonb_set(trigger, '{type}', '"manual"'), priority, false, true,
         coalesce((select v2.steps from b2c.journey_versions v2 where v2.journey_id = j.id and v2.version = j.current_version), j.draft_steps), me
    from b2c.journeys j where j.id = p_id
  returning id into v;
  if v is null then raise exception 'unknown journey'; end if;
  return v;
end $f$;

/* Test a journey on one test lead now (B9.4 test mode). */
create or replace function b2c.journey_test(p_id bigint, p_lead bigint) returns bigint language plpgsql security definer set search_path = '' as $f$
begin
  perform b2c.require('marketing');
  if not coalesce((select is_test from b2c.leads_state where lead_id = p_lead), false) then raise exception 'test runs use test leads only'; end if;
  return b2c.journey_start(p_lead, p_id, 'test');
end $f$;

-- ---------- the engine ----------
create or replace function b2c.journey_template(p_channel text, p_ref jsonb) returns bigint language sql stable security definer set search_path = '' as $f$
  select case when jsonb_typeof(p_ref) = 'number' then (p_ref #>> '{}')::bigint
              when p_channel = 'whatsapp' then (select t.id from b2c.wa_templates t where t.name = p_ref #>> '{}' and t.archived_at is null order by t.status = 'approved' desc, t.language = 'en' desc, t.id limit 1)
              else (select t.id from b2c.email_templates t where t.name = p_ref #>> '{}' and t.archived_at is null order by t.language = 'en' desc, t.id limit 1) end
$f$;

/* Runs one lead's journey from its current step until it has to wait. */
create or replace function b2c.journey_step(p_run bigint) returns text language plpgsql security definer set search_path = '' as $f$
declare r b2c.journey_runs; j b2c.journeys; v_steps jsonb; s jsonb; v_idx int; v_res jsonb; v_why text; v_goto text; v_ok boolean; v_n int := 0;
        st b2c.leads_state; v_out text := 'idle';
begin
  select * into r from b2c.journey_runs where id = p_run for update skip locked;
  if r.id is null or r.status <> 'running' then return 'skip'; end if;
  select * into j from b2c.journeys where id = r.journey_id;
  select steps into v_steps from b2c.journey_versions where journey_id = r.journey_id and version = r.version;
  select * into st from b2c.leads_state where lead_id = r.lead_id;
  -- exits the lead's state decides
  v_why := b2c.may_message(r.lead_id);
  if v_why is not null then perform b2c.journey_exit(r.lead_id, v_why); return 'exited'; end if;
  if st.status = 'closed' then perform b2c.journey_exit(r.lead_id, coalesce('closed: ' || st.closed_reason, 'closed')); return 'exited'; end if;
  if st.dormant_at is not null then perform b2c.journey_exit(r.lead_id, 'dormant'); return 'exited'; end if;
  if st.status = 'active' and st.owner_id is not null and not j.allow_active_sales then
    perform b2c.journey_exit(r.lead_id, case when st.reengaged_at >= r.entered_at then 're-engaged' else 'assigned' end); return 'exited';
  end if;
  if j.status in ('paused', 'archived') then return 'journey ' || j.status; end if;

  v_idx := r.step_idx;
  loop
    v_n := v_n + 1;
    if v_idx >= jsonb_array_length(v_steps) or v_n > 25 then
      update b2c.journey_runs set status = 'done', exited_at = now(), exit_reason = 'completed', step_idx = v_idx where id = r.id;
      insert into b2c.journey_log (run_id, lead_id, step_idx, outcome) values (r.id, r.lead_id, v_idx, 'completed');
      update b2c.leads_state set journey = null where lead_id = r.lead_id;
      return 'completed';
    end if;
    s := v_steps -> v_idx; v_goto := null;
    case s ->> 'type'
    when 'send' then
      v_res := case s ->> 'channel' when 'whatsapp'
                 then b2c.queue_marketing_wa(r.lead_id, b2c.journey_template('whatsapp', s -> 'template'), 'journey', jsonb_build_object('run_id', r.id, 'journey', j.key), j.allow_active_sales)
                 else b2c.queue_marketing_email(r.lead_id, b2c.journey_template('email', s -> 'template'), 'journey', jsonb_build_object('run_id', r.id, 'journey', j.key), j.allow_active_sales) end;
      if v_res ? 'blocked' and v_res ->> 'blocked' like 'wait:%' then
        update b2c.journey_runs set step_idx = v_idx, next_at = case v_res ->> 'blocked'
            when 'wait: quiet hours' then b2c.next_send_window(now())
            when 'wait: daily cap' then b2c.next_send_window(((now() at time zone 'Asia/Kolkata')::date + 1)::timestamp at time zone 'Asia/Kolkata')
            when 'wait: 30-day cap' then b2c.next_send_window(now() + interval '3 days')
            else now() + interval '30 minutes' end where id = r.id;
        insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'send', 'waiting', v_res);
        return 'waiting';
      end if;
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail)
      values (r.id, r.lead_id, v_idx, 'send', case when v_res ? 'blocked' then 'blocked' else 'sent' end, v_res || jsonb_build_object('channel', s ->> 'channel'));
      v_out := 'sent';
    when 'wait' then
      update b2c.journey_runs set step_idx = v_idx + 1, step_started_at = now(),
             next_at = case when s ? 'until' then
                         case when (now() at time zone 'Asia/Kolkata')::time < (s ->> 'until')::time
                              then ((now() at time zone 'Asia/Kolkata')::date + (s ->> 'until')::time) at time zone 'Asia/Kolkata'
                              else ((now() at time zone 'Asia/Kolkata')::date + 1 + (s ->> 'until')::time) at time zone 'Asia/Kolkata' end
                       else now() + make_interval(days => coalesce((s ->> 'days')::int, 0), hours => coalesce((s ->> 'hours')::int, 0), mins => coalesce((s ->> 'minutes')::int, 0)) end
       where id = r.id;
      return 'waiting';
    when 'branch' then
      v_ok := case s ->> 'on'
        when 'reply' then exists (select 1 from b2c.replies x where x.lead_id = r.lead_id and x.created_at >= r.entered_at
                                     and coalesce(x.corrected_class, x.class) in (select jsonb_array_elements_text(coalesce(s -> 'classes', '["positive"]'))))
        when 'ab' then (r.id % 100) < coalesce((s ->> 'pct')::int, 50)
        else b2c.lead_matches(r.lead_id, coalesce(s -> 'filters', '{}')) end;
      v_goto := case when v_ok then s ->> 'then' else s ->> 'else' end;
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'branch', case when v_ok then 'branch:then' else 'branch:else' end, '{}');
    when 'score' then
      perform b2c.score_add(r.lead_id, 'journey', coalesce((s ->> 'delta')::numeric, 0), jsonb_build_object('journey', j.key));
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'score', 'scored', jsonb_build_object('delta', s -> 'delta'));
    when 'tag' then
      update b2c.leads_state set tags = array(select distinct unnest(tags || array[lower(s ->> 'tag')])) where lead_id = r.lead_id;
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'tag', 'tagged', jsonb_build_object('tag', s ->> 'tag'));
    when 'task' then
      insert into b2c.tasks (lead_id, owner_id, kind, title, due_at, source) values (r.lead_id, null, 'qualify', left(coalesce(s ->> 'title', 'Nurture follow-up'), 200), now(), 'journey:' || j.key);
      perform b2c.notify_admins('journey_task', left(coalesce(s ->> 'title', 'Nurture follow-up'), 120), j.name, '/w/leads/' || r.lead_id, r.lead_id, 'jtask:' || r.id || ':' || v_idx);
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome) values (r.id, r.lead_id, v_idx, 'task', 'task');
    when 'assign' then
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome) values (r.id, r.lead_id, v_idx, 'assign', 'assigned');
      perform b2c.reengage(r.lead_id, 'journey:' || j.key);
      update b2c.journey_runs set status = 'exited', exited_at = now(), exit_reason = 'assigned' where id = r.id and status = 'running';
      return 'assigned';
    when 'move' then
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'move', 'moved', jsonb_build_object('to', s ->> 'journey'));
      if exists (select 1 from b2c.journeys where key = s ->> 'journey' and current_version > 0 and status <> 'archived' and (not test_mode or r.is_test)) then
        perform b2c.journey_start(r.lead_id, (select id from b2c.journeys where key = s ->> 'journey'), 'move');
        return 'moved';
      end if;
      update b2c.journey_runs set status = 'done', exited_at = now(), exit_reason = 'completed (next journey unavailable)' where id = r.id;
      update b2c.leads_state set journey = null where lead_id = r.lead_id;
      return 'completed';
    when 'exit' then
      update b2c.journey_runs set status = 'exited', exited_at = now(), exit_reason = coalesce(s ->> 'reason', 'exit step'), step_idx = v_idx where id = r.id;
      insert into b2c.journey_log (run_id, lead_id, step_idx, step_type, outcome, detail) values (r.id, r.lead_id, v_idx, 'exit', 'exited', jsonb_build_object('reason', s ->> 'reason'));
      update b2c.leads_state set journey = null where lead_id = r.lead_id;
      return 'exited';
    else
      null;
    end case;
    v_idx := case when v_goto is not null then (select (o - 1)::int from jsonb_array_elements(v_steps) with ordinality e(x, o) where x ->> 'id' = v_goto) else v_idx + 1 end;
    update b2c.journey_runs set step_idx = v_idx, step_started_at = now() where id = r.id;
  end loop;
end $f$;

/* Does one lead match a filter (branches)? */
create or replace function b2c.lead_matches(p_lead bigint, p_filters jsonb) returns boolean language plpgsql stable security definer set search_path = '' as $f$
declare v boolean;
begin
  execute format('select exists (select 1 from b2c.leads_v v where v.lead_id = %s and %s)', p_lead, b2c.filters_where(p_filters)) into v;
  return v;
end $f$;

/* Which journey a pooled lead should enter: the lost sub-stage's journey, the partner's lost reason through the map, or
   the first active journey whose pool_entry trigger names the pool reason. */
create or replace function b2c.journey_for(p_lead bigint) returns bigint language plpgsql stable security definer set search_path = '' as $f$
declare s b2c.leads_state; v_key text; v_reason text; m record; v bigint;
begin
  select * into s from b2c.leads_state where lead_id = p_lead;
  if s.pool_reason = 'counsellor_lost' then v_key := s.journey;
  elsif s.pool_reason = 'partner_lost' then
    v_reason := lower(coalesce(s.partner_lost ->> 'lost_reason', ''));
    for m in select key, value from jsonb_each_text(b2c.setting('partner_lost_map')) where key <> 'default' loop
      if position(m.key in v_reason) > 0 then v_key := m.value; exit; end if;
    end loop;
    v_key := coalesce(v_key, b2c.setting('partner_lost_map') ->> 'default', 'partner_lost_reengage');
  end if;
  if v_key is not null then
    select id into v from b2c.journeys where key = v_key and status = 'active' and current_version > 0 and (not test_mode or s.is_test);
    if v is not null then return v; end if;
  end if;
  select j.id into v from b2c.journeys j
   where j.status = 'active' and j.current_version > 0 and j.trigger ->> 'type' = 'pool_entry' and (not j.test_mode or s.is_test)
     and (j.trigger -> 'reasons' is null or j.trigger -> 'reasons' ? coalesce(s.pool_reason, s.handoff_reason, ''))
     and (j.trigger -> 'sub_stages' is null or j.trigger -> 'sub_stages' ? coalesce(s.sub_stage, ''))
   order by j.priority, j.id limit 1;
  return v;
end $f$;

/* Every minute: leads that should enter a journey now. */
create or replace function b2c.journey_enroll_tick(p_limit int default 200) returns int language plpgsql security definer set search_path = '' as $f$
declare r record; v bigint; n int := 0; j b2c.journeys;
begin
  -- pooled leads whose first nurture message is due (the lost sub-stage's or the partner's delay) and that have not started one in this pool stay
  for r in select s.lead_id from b2c.leads_state s
            where s.status = 'pool' and s.deleted_at is null and s.dormant_at is null
              and coalesce(s.first_message_due_at, s.pool_entered_at, s.handed_off_at) <= now()
              and not exists (select 1 from b2c.journey_runs x where x.lead_id = s.lead_id and (x.status in ('running', 'paused') or x.entered_at >= coalesce(s.pool_entered_at, s.handed_off_at)))
              and b2c.may_message(s.lead_id) is null
            order by coalesce(s.first_message_due_at, s.pool_entered_at) limit p_limit loop
    v := b2c.journey_for(r.lead_id);
    if v is not null then perform b2c.journey_start(r.lead_id, v, 'pool_entry'); n := n + 1; end if;
  end loop;
  -- segment, tag and inactivity triggers: each lead enters each such journey once
  for j in select * from b2c.journeys where status = 'active' and current_version > 0 and trigger ->> 'type' in ('segment', 'tag', 'inactive') order by priority, id loop
    for r in execute format(
      'select s.lead_id from b2c.leads_state s where s.deleted_at is null and s.dormant_at is null and s.is_test = %L
          and (s.status = %L or (%L and s.status = %L))
          and not exists (select 1 from b2c.journey_runs x where x.lead_id = s.lead_id and (x.status in (%L, %L) or x.journey_id = %s))
          and %s limit %s',
      j.test_mode, 'pool', j.allow_active_sales, 'active', 'running', 'paused', j.id,
      case j.trigger ->> 'type'
        when 'segment' then format('s.lead_id in (select b2c.segment_leads(%s, null, %L))', (j.trigger ->> 'segment_id')::bigint, j.test_mode)
        when 'tag' then format('%L = any (s.tags)', lower(j.trigger ->> 'tag'))
        else format('coalesce(s.last_activity_at, s.pool_entered_at) < now() - make_interval(days => %s)', coalesce((j.trigger ->> 'days')::int, 30)) end,
      p_limit) loop
      exit when n >= p_limit;
      continue when b2c.may_message(r.lead_id) is not null;
      perform b2c.journey_start(r.lead_id, j.id, j.trigger ->> 'type'); n := n + 1;
    end loop;
  end loop;
  return n;
end $f$;

create or replace function b2c.journey_tick(p_limit int default 300) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r record; v text; c jsonb := '{}'::jsonb; n_in int;
begin
  n_in := b2c.journey_enroll_tick(200);
  for r in select id from b2c.journey_runs where status = 'running' and next_at <= now() order by next_at limit p_limit loop
    begin
      v := b2c.journey_step(r.id);
    exception when others then
      v := 'error';
      insert into b2c.journey_log (run_id, lead_id, outcome, detail) select r.id, x.lead_id, 'error', jsonb_build_object('error', sqlerrm) from b2c.journey_runs x where x.id = r.id;
      update b2c.journey_runs set next_at = now() + interval '1 hour' where id = r.id;
    end;
    c := c || jsonb_build_object(v, coalesce((c ->> v)::int, 0) + 1);
  end loop;
  return c || jsonb_build_object('entered', n_in);
end $f$;

/* The journey page's numbers (B9.0): live counts on every step, the funnel, exits by reason. */
create or replace function b2c.journey_stats(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('marketing');
  return jsonb_build_object(
    'entered', (select count(*) from b2c.journey_runs where journey_id = p_id and not is_test),
    'running', (select count(*) from b2c.journey_runs where journey_id = p_id and status in ('running', 'paused') and not is_test),
    'completed', (select count(*) from b2c.journey_runs where journey_id = p_id and status = 'done' and not is_test),
    'at_step', (select coalesce(jsonb_object_agg(step_idx, n), '{}') from (select step_idx, count(*) n from b2c.journey_runs where journey_id = p_id and status in ('running', 'paused') group by step_idx) a),
    'exits', (select coalesce(jsonb_object_agg(coalesce(exit_reason, '?'), n), '{}') from (select exit_reason, count(*) n from b2c.journey_runs where journey_id = p_id and status = 'exited' and not is_test group by exit_reason) e),
    'sent', (select count(*) from b2c.journey_log l join b2c.journey_runs x on x.id = l.run_id where x.journey_id = p_id and l.outcome = 'sent'),
    'blocked', (select coalesce(jsonb_object_agg(k, n), '{}') from (select l.detail ->> 'blocked' k, count(*) n from b2c.journey_log l join b2c.journey_runs x on x.id = l.run_id
                 where x.journey_id = p_id and l.outcome in ('blocked', 'waiting') and l.at > now() - interval '30 days' group by 1) b),
    're_engaged', (select count(*) from b2c.journey_runs x join b2c.leads_state s on s.lead_id = x.lead_id where x.journey_id = p_id and s.reengaged_at >= x.entered_at and not x.is_test),
    'enrolled', (select count(*) from b2c.journey_runs x where x.journey_id = p_id and not x.is_test and exists (select 1 from b2c.enrollments e where e.lead_id = x.lead_id and e.created_at >= x.entered_at)),
    'test_runs', (select count(*) from b2c.journey_runs where journey_id = p_id and is_test));
end $f$;

/* Re-engagement also ends the journey (B6.3 step 1). */
create or replace function b2c.reengage(p_lead bigint, p_trigger text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.leads_state set status = 'active', hot = true, reengaged_at = now(), reengage_trigger = p_trigger, journey = null, updated_at = now()
   where lead_id = p_lead and status = 'pool';
  if not found then return jsonb_build_object('outcome', 'skipped', 'why', 'not in the pool'); end if;
  perform b2c.journey_exit(p_lead, 're-engaged: ' || p_trigger);
  insert into b2c.activities (lead_id, kind, body, meta, at) values (p_lead, 'reengaged', 'Re-engaged: ' || p_trigger, jsonb_build_object('trigger', p_trigger), now());
  return b2c.allocate(p_lead, 'reengaged');
end $f$;

-- ---------- the starter set (B9.4, audit §4.6): templates in draft until Meta approves them ----------
insert into b2c.wa_templates (name, language, category, audience, purpose, body, variables, buttons, status) values
  ('nurture_tried_to_reach', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, our counsellor tried to reach you about {{2}}. Would you like a call at a time that suits you?', '["first_name","programme"]', '[{"type":"quick_reply","text":"Yes, call me"},{"type":"quick_reply","text":"Not now"}]', 'draft'),
  ('nurture_lower_fee', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, there are {{2}} options with lower fees and easy EMIs. Shall we share them?', '["first_name","programme"]', '[{"type":"quick_reply","text":"Share details"},{"type":"quick_reply","text":"Not now"}]', 'draft'),
  ('nurture_eligible_programmes', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, based on your qualification there are programmes you are eligible for right now. Want a short list?', '["first_name"]', '[{"type":"quick_reply","text":"Share details"},{"type":"quick_reply","text":"Not now"}]', 'draft'),
  ('nurture_monthly_update', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, a quick update on {{2}}: new intakes and scholarships are open this month. Interested?', '["first_name","programme"]', '[{"type":"quick_reply","text":"I''m interested"},{"type":"quick_reply","text":"Not now"}]', 'draft'),
  ('nurture_reengage', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, are you still thinking about {{2}}? We can help you compare universities and fees.', '["first_name","programme"]', '[{"type":"quick_reply","text":"Yes, call me"},{"type":"quick_reply","text":"Not interested"}]', 'draft'),
  ('nurture_long_term', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, if your plans change, Eduwit can help you choose the right online programme. Reply anytime.', '["first_name"]', '[{"type":"quick_reply","text":"I''m interested"}]', 'draft'),
  ('nurture_fix_reapply', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, your application needs one more document to go through. We can help you fix it and reapply.', '["first_name"]', '[{"type":"quick_reply","text":"Yes, call me"}]', 'draft'),
  ('nurture_discovery', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, tell us what you would like to study and we will suggest the best online programmes for you.', '["first_name"]', '[{"type":"quick_reply","text":"Share details"},{"type":"quick_reply","text":"Not now"}]', 'draft'),
  ('nurture_eligibility_check', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, check your eligibility for {{2}} in 2 minutes. Shall we start?', '["first_name","programme"]', '[{"type":"quick_reply","text":"Yes, call me"},{"type":"quick_reply","text":"Not now"}]', 'draft'),
  ('nurture_partner_lost', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, still looking for the right {{2}}? Eduwit can help you compare options from several universities.', '["first_name","programme"]', '[{"type":"quick_reply","text":"Yes, call me"},{"type":"quick_reply","text":"Not now"}]', 'draft'),
  ('nurture_qualify', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, answer 3 quick questions so we can suggest the right programme for you.', '["first_name"]', '[{"type":"quick_reply","text":"Share details"}]', 'draft'),
  ('nurture_consent_repeat', 'en', 'marketing', 'marketing', 'journey', 'Hi {{1}}, may Eduwit send you programme updates on WhatsApp and email? Reply STOP anytime to opt out.', '["first_name"]', '[{"type":"quick_reply","text":"Yes, send updates"},{"type":"quick_reply","text":"No thanks"}]', 'draft')
on conflict (name, language) do nothing;

insert into b2c.email_templates (name, language, subject, body) values
  ('nurture_programme_options', 'en', '{{programme}}: options that fit you', E'Hi {{first_name}},\n\nHere are online {{programme}} options from recognised universities, with fees and EMI choices. Reply to this email or tap the link below and a counsellor will call you.\n\nTeam Eduwit'),
  ('nurture_lower_fee_email', 'en', 'Lower-fee {{programme}} options and EMI plans', E'Hi {{first_name}},\n\nFee is often the deciding factor. These programmes cost less and offer EMIs from a few thousand rupees a month. Reply "call me" and we will walk you through them.\n\nTeam Eduwit'),
  ('nurture_monthly_email', 'en', 'This month at Eduwit: new intakes and scholarships', E'Hi {{first_name}},\n\nNew intakes and scholarships are open this month for {{programme}}. If your plans have changed, reply and a counsellor will help.\n\nTeam Eduwit')
on conflict (name, language) do nothing;

insert into b2c.journeys (key, name, description, trigger, priority, status, test_mode, draft_steps) values
  ('we_tried_to_reach_you', 'Not reachable: we tried to reach you', 'Counsellor-lost "Uncontactable" and partner "not reachable" leads, after 3 days.', '{"type":"pool_entry","sub_stages":["Uncontactable"]}', 10, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_tried_to_reach"},{"id":"s2","type":"wait","days":3},{"id":"s3","type":"branch","on":"reply","classes":["positive"],"then":"s8","else":"s4"},
     {"id":"s4","type":"send","channel":"email","template":"nurture_programme_options"},{"id":"s5","type":"wait","days":7},{"id":"s6","type":"send","channel":"whatsapp","template":"nurture_reengage"},
     {"id":"s7","type":"move","journey":"monthly_update"},{"id":"s8","type":"assign"}]'),
  ('lower_fee_emi', 'Fee concern: lower-fee options and EMI', 'Can''t afford the fee or EMI, loan not approved, partner "over budget"; after 7 days.', '{"type":"pool_entry","sub_stages":["Can''t afford fee or EMI","Loan not approved"]}', 20, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_lower_fee"},{"id":"s2","type":"wait","days":4},{"id":"s3","type":"branch","on":"reply","classes":["positive"],"then":"s7","else":"s4"},
     {"id":"s4","type":"send","channel":"email","template":"nurture_lower_fee_email"},{"id":"s5","type":"wait","days":14},{"id":"s6","type":"move","journey":"monthly_update"},{"id":"s7","type":"assign"}]'),
  ('eligible_programmes', 'Not eligible: programmes they qualify for', 'Not eligible (counsellor or partner); after 7 days.', '{"type":"pool_entry","sub_stages":["Not eligible"]}', 20, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_eligible_programmes"},{"id":"s2","type":"wait","days":5},{"id":"s3","type":"branch","on":"reply","classes":["positive"],"then":"s6","else":"s4"},
     {"id":"s4","type":"send","channel":"email","template":"nurture_programme_options"},{"id":"s5","type":"move","journey":"monthly_update"},{"id":"s6","type":"assign"}]'),
  ('reengage_60d', 'Not interested: re-engage after 60 days', 'One gentle message after 60 days, then the long-term update.', '{"type":"pool_entry","sub_stages":["Not interested"]}', 30, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_reengage"},{"id":"s2","type":"wait","days":7},{"id":"s3","type":"branch","on":"reply","classes":["positive"],"then":"s5","else":"s4"},
     {"id":"s4","type":"move","journey":"long_term_update"},{"id":"s5","type":"assign"}]'),
  ('long_term_update', 'Long-term update (lost to a competitor)', 'A message every 90 days.', '{"type":"pool_entry","sub_stages":["Lost to competitor","Chose another provider"]}', 40, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_long_term"},{"id":"s2","type":"wait","days":90},{"id":"s3","type":"branch","on":"reply","classes":["positive"],"then":"s6","else":"s4"},
     {"id":"s4","type":"send","channel":"email","template":"nurture_monthly_email"},{"id":"s5","type":"wait","days":90},{"id":"s6","type":"assign"}]'),
  ('monthly_update', 'Not now: monthly update', 'Not now, later, and Other; one update a month for six months.', '{"type":"pool_entry","sub_stages":["Not now, later","Other"]}', 50, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_monthly_update"},{"id":"s2","type":"wait","days":30},{"id":"s3","type":"branch","on":"reply","classes":["positive"],"then":"s9","else":"s4"},
     {"id":"s4","type":"send","channel":"email","template":"nurture_monthly_email"},{"id":"s5","type":"wait","days":30},{"id":"s6","type":"send","channel":"whatsapp","template":"nurture_monthly_update"},
     {"id":"s7","type":"wait","days":30},{"id":"s8","type":"move","journey":"long_term_update"},{"id":"s9","type":"assign"}]'),
  ('fix_and_reapply', 'Document verification failed: fix and reapply', 'After 3 days: what was missing and how to resubmit.', '{"type":"pool_entry","sub_stages":["Document verification failed"]}', 10, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_fix_reapply"},{"id":"s2","type":"wait","days":3},{"id":"s3","type":"branch","on":"reply","classes":["positive","question"],"then":"s5","else":"s4"},
     {"id":"s4","type":"task","title":"Fix and reapply: no reply after 3 days, call to help"},{"id":"s5","type":"assign"}]'),
  ('partner_lost_reengage', 'Partner-lost re-engagement', 'Partner-lost leads whose reason has no specific journey.', '{"type":"pool_entry","reasons":["partner_lost"]}', 60, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_partner_lost"},{"id":"s2","type":"wait","days":5},{"id":"s3","type":"branch","on":"reply","classes":["positive"],"then":"s7","else":"s4"},
     {"id":"s4","type":"send","channel":"email","template":"nurture_programme_options"},{"id":"s5","type":"wait","days":21},{"id":"s6","type":"move","journey":"monthly_update"},{"id":"s7","type":"assign"}]'),
  ('qualification_nurture', 'Qualification nurture (missing details)', 'Not-qualified leads: invite them to finish their details; an Admin task after 48 hours.', '{"type":"pool_entry","reasons":["not_qualified"]}', 70, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_qualify"},{"id":"s2","type":"wait","days":2},{"id":"s3","type":"branch","on":"reply","classes":["positive","question"],"then":"s4","else":"s5"},
     {"id":"s4","type":"task","title":"To qualify: collect the missing details (call only for that)"},{"id":"s5","type":"send","channel":"whatsapp","template":"nurture_discovery"},
     {"id":"s6","type":"wait","days":14},{"id":"s7","type":"move","journey":"monthly_update"}]'),
  ('programme_discovery', 'New enquiry, never qualified: programme discovery', 'Manual or segment entry.', '{"type":"manual"}', 80, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_discovery"},{"id":"s2","type":"wait","days":3},{"id":"s3","type":"branch","on":"reply","classes":["positive"],"then":"s6","else":"s4"},
     {"id":"s4","type":"send","channel":"email","template":"nurture_programme_options"},{"id":"s5","type":"move","journey":"monthly_update"},{"id":"s6","type":"assign"}]'),
  ('eligibility_unknown', 'Programme interest, eligibility unknown', 'Manual or segment entry.', '{"type":"manual"}', 80, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_eligibility_check"},{"id":"s2","type":"wait","days":4},{"id":"s3","type":"branch","on":"reply","classes":["positive"],"then":"s5","else":"s4"},
     {"id":"s4","type":"move","journey":"monthly_update"},{"id":"s5","type":"assign"}]'),
  ('consent_repeat', 'Ask for marketing consent again', 'Leads without marketing consent (manual or segment); a utility template once approved.', '{"type":"manual"}', 90, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_consent_repeat"},{"id":"s2","type":"exit","reason":"asked"}]'),
  ('deadline_countdown', 'Admission-deadline countdown', 'Set a segment trigger and the dates before an intake closes; reaches active leads only if the Admin allows it.', '{"type":"manual"}', 5, 'draft', false,
   '[{"id":"s1","type":"send","channel":"whatsapp","template":"nurture_monthly_update"},{"id":"s2","type":"wait","days":7},{"id":"s3","type":"send","channel":"email","template":"nurture_monthly_email"},{"id":"s4","type":"exit","reason":"deadline passed"}]')
on conflict (key) do nothing;

-- the starter journeys are published once (version 1) and stay active only after Marketing reviews them: they start paused
do $d$
declare j record;
begin
  for j in select id, draft_steps from b2c.journeys where current_version = 0 and created_by is null loop
    insert into b2c.journey_versions (journey_id, version, steps) values (j.id, 1, j.draft_steps) on conflict do nothing;
    update b2c.journeys set current_version = 1, status = 'paused' where id = j.id;
  end loop;
end $d$;

alter table b2c.journeys enable row level security;
alter table b2c.journey_versions enable row level security;
alter table b2c.journey_runs enable row level security;
alter table b2c.journey_log enable row level security;
grant select on b2c.journeys, b2c.journey_versions, b2c.journey_runs, b2c.journey_log to authenticated;
do $p$
begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'journeys' and policyname = 'staff read') then
    create policy "staff read" on b2c.journeys for select to authenticated using ((select b2c.is_staff()));
    create policy "marketing read" on b2c.journey_versions for select to authenticated using ((select b2c.can('marketing')));
    create policy "who may see" on b2c.journey_runs for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "who may see" on b2c.journey_log for select to authenticated using ((select b2c.can_see(lead_id)));
  end if;
end $p$;
grant execute on function b2c.journey_lead(bigint, text, bigint), b2c.journey_save(jsonb), b2c.journey_publish(bigint, boolean), b2c.journey_set(bigint, text),
  b2c.journey_clone(bigint), b2c.journey_test(bigint, bigint), b2c.journey_stats(bigint) to authenticated;
revoke execute on function b2c.journey_exit(bigint, text), b2c.journey_start(bigint, bigint, text), b2c.journey_step(bigint), b2c.journey_enroll_tick(int),
  b2c.journey_tick(int), b2c.journey_for(bigint), b2c.lead_matches(bigint, jsonb), b2c.journey_template(text, jsonb), b2c.journey_check_steps(jsonb) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
