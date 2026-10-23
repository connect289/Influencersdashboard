-- 0014 the synthetic test runner's side of the database (spec §10, phase 5). The app runs the journeys (web/lib/tests);
-- schema one keeps the catalogue, each run's steps, timings and artefacts, a lease so two overlapping invocations
-- never drive the same run, and reports each finished run to the test's own check, so a failing test opens an
-- incident through the same lifecycle as every other check (open after 1 failure, resolve after the next pass).

alter table one.tests
  add column needs text[] not null default '{}',
  add column seam text,
  add column description text;

alter table one.test_runs
  add column trigger text not null default 'schedule' check (trigger in ('schedule', 'manual')),
  add column requested_by text,
  add column state jsonb not null default '{}',
  add column error text,
  add column holder text,
  add column lease_until timestamptz,
  add column purge_report jsonb;
-- One run in flight per test.
create unique index test_runs_one_inflight on one.test_runs (test_id) where finished_at is null;

-- What a run may record (artefacts keep ids and test identities for the purge, never a contact); steps are shown on
-- the Tests page, so their free text is redacted on the way in.
create or replace function one.test_steps_clean(p_steps jsonb) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce((select jsonb_agg(jsonb_build_object(
            'key', left(s ->> 'key', 60), 'title', left(s ->> 'title', 120), 'ok', (s ->> 'ok')::boolean,
            'ms', greatest(0, least(coalesce((s ->> 'ms')::numeric, 0), 86400000))::bigint,
            'detail', one.redact(to_jsonb(left(s ->> 'detail', 300)), one.pii_keys()) #>> '{}', 'at', s ->> 'at') order by o)
     from jsonb_array_elements(case when jsonb_typeof(p_steps) = 'array' then p_steps else '[]' end) with ordinality a(s, o)
    where o <= 50), '[]')
$$;

-- A run as the runner reads it.
create or replace function one.test_run_json(p one.test_runs) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'testId', p.test_id, 'startedAt', p.started_at, 'steps', p.step_results,
                            'artefacts', p.artefacts,
                            'state', coalesce(nullif(p.state, '{}'), jsonb_build_object('step', 0, 'stepStartedAt', p.started_at, 'acted', false)))
$$;

-- The catalogue, the test identities, and the in-flight runs this holder now leases (theirs had expired). Service role.
create or replace function one.tests_state(p_holder text, p_lease_s integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_runs jsonb;
begin
  perform one.tests_reap();
  with claimed as (
    update one.test_runs r set holder = p_holder, lease_until = now() + make_interval(secs => least(greatest(p_lease_s, 30), 600))
     where r.finished_at is null and (r.lease_until is null or r.lease_until < now())
    returning r.*)
  select coalesce(jsonb_agg(one.test_run_json(c) order by c.started_at), '[]') into v_runs from claimed c;
  return jsonb_build_object(
    'tests', (select coalesce(jsonb_agg(jsonb_build_object(
                'id', t.id, 'enabled', t.enabled, 'schedule', t.schedule, 'timeout_s', t.timeout_s,
                'run_requested_at', t.run_requested_at,
                'last_started_at', (select max(r.started_at) from one.test_runs r where r.test_id = t.id),
                'inflight', exists (select 1 from one.test_runs r where r.test_id = t.id and r.finished_at is null)) order by t.id), '[]')
                from one.tests t),
    'identities', coalesce(one.setting('test_identities'), '{}'),
    'runs', v_runs);
end $$;

-- Starts a run, or returns null: the test is off, a run is in flight, or this slot (p_key) already ran.
create or replace function one.test_run_start(p_test text, p_trigger text, p_key text, p_holder text, p_lease_s integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t one.tests;
  v_run one.test_runs;
begin
  select * into v_t from one.tests where id = p_test for update;
  if not found or not v_t.enabled then
    return null;
  end if;
  if exists (select 1 from one.test_runs where test_id = p_test and finished_at is null) then
    return null;
  end if;
  insert into one.test_runs (test_id, idempotency_key, trigger, requested_by, holder, lease_until, state)
  values (p_test, p_key, p_trigger, case when p_trigger = 'manual' then v_t.run_requested_by end, p_holder,
          now() + make_interval(secs => least(greatest(p_lease_s, 30), 600)),
          jsonb_build_object('step', 0, 'stepStartedAt', now(), 'acted', false))
  on conflict (idempotency_key) do nothing
  returning * into v_run;
  if v_run.id is null then
    return null;
  end if;
  update one.tests set run_requested_at = null, run_requested_by = null where id = p_test and p_trigger = 'manual';
  return one.test_run_json(v_run);
end $$;

-- Saves a run in flight; only its holder can, and the lease is renewed.
create or replace function one.test_run_save(p_run bigint, p_holder text, p_lease_s integer, p_steps jsonb, p_artefacts jsonb, p_state jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update one.test_runs
     set step_results = one.test_steps_clean(p_steps),
         artefacts = case when jsonb_typeof(p_artefacts) = 'object' then p_artefacts else artefacts end,
         state = case when jsonb_typeof(p_state) = 'object' then p_state else state end,
         lease_until = now() + make_interval(secs => least(greatest(p_lease_s, 30), 600))
   where id = p_run and finished_at is null and holder = p_holder;
  if not found then
    raise exception 'run % is not held by this runner', p_run using errcode = '55000';
  end if;
end $$;

-- Finishes a run and reports it to the test's check: a failure opens or touches the incident, a pass counts towards
-- resolving it. The value names the failed step and the run, so the incident links back to its timings.
create or replace function one.test_run_finish(p_run bigint, p_holder text, p_ok boolean, p_error text, p_steps jsonb, p_artefacts jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_run one.test_runs;
  v_failed jsonb;
  v_outcome text;
begin
  update one.test_runs
     set finished_at = now(), ok = coalesce(p_ok, false), error = left(p_error, 300),
         step_results = one.test_steps_clean(p_steps),
         artefacts = case when jsonb_typeof(p_artefacts) = 'object' then p_artefacts else artefacts end,
         holder = null, lease_until = null
   where id = p_run and finished_at is null and holder = p_holder
  returning * into v_run;
  if v_run.id is null then
    raise exception 'run % is not held by this runner', p_run using errcode = '55000';
  end if;
  select s into v_failed from jsonb_array_elements(v_run.step_results) s where (s ->> 'ok')::boolean is false limit 1;
  if exists (select 1 from one.checks where id = v_run.test_id and enabled and kind = 'test') then
    v_outcome := one.report_result(v_run.test_id, case when v_run.ok then 'ok' else 'fail' end,
                                   jsonb_build_object('run', v_run.id, 'failed_step', v_failed ->> 'key', 'detail', v_failed ->> 'detail',
                                                      'steps', jsonb_array_length(v_run.step_results)),
                                   case when v_run.ok then null else v_run.error end,
                                   (extract(epoch from v_run.finished_at - v_run.started_at) * 1000)::int);
  end if;
  return jsonb_build_object('ok', v_run.ok, 'outcome', v_outcome);
end $$;

-- A run whose holder died stays in flight until its lease ends, then the next runner takes it over; a run stuck past
-- its test's timeout plus ten minutes (no runner reached it) is closed as failed here, once a minute, from the tick.
create or replace function one.tests_reap() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_n integer := 0;
  r record;
begin
  for r in select tr.id, tr.test_id from one.test_runs tr join one.tests t on t.id = tr.test_id
            where tr.finished_at is null and tr.started_at < now() - make_interval(secs => t.timeout_s + 600)
              and (tr.lease_until is null or tr.lease_until < now()) loop
    update one.test_runs set holder = 'reaper' where id = r.id;
    perform one.test_run_finish(r.id, 'reaper', false, 'abandoned: no runner reached it before its timeout',
                                (select step_results from one.test_runs where id = r.id) || jsonb_build_array(jsonb_build_object(
                                  'key', 'runner', 'title', 'The runner reached the run', 'ok', false, 'ms', 0,
                                  'detail', 'no runner reached it before its timeout', 'at', now())),
                                null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- The Tests page (spec §10: "its last 30 runs are visible with step timings, so a slow step is seen before it fails"):
-- each test with its steps and their timeouts, what it needs from Setup, and its last 30 runs with their steps.
create or replace function one.ui_tests() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_setup jsonb := coalesce(one.setting('setup') -> 'items', '{}');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'app', t.app, 'title', t.title, 'seam', t.seam, 'description', t.description, 'schedule', t.schedule,
      'severity', t.severity, 'timeout_s', t.timeout_s, 'enabled', t.enabled, 'disabled_reason', t.disabled_reason,
      'steps', jsonb_array_length(t.steps), 'step_defs', t.steps,
      'needs', (select coalesce(jsonb_agg(jsonb_build_object('item', n, 'validated', coalesce((v_setup -> n ->> 'validated')::boolean, false)) order by o), '[]')
                  from unnest(t.needs) with ordinality u(n, o)),
      'run_requested_at', t.run_requested_at,
      'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'started_at', r.started_at, 'finished_at', r.finished_at, 'ok', r.ok,
                                                           'trigger', r.trigger, 'error', r.error, 'purged_at', r.purged_at,
                                                           'duration_ms', round(extract(epoch from r.finished_at - r.started_at) * 1000),
                                                           'steps', r.step_results) order by r.started_at desc), '[]')
                 from (select * from one.test_runs r where r.test_id = t.id order by r.started_at desc limit 30) r)) order by t.id), '[]')
    from one.tests t);
