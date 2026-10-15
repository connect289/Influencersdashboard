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

-- ========== b41: counsellor workspace ==========
-- C1 WhatsApp media out and in
do $x$
declare j jsonb; e text; v bigint; m bigint; a bigint; d bigint;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996630, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  update b2c.leads_state set status = 'active', owner_id = 'aaaaaaaa-0000-0000-0000-00000000e901', assigned_at = now(), stage_id = 3 where lead_id = 996630;
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.wa_queue_media(996630, 'image', 'leads/996630/x.png'); e := 'sent'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c1_media_needs_open_window', e like 'the 24-hour window is closed%', e);
  perform pg_temp.as_system();
  j := b2c.wa_inbound(jsonb_build_object('from', '910000999630', 'kind', 'media', 'wamid', 'cp-wamid-630',
         'media', jsonb_build_object('id', 'meta-media-1', 'mime_type', 'application/pdf', 'filename', 'marksheet.pdf', 'caption', 'my marksheet')));
  select id into m from b2c.wa_messages where wamid = 'cp-wamid-630';
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.wa_queue_media(996630, 'image', 'leads/1/x.png'); e := 'sent'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c1_only_from_the_leads_folder', e = 'files are sent from the lead''s folder', e);
  v := b2c.wa_queue_media(996630, 'document', null, 'Our brochure', 'brochure.pdf', 'https://example.com/brochure.pdf');
  insert into r (name, ok, detail) values ('c1_brochure_sent_in_window', exists (select 1 from b2c.send_queue q where q.wa_message_id = v and q.payload ->> 'type' = 'media'
    and q.payload ->> 'link' = 'https://example.com/brochure.pdf' and q.payload ->> 'media_kind' = 'document'), null);
  begin perform b2c.wa_media_open(m); e := 'opened'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c1_inbound_waits_for_fetch', e = 'this file is still being fetched', e);
  perform pg_temp.as_system();
  j := b2c.wa_media_take(50);
  insert into r (name, ok, detail) values ('c1_job_takes_inbound_media', exists (select 1 from jsonb_array_elements(j) x where (x ->> 'id')::bigint = m and x -> 'media' ->> 'id' = 'meta-media-1'), j::text);
  perform b2c.wa_media_stored(m, 'leads/996630/wa/' || m || '-marksheet.pdf');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e902');
  begin perform b2c.wa_media_open(m); e := 'opened'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c1_other_counsellor_cannot_open', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  insert into r (name, ok, detail) values ('c1_owner_opens', b2c.wa_media_open(m) ->> 'path' like 'leads/996630/wa/%', null);
  insert into b2c.applications (lead_id, university, programme, status, checklist, created_by)
  values (996630, 'Jain Online', 'Online MBA', 'started', '{"Graduation marksheet": "pending"}', 'aaaaaaaa-0000-0000-0000-00000000e901') returning id into a;
  d := b2c.wa_media_attach(m, a, 'Graduation marksheet');
  insert into r (name, ok, detail) values ('c1_attach_to_checklist_in_one_tap', (select checklist ->> 'Graduation marksheet' from b2c.applications where id = a) = 'received'
    and (select source from b2c.documents where id = d) = 'whatsapp', null);
  insert into r (name, ok, detail) values ('c10_counsellor_opens_own_documents', b2c.document_open(d) ->> 'path' like 'leads/996630/%', null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  begin perform b2c.wa_queue_media(996630, 'document', null, null, null, 'https://example.com/b.pdf'); e := 'sent'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c5_marketing_cannot_send', e = 'not allowed', e);
  j := b2c.inbox_list('{"search": "marksheet"}');
  insert into r (name, ok, detail) values ('c5_search_message_text_marketing_reads', exists (select 1 from jsonb_array_elements(j) x where (x ->> 'lead_id')::bigint = 996630 and (x ->> 'read_only')::boolean), j::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  j := b2c.inbox_list('{"window": "open"}');
  insert into r (name, ok, detail) values ('c5_window_filter', exists (select 1 from jsonb_array_elements(j) x where (x ->> 'lead_id')::bigint = 996630), null);
  j := b2c.inbox_list('{"awaiting": true}');
  insert into r (name, ok, detail) values ('c5_awaiting_reply_filter', not exists (select 1 from jsonb_array_elements(j) x where (x ->> 'lead_id')::bigint = 996630), j::text);
  perform pg_temp.as_system();
end $x$;

-- C2/C6 the programme page and fit; C3 pipeline; C4 library and merge fields
do $x$
declare j jsonb; e text;
begin
  perform pg_temp.as_system();
  update public.catalog_programs set fee_yearly = 89500, fee_other = '{"duration_months": 24, "emi_monthly": 4999, "intakes": ["January", "July"], "scholarship": "10% for defence"}',
         min_qualification = 'Graduation' where id = 11;
  insert into b2b.partners (id, slug, name, status) values (99601, 'cp-partner', 'CP Partner', 'active') on conflict do nothing;
  insert into b2b.partner_programmes (partner_id, programme_id, commission, active) values (99601, 11, '{"rate_type": "percent", "value": 12}', true);
  insert into b2c.university_rates (university_id, programme_id, rate_type, fee_base, value, valid_from, note) values (1, null, 'percent', 'first_year', 20, current_date - 1, 'cp test');
  e := b2c.programme_cache_refresh(true)::text;
  insert into r (name, ok, detail) values ('c2_cache_refreshes', e::int >= 3
    and (select duration_months = 24 and emi_monthly = 4999 and intakes = '{January,July}' and jsonb_array_length(partners) = 1 from b2c.programme_cache where id = 11), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  j := b2c.programme_search('{"intake": "jul", "emi": true, "duration_max": 24, "sort": "fee"}');
  insert into r (name, ok, detail) values ('c2_filters', (j ->> 'total')::int = 1 and (j -> 'rows' -> 0 ->> 'id')::bigint = 11, j::text);
  insert into r (name, ok, detail) values ('c2_no_partner_money_for_sales', not (j -> 'rows' -> 0 ? 'partners') and not (j -> 'rows' -> 0 ? 'eduwit_commission'), null);
  j := b2c.programme_search('{"lead": 996630, "eligible": true, "course": "MBA"}');
  insert into r (name, ok, detail) values ('c2_eligible_for_this_lead', (j ->> 'eligible_rank') is not null and (j ->> 'total')::int >= 1, j::text);
  begin perform b2c.programme_compare(array[11]::bigint[]); e := 'compared'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c2_compare_2_to_4', e = 'compare 2 to 4 programmes', e);
  j := b2c.programme_compare(array[11, 12]::bigint[], 996630);
  insert into r (name, ok, detail) values ('c2_compare_side_by_side', jsonb_array_length(j) = 2 and (j -> 0 ->> 'id')::bigint = 11 and j -> 0 ? 'eligible', j::text);
  insert into r (name, ok, detail) values ('c2_facets', b2c.programme_facets() -> 'intakes' ? 'July' and b2c.programme_facets() -> 'courses' ? 'MBA', null);
  j := b2c.programme_fit(996630);
  insert into r (name, ok, detail) values ('c6_fit_with_eligibility_and_emi', j -> 'rows' -> 0 ? 'eligible' and j -> 'rows' -> 0 ? 'emi_monthly' and j -> 'rows' -> 0 ? 'duration_months', j::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  j := b2c.programme_search('{"q": "MBA", "university": "Amity"}');
  insert into r (name, ok, detail) values ('c2_marketing_sees_partners_and_commission', j -> 'rows' -> 0 -> 'partners' -> 0 ->> 'name' = 'CP Partner'
    and (j -> 'rows' -> 0 -> 'eduwit_commission' ->> 'amount')::numeric = 17900, j::text);
  begin perform b2c.pipeline_board(); e := 'listed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c3_pipeline_not_for_marketing', e = 'not allowed', e);
  perform pg_temp.as_system();
  update b2c.leads_state set next_task_due_at = now() - interval '1 hour' where lead_id = 996630;
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e902');
  j := b2c.pipeline_board(jsonb_build_object('owner', 'aaaaaaaa-0000-0000-0000-00000000e901', 'include_test', true));
  insert into r (name, ok, detail) values ('c3_counsellor_sees_only_own', not exists (select 1 from jsonb_array_elements(j -> 'columns') c, jsonb_array_elements(c -> 'cards') k where (k ->> 'lead_id')::bigint = 996630), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  j := b2c.pipeline_board(jsonb_build_object('owner', 'aaaaaaaa-0000-0000-0000-00000000e901', 'include_test', true));
  insert into r (name, ok, detail) values ('c3_admin_filters_by_counsellor', (select (c ->> 'count')::int from jsonb_array_elements(j -> 'columns') c where (c ->> 'stage_id')::int = 3) >= 1
    and (select k ->> 'overdue' from jsonb_array_elements(j -> 'columns') c, jsonb_array_elements(c -> 'cards') k where (k ->> 'lead_id')::bigint = 996630) = 'true', j::text);
  insert into r (name, ok, detail) values ('c3_column_value', (select c ? 'expected' from jsonb_array_elements(j -> 'columns') c where (c ->> 'stage_id')::int = 3), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  perform b2c.email_template_save('{"name": "CP after call", "subject": "Hello {{first_name}}", "body": "Fee {{fee}}"}');
  j := b2c.email_library('{"mine": true}');
  insert into r (name, ok, detail) values ('c4_library_has_author_and_rate', j -> 0 ->> 'author' = 'Asha CP' and j -> 0 ? 'uses' and j -> 0 ? 'reply_rate', j::text);
  j := b2c.merge_values(996630);
  insert into r (name, ok, detail) values ('c4_merge_fields', j ->> 'first_name' is not null and j ->> 'counsellor_name' = 'Asha CP' and j ? 'programme', j::text);
  perform pg_temp.as_system();
end $x$;

-- C7 WhatsApp alerts to one's own number; C9 custom fields and done tasks; C10 checklists; C11 SLA by source and neglect
do $x$
declare j jsonb; e text; v int;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.my_wa_alerts_set(array['moon']); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c7_unknown_alert_refused', e = 'unknown alert', e);
  begin perform b2c.my_wa_alerts_set(array['reminder']); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c7_needs_own_number', e = 'add your mobile number in Teams first', e);
  perform pg_temp.as_system();
  update b2c.users set phone = '919000099601' where user_id = 'aaaaaaaa-0000-0000-0000-00000000e901';
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  perform b2c.my_wa_alerts_set(array['reminder']);
  perform pg_temp.as_system();
  perform b2c.notify('aaaaaaaa-0000-0000-0000-00000000e901', 'reminder', 'In 10 minutes: call', 'CP Student', '/s/leads/996630', 996630, 'cp-rem-1');
  j := b2c.staff_wa_tick();
  insert into r (name, ok, detail) values ('c7_nothing_without_template', j ->> 'why' = 'no approved staff template', j::text);
  insert into b2c.wa_templates (name, language, category, audience, body, variables, status)
  values ('staff_alert', 'en', 'utility', 'sales', '{{1}} {{2}} {{3}}', '["title", "body", "link"]', 'approved');
  j := b2c.staff_wa_tick();
  insert into r (name, ok, detail) values ('c7_alert_to_own_number', exists (select 1 from b2c.send_queue q where q.to_address = '919000099601' and q.purpose = 'staff_alert'
    and q.payload -> 'template' -> 'params' ->> 0 = 'In 10 minutes: call'), j::text);
  j := b2c.staff_wa_tick();
  insert into r (name, ok, detail) values ('c7_sent_once', (select count(*) from b2c.send_queue q where q.to_address = '919000099601' and q.purpose = 'staff_alert') = 1, null);

  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.custom_fields_save('[{"key": "x", "label": "X", "type": "text"}]', 'test'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c9_fields_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  begin perform b2c.custom_fields_save('[{"key": "Bad Key", "label": "X", "type": "text"}]', 'test'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c9_keys_validated', e like 'field keys are%', e);
  perform b2c.custom_fields_save('[{"key": "parent_name", "label": "Parent", "type": "text"}, {"key": "exam", "label": "Entrance exam", "type": "select", "options": ["CAT", "MAT"]}]', 'cp test');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.custom_field_set(996630, 'exam', 'GRE'); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c9_select_options', e = 'choose one of the options', e);
  j := b2c.custom_field_set(996630, 'exam', 'CAT');
  insert into r (name, ok, detail) values ('c9_custom_value_with_history', j ->> 'exam' = 'CAT'
    and exists (select 1 from b2c.field_history h where h.lead_id = 996630 and h.field = 'custom.exam'), j::text);
  j := b2c.lead_detail(996630);
  insert into r (name, ok, detail) values ('c9_lead_screen_extras', j ? 'done_tasks' and j -> 'custom' ->> 'exam' = 'CAT' and jsonb_array_length(j -> 'custom_fields') = 2
    and jsonb_array_length(j -> 'documents') = 1 and j ? 'partner', null);

  begin perform b2c.checklist_save('Jain Online', array['ID']); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('c10_checklist_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  perform b2c.checklist_save('Jain Online', array['ID', 'Graduation marksheet', ' id '], 'cp');
  j := b2c.checklists();
  insert into r (name, ok, detail) values ('c10_checklist_saved_with_history', exists (select 1 from jsonb_array_elements(j -> 'lists') x where x ->> 'university' = 'Jain Online' and jsonb_array_length(x -> 'items') = 2)
    and jsonb_array_length(j -> 'history') >= 1, j::text);

  perform pg_temp.as_system();
  update b2c.settings set value = value || '{"by_source": {"website": {"hot": 7, "warm": 60}}}' where key = 'sla_minutes';
  insert into r (name, ok, detail) values ('c11_sla_by_source', b2c.sla_minutes_for(996630, true, null, 15) = 7 and b2c.sla_minutes_for(996630, false, 'cold', 1440) = 1440, null);
  update b2c.leads_state set last_activity_at = now() - interval '50 hours', neglect_alerted_at = null where lead_id = 996630;
  v := b2c.neglect_tick();
  insert into r (name, ok, detail) values ('c11_neglect_flagged', (select neglect_alerted_at is not null from b2c.leads_state where lead_id = 996630)
    and exists (select 1 from b2c.notifications n where n.lead_id = 996630 and n.kind = 'neglect'), v::text);
  insert into r (name, ok, detail) values ('c11_neglect_once_per_spell', b2c.neglect_tick() = 0, null);
end $x$;

-- ========== b42: access, stages and allocation ==========
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-00000000e905', 'sona.cp@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, takes_leads, languages, team) values
  ('aaaaaaaa-0000-0000-0000-00000000e905', 'sona.cp@eduwit.in', 'Sona CP', 'sales_head', true, true, false, '{English}', 'CP North');
update b2c.users set team = 'CP North' where user_id = 'aaaaaaaa-0000-0000-0000-00000000e901';
update b2c.users set team = 'CP South' where user_id = 'aaaaaaaa-0000-0000-0000-00000000e902';
insert into b2c.session_checks (session_id, user_id, method) values ('bbbbbbbb-0000-0000-0000-00000000e905', 'aaaaaaaa-0000-0000-0000-00000000e905', 'email_code') on conflict do nothing;

-- E15 the sales head's team; stage overrides asked by a counsellor, approved by the sales head
do $x$
declare j jsonb; e text; v bigint;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996640, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  perform pg_temp.lead(996641, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  update b2c.leads_state set status = 'active', owner_id = 'aaaaaaaa-0000-0000-0000-00000000e901', assigned_at = now(), stage_id = 4, sub_stage = 'Budget confirmed' where lead_id = 996640;
  insert into b2c.calls (lead_id, number, direction, outcome, logged_at, user_id) values (996640, '910000999640', 'out', 'connected', now(), 'aaaaaaaa-0000-0000-0000-00000000e901');
  update b2c.leads_state set status = 'active', owner_id = 'aaaaaaaa-0000-0000-0000-00000000e902', assigned_at = now(), stage_id = 3 where lead_id = 996641;
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e905');
  insert into r (name, ok, detail) values ('e15_head_sees_own_team', b2c.can_see(996640) and not b2c.can_see(996641), null);
  j := b2c.lead_list('{"ids": [996640, 996641], "include_test": true}');
  insert into r (name, ok, detail) values ('e15_head_list_is_team', (j ->> 'total')::int = 1 and (j -> 'rows' -> 0 ->> 'lead_id')::bigint = 996640, j ->> 'total');
  begin perform b2c.reassign(array[996641]::bigint[], 'aaaaaaaa-0000-0000-0000-00000000e901', 'move it'); e := 'moved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('e15_head_reassigns_in_team_only', e = 'not your team''s lead', e);
  begin perform b2c.reassign(array[996640]::bigint[], 'aaaaaaaa-0000-0000-0000-00000000e902', 'move it'); e := 'moved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('e15_head_reassigns_to_team_only', e = 'choose someone in your team', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.set_stage(996640, 3::smallint, 'Spoke briefly', 'back', now() + interval '1 day'); e := 'moved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('e15_counsellor_cannot_move_back', e like 'moving back%', e);
  v := b2c.stage_override_request(996640, 3::smallint, 'Spoke briefly', 'student wants to restart', now() + interval '1 day');
  insert into r (name, ok, detail) values ('e15_request_notifies_head', exists (select 1 from b2c.notifications n where n.user_id = 'aaaaaaaa-0000-0000-0000-00000000e905' and n.kind = 'stage_request'), null);
  begin perform b2c.stage_override_decide(v, true); e := 'decided'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('e15_counsellor_cannot_approve', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e905');
  insert into r (name, ok, detail) values ('e15_head_sees_request', jsonb_array_length(b2c.stage_requests_list()) >= 1, null);
  j := b2c.stage_override_decide(v, true, 'fine');
  insert into r (name, ok, detail) values ('e15_approved_moves_back', (select stage_id from b2c.leads_state where lead_id = 996640) = 3
    and (select status from b2c.stage_requests where id = v) = 'approved', j::text);
  perform pg_temp.as_system();
end $x$;

-- E2/D4 stages and sub-stages
do $x$
declare j jsonb; e text; v bigint;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e905');
  begin perform b2c.stage_save('{"id": 3, "name": "x"}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('e2_stages_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  begin perform b2c.stage_save('{"id": 3, "required": ["moon"]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('e2_requirements_checked', e = 'unknown requirement', e);
  perform b2c.stage_save('{"id": 3, "name": "Contacted (CP)", "reason": "test"}');
  v := b2c.sub_stage_save('{"stage_id": 3, "name": "CP waiting for parents", "comment_required": true}');
  begin perform b2c.sub_stage_save('{"stage_id": 3, "name": "cp WAITING for parents"}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('e2_no_duplicate_sub_stage', e = 'that sub-stage exists', e);
  j := b2c.stages_admin();
  insert into r (name, ok, detail) values ('e2_editor_with_history', exists (select 1 from jsonb_array_elements(j -> 'stages') x where (x ->> 'id')::int = 3 and x ->> 'name' = 'Contacted (CP)')
    and jsonb_array_length(j -> 'history') >= 2, null);
  perform pg_temp.as_system();
end $x$;

-- E4 assignment email fallback; E5 on-call; E7 breaks, holidays, week; E6 queues; E13 simulate future rules
do $x$
declare j jsonb; e text; v bigint; u b2c.users; q bigint;
begin
  perform pg_temp.as_system();
  perform pg_temp.lead(996642, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  update b2c.leads_state set status = 'active', owner_id = 'aaaaaaaa-0000-0000-0000-00000000e901', assigned_at = now() where lead_id = 996642;
  insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, status, attempts) values ('whatsapp', 996642, '910000999642', '{"type": "text", "text": "x"}', 'assignment', 'sending', 5)
  returning id into q;
  perform b2c.send_done(jsonb_build_array(jsonb_build_object('id', q, 'ok', false, 'error', 'not on WhatsApp')));
  insert into r (name, ok, detail) values ('e4_failed_whatsapp_falls_back_to_email', exists (select 1 from b2c.send_queue x where x.lead_id = 996642 and x.channel = 'email' and x.purpose = 'assignment'
    and x.payload ->> 'subject' = 'Your Eduwit counsellor: Asha CP'), null);
  insert into r (name, ok, detail) values ('e4_witty_idle_checked_at_send', not b2c.witty_busy(996642), null);

  -- on call: a hot lead while everyone is off hours
  perform pg_temp.lead(996643, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  update b2c.leads_state set hot = true where lead_id = 996643;
  insert into b2c.shift_overrides (user_id, day, off) select user_id, b2c.local_day(user_id, now()), true from b2c.users where email like '%.cp@eduwit.in'
  on conflict do nothing;
  update b2c.users set on_call = true where user_id = 'aaaaaaaa-0000-0000-0000-00000000e902';
  j := b2c.decide(996643, 'handoff', now(), null, false);
  insert into r (name, ok, detail) values ('e5_hot_outside_hours_to_on_call', j ->> 'outcome' = 'assigned' and j ->> 'chosen' = 'aaaaaaaa-0000-0000-0000-00000000e902' and j ->> 'logic' = 'on_call', j::text);
  update b2c.users set on_call = false where user_id = 'aaaaaaaa-0000-0000-0000-00000000e902';
  delete from b2c.shift_overrides where user_id in (select user_id from b2c.users where email like '%.cp@eduwit.in');

  -- breaks: hot leads only
  insert into b2c.work_breaks (user_id, start_t, end_t, label) values ('aaaaaaaa-0000-0000-0000-00000000e901', '00:00', '23:59', 'CP lunch');
  select * into u from b2c.users where user_id = 'aaaaaaaa-0000-0000-0000-00000000e901';
  insert into r (name, ok, detail) values ('e7_break_takes_hot_only', b2c.ineligible(u, b2c.lead_facts(996643, 'handoff'), now(), false, false) = 'on break'
    and b2c.ineligible(u, b2c.lead_facts(996643, 'handoff'), now(), true, false) is null, null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  perform b2c.holidays_import('[{"day": "2099-01-26", "name": "CP Republic Day", "kind": "national"}, {"day": "2099-08-15", "name": "CP Independence Day"}]');
  insert into r (name, ok, detail) values ('e7_holiday_import', (select count(*) from b2c.holidays where name like 'CP %') = 2, null);
  j := b2c.calendar_week('2099-01-26');
  insert into r (name, ok, detail) values ('e7_week_view', jsonb_array_length(j -> 'days') = 7 and j -> 'days' -> 0 ->> 'holiday' = 'CP Republic Day' and (j -> 'days' -> 0 -> 'nobody_on_duty')::boolean
    and j -> 'breaks' -> 0 ->> 'label' = 'CP lunch', null);

  -- queues: the manual queue is not decided again every minute
  perform pg_temp.as_system();
  perform pg_temp.lead(996644, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  update b2c.leads_state set status = 'active', owner_id = null where lead_id = 996644;
  insert into b2c.allocation_decisions (lead_id, trigger, outcome, why, at) values (996644, 'handoff', 'manual_queue', 'manual queue', now() + interval '1 minute');
  perform b2c.allocation_tick();
  insert into r (name, ok, detail) values ('e6_manual_queue_left_alone', (select outcome from b2c.allocation_decisions where lead_id = 996644 and not simulated order by at desc limit 1) = 'manual_queue'
    and (select owner_id from b2c.leads_state where lead_id = 996644) is null, null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  j := b2c.queues();
  insert into r (name, ok, detail) values ('e6_queues_apart', exists (select 1 from jsonb_array_elements(j -> 'manual') x where (x ->> 'lead_id')::bigint = 996644), null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.queue_allocate(996644); e := 'allocated'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('e6_allocate_needs_reassign', e = 'not allowed', e);

  -- E13 a future rule can be simulated
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  v := b2c.rule_save(jsonb_build_object('name', 'CP future', 'logic', 'manual', 'applies_from', now() + interval '30 days', 'position', 1));
  create temp table if not exists sim_load (user_id uuid, m date, d date, n int);
  create temp table if not exists sim_turns (rule_id bigint primary key, turn int);
  perform set_config('b2c.sim_rules', array[v]::text, true);
  j := b2c.decide(996644, 'handoff', now(), null, true);
  insert into r (name, ok, detail) values ('e13_simulate_future_rule', j ->> 'rule_name' = 'CP future' and j ->> 'outcome' = 'manual_queue', j::text);
  perform set_config('b2c.sim_rules', '', true);
  j := b2c.decide(996644, 'handoff', now(), null, true);
  insert into r (name, ok, detail) values ('e13_future_rule_not_live', j ->> 'rule_name' is distinct from 'CP future', j::text);
  perform pg_temp.as_system();
end $x$;

-- E8 capacity; E9 directory and invitations; E10 sessions; E14 writes; D13 view as Sales
do $x$
declare j jsonb; e text; n int;
begin
  perform pg_temp.as_system();
  update b2c.users set monthly_cap = 1, is_test_user = false where user_id = 'aaaaaaaa-0000-0000-0000-00000000e901';
  n := b2c.capacity_tick();
  insert into r (name, ok, detail) values ('e8_capacity_alert', exists (select 1 from b2c.notifications x where x.kind = 'capacity' and x.title like 'Asha CP is at%'), n::text);
  update b2c.users set monthly_cap = 200, is_test_user = true where user_id = 'aaaaaaaa-0000-0000-0000-00000000e901';
  perform b2c.directory_sync('[{"email": "newperson.cp@eduwit.in", "name": "New Person CP"}, {"email": "asha.cp@eduwit.in", "name": "Asha CP"}]');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  j := b2c.directory_unadded();
  insert into r (name, ok, detail) values ('e9_unadded_workspace_users', exists (select 1 from jsonb_array_elements(j) x where x ->> 'email' = 'newperson.cp@eduwit.in')
    and not exists (select 1 from jsonb_array_elements(j) x where x ->> 'email' = 'asha.cp@eduwit.in'), j::text);
  perform b2c.invite_sent('aaaaaaaa-0000-0000-0000-00000000e902');
  insert into r (name, ok, detail) values ('e9_invite_valid_7_days', b2c.invite_ok('bala.cp@eduwit.in'), null);
  perform pg_temp.as_system();
  update b2c.users set invite_expires_at = now() - interval '1 minute' where user_id = 'aaaaaaaa-0000-0000-0000-00000000e902';
  insert into r (name, ok, detail) values ('e9_invite_expires', not b2c.invite_ok('bala.cp@eduwit.in'), null);
  update b2c.users set first_sign_in_at = now() where user_id = 'aaaaaaaa-0000-0000-0000-00000000e902';
  insert into r (name, ok, detail) values ('e9_signed_in_users_unaffected', b2c.invite_ok('bala.cp@eduwit.in'), null);

  insert into b2c.trusted_devices (token_hash, user_id, label, expires_at) values ('cp-device-hash-0000000001', 'aaaaaaaa-0000-0000-0000-00000000e902', 'CP phone', now() + interval '30 days');
  insert into r (name, ok, detail) values ('e10_trusted_7_days', (select expires_at < now() + interval '7 days 1 minute' from b2c.trusted_devices where token_hash = 'cp-device-hash-0000000001'), null);
  insert into b2c.session_checks (session_id, user_id, method) values ('cccccccc-0000-0000-0000-00000000e902', 'aaaaaaaa-0000-0000-0000-00000000e902', 'email_code');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e902');
  perform b2c.session_note('CP browser', '127.0.0.1');
  j := b2c.my_devices();
  insert into r (name, ok, detail) values ('e10_device_list', jsonb_array_length(j -> 'sessions') = 2 and jsonb_array_length(j -> 'devices') = 1
    and exists (select 1 from jsonb_array_elements(j -> 'sessions') x where (x ->> 'current')::boolean and x ->> 'user_agent' = 'CP browser'), j::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  n := b2c.session_revoke(null, null, 'aaaaaaaa-0000-0000-0000-00000000e902');
  insert into r (name, ok, detail) values ('e10_admin_signs_out_everywhere', n = 3, n::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e902');
  insert into r (name, ok, detail) values ('e10_revoked_session_has_no_role', b2c.my_role() is null, null);
  perform pg_temp.as_system();
  update b2c.session_checks set revoked_at = null where user_id = 'aaaaaaaa-0000-0000-0000-00000000e902';

  perform pg_temp.lead(996645, '{"b2c_lane": "sales", "reason": "no_partner_offers_programme"}'::jsonb);
  update b2c.assignments set ended_at = now() where lead_id = 996645 and ended_at is null;
  insert into b2c.assignments (lead_id, user_id, trigger) values (996645, 'aaaaaaaa-0000-0000-0000-00000000e901', 'test');
  insert into r (name, ok, detail) values ('e14_off_until_b2b_accepts', not exists (select 1 from b2c.outbox o where o.lead_id = 996645 and o.kind = 'update' and o.body -> 'set' ? 'team_id'), null);
  update b2c.settings set value = '{"team_and_revenue": true}' where key = 'b2b_writes';
  update b2c.assignments set ended_at = now() where lead_id = 996645 and ended_at is null;
  insert into b2c.assignments (lead_id, user_id, trigger) values (996645, 'aaaaaaaa-0000-0000-0000-00000000e901', 'test');
  insert into r (name, ok, detail) values ('e14_team_written', exists (select 1 from b2c.outbox o where o.lead_id = 996645 and o.kind = 'update' and o.body -> 'set' ->> 'team_id' = 'CP North'), null);
  update b2c.settings set value = '{"team_and_revenue": false}' where key = 'b2b_writes';

  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e905');
  begin perform b2c.view_as_sales('aaaaaaaa-0000-0000-0000-00000000e901'); e := 'viewed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d13_view_as_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  j := b2c.view_as_sales('aaaaaaaa-0000-0000-0000-00000000e901', '{"ids": [996640, 996641]}');
  insert into r (name, ok, detail) values ('d13_view_as_counsellor_logged', (j -> 'leads' ->> 'total')::int = 1
    and exists (select 1 from b2c.audit_log a where a.action = 'view_as_sales' and a.detail ->> 'as' = 'aaaaaaaa-0000-0000-0000-00000000e901'), j::text);
  perform pg_temp.as_system();
end $x$;

-- ========== b43: platform, money, analytics, templates ==========
do $x$
declare j jsonb; e text; v bigint; ok boolean; i int;
begin
  -- D5 connectors
  perform pg_temp.as_system();
  perform b2c.connector_report('whatsapp', true, '{"quality": "GREEN"}');
  perform b2c.connector_report('whatsapp', false, null, 'token expired');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  begin perform b2c.connectors_overview(); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d5_connectors_admin_only', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  j := b2c.connectors_overview();
  insert into r (name, ok, detail) values ('d5_last_success_and_error', j -> 'status' -> 'whatsapp' ->> 'last_error' = 'token expired' and j -> 'status' -> 'whatsapp' ->> 'last_ok_at' is not null
    and j -> 'status' -> 'whatsapp' -> 'detail' ->> 'quality' = 'GREEN' and j ? 'gmail' and j ? 'b2b' and j ? 'claude', j::text);

  -- D6 own Gmail
  perform pg_temp.as_system();
  begin perform b2c.connection_save('aaaaaaaa-0000-0000-0000-00000000e901', 'gmail', 'someone@gmail.com', array['https://www.googleapis.com/auth/gmail.send'], 'sealed'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d6_own_mailbox_only', e = 'connect your own @eduwit.in mailbox', e);
  perform b2c.connection_save('aaaaaaaa-0000-0000-0000-00000000e901', 'gmail', 'asha.cp@eduwit.in', array['https://www.googleapis.com/auth/gmail.send'], 'sealed-token');
  perform b2c.connection_mark('aaaaaaaa-0000-0000-0000-00000000e901', 'gmail', false, 'invalid_grant: Token has been expired or revoked.');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  j := b2c.my_connections();
  insert into r (name, ok, detail) values ('d6_revocation_shown', j -> 0 ->> 'status' = 'revoked' and not (j -> 0 ? 'token_sealed')
    and exists (select 1 from b2c.notifications n where n.user_id = 'aaaaaaaa-0000-0000-0000-00000000e901' and n.kind = 'connection'), j::text);
  insert into r (name, ok, detail) values ('d6_tokens_not_for_clients', not has_function_privilege('authenticated', 'b2c.connection_token(uuid,text)', 'execute')
    and not has_table_privilege('authenticated', 'b2c.user_connections', 'select'), null);
  perform b2c.connection_disconnect('gmail');
  insert into r (name, ok, detail) values ('d6_disconnect_forgets_token', (select token_sealed is null and status = 'disconnected' from b2c.user_connections where user_id = 'aaaaaaaa-0000-0000-0000-00000000e901'), null);

  -- D7 metrics run
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  begin
    j := b2c.analytics_run(jsonb_build_object('metrics', '["b2c_created", "duplicate_cascades", "contact_rate", "days_to_counsel", "margin", "receivables"]'::jsonb,
                                              'from', (current_date - 30)::text, 'to', current_date::text));
    e := 'ran';
  exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d7_new_metrics_run', e = 'ran', e);
  begin
    j := b2c.analytics_run(jsonb_build_object('metrics', '["suppressions"]'::jsonb, 'dims', '["suppression_cause"]'::jsonb, 'from', (current_date - 30)::text, 'to', current_date::text));
    e := 'ran';
  exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d7_suppression_by_cause', e = 'ran', e);

  -- D9 alerts by WhatsApp
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  begin perform b2c.alert_save('{"metric": "handoffs", "op": "above", "threshold": 1, "channels": ["whatsapp"]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d9_whatsapp_needs_number', e = 'add your mobile number in Teams first', e);
  perform pg_temp.as_system();
  update b2c.users set phone = '919000099603' where user_id = 'aaaaaaaa-0000-0000-0000-00000000e903';
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  v := b2c.alert_save('{"metric": "handoffs", "op": "above", "threshold": 1, "channels": ["whatsapp", "push"]}');
  insert into r (name, ok, detail) values ('d9_alert_by_whatsapp', (select 'whatsapp' = any (channels) from b2c.metric_alerts where id = v)
    and (select 'alert' = any (wa_alerts) from b2c.users where user_id = 'aaaaaaaa-0000-0000-0000-00000000e903'), null);

  -- D10 commission dashboard
  j := b2c.commission_dashboard('{"test": true}');
  insert into r (name, ok, detail) values ('d10_dashboard_for_money_readers', j ? 'by_counsellor' and j ? 'by_status' and j ? 'by_month' and j ? 'runs' and j ? 'next_run', j::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e901');
  begin perform b2c.commission_dashboard(); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d10_not_for_counsellors', e = 'not allowed', e);

  -- D11 invoices and statements
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  begin perform b2c.invoice_send(-1); e := 'sent'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d11_invoice_must_be_approved', e = 'approve the invoice first', e);
  begin perform b2c.run_statements_send(-1); e := 'sent'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d11_run_must_be_approved', e = 'approve the run first', e);

  -- D12 guide screenshots
  select id into v from b2c.user_guides order by id limit 1;
  begin perform b2c.guide_images_set(v, '[{"path": "../secrets.png"}]'); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('d12_screenshots_under_guides', e = 'screenshots are stored under guides/', e);
  perform b2c.guide_images_set(v, '[{"path": "guides/today.png", "caption": "Today"}]');
  insert into r (name, ok, detail) values ('d12_screenshots_saved', (select images -> 0 ->> 'path' from b2c.user_guides where id = v) = 'guides/today.png', null);

  -- D14 rate limits
  perform pg_temp.as_system();
  ok := true;
  for i in 1 .. 3 loop ok := b2c.rate_check('cp-test:1.2.3.4', 3, 60); end loop;
  insert into r (name, ok, detail) values ('d14_rate_within_limit', ok, null);
  insert into r (name, ok, detail) values ('d14_rate_over_limit', not b2c.rate_check('cp-test:1.2.3.4', 3, 60), null);

  -- A12 templates
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  begin perform b2c.wa_template_save('{"name": "cp_header_bad", "body": "Hi {{1}}", "header": {"type": "image"}}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a12_media_header_needs_sample', e like 'a header is text%', e);
  v := b2c.wa_template_save('{"name": "cp_header_ok", "body": "Hi {{1}}, our brochure", "variables": ["first_name"], "header": {"type": "document", "example_url": "https://example.com/b.pdf"}}');
  perform b2c.wa_template_save(jsonb_build_object('id', v, 'body', 'Hello {{1}}, our brochure'));
  insert into r (name, ok, detail) values ('a12_version_history', jsonb_array_length(b2c.template_history('whatsapp', v)) = 2, null);
  begin perform b2c.template_preview('whatsapp', v, 996630 + 1000000); e := 'shown'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a12_preview_needs_test_lead', e = 'preview with a test lead', e);
  j := b2c.template_preview('whatsapp', v, 996630);
  insert into r (name, ok, detail) values ('a12_preview_on_test_lead', j ->> 'body' like 'Hello CP%' and j -> 'header' ->> 'type' = 'document', j::text);
  insert into r (name, ok, detail) values ('a12_performance', jsonb_typeof(b2c.template_performance('whatsapp')) = 'object' and jsonb_typeof(b2c.template_performance('email')) = 'object', null);
  begin perform b2c.email_template_m_save('{"name": "CP blocks", "subject": "Hi", "body": "<p>x</p>", "blocks": [{"type": "iframe"}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('a12_blocks_checked', e = 'unknown block', e);
  v := b2c.email_template_m_save('{"name": "CP blocks", "subject": "Hi {{first_name}}", "body": "<p>Hi {{first_name}}</p>", "blocks": [{"type": "heading", "text": "Hi"}, {"type": "button", "text": "Apply", "url": "https://eduwit.in"}]}');
  insert into r (name, ok, detail) values ('a12_block_editor_saved', (select jsonb_array_length(blocks) from b2c.email_templates where id = v) = 2
    and b2c.template_preview('email', v, 996630) ->> 'subject' like 'Hi CP%', null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e904');
  j := b2c.wa_template_import('[{"name": "cp_imported", "language": "en", "category": "MARKETING", "status": "APPROVED", "id": "meta-1",
        "components": [{"type": "HEADER", "format": "TEXT", "text": "Eduwit"}, {"type": "BODY", "text": "Hi {{1}}, new intake for {{2}}"}]},
       {"name": "cp_header_ok", "language": "en", "status": "PENDING", "id": "meta-2", "components": [{"type": "BODY", "text": "Hello {{1}}, our brochure"}]}]');
  insert into r (name, ok, detail) values ('a12_import_from_account', (j ->> 'added')::int = 1 and (j ->> 'updated')::int = 1
    and (select status = 'approved' and variables = '["var_1", "var_2"]'::jsonb and header ->> 'text' = 'Eduwit' from b2c.wa_templates where name = 'cp_imported'), j::text);

  -- fixes: yes/no filter on a text field; a stuck export retried; campaign replies list
  j := b2c.lead_list('{"filters": {"all": [{"field": "flagged", "op": "is_true"}]}, "limit": 1}');
  insert into r (name, ok, detail) values ('fix_flagged_is_true_on_text', j ? 'total', null);
  perform pg_temp.as_system();
  insert into b2c.exports (user_id, params, format, status, attempts, created_at) values ('aaaaaaaa-0000-0000-0000-00000000e904', '{}', 'csv', 'running', 1, now() - interval '1 hour') returning id into v;
  j := b2c.export_take(5);
  insert into r (name, ok, detail) values ('fix_stuck_export_retried', exists (select 1 from jsonb_array_elements(j) x where (x ->> 'id')::bigint = v), j::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000e903');
  insert into r (name, ok, detail) values ('fix_campaign_replies_list', jsonb_typeof(b2c.campaign_replies(-1)) = 'array', null);
  perform pg_temp.as_system();
end $x$;

-- ---------- grants ----------
insert into r (name, ok, detail)
select 'authenticated_can_call', bool_and(has_function_privilege('authenticated', f, 'execute')), string_agg(f, ', ') filter (where not has_function_privilege('authenticated', f, 'execute'))
  from unnest(array['b2c.opt_in(bigint,text[],text,text)', 'b2c.qualify_record(bigint,jsonb)', 'b2c.qualify_queue(jsonb)', 'b2c.qualify_assign(bigint,uuid)',
    'b2c.qualify_resend(bigint)', 'b2c.flag_review(bigint,text,text)', 'b2c.flagged_list()', 'b2c.replies_delegates_set(uuid[])',
    'b2c.views_list(text)', 'b2c.view_get(bigint)', 'b2c.view_pin(text,bigint)', 'b2c.bulk_journey(bigint[],text,bigint)', 'b2c.bulk_stage(bigint[],smallint,text,text,timestamp with time zone)',
    'b2c.lead_delete_request(bigint[],text,text)', 'b2c.bulk_job_undo(bigint)', 'b2c.bulk_jobs_list()', 'b2c.lead_erase(bigint,text,text)', 'b2c.export_request(jsonb)',
    'b2c.exports_mine()', 'b2c.export_open(bigint)', 'b2c.wa_queue_media(bigint,text,text,text,text,text)', 'b2c.wa_media_open(bigint)',
    'b2c.wa_media_attach(bigint,bigint,text)', 'b2c.programme_compare(bigint[],bigint)', 'b2c.programme_facets()', 'b2c.pipeline_board(jsonb)', 'b2c.email_library(jsonb)',
    'b2c.merge_values(bigint)', 'b2c.my_wa_alerts_set(text[])', 'b2c.custom_fields_save(jsonb,text)', 'b2c.custom_field_set(bigint,text,text)',
    'b2c.checklist_save(text,text[],text)', 'b2c.checklists()', 'b2c.document_open(bigint)',
    'b2c.stage_override_request(bigint,smallint,text,text,timestamp with time zone)', 'b2c.stage_override_decide(bigint,boolean,text)', 'b2c.stage_requests_list()',
    'b2c.stage_save(jsonb)', 'b2c.sub_stage_save(jsonb)', 'b2c.stages_admin()', 'b2c.queues()', 'b2c.queue_allocate(bigint)', 'b2c.breaks_save(jsonb)',
    'b2c.holidays_import(jsonb)', 'b2c.calendar_week(date)', 'b2c.directory_unadded()', 'b2c.invite_sent(uuid)', 'b2c.session_note(text,text)', 'b2c.my_devices(uuid)',
    'b2c.session_revoke(uuid,text,uuid)', 'b2c.view_as_sales(uuid,jsonb)', 'b2c.simulate(date,date,bigint[])',
    'b2c.connectors_overview()', 'b2c.my_connections()', 'b2c.connection_disconnect(text)', 'b2c.commission_dashboard(jsonb)', 'b2c.invoice_send(bigint,text)',
    'b2c.run_statements_send(bigint)', 'b2c.guide_images_set(bigint,jsonb)', 'b2c.wa_template_import(jsonb)', 'b2c.template_history(text,bigint)',
    'b2c.template_preview(text,bigint,bigint)', 'b2c.template_performance(text,integer)', 'b2c.campaign_replies(bigint,integer)']) f;
insert into r (name, ok, detail)
select 'authenticated_cannot_call_internals', not bool_or(has_function_privilege('authenticated', f, 'execute')), string_agg(f, ', ') filter (where has_function_privilege('authenticated', f, 'execute'))
  from unnest(array['b2c.qualify_form(text)', 'b2c.qualify_submit(text,jsonb)', 'b2c.qualify_apply(bigint,jsonb,text,uuid)', 'b2c.qualify_start(bigint,text)',
    'b2c.qualify_tick()', 'b2c.queue_system_email(bigint,text,text,text,text,timestamp with time zone)', 'b2c.queue_system_text(bigint,text,text,text)',
    'b2c.opted_out_now(bigint)', 'b2c.partner_lost_due(jsonb)', 'b2c.erase_files_take(integer)', 'b2c.export_take(integer)', 'b2c.export_page(bigint,integer,integer)',
    'b2c.events_feed(bigint,integer)', 'b2c.bulk_jobs_tick(integer)', 'b2c.wa_media_take(integer)', 'b2c.wa_media_stored(bigint,text,text)',
    'b2c.programme_cache_refresh(boolean)', 'b2c.staff_wa_tick()', 'b2c.neglect_tick()', 'b2c.lead_expected_value(bigint)',
    'b2c.invite_ok(text)', 'b2c.capacity_tick()', 'b2c.witty_busy(bigint)', 'b2c.assignment_email(bigint,timestamp with time zone)', 'b2c.in_my_team(uuid)', 'b2c.lead_delete_job_part(bigint[],text,uuid,bigint)', 'b2c.filter_leads(jsonb,boolean)']) f;
insert into r (name, ok, detail)
select 'anon_calls_nothing', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2c' and has_function_privilege('anon', p.oid, 'execute')), null;

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
