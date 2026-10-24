-- The test runner's database side (migration 0014): start, lease, save, finish, report to the test's check, reap.
-- Local test cluster only.
\set ON_ERROR_STOP 1
-- This test rewrites histories that are append-only in production (D-085): it says so, as one.retention() does.
select set_config('one.history_writer', 'on', false);
do $$ begin
  if current_database() <> 'rehearsal' or to_regclass('public.stub_health') is null then
    raise exception 'refused: this test rewrites fixtures and runs only on the local test cluster';
  end if;
end $$;
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;
create or replace function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text) to authenticated, service_role;

truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
delete from one.test_runs where test_id = 'T-LOCAL';
delete from one.tests where id = 'T-LOCAL';
delete from one.check_state where check_id = 'T-LOCAL';
delete from one.results where check_id = 'T-LOCAL';
delete from one.checks where id = 'T-LOCAL';
insert into one.tests (id, app, title, steps, schedule, timeout_s, severity, enabled, needs, seam)
values ('T-LOCAL', 'one', 'Local runner test', '[{"key": "a", "title": "Step A", "timeout_s": 30}]', '0 * * * *', 600, 'P2', true, '{email}', 'one → one');
select one.seed_check('{"id": "T-LOCAL", "app": "one", "title": "Synthetic test failed: Local runner test", "description": "x", "kind": "test",
                        "severity": "P2", "cadence_s": 3600, "open_after": 1, "resolve_after": 1, "tags": ["test"], "enabled": true}');

-- 1. The API is the service role's -------------------------------------------------------------------------------------
select pg_temp.ok(not has_function_privilege('authenticated', 'one.tests_state(text,integer)', 'execute')
                  and has_function_privilege('service_role', 'one.test_run_finish(bigint,text,boolean,text,jsonb,jsonb)', 'execute'),
                  'only the app runs tests');

