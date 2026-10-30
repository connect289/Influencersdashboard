-- Rollback of 0029 storage within the plan: restores 0021's one.retention() verbatim, puts the retention and thresholds
-- settings back to the versions before 0029's seeds when those seeds are still the latest (a later edit by a person
-- stays), and removes PLAT-10 with its state and results. PLAT-10's incidents are history that spec §13 keeps forever:
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
