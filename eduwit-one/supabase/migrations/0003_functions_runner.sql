-- 0003 (runner) check evaluation, the minute tick, the nightly run, the privilege audit, health (spec §5, §6).
-- one.tick() and one.nightly() follow b2c.minute_tick: every step in its own exception block, a JSON report with
-- <step>_error keys, and they never raise.

-- Records a result, moves the counters, and opens, touches or resolves the check's incident. Single writer of
-- one.results, one.check_state and the check-driven part of one.incidents. A check whose own SQL errors, or whose
-- source has gone missing, is a failure too: a P1 check that cannot run is a P1 blind spot (D-042). Only staging, where
-- sources are absent by design, sets checks.source_missing_opens_incident to false. A skipped run moves nothing.
create or replace function one.evaluate(p_check_id text, p_status text, p_value jsonb, p_error text, p_duration_ms integer) returns text
language plpgsql set search_path = '' as $$
declare
  v_check one.checks;
  v_state one.check_state;
  v_open bigint;
  v_severity one.severity;
  v_failing boolean;
  v_subjects text[];
begin
  select * into strict v_check from one.checks where id = p_check_id;
  v_failing := p_status in ('fail', 'error')
               or (p_status = 'source_missing' and coalesce((one.setting('checks') ->> 'source_missing_opens_incident')::boolean, true));
  insert into one.results (check_id, status, value, error, duration_ms) values (p_check_id, p_status, p_value, left(p_error, 1000), p_duration_ms);
  insert into one.check_state (check_id) values (p_check_id) on conflict do nothing;
  update one.check_state set
    last_ran_at = now(), last_status = p_status, killed_count = 0,
    consecutive_fail = case when v_failing then consecutive_fail + 1 when p_status = 'ok' then 0 else consecutive_fail end,
    consecutive_ok = case when p_status = 'ok' then consecutive_ok + 1 when v_failing then 0 else consecutive_ok end
   where check_id = p_check_id
   returning * into v_state;
  select id into v_open from one.incidents where check_id = p_check_id and resolved_at is null;
  if v_failing and v_state.consecutive_fail >= v_check.open_after then
    v_severity := case when p_status = 'fail' then coalesce(nullif(p_value ->> 'severity', '')::one.severity, v_check.severity) else v_check.severity end;
    v_subjects := case when p_status = 'fail' and jsonb_typeof(p_value -> 'subjects') = 'array'
                       then array(select jsonb_array_elements_text(p_value -> 'subjects')) else '{}' end;
    perform one.open_or_touch_incident(p_check_id, v_severity,
      jsonb_build_object('status', p_status, 'value', p_value, 'error', left(p_error, 300), 'at', now()), v_subjects);
    return case when v_open is null then 'opened' else 'touched' end;
  end if;
  if p_status = 'ok' and v_open is not null and v_state.consecutive_ok >= v_check.resolve_after then
    perform one.resolve_incident(v_open, 'one', 'recovered');
    return 'resolved';
  end if;
  return 'none';
end $$;