set role service_role;
-- 2. Start: one run in flight per test, one run per slot ---------------------------------------------------------------
select (one.test_run_start('T-LOCAL', 'schedule', 'T-LOCAL:slot-1', 'runner-a', 90) ->> 'id')::bigint as r1 \gset
select pg_temp.ok(:r1 is not null, 'a run starts');
select pg_temp.ok(one.test_run_start('T-LOCAL', 'schedule', 'T-LOCAL:slot-2', 'runner-a', 90) is null, 'not while one is in flight');
select pg_temp.ok(jsonb_array_length(one.tests_state('runner-b', 90) -> 'runs') = 0, 'another runner cannot take a run under lease');
select pg_temp.ok((one.tests_state('runner-a', 90) #>> '{identities,phone_prefix}') is not null, 'the state carries the test identities');

-- 3. Save: only the holder; free text is redacted ------------------------------------------------------------------------
select pg_temp.ok(pg_temp.err(format('select one.test_run_save(%s, ''runner-b'', 90, ''[]'', ''{}'', ''{}'')', :r1)) = '55000', 'only the holder saves');
select one.test_run_save(:r1, 'runner-a', 90,
  '[{"key": "a", "title": "Step A", "ok": true, "ms": 1200, "detail": "reply to +91 98111 22334 seen", "at": "2026-10-23T10:00:00Z"}]',
  '{"phones": ["910000000001"], "lead_id": 7}', '{"step": 1, "stepStartedAt": "2026-10-23T10:00:01Z", "acted": false}');
reset role;
select pg_temp.ok((select step_results -> 0 ->> 'detail' = '[phone]' and artefacts ->> 'lead_id' = '7' and not artefacts ? 'phones' and (state ->> 'step')::int = 1
                     from one.test_runs where id = :r1), 'step details are redacted; artefacts are kept, but the runner cannot set the phones the purge acts on');

-- 4. Finish: a failure opens the test's incident; the next pass resolves it ------------------------------------------------
set role service_role;
select one.test_run_finish(:r1, 'runner-a', false, 'a: timeout',
  '[{"key": "a", "title": "Step A", "ok": false, "ms": 30000, "detail": "not seen within 30 s", "at": "2026-10-23T10:00:31Z"}]', null);
reset role;
select pg_temp.ok((select count(*) = 1 from one.incidents where check_id = 'T-LOCAL' and resolved_at is null), 'a failing run opens the incident');
select pg_temp.ok((select value ->> 'failed_step' = 'a' from one.results where check_id = 'T-LOCAL' order by id desc limit 1), 'naming the failed step');
set role service_role;
select pg_temp.ok(one.test_run_start('T-LOCAL', 'schedule', 'T-LOCAL:slot-1', 'runner-a', 90) is null, 'a slot that ran does not run again');
select (one.test_run_start('T-LOCAL', 'schedule', 'T-LOCAL:slot-3', 'runner-a', 90) ->> 'id')::bigint as r2 \gset
select one.test_run_finish(:r2, 'runner-a', true, null,
  '[{"key": "a", "title": "Step A", "ok": true, "ms": 900, "detail": null, "at": "2026-10-23T11:00:01Z"}]', null);
reset role;
select pg_temp.ok((select count(*) = 0 from one.incidents where check_id = 'T-LOCAL' and resolved_at is null), 'a passing run resolves it');

-- 5. Run now: the request is taken once and recorded on the run ---------------------------------------------------------
update one.tests set run_requested_at = now(), run_requested_by = 'eng@eduwit.in' where id = 'T-LOCAL';
set role service_role;
select (one.test_run_start('T-LOCAL', 'manual', 'T-LOCAL:manual:x', 'runner-a', 90) ->> 'id')::bigint as r3 \gset
reset role;
select pg_temp.ok((select trigger = 'manual' and requested_by = 'eng@eduwit.in' from one.test_runs where id = :r3)
                  and (select run_requested_at is null from one.tests where id = 'T-LOCAL'), 'a manual run records who asked, and the request is cleared');

-- 6. Leases and the reaper -----------------------------------------------------------------------------------------------------
update one.test_runs set lease_until = now() - interval '1 second' where id = :r3;
set role service_role;
select pg_temp.ok((select (one.tests_state('runner-b', 90) -> 'runs' -> 0 ->> 'id')::bigint = :r3), 'an expired lease passes to the next runner');
select one.test_run_save(:r3, 'runner-b', 0, '[]', '{}', null);
reset role;
select pg_temp.ok((select lease_until is null from one.test_runs where id = :r3), 'a waiting run is saved with its lease released');
set role service_role;
select pg_temp.ok((select (one.tests_state('runner-c', 90) -> 'runs' -> 0 ->> 'id')::bigint = :r3), 'so the next invocation takes it at once');
reset role;
update one.test_runs set started_at = now() - interval '2 hours', lease_until = now() - interval '1 second' where id = :r3;
set role service_role;
select one.tests_state('runner-c', 90);
reset role;
select pg_temp.ok((select finished_at is not null and not ok and error ~ '^abandoned' from one.test_runs where id = :r3), 'a run no runner reached is closed as failed');

-- 7. The Tests page shows steps with their timeouts, and what the test waits for -------------------------------------------
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in') on conflict do nothing;
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000001') on conflict do nothing;
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner') on conflict do nothing;
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000001', 'email_code')
on conflict do nothing;
set role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000f1"}', false);
select pg_temp.ok((select t -> 'step_defs' -> 0 ->> 'timeout_s' = '30' and t -> 'needs' -> 0 ->> 'item' = 'email' and jsonb_array_length(t -> 'runs') = 3
                     from jsonb_array_elements(one.ui_tests()) t where t ->> 'id' = 'T-LOCAL'), 'the Tests page reads steps, needs and runs');
reset role;
select set_config('request.jwt.claims', '', false);

-- 8. The catalogue (0015): a test runs only when its Setup items are validated, and its check follows it ---------------------
select pg_temp.ok((select enabled and disabled_reason is null from one.tests where id = 'T-ALERT')
                  and (select enabled and kind = 'test' from one.checks where id = 'T-ALERT'), 'T-ALERT needs only email, which is validated: on, with its check');
select pg_temp.ok((select not enabled and disabled_reason = 'setup:test_whatsapp_number' from one.tests where id = 'T-WITTY-TURN')
                  and (select not enabled and disabled_reason = 'builder:follows-its-test' from one.checks where id = 'T-WITTY-TURN'),
                  'T-WITTY-TURN waits for the test number, and so does its check');
select pg_temp.ok((select disabled_reason = 'blocked:no-safe-catalogue-write' from one.tests where id = 'T-WEB-CATALOG'), 'T-WEB-CATALOG is blocked');
set role service_role;
select one.setup_validated('test_b2b_intake_key', true, 'intake-only key saved', 'connect@eduwit.in');
reset role;
select pg_temp.ok((select disabled_reason = 'setup:test_runner_user' from one.tests where id = 'T-HANDOFF'), 'validating one item moves a test to the next it needs');
set role service_role;
select one.setup_validated('chatwoot', true, 'account and inbox read', 'connect@eduwit.in');
select one.setup_validated('test_whatsapp_number', true, 'in w2_trusted with is_test', 'connect@eduwit.in');
reset role;
select pg_temp.ok((select enabled from one.tests where id = 'T-WITTY-TURN') and (select enabled from one.checks where id = 'T-WITTY-TURN'),
                  'with every item validated, the test and its check are on');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in') on conflict do nothing;
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000002') on conflict do nothing;
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer') on conflict do nothing;
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000002', 'email_code')
on conflict do nothing;
set role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000f2"}', false);
select pg_temp.ok(pg_temp.err($q$select one.ui_test_update('T-WITTY-TURN', '{"enabled": false}', 'noisy')$q$) = '42501', 'an engineer cannot switch a P1 test off');
select pg_temp.ok(pg_temp.err($q$select one.ui_test_update('T-WEB-CATALOG', '{"enabled": true}', 'try it')$q$) = '22023', 'nor switch on a blocked one');
select pg_temp.ok(pg_temp.err($q$select one.ui_test_update('T-HANDOFF', '{"enabled": true}', 'try it')$q$) = '22023', 'nor one whose identities are not set up');
select pg_temp.ok((one.ui_test_update('T-ALERT', '{"schedule": "15 5 * * *"}', 'later') ->> 'ok')::boolean, 'but moves a schedule');
reset role;
select set_config('request.jwt.claims', '', false);
set role service_role;
select one.setup_validated('test_whatsapp_number', false, 'removed from w2_trusted', 'connect@eduwit.in');
reset role;
select pg_temp.ok((select not enabled and disabled_reason = 'setup:test_whatsapp_number' from one.tests where id = 'T-WITTY-TURN')
                  and (select not enabled from one.checks where id = 'T-WITTY-TURN'), 'losing a validation switches the test and its check off');

delete from one.test_runs where test_id = 'T-LOCAL';
delete from one.tests where id = 'T-LOCAL';
truncate one.incidents restart identity cascade;
delete from one.check_state where check_id = 'T-LOCAL';
delete from one.results where check_id = 'T-LOCAL';
delete from one.checks where id = 'T-LOCAL';
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
