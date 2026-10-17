-- web8: Witty on the website (web_advisor) — sessions, transcript in w2_messages shape, lead writes through lead_intake
-- with the web channel stamps, idempotent turns, ownership, feedback, callbacks, history, read-only tool wrappers.
-- Runs on the replica too (no catalogue or prompts there: those checks accept empty results).
begin;
create temp table r (ok boolean, name text) on commit drop;
create temp table v (k text primary key, val jsonb) on commit drop;

-- A verified Witty gate visitor (surface gate) → student + lead (website_agent / web).
select public.web_gate_start(jsonb_build_object('idempotency_key', 'g-1', 'surface', 'gate', 'name', 'Ravi Kumar', 'email', 'ravi.k@example.org',
  'phone', '+919812300077', 'consent_version', 'web-gate-2026-10-v1', 'is_test', true, 'code_hash', 'c1'));
insert into v select 'verify', public.web_gate_verify((select id from public.web_gate_attempts where idempotency_key = 'g-1'), 'c1');
insert into r select (select l.lead_source = 'website_agent' and l.channel = 'web' and l.first_agent_channel = 'web'
  from public.student_leads l where l.id = (select (val->>'lead_id')::bigint from v where k = 'verify')), 'gate lead: website_agent, channel web, first_agent_channel web';
insert into v select 'sid', to_jsonb((select val->>'student_id' from v where k = 'verify'));

