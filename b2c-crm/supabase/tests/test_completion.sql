-- Completion checks (b39 onward: docs/completion-gaps.md), rolled back. Every row of the final select must say ok = true.
-- Writes only test users and test leads (phones 9100009996xx); safe on staging (SQL editor) and on a local copy.
begin;
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000e901', 'asha.cp@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e902', 'bala.cp@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e903', 'meera.cp@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000e904', 'admin.cp@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, takes_leads, languages) values
  ('aaaaaaaa-0000-0000-0000-00000000e901', 'asha.cp@eduwit.in', 'Asha CP', 'counsellor', true, true, true, '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000e902', 'bala.cp@eduwit.in', 'Bala CP', 'counsellor', true, true, true, '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000e903', 'meera.cp@eduwit.in', 'Meera CP', 'marketing', true, true, false, '{English}'),
  ('aaaaaaaa-0000-0000-0000-00000000e904', 'admin.cp@eduwit.in', 'Admin CP', 'admin', true, true, false, '{English}');
delete from b2c.holidays;
insert into b2c.work_patterns (user_id, isodow, start_t, end_t)
select u.user_id, d, '00:00', '23:59' from b2c.users u, generate_series(1, 7) d where u.email like '%.cp@eduwit.in' on conflict do nothing;
update b2c.settings set value = value || '{"quiet_start": "00:00", "quiet_end": "23:59"}' where key = 'messaging';
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'session_id', ('bbbbbbbb-0000-0000-0000-' || right(p::text, 12))::uuid)::text, true);
end $f$;
create function pg_temp.as_system() returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims', '', true); end $f$;
insert into b2c.session_checks (session_id, user_id, method)
select ('bbbbbbbb-0000-0000-0000-' || right(user_id::text, 12))::uuid, user_id, 'email_code' from b2c.users where email like '%.cp@eduwit.in' on conflict do nothing;

/* A test lead: the record, then the hand-off with the given data. */
create function pg_temp.lead(p_id bigint, p_handoff jsonb, p_extra jsonb default '{}') returns void language plpgsql as $f$
begin
  perform b2c.handoff_receive(jsonb_build_object('id', 'cp-' || p_id || '-u', 'type', 'b2c.lead_upserted', 'lead_id', p_id, 'occurred_at', now(), 'test', true, 'contract_version', 3,
    'data', jsonb_build_object('version', 1, 'seq', 1, 'record', jsonb_build_object('id', p_id, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
      'student', jsonb_build_object('name', 'CP Student ' || p_id, 'phone', '9100009996' || right(p_id::text, 2), 'email', 'cp' || p_id || '@example.com'),
      'education', jsonb_build_object('highest_qualification', 'B.Com'), 'interest', jsonb_build_object('course', 'MBA'),
      'consent', jsonb_build_object('state', 'given', 'opted_out', false), 'source', jsonb_build_object('lead_source', 'website')) || p_extra)), 'test');
  perform b2c.handoff_receive(jsonb_build_object('id', 'cp-' || p_id || '-h', 'type', 'b2c.lead_handed_off', 'lead_id', p_id, 'occurred_at', now(), 'test', true,
    'contract_version', 3, 'data', p_handoff), 'test');
end $f$;
create function pg_temp.env(p_id text, p_type text, p_lead bigint, p_data jsonb) returns jsonb language sql as $f$
  select jsonb_build_object('id', p_id, 'type', p_type, 'lead_id', p_lead, 'occurred_at', now(), 'test', true, 'contract_version', 3, 'data', p_data)
$f$;

