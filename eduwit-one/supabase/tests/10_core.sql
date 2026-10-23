-- Core behaviour of schema one. Local test cluster only (scripts/db/local-test.sh). Fixtures are written as the
-- bootstrap superuser; the code under test runs as postgres, as pg_cron runs it on Supabase. Re-runnable: it resets
-- its fixtures first, because the cluster outlives a rollback and re-apply.
\set ON_ERROR_STOP 1
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;

truncate cron.job_run_details, net.http_request_queue, vault.secrets;
delete from cron.job where jobname not in ('one-tick', 'one-nightly');
truncate public.w2_events, public.w2_messages, public.w2_outbox, public.touchpoints, b2b.events, b2c.events, public.student_leads restart identity;
update public.stub_health set value = '[]' where app = 'witty';
drop function if exists public.new_anon_rpc();

-- 1. Seeds and schedule -----------------------------------------------------------------------------------------------
set role postgres;
select pg_temp.ok((select count(*) from one.settings) >= 15, 'settings seeded');
select pg_temp.ok((select value ? 'items' from one.settings where key = 'setup'), 'setup checklist loaded into one.settings.setup');
select pg_temp.ok((select count(*) from one.checks) >= 9, 'checks seeded');
select pg_temp.ok(exists (select 1 from cron.job where jobname = 'one-tick' and schedule = '* * * * *'), 'one-tick scheduled every minute');
select pg_temp.ok(exists (select 1 from cron.job where jobname = 'one-nightly' and schedule = '0 21 * * *'), 'one-nightly scheduled at 02:30 IST');

-- 2. Tick: report without errors, idempotent within a minute -----------------------------------------------------------
create temp table t_tick as select one.tick() as r;
select pg_temp.ok((select r::text !~ '_error"' and r::text !~ 'check_errors' from t_tick), 'tick report has no error keys: ' || (select r::text from t_tick));
select pg_temp.ok((select (one.tick() ? 'skipped') or date_trunc('minute', clock_timestamp()) > date_trunc('minute', (r ->> 'at')::timestamptz) from t_tick),
                  'a second tick in the same minute does nothing');
select pg_temp.ok((select last_ok_at > now() - interval '1 minute' from one.heartbeats where component = 'one:tick'), 'tick writes its heartbeat');

-- 3. A failing check opens a P1, queues the email and an AI triage task ------------------------------------------------
select pg_temp.ok(exists (select 1 from one.incidents where check_id = 'PLAT-05' and resolved_at is null and severity = 'P1'), 'PLAT-05 (base URLs and keys missing) opened a P1');
select pg_temp.ok(exists (select 1 from one.deliveries d join one.incidents i on i.id = d.incident_id
                           where i.check_id = 'PLAT-05' and d.recipient = 'connect@eduwit.in' and d.status = 'pending' and d.channel = 'email'), 'P1 email queued to the P1 inbox');
select pg_temp.ok(exists (select 1 from one.ai_tasks t join one.incidents i on i.id = t.incident_id where i.check_id = 'PLAT-05' and t.kind = 'triage'), 'triage task queued');
select pg_temp.ok((select alert_state = 'pending' from one.incidents where check_id = 'PLAT-05' and resolved_at is null), 'P1 alert state pending');

-- 4. Missing sources are not failures (D-009) ---------------------------------------------------------------------------
select pg_temp.ok((select last_status = 'source_missing' from one.check_state where check_id = 'INF-05'), 'INF-05 without schema inf is source_missing');
select pg_temp.ok(not exists (select 1 from one.incidents where check_id = 'INF-05'), 'source_missing opens no incident');

