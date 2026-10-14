-- Phase 1 behaviour checks, rolled back. Run on staging (or a local copy with tests/local_stubs.sql). Every row of the
-- final select must say ok = true. Uses test phones 9190000000NN only.
begin;
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

-- ---------- people ----------
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000b001', 'admin.test@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000b002', 'priya.test@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000b003', 'rohan.test@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000b004', 'real.counsellor@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000b005', 'sneha.test@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000b006', 'ankit.test@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, languages, takes_leads) values
  ('aaaaaaaa-0000-0000-0000-00000000b001', 'admin.test@eduwit.in', 'Test Admin', 'admin', true, false, '{English}', false),
  ('aaaaaaaa-0000-0000-0000-00000000b002', 'priya.test@eduwit.in', 'Priya Test', 'counsellor', true, true, '{English,Hindi}', true),
  ('aaaaaaaa-0000-0000-0000-00000000b003', 'rohan.test@eduwit.in', 'Rohan Test', 'counsellor', true, true, '{English,Marathi}', true),
  ('aaaaaaaa-0000-0000-0000-00000000b004', 'real.counsellor@eduwit.in', 'Real Counsellor', 'counsellor', true, false, '{English}', true),
  ('aaaaaaaa-0000-0000-0000-00000000b005', 'sneha.test@eduwit.in', 'Sneha Test', 'marketing', true, false, '{English}', true),
  ('aaaaaaaa-0000-0000-0000-00000000b006', 'ankit.test@eduwit.in', 'Ankit Test', 'counsellor', true, true, '{Hindi}', true);
-- everyone works all day, every day, in this test (holidays cleared inside the transaction)
delete from b2c.holidays;
insert into b2c.work_patterns (user_id, isodow, start_t, end_t)
select u.user_id, d, '00:00', '23:59' from b2c.users u, generate_series(1, 7) d;
-- Ankit is on leave today
insert into b2c.leaves (user_id, from_day, to_day, mode) values ('aaaaaaaa-0000-0000-0000-00000000b006', (now() at time zone 'Asia/Kolkata')::date, (now() at time zone 'Asia/Kolkata')::date + 3, 'hold');

create function pg_temp.as_user(p uuid, p_session uuid default null) returns void language plpgsql as $f$
begin
  -- identity only: every b2c function is SECURITY DEFINER and checks b2c.require()/can_see() from the claims;
  -- what the authenticated role may execute is checked separately at the end (grants)
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'session_id', coalesce(p_session, ('bbbbbbbb-0000-0000-0000-' || right(p::text, 12))::uuid))::text, true);
end $f$;
create function pg_temp.as_system() returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', '', true);
end $f$;
create function pg_temp.env(p_id text, p_type text, p_lead bigint, p_data jsonb, p_test boolean default true) returns jsonb language sql as $f$
  select jsonb_build_object('id', p_id, 'type', p_type, 'lead_id', p_lead, 'occurred_at', now(), 'test', p_test, 'contract_version', 3, 'data', p_data)
$f$;
create function pg_temp.rec(p_lead bigint, p_phone text, p_name text, p_course text, p_extra jsonb default '{}') returns jsonb language sql as $f$
  select jsonb_build_object('id', p_lead, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
    'student', jsonb_build_object('name', p_name, 'phone', p_phone, 'email', lower(replace(p_name, ' ', '.')) || '@example.in', 'city', 'Pune', 'preferred_language', 'Hindi'),
    'education', jsonb_build_object('highest_qualification', 'B.Com'), 'interest', jsonb_build_object('course', p_course, 'enrollment_timeline', 'Jan 2027'),
    'consent', jsonb_build_object('state', 'given', 'opted_out', false), 'source', jsonb_build_object('lead_source', 'meta_lead_ad'),
    'allocation', jsonb_build_object('destination', 'in_house')) || p_extra
$f$;