-- ========== b39: nurture and re-engagement ==========
-- A1 qualification first: a not-qualified lead that re-engages is not sold to
do $x$
declare j jsonb; q b2c.qualify_requests; s b2c.leads_state; e text; v_tok text;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996601, '{"b2c_lane": "nurture", "reason": "not_qualified", "missing": ["course", "highest_qualification"]}'::jsonb);
  perform b2c.marketing_consent(996601, 'whatsapp', true, 'test');
  j := b2c.wa_inbound(jsonb_build_object('from', '910000999601', 'text', 'Yes, call me', 'wamid', 'cp-wamid-1'));
  select * into s from b2c.leads_state where lead_id = 996601;
  select * into q from b2c.qualify_requests where lead_id = 996601;
  insert into r (name, ok, detail) values ('a1_not_qualified_reply_not_assigned', s.status = 'pool' and s.owner_id is null and q.status = 'waiting', j::text || ' ' || s.status);
  insert into r (name, ok, detail) values ('a1_asks_only_the_missing_details', q.questions = '["course", "highest_qualification"]'::jsonb, q.questions::text);
  insert into r (name, ok, detail) values ('a1_form_link_sent_in_the_window',
    exists (select 1 from b2c.send_queue x where x.lead_id = 996601 and x.purpose = 'qualify' and x.payload ->> 'type' = 'text' and x.payload ->> 'text' like '%/q/' || q.token || '%'), null);
  insert into r (name, ok, detail) values ('a1_timeline_says_why', exists (select 1 from b2c.activities a where a.lead_id = 996601 and a.body like '%not assigned for selling%'), null);
  -- a second trigger does not open a second request
  j := b2c.reengage(996601, 'score');
  insert into r (name, ok, detail) values ('a1_one_request_at_a_time', (select count(*) from b2c.qualify_requests where lead_id = 996601) = 1 and (j ->> 'already')::boolean, j::text);
  -- 48 hours later: a To qualify task for the Admin
  update b2c.qualify_requests set due_at = now() - interval '1 minute' where lead_id = 996601;
  j := b2c.qualify_tick();
  select * into q from b2c.qualify_requests where lead_id = 996601;
  insert into r (name, ok, detail) values ('a1_after_48h_to_qualify_task',
    q.status = 'escalated' and exists (select 1 from b2c.tasks t where t.id = q.task_id and t.kind = 'qualify' and t.owner_id is null and t.status = 'open'), j::text);
  -- a counsellor cannot see it until the Admin gives them the task
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  insert into r (name, ok, detail) values ('a1_counsellor_cannot_see_before', not b2c.can_see(996601), null);
  begin perform b2c.qualify_record(996601, '{"course": "Online MBA"}'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a1_counsellor_cannot_record_before', e = 'not allowed', e);
  begin perform b2c.qualify_queue(); e := 'listed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a1_queue_is_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  insert into r (name, ok, detail) values ('a1_admin_sees_the_queue', jsonb_array_length(b2c.qualify_queue('{"test": true}')) >= 1, null);
  perform b2c.qualify_assign(q.id, 'aaaaaaaa-0000-0000-0000-00000000e901');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  insert into r (name, ok, detail) values ('a1_counsellor_sees_after_assignment', b2c.can_see(996601), null);
  j := b2c.qualify_record(996601, '{"course": "Online MBA", "highest_qualification": "B.Com", "phone": "999"}');
  select * into q from b2c.qualify_requests where lead_id = 996601;
  insert into r (name, ok, detail) values ('a1_details_recorded_and_sent_to_b2b',
    q.status = 'answered' and q.answered_via = 'staff'
    and exists (select 1 from b2c.outbox o where o.lead_id = 996601 and o.kind = 'update' and o.body -> 'set' ->> 'course' = 'Online MBA' and not (o.body -> 'set' ? 'phone'))
    and exists (select 1 from b2c.outbox o where o.lead_id = 996601 and o.kind = 'event' and o.body ->> 'type' = 'b2ccrm.qualification_completed'), j::text);
  insert into r (name, ok, detail) values ('a1_task_closed', not exists (select 1 from b2c.tasks t where t.lead_id = 996601 and t.kind = 'qualify' and t.status = 'open'), null);
  insert into r (name, ok, detail) values ('a1_counsellor_loses_access_after', not b2c.can_see(996601), null);
  perform pg_temp.as_system();
  -- the public form: open once, then closed
  perform pg_temp.lead(996602, '{"b2c_lane": "nurture", "reason": "not_qualified", "missing": []}'::jsonb);
  j := b2c.qualify_start(996602, 'witty_interest');
  select token into v_tok from b2c.qualify_requests where lead_id = 996602;
  j := b2c.qualify_form(v_tok);
  insert into r (name, ok, detail) values ('a1_form_default_three_questions', j ->> 'status' = 'open' and jsonb_array_length(j -> 'questions') = 3, j::text);
  j := b2c.qualify_submit(v_tok, '{"course": "MCA", "enrollment_timeline": "next month"}');
  insert into r (name, ok, detail) values ('a1_form_scores_form_filled', exists (select 1 from b2c.score_events x where x.lead_id = 996602 and x.rule_key = 'form_filled'), j::text);
  begin perform b2c.qualify_submit(v_tok, '{"course": "MBA"}'); e := 'again'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a1_form_works_once', e = 'this link is no longer open', e);
  insert into r (name, ok, detail) values ('a1_bad_token', b2c.qualify_form('nope') ->> 'status' = 'unknown', null);
  -- a person handing it over on purpose still assigns it
  perform pg_temp.lead(996603, '{"b2c_lane": "nurture", "reason": "not_qualified", "missing": ["course"]}'::jsonb);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  j := b2c.nurture_handover(996603, 'student called the office');
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('a1_handover_still_assigns', (select status from b2c.leads_state where lead_id = 996603) = 'active'
    and not exists (select 1 from b2c.qualify_requests where lead_id = 996603), j::text);
  -- B2B's "re-engaged, still missing" starts the same step
  perform pg_temp.lead(996604, '{"b2c_lane": "nurture", "reason": "not_qualified", "missing": ["email"]}'::jsonb);
  j := b2c.handoff_receive(pg_temp.env('cp-reeng-996604', 'b2c.lead_reengaged', 996604, '{"missing": ["email"], "trigger": "witty_interest"}'), 'test');
  insert into r (name, ok, detail) values ('a1_b2b_reengaged_starts_qualification', exists (select 1 from b2c.qualify_requests where lead_id = 996604 and questions = '["email"]'::jsonb), j::text);
end $x$;

-- A2 opting in again
do $x$
declare j jsonb; e text;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996605, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"partner_name": "Up Edu", "lost_reason": "later"}}'::jsonb);
  j := b2c.wa_inbound(jsonb_build_object('from', '910000999605', 'text', 'STOP', 'wamid', 'cp-wamid-5a'));
  insert into r (name, ok, detail) values ('a2_stop_opts_out', b2c.may_message(996605) = 'opted out', j::text);
  j := b2c.wa_inbound(jsonb_build_object('from', '910000999605', 'text', 'hello', 'wamid', 'cp-wamid-5b'));
  insert into r (name, ok, detail) values ('a2_message_while_opted_out_does_nothing', j ->> 'status' = 'opted_out_received' and b2c.may_message(996605) = 'opted out', j::text);
  j := b2c.wa_inbound(jsonb_build_object('from', '910000999605', 'text', 'START', 'wamid', 'cp-wamid-5c'));
  insert into r (name, ok, detail) values ('a2_start_opts_in_again', j ->> 'status' = 'opted_in' and b2c.may_message(996605) is null and b2c.has_marketing_consent(996605, 'whatsapp'), j::text);
  j := b2c.wa_inbound(jsonb_build_object('from', '910000999605', 'text', 'stop', 'wamid', 'cp-wamid-5d'));
  insert into r (name, ok, detail) values ('a2_stop_again_counts_again', b2c.may_message(996605) = 'opted out', j::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  begin perform b2c.opt_in(996605, null, 'staff'); e := 'done'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a2_staff_must_say_how', e like 'say how%', e);
  j := b2c.opt_in(996605, array['email'], 'staff', 'Student emailed asking to hear from us again');
  insert into r (name, ok, detail) values ('a2_staff_opt_in', b2c.may_message(996605) is null and b2c.has_marketing_consent(996605, 'email'), j::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.opt_in(996605, null, 'staff', 'counsellor tries this'); e := 'done'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a2_counsellor_cannot_opt_in', e = 'not allowed', e);
  perform pg_temp.as_system();
end $x$;

-- A3 scoring triggers and the qualification minimum
do $x$
declare j jsonb;
begin
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('a3_qualification_order',
    b2c.qual_rank('12th') < b2c.qual_rank('B.Com') and b2c.qual_rank('B.Com') < b2c.qual_rank('MBA') and b2c.qual_rank('Diploma') < b2c.qual_rank('Graduate')
    and b2c.qual_rank('') is null and b2c.qual_rank('SSC') = 1, null);
  perform pg_temp.lead(996606, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"partner_name": "Up Edu", "lost_reason": "later"}}'::jsonb);
  j := b2c.handoff_receive(pg_temp.env('cp-reenq-996606', 'b2c.lead_reenquired', 996606, '{"what": {"source_system": "witty", "event_type": "chat"}}'), 'test');
  insert into r (name, ok, detail) values ('a3_witty_resumed_scores', exists (select 1 from b2c.score_events where lead_id = 996606 and rule_key = 'witty_resumed'), j::text);
  insert into r (name, ok, detail) values ('a3_reenquiry_still_reengages', (select status from b2c.leads_state where lead_id = 996606) = 'active', null);
  perform pg_temp.lead(996607, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"partner_name": "Up Edu", "lost_reason": "later"}}'::jsonb);
  update b2c.leads_state set status = 'active', owner_id = 'aaaaaaaa-0000-0000-0000-00000000e901' where lead_id = 996607;
  j := b2c.handoff_receive(pg_temp.env('cp-reenq-996607', 'b2c.lead_reenquired', 996607, '{"what": {"source_system": "meta", "event_type": "lead_form"}}'), 'test');
  insert into r (name, ok, detail) values ('a3_form_filled_scores', exists (select 1 from b2c.score_events where lead_id = 996607 and rule_key = 'form_filled'), j::text);
  perform pg_temp.lead(996608, '{"b2c_lane": "nurture", "reason": "not_qualified", "missing": ["course"]}'::jsonb);
  j := b2c.handoff_receive(pg_temp.env('cp-reenq-996608', 'b2c.lead_reenquired', 996608, '{"interest": true, "what": {"source_system": "witty"}}'), 'test');
  insert into r (name, ok, detail) values ('a3_not_qualified_reenquiry_qualifies', exists (select 1 from b2c.qualify_requests where lead_id = 996608 and trigger = 'witty_interest')
    and (select status from b2c.leads_state where lead_id = 996608) = 'pool', j::text);
