-- Rollback of 0033 a lighter minute tick: PLAT-01 and B2C-01 as 0006 seeded them before 0033 (every minute, the
-- distinct-on queries). A cadence a person set on Settings stays.

-- PLAT-01 before 0033.
select one.seed_check(jsonb_build_object(
  'id', 'PLAT-01',
  'app', 'platform',
  'kind', 'sql',
  'severity', 'P1',
  'cadence_s', 60,
  'open_after', 1,
  'resolve_after', 3,
  'title', 'A cron job''s latest run failed',
  'description', 'A one-tick run that a killed check or event copy ended is left to that check''s incident (hardening F3). The latest finished run in the last 26 h of each active cron job ended in "failed" (a run still in progress is ignored, so it cannot hide the failure before it). Each job is a subject: a job joining the failing set alerts again (D-043). "job startup timeout" is left to PLAT-01B (D-008); b2c-capacity has its own P2 check, B2C-10. Reads only the newest cron_scan_runs runs, through the runid key (M3 and M7 of the second review); jobs that ran less than daily are PLAT-01W''s.',
  'auto_fix_id', null,
  'tags', '["cron"]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with w as (select coalesce(max(runid), 0) - (select one.threshold('cron_scan_runs'))::bigint as from_runid from cron.job_run_details),
last_run as (
  select distinct on (d.jobid) d.jobid, d.status, d.return_message, d.start_time
    from cron.job_run_details d, w
   where d.runid > w.from_runid and d.start_time > now() - interval '26 hours'
     and d.status in ('succeeded', 'failed') and d.return_message is distinct from 'job startup timeout'
   order by d.jobid, d.runid desc),
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

-- B2C-01 before 0033 (as 0029 seeded it).
select one.seed_check(jsonb_build_object(
  'id', 'B2C-01',
  'app', 'b2c',
  'kind', 'sql',
  'severity', 'P1',
  'cadence_s', 60,
  'open_after', 1,
  'resolve_after', 3,
  'title', 'Spark''s timers or its answers to them are failing',
  'description', 'Direct read of system_health''s "timers" and "app" checks: no b2c-* job at all, a b2c-* job whose latest finished run failed (a run in progress is ignored; startup timeouts excluded, see PLAT-01B; b2c-capacity left to B2C-10), or a Spark job call answered with an error status in the last hour. Reads the newest cron_scan_runs runs through the runid key in one pass for all of Spark''s jobs (M3, M7 of the second review; one pass since 0029, D-103: the per-job lookups took 9 s a minute).',
  'auto_fix_id', null,
  'tags', '["cron"]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with w as (select coalesce(max(runid), 0) - (select one.threshold('cron_scan_runs'))::bigint as from_runid from cron.job_run_details),
timers as (select j.jobid, j.jobname from cron.job j where j.jobname like 'b2c-%' and j.jobname <> 'b2c-capacity' and j.active),
last_run as (
  select distinct on (d.jobid) d.jobid, d.status
    from cron.job_run_details d, w
   where d.runid > w.from_runid and d.jobid in (select t.jobid from timers t)
     and d.status in ('succeeded', 'failed') and d.return_message is distinct from 'job startup timeout'
   order by d.jobid, d.runid desc),
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