-- ---------- 2FA ----------
do $x$
declare v_code text; v jsonb; e text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b002', 'cccccccc-0000-0000-0000-000000000001');
  insert into r (name, ok, detail) values ('not_staff_before_code', not b2c.is_staff(), null);
  perform pg_temp.as_system();
  v_code := b2c.mfa_issue('aaaaaaaa-0000-0000-0000-00000000b002', 'cccccccc-0000-0000-0000-000000000001');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b002', 'cccccccc-0000-0000-0000-000000000001');
  v := b2c.mfa_verify(case when v_code = '000000' then '111111' else '000000' end, false);
  insert into r (name, ok, detail) values ('wrong_code_refused', (v ->> 'ok')::boolean = false, v::text);
  v := b2c.mfa_verify(v_code, true, 'test phone');
  insert into r (name, ok, detail) values ('right_code_passes_and_trusts', (v ->> 'ok')::boolean and v ->> 'device_token' is not null and b2c.is_staff(), null);
  insert into r (name, ok, detail) values ('me_reports_sales', b2c.me() ->> 'interface' = 'sales' and (b2c.me() ->> 'checked')::boolean, b2c.me()::text);
  -- a new session on the trusted device skips the code
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b002', 'cccccccc-0000-0000-0000-000000000002');
  e := b2c.device_trust_check(v ->> 'device_token')::text;
  insert into r (name, ok, detail) values ('trusted_device', e = 'true' and b2c.is_staff(), e);
  perform pg_temp.as_system();
end $x$;
-- every other test person has passed 2FA for their standard session
insert into b2c.session_checks (session_id, user_id, method)
select ('bbbbbbbb-0000-0000-0000-' || right(user_id::text, 12))::uuid, user_id, 'email_code' from b2c.users;

-- ---------- rules: duplicate cascade → seniors (Priya, Rohan) ----------
do $x$
declare v_pool bigint;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b001');
  v_pool := b2c.pool_save('{"name":"Seniors (test)","members":[{"user_id":"aaaaaaaa-0000-0000-0000-00000000b002","weight":2},{"user_id":"aaaaaaaa-0000-0000-0000-00000000b003","weight":2}]}');
  perform b2c.rule_save(jsonb_build_object('name', 'Duplicate cascade to seniors', 'position', 10, 'logic', 'round_robin', 'pool_id', v_pool,
                        'condition', '{"all":[{"field":"reason","op":"eq","value":"duplicate_cascade"}]}'::jsonb, 'fallbacks', '["next_rule"]'::jsonb));
  perform pg_temp.as_system();
end $x$;

