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
