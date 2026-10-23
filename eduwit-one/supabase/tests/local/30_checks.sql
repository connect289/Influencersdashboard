-- Phase 2 criteria on the stubbed path (spec §14): the known live findings open the expected incidents, a stale
-- heartbeat opens an HB incident, a never-seen component stays quiet, and a check that is off for setup is skipped.
-- Local test cluster only.
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

-- 1. b2c-capacity fails every day on production: B2C-10 opens a P2, and PLAT-01 does not raise it a second time --------
delete from cron.job_run_details where jobid in (select jobid from cron.job where jobname = 'b2c-capacity');
delete from cron.job where jobname = 'b2c-capacity';
insert into cron.job (jobname, schedule, command) values ('b2c-capacity', '15 4 * * *', 'select b2c.capacity_tick()');
insert into cron.job_run_details (jobid, status, return_message, start_time, end_time)
select jobid, 'failed', 'ERROR:  cannot extract elements from a scalar', now() - interval '1 hour', now() - interval '1 hour'
  from cron.job where jobname = 'b2c-capacity';
set role postgres;
select one.run_check('B2C-10');
select pg_temp.ok((select severity = 'P2' and alert_state = 'digest' from one.incidents where check_id = 'B2C-10' and resolved_at is null),
                  'b2c-capacity failing opens a P2 B2C-10 incident, routed to the digest');
create temp table t_p1 as select one.run_check('PLAT-01') as r;
select pg_temp.ok(not exists (select 1 from one.results where check_id = 'PLAT-01' and ran_at > now() - interval '1 minute'
                                and value::text ~ 'b2c-capacity'), 'PLAT-01 leaves b2c-capacity to B2C-10');

-- 2. A stale heartbeat opens its HB incident; a never-seen component does not ---------------------------------------
reset role;
delete from one.heartbeats where component in ('website', 'spark');
insert into one.heartbeats (component, last_ok_at, expected_interval_s) values ('website', now() - interval '10 minutes', 60);
set role postgres;
select one.run_check('HB-website');
select pg_temp.ok((select severity = 'P1' from one.incidents where check_id = 'HB-website' and resolved_at is null), 'a website heartbeat 10 min old opens a P1');
select one.run_check('HB-spark');
select pg_temp.ok((select last_status = 'ok' from one.check_state where check_id = 'HB-spark'), 'a component never seen reports ok (never_seen), not down');
reset role;
insert into one.heartbeats (component, last_error_at, last_error, expected_interval_s) values ('spark', now(), 'health 503', 120);
set role postgres;
select one.run_check('HB-spark');
select pg_temp.ok((select last_status = 'fail' from one.check_state where check_id = 'HB-spark'), 'a component read but never once ok is down');
reset role;
delete from one.heartbeats where component = 'spark';
set role postgres;
select one.heartbeat('website', true, '{"probe": "test"}', null, 60);
select one.run_check('HB-website'); select one.run_check('HB-website'); select one.run_check('HB-website');
select pg_temp.ok((select resolution = 'recovered' from one.incidents where check_id = 'HB-website' order by id desc limit 1), 'fresh heartbeats resolve it');

-- 3. A check that is off until configured is skipped, never failed ---------------------------------------------------
select pg_temp.ok((one.run_check('HB-n8n:PKPs7tXg9bej8AgX') ->> 'status') = 'skipped', 'a setup-gated check is skipped');
select pg_temp.ok((select disabled_reason = 'setup:n8n_api' and not enabled from one.checks where id = 'WITTY-02'), 'WITTY-02 waits for Setup item n8n_api');

-- 4. App-run checks report through one.report_result; a disabled one is refused --------------------------------------
select pg_temp.ok(one.report_result('WEB-02', 'fail', '{"status": 503}', null, 120) in ('none', 'opened'), 'the app can report WEB-02');
select pg_temp.ok(one.report_result('WEB-02', 'fail', '{"status": 503}', null, 120) = 'opened', 'WEB-02 opens on the second failure (open_after 2)');
do $$ begin
  perform one.report_result('WITTY-02', 'fail', '{}', null, 10);
  raise exception 'ASSERT FAILED: a disabled check accepted a report';
exception when invalid_parameter_value then null;
end $$;
reset role;
