-- 0005 the minute job's procedure and the two pg_cron jobs (spec §5). cron.schedule replaces a job of the same name,
-- so re-running is safe. 02:30 IST = 21:00 UTC.

-- What pg_cron runs every minute: the steps of one.tick(), with a commit after the heartbeat, after each check, after
-- each event source and after the app call, so no app table stays locked for the whole tick and a slow step cannot
-- undo the others (D-044). On Postgres 17 and later, checks.transaction_timeout bounds each of those transactions; a
-- run it kills fails visibly in cron.job_run_details (PLAT-01), and the check it was running goes to the back of the
-- next tick (one.due_checks orders by last start). A procedure that commits cannot carry SET clauses, so this one sets
-- its search_path at the start of the session pg_cron opens for it; every name inside is schema-qualified anyway.
create or replace procedure one.tick_job()
language plpgsql as $$
declare
  v_run bigint;
  v_report jsonb := jsonb_build_object('at', now(), 'mode', 'job');
  v_id text;
  v_src record;
begin
  perform pg_catalog.set_config('search_path', '', false);
  if pg_catalog.current_setting('server_version_num')::int >= 170000 then
    perform pg_catalog.set_config('transaction_timeout', coalesce(one.setting('checks') ->> 'transaction_timeout', '30s'), false);
  end if;
  perform one.heartbeat('one:tick', true, jsonb_build_object('at', now()), null, 60);
  insert into one.runs (kind, bucket) values ('tick', date_trunc('minute', now()))
  on conflict (kind, bucket) do nothing returning id into v_run;
  commit;
  if v_run is null then
    return;
  end if;
  for v_id in select one.due_checks() loop
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  for v_src in select * from one.events_sources() loop
    v_report := jsonb_set(v_report, '{events}', coalesce(v_report -> 'events', '{}') || one.events_copy_safe(v_src.source, v_src.app, v_src.sql));
    commit;
  end loop;
  v_report := v_report || one.tick_app_call();
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  commit;
end $$;

call one.apply_grants();

do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'cron') then
    raise notice '0005: pg_cron not installed; jobs not scheduled';
    return;
  end if;
  perform cron.schedule('one-tick', '* * * * *', 'call one.tick_job()');
  perform cron.schedule('one-nightly', '0 21 * * *', 'select one.nightly()');
end $$;