-- Runs one SQL check. Its sql is written only by migrations (column grants in 0002); it returns one row (ok boolean,
-- value jsonb). It runs under the check's own search_path (empty unless the check calls an invoker-rights app function,
-- D-042) and a lock timeout, so it never queues behind an app's migration: a lock wait gives up and the run is
-- skipped. A statement timeout cannot be armed inside a function; the cron job bounds each transaction instead (D-044).
create or replace function one.run_check(p_check_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_check one.checks;
  v_rows integer;
  v_ok boolean;
  v_value jsonb;
  v_status text;
  v_error text;
  v_started timestamptz := clock_timestamp();
  v_lock text := current_setting('lock_timeout');
begin
  select * into strict v_check from one.checks where id = p_check_id;
  if not v_check.enabled or v_check.sql is null then
    return jsonb_build_object('check', p_check_id, 'status', 'skipped', 'reason', coalesce(v_check.disabled_reason, 'no sql'));
  end if;
  begin
    perform set_config('search_path', v_check.search_path, true);
    perform set_config('lock_timeout', coalesce(one.setting('checks') ->> 'lock_timeout', '2s'), true);
    execute format('select count(*)::int, bool_and(ok), (array_agg(value))[1] from (%s) q', v_check.sql)
      into v_rows, v_ok, v_value;
    v_status := case when v_rows <> 1 then 'error' when v_ok then 'ok' else 'fail' end;
    v_error := case when v_rows <> 1 then format('check returned %s rows, expected 1', v_rows) end;
  exception
    when lock_not_available then
      v_status := 'skipped';
      v_error := 'lock wait over lock_timeout: ' || sqlerrm;
    when undefined_table or undefined_function or undefined_column or invalid_schema_name then
      v_status := 'source_missing';
      v_error := sqlerrm;
    when others then
      v_status := 'error';
      v_error := sqlerrm;
  end;
  perform set_config('search_path', '', true);
  perform set_config('lock_timeout', v_lock, true);
  return jsonb_build_object('check', p_check_id, 'status', v_status, 'error', left(v_error, 200),
    'incident', one.evaluate(p_check_id, v_status, v_value, v_error, (extract(epoch from clock_timestamp() - v_started) * 1000)::int));
end $$;

-- For checks the app runs (HTTP probes, synthetic tests): the app reports, the database decides. Only those kinds:
-- an rpc or heartbeat check is run by the tick, and a second writer could resolve what the tick found (m3).
create or replace function one.report_result(p_check_id text, p_status text, p_value jsonb, p_error text, p_duration_ms integer) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from one.checks where id = p_check_id and enabled and kind in ('http', 'test')) then
    raise exception 'one.report_result: % is not an enabled app-run check', p_check_id using errcode = '22023';
  end if;
  return one.evaluate(p_check_id, p_status, p_value, p_error, p_duration_ms);
end $$;

-- Checks due now, least recently started first. Due-ness counts in whole minutes from the start of this minute, so a
-- one-minute check that ran late in the last tick is still due in this one (M7). p_killed false: the checks whose
-- last run finished; true: those whose last run was killed (one.reap_killed), due again after 10 min per consecutive
-- kill, at most an hour, and run by the cron job only after the alert step and the app call (B1).
create or replace function one.due_checks(p_killed boolean default false) returns setof text
language sql stable set search_path = '' as $$
  select c.id from one.checks c left join one.check_state s on s.check_id = c.id
   where c.enabled and c.sql is not null
     and (coalesce(s.killed_count, 0) > 0) = p_killed
     and (s.last_ran_at is null
          or s.last_ran_at < date_trunc('minute', now()) - make_interval(secs => c.cadence_s - 60))
     and (not p_killed or s.last_started_at < now() - make_interval(mins => least(10 * s.killed_count, 60)))
   order by s.last_started_at nulls first, c.id
$$;