-- ---------- hand-offs ----------
do $x$
declare v jsonb; s b2c.leads_state; d b2c.allocation_decisions; n int;
begin
  -- record first, then the hand-off
  v := b2c.handoff_receive(pg_temp.env('t-evt-1', 'b2c.lead_upserted', 900001, jsonb_build_object('version', 1, 'seq', 10, 'record', pg_temp.rec(900001, '919000000001', 'Asha Test', 'MBA'))));
  insert into r (name, ok, detail) values ('record_cached', exists (select 1 from b2c.lead_records where lead_id = 900001 and version = 1), v::text);
  v := b2c.handoff_receive(pg_temp.env('t-evt-2', 'b2c.lead_handed_off', 900001, '{"b2c_lane":"sales","reason":"duplicate_cascade","handling":{"job":"sell","assignment":"round_robin_now","first_contact_script":"neutral_adviser"},"partner_bar":{"reason":"duplicate"},"already_with_providers":[{"partner_name":"Down Edu","first_had_at":"2026-08-28"}]}'));
  select * into s from b2c.leads_state where lead_id = 900001;
  insert into r (name, ok, detail) values ('handoff_assigned_to_senior', s.owner_id in ('aaaaaaaa-0000-0000-0000-00000000b002', 'aaaaaaaa-0000-0000-0000-00000000b003') and s.stage_id = 1 and s.hot, v::text);
  select * into d from b2c.allocation_decisions where lead_id = 900001 order by id desc limit 1;
  insert into r (name, ok, detail) values ('decision_explained', d.rule_name = 'Duplicate cascade to seniors' and jsonb_array_length(d.eligible) = 2, to_jsonb(d)::text);
  insert into r (name, ok, detail) values ('partner_bar_and_providers', s.partner_bar_reason = 'duplicate' and jsonb_array_length(s.providers) = 1, null);
  insert into r (name, ok, detail) values ('first_call_task', exists (select 1 from b2c.tasks where lead_id = 900001 and status = 'open' and title like 'First call: neutral%'), null);
  insert into r (name, ok, detail) values ('sla_hot_15_min', s.sla_due_at between now() + interval '14 minutes' and now() + interval '16 minutes', s.sla_due_at::text);
  insert into r (name, ok, detail) values ('assignment_message_queued', exists (select 1 from b2c.send_queue q where q.lead_id = 900001 and q.purpose = 'assignment'), null);
  insert into r (name, ok, detail) values ('owner_queued_for_b2b', exists (select 1 from b2c.outbox o where o.lead_id = 900001 and o.kind = 'update' and not o.urgent and o.body -> 'set' ? 'owner_user_id'), null);
  -- the same envelope again
  v := b2c.handoff_receive(pg_temp.env('t-evt-2', 'b2c.lead_handed_off', 900001, '{}'));
  insert into r (name, ok, detail) values ('duplicate_envelope_once', v ->> 'status' = 'duplicate' and (select count(*) from b2c.assignments where lead_id = 900001) = 1, v::text);
  -- an older version never overwrites
  perform b2c.handoff_receive(pg_temp.env('t-evt-3', 'b2c.lead_upserted', 900001, jsonb_build_object('version', 0, 'record', pg_temp.rec(900001, '919000000001', 'OLD NAME', 'MBA'))));
  insert into r (name, ok, detail) values ('older_version_ignored', (select record -> 'student' ->> 'name' from b2c.lead_records where lead_id = 900001) = 'Asha Test', null);

  -- second duplicate-cascade lead goes to the other senior (round robin)
  perform b2c.handoff_receive(pg_temp.env('t-evt-4', 'b2c.lead_upserted', 900002, jsonb_build_object('version', 1, 'record', pg_temp.rec(900002, '919000000002', 'Rahul Test', 'MCA'))));
  perform b2c.handoff_receive(pg_temp.env('t-evt-5', 'b2c.lead_handed_off', 900002, '{"b2c_lane":"sales","reason":"duplicate_cascade","handling":{"assignment":"round_robin_now"}}'));
  insert into r (name, ok, detail) values ('round_robin_alternates',
    (select owner_id from b2c.leads_state where lead_id = 900002) is distinct from (select owner_id from b2c.leads_state where lead_id = 900001), null);

  -- other sales reasons go to the catch-all: never Ankit (on leave), never the real counsellor (test lead), never marketing
  perform b2c.handoff_receive(pg_temp.env('t-evt-6a', 'b2c.lead_upserted', 900003, jsonb_build_object('version', 1, 'record', pg_temp.rec(900003, '919000000003', 'Mohit Test', 'BBA'))));
  perform b2c.handoff_receive(pg_temp.env('t-evt-6', 'b2c.lead_handed_off', 900003, '{"b2c_lane":"sales","reason":"no_partner_offers_programme"}'));
  select * into d from b2c.allocation_decisions where lead_id = 900003 order by id desc limit 1;
  insert into r (name, ok, detail) values ('leave_and_test_isolation',
    d.chosen in ('aaaaaaaa-0000-0000-0000-00000000b002', 'aaaaaaaa-0000-0000-0000-00000000b003')
    and exists (select 1 from jsonb_array_elements(d.skipped) x where x ->> 'why' = 'on leave')
    and exists (select 1 from jsonb_array_elements(d.skipped) x where x ->> 'why' = 'test lead'), to_jsonb(d)::text);

  -- a nurture hand-off waits in the pool, unassigned, with the welcome message queued
  perform b2c.handoff_receive(pg_temp.env('t-evt-7', 'b2c.lead_upserted', 900004, jsonb_build_object('version', 1, 'record', pg_temp.rec(900004, '919000000004', 'Vikram Test', null))));
  perform b2c.handoff_receive(pg_temp.env('t-evt-8', 'b2c.lead_handed_off', 900004, '{"b2c_lane":"nurture","reason":"not_qualified","missing":["no_course"],"b2c_actions":["welcome_explore_programmes"]}'));
  select * into s from b2c.leads_state where lead_id = 900004;
  insert into r (name, ok, detail) values ('nurture_pool_unassigned', s.status = 'pool' and s.owner_id is null and s.pool_reason = 'not_qualified', to_jsonb(s)::text);
  insert into r (name, ok, detail) values ('welcome_queued', exists (select 1 from b2c.send_queue q where q.lead_id = 900004 and q.purpose = 'welcome'), null);

  -- partner-lost in the pool, then a re-enquiry re-engages it as hot
  perform b2c.handoff_receive(pg_temp.env('t-evt-9', 'b2c.lead_upserted', 900005, jsonb_build_object('version', 1, 'record', pg_temp.rec(900005, '919000000005', 'Ritika Test', 'MBA'))));
  perform b2c.handoff_receive(pg_temp.env('t-evt-10', 'b2c.lead_handed_off', 900005, jsonb_build_object('b2c_lane', 'nurture', 'reason', 'partner_lost', 'partner_bar', '{"reason":"lost"}',
                              'nurture_first_message_at', now() + interval '7 days', 'lost', '{"partner_name":"Up Edu","lost_reason":"over budget"}')));
  insert into r (name, ok, detail) values ('partner_lost_waits', (select status = 'pool' and first_message_due_at > now() + interval '6 days' from b2c.leads_state where lead_id = 900005), null);
  v := b2c.handoff_receive(pg_temp.env('t-evt-11', 'b2c.lead_reenquired', 900005, '{"interest":true,"reactivation":true,"what":{"source_system":"witty","event_type":"lead.interest"}}'));
  select * into s from b2c.leads_state where lead_id = 900005;
  insert into r (name, ok, detail) values ('reengaged_hot_assigned', s.status = 'active' and s.owner_id is not null and s.hot and s.sub_stage = 'Re-engaged from nurture' and s.reengage_trigger = 'witty_interest', to_jsonb(s)::text);
