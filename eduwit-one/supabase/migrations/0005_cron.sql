-- 0005 the two pg_cron jobs (spec §5). cron.schedule replaces a job of the same name, so re-running is safe.
-- 02:30 IST = 21:00 UTC.

do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'cron') then
    raise notice '0005: pg_cron not installed; jobs not scheduled';
    return;
  end if;
  perform cron.schedule('one-tick', '* * * * *', 'select one.tick()');
  perform cron.schedule('one-nightly', '0 21 * * *', 'select one.nightly()');
end $$;
