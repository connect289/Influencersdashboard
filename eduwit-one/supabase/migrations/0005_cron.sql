-- 0005 the minute job's procedure and the two pg_cron jobs (spec §5). cron.schedule replaces a job of the same name,
-- so re-running is safe. 02:30 IST = 21:00 UTC. A tick that fires before 0006 and 0007 have seeded the checks and the
-- settings runs no check and copies no event (one.events_copy refuses an empty PII list; M4 of the second review).

-- What pg_cron runs every minute: the steps of one.tick(), each in its own transaction, so no app table stays locked
-- for the whole tick and a slow step cannot undo the others (D-044). On Postgres 17 and later,
-- checks.transaction_timeout bounds each transaction. Order (B1 of the second review, D-056):
--   1. the one:tick heartbeat; the tick lock (one tick at a time; a session lock, released when pg_cron's session
--      ends, also when a kill ends it); the minute's run row;
--   2. one.reap_killed(): a check or an event copy that started in an earlier tick and never finished gets an error
--      result (so its incident opens) and is moved out of the way;
--   3. the due checks, each with its start mark committed first, so a kill cannot roll the mark back;
--   4. the alert step, then the app call (the alert sender); the run is "finished" here, and the external watchdog
--      reads this time, not the heartbeat;
--   5. the event copies, then the checks whose last run was killed, each with its start mark committed first.
-- A procedure that commits cannot carry SET clauses, so this one sets its search_path at the start of the session
-- pg_cron opens for it; every name inside is schema-qualified anyway.
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
  commit;
  if not pg_catalog.pg_try_advisory_lock(pg_catalog.hashtext('one.tick')) then
    return;
  end if;
  insert into one.runs (kind, bucket) values ('tick', date_trunc('minute', now()))
  on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    perform pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('one.tick'));
    commit;
    return;
  end if;
  v_report := v_report || one.reap_killed();
  update one.runs set report = v_report where id = v_run;
  commit;
  for v_id in select one.due_checks(false) loop
    perform one.mark_started(v_id);
    commit;
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  v_report := v_report || one.alerts_step();
  update one.runs set report = v_report where id = v_run;
  commit;
  v_report := v_report || one.tick_app_call();
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  commit;
  for v_src in select * from one.events_due() loop
    perform one.mark_source_started(v_src.source);
    commit;
    v_report := jsonb_set(v_report, '{events}', coalesce(v_report -> 'events', '{}') || one.events_copy_safe(v_src.source, v_src.app, v_src.sql));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  for v_id in select one.due_checks(true) loop
    perform one.mark_started(v_id);
    commit;
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
    update one.runs set report = v_report where id = v_run;
    commit;
  end loop;
  perform pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('one.tick'));
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