end $x$;

-- ---------- the counsellor's work ----------
do $x$
declare v jsonb; v_owner uuid; v_call bigint; e text; n int; s b2c.leads_state; v_contact bigint;
begin
  select owner_id into v_owner from b2c.leads_state where lead_id = 900001;
  perform pg_temp.as_user(v_owner);
  v := b2c.today();
  insert into r (name, ok, detail) values ('today_queue', exists (select 1 from jsonb_array_elements(v -> 'queue') q where (q -> 'lead' ->> 'lead_id')::bigint = 900001 and q ->> 'why' = 'New, not worked'), v::text);
  -- only own leads
  v := b2c.lead_list('{"filters":{}, "include_test": true}');
  insert into r (name, ok, detail) values ('counsellor_sees_own_only', not exists (select 1 from jsonb_array_elements(v -> 'rows') x where (x ->> 'owner_id')::uuid is distinct from v_owner), (v ->> 'total'));
  begin perform b2c.lead_detail((select lead_id from b2c.leads_state where owner_id is distinct from v_owner and status = 'active' limit 1)); e := 'seen'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('other_lead_hidden', e = 'not allowed', e);

  -- call: tap, then a log without a next follow-up is refused, with one it moves the stage
  v := b2c.call_tap(900001);
  v_call := (v ->> 'call_id')::bigint;
  insert into r (name, ok, detail) values ('call_tap_number', v ->> 'tel' = 'tel:+919000000001', v::text);
  begin perform b2c.call_log(v_call, 'no_answer', 0, null, null); e := 'logged'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('call_needs_next_followup', e = 'set the next follow-up', e);
  v := b2c.call_log(v_call, 'no_answer', 0, 'rang out', now() + interval '3 hours');
  select * into s from b2c.leads_state where lead_id = 900001;
  insert into r (name, ok, detail) values ('auto_could_not_connect', s.stage_id = 2 and s.sub_stage = 'No answer' and s.contact_attempts = 1 and s.sla_met_at is not null, v::text);
  insert into r (name, ok, detail) values ('one_merged_update_per_lead',
    (select count(*) from b2c.outbox where lead_id = 900001 and kind = 'update' and status = 'queued') = 1
    and (select body -> 'set' ->> 'stage' from b2c.outbox where lead_id = 900001 and kind = 'update' and status = 'queued') = 'contacted', null);
  insert into r (name, ok, detail) values ('call_activity_batched', exists (select 1 from b2c.outbox where lead_id = 900001 and kind = 'activity' and not urgent and body ->> 'outcome' = 'no_answer'), null);

  v := b2c.call_log((b2c.call_tap(900001) ->> 'call_id')::bigint, 'connected', 240, 'wants weekend batch', now() + interval '1 day');
  insert into r (name, ok, detail) values ('auto_contacted', (select stage_id = 3 and sub_stage = 'Spoke briefly' from b2c.leads_state where lead_id = 900001), v::text);

  -- stages: sub-stage required; Qualified needs the profile; back to New Lead needs the Admin
  begin perform b2c.set_stage(900001, 5::smallint, 'Not a sub-stage', null, now() + interval '1 day'); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('sub_stage_required', e like 'choose a sub-stage%', e);
  begin perform b2c.set_stage(900001, 1::smallint, 'Fresh assignment', null, now() + interval '1 day'); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('no_backward_without_admin', e like 'moving back from%', e);
  begin perform b2c.set_stage(900001, 4::smallint, 'Eligible and interested', null, null); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('stage_needs_followup', e = 'set the next follow-up', e);
  v := b2c.set_stage(900001, 4::smallint, 'Eligible and interested', 'B.Com 68%, Jan intake', now() + interval '1 day');
  insert into r (name, ok, detail) values ('qualified', v ->> 'canonical' = 'counselled', v::text);

  -- contacts: add and make primary; never edit an existing one
  v := b2c.add_contact(900001, 'phone', '+91 90000 00031', 'parent', array['call']);
  v_contact := (v ->> 'id')::bigint;
  insert into r (name, ok, detail) values ('contact_added_primary', (select primary_call from b2c.lead_contacts where id = v_contact)
    and (select count(*) from b2c.lead_contacts where lead_id = 900001 and primary_call) = 1, v::text);
  begin update b2c.lead_contacts set value = '919000000099' where lead_id = 900001 and origin = 'intake' and kind = 'phone'; e := 'edited'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('intake_contact_locked', e <> 'edited', e);
  insert into r (name, ok, detail) values ('contact_event_batched', exists (select 1 from b2c.outbox where lead_id = 900001 and kind = 'event' and body ->> 'type' = 'b2ccrm.contact_added' and not urgent), null);

  -- cross-sell needs a reason; it is history and a batched update
  begin perform b2c.correct_lead(900001, '{"course":"Executive MBA"}', null); e := 'changed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('cross_sell_needs_reason', e like 'give a reason%', e);
  v := b2c.correct_lead(900001, '{"course":"Executive MBA"}', '7 years of experience');
  insert into r (name, ok, detail) values ('cross_sell_recorded', exists (select 1 from b2c.field_history where lead_id = 900001 and field = 'course' and kind = 'cross_sell')
    and (select body -> 'set' ->> 'course' from b2c.outbox where lead_id = 900001 and kind = 'update' and status = 'queued') = 'Executive MBA'
    and b2c.pending_set(900001) ->> 'course' = 'Executive MBA', v::text);
  begin perform b2c.correct_lead(900001, '{"phone":"919000000077"}', 'x'); e := 'changed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('phone_not_correctable', e = 'you cannot change phone', e);

  -- WhatsApp: free text only inside the window
  begin perform b2c.wa_queue_text(900001, 'hello'); e := 'sent'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('free_text_needs_window', e like 'the 24-hour window is closed%', e);
  perform pg_temp.as_system();
  v := b2c.wa_inbound('{"from":"919000000001","text":"Papa wants to know about EMI","wamid":"wamid.test.1"}');
  insert into r (name, ok, detail) values ('inbound_to_counsellor', v ->> 'status' = 'to_counsellor', v::text);
  perform pg_temp.as_user(v_owner);
  insert into r (name, ok, detail) values ('free_text_after_reply', b2c.wa_queue_text(900001, 'Yes, no-cost EMI is available') is not null, null);
  insert into r (name, ok, detail) values ('compose_lists_sales_templates', jsonb_array_length(b2c.wa_compose(900001) -> 'templates') >= 3, null);

  -- hand back: the rules give it to someone else
  v := b2c.hand_back(900003, 'student prefers a Marathi speaker');
  perform pg_temp.as_system();
