-- Rollback of 0041: the apps' server-error counts leave schema one. Removes the table with its rows, the writer and
-- the page's reader with their grants, restores 0029's one.retention() verbatim, puts the thresholds setting back to
-- the version before 0041's seed when that seed is still the latest (a later edit by a person stays, with the unused
-- key app_errors_15m in it), and removes the five checks with their state and results. Their incidents are history
-- that spec §13 keeps forever: while any exists, this rollback refuses, unless the session sets
-- one.rollback_discards_history = on (as 0029's rollback; the local test and the staging rehearsal do).
-- The apps need no change first: a report to a function that is gone fails quietly on their side and is dropped.
-- After this rollback, apply 0006_seed_checks.sql only from a tree that no longer carries the five checks.

do $$
begin
  if coalesce(current_setting('one.rollback_discards_history', true), '') <> 'on'
     and exists (select 1 from one.incidents where check_id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR')) then
    raise exception '0041 rollback refused: schema one holds incidents of the server-error checks, which are kept forever. Export them, then run this rollback with one.rollback_discards_history = on'
      using errcode = '55000';
  end if;
end $$;

delete from one.api_grants where (fn, role) in (('one.app_error_report(text,jsonb)', 'service_role'), ('one.ui_app_errors(text,integer)', 'authenticated'));

-- 0029's one.retention, verbatim.
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
  -- Two tiers: ok results repeat the value before them and are kept ok_results_days (2 since 0029; 14 before); failures
  -- and errors stay results_days (14 since 0029; 90 before) for the incident pages and the comparisons (efficiency
  -- review 10; D-103: the Free plan's 500 MB database limit).
  delete from one.results where status = 'ok' and ran_at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'ok_results_days')::int, 2)));
  get diagnostics v_ok = row_count;
  delete from one.results where ran_at < now() - make_interval(days => coalesce((v_cfg ->> 'results_days')::int, 14));
  get diagnostics v_results = row_count;
  -- The app's minute-by-minute report rows (one per tick) are kept app_report_days (7; 30 before 0029); a person's
  -- audit rows are kept for good.
  delete from one.audit where action = 'app_report' and at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'app_report_days')::int, 7)));
  get diagnostics v_audit = row_count;
  delete from one.email_codes where created_at < now() - interval '7 days';
  delete from one.sign_in_log where at < now() - interval '365 days';
  delete from one.events where occurred_at < now() - make_interval(days => coalesce((v_cfg ->> 'events_days')::int, 30));
  get diagnostics v_events = row_count;
  delete from one.ai_calls where created_at < now() - make_interval(days => coalesce((v_cfg ->> 'ai_calls_days')::int, 365));
  get diagnostics v_calls = row_count;
  -- The tick and nightly reports are kept runs_days (7; 30 before 0029): the checks read 26 hours of them at most.
  delete from one.runs where started_at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'runs_days')::int, 7)));
  -- Conversations with the command centre (0021) and their actions go with their thread.
  delete from one.chat_threads where updated_at < now() - make_interval(days => coalesce((v_cfg ->> 'chat_days')::int, 90));
  get diagnostics v_chat = row_count;
  perform set_config('one.history_writer', 'off', true);
  return jsonb_build_object('results', v_results + v_ok, 'ok_results', v_ok, 'events', v_events, 'ai_calls', v_calls, 'audit', v_audit, 'chat_threads', v_chat);
end $$;

do $$
declare
  v_row one.settings;
  v_prev one.settings_versions;
begin
  select * into v_row from one.settings where key = 'thresholds';
  if found and v_row.actor = 'seed'
     and exists (select 1 from one.settings_versions where key = 'thresholds' and version = v_row.version and reason like 'D-141 (0041)%') then
    select * into v_prev from one.settings_versions where key = 'thresholds' and version = v_row.version - 1;
    if found then
      perform one.settings_put('thresholds', v_prev.value, 'seed', 'rollback of 0041: the version before D-141');
    end if;
  end if;
end $$;

select set_config('one.history_writer', 'on', true);
delete from one.deliveries where incident_id in (select id from one.incidents where check_id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR'));
update one.ai_tasks set incident_id = null, status = case when status in ('pending', 'claimed', 'deferred') then 'cancelled' else status end
 where incident_id in (select id from one.incidents where check_id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR'));
delete from one.actions where incident_id in (select id from one.incidents where check_id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR'));
delete from one.proposals where incident_id in (select id from one.incidents where check_id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR'));
delete from one.incidents where check_id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR');
delete from one.results where check_id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR');
delete from one.check_state where check_id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR');
delete from one.checks where id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR');
select set_config('one.history_writer', 'off', true);

drop function if exists one.ui_app_errors(text, integer);
drop function if exists one.app_error_report(text, jsonb);
drop function if exists one.app_error_text(text, integer);
drop table if exists one.app_errors;

call one.apply_grants();
