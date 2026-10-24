-- Eduwit One's own health (spec §6 ONE-01, standard 7). Source for scripts/db/gen-checks.ts.

-- check: ONE-01
-- app: one
-- kind: sql
-- severity: P2
-- cadence_s: 60
-- title: Eduwit One itself is unwell: tick errors, AI backlog, failed deliveries or AI overspend
-- description: A tick report in the last 10 min with an _error key (a killed check or event copy included); a tick that started 2 to 15 min ago and never finished its alert step and app call; an event source in error, killed or missing (where missing counts, D-042; m13 of the second review); a check slower than checks.slow_ms in the last 10 min (a statement timeout cannot be armed per check, D-044); more than ai_queue_max AI tasks pending or held past their 10-minute lease; a failed delivery in the last 24 h; AI spend today (one.ai_calls.cost_inr, IST) at or above one.settings.ai.daily_cap_inr, or AI work held back because the day's cap is reached or the Anthropic API credits are used up (spec §11: ONE-01 fires at 100%; phase 6 review M1; D-078). A cap of 0 means the owner switched the AI off and raises nothing.
with v as (
  select (select count(*) from one.runs where kind = 'tick' and started_at > now() - interval '10 minutes' and report::text ~ '_error"') as tick_errors_10m,
         (select count(*) from one.runs where kind = 'tick' and finished_at is null
             and started_at between now() - interval '15 minutes' and now() - interval '2 minutes') as ticks_unfinished_15m,
         (select coalesce(jsonb_agg(w.source order by w.source), '[]') from one.event_watermarks w
           where w.last_status in ('error', 'killed')
              or (w.last_status = 'source_missing' and coalesce(((select one.setting('checks')) ->> 'source_missing_opens_incident')::boolean, true))) as event_sources_failing,
         (select coalesce(jsonb_agg(distinct r.check_id), '[]') from one.results r
           where r.ran_at > now() - interval '10 minutes' and r.duration_ms > coalesce(((select one.setting('checks')) ->> 'slow_ms')::int, 5000)) as slow_checks,
         (select count(*) from one.ai_tasks
           where status = 'pending' or (status = 'claimed' and claimed_at < now() - interval '10 minutes')) as ai_pending,
         (select count(*) from one.ai_tasks
           where status = 'deferred' and (deferred_reason like 'budget (cap reached)%' or deferred_reason like 'budget (credits exhausted)%')) as ai_held_at_cap,
         (select count(*) from one.deliveries where status = 'failed' and created_at > now() - interval '24 hours') as deliveries_failed_24h,
         (select coalesce(sum(cost_inr), 0) from one.ai_calls where (created_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date) as ai_spent_inr_today,
         ((select one.setting('ai')) ->> 'daily_cap_inr')::numeric as ai_cap_inr)
select tick_errors_10m = 0 and ticks_unfinished_15m = 0 and jsonb_array_length(event_sources_failing) = 0
       and jsonb_array_length(slow_checks) = 0 and ai_pending <= (select one.threshold('ai_queue_max')) and deliveries_failed_24h = 0
       and (coalesce(ai_cap_inr, 0) = 0 or (ai_spent_inr_today < ai_cap_inr and ai_held_at_cap = 0)) as ok, to_jsonb(v) as value
  from v

-- check: ONE-02
-- app: one
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- title: Alert emails are not going out
-- description: An alert, escalation or storm email still pending or sending delivery_stuck_min (5) minutes after it was queued: the app is not answering the tick's call, or cannot send. This incident's own email waits in the same queue, so the external watchdog reads the same age and pages through the uptime monitor (D-018; M2 of the second review).
select count(*) = 0 as ok,
       jsonb_build_object('stuck', count(*), 'oldest_at', min(created_at),
                          'ids', coalesce(to_jsonb((array_agg(id order by id) filter (where id is not null))[1:20]), '[]')) as value
  from one.deliveries
 where status in ('pending', 'sending') and kind in ('alert', 'escalation', 'storm')
   and created_at < now() - make_interval(mins => (select one.threshold('delivery_stuck_min'))::int)

-- check: ONE-STORM
-- app: one
-- kind: integrity
-- severity: P1
-- cadence_s: 60
-- resolve_after: 15
-- title: Alert storm: many P1 incidents opened within minutes
-- description: More than alerts.storm.p1_count (10) P1 incidents opened in alerts.storm.window_min (5) minutes. Its incident is the one storm alert, naming the count and the top three checks; while it was routed in the last storm.suppress_min (15) minutes, other P1s are suppressed and filed under it (spec §9). Resolves after 15 calm minutes.
with w as (select coalesce((select one.setting('alerts')) -> 'storm', '{}') as s),
recent as (
  select i.check_id from one.incidents i, w
   where i.severity = 'P1' and i.check_id <> 'ONE-STORM'
     and i.opened_at > now() - make_interval(mins => coalesce((w.s ->> 'window_min')::int, 5)))
select count(*) <= coalesce((select (s ->> 'p1_count')::int from w), 10) as ok,
       jsonb_build_object('p1_opened', count(*),
         'top_checks', (select coalesce(jsonb_agg(check_id), '[]') from (select check_id from recent group by check_id order by count(*) desc, check_id limit 3) t)) as value
  from recent

-- check: ONE-PURGE
-- app: one
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: Synthetic test rows are not being purged
-- description: A finished test run still not purged a day after tests.purge_after_days (2): the purge keeps failing in an app (its report is on the run) or is not running (no time left in the tick, the test runner login missing). Test leads then stay in B2B and Spark longer than agreed (D-071).
select count(*) = 0 as ok,
       jsonb_build_object('overdue', count(*), 'oldest_finished_at', min(finished_at), 'max_attempts', coalesce(max(purge_attempts), 0),
                          'runs', coalesce(to_jsonb((array_agg(id order by finished_at))[1:20]), '[]'),
                          'tests', coalesce(jsonb_agg(distinct test_id), '[]')) as value
  from one.test_runs
 where purged_at is null and finished_at is not null
   and finished_at < now() - make_interval(days => coalesce(((select one.setting('tests')) ->> 'purge_after_days')::int, 2) + 1)

-- check: ONE-SYNTH
-- app: one
-- kind: test
-- severity: P2
-- cadence_s: 3600
-- resolve_after: 1
-- tags: synthetic
-- title: Synthetic incident (T-ALERT)
-- description: Never fails on its own. T-ALERT opens an incident on it to prove that a delivery is sent and delivered, then acknowledges and resolves it. Its incidents are left out of the P2 digest and the brief, and carry "synthetic" in their evidence.
