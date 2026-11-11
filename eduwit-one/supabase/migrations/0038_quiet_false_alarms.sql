-- 0038 the monitor stops crying wolf (D-136). Four things found by the evaluation of 10 Nov 2026, none of them in the
-- five apps; only schema one changes.
--   1. ONE-01 counted the end-to-end tests as "slow checks": a journey takes as long as its steps wait (T-WITTY-QUALIFY
--      ran 85 s every hour), so ONE-01 failed for ten minutes of every hour. Tests are left out of slow_checks; a test
--      has its own step time limits and its own incident.
--   2. HB-whatsapp:b2c had been open since 2 Nov although Spark has no WhatsApp number set up: the probe writes a
--      heartbeat only for a line with a number id in settings.whatsapp.phone_ids. A line that was never set up (no id
--      and no heartbeat ever written) now passes with configured false; a line that has reported even once keeps the
--      usual rule, so removing an id later still raises the alarm. The same rule for Witty's line, which is unchanged
--      in effect (it is set up and reporting).
--   3. Settings -> Privileges acknowledged one function per click, and PLAT-07 had been open since 31 Oct behind 58 of
--      them (53 are Scout's own admin API). one.ui_privilege_ack_schema acknowledges every listed function of one
--      schema in one step: owner only, as one.ui_privilege_ack is since 0030 (D-110); it refuses when the number the
--      owner was shown differs from what is there now, so nothing that appeared in between is swept in unread; one
--      audit row per function.
--   4. T-WITTY-QUALIFY had failed every hour since its first run: the harness scenario it played (happy_path_mba) gives
--      no email, so Witty rightly never qualifies it and the wait for a HOT lead could not end. The app now sends its
--      own qualifying conversation on one reserved harness phone (lib/tests/apps.ts, QUALIFY_SCENARIO); here the stored
--      setting moves to it only where it still holds the old default.
-- Direct updates of one.checks rather than one.seed_check, so the owner's switch, severity and cadence stay. Sources:
-- supabase/checks/one.sql and heartbeats.sql (0006 is regenerated for a fresh install). Rollback:
-- 0038_quiet_false_alarms.rollback.sql.

with next (id, description, sql) as (values
  ('ONE-01', $d$More than fix_failed_acts_max fix acts that failed, or more than ai_failed_tasks_max AI tasks that failed, in 24 h (hardening F16). A tick report in the last 10 min with an _error key (a killed check or event copy included); a tick that started 2 to 15 min ago and never finished its alert step and app call; an event source in error, killed or missing (where missing counts, D-042; m13 of the second review); a check slower than checks.slow_ms in the last 10 min (a statement timeout cannot be armed per check, D-044; the end-to-end tests are left out, a journey takes as long as its steps wait, D-136); more than ai_queue_max AI tasks pending or held past their 10-minute lease; a failed delivery in the last 24 h; AI spend today (one.ai_calls.cost_inr, IST) at or above one.settings.ai.daily_cap_inr, or AI work held back because the day's cap is reached or the Anthropic API credits are used up (spec §11: ONE-01 fires at 100%; phase 6 review M1; D-078). A cap of 0 means the owner switched the AI off and raises nothing. A check parked after three killed runs in a row (it tries again every checks.parked_retry_h hours until a run finishes, D-102).$d$, $q$with v as (
  select (select count(*) from one.runs where kind = 'tick' and started_at > now() - interval '10 minutes' and report::text ~ '_error"') as tick_errors_10m,
         (select count(*) from one.runs where kind = 'tick' and finished_at is null
             and started_at between now() - interval '15 minutes' and now() - interval '2 minutes') as ticks_unfinished_15m,
         (select coalesce(jsonb_agg(w.source order by w.source), '[]') from one.event_watermarks w
           where w.last_status in ('error', 'killed')
              or (w.last_status = 'source_missing' and coalesce(((select one.setting('checks')) ->> 'source_missing_opens_incident')::boolean, true))) as event_sources_failing,
         (select coalesce(jsonb_agg(distinct r.check_id), '[]') from one.results r
           where r.ran_at > now() - interval '10 minutes' and r.duration_ms > coalesce(((select one.setting('checks')) ->> 'slow_ms')::int, 5000)
             and not exists (select 1 from one.checks t where t.id = r.check_id and t.kind = 'test')) as slow_checks,
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
  ('HB-whatsapp:witty', $d$WhatsApp Cloud API phone number status and quality rating, written by the app's WhatsApp probe; expected every 900 s. A line that was never set up (no number id in settings.whatsapp.phone_ids and no heartbeat ever written for it) has nothing to lose, so the check passes with configured false (D-136); once the id is entered on the Setup page, or after the line has reported even once, the usual rule applies.$d$, $q$select case when x.known then (x.s ->> 'ok')::boolean else true end as ok,
       case when x.known then x.s else jsonb_build_object('configured', false) end as value
  from (select one.heartbeat_state('whatsapp:witty') as s,
               (coalesce((select one.setting('whatsapp')) -> 'phone_ids' ->> 'witty', '') <> ''
                or exists (select 1 from one.heartbeats h where h.component = 'whatsapp:witty')) as known) x$q$),
  ('HB-whatsapp:b2c', $d$WhatsApp Cloud API phone number status and quality rating, written by the app's WhatsApp probe; expected every 900 s. A line that was never set up (no number id in settings.whatsapp.phone_ids and no heartbeat ever written for it) has nothing to lose, so the check passes with configured false (D-136); once the id is entered on the Setup page, or after the line has reported even once, the usual rule applies.$d$, $q$select case when x.known then (x.s ->> 'ok')::boolean else true end as ok,
       case when x.known then x.s else jsonb_build_object('configured', false) end as value
  from (select one.heartbeat_state('whatsapp:b2c') as s,
               (coalesce((select one.setting('whatsapp')) -> 'phone_ids' ->> 'b2c', '') <> ''
                or exists (select 1 from one.heartbeats h where h.component = 'whatsapp:b2c')) as known) x$q$))
update one.checks c
   set description = next.description, sql = next.sql, version = c.version + 1, updated_at = now()
  from next
 where c.id = next.id and (c.description, c.sql) is distinct from (next.description, next.sql);

create or replace function one.ui_privilege_ack_schema(p_schema text, p_expected integer, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_fns text[];
  f text;
begin
  select coalesce(array_agg(b.fn order by b.fn), '{}') into v_fns
    from one.privilege_baseline b where b.schema = p_schema and not b.acknowledged;
  if cardinality(v_fns) = 0 then
    raise exception 'nothing to acknowledge in schema %', left(coalesce(p_schema, ''), 60) using errcode = '22023';
  end if;
  if cardinality(v_fns) is distinct from p_expected then
    raise exception 'the list changed: % function(s) to acknowledge in %, not %; reload the page and read it again',
      cardinality(v_fns), left(p_schema, 60), coalesce(p_expected::text, 'none') using errcode = '22023';
  end if;
  update one.privilege_baseline set acknowledged = true, acknowledged_by = v_actor where fn = any (v_fns) and not acknowledged;
  foreach f in array v_fns loop
    perform one.ui_audit_write(v_actor, 'privilege.acknowledge', 'function:' || left(f, 180), null, null, p_request_id);
  end loop;
  return jsonb_build_object('ok', true, 'acknowledged', cardinality(v_fns));
end $$;

insert into one.api_grants (fn, role, why)
values ('one.ui_privilege_ack_schema(text,integer,text)', 'authenticated', 'page write (0038): the owner acknowledges a schema''s new functions')
on conflict do nothing;

-- T-WITTY-QUALIFY plays Eduwit One's own scenario; a value someone chose on the Settings page is left alone.
select one.settings_put('n8n', one.setting('n8n') || '{"test_harness_scenario": "one_qualify_hot"}', 'seed',
                        '0038: T-WITTY-QUALIFY plays a conversation Witty can qualify (D-136)')
 where one.setting('n8n') ->> 'test_harness_scenario' = 'happy_path_mba';

call one.apply_grants();
