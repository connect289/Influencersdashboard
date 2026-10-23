-- 0003 (runner) check evaluation, the minute tick, the nightly run, the privilege audit, health (spec §5, §6).
-- one.tick() and one.nightly() follow b2c.minute_tick: every step in its own exception block, a JSON report with
-- <step>_error keys, and they never raise.

-- Records a result, moves the counters, and opens, touches or resolves the check's incident. Single writer of
-- one.results, one.check_state and the check-driven part of one.incidents.
create or replace function one.evaluate(p_check_id text, p_status text, p_value jsonb, p_error text, p_duration_ms integer) returns text
language plpgsql set search_path = '' as $$
declare
  v_check one.checks;
  v_state one.check_state;
  v_open bigint;
  v_severity one.severity;
begin
  select * into strict v_check from one.checks where id = p_check_id;
  insert into one.results (check_id, status, value, error, duration_ms) values (p_check_id, p_status, p_value, left(p_error, 1000), p_duration_ms);
  insert into one.check_state (check_id) values (p_check_id) on conflict do nothing;
  update one.check_state set
    last_ran_at = now(), last_status = p_status,
    consecutive_fail = case p_status when 'fail' then consecutive_fail + 1 when 'ok' then 0 else consecutive_fail end,
    consecutive_ok = case p_status when 'ok' then consecutive_ok + 1 when 'fail' then 0 else consecutive_ok end
   where check_id = p_check_id
   returning * into v_state;
  select id into v_open from one.incidents where check_id = p_check_id and resolved_at is null;
  if p_status = 'fail' and v_state.consecutive_fail >= v_check.open_after then
    v_severity := coalesce(nullif(p_value ->> 'severity', '')::one.severity, v_check.severity);
    perform one.open_or_touch_incident(p_check_id, v_severity, jsonb_build_object('value', p_value, 'at', now()));
    return case when v_open is null then 'opened' else 'touched' end;
  end if;
  if p_status = 'ok' and v_open is not null and v_state.consecutive_ok >= v_check.resolve_after then
    perform one.resolve_incident(v_open, 'one', 'recovered');
    return 'resolved';
  end if;
  return 'none';
end $$;

-- Runs one SQL check. Its sql is written only by migrations (column grants in 0002); it returns one row
-- (ok boolean, value jsonb). A missing table or function is "source_missing", never a failure (D-009).
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
  v_timeout text := current_setting('statement_timeout');
begin
  select * into strict v_check from one.checks where id = p_check_id;
  if not v_check.enabled or v_check.sql is null then
    return jsonb_build_object('check', p_check_id, 'status', 'skipped', 'reason', coalesce(v_check.disabled_reason, 'no sql'));
  end if;
  begin
    perform set_config('statement_timeout', '10s', true);
    execute format('select count(*)::int, bool_and(ok), (array_agg(value))[1] from (%s) q', v_check.sql)
      into v_rows, v_ok, v_value;
    perform set_config('statement_timeout', v_timeout, true);
    v_status := case when v_rows <> 1 then 'error' when v_ok then 'ok' else 'fail' end;
    v_error := case when v_rows <> 1 then format('check returned %s rows, expected 1', v_rows) end;
  exception
    when undefined_table or undefined_function or undefined_column or invalid_schema_name then
      perform set_config('statement_timeout', v_timeout, true);
      v_status := 'source_missing';
      v_error := sqlerrm;
    when others then
      perform set_config('statement_timeout', v_timeout, true);
      v_status := 'error';
      v_error := sqlerrm;
  end;
  return jsonb_build_object('check', p_check_id, 'status', v_status,
    'incident', one.evaluate(p_check_id, v_status, v_value, v_error, (extract(epoch from clock_timestamp() - v_started) * 1000)::int));
end $$;

-- For checks the app runs (HTTP probes, synthetic tests): the app reports, the database decides.
create or replace function one.report_result(p_check_id text, p_status text, p_value jsonb, p_error text, p_duration_ms integer) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from one.checks where id = p_check_id and enabled and kind in ('http', 'test', 'heartbeat', 'rpc')) then
    raise exception 'one.report_result: % is not an enabled app-run check', p_check_id using errcode = '22023';
  end if;
  return one.evaluate(p_check_id, p_status, p_value, p_error, p_duration_ms);
end $$;

-- All due SQL checks, each isolated so one broken check cannot stop the rest.
create or replace function one.run_sql_checks() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_id text;
  v_out jsonb;
  v_counts jsonb := '{}';
  v_errors jsonb := '{}';
begin
  for v_id in
    select c.id from one.checks c left join one.check_state s on s.check_id = c.id
     where c.enabled and c.sql is not null
       and (s.last_ran_at is null or s.last_ran_at <= now() - make_interval(secs => c.cadence_s - 5))
     order by c.id
  loop
    begin
      v_out := one.run_check(v_id);
      v_counts := v_counts || jsonb_build_object(v_out ->> 'status', coalesce((v_counts ->> (v_out ->> 'status'))::int, 0) + 1);
    exception when others then
      v_errors := v_errors || jsonb_build_object(v_id, sqlerrm);
    end;
  end loop;
  return v_counts || case when v_errors = '{}' then '{}' else jsonb_build_object('check_errors', v_errors) end;
end $$;

-- The minute tick (cron one-tick). Heartbeat first, so the watchdog sees life even if a later step fails; then the
-- run row, whose unique minute bucket makes repeated calls within a minute do nothing (spec §16.5).
create or replace function one.tick() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_run bigint;
  v_report jsonb := jsonb_build_object('at', now());
begin
  perform one.heartbeat('one:tick', true, jsonb_build_object('at', now()), null, 60);
  insert into one.runs (kind, bucket) values ('tick', date_trunc('minute', now()))
  on conflict (kind, bucket) do nothing returning id into v_run;
  if v_run is null then
    return v_report || jsonb_build_object('skipped', 'already ran this minute');
  end if;
  begin
    v_report := v_report || jsonb_build_object('checks', one.run_sql_checks());
  exception when others then v_report := v_report || jsonb_build_object('checks_error', sqlerrm);
  end;
  begin
    v_report := v_report || jsonb_build_object('events', one.events_refresh());
  exception when others then v_report := v_report || jsonb_build_object('events_error', sqlerrm);
  end;
  begin
    v_report := v_report || jsonb_build_object('app', coalesce(one.job_call('/api/internal/tick')::text, 'not_configured'));
  exception when others then v_report := v_report || jsonb_build_object('app_error', sqlerrm);
  end;
  update one.runs set finished_at = now(), report = v_report where id = v_run;
  return v_report;
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
  on conflict (fn) do update set roles = excluded.roles, last_seen = now();
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
    'open_p1', (select count(*) from one.incidents where resolved_at is null and severity = 'P1'),
    'open_total', (select count(*) from one.incidents where resolved_at is null),
    'ai_pending', (select count(*) from one.ai_tasks where status = 'pending'),
    'deliveries_pending', (select count(*) from one.deliveries where status in ('pending', 'failed')),
    'last_nightly', (select max(started_at) from one.runs where kind = 'nightly'))
$$;

-- The portal's health without granting anything on schema inf (D-020). Where the portal is absent (staging) the
-- error propagates, so one.run_check() records source_missing rather than a failure.
create or replace function one.inf_health() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  return inf.health();
end $$;

call one.apply_grants();
grant execute on function one.health(), one.inf_health() to eduwit_one_reader, service_role;
grant execute on function one.run_check(text), one.report_result(text, text, jsonb, text, integer) to service_role;