end $x$;

do $x$
begin
  insert into r (name, ok, detail) values ('hand_back_moves_lead',
    (select owner_id from b2c.leads_state where lead_id = 900003) is distinct from (select user_id from b2c.assignments where lead_id = 900003 order by id limit 1), null);
end $x$;

-- ---------- Lost → pool ----------
do $x$
declare v jsonb; v_owner uuid := (select owner_id from b2c.leads_state where lead_id = 900002); s b2c.leads_state;
begin
  perform pg_temp.as_user(v_owner);
  v := b2c.set_stage(900002, 10::smallint, 'Not now, later', 'next year', null);
  perform pg_temp.as_system();
  select * into s from b2c.leads_state where lead_id = 900002;
  insert into r (name, ok, detail) values ('lost_returns_to_pool', s.status = 'pool' and s.owner_id is null and s.pool_reason = 'counsellor_lost'
    and s.first_message_due_at between now() + interval '29 days' and now() + interval '31 days' and s.journey = 'monthly_update', to_jsonb(s)::text);
  insert into r (name, ok, detail) values ('lost_tasks_cancelled', not exists (select 1 from b2c.tasks where lead_id = 900002 and status = 'open'), null);
end $x$;

-- ---------- consent round trip (contract §1.3) and opt-out ----------
do $x$
declare v jsonb; q b2c.consent_requests; s jsonb;
begin
  perform b2c.handoff_receive(pg_temp.env('t-evt-20', 'b2c.consent_requested', 900003, jsonb_build_object('request_id', 77001, 'context', 'decision', 'programme', 'MBA',
    'text', 'To connect you with the best admission counsellor for MBA, may we share your details with our admission partner? Reply YES or NO.',
    'text_version', 'wa_partner_consent:v1', 'expires_at', now() + interval '48 hours')));
  select * into q from b2c.consent_requests where request_id = 77001;
  insert into r (name, ok, detail) values ('consent_send_queued', q.status = 'queued' and q.send_message_id is not null, to_jsonb(q)::text);
  s := b2c.send_take(50);
  insert into r (name, ok, detail) values ('send_take_dry_run_for_test', not exists (select 1 from jsonb_array_elements(s) x where (x ->> 'live')::boolean), s::text);
  perform b2c.send_done((select jsonb_agg(jsonb_build_object('id', (x ->> 'id')::bigint, 'ok', true, 'dry_run', true, 'wamid', 'wamid.out.' || (x ->> 'id'))) from jsonb_array_elements(s) x));
  insert into r (name, ok, detail) values ('consent_sent_reported_urgent', exists (select 1 from b2c.outbox where kind = 'event' and urgent and body ->> 'type' = 'b2ccrm.consent_request_sent'
    and (body -> 'data' ->> 'request_id')::bigint = 77001), null);
  v := b2c.wa_inbound('{"from":"919000000003","button":"YES","wamid":"wamid.student.yes"}');
  insert into r (name, ok, detail) values ('consent_yes_with_wamid', v ->> 'status' = 'consent_yes' and exists (select 1 from b2c.outbox where kind = 'event' and urgent
    and body ->> 'type' = 'b2ccrm.partner_consent' and body -> 'data' ->> 'message_id' = 'wamid.student.yes' and body -> 'data' ->> 'answer' = 'yes'), v::text);
  -- a text that differs from ours is held, not sent
  perform b2c.handoff_receive(pg_temp.env('t-evt-21', 'b2c.consent_requested', 900003, '{"request_id":77002,"programme":"MBA","text":"Different words entirely"}'));
  insert into r (name, ok, detail) values ('consent_wording_mismatch_held', (select status from b2c.consent_requests where request_id = 77002) = 'held', null);
  -- STOP opts out at once, everywhere
  v := b2c.wa_inbound('{"from":"919000000004","text":"STOP","wamid":"wamid.stop.1"}');
  insert into r (name, ok, detail) values ('stop_opts_out', v ->> 'status' = 'opted_out' and b2c.may_message(900004) = 'opted out'
    and exists (select 1 from b2c.outbox where kind = 'event' and urgent and body ->> 'type' = 'b2ccrm.opted_out' and lead_id = 900004)
    and not exists (select 1 from b2c.send_queue where lead_id = 900004 and status = 'queued'), v::text);
  -- an unknown number becomes a new-lead request through the Intake API
  v := b2c.wa_inbound('{"from":"919000000088","text":"Hi, I want an MBA","wamid":"wamid.new.1","profile_name":"New Test"}');
  insert into r (name, ok, detail) values ('unknown_number_intake', v ->> 'status' = 'new_lead_requested' and exists (select 1 from b2c.outbox where kind = 'intake' and urgent and body ->> 'lead_source' = 'b2c_whatsapp'), v::text);
