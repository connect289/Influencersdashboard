-- Rollback of 0005: unschedules both jobs (their past runs stay in cron.job_run_details until pg_cron prunes them) and
-- removes the minute job's procedure.

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.unschedule(jobid) from cron.job where jobname in ('one-tick', 'one-nightly');
  end if;
end $$;
drop procedure if exists one.tick_job();
