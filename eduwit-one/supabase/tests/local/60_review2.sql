-- The second database review's findings (docs/reviews/phase-1-2-db.md), each shown fixed on the stubbed path. M8
-- (guards) is in scripts/db/guards.test.ts and the fingerprint step of local-test.sh; m8 (0006's rollback) and m16 in
-- local-test.sh; m2 in with-db.ts. Local test cluster only.
\set ON_ERROR_STOP 1
do $$ begin
  if current_database() <> 'rehearsal' or to_regclass('public.stub_health') is null then
    raise exception 'refused: this test rewrites fixtures and runs only on the local test cluster';
  end if;
end $$;
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;
truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
create temp table t_saved as select key, value from one.settings where key in ('alerts', 'events', 'app', 'checks');

-- B1: a killed check keeps its committed start mark; the next tick records it as an error (its incident opens), runs
-- the other checks, finishes its alert step and app call, and keeps the killed check out of the way --------------------
insert into one.checks (id, app, title, kind, sql, severity, cadence_s)
values ('ONE-SLOW', 'one', 'test: a slow check', 'sql', 'select pg_sleep(3) is not null as ok, null::jsonb as value', 'P3', 60);
delete from one.runs where kind = 'tick';
update one.check_state set last_ran_at = now() - interval '1 day', last_started_at = now() - interval '1 day', killed_count = 0;
-- ONE-SLOW has never started, so it runs first; a 2 s statement timeout on the CALL stands in for transaction_timeout.
set role postgres;
\set ON_ERROR_STOP 0
set statement_timeout = '2s';
call one.tick_job();
\set ON_ERROR_STOP 1
reset statement_timeout;
select pg_temp.ok((select last_started_at is not null and last_ran_at is null from one.check_state where check_id = 'ONE-SLOW'),
                  'the killed check kept its committed start mark');
reset role;
delete from one.runs where kind = 'tick';
set role postgres;
call one.tick_job();
select pg_temp.ok((select last_status = 'error' and killed_count = 1 from one.check_state where check_id = 'ONE-SLOW'), 'the next tick records the kill as an error');
select pg_temp.ok(exists (select 1 from one.incidents where check_id = 'ONE-SLOW' and resolved_at is null), 'which opens the check''s incident');
select pg_temp.ok((select finished_at is not null and report ? 'killed_error' and report ? 'events'
                          and (select sum(value::int) from jsonb_each_text(report -> 'checks')) > 20 from one.runs where kind = 'tick'),
                  'the tick names the kill, runs the other checks, finishes and copies events: ' || (select report::text from one.runs where kind = 'tick'));
select pg_temp.ok((select count(*) = 1 from one.results where check_id = 'ONE-SLOW'), 'the killed check is not run again within its back-off');
select pg_temp.ok((one.watchdog() ->> 'tick_age_s')::numeric < 60, 'the watchdog reads the finished tick');
reset role;
delete from one.ai_tasks where incident_id in (select id from one.incidents where check_id = 'ONE-SLOW');
delete from one.deliveries where incident_id in (select id from one.incidents where check_id = 'ONE-SLOW');
delete from one.incidents where check_id = 'ONE-SLOW';
delete from one.checks where id = 'ONE-SLOW';

-- M2: a job call with no HTTP status counts; one:app and the probes are down once expected and never seen; a stuck
-- alert email fails ONE-02 and the watchdog --------------------------------------------------------------------------
set role postgres;
create table b2c.job_calls (calls jsonb);
insert into b2c.job_calls values ('[{"id": 900001}]');
reset role;
insert into net._http_response (id, status_code, timed_out, error_msg) values (900001, null, true, 'Timeout of 5000 ms reached');
set role postgres;
select one.run_check('PLAT-04');
select pg_temp.ok((select last_status = 'fail' from one.check_state where check_id = 'PLAT-04'), 'a timed-out job call fails PLAT-04');
select one.settings_put('app', one.setting('app') || '{"base_url": "https://one.example.test"}', 'test@eduwit.in', 'expect the app');
reset role;
delete from one.heartbeats where component in ('one:app', 'website');
update one.settings set updated_at = now() - interval '20 minutes' where key = 'app';
set role postgres;
select one.run_check('HB-one:app');
select pg_temp.ok((select last_status = 'fail' from one.check_state where check_id = 'HB-one:app'), 'one:app never seen 20 min after app.base_url was set is down');
reset role;
insert into one.heartbeats (component, last_ok_at, expected_interval_s, created_at) values ('one:app', now(), 60, now() - interval '20 minutes');
set role postgres;
select one.run_check('HB-website');
select pg_temp.ok((select last_status = 'fail' from one.check_state where check_id = 'HB-website'), 'a probe that never wrote, 20 min after the app first answered, is down');
reset role;
insert into one.deliveries (channel, recipient, kind, idempotency_key, created_at)
values ('email', 'connect@eduwit.in', 'alert', 'test:stuck', now() - interval '10 minutes');
set role postgres;
select one.run_check('ONE-02');
select pg_temp.ok((select last_status = 'fail' from one.check_state where check_id = 'ONE-02'), 'an alert email pending for 10 min fails ONE-02');
select pg_temp.ok((one.watchdog() ->> 'delivery_wait_s')::numeric >= 600, 'and the watchdog sees its age');
reset role;
delete from one.deliveries where idempotency_key = 'test:stuck';
delete from one.heartbeats where component = 'one:app';

-- M3: a job's run in progress does not hide its last finished run's failure -----------------------------------------
delete from cron.job_run_details;
insert into cron.job (jobname, schedule, command) values ('test-slow', '* * * * *', 'select 1') on conflict (jobname) do nothing;
insert into cron.job_run_details (jobid, status, return_message, start_time, end_time)
select jobid, 'failed', 'ERROR: boom', now() - interval '2 minutes', now() - interval '110 seconds' from cron.job where jobname = 'test-slow'
union all
select jobid, 'running', null, now() - interval '1 second', null from cron.job where jobname = 'test-slow';
set role postgres;
select one.run_check('PLAT-01');
select pg_temp.ok((select value -> 'subjects' ? 'test-slow' from one.results where check_id = 'PLAT-01' order by id desc limit 1),
                  'PLAT-01 sees the failure behind a run in progress');

-- m12: a weekly job's failure is not lost when it leaves the 26 h window -------------------------------------------
reset role;
insert into cron.job (jobname, schedule, command) values ('test-weekly', '0 3 * * 0', 'select 1') on conflict (jobname) do nothing;
insert into cron.job_run_details (jobid, status, return_message, start_time, end_time)
select jobid, 'failed', 'ERROR: weekly', now() - interval '3 days', now() - interval '3 days' from cron.job where jobname = 'test-weekly';
set role postgres;
select one.run_check('PLAT-01W');
select pg_temp.ok((select value -> 'subjects' ? 'test-weekly' from one.results where check_id = 'PLAT-01W' order by id desc limit 1),
                  'PLAT-01W reports a weekly job whose latest run failed');
reset role;
delete from cron.job_run_details;
delete from cron.job where jobname in ('test-slow', 'test-weekly');

-- M4: nothing is copied without a PII list, and the list cannot be saved empty --------------------------------------
set role postgres;
do $$ begin
  perform one.settings_put('events', one.setting('events') || '{"pii_columns": []}', 'test', 'empty list');
  raise exception 'ASSERT FAILED: an empty PII list was saved';
exception when invalid_parameter_value then null;
end $$;
reset role;
delete from one.settings where key = 'events';
insert into b2b.events (type, payload) values ('m4.test', '{"student_name": "Asha"}');
set role postgres;
create temp table t_m4 as select one.events_copy_safe('b2b.events', 'b2b', (select sql from one.events_sources() where source = 'b2b.events')) as r;
select pg_temp.ok((select r ? 'b2b.events_error' from t_m4), 'with no PII list the copy refuses: ' || (select r::text from t_m4));
select pg_temp.ok(not exists (select 1 from one.events where type = 'm4.test'), 'and copies nothing');
reset role;
insert into one.settings (key, value) select key, value from t_saved where key = 'events';

-- M5: contacts inside text, behind a prefix, inside stringified JSON or as keys; names under more keys ------------------
create temp table t_pii as select array(select jsonb_array_elements_text(value -> 'pii_columns')) as k from one.settings where key = 'events';
select pg_temp.ok(one.redact('{"t": "call back on 98111 22334 after six"}', '{}') = '{"t": "[phone]"}', 'a phone inside text');
select pg_temp.ok(one.redact('{"uri": "tel:+919811122334", "w": "whatsapp:+44 7911 123456"}', '{}') = '{"uri": "[phone]", "w": "[phone]"}', 'a phone behind a prefix');
select pg_temp.ok(one.redact('{"r": "{\"status\":\"duplicate\",\"mobile\":\"9811122334\"}"}', '{mobile}') = '{"r": "{\"status\": \"duplicate\"}"}',
                  'a JSON document kept as text is redacted as JSON');
select pg_temp.ok(one.redact('{"turns_by": {"9811122334": 3, "asha@x.in": 1}}', '{}') = '{"turns_by": {"[phone]": 3, "[email]": 1}}', 'contacts used as keys');
select pg_temp.ok(one.redact('{"lead_name": "Asha", "father_name": "R", "b2c_stage_comment": "x", "reason": "duplicate"}', (select k from t_pii)) = '{"reason": "duplicate"}',
                  'names and comments under the added keys are dropped');
select pg_temp.ok(one.redact('{"id": "550e8400-e29b-41d4-a716-446655440000", "at": "2026-10-23 10:00:00+05:30", "n": 1729700000, "h": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"}', '{}')
                  = '{"id": "550e8400-e29b-41d4-a716-446655440000", "at": "2026-10-23 10:00:00+05:30", "n": 1729700000, "h": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"}',
                  'ids, hashes, timestamps and epoch numbers stay');

-- M6: an event that committed late, or landed in a skipped minute, is still reported; each event is a subject -----------
insert into b2b.events (type, occurred_at) values ('routing.error', now() - interval '5 minutes');
set role postgres;
select one.run_check('B2B-02');
select pg_temp.ok((select status = 'fail' and jsonb_array_length(value -> 'subjects') >= 1 from one.results where check_id = 'B2B-02' order by id desc limit 1),
                  'B2B-02 reports an event from 5 minutes ago, with its id as a subject');
reset role;
delete from b2b.events where type in ('routing.error', 'm4.test');

-- M7: a one-minute check that ran late in the last minute is due in this one --------------------------------------
update one.check_state set last_ran_at = date_trunc('minute', now()) - interval '2 seconds', last_started_at = date_trunc('minute', now()) - interval '3 seconds', killed_count = 0
 where check_id = 'PLAT-02';
set role postgres;
select pg_temp.ok('PLAT-02' in (select one.due_checks()), 'a one-minute check that ran at :58 is due at the next minute');
reset role;
update one.check_state set last_ran_at = now(), last_started_at = now() where check_id = 'PLAT-02';
set role postgres;
select pg_temp.ok('PLAT-02' not in (select one.due_checks()), 'and not twice in the same minute');

-- M10: a view the API roles can read past RLS fails PLAT-06 -----------------------------------------------------------
select one.capture_baselines();
reset role;
create view public.leads_overview as select id, whatsapp_number from public.student_leads;
grant select on public.leads_overview to anon;
set role postgres;
select one.run_check('PLAT-06');
select pg_temp.ok((select value::text ~ 'security_definer_view' and value::text ~ 'leads_overview' from one.results where check_id = 'PLAT-06' order by id desc limit 1),
                  'PLAT-06 reports a security-definer view added after install');
reset role;
drop view public.leads_overview;

-- m1: a malformed setting is refused at the door; one that got in anyway still leaves an error result ----------------
set role postgres;
do $$ begin
  perform one.settings_put('alerts', one.setting('alerts') || '{"p1": {"email": "connect@eduwit.in"}}', 'test', 'a string, not a list');
  raise exception 'ASSERT FAILED: a malformed alerts value was saved';
exception when invalid_parameter_value then null;
end $$;
do $$ begin
  perform one.settings_put('app', one.setting('app') || '{"base_url": "http://one.example.test"}', 'test', 'plain http');
  raise exception 'ASSERT FAILED: an http base URL was saved (m15)';
exception when invalid_parameter_value then null;
end $$;
reset role;
update one.settings set value = jsonb_set(value, '{p1,email}', '"connect@eduwit.in"') where key = 'alerts';
update public.stub_health set value = '{"ok": false}' where app = 'b2b';
delete from one.incidents where check_id = 'B2B-01';
set role postgres;
create temp table t_m1 as select one.run_check_safe('B2B-01') as r;
select pg_temp.ok((select r ? 'B2B-01_error' from t_m1), 'recording failed: the report names it');
select pg_temp.ok((select status = 'error' and error ~ 'recording failed' from one.results where check_id = 'B2B-01' order by id desc limit 1),
                  'and an error result is kept: ' || coalesce((select error from one.results where check_id = 'B2B-01' order by id desc limit 1), 'none'));
reset role;
update one.settings s set value = t.value from t_saved t where s.key = t.key and t.key = 'alerts';
update public.stub_health set value = '{"ok": true}' where app = 'b2b';
set role postgres;
select one.run_check('B2B-01');
reset role;

-- m3: the tick's own kinds cannot be reported by the app ------------------------------------------------------------
set role postgres;
do $$ begin
  perform one.report_result('B2B-01', 'ok', '{}', null, 1);
  raise exception 'ASSERT FAILED: the app reported an rpc check';
exception when invalid_parameter_value then null;
end $$;

-- m5: a subject that recovered and fails again alerts again ---------------------------------------------------------
reset role;
truncate one.ai_tasks, one.deliveries, one.incidents restart identity cascade;
set role postgres;
select one.open_or_touch_incident('PLAT-01', 'P1', '{}', '{A}');
select one.open_or_touch_incident('PLAT-01', 'P1', '{}', '{A,B}');
select one.acknowledge_incident((select id from one.incidents where check_id = 'PLAT-01'), 'owner@eduwit.in');
select one.open_or_touch_incident('PLAT-01', 'P1', '{}', '{B}');
select pg_temp.ok((select acknowledged_at is not null and subjects = '{B}' from one.incidents where check_id = 'PLAT-01'), 'A recovered: the set is {B}, still acknowledged');
select one.open_or_touch_incident('PLAT-01', 'P1', '{}', '{A,B}');
select pg_temp.ok((select acknowledged_at is null and alert_seq = 3 from one.incidents where check_id = 'PLAT-01'), 'A failing again clears the acknowledgement and alerts again');

-- m6: switching a check off closes its open incident ------------------------------------------------------------------
select one.open_or_touch_incident('WEB-01', 'P1', '{}');
reset role;
update one.checks set enabled = false, disabled_reason = 'owner:test' where id = 'WEB-01';
set role postgres;
select one.alerts_step();
select pg_temp.ok((select resolution = 'accepted' and resolution_note ~ 'owner:test' from one.incidents where check_id = 'WEB-01'), 'the incident of a switched-off check is closed');
reset role;
update one.checks set enabled = true, disabled_reason = null where id = 'WEB-01';

-- m7: a function that gains a role must be looked at again ------------------------------------------------------------
create function public.auth_only_rpc() returns int language sql security definer as $$ select 3 $$;
revoke execute on function public.auth_only_rpc() from public;
grant execute on function public.auth_only_rpc() to authenticated;
set role postgres;
select one.privilege_audit();
reset role;
update one.privilege_baseline set acknowledged = true, acknowledged_by = 'test' where fn like '%auth_only_rpc%';
grant execute on function public.auth_only_rpc() to anon;
set role postgres;
select one.privilege_audit();
select pg_temp.ok((select not acknowledged from one.privilege_baseline where fn like '%auth_only_rpc%'), 'opening an acknowledged function to anon unacknowledges it');
reset role;
drop function public.auth_only_rpc();
delete from one.privilege_baseline where fn like '%auth_only_rpc%';

-- m11: an added student_leads column does not page; a renamed one does -----------------------------------------------
select pg_temp.ok(exists (select 1 from one.baselines where key = 'student_leads_columns'), 'the column baseline exists');
alter table public.student_leads add column preferred_city text;
set role postgres;
select one.run_check('INT-06');
select pg_temp.ok((select last_status = 'ok' from one.check_state where check_id = 'INT-06'), 'an added column is ok');
reset role;
alter table public.student_leads drop column preferred_city;
alter table public.student_leads rename column email_id to email_address;
set role postgres;
select one.run_check('INT-06');
select pg_temp.ok((select last_status = 'fail' from one.check_state where check_id = 'INT-06'), 'a renamed column fails');
reset role;
alter table public.student_leads rename column email_address to email_id;

-- m13: an event source in error shows in ONE-01 -------------------------------------------------------------------------
update one.event_watermarks set last_status = 'error', last_error = 'test' where source = 'b2b.events';
set role postgres;
select one.run_check('ONE-01');
select pg_temp.ok((select value -> 'event_sources_failing' ? 'b2b.events' from one.results where check_id = 'ONE-01' order by id desc limit 1),
                  'ONE-01 names the failing event source');
reset role;
update one.event_watermarks set last_status = 'ok', last_error = null where source = 'b2b.events';

-- Clean up ---------------------------------------------------------------------------------------------------------
drop table b2c.job_calls;
delete from net._http_response where id = 900001;
update one.settings s set value = t.value from t_saved t where s.key = t.key;
truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
-- The smoke test that follows runs its own tick; this file's ticks (one of them killed on purpose) are not its.
delete from one.runs where kind = 'tick';
