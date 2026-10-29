-- Rollback of 0021 the command centre: drops the chat tables and functions, restores 0018's one.ai_tool and one.ai_claim and
-- 0020's one.retention verbatim, removes the 'chat' task kind with its tasks and their call rows, and takes the chat's
-- settings keys back. Audit rows stay (append-only). Conversations are lost with their tables: this rollback is for a
-- rehearsal or a withdrawn deploy, not for a database people have been chatting on.

drop function if exists one.ui_chat_thread_archive(bigint, text);
drop function if exists one.ui_chat_action_result(bigint, boolean, jsonb, text);
drop function if exists one.ui_chat_action_decide(bigint, text, text);
drop function if exists one.ui_chat_action_propose(bigint, text, text, jsonb, text, text);
drop function if exists one.ui_chat_turn_finish(bigint, text, jsonb, text, text);
drop function if exists one.ui_chat_turn_start(bigint, text, text, text);
drop function if exists one.ui_chat_thread(bigint);
drop function if exists one.ui_chat_threads(integer);
drop function if exists one.chat_snapshot();
drop function if exists one.chat_append(bigint, text, jsonb, bigint);
drop function if exists one.chat_own_thread(bigint);
drop table if exists one.chat_actions;
drop table if exists one.chat_messages;
drop table if exists one.chat_threads;
delete from one.api_grants where why = 'the command centre chat (0021)';

delete from one.ai_calls where task_id in (select id from one.ai_tasks where kind = 'chat');
delete from one.ai_tasks where kind = 'chat';
alter table one.ai_tasks drop constraint ai_tasks_kind_check;
alter table one.ai_tasks add constraint ai_tasks_kind_check
  check (kind in ('classify', 'triage', 'explain', 'brief', 'propose_fix', 'propose_feature', 'ask', 'test_author'));

do $$
declare
  v one.settings;
begin
  select * into v from one.settings where key = 'ai';
  if found and (coalesce(v.value -> 'routing', '{}'::jsonb) ? 'chat') then
    perform one.settings_put('ai', v.value #- '{routing,chat}', v.actor, '0021 rollback: the chat tier is removed');
  end if;
  select * into v from one.settings where key = 'retention';
  if found and (v.value ? 'chat_days') then
    perform one.settings_put('retention', v.value - 'chat_days', v.actor, '0021 rollback: chat_days is removed');
  end if;
end $$;

-- 0018's one.ai_tool, verbatim.
create or replace function one.ai_tool(p_task bigint, p_holder text, p_name text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_started timestamptz := clock_timestamp();
  v jsonb;
begin
  if not exists (select 1 from one.ai_tasks where id = p_task and status = 'claimed' and claimed_by = p_holder and kind = 'ask') then
    raise exception 'task % is not a question held by this worker', p_task using errcode = '42501';
  end if;
  perform set_config('transaction_read_only', 'on', true);
  begin
    perform set_config('lock_timeout', '2s', true);
    v := jsonb_build_object('ok', true, 'data', one.ai_tool_data(p_name, p_args));
  exception
    when sqlstate '22023' or sqlstate 'P0002' or invalid_text_representation or numeric_value_out_of_range then
      v := jsonb_build_object('ok', false, 'error', left(sqlerrm, 200));
    when undefined_table or undefined_function or undefined_column or invalid_schema_name then
      v := jsonb_build_object('ok', false, 'error', 'not available on this database');
    when insufficient_privilege then
      v := jsonb_build_object('ok', false, 'error', 'needs a person''s own access in the app');
    when lock_not_available or query_canceled then
      v := jsonb_build_object('ok', false, 'error', 'the read took too long; try a smaller range');
    when others then
      v := jsonb_build_object('ok', false, 'error', left(sqlerrm, 200));
  end;
  perform set_config('search_path', '', true);
  return v || jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_started) * 1000));
end $$;