end $$;

-- The catalogue (migration 0015, generated from config/tests.json) -------------------------------------------------------

-- Each test has a check of its own (kind test, the test's id), which the runner reports to and which carries the
-- incident. It follows its test: on when the test is on, off with "builder:follows-its-test" otherwise.
create or replace function one.tests_check_sync() returns trigger
language plpgsql set search_path = '' as $$
begin
  update one.checks
     set enabled = new.enabled, severity = new.severity,
         disabled_reason = case when new.enabled then null else 'builder:follows-its-test' end,
         updated_at = now(), version = version + 1
   where id = new.id and kind = 'test'
     and (enabled, severity, disabled_reason) is distinct from
         (new.enabled, new.severity, case when new.enabled then null else 'builder:follows-its-test' end);
  return new;
end $$;
create trigger tests_check_sync after insert or update of enabled, severity on one.tests
  for each row execute function one.tests_check_sync();

-- A test runs only when every Setup item it needs is validated (spec §15: "its dependent checks, tests and fixes are
-- seeded enabled"). Re-read after every validation: a test waiting for Setup switches on, or waits for the next item;
-- an enabled test whose item lost its validation switches off with that item as the reason. A test someone switched
-- off by hand (owner:...) stays off.
create or replace function one.tests_sync_setup() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_setup jsonb := coalesce(one.setting('setup') -> 'items', '{}');
  v_n integer;
begin
  with m as (
    select t.id, t.enabled, t.disabled_reason,
           (select u.n from unnest(t.needs) with ordinality u(n, o)
             where not coalesce((v_setup -> u.n ->> 'validated')::boolean, false) order by u.o limit 1) as missing
      from one.tests t)
  update one.tests t
     set enabled = m.missing is null,
         disabled_reason = case when m.missing is null then null else 'setup:' || m.missing end,
         updated_by = 'setup'
    from m
   where t.id = m.id
     and ((m.disabled_reason like 'setup:%' and (m.missing is null or m.disabled_reason <> 'setup:' || m.missing))
          or (m.enabled and m.missing is not null));
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- One catalogue entry: the test and its check. A re-run keeps what a person changed (schedule, switch), takes the
-- rest from the catalogue, and leaves the switch to tests_sync_setup().
create or replace function one.seed_test(p jsonb) returns void
language plpgsql set search_path = '' as $$
declare
  v_needs text[] := array(select jsonb_array_elements_text(p -> 'needs'));
begin
  insert into one.tests as t (id, app, title, seam, description, steps, schedule, timeout_s, severity, needs, enabled, disabled_reason, updated_by)
  values (p ->> 'id', p ->> 'app', p ->> 'title', p ->> 'seam', p ->> 'description', p -> 'steps', p ->> 'schedule',
          (p ->> 'timeout_s')::int, (p ->> 'severity')::one.severity, v_needs, false,
          coalesce(p ->> 'disabled', 'setup:' || coalesce(v_needs[1], 'none')), 'seed')
  on conflict (id) do update set
    app = excluded.app, title = excluded.title, seam = excluded.seam, description = excluded.description, steps = excluded.steps,
    timeout_s = excluded.timeout_s, needs = excluded.needs,
    schedule = case when t.updated_by in ('seed', 'setup') then excluded.schedule else t.schedule end,
    severity = case when t.updated_by in ('seed', 'setup') then excluded.severity else t.severity end,
    disabled_reason = case when t.updated_by = 'seed' and not t.enabled then excluded.disabled_reason else t.disabled_reason end;
  perform one.seed_check(jsonb_build_object(
    'id', p ->> 'id', 'app', p ->> 'app', 'title', 'Synthetic test failed: ' || (p ->> 'title'),
    'description', 'The synthetic journey ' || (p ->> 'seam') || ' (docs/TESTS.md). It fails when a step is not seen within its timeout or a safety rule refuses the run.',
    'kind', 'test', 'severity', p ->> 'severity', 'cadence_s', 3600, 'open_after', 1, 'resolve_after', 1,
    'tags', jsonb_build_array('test'), 'enabled', false, 'disabled_reason', 'builder:follows-its-test'));
  update one.checks c set enabled = t.enabled, disabled_reason = case when t.enabled then null else 'builder:follows-its-test' end
    from one.tests t where t.id = p ->> 'id' and c.id = t.id;
end $$;

-- The Setup validation also re-reads which tests can run (0011's version, plus one.tests_sync_setup()).
create or replace function one.setup_validated(p_item text, p_ok boolean, p_detail text, p_actor text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := p_actor;
  v_setup jsonb := coalesce(one.setting('setup'), '{"items": {}}');
  v_on integer := 0;
  v_tests integer;
begin
  if p_ok is null or coalesce(p_actor, '') !~ '^[^@\s]+@[^@\s]+$' then
    raise exception 'a validation needs a result and the person who ran it' using errcode = '22023';
  end if;
  if not exists (select 1 from jsonb_array_elements(coalesce(one.setting('setup_catalog') -> 'items', '[]')) i where i ->> 'id' = p_item) then
    raise exception 'no Setup item %', p_item using errcode = 'P0002';
  end if;
  v_setup := jsonb_set(v_setup, array['items', p_item], coalesce(v_setup -> 'items' -> p_item, '{}') || jsonb_build_object(
    'status', case when p_ok then 'verified' else 'refused' end, 'validated', p_ok, 'validated_at', now(),
    'ran', 'Setup page: validate, by ' || v_actor, 'detail', left(p_detail, 500), 'source', 'app'), true);
  perform one.settings_put('setup', v_setup, v_actor, 'validate ' || p_item);
  if p_ok then
    update one.checks set enabled = true, disabled_reason = null, updated_by = v_actor, updated_at = now(), version = version + 1
     where disabled_reason = 'setup:' || p_item;
    get diagnostics v_on = row_count;
  end if;
  v_tests := one.tests_sync_setup();
  perform one.ui_audit_write(v_actor, 'setup.validate', 'setup:' || p_item, null,
                             jsonb_build_object('ok', p_ok, 'detail', left(p_detail, 500), 'checks_on', v_on, 'tests_changed', v_tests), p_request_id);
  return jsonb_build_object('ok', true, 'checks_on', v_on, 'tests_changed', v_tests);
end $$;


-- Switching a test: on only when every Setup item it needs is validated; off for a P1 test only by the owner.
create or replace function one.ui_test_update(p_id text, p_patch jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_t one.tests;
  v_enabled boolean;
  v_item text;
begin
  select * into v_t from one.tests where id = p_id for update;
  if not found then
    raise exception 'no test %', p_id using errcode = 'P0002';
  end if;
  v_enabled := coalesce((p_patch ->> 'enabled')::boolean, v_t.enabled);
  -- A test runs only on validated identities: every Setup item it needs (spec §10, §15).
  select u.n into v_item from unnest(v_t.needs) with ordinality u(n, o)
   where not coalesce((one.setting('setup') #>> array['items', u.n, 'validated'])::boolean, false) order by u.o limit 1;
  if v_enabled and not v_t.enabled and v_t.disabled_reason like 'blocked:%' then
    raise exception 'test % cannot run: %', p_id, v_t.disabled_reason using errcode = '22023';
  end if;
  if v_enabled and not v_t.enabled and v_item is not null then
    raise exception 'test % waits for Setup item %', p_id, v_item using errcode = '22023';
  end if;
  -- Switching off a P1 test is the owner's, as for a P1 check (D-065).
  if v_t.enabled and not v_enabled and v_t.severity = 'P1' then
    perform one.ui_require('owner');
  end if;
  if p_patch ? 'schedule' and p_patch ->> 'schedule' !~ '^(\S+\s+){4}\S+$' then
    raise exception 'a schedule is a 5-field cron expression' using errcode = '22023';
  end if;
  update one.tests set enabled = v_enabled,
         disabled_reason = case when v_enabled then null when v_t.enabled then 'owner:' || left(v_reason, 60) else disabled_reason end,
         schedule = coalesce(p_patch ->> 'schedule', schedule), updated_by = v_actor
   where id = p_id;
  perform one.ui_audit_write(v_actor, 'test.update', 'test:' || p_id, jsonb_build_object('enabled', v_t.enabled, 'schedule', v_t.schedule),
                             p_patch || jsonb_build_object('reason', v_reason), p_request_id);
  return jsonb_build_object('ok', true);
end $$;


insert into one.api_grants (fn, role, why) values
  ('one.tests_state(text,integer)', 'service_role', 'test runner (0014): the catalogue and the runs it now leases'),
  ('one.test_run_start(text,text,text,text,integer)', 'service_role', 'test runner (0014): start a run'),
  ('one.test_run_save(bigint,text,integer,jsonb,jsonb,jsonb)', 'service_role', 'test runner (0014): save a run in flight'),
  ('one.test_run_finish(bigint,text,boolean,text,jsonb,jsonb)', 'service_role', 'test runner (0014): finish a run and report it')
on conflict do nothing;
call one.apply_grants();
