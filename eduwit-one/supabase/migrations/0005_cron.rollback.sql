-- Rollback of 0005: unschedules both jobs (their past runs stay in cron.job_run_details until pg_cron prunes them).

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.unschedule(jobid) from cron.job where jobname in ('one-tick', 'one-nightly');
  end if;
end $$;