-- 5. Incident lifecycle: open, touch, recover after 3 ok runs, reopen within 24 h --------------------------------------
reset role;
insert into cron.job (jobname, schedule, command) values ('t-daily', '0 3 * * *', 'select 1');
insert into cron.job_run_details (jobid, status, return_message, start_time, end_time)
select jobid, 'failed', 'ERROR: boom', now() - interval '2 minutes', now() - interval '2 minutes' from cron.job where jobname = 't-daily';
set role postgres;
select one.run_check('PLAT-01');
select pg_temp.ok((select occurrences = 1 and severity = 'P1' from one.incidents where check_id = 'PLAT-01' and resolved_at is null), 'PLAT-01 opened on a failed run');
select one.run_check('PLAT-01');
select pg_temp.ok((select occurrences = 2 from one.incidents where check_id = 'PLAT-01' and resolved_at is null), 'a second failure touches the same incident');
reset role;
insert into cron.job_run_details (jobid, status, return_message, start_time, end_time)
select jobid, 'succeeded', '1 row', now() - interval '1 minute', now() - interval '1 minute' from cron.job where jobname = 't-daily';
set role postgres;
select one.run_check('PLAT-01'); select one.run_check('PLAT-01');
select pg_temp.ok(exists (select 1 from one.incidents where check_id = 'PLAT-01' and resolved_at is null), 'two ok runs do not resolve yet');
select one.run_check('PLAT-01');
select pg_temp.ok((select resolution = 'recovered' from one.incidents where check_id = 'PLAT-01'), 'three ok runs resolve as recovered');
reset role;
insert into cron.job_run_details (jobid, status, return_message, start_time, end_time)
select jobid, 'failed', 'ERROR: boom again', now(), now() from cron.job where jobname = 't-daily';
set role postgres;
select one.run_check('PLAT-01');
select pg_temp.ok((select count(*) = 1 and bool_and(reopened_count = 1 and resolved_at is null) from one.incidents where check_id = 'PLAT-01'), 'a failure within 24 h reopens, not duplicates');

-- 6. Startup timeouts are grouped, and escalate to P1 in bulk (D-008) ---------------------------------------------------
reset role;
insert into cron.job_run_details (jobid, status, return_message, start_time, end_time)
select jobid, 'failed', 'job startup timeout', now(), now() from cron.job, generate_series(1, 3) where jobname = 't-daily';
set role postgres;
select one.run_check('PLAT-01B');
select pg_temp.ok((select severity = 'P2' from one.incidents where check_id = 'PLAT-01B' and resolved_at is null), '3 startup timeouts: one P2 incident');
reset role;
insert into cron.job_run_details (jobid, status, return_message, start_time, end_time)
select jobid, 'failed', 'job startup timeout', now(), now() from cron.job, generate_series(1, 10) where jobname = 't-daily';
set role postgres;
select one.run_check('PLAT-01B');
select pg_temp.ok((select severity = 'P1' from one.incidents where check_id = 'PLAT-01B' and resolved_at is null), '13 startup timeouts escalate the same incident to P1');

-- 7. A check's value can raise its severity (WITTY-01) ------------------------------------------------------------------
reset role;
update public.stub_health set value = '[{"alert": "outbox_failed", "detail": "1"}]' where app = 'witty';
set role postgres;
select one.run_check('WITTY-01');
select pg_temp.ok((select severity = 'P1' from one.incidents where check_id = 'WITTY-01' and resolved_at is null), 'outbox_failed makes WITTY-01 a P1');
reset role;
update public.stub_health set value = '[]' where app = 'witty';
set role postgres;

-- 8. A seed never overwrites a person's setting (spec §16.8) ------------------------------------------------------------
select one.settings_put('proposals', '{"expire_days": 30, "approvers": []}', 'owner@eduwit.in', 'test');
select one.settings_put('proposals', '{"expire_days": 14, "approvers": []}', 'seed', 'reseed');
select pg_temp.ok((select (value ->> 'expire_days')::int = 30 and actor = 'owner@eduwit.in' from one.settings where key = 'proposals'), 'a person''s value survives a reseed');
select pg_temp.ok((select max(version) from one.settings_versions where key = 'proposals') = (select version from one.settings where key = 'proposals'), 'every change is versioned');