end $x$;

-- A4, A5 partner-lost: the sub-stage's delay and journey, and the partner's history
do $x$
declare s b2c.leads_state;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996609, '{"b2c_lane": "nurture", "reason": "partner_lost", "partner_bar": {"reason": "lost"},
      "lost": {"partner_name": "Up Edu", "lost_reason": "Over budget", "partner_status": "Lost", "partner_sub_status": "Fee issue", "partner_last_activity": "2026-10-01"},
      "partners_tried": [{"partner_name": "Up Edu", "outcome": "lost"}, {"partner_name": "Learn Co", "outcome": "duplicate"}]}'::jsonb);
  select * into s from b2c.leads_state where lead_id = 996609;
  insert into r (name, ok, detail) values ('a4_over_budget_waits_7_days', s.first_message_due_at between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour',
                                          s.first_message_due_at::text);
  insert into r (name, ok, detail) values ('a4_maps_to_sub_stage', b2c.partner_lost_sub_stage('Over budget') = 'Can''t afford fee or EMI' and b2c.partner_lost_sub_stage('weird') = 'Other', null);
  insert into r (name, ok, detail) values ('a5_partner_history_on_timeline',
    exists (select 1 from b2c.activities a where a.lead_id = 996609 and a.kind = 'partner_history' and a.body like '%Up Edu%' and a.body like '%Fee issue%' and a.body like '%Learn Co (duplicate)%'), null);
  insert into r (name, ok, detail) values ('a5_partners_tried_kept', jsonb_array_length(s.partners_tried) = 2, null);
  perform pg_temp.lead(996610, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"lost_reason": "something odd"}, "nurture_first_message_after_days": 2}'::jsonb);
  insert into r (name, ok, detail) values ('a4_b2b_days_win', (select first_message_due_at from b2c.leads_state where lead_id = 996610) < now() + interval '2 days 1 hour', null);
  perform pg_temp.lead(996611, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"lost_reason": "something odd"}}'::jsonb);
  insert into r (name, ok, detail) values ('a4_unmapped_uses_other_30_days', (select first_message_due_at from b2c.leads_state where lead_id = 996611) > now() + interval '29 days', null);