end $x$;

-- ---------- outbox: urgent now, the rest in the 15-minute batch ----------
do $x$
declare u jsonb; b jsonb; v_upd bigint;
begin
  u := b2c.outbox_take('urgent', 400);
  insert into r (name, ok, detail) values ('urgent_take_only_urgent', jsonb_array_length(u) > 0 and not exists (select 1 from jsonb_array_elements(u) x where not (x ->> 'urgent')::boolean), null);
  b := b2c.outbox_take('batch', 400);
  insert into r (name, ok, detail) values ('batch_takes_the_rest', exists (select 1 from jsonb_array_elements(b) x where x ->> 'kind' = 'update')
    and exists (select 1 from jsonb_array_elements(b) x where x ->> 'kind' = 'activity'), jsonb_array_length(b)::text);
  select (x ->> 'id')::bigint into v_upd from jsonb_array_elements(b) x where x ->> 'kind' = 'update' and (x ->> 'lead_id')::bigint = 900001;
  perform b2c.outbox_done(jsonb_build_array(jsonb_build_object('id', v_upd, 'ok', true, 'status', 200,
            'answer', jsonb_build_object('version', 5, 'record', pg_temp.rec(900001, '919000000001', 'Asha Test', 'Executive MBA')))));
  insert into r (name, ok, detail) values ('applied_caches_record', (select version from b2c.lead_records where lead_id = 900001) = 5
    and (select status from b2c.outbox where id = v_upd) = 'applied', null);
  perform b2c.outbox_done((select jsonb_agg(jsonb_build_object('id', (x ->> 'id')::bigint, 'ok', false, 'status', 503)) from jsonb_array_elements(u) x));
  insert into r (name, ok, detail) values ('server_error_retries', not exists (select 1 from jsonb_array_elements(u) x join b2c.outbox o on o.id = (x ->> 'id')::bigint
    where o.status <> 'queued' or o.next_attempt_at <= now()), null);