-- The check start mark, written and committed by the cron job before the check runs, so a run that is killed still
-- leaves it (B1 of the second review: in the check's own transaction the kill rolled it back).
create or replace function one.mark_started(p_check_id text) returns void
language sql set search_path = '' as $$
  insert into one.check_state (check_id, last_started_at) values (p_check_id, now())
  on conflict (check_id) do update set last_started_at = now()
$$;

-- At the start of a tick, under the tick lock: every check that started and never finished was killed (by
-- transaction_timeout, a cancel or a crash). Each gets an error result, which counts as a failure and opens its
-- incident like any error (D-042), and its kill count goes up. The same for an event copy that never finished.
create or replace function one.reap_killed() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_row record;
  v_checks text[] := '{}';
  v_sources text[] := '{}';
begin
  for v_row in
    select s.check_id, s.killed_count from one.check_state s
     where s.last_started_at > coalesce(s.last_ran_at, '-infinity'::timestamptz)
     order by s.check_id
  loop
    perform one.evaluate(v_row.check_id, 'error', null,
      'killed: the run started and did not finish (transaction_timeout, a cancel or a crash); it now runs after the alert step', null);
    update one.check_state set killed_count = v_row.killed_count + 1 where check_id = v_row.check_id;
    v_checks := v_checks || v_row.check_id;
  end loop;
  update one.event_watermarks set last_status = 'killed', last_error = 'the copy started and did not finish', updated_at = now()
   where last_started_at >= updated_at and last_status is distinct from 'killed';
  select coalesce(array_agg(source order by source), '{}') into v_sources from one.event_watermarks where last_status = 'killed' and updated_at = now();
  return case when cardinality(v_checks) + cardinality(v_sources) = 0 then '{}'::jsonb
              else jsonb_build_object('killed_error', jsonb_build_object('checks', to_jsonb(v_checks), 'sources', to_jsonb(v_sources))) end;
end $$;

-- One check, isolated: marks the start, runs it, and turns anything unexpected into an error result. Returns the
-- report fragment: {"status": ...} plus "<ID>_error" when the run errored, or its source is missing where that counts.
create or replace function one.run_check_safe(p_check_id text) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_out jsonb;
begin
  insert into one.check_state (check_id, last_started_at) values (p_check_id, now())
  on conflict (check_id) do update set last_started_at = now();
  begin
    v_out := one.run_check(p_check_id);
  exception when others then
    -- Recording or routing the result failed (run_check's own block covers the check's SQL). The rollback took the
    -- result with it, so keep an error result here; the "<ID>_error" key below reaches ONE-01 (m1).
    v_out := jsonb_build_object('check', p_check_id, 'status', 'error', 'error', left(sqlerrm, 200));
    insert into one.results (check_id, status, error) values (p_check_id, 'error', left('recording failed: ' || sqlerrm, 1000));
    update one.check_state set last_ran_at = now(), last_status = 'error', killed_count = 0 where check_id = p_check_id;
  end;
  return jsonb_build_object('status', v_out ->> 'status')
         || case when v_out ->> 'status' = 'error'
                   or (v_out ->> 'status' = 'source_missing' and coalesce((one.setting('checks') ->> 'source_missing_opens_incident')::boolean, true))
                 then jsonb_build_object(p_check_id || '_error', coalesce(v_out ->> 'error', v_out ->> 'status')) else '{}' end;
end $$;

-- Folds one check's fragment into a tick report: a count per status, and its "<ID>_error" key if any.
create or replace function one.report_add(p_report jsonb, p_fragment jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_set(p_report, '{checks}', coalesce(p_report -> 'checks', '{}')
           || jsonb_build_object(p_fragment ->> 'status', coalesce((p_report #>> array['checks', p_fragment ->> 'status'])::int, 0) + 1))
         || (p_fragment - 'status')
$$;

-- All due SQL checks in the caller's transaction (used by one.tick(); the cron job commits per check instead).
create or replace function one.run_sql_checks() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_id text;
  v_report jsonb := '{}';
begin
  for v_id in select one.due_checks() loop
    v_report := one.report_add(v_report, one.run_check_safe(v_id));
  end loop;
  return v_report;
end $$;

-- The minute tick by hand: everything in the caller's transaction, returning the report (spec §5: "run select
-- one.tick() by hand and inspect the report"). Heartbeat first, so the watchdog sees life even if a later step fails;
-- the unique minute bucket makes repeated calls within a minute do nothing (spec §16.5). pg_cron runs
-- one.tick_job(), the same steps with a commit after each (D-044).
create or replace function one.tick() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_run bigint;
  v_report jsonb := jsonb_build_object('at', now());
begin
  perform one.heartbeat('one:tick', true, jsonb_build_object('at', now()), null, 60);
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('one.tick')) then
    return v_report || jsonb_build_object('skipped', 'another tick is running');
  end if;
  insert into one.runs (kind, bucket) values ('tick', date_trunc('minute', now()))
  on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    return v_report || jsonb_build_object('skipped', 'already ran this minute');
  end if;
  v_report := v_report || one.reap_killed();
  begin
    v_report := v_report || one.run_sql_checks();
  exception when others then v_report := v_report || jsonb_build_object('checks_error', sqlerrm);
  end;
  v_report := v_report || one.alerts_step();
  v_report := v_report || one.tick_app_call();
  begin
    v_report := v_report || jsonb_build_object('events', one.events_refresh());
  exception when others then v_report := v_report || jsonb_build_object('events_error', sqlerrm);
  end;
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  return v_report;
end $$;

-- The app call at the end of a tick, isolated: the request id, "not_configured", or an app_error key.
create or replace function one.tick_app_call() returns jsonb
language plpgsql set search_path = '' as $$
begin
  return jsonb_build_object('app', coalesce(one.job_call('/api/internal/tick')::text, 'not_configured'));
exception when others then
  return jsonb_build_object('app_error', sqlerrm);
end $$;

-- Anon- or authenticated-executable SECURITY DEFINER functions outside the platform schemas. The first run is the
-- baseline (acknowledged); anything new afterwards stays unacknowledged until a person acknowledges it (PLAT-07).
create or replace function one.privilege_audit() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_first boolean := not exists (select 1 from one.privilege_baseline);
  v_new integer;
begin
  with current_set as (
    select p.oid::regprocedure::text as fn, n.nspname as schema,
           array_remove(array[case when has_function_privilege('anon', p.oid, 'execute') then 'anon' end,
                               case when has_function_privilege('authenticated', p.oid, 'execute') then 'authenticated' end], null) as roles
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.prosecdef
       and n.nspname not in ('pg_catalog', 'information_schema', 'auth', 'storage', 'graphql', 'graphql_public', 'realtime',
                             'extensions', 'vault', 'pgsodium', 'net', 'cron', 'pgbouncer', 'supabase_functions',
                             'supabase_migrations', 'pgmq', 'one'))
  insert into one.privilege_baseline (fn, schema, roles, acknowledged, acknowledged_by)
  select fn, schema, roles, v_first, case when v_first then 'baseline' end from current_set where cardinality(roles) > 0
  on conflict (fn) do update set roles = excluded.roles, last_seen = now(),
    -- A function that gains a role (authenticated-only opened to anon) must be looked at again (m7).
    acknowledged = one.privilege_baseline.acknowledged and excluded.roles <@ one.privilege_baseline.roles,
    acknowledged_by = case when excluded.roles <@ one.privilege_baseline.roles then one.privilege_baseline.acknowledged_by end;
  select count(*) into v_new from one.privilege_baseline where not acknowledged and last_seen > now() - interval '1 day';
  return jsonb_build_object('baseline_created', v_first, 'unacknowledged', v_new,
                            'total', (select count(*) from one.privilege_baseline where last_seen > now() - interval '1 day'));
end $$;

create or replace function one.retention() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('retention'), '{}');
  v_results integer;
  v_events integer;
  v_calls integer;
begin
  delete from one.results where ran_at < now() - make_interval(days => coalesce((v_cfg ->> 'results_days')::int, 90));
  get diagnostics v_results = row_count;
  delete from one.events where occurred_at < now() - make_interval(days => coalesce((v_cfg ->> 'events_days')::int, 180));
  get diagnostics v_events = row_count;
  delete from one.ai_calls where created_at < now() - make_interval(days => coalesce((v_cfg ->> 'ai_calls_days')::int, 365));
  get diagnostics v_calls = row_count;
  delete from one.runs where started_at < now() - interval '30 days';
  return jsonb_build_object('results', v_results, 'events', v_events, 'ai_calls', v_calls);
end $$;

-- Test-row purge goes through each app's own delete path, run by the app (phase 5). Here: how many runs are due.
create or replace function one.purge_test_rows() returns jsonb
language sql set search_path = '' as $$
  select jsonb_build_object('due', count(*), 'purged_by', 'app:/api/internal/tests/purge')
    from one.test_runs
   where purged_at is null and finished_at < now() - make_interval(days => coalesce((one.setting('tests') ->> 'purge_after_days')::int, 2))
$$;

-- Baselines the integrity checks compare against. Captured once; a person re-acknowledges a change from the UI,
-- which replaces the row. Never overwritten here, so a drift stays visible until someone accepts it.
create or replace function one.capture_baselines() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_captured text[] := '{}';
begin
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'lead_intake') then
    insert into one.baselines (key, value)
    select 'lead_intake_md5', jsonb_build_object('md5', md5(string_agg(p.prosrc, '' order by p.oid)))
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'lead_intake'
    on conflict (key) do nothing;
    if found then v_captured := v_captured || 'lead_intake_md5'::text; end if;
  end if;
  if to_regclass('public.student_leads') is not null then
    insert into one.baselines (key, value)
    select 'student_leads_columns', jsonb_agg(column_name || ':' || udt_name order by ordinal_position)
      from information_schema.columns where table_schema = 'public' and table_name = 'student_leads'
    on conflict (key) do nothing;
    if found then v_captured := v_captured || 'student_leads_columns'::text; end if;
  end if;
  -- Views the API roles can read that run with their owner's rights (Supabase lint security_definer_view). The ones
  -- that exist at install are tracked as cleanup proposals (spec §13); PLAT-06 reports any view added after (M10).
  insert into one.baselines (key, value)
  select 'security_definer_views', coalesce(jsonb_agg(v order by v), '[]') from one.security_definer_views() v
  on conflict (key) do nothing;
  if found then v_captured := v_captured || 'security_definer_views'::text; end if;
  return jsonb_build_object('captured', to_jsonb(v_captured));
end $$;

-- Nightly (cron one-nightly, 02:30 IST): privilege audit, baselines, retention, proposal expiry, test purge status, brief task.
create or replace function one.nightly() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_run bigint;
  v_day date := (now() at time zone 'Asia/Kolkata')::date;
  v_report jsonb := jsonb_build_object('at', now());
begin
  perform one.heartbeat('one:nightly', true, jsonb_build_object('at', now()), null, 90000);
  insert into one.runs (kind, bucket) values ('nightly', v_day::timestamptz) on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    return v_report || jsonb_build_object('skipped', 'already ran today');
  end if;
  begin v_report := v_report || jsonb_build_object('privileges', one.privilege_audit());
  exception when others then v_report := v_report || jsonb_build_object('privileges_error', sqlerrm); end;
  begin v_report := v_report || jsonb_build_object('baselines', one.capture_baselines());
  exception when others then v_report := v_report || jsonb_build_object('baselines_error', sqlerrm); end;
  begin v_report := v_report || jsonb_build_object('retention', one.retention());
  exception when others then v_report := v_report || jsonb_build_object('retention_error', sqlerrm); end;
  begin
    -- A snooze ends: the proposal is back in the queue with a fresh expiry (the builder's never expire). Before the
    -- expiry step, so the snooze end it kept in expires_at does not expire it at once (phase review M2).
    update one.proposals
       set status = 'open',
           expires_at = case when source = 'builder' then null
                             else now() + make_interval(days => coalesce((one.setting('proposals') ->> 'expire_days')::int, 14)) end
     where status = 'snoozed' and expires_at <= now();
    update one.proposals set status = 'expired' where status = 'open' and expires_at < now();
    v_report := v_report || jsonb_build_object('proposals_expired', true);
  exception when others then v_report := v_report || jsonb_build_object('proposals_error', sqlerrm); end;
  begin v_report := v_report || jsonb_build_object('test_purge', one.purge_test_rows());
  exception when others then v_report := v_report || jsonb_build_object('test_purge_error', sqlerrm); end;
  begin
    perform one.enqueue_ai('brief', jsonb_build_object('for_date', v_day), null, format('brief:%s', v_day));
    v_report := v_report || jsonb_build_object('brief', 'queued');
  exception when others then v_report := v_report || jsonb_build_object('brief_error', sqlerrm); end;
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  return v_report;
end $$;

-- Eduwit One's own health (spec §5): tick age, open P1s, queue depths. Read by /api/health and the watchdog.
create or replace function one.health() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'tick_age_s', (select round(extract(epoch from now() - last_ok_at)) from one.heartbeats where component = 'one:tick'),
    'tick_finished_age_s', (select round(extract(epoch from now() - max(finished_at))) from one.runs where kind = 'tick'),
    'open_p1', (select count(*) from one.incidents where resolved_at is null and severity = 'P1'),
    'open_total', (select count(*) from one.incidents where resolved_at is null),
    'ai_pending', (select count(*) from one.ai_tasks where status = 'pending'),
    'deliveries_pending', (select count(*) from one.deliveries where status in ('pending', 'failed')),
    'last_nightly', (select max(started_at) from one.runs where kind = 'nightly'))
$$;

-- The verdict of a heartbeat check (spec §6 HB-*): fresh within expected_interval_s × heartbeat_multiple is ok; read
-- but stale, or read and never once ok, is down (D-050). A component never written is ok only while nothing expects
-- it yet: one:app is expected once app.base_url is set, the app's probes once the app has answered a tick; after
-- heartbeat_never_seen_grace_min of that it is down too, so a prober that never runs cannot hide (M2, D-056).
create or replace function one.heartbeat_state(p_component text) returns jsonb
language sql stable set search_path = '' as $$
  with h as (select * from one.heartbeats where component = p_component),
  v as (
    select not exists (select 1 from h) as never_seen,
           (select last_ok_at from h) as last_ok_at, (select last_error_at from h) as last_error_at,
           (select last_error from h) as last_error, (select expected_interval_s from h) as expected_interval_s,
           case when p_component = 'one:app'
                  then (select s.updated_at from one.settings s where s.key = 'app' and nullif(s.value ->> 'base_url', '') is not null)
                when p_component like 'one:%' then null
                else (select a.created_at from one.heartbeats a where a.component = 'one:app' and a.last_ok_at is not null) end as expected_since,
           coalesce(one.threshold('heartbeat_multiple'), 3) as multiple,
           coalesce(one.threshold('heartbeat_never_seen_grace_min'), 15) as grace)
  select jsonb_build_object(
    'ok', case when never_seen then expected_since is null or expected_since > now() - make_interval(mins => grace::int)
               else coalesce(last_ok_at > now() - make_interval(secs => (expected_interval_s * multiple)::int), false) end,
    'component', p_component, 'last_ok_at', last_ok_at, 'last_error_at', last_error_at, 'last_error', left(last_error, 300),
    'never_seen', never_seen, 'expected_since', expected_since)
  from v
$$;

-- Views in a schema the API exposes (anon has USAGE) that anon or authenticated can read and that run with their
-- owner's rights (no security_invoker): the Supabase lint security_definer_view, level ERROR (M10).
create or replace function one.security_definer_views() returns setof text
language sql stable set search_path = '' as $$
  select c.oid::regclass::text
    from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where c.relkind = 'v'
     and n.nspname not in ('pg_catalog', 'information_schema', 'graphql', 'graphql_public', 'extensions', 'auth', 'storage',
                           'realtime', 'net', 'cron', 'vault', 'pgsodium', 'supabase_functions', 'supabase_migrations', 'pgbouncer', 'pgmq', 'one')
     and pg_catalog.has_schema_privilege('anon', n.oid, 'USAGE')
     and not coalesce(c.reloptions::text[] && array['security_invoker=true', 'security_invoker=on', 'security_invoker=1'], false)
     and (pg_catalog.has_table_privilege('anon', c.oid, 'SELECT') or pg_catalog.has_table_privilege('authenticated', c.oid, 'SELECT'))
   order by 1
$$;

-- Roles other than the owners that could create objects in schema public. WITTY-01 runs with search_path public
-- (D-042), which is safe only while this is empty; PLAT-06 reports any role it returns.
create or replace function one.public_schema_writers() returns setof text
language sql stable set search_path = '' as $$
  select r from unnest(array['public', 'anon', 'authenticated', 'service_role', 'authenticator', 'eduwit_one_reader', 'eduwit_one_fixer']) r
   where case when r = 'public' or exists (select 1 from pg_catalog.pg_roles x where x.rolname = r)
              then pg_catalog.has_schema_privilege(r, 'public', 'CREATE') else false end
$$;

-- The portal's health without granting anything on schema inf (D-020). Where the portal is absent (staging) the
-- error propagates, so one.run_check() records source_missing rather than a failure.
create or replace function one.inf_health() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  return inf.health();
end $$;

insert into one.api_grants (fn, role, why) values
  ('one.health()', 'eduwit_one_reader', 'Eduwit One health'),
  ('one.inf_health()', 'eduwit_one_reader', 'the portal health without schema inf')
on conflict do nothing;
call one.apply_grants();
