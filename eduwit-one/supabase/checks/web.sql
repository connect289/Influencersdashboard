-- Website and web advisor checks (spec §6, WEB-*). Sources for scripts/db/gen-checks.ts.

-- check: WEB-01
-- app: web
-- kind: rpc
-- severity: P1
-- cadence_s: 60
-- fix: FIX-OUTBOX-WEB
-- title: The website's database health is not ok
-- description: public.web_health(): db false, catalogue poll older than 600 s, dead outbox rows, or oldest pending over 900 s. FIX-CATALOG-POLL attaches to the catalogue case.
select coalesce((h ->> 'db')::boolean, false)
       and coalesce((h ->> 'catalog_checked_seconds_ago')::numeric, 0) <= 600
       and coalesce((h ->> 'outbox_dead')::int, 0) = 0
       and coalesce((h ->> 'outbox_oldest_pending_seconds')::numeric, 0) <= 900 as ok, h as value
  from (select public.web_health() as h) x

-- check: WEB-02
-- app: web
-- kind: http
-- severity: P1
-- cadence_s: 300
-- open_after: 2
-- title: The website's /api/health is not ok
-- description: GET <hosts.website>/api/health not {ok:true} within 5 s, twice in a row (open_after 2). Run by the app's health probe every 5 minutes (D-133), which also writes heartbeat website.

-- check: WEB-03
-- app: web
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- title: A website sign-up did not get its code or its lead
-- description: Non-test web_gate_attempts from the last 24 h with no code_sent_at web_code_min minutes after submitted_at, or verified with no lead_id web_lead_min minutes after verified_at.
select count(*) = 0 as ok,
       jsonb_build_object('no_code', count(*) filter (where code_sent_at is null), 'no_lead', count(*) filter (where code_sent_at is not null)) as value
  from public.web_gate_attempts
 where not coalesce(is_test, false) and submitted_at > now() - interval '24 hours'
   and ((code_sent_at is null and submitted_at < now() - make_interval(mins => (select one.threshold('web_code_min'))::int))
        or (verified_at is not null and lead_id is null and verified_at < now() - make_interval(mins => (select one.threshold('web_lead_min'))::int)))

-- check: WEB-04
-- app: web
-- kind: sql
-- severity: P2
-- cadence_s: 900
-- open_after: 4
-- title: The website catalogue has unmapped rows or rows awaiting review
-- description: web_catalog_state.last_result reports unmapped or admin_needs_review above 0; open_after 4 at a 15-min cadence means it must last an hour.
select coalesce((c.last_result ->> 'unmapped')::int, 0) = 0 and coalesce((c.last_result ->> 'admin_needs_review')::int, 0) = 0 as ok,
       jsonb_build_object('unmapped', c.last_result -> 'unmapped', 'admin_needs_review', c.last_result -> 'admin_needs_review', 'checked_at', c.last_checked_at) as value
  from (select 1) x left join lateral (select last_result, last_checked_at from public.web_catalog_state order by id limit 1) c on true

-- check: WEB-05
-- app: web
-- kind: sql
-- severity: P3
-- cadence_s: 3600
-- title: Website search returns nothing too often, or a new 404 is popular
-- description: Zero-result share of web_search_log in the last hour above 20 percent (at least 20 searches), or an unresolved web_404_log path first seen in the last 7 days with more than 10 hits.
with s as (select count(*) as n, count(*) filter (where zero) as z from public.web_search_log where created_at > now() - interval '1 hour'),
f as (select coalesce(jsonb_agg(path order by hits desc), '[]') as paths, count(*) as n from public.web_404_log
       where resolved_at is null and first_seen > now() - interval '7 days' and hits > 10)
select (s.n < 20 or s.z * 100.0 / s.n <= 20) and f.n = 0 as ok,
       jsonb_build_object('searches_1h', s.n, 'zero_1h', s.z, 'new_404_paths', f.paths) as value
  from s, f

-- check: WEB-06
-- app: web
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: Web advisor spend is over cap, or an escalation got no callback
-- description: Sum of non-test web_advisor_sessions.cost_usd today (IST) above web_advisor_daily_usd, or a session escalated more than 1 h ago in the last 7 days with no web_callback_requests row.
with v as (
  select (select coalesce(sum(cost_usd), 0) from public.web_advisor_sessions
           where not coalesce(is_test, false) and created_at >= (((now() at time zone 'Asia/Kolkata')::date)::timestamp at time zone 'Asia/Kolkata') and created_at < ((((now() at time zone 'Asia/Kolkata')::date + 1)::timestamp) at time zone 'Asia/Kolkata')) as spent_usd_today,
         (select count(*) from public.web_advisor_sessions s
           where not coalesce(s.is_test, false) and s.escalated_at between now() - interval '7 days' and now() - interval '1 hour'
             and not exists (select 1 from public.web_callback_requests c where c.session_id = s.id)) as escalations_without_callback)
select spent_usd_today <= (select one.threshold('web_advisor_daily_usd')) and escalations_without_callback = 0 as ok, to_jsonb(v) as value
  from v

-- check: WEB-07
-- app: web
-- kind: http
-- severity: P1
-- cadence_s: 300
-- title: The website's production deployment is not ready or its functions are erroring
-- description: Vercel API: the latest production deployment of project eduwit-website (one.settings.vercel) is not READY, or its function error rate is over 2 percent in 15 min. Run by the app's Vercel probe, which also writes heartbeat vercel:website.

-- check: WEB-ERR
-- app: web
-- kind: sql
-- severity: P2
-- cadence_s: 300
-- resolve_after: 2
-- disabled: blocked:web_error_reporter_not_ported
-- title: The website is throwing server errors
-- description: The server errors the app itself reported (one.app_error_report, migration 0041, D-141: counts per route template and error name, no personal data) in the 5-minute buckets that started in the last 15 minutes, the current one and the two before it, against app_errors_15m (20). Fires above the limit and resolves by itself after two readings at or under it. The value names the three busiest route and error pairs. An app that does not throw reports nothing, so no rows reads as no errors; the reporter runs only on a deployment (production build, a hosted Supabase address and its service key). Off until the website carries the reporter (it lives in another repository branch): until then the website reports nothing, and a check that reads nothing must not read as passing.
with cfg as (select coalesce((select one.threshold('app_errors_15m')), 20)::numeric as max_15m),
e as (
  select x.route, x.error_name, sum(x.n) as n, max(x.last_seen) as last_seen
    from one.app_errors x
   where x.app = 'web' and x.bucket > now() - interval '15 minutes'
   group by x.route, x.error_name),
t as (select coalesce(sum(e.n), 0) as errors, count(*) as pairs, max(e.last_seen) as last_seen from e)
select t.errors <= cfg.max_15m as ok,
       jsonb_build_object('errors_15m', t.errors, 'limit', cfg.max_15m, 'pairs', t.pairs, 'last_seen', t.last_seen,
                          'top', (select coalesce(jsonb_agg(jsonb_build_object('route', s.route, 'error', s.error_name, 'n', s.n) order by s.n desc, s.route, s.error_name), '[]')
                                    from (select e.route, e.error_name, e.n from e order by e.n desc, e.route, e.error_name limit 3) s)) as value
  from cfg, t