end $x$;

-- ---------- routing to partners (B4.2) ----------
do $x$
declare v jsonb;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b001');
  v := b2c.route_to_partners(array[900001::bigint, 900003::bigint], 'student wants a weekend batch from a partner');
  insert into r (name, ok, detail) values ('barred_lead_refused', exists (select 1 from jsonb_array_elements(v -> 'refused') x where (x ->> 'lead_id')::bigint = 900001 and x ->> 'why' = 'partner-barred')
    and (v ->> 'sent')::int = 1, v::text);
  perform pg_temp.as_system();
  perform b2c.handoff_receive(pg_temp.env('t-evt-30', 'b2b.lead_routed_to_partner', 900003, '{"origin":"to_partners"}'));
  insert into r (name, ok, detail) values ('routed_closes_pipeline', (select status = 'closed' and closed_reason = 'routed_to_partner' from b2c.leads_state where lead_id = 900003)
    and not exists (select 1 from b2c.tasks where lead_id = 900003 and status = 'open'), null);
end $x$;

-- ---------- roles ----------
do $x$
declare e text; v jsonb;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b005');      -- Marketing
  v := b2c.lead_list('{"include_test": true}');
  insert into r (name, ok, detail) values ('marketing_sees_all', (v ->> 'total')::int >= 5, v ->> 'total');
  begin perform b2c.set_stage(900005, 3::smallint, 'Spoke briefly', null, now() + interval '1 day'); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('marketing_cannot_work_leads', e = 'not allowed', e);
  insert into r (name, ok, detail) values ('marketing_can_tag', b2c.tag(array[900005::bigint], 'diwali', true) = 1, null);
  begin perform b2c.reassign(array[900005::bigint], null, 'try'); e := 'reassigned'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('marketing_cannot_reassign', e = 'not allowed', e);
  perform pg_temp.as_system();
end $x$;

-- ---------- sales email templates fork on edit ----------
do $x$
declare v_a bigint; v_b bigint;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b002');
  v_a := b2c.email_template_save('{"name":"After first call","category":"after_call","subject":"Our call","body":"Hi {{first_name}}"}');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b003');
  v_b := b2c.email_template_save(jsonb_build_object('id', v_a, 'name', 'After first call (Rohan)', 'subject', 'Our call today', 'body', 'Hello {{first_name}}'));
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('fork_on_edit', v_b <> v_a and (select parent_id from b2c.sales_email_templates where id = v_b) = v_a
    and (select body from b2c.sales_email_templates where id = v_a) = 'Hi {{first_name}}', null);
end $x$;

