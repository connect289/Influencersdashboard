-- Rollback of 0029 storage within the plan: restores 0021's one.retention() verbatim, puts the retention and thresholds
-- settings back to the versions before 0029's seeds when those seeds are still the latest (a later edit by a person
-- stays), re-seeds B2C-01 as before, and removes PLAT-10 with its state and results. PLAT-10's incidents are history that spec §13 keeps forever:
-- while any exists, this rollback refuses, unless the session sets one.rollback_discards_history = on (as 0006's
-- rollback; the local test and the staging rehearsal do). The rows 0029's retention pass deleted are not restored.

do $$
begin
  if coalesce(current_setting('one.rollback_discards_history', true), '') <> 'on'
     and exists (select 1 from one.incidents where check_id = 'PLAT-10') then
    raise exception '0029 rollback refused: schema one holds PLAT-10 incidents, which are kept forever. Export them, then run this rollback with one.rollback_discards_history = on'
      using errcode = '55000';
  end if;
end $$;

create or replace function one.retention() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('retention'), '{}');
  v_results integer;
  v_events integer;
  v_calls integer;
  v_ok integer;
  v_audit integer;
  v_chat integer;
begin
  -- The histories are append-only (D-085); this is the one step that may prune them.
  perform set_config('one.history_writer', 'on', true);
  -- Two tiers: ok results repeat the value before them and are kept ok_results_days (14); failures and errors stay
  -- results_days (90) for the incident pages and the comparisons (efficiency review 10).
  delete from one.results where status = 'ok' and ran_at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'ok_results_days')::int, 14)));
  get diagnostics v_ok = row_count;
  delete from one.results where ran_at < now() - make_interval(days => coalesce((v_cfg ->> 'results_days')::int, 90));
  get diagnostics v_results = row_count;
  -- The app's minute-by-minute report rows (one per tick) are kept 30 days; a person's audit rows are kept for good.
  delete from one.audit where action = 'app_report' and at < now() - interval '30 days';
  get diagnostics v_audit = row_count;
  delete from one.email_codes where created_at < now() - interval '7 days';
  delete from one.sign_in_log where at < now() - interval '365 days';
  delete from one.events where occurred_at < now() - make_interval(days => coalesce((v_cfg ->> 'events_days')::int, 180));
  get diagnostics v_events = row_count;
  delete from one.ai_calls where created_at < now() - make_interval(days => coalesce((v_cfg ->> 'ai_calls_days')::int, 365));
  get diagnostics v_calls = row_count;
  delete from one.runs where started_at < now() - interval '30 days';
  -- Conversations with the command centre (0021) and their actions go with their thread.
  delete from one.chat_threads where updated_at < now() - make_interval(days => coalesce((v_cfg ->> 'chat_days')::int, 90));
  get diagnostics v_chat = row_count;
  perform set_config('one.history_writer', 'off', true);
  return jsonb_build_object('results', v_results + v_ok, 'ok_results', v_ok, 'events', v_events, 'ai_calls', v_calls, 'audit', v_audit, 'chat_threads', v_chat);
end $$;

do $$
declare
  v_key text;
  v_row one.settings;
  v_prev one.settings_versions;
begin
  foreach v_key in array array['retention', 'thresholds'] loop
    select * into v_row from one.settings where key = v_key;
    if found and v_row.actor = 'seed'
       and exists (select 1 from one.settings_versions where key = v_key and version = v_row.version and reason like 'D-103 (0029)%') then
      select * into v_prev from one.settings_versions where key = v_key and version = v_row.version - 1;
      if found then
        perform one.settings_put(v_key, v_prev.value, 'seed', 'rollback of 0029: the version before D-103');
      end if;
    end if;
  end loop;
end $$;

-- B2C-01 as 0006 seeded it before 0029 (the per-job lookups).
select one.seed_check(jsonb_build_object(
  'id', 'B2C-01',
  'app', 'b2c',
  'kind', 'sql',
  'severity', 'P1',
  'cadence_s', 60,
  'open_after', 1,
  'resolve_after', 3,
  'title', 'Spark''s timers or its answers to them are failing',
  'description', 'Direct read of system_health''s "timers" and "app" checks: no b2c-* job at all, a b2c-* job whose latest finished run failed (a run in progress is ignored; startup timeouts excluded, see PLAT-01B; b2c-capacity left to B2C-10), or a Spark job call answered with an error status in the last hour. Reads the newest cron_scan_runs runs through the runid key (M3, M7 of the second review).',
  'auto_fix_id', null,
  'tags', '["cron"]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with w as (select coalesce(max(runid), 0) - (select one.threshold('cron_scan_runs'))::bigint as from_runid from cron.job_run_details),
jobs as (
  select j.jobname, (select d.status from cron.job_run_details d, w
                      where d.jobid = j.jobid and d.runid > w.from_runid and d.status in ('succeeded', 'failed')
                        and d.return_message is distinct from 'job startup timeout'
                      order by d.runid desc limit 1) as last_status
    from cron.job j where j.jobname like 'b2c-%' and j.jobname <> 'b2c-capacity' and j.active),
calls as (
  select count(*) as failed from b2c.job_calls c, jsonb_array_elements(c.calls) e join net._http_response r on r.id = (e ->> 'id')::bigint
   where r.created > now() - interval '1 hour' and (r.status_code is null or r.status_code >= 400))
select (select count(*) from jobs) > 0 and not exists (select 1 from jobs where last_status = 'failed') and (select failed from calls) = 0 as ok,
       jsonb_build_object('timers', (select count(*) from jobs),
                          'failed_jobs', (select coalesce(jsonb_agg(jobname order by jobname), '[]') from jobs where last_status = 'failed'),
                          'subjects', (select coalesce(jsonb_agg(jobname order by jobname), '[]') from jobs where last_status = 'failed'),
                          'failed_calls_1h', (select failed from calls)) as value
$sql$));

select set_config('one.history_writer', 'on', true);
delete from one.deliveries where incident_id in (select id from one.incidents where check_id = 'PLAT-10');
update one.ai_tasks set incident_id = null, status = case when status in ('pending', 'claimed', 'deferred') then 'cancelled' else status end
 where incident_id in (select id from one.incidents where check_id = 'PLAT-10');
delete from one.actions where incident_id in (select id from one.incidents where check_id = 'PLAT-10');
delete from one.proposals where incident_id in (select id from one.incidents where check_id = 'PLAT-10');
delete from one.incidents where check_id = 'PLAT-10';
delete from one.results where check_id = 'PLAT-10';
delete from one.check_state where check_id = 'PLAT-10';
delete from one.checks where id = 'PLAT-10';
select set_config('one.history_writer', 'off', true);

call one.apply_grants();