-- 0018's one.ai_claim, verbatim.
create or replace function one.ai_claim(p_holder text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ai jsonb := coalesce(one.setting('ai'), '{}');
  v_cap numeric := coalesce((one.setting('ai') ->> 'daily_cap_inr')::numeric, 0);
  v_pct numeric := coalesce((one.setting('ai') ->> 'queue_non_triage_at_pct')::numeric, 80);
  v_all text[] := array['classify', 'triage', 'explain', 'brief', 'propose_fix', 'propose_feature', 'ask', 'test_author'];
  v_spent numeric;
  v_allowed text[];
  v_task one.ai_tasks;
  v_context jsonb;
begin
  if coalesce(p_holder, '') !~ '^[a-z0-9:._-]{3,80}$' then
    raise exception 'one.ai_claim: bad holder' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('one.ai_claim'));
  update one.ai_tasks set status = 'cancelled', error = 'older than ai.task_max_age_h', claimed_by = null
   where status in ('pending', 'deferred') and created_at < now() - make_interval(hours => coalesce((v_ai ->> 'task_max_age_h')::int, 48));
  update one.ai_tasks t set status = 'cancelled', error = 'a synthetic test incident is not analysed'
    from one.incidents i
   where t.incident_id = i.id and t.status in ('pending', 'deferred') and (i.check_id = 'ONE-SYNTH' or 'synthetic' = any (i.tags));
  update one.ai_tasks set status = case when attempts >= 3 then 'failed' else 'pending' end,
                          error = 'the worker stopped during this task', claimed_by = null
   where status = 'claimed' and claimed_at < now() - interval '10 minutes';
  if (select count(*) from one.ai_tasks where status = 'claimed') >= coalesce((v_ai ->> 'max_parallel')::int, 2) then
    return null;
  end if;
  v_spent := one.ai_spent_today();
  v_allowed := case when v_cap <= 0 or v_spent >= v_cap then '{}'::text[]
                    when v_spent >= v_cap * v_pct / 100 then array['classify', 'triage']
                    else v_all end;
  -- The reason is also the task's error, which the incident and Ask pages show.
  update one.ai_tasks
     set status = 'deferred', not_before = now() + interval '15 minutes',
         deferred_reason = case when cardinality(v_allowed) = 0
                                then format('budget (cap reached): today''s AI spend ₹%s has reached the cap ₹%s', round(v_spent, 2), v_cap)
                                else format('budget (over %s%%): today''s AI spend ₹%s is %s%% of the cap ₹%s, so only classify and triage run', v_pct,
                                            round(v_spent, 2), round(v_spent / v_cap * 100), v_cap) end
   where (status = 'pending' or (status = 'deferred' and coalesce(not_before, '-infinity') <= now()))
     and not (kind = any (v_allowed));
  update one.ai_tasks set error = deferred_reason where status = 'deferred' and deferred_reason like 'budget (%' and error is distinct from deferred_reason;
  for i in 1..5 loop
    select * into v_task from one.ai_tasks
     where (status = 'pending' or (status = 'deferred' and coalesce(not_before, '-infinity') <= now()))
       and kind = any (v_allowed)
     order by one.ai_priority(kind), id
     limit 1 for update skip locked;
    if not found then
      return null;
    end if;
    begin
      v_context := one.ai_context(v_task);
    exception
      -- OTHERS does not catch a cancelled statement: a statement timeout while one context is built must fail that
      -- task, or it would come first again every minute (review M3).
      when query_canceled then
        update one.ai_tasks set status = 'failed', error = 'building the data for this task took too long' where id = v_task.id;
        continue;
      when others then
        update one.ai_tasks set status = 'failed', error = left('could not build the data for this task: ' || sqlerrm, 300) where id = v_task.id;
        continue;
    end;
    update one.ai_tasks
       set status = 'claimed', claimed_by = p_holder, claimed_at = now(), attempts = attempts + 1, deferred_reason = null, not_before = null,
           -- A brief keeps the numbers it was written from (they become the brief's stats).
           input = case when kind = 'brief' then input || jsonb_build_object('stats', v_context -> 'stats') else input end
     where id = v_task.id returning * into v_task;
    return jsonb_build_object(
      'task', jsonb_build_object('id', v_task.id, 'kind', v_task.kind, 'input', v_task.input - 'stats', 'model_hint', v_task.model_hint,
                                 'attempts', v_task.attempts, 'incident_id', v_task.incident_id),
      'ai', v_ai,
      -- task_spent_inr: what earlier attempts of this task spent, so per_task_cap_inr holds across attempts (review M6).
      'budget', jsonb_build_object('spent_inr', v_spent, 'cap_inr', v_cap, 'remaining_inr', greatest(v_cap - v_spent, 0),
                                   'task_spent_inr', (select coalesce(sum(cost_inr), 0) from one.ai_calls where task_id = v_task.id)),
      'context', v_context);
  end loop;
  return null;
end $$;

-- 0020's one.retention, verbatim.
create or replace function one.retention() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('retention'), '{}');
  v_results integer;
  v_events integer;
  v_calls integer;
  v_ok integer;
  v_audit integer;
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
  perform set_config('one.history_writer', 'off', true);
  return jsonb_build_object('results', v_results + v_ok, 'ok_results', v_ok, 'events', v_events, 'ai_calls', v_calls, 'audit', v_audit);
end $$;

call one.apply_grants();