-- ---------- enrolment and verification ----------
do $x$
declare e text; v bigint; v_owner uuid := (select owner_id from b2c.leads_state where lead_id = 900005);
begin
  perform pg_temp.as_user(v_owner);
  begin perform b2c.enrollment_record('{"lead_id":900005,"university":"Amity Online","programme":"Online MBA","fee":179000,"enrolled_on":"2026-10-09"}'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('enrolment_needs_proof', e like 'an enrolment needs%', e);
  v := b2c.enrollment_record('{"lead_id":900005,"university":"Amity Online","programme":"Online MBA","fee":179000,"fee_paid":179000,"enrolled_on":"2026-10-09","proof_path":"leads/900005/receipt.pdf"}');
  insert into r (name, ok, detail) values ('enrolled_full', (select stage_id = 9 and sub_stage = 'Fee paid (full)' from b2c.leads_state where lead_id = 900005), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b001');
  perform b2c.enrollment_verify(v, true);
  begin perform b2c.lead_delete(array[900005::bigint], 'junk'); e := 'deleted'; exception when others then e := sqlerrm; end;
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('verified_closes', (select status = 'verified' from b2c.enrollments where id = v)
    and (select sub_stage = 'Verified by Admin' and status = 'closed' from b2c.leads_state where lead_id = 900005), null);
  insert into r (name, ok, detail) values ('enrolled_lead_not_deleted', (select deleted_at is null from b2c.leads_state where lead_id = 900005), e);
end $x$;

-- ---------- SLA, reminders, simulation ----------
do $x$
declare v jsonb;
begin
  update b2c.leads_state set sla_due_at = now() - interval '1 minute', sla_met_at = null, first_contacted_at = null, sla_breached_at = null where lead_id = 900002;
  update b2c.leads_state set status = 'active' where lead_id = 900002;
  v := to_jsonb(b2c.sla_tick());
  insert into r (name, ok, detail) values ('sla_breach', (v #>> '{}')::int >= 1 and (select sla_breached_at is not null from b2c.leads_state where lead_id = 900002), v::text);
  update b2c.tasks set due_at = now() + interval '5 minutes', reminded_at = null where id = (select id from b2c.tasks where status = 'open' order by id limit 1);
  v := b2c.reminder_tick();
  insert into r (name, ok, detail) values ('reminder_10_min', (v ->> 'reminders')::int >= 1 and exists (select 1 from b2c.notifications where kind = 'reminder' and link like '/s/leads/%'), v::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000b001');
  v := b2c.simulate(((now() at time zone 'Asia/Kolkata')::date - 1), (now() at time zone 'Asia/Kolkata')::date + 1);
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('simulation_runs', (v ->> 'leads')::int = 0, v::text);   -- test leads are left out of simulations
  v := b2c.minute_tick();
  insert into r (name, ok, detail) values ('minute_tick_clean', not exists (select 1 from jsonb_object_keys(v) k where k like '%error'), v::text);
end $x$;

-- ---------- grants: what the app's signed-in role may call, and what it may not ----------
insert into r (name, ok, detail)
select 'authenticated_can_call', bool_and(has_function_privilege('authenticated', f, 'execute')), string_agg(f, ', ') filter (where not has_function_privilege('authenticated', f, 'execute'))
  from unnest(array['b2c.me()', 'b2c.mfa_verify(text,boolean,text)', 'b2c.today()', 'b2c.lead_list(jsonb)', 'b2c.lead_detail(bigint)',
    'b2c.set_stage(bigint,smallint,text,text,timestamptz,text,text)', 'b2c.call_tap(bigint,bigint)', 'b2c.call_log(bigint,text,integer,text,timestamptz,text,text)',
    'b2c.task_done(bigint,text,timestamptz,text,text)', 'b2c.add_contact(bigint,text,text,text,text[])', 'b2c.correct_lead(bigint,jsonb,text)',
    'b2c.wa_compose(bigint)', 'b2c.wa_queue_template(bigint,bigint,jsonb)', 'b2c.wa_queue_text(bigint,text)', 'b2c.inbox_list(jsonb)',
    'b2c.email_template_save(jsonb)', 'b2c.application_save(jsonb)', 'b2c.enrollment_record(jsonb)', 'b2c.enrollment_verify(bigint,boolean,text)',
    'b2c.new_lead(jsonb,jsonb)', 'b2c.route_to_partners(bigint[],text)', 'b2c.reassign(bigint[],uuid,text)', 'b2c.hand_back(bigint,text)',
    'b2c.rule_save(jsonb)', 'b2c.simulate(date,date)', 'b2c.team()', 'b2c.user_save(jsonb)', 'b2c.programme_search(jsonb)', 'b2c.admin_home()',
    'b2c.notifications_mine(integer)', 'b2c.set_away(integer)', 'b2c.is_staff()', 'b2c.can_see(bigint)', 'b2c.uid()']) f;
insert into r (name, ok, detail)
select 'authenticated_cannot_call_internals', not bool_or(has_function_privilege('authenticated', f, 'execute')), string_agg(f, ', ') filter (where has_function_privilege('authenticated', f, 'execute'))
  from unnest(array['b2c.mfa_issue(uuid,uuid)', 'b2c.handoff_receive(jsonb,text)', 'b2c.apply_envelope(text)', 'b2c.apply_record(bigint,integer,bigint,jsonb,text)',
    'b2c.outbox_take(text,integer)', 'b2c.outbox_done(jsonb)', 'b2c.allocate(bigint,text,uuid)', 'b2c.assign(bigint,uuid,bigint,text,text)',
    'b2c.queue_update(bigint,jsonb,boolean)', 'b2c.send_take(integer)', 'b2c.send_done(jsonb)', 'b2c.wa_inbound(jsonb)', 'b2c.minute_tick()',
    'b2c.job_call(text)', 'b2c.directory_sync(jsonb)', 'b2c.notify(uuid,text,text,text,text,bigint,text)', 'b2c.close_lead(bigint,text,text)',
    'b2c.reengage(bigint,text)', 'b2c.working_window(uuid,date)', 'b2c.decide(bigint,text,timestamptz,uuid,boolean)']) f;
insert into r (name, ok, detail) values ('anon_has_nothing', not has_schema_privilege('anon', 'b2c', 'usage'), null);

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
