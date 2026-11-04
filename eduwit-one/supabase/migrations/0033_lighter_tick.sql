-- 0033 a lighter minute tick (D-128). On 1 Nov 2026 Eduwit One's one-tick was the heaviest job in the shared database:
-- about 5 s of database time a minute, over half of it PLAT-01 reading a day of pg_cron's run history (4.5 s cold;
-- 83 ms when its pages happened to be in memory), and B2C-01 the same way for Spark's jobs (0.8 s). The database is the
-- Micro compute, where some 20 jobs open a connection at the top of every minute, so every second the tick spends there
-- is a second the apps' jobs wait for. What changes, for these two checks only:
--   1. PLAT-01 and B2C-01 run every 5 minutes instead of every minute (same severity, same alerts, same subjects).
--      Stalls stay PLAT-01B's (job startup timeouts), which still runs every minute and costs 24 ms.
--   2. Each finds every job's newest run by its run number first (a hash aggregate over two columns) and then reads only
--      those rows, instead of sorting a day of history with its messages. The same answers, job by job, checked side by
--      side on production on 1 Nov (55 ms warm against 85 to 100 ms).
-- A cadence a person set on Settings stays (one.seed_check keeps it). Nothing of the five apps is touched; only schema
-- one. Rollback: 0033_lighter_tick.rollback.sql.

-- 1. PLAT-01, as 0006 now seeds it.
select one.seed_check(jsonb_build_object(
  'id', 'PLAT-01',
  'app', 'platform',
  'kind', 'sql',
  'severity', 'P1',
  'cadence_s', 300,
  'open_after', 1,
  'resolve_after', 3,
  'title', 'A cron job''s latest run failed',
  'description', 'A one-tick run that a killed check or event copy ended is left to that check''s incident (hardening F3). The latest finished run in the last 26 h of each active cron job ended in "failed" (a run still in progress is ignored, so it cannot hide the failure before it). Each job is a subject: a job joining the failing set alerts again (D-043). "job startup timeout" is left to PLAT-01B (D-008); b2c-capacity has its own P2 check, B2C-10. Reads only the newest cron_scan_runs runs, through the runid key (M3 and M7 of the second review); jobs that ran less than daily are PLAT-01W''s. Every 5 minutes since 0033 (D-128): it was over half of the minute tick''s database time, mostly reading a day of run history; job stalls stay PLAT-01B''s, every minute. Each job''s newest run is found by its run number first and only those rows are read.',
  'auto_fix_id', null,
  'tags', '["cron"]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with w as (select coalesce(max(runid), 0) - (select one.threshold('cron_scan_runs'))::bigint as from_runid from cron.job_run_details),
latest as (
  select d.jobid, max(d.runid) as runid
    from cron.job_run_details d, w
   where d.runid > w.from_runid and d.start_time > now() - interval '26 hours'
     and d.status in ('succeeded', 'failed') and d.return_message is distinct from 'job startup timeout'
   group by d.jobid),
last_run as (
  select d.jobid, d.status, d.return_message, d.start_time
    from latest l join cron.job_run_details d on d.runid = l.runid),
failed as (
  select j.jobname, r.start_time, left(r.return_message, 200) as message
    from cron.job j join last_run r on r.jobid = j.jobid
   where j.active and r.status = 'failed' and j.jobname <> 'b2c-capacity'
     and not (j.jobname = 'one-tick' and exists (select 1 from one.runs x where x.kind = 'tick' and x.report ? 'killed_error'
                                                   and x.started_at between r.start_time - interval '2 minutes' and r.start_time + interval '2 minutes')))
select count(*) = 0 as ok,
       jsonb_build_object('failed_jobs', coalesce(jsonb_agg(jsonb_build_object('job', jobname, 'at', start_time, 'message', message) order by jobname), '[]'),
                          'subjects', coalesce(jsonb_agg(jobname order by jobname), '[]')) as value
  from failed
$sql$));

-- 2. B2C-01, as 0006 now seeds it.
select one.seed_check(jsonb_build_object(
  'id', 'B2C-01',
  'app', 'b2c',
  'kind', 'sql',
  'severity', 'P1',
  'cadence_s', 300,
  'open_after', 1,
  'resolve_after', 3,
  'title', 'Spark''s timers or its answers to them are failing',
  'description', 'Direct read of system_health''s "timers" and "app" checks: no b2c-* job at all, a b2c-* job whose latest finished run failed (a run in progress is ignored; startup timeouts excluded, see PLAT-01B; b2c-capacity left to B2C-10), or a Spark job call answered with an error status in the last hour. Reads the newest cron_scan_runs runs through the runid key in one pass for all of Spark''s jobs (M3, M7 of the second review; one pass since 0029, D-103: the per-job lookups took 9 s a minute). Every 5 minutes since 0033 (D-128), each job''s newest run found by its run number first.',
  'auto_fix_id', null,
  'tags', '["cron"]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with w as (select coalesce(max(runid), 0) - (select one.threshold('cron_scan_runs'))::bigint as from_runid from cron.job_run_details),
timers as (select j.jobid, j.jobname from cron.job j where j.jobname like 'b2c-%' and j.jobname <> 'b2c-capacity' and j.active),
latest as (
  select d.jobid, max(d.runid) as runid
    from cron.job_run_details d, w
   where d.runid > w.from_runid and d.jobid in (select t.jobid from timers t)
     and d.status in ('succeeded', 'failed') and d.return_message is distinct from 'job startup timeout'
   group by d.jobid),
last_run as (select d.jobid, d.status from latest l join cron.job_run_details d on d.runid = l.runid),
jobs as (select t.jobname, r.status as last_status from timers t left join last_run r on r.jobid = t.jobid),
calls as (
  select count(*) as failed from b2c.job_calls c, jsonb_array_elements(c.calls) e join net._http_response r on r.id = (e ->> 'id')::bigint
   where r.created > now() - interval '1 hour' and (r.status_code is null or r.status_code >= 400))
select (select count(*) from jobs) > 0 and not exists (select 1 from jobs where last_status = 'failed') and (select failed from calls) = 0 as ok,
       jsonb_build_object('timers', (select count(*) from jobs),
                          'failed_jobs', (select coalesce(jsonb_agg(jobname order by jobname), '[]') from jobs where last_status = 'failed'),
                          'subjects', (select coalesce(jsonb_agg(jobname order by jobname), '[]') from jobs where last_status = 'failed'),
                          'failed_calls_1h', (select failed from calls)) as value
$sql$));
