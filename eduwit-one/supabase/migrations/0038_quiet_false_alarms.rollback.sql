-- Rollback of 0038: ONE-01 and the two WhatsApp heartbeat checks as they were before it, the bulk acknowledgement gone
-- (what was acknowledged with it stays acknowledged, with its audit rows), and the harness scenario back to the old
-- default where it holds the new one. (The app's own scenario stays in the app's code; with the old setting it is not
-- sent.)

with before (id, description, sql) as (values
  ('ONE-01', $d$More than fix_failed_acts_max fix acts that failed, or more than ai_failed_tasks_max AI tasks that failed, in 24 h (hardening F16). A tick report in the last 10 min with an _error key (a killed check or event copy included); a tick that started 2 to 15 min ago and never finished its alert step and app call; an event source in error, killed or missing (where missing counts, D-042; m13 of the second review); a check slower than checks.slow_ms in the last 10 min (a statement timeout cannot be armed per check, D-044); more than ai_queue_max AI tasks pending or held past their 10-minute lease; a failed delivery in the last 24 h; AI spend today (one.ai_calls.cost_inr, IST) at or above one.settings.ai.daily_cap_inr, or AI work held back because the day's cap is reached or the Anthropic API credits are used up (spec §11: ONE-01 fires at 100%; phase 6 review M1; D-078). A cap of 0 means the owner switched the AI off and raises nothing. A check parked after three killed runs in a row (it tries again every checks.parked_retry_h hours until a run finishes, D-102).$d$, $q$with v as (
  select (select count(*) from one.runs where kind = 'tick' and started_at > now() - interval '10 minutes' and report::text ~ '_error"') as tick_errors_10m,
         (select count(*) from one.runs where kind = 'tick' and finished_at is null
             and started_at between now() - interval '15 minutes' and now() - interval '2 minutes') as ticks_unfinished_15m,
         (select coalesce(jsonb_agg(w.source order by w.source), '[]') from one.event_watermarks w
           where w.last_status in ('error', 'killed')
              or (w.last_status = 'source_missing' and coalesce(((select one.setting('checks')) ->> 'source_missing_opens_incident')::boolean, true))) as event_sources_failing,
         (select coalesce(jsonb_agg(distinct r.check_id), '[]') from one.results r
           where r.ran_at > now() - interval '10 minutes' and r.duration_ms > coalesce(((select one.setting('checks')) ->> 'slow_ms')::int, 5000)) as slow_checks,
         (select coalesce(jsonb_agg(c.id order by c.id), '[]') from one.checks c join one.check_state st on st.check_id = c.id
           where c.enabled and st.killed_count >= 3) as parked_checks,
         (select count(*) from one.ai_tasks
           where status = 'pending' or (status = 'claimed' and claimed_at < now() - interval '10 minutes')) as ai_pending,
         (select count(*) from one.ai_tasks
           where status = 'deferred' and (deferred_reason like 'budget (cap reached)%' or deferred_reason like 'budget (credits exhausted)%')) as ai_held_at_cap,
         (select count(*) from one.deliveries where status = 'failed' and created_at > now() - interval '24 hours') as deliveries_failed_24h,
         (select one.ai_spent_today()) as ai_spent_inr_today,
         (select count(*) from one.actions where step = 'after' and status = 'failed' and not dry_run and ran_at > now() - interval '24 hours') as fix_acts_failed_24h,
         (select count(*) from one.ai_tasks where status = 'failed' and created_at > now() - interval '24 hours') as ai_failed_24h,
         ((select one.setting('ai')) ->> 'daily_cap_inr')::numeric as ai_cap_inr)
select tick_errors_10m = 0 and ticks_unfinished_15m = 0 and jsonb_array_length(event_sources_failing) = 0
       and jsonb_array_length(slow_checks) = 0 and jsonb_array_length(parked_checks) = 0
       and ai_pending <= (select one.threshold('ai_queue_max')) and deliveries_failed_24h = 0
       and fix_acts_failed_24h <= (select one.threshold('fix_failed_acts_max')) and ai_failed_24h <= (select one.threshold('ai_failed_tasks_max'))
       and (coalesce(ai_cap_inr, 0) = 0 or (ai_spent_inr_today < ai_cap_inr and ai_held_at_cap = 0)) as ok, to_jsonb(v) as value
  from v$q$),
  ('HB-whatsapp:witty', $d$WhatsApp Cloud API phone number status and quality rating, written by the app's WhatsApp probe; expected every 900 s.$d$, $q$select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('whatsapp:witty') as s) x$q$),
  ('HB-whatsapp:b2c', $d$WhatsApp Cloud API phone number status and quality rating, written by the app's WhatsApp probe; expected every 900 s.$d$, $q$select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('whatsapp:b2c') as s) x$q$))
update one.checks c
   set description = before.description, sql = before.sql, version = c.version + 1, updated_at = now()
  from before
 where c.id = before.id and (c.description, c.sql) is distinct from (before.description, before.sql);

delete from one.api_grants where fn = 'one.ui_privilege_ack_schema(text,integer,text)';
drop function if exists one.ui_privilege_ack_schema(text, integer, text);

select one.settings_put('n8n', one.setting('n8n') || '{"test_harness_scenario": "happy_path_mba"}', 'seed', 'rollback of 0038')
 where one.setting('n8n') ->> 'test_harness_scenario' = 'one_qualify_hot';

call one.apply_grants();