-- Session opens with the verified name and email already confirmed; reopening resumes it.
insert into v select 'open', public.web_advisor_session_open((select (val #>> '{}')::uuid from v where k = 'sid'), false, true);
insert into r select (select val->'state'->'profile'->'email_id'->>'value' = 'ravi.k@example.org' and (val->'state'->'profile'->'student_name'->>'confirmed')::boolean from v where k = 'open'), 'profile pre-filled from the verified gate';
insert into r select (public.web_advisor_session_open((select (val #>> '{}')::uuid from v where k = 'sid'), false, true)->'session'->>'id') = (select val->'session'->>'id' from v where k = 'open'), 'reopening resumes the same session';

-- Turn 1: transcript rows + state + lead update (chat.turn not written as a lead event when event_type is empty).
insert into v select 't1', public.web_advisor_turn_commit(jsonb_build_object('session_id', (select val->'session'->>'id' from v where k = 'open'),
  'student_id', (select val #>> '{}' from v where k = 'sid'), 'message_id', 'm-1', 'run_id', 'r-1', 'student_message', 'I want to do an MBA',
  'reply', 'Good news: we have 38 MBA options. Do you have a specialization in mind?', 'answer_mode', 'DIRECTIONAL', 'reply_source', 'llm',
  'model', 'mock', 'usage', '{"prompt_tokens":1200,"cached_tokens":1000,"output_tokens":40,"cost_usd":0.0012}'::jsonb, 'latency_ms', 900,
  'state', '{"profile":{"interested_course":{"value":"MBA","confirmed":true}}}'::jsonb, 'phase', 'QUALIFY_IT', 'language', 'english',
  'event_type', 'lead.updated', 'lead', '{"interested_course":"MBA","programme_level":"PG","conversation_phase":"QUALIFY_IT"}'::jsonb,
  'agent_core_version', 'extractor:6:x|counselor:6:y|engine:test'));
insert into r select (select (val->>'ok')::boolean and (val->>'turn')::int = 1 from v where k = 't1'), 'turn committed';
insert into r select (select count(*) from public.web_advisor_messages where session_id = (select (val->'session'->>'id')::uuid from v where k = 'open')) = 2, 'both messages stored';
insert into r select (select phone = '919812300077' and channel = 'web' from public.web_advisor_messages where direction = 'in' and message_id = 'm-1'), 'w2_messages shape: phone digits, channel web';
insert into r select (select interested_course = 'MBA' and lead_stage = 'QUALIFY_IT' from public.student_leads where id = (select (val->>'lead_id')::bigint from v where k = 'verify')), 'lead enriched through lead_intake';
insert into r select (select prompt_tokens = 1200 and cached_tokens = 1000 and phase = 'QUALIFY_IT' and agent_core_version like 'extractor:6%' from public.web_advisor_sessions where id = (select (val->'session'->>'id')::uuid from v where k = 'open')), 'usage, phase and core version recorded';

-- Same client message id again (retry after network loss) is a no-op.
insert into r select (public.web_advisor_turn_commit(jsonb_build_object('session_id', (select val->'session'->>'id' from v where k = 'open'),
  'student_id', (select val #>> '{}' from v where k = 'sid'), 'message_id', 'm-1', 'student_message', 'I want to do an MBA', 'reply', 'x')) ->> 'status') = 'duplicate', 'retried message is not stored twice';
-- Another student cannot write to this session.
insert into r select (public.web_advisor_turn_commit(jsonb_build_object('session_id', (select val->'session'->>'id' from v where k = 'open'),
  'student_id', gen_random_uuid(), 'message_id', 'm-2', 'student_message', 'x', 'reply', 'y')) ->> 'reason') = 'not_owner', 'session ownership enforced';

-- Escalation (HOT) classification lands on the lead.
select public.web_advisor_turn_commit(jsonb_build_object('session_id', (select val->'session'->>'id' from v where k = 'open'),
  'student_id', (select val #>> '{}' from v where k = 'sid'), 'message_id', 'm-3', 'student_message', 'I want to join this month',
  'reply', 'Thank you Ravi. An academic counsellor will contact you shortly about MBA.', 'answer_mode', 'HANDOFF', 'reply_source', 'fixed',
  'classification', 'HOT', 'readiness', 'READY_NOW', 'eligibility', 'ELIGIBLE', 'phase', 'ESCALATION', 'escalate', true,
  'event_type', 'lead.escalated', 'lead', '{"classification":"HOT","readiness":"READY_NOW","eligibility":"ELIGIBLE","conversation_phase":"ESCALATION","enrollment_timeline":"this month"}'::jsonb));
insert into r select (select lead_status = 'HOT' and temperature = 'hot' and is_sales_ready from public.student_leads where id = (select (val->>'lead_id')::bigint from v where k = 'verify')), 'HOT classification makes the lead sales-ready';
insert into r select (select escalated_at is not null and classification = 'HOT' from public.web_advisor_sessions where id = (select (val->'session'->>'id')::uuid from v where k = 'open')), 'session escalated';

-- Feedback only on the student's own agent replies.
insert into r select public.web_advisor_feedback_add((select (val #>> '{}')::uuid from v where k = 'sid'), (select (val->>'out_id')::bigint from v where k = 't1'), 1::smallint), 'thumbs up stored';
insert into r select not public.web_advisor_feedback_add(gen_random_uuid(), (select (val->>'out_id')::bigint from v where k = 't1'), -1::smallint), 'feedback by someone else refused';
insert into r select not public.web_advisor_feedback_add((select (val #>> '{}')::uuid from v where k = 'sid'), (select (val->>'in_id')::bigint from v where k = 't1'), 1::smallint), 'feedback only on Witty replies';

-- Callback slot written to the lead.
insert into r select (public.web_callback_request((select (val #>> '{}')::uuid from v where k = 'sid'), (select (val->'session'->>'id')::uuid from v where k = 'open'),
  ((now() at time zone 'Asia/Kolkata')::date + 1), 'evening') ->> 'ok')::boolean, 'callback booked';
insert into r select (select preferred_counseling_time like 'Callback %evening%' from public.student_leads where id = (select (val->>'lead_id')::bigint from v where k = 'verify')), 'callback slot on the lead';
insert into r select (public.web_callback_request((select (val #>> '{}')::uuid from v where k = 'sid'), null, ((now() at time zone 'Asia/Kolkata')::date + 30), 'evening') ->> 'reason') = 'bad_date', 'callback limited to the next 14 days';

-- History and restart.
insert into r select jsonb_array_length(public.web_advisor_history((select (val #>> '{}')::uuid from v where k = 'sid'))) = 1, 'history lists the conversation';
insert into r select (public.web_advisor_session_open((select (val #>> '{}')::uuid from v where k = 'sid'), true, true)->'session'->>'id') <> (select val->'session'->>'id' from v where k = 'open'), 'restart opens a new session';

-- Read-only tool wrappers.
insert into r select (public.web_agent_core_prompts() ? 'overlay'), 'prompts by reference incl. the web overlay';
insert into r select not exists (select 1 from jsonb_array_elements(public.web_advisor_search('{"course":"mba"}')->'rows') e(x)
  where not exists (select 1 from public.web_offering_search s where s.id = (x->>'id')::bigint)), 'search returns only rows the website shows';
insert into r select jsonb_typeof(public.web_advisor_kb('is an online degree valid')) = 'array', 'knowledge search returns a list';
insert into r select not exists (select 1 from public.catalog_programs where active and course_key = 'mba')
  or ((public.web_advisor_search('{"course":"MBA","level":"PG"}')->>'visible_total')::int > 0
      and (public.web_advisor_search('{"course":"MA English"}')->>'visible_total')::int > 0), 'course names normalised to Witty''s catalogue keys';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
