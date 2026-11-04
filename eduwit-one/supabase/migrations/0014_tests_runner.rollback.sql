-- Rollback of 0014: the runner functions, the added columns, and the Tests page read as 0010 wrote it. Runs and
-- their history stay (spec §13 keeps history); only what 0014 added goes.

delete from one.api_grants where why like 'test runner (0014):%';
drop function if exists one.test_run_finish(bigint, text, boolean, text, jsonb, jsonb);
drop function if exists one.test_run_save(bigint, text, integer, jsonb, jsonb, jsonb);
drop function if exists one.test_run_start(text, text, text, text, integer);
drop function if exists one.tests_state(text, integer);
drop function if exists one.tests_reap();
drop function if exists one.test_run_json(one.test_runs);
drop function if exists one.test_steps_clean(jsonb);
drop trigger if exists tests_check_sync on one.tests;
drop function if exists one.tests_check_sync();
drop function if exists one.seed_test(jsonb);
drop index if exists one.test_runs_one_inflight;
alter table one.test_runs drop column if exists purge_next_at;
alter table one.test_runs drop column if exists purge_attempts;
alter table one.test_runs drop column if exists purge_report;
alter table one.test_runs drop column if exists lease_until;
alter table one.test_runs drop column if exists holder;
alter table one.test_runs drop column if exists error;
alter table one.test_runs drop column if exists state;
alter table one.test_runs drop column if exists requested_by;
alter table one.test_runs drop column if exists trigger;
alter table one.tests drop column if exists description;
alter table one.tests drop column if exists seam;
alter table one.tests drop column if exists needs;

create or replace function one.ui_tests() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'app', t.app, 'title', t.title, 'schedule', t.schedule, 'severity', t.severity, 'timeout_s', t.timeout_s,
      'enabled', t.enabled, 'disabled_reason', t.disabled_reason, 'steps', jsonb_array_length(t.steps),
      'run_requested_at', t.run_requested_at,
      'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'started_at', r.started_at, 'finished_at', r.finished_at, 'ok', r.ok,
                                                           'duration_ms', round(extract(epoch from r.finished_at - r.started_at) * 1000),
                                                           'steps', r.step_results) order by r.started_at desc), '[]')
                 from (select * from one.test_runs r where r.test_id = t.id order by r.started_at desc limit 30) r)) order by t.id), '[]')
    from one.tests t);
end $$;

create or replace function one.setup_validated(p_item text, p_ok boolean, p_detail text, p_actor text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := p_actor;
  v_setup jsonb := coalesce(one.setting('setup'), '{"items": {}}');
  v_on integer := 0;
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
  perform one.ui_audit_write(v_actor, 'setup.validate', 'setup:' || p_item, null,
                             jsonb_build_object('ok', p_ok, 'detail', left(p_detail, 500), 'checks_on', v_on), p_request_id);
  return jsonb_build_object('ok', true, 'checks_on', v_on);
end $$;


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
  v_item := substring(v_t.disabled_reason from '^setup:(.*)$');
  if v_enabled and not v_t.enabled and v_item is not null
     and not coalesce((one.setting('setup') #>> array['items', v_item, 'validated'])::boolean, false) then
    raise exception 'test % waits for Setup item %', p_id, v_item using errcode = '22023';
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


-- tests_sync_setup() goes last: 0011's setup_validated no longer calls it.
drop function if exists one.tests_sync_setup();

call one.apply_grants();
