-- B2B CRM job schedules for the shared database's load (estate audit, B2B-L1 and B2B-L2; owner approved 31 Oct 2026).
-- Run once in the Supabase SQL editor (production), in one go. Not a migration: nothing applies it automatically.
-- Why: the B2B CRM starts 2,411 of the estate's ~3,120 pg_cron runs an hour, almost all with nothing to do before go-live,
-- and the bursts at :00 and :30 exceed cron.max_running_jobs (32); the stalls show as "job startup timeout" for every app.
-- Effect: about 1,048 B2B starts an hour; the nightly jobs leave the 20:40-22:15 UTC pile-up; the run-history clean-up
-- moves to 08:23 UTC, keeps 3 days and always keeps each job's newest run.
-- At go-live, restore the jobs the revert block names (each with its condition) and keep the rest.
begin;
select cron.alter_job(jobid, schedule := '30 seconds') from cron.job where jobname in ('b2b-b2c-sync-tick', 'b2b-push-tick', 'b2b-intake-tick');
select cron.alter_job(jobid, schedule := '45 seconds') from cron.job where jobname in ('b2b-outbox-tick', 'b2b-notify-tick');
select cron.alter_job(jobid, schedule := '4-59/5 * * * *') from cron.job where jobname = 'b2b-capi-tick';
select cron.alter_job(jobid, schedule := '2-59/5 * * * *') from cron.job where jobname = 'b2b-partner-sync-tick';
select cron.alter_job(jobid, schedule := '1-59/5 * * * *') from cron.job where jobname in ('b2b-money-tick', 'b2b-ai-autopilot');
select cron.alter_job(jobid, schedule := '2-59/5 * * * *') from cron.job where jobname = 'b2b-sla-tick';
select cron.alter_job(jobid, schedule := '3-59/5 * * * *') from cron.job where jobname in ('b2b-guard-tick', 'b2b-ai-schedule');
select cron.alter_job(jobid, schedule := '4-59/5 * * * *') from cron.job where jobname = 'b2b-lost-grace-tick';
select cron.alter_job(jobid, schedule := '6-59/10 * * * *') from cron.job where jobname = 'b2b-ml-tick';
select cron.alter_job(jobid, schedule := '8-59/15 * * * *') from cron.job where jobname = 'b2b-refresh-facts';
select cron.alter_job(jobid, schedule := '47 2 * * *') from cron.job where jobname = 'b2b-retention';
select cron.alter_job(jobid, schedule := '53 2 * * *') from cron.job where jobname = 'b2b-reconcile-nightly';
select cron.alter_job(jobid, schedule := '47 3 * * *') from cron.job where jobname = 'b2b-ml-prune';
select cron.alter_job(
  job_id   := (select jobid from cron.job where jobname = 'b2b-cron-prune'),
  schedule := '23 8 * * *',
  command  := $cmd$delete from cron.job_run_details d
                    where d.start_time < now() - interval '3 days'
                      and d.runid <> all (array(select max(x.runid) from cron.job_run_details x group by x.jobid))$cmd$);
commit;

-- Check afterwards (expect the new schedules):
--   select jobname, schedule from cron.job where jobname like 'b2b-%' order by jobname;

-- Revert block (the schedules on 31 Oct 2026 before this file; run only the lines whose condition has come true):
--   when the B2C CRM holds leads:      select cron.alter_job(jobid, schedule := '5 seconds')  from cron.job where jobname = 'b2b-b2c-sync-tick';
--   when the first partner goes live:  select cron.alter_job(jobid, schedule := '10 seconds') from cron.job where jobname = 'b2b-push-tick';
--                                      select cron.alter_job(jobid, schedule := '* * * * *')  from cron.job where jobname = 'b2b-partner-sync-tick';
--   when a CAPI switch goes live:      select cron.alter_job(jobid, schedule := '* * * * *')  from cron.job where jobname = 'b2b-capi-tick';
--   keep as set here: b2b-intake-tick (30 seconds even live), b2b-outbox-tick and b2b-notify-tick (45 seconds), the */5,
--   */10 and */15 offsets, the nightly times, and the clean-up at 08:23 UTC.
--   The full previous state: b2b-intake-tick '10 seconds'; b2b-outbox-tick '15 seconds'; b2b-notify-tick '30 seconds';
--   b2b-money-tick, b2b-ai-autopilot, b2b-sla-tick, b2b-guard-tick, b2b-ai-schedule, b2b-lost-grace-tick '*/5 * * * *';
--   b2b-ml-tick '*/10 * * * *'; b2b-refresh-facts '*/15 * * * *'; b2b-retention '45 20 * * *';
--   b2b-reconcile-nightly '7 21 * * *'; b2b-ml-prune '40 21 * * *'; b2b-cron-prune '15 22 * * *' with
--   delete from cron.job_run_details where start_time < now() - interval '7 days'
-- Note: m33f schedules b2b-cron-prune; a rebuild from the migrations would bring its old schedule back until a migration
-- reschedules it the same way.