end $x$;

-- E1 flagged leads wait for the Admin
do $x$
declare j jsonb; e text;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996612, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"lost_reason": "later"}}'::jsonb);
  perform b2c.marketing_consent(996612, 'whatsapp', true, 'test');
  j := b2c.handoff_receive(pg_temp.env('cp-flag-996612', 'b2c.lead_flagged', 996612, '{"classification": "junk"}'), 'test');
  insert into r (name, ok, detail) values ('e1_flagged_no_marketing', b2c.may_market(996612, 'whatsapp') = 'wait: flagged for review', b2c.may_market(996612, 'whatsapp'));
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  begin perform b2c.flag_review(996612, 'keep'); e := 'done'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('e1_review_is_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  insert into r (name, ok, detail) values ('e1_on_the_review_list', exists (select 1 from jsonb_array_elements(b2c.flagged_list()) x where (x ->> 'lead_id')::bigint = 996612), null);
  perform b2c.flag_review(996612, 'keep', 'real student');
  insert into r (name, ok, detail) values ('e1_keep_clears', (select flagged from b2c.leads_state where lead_id = 996612) is null and b2c.may_market(996612, 'whatsapp') is distinct from 'wait: flagged for review', null);
  perform pg_temp.as_system();
  perform pg_temp.lead(996613, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  j := b2c.handoff_receive(pg_temp.env('cp-flag-996613', 'b2c.lead_flagged', 996613, '{"classification": "programme mismatch"}'), 'test');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  perform b2c.flag_review(996613, 'cannot_serve', 'we do not offer this');
  insert into r (name, ok, detail) values ('e1_agree_closes_as_lost', (select stage_id = 10 and status = 'closed' from b2c.leads_state where lead_id = 996613), null);
  perform pg_temp.as_system();
end $x$;

-- A7 journeys: new triggers and the update step
do $x$
declare v bigint; e text; j jsonb;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  begin perform b2c.journey_save('{"name": "x", "trigger": {"type": "moon"}}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a7_unknown_trigger_refused', e = 'unknown trigger moon', e);
  begin perform b2c.journey_save('{"name": "x", "trigger": {"type": "date"}}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a7_date_trigger_needs_date', e = 'a date trigger needs the date', e);
  begin perform b2c.journey_save('{"name": "x", "draft_steps": [{"id": "s1", "type": "update", "field": "name", "value": "Bob"}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a7_update_cannot_change_identity', e like '%cannot change name', e);
  v := b2c.journey_save(jsonb_build_object('name', 'CP deadline', 'test_mode', true,
         'trigger', jsonb_build_object('type', 'date', 'at', ((now() at time zone 'Asia/Kolkata')::date + 5)::text, 'days_before', 7),
         'draft_steps', '[{"id": "s1", "type": "update", "field": "temperature", "value": "warm"}, {"id": "s2", "type": "update", "field": "untag", "value": "cold_list"},
                          {"id": "s3", "type": "exit", "reason": "done"}]'::jsonb));
  perform b2c.journey_publish(v);
  perform b2c.journey_set(v, 'active');
  perform pg_temp.as_system();
  perform pg_temp.lead(996614, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"lost_reason": "later"}}'::jsonb);
  update b2c.leads_state set tags = '{cold_list}', first_message_due_at = now() + interval '30 days' where lead_id = 996614;
  j := b2c.journey_tick(50);
  insert into r (name, ok, detail) values ('a7_date_trigger_enters', exists (select 1 from b2c.journey_runs where lead_id = 996614 and journey_id = v), j::text);
  insert into r (name, ok, detail) values ('a7_update_step_runs', (select temperature = 'warm' and not ('cold_list' = any (tags)) from b2c.leads_state where lead_id = 996614), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  j := b2c.journey_stats(v);
  insert into r (name, ok, detail) values ('a8_journey_cost_shown', j ? 'wa_cost' and j ? 'emails', j::text);
  j := b2c.nurture_overview();
  insert into r (name, ok, detail) values ('a6_overview_outflow_and_deliverability', j ? 'deliverability_7d' and j -> 'flow_14d' -> 0 ? 'dormant' and j -> 'flow_14d' -> 0 ? 'opted_out' and j ? 'to_qualify', null);
  perform pg_temp.as_system();
end $x$;

-- A11 a designated counsellor answers the Replies inbox
do $x$
declare e text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  insert into r (name, ok, detail) values ('a11_counsellor_not_replies_by_default', not b2c.can('replies'), null);
  begin perform b2c.replies_delegates_set(array['aaaaaaaa-0000-0000-0000-00000000e901']::uuid[]); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a11_only_admin_sets', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  begin perform b2c.replies_delegates_set(array['aaaaaaaa-0000-0000-0000-00000000e903']::uuid[]); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a11_only_counsellors', e = 'choose active counsellors', e);
  perform b2c.replies_delegates_set(array['aaaaaaaa-0000-0000-0000-00000000e901']::uuid[]);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  insert into r (name, ok, detail) values ('a11_delegate_has_replies', b2c.can('replies') and jsonb_typeof(b2c.replies_list('{}')) = 'array', null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e902');
  insert into r (name, ok, detail) values ('a11_others_still_not', not b2c.can('replies'), null);
  perform pg_temp.as_system();
end $x$;

-- ========== b40: leads table and Admin tools ==========
-- B1/B2 the wide row: activity, application and money columns; money hidden from Sales; new filters, groups, group-by, select all
do $x$
declare j jsonb; e text; v bigint; v2 bigint;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996620, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  perform pg_temp.lead(996621, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  update b2c.leads_state set status = 'active', owner_id = 'aaaaaaaa-0000-0000-0000-00000000e901', assigned_at = now() where lead_id in (996620, 996621);
  insert into b2c.calls (lead_id, number, direction, outcome, logged_at, user_id) values (996620, '910000999620', 'out', 'no_answer', now() - interval '1 hour', 'aaaaaaaa-0000-0000-0000-00000000e901'),
    (996620, '910000999620', 'out', 'connected', now(), 'aaaaaaaa-0000-0000-0000-00000000e901');
  insert into b2c.wa_messages (lead_id, phone, direction, kind, body, status) values (996620, '910000999620', 'in', 'text', 'my number is 98...', 'received');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  j := b2c.lead_list('{"filters": {"all": [{"field": "calls_connected", "op": "gte", "value": 1}]}, "include_test": true}');
  insert into r (name, ok, detail) values ('b1_filter_on_sales_activity', (j ->> 'total')::int = 1 and j -> 'rows' -> 0 ->> 'last_call_outcome' = 'connected'
    and (j -> 'rows' -> 0 ->> 'calls_logged')::int = 2 and (j -> 'rows' -> 0 ->> 'wa_received')::int = 1, j::text);
  insert into r (name, ok, detail) values ('b2_money_hidden_from_sales', not (j -> 'rows' -> 0 ? 'university_gross') and not (j -> 'rows' -> 0 ? 'counsellor_commission'), null);
  begin perform b2c.lead_list('{"filters": {"all": [{"field": "university_gross", "op": "gt", "value": 0}]}}'); e := 'listed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b2_cannot_filter_on_money_in_sales', e = 'cannot filter on university_gross', e);
  j := b2c.lead_list('{"filters": {"all": [{"field": "created_at", "op": "this_month"}, {"field": "lead_id", "op": "in", "value": ["996620", "996621"]}]}, "include_test": true}');
  insert into r (name, ok, detail) values ('b1_this_month', (j ->> 'total')::int = 2, j ->> 'total');
  j := b2c.lead_list('{"filters": {"all": [{"field": "lead_id", "op": "in", "value": ["996620", "996621"]}],
        "groups": [{"any": [{"field": "calls_logged", "op": "gte", "value": 1}, {"field": "name", "op": "contains", "value": "nobody"}]}]}, "include_test": true}');
  insert into r (name, ok, detail) values ('b1_or_groups', (j ->> 'total')::int = 1, j ->> 'total');
  j := b2c.lead_list('{"filters": {"all": [{"field": "lead_id", "op": "in", "value": ["996620", "996621"]}]}, "group_by": "last_call_outcome", "include_test": true}');
  insert into r (name, ok, detail) values ('b1_group_by_counts', jsonb_array_length(j -> 'groups') = 2 and not (j -> 'groups' -> 0 ? 'expected'), j -> 'groups' ->> 0);
  j := b2c.lead_list('{"mode": "ids", "filters": {"all": [{"field": "lead_id", "op": "in", "value": ["996620", "996621"]}]}, "include_test": true}');
  insert into r (name, ok, detail) values ('b3_select_all_of_a_view', j -> 'ids' = '[996620, 996621]'::jsonb, j::text);
  j := b2c.lead_list('{"ids": [996621], "include_test": true}');
  insert into r (name, ok, detail) values ('b5_selected_rows_only', (j ->> 'total')::int = 1, j ->> 'total');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e902');
  j := b2c.lead_list('{"ids": [996620, 996621], "include_test": true}');
  insert into r (name, ok, detail) values ('b1_counsellor_scope_kept', (j ->> 'total')::int = 0, j ->> 'total');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  j := b2c.lead_list('{"ids": [996620], "group_by": "owner_name", "include_test": true}');
  insert into r (name, ok, detail) values ('b2_admin_sees_money_columns', j -> 'rows' -> 0 ? 'university_gross' and j -> 'groups' -> 0 ? 'expected', null);

  -- views shared with the same role by link, a default per person
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.view_save('{"name": "x", "columns": ["name", "password"]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b1_unknown_column_refused', e = 'unknown column', e);
  begin perform b2c.view_save('{"name": "x", "shared_with_role": "admin"}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b1_share_own_role_only', e = 'a view can be shared with your own role only', e);
  v := b2c.view_save('{"name": "CP shared", "columns": ["name", "calls_logged", "last_call_outcome"], "group_by": "stage", "layout": "kanban", "shared_with_role": "counsellor"}');
  v2 := b2c.view_save('{"name": "CP private"}');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e902');
  insert into r (name, ok, detail) values ('b1_shared_view_opens_by_link', (b2c.view_get(v) ->> 'layout') = 'kanban'
    and exists (select 1 from jsonb_array_elements(b2c.views_list('sales') -> 'views') x where (x ->> 'id')::bigint = v), null);
  begin perform b2c.view_get(v2); e := 'opened'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b1_private_view_stays_private', e = 'this view is not shared with you', e);
  perform b2c.view_pin('sales', v);
  insert into r (name, ok, detail) values ('b1_pinned_default', (b2c.views_list('sales') ->> 'default')::bigint = v, null);
  perform pg_temp.as_system();
end $x$;

-- B3/B4 bulk: journeys, stage, delete as a job with typed confirmation and undo
do $x$
declare j jsonb; e text; v bigint;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996622, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"lost_reason": "later"}}'::jsonb);
  perform pg_temp.lead(996623, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"lost_reason": "later"}}'::jsonb);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  begin perform b2c.bulk_journey(array[996622]::bigint[], 'add', -1); e := 'added'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b3_journey_must_be_published', e = 'choose a published journey', e);
  v := b2c.journey_save('{"name": "CP bulk", "test_mode": true, "trigger": {"type": "manual"}, "draft_steps": [{"id": "s1", "type": "wait", "hours": 24}, {"id": "s2", "type": "exit", "reason": "done"}]}');
  perform b2c.journey_publish(v);
  perform b2c.journey_set(v, 'active');
  j := b2c.bulk_journey(array[996622, 996623]::bigint[], 'add', v);
  insert into r (name, ok, detail) values ('b3_marketing_adds_to_journey', (j ->> 'done')::int = 2
    and (select count(*) from b2c.journey_runs where journey_id = v and lead_id in (996622, 996623) and status = 'running') = 2, j::text);
  j := b2c.bulk_journey(array[996622]::bigint[], 'remove');
  insert into r (name, ok, detail) values ('b3_marketing_removes_from_journey', (j ->> 'done')::int = 1
    and not exists (select 1 from b2c.journey_runs where journey_id = v and lead_id = 996622 and status = 'running'), j::text);
  begin perform b2c.bulk_stage(array[996622]::bigint[], 3::smallint, null); e := 'changed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b3_stage_is_admin_only', e = 'not allowed', e);
  begin perform b2c.lead_delete_request(array[996622, 996623]::bigint[], 'test', 'DELETE'); e := 'queued'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b3_bulk_delete_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  begin perform b2c.lead_delete_request(array[996622, 996623]::bigint[], 'test', 'DELETE'); e := 'queued'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b3_typed_confirmation', e = 'type DELETE 2 to confirm', e);
  j := b2c.lead_delete_request(array[996622, 996623]::bigint[], 'test', 'DELETE 2');
  insert into r (name, ok, detail) values ('b3_delete_waits_for_the_job', (select count(*) from b2c.leads_state where lead_id in (996622, 996623) and deleted_at is null) = 2, j::text);
  perform pg_temp.as_system();
  perform b2c.bulk_jobs_tick();
  perform b2c.bulk_jobs_tick();
  insert into r (name, ok, detail) values ('b3_job_deletes', (select count(*) from b2c.leads_state where lead_id in (996622, 996623) and deleted_at is not null) = 2
    and (select status from b2c.bulk_jobs where id = (j ->> 'job_id')::bigint) = 'done'
    and not exists (select 1 from b2c.journey_runs where lead_id = 996623 and status = 'running'), (select row_to_json(b)::text from b2c.bulk_jobs b where id = (j ->> 'job_id')::bigint));
  insert into r (name, ok, detail) values ('b3_job_notifies', exists (select 1 from b2c.notifications n where n.user_id = 'aaaaaaaa-0000-0000-0000-00000000e904' and n.kind = 'bulk_job'), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  e := b2c.bulk_job_undo((j ->> 'job_id')::bigint)::text;
  insert into r (name, ok, detail) values ('b3_undo_restores', e = '2'
    and (select count(*) from b2c.leads_state where lead_id in (996622, 996623) and deleted_at is null) = 2, null);
  perform pg_temp.as_system();
end $x$;

-- B4 erasure on the student's request
do $x$
declare j jsonb; e text;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996624, '{"b2c_lane": "nurture", "reason": "partner_lost", "lost": {"lost_reason": "later", "partner_name": "CP Partner"}}'::jsonb);
  insert into b2c.wa_messages (lead_id, phone, direction, kind, body, status) values (996624, '910000999624', 'in', 'text', 'my address is ...', 'received');
  insert into b2c.activities (lead_id, kind, body) values (996624, 'note', 'lives near the station');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  begin perform b2c.lead_erase(996624, 'email 15 Oct'); e := 'erased'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b4_erase_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  begin perform b2c.lead_erase(996624, ''); e := 'erased'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b4_needs_reference', e like 'give the request reference%', e);
  j := b2c.lead_erase(996624, 'email 15 Oct', 'asked by email');
  insert into r (name, ok, detail) values ('b4_identity_gone', (select record -> 'student' ->> 'name' = 'Erased student' and not (record -> 'student' ? 'phone') and not (record -> 'student' ? 'email')
     from b2c.lead_records where lead_id = 996624)
    and not exists (select 1 from b2c.lead_contacts where lead_id = 996624 and value <> 'erased'), j::text);
  insert into r (name, ok, detail) values ('b4_messages_and_notes_gone', not exists (select 1 from b2c.wa_messages where lead_id = 996624 and body is not null)
    and not exists (select 1 from b2c.activities where lead_id = 996624 and kind = 'note' and body <> '[erased]'), null);
  insert into r (name, ok, detail) values ('b4_b2b_told', exists (select 1 from b2c.outbox o where o.kind = 'event' and o.lead_id = 996624 and o.body ->> 'type' = 'b2ccrm.erasure_requested'
    and o.body -> 'data' ->> 'reference' = 'email 15 Oct'), null);
  insert into r (name, ok, detail) values ('b4_logged_with_reference', exists (select 1 from b2c.audit_log a where a.lead_id = 996624 and a.action = 'erase' and a.detail ->> 'reference' = 'email 15 Oct'), null);
  insert into r (name, ok, detail) values ('b4_restore_cannot_bring_back', b2c.lead_restore(array[996624]::bigint[]) = 0, null);
  begin perform b2c.lead_erase(996624, 'again'); e := 'erased'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b4_once_only', e = 'this lead was already erased', e);
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('b4_record_not_refilled', not b2c.apply_record(996624, 99, 99, '{"id": 996624, "student": {"name": "Back", "phone": "910000999624"}}')
    and (select record -> 'student' ->> 'name' from b2c.lead_records where lead_id = 996624) = 'Erased student', null);
