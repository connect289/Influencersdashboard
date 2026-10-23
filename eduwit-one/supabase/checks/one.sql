-- Eduwit One's own health (spec §6 ONE-01, standard 7). Source for scripts/db/gen-checks.ts.

-- check: ONE-01
-- app: one
-- kind: sql
-- severity: P2
-- cadence_s: 60
-- title: Eduwit One itself is unwell: tick errors, AI backlog, failed deliveries or AI overspend
-- description: A tick report in the last 10 min with an _error key; a check slower than checks.slow_ms in the last 10 min (a statement timeout cannot be armed per check, D-044); more than ai_queue_max pending AI tasks; a failed delivery in the last 24 h; AI spend today (one.ai_calls.cost_inr, IST) above one.settings.ai.daily_cap_inr.
with v as (
  select (select count(*) from one.runs where kind = 'tick' and started_at > now() - interval '10 minutes' and report::text ~ '_error"') as tick_errors_10m,
         (select coalesce(jsonb_agg(distinct r.check_id), '[]') from one.results r
           where r.ran_at > now() - interval '10 minutes' and r.duration_ms > coalesce((one.setting('checks') ->> 'slow_ms')::int, 5000)) as slow_checks,
         (select count(*) from one.ai_tasks where status = 'pending') as ai_pending,
         (select count(*) from one.deliveries where status = 'failed' and created_at > now() - interval '24 hours') as deliveries_failed_24h,
         (select coalesce(sum(cost_inr), 0) from one.ai_calls where (created_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date) as ai_spent_inr_today,
         (one.setting('ai') ->> 'daily_cap_inr')::numeric as ai_cap_inr)
select tick_errors_10m = 0 and jsonb_array_length(slow_checks) = 0 and ai_pending <= one.threshold('ai_queue_max') and deliveries_failed_24h = 0
       and ai_spent_inr_today <= coalesce(ai_cap_inr, 'infinity'::numeric) as ok, to_jsonb(v) as value
  from v

-- check: ONE-STORM
-- app: one
-- kind: integrity
-- severity: P1
-- cadence_s: 60
-- resolve_after: 15
-- title: Alert storm: many P1 incidents opened within minutes
-- description: More than alerts.storm.p1_count (10) P1 incidents opened in alerts.storm.window_min (5) minutes. Its incident is the one storm alert, naming the count and the top three checks; while it was routed in the last storm.suppress_min (15) minutes, other P1s are suppressed and filed under it (spec §9). Resolves after 15 calm minutes.
with w as (select coalesce(one.setting('alerts') -> 'storm', '{}') as s),
recent as (
  select i.check_id from one.incidents i, w
   where i.severity = 'P1' and i.check_id <> 'ONE-STORM'
     and i.opened_at > now() - make_interval(mins => coalesce((w.s ->> 'window_min')::int, 5)))
select count(*) <= coalesce((select (s ->> 'p1_count')::int from w), 10) as ok,
       jsonb_build_object('p1_opened', count(*),
         'top_checks', (select coalesce(jsonb_agg(check_id), '[]') from (select check_id from recent group by check_id order by count(*) desc, check_id limit 3) t)) as value
  from recent