end $x$;

-- B5 exports, D1 events feed, D2 published status
do $x$
declare j jsonb; e text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.export_request('{}'); e := 'requested'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('b5_export_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  j := b2c.export_request('{"ids": [996620, 996621], "format": "xlsx", "include_test": true}');
  insert into r (name, ok, detail) values ('b5_small_export_inline', (j ->> 'inline')::boolean and (j ->> 'rows')::int = 2, j::text);
  perform pg_temp.as_system();
  insert into b2c.exports (user_id, params, format) values ('aaaaaaaa-0000-0000-0000-00000000e904', '{"ids": [996620], "include_test": true}', 'csv');
  j := b2c.export_take(5);
  insert into r (name, ok, detail) values ('b5_job_runs_as_the_admin', (b2c.export_page((j -> 0 ->> 'id')::bigint, 0) ->> 'total')::int = 1, j::text);
  perform b2c.export_done((j -> 0 ->> 'id')::bigint, 1, 'exports/x.csv');
  insert into r (name, ok, detail) values ('b5_link_expires_in_7_days', (select expires_at between now() + interval '6 days' and now() + interval '8 days' from b2c.exports where id = (j -> 0 ->> 'id')::bigint), null);
  j := b2c.events_feed(0, 1000);
  insert into r (name, ok, detail) values ('d1_events_feed', exists (select 1 from jsonb_array_elements(j -> 'events') x where x ->> 'type' = 'b2ccrm.erasure_requested' and (x ->> 'lead_id')::bigint = 996624)
    and (j ->> 'next_after')::bigint >= (select max(id) from b2c.outbox where kind = 'event'), null);
  insert into r (name, ok, detail) values ('d2_status_view', exists (select 1 from public.b2c_lead_status_v where lead_id = 996620 and counsellor = 'Asha CP')
    and not exists (select 1 from public.b2c_lead_status_v where lead_id = 996624), null);
end $x$;
insert into r (name, ok, detail) values ('d2_status_view_service_only', not has_table_privilege('authenticated', 'public.b2c_lead_status_v', 'select')
  and not has_table_privilege('anon', 'public.b2c_lead_status_v', 'select') and has_table_privilege('service_role', 'public.b2c_lead_status_v', 'select'), null);
insert into r (name, ok, detail) values ('b2_wide_view_not_for_clients', not has_table_privilege('authenticated', 'b2c.leads_wide_v', 'select'), null);

-- ---------- grants ----------
insert into r (name, ok, detail)
select 'authenticated_can_call', bool_and(has_function_privilege('authenticated', f, 'execute')), string_agg(f, ', ') filter (where not has_function_privilege('authenticated', f, 'execute'))
  from unnest(array['b2c.opt_in(bigint,text[],text,text)', 'b2c.qualify_record(bigint,jsonb)', 'b2c.qualify_queue(jsonb)', 'b2c.qualify_assign(bigint,uuid)',
    'b2c.qualify_resend(bigint)', 'b2c.flag_review(bigint,text,text)', 'b2c.flagged_list()', 'b2c.replies_delegates_set(uuid[])',
    'b2c.views_list(text)', 'b2c.view_get(bigint)', 'b2c.view_pin(text,bigint)', 'b2c.bulk_journey(bigint[],text,bigint)', 'b2c.bulk_stage(bigint[],smallint,text,text,timestamp with time zone)',
    'b2c.lead_delete_request(bigint[],text,text)', 'b2c.bulk_job_undo(bigint)', 'b2c.bulk_jobs_list()', 'b2c.lead_erase(bigint,text,text)', 'b2c.export_request(jsonb)',
    'b2c.exports_mine()', 'b2c.export_open(bigint)']) f;
insert into r (name, ok, detail)
select 'authenticated_cannot_call_internals', not bool_or(has_function_privilege('authenticated', f, 'execute')), string_agg(f, ', ') filter (where has_function_privilege('authenticated', f, 'execute'))
  from unnest(array['b2c.qualify_form(text)', 'b2c.qualify_submit(text,jsonb)', 'b2c.qualify_apply(bigint,jsonb,text,uuid)', 'b2c.qualify_start(bigint,text)',
    'b2c.qualify_tick()', 'b2c.queue_system_email(bigint,text,text,text,text,timestamp with time zone)', 'b2c.queue_system_text(bigint,text,text,text)',
    'b2c.opted_out_now(bigint)', 'b2c.partner_lost_due(jsonb)', 'b2c.erase_files_take(integer)', 'b2c.export_take(integer)', 'b2c.export_page(bigint,integer,integer)',
    'b2c.events_feed(bigint,integer)', 'b2c.bulk_jobs_tick(integer)', 'b2c.lead_delete_job_part(bigint[],text,uuid,bigint)', 'b2c.filter_leads(jsonb,boolean)']) f;
insert into r (name, ok, detail)
select 'anon_calls_nothing', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2c' and has_function_privilege('anon', p.oid, 'execute')), null;

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
