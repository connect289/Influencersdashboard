-- 0042 WEB-ERR can be switched on (D-142). The website carries the server-error reporter since 14 Nov 2026 (website
-- D-097, commit 9eafa94, live in deployment 191081b); on 19 Nov 2026 the website's exact call (one.app_error_report('web',
-- …) as service_role) was made in production inside a rolled-back transaction and wrote its row, and the website's
-- production deployment carries the address and the secret key the reporter needs. So the check's off reason changes from
-- blocked:web_error_reporter_not_ported (which the console's switch refuses) to owner:ready_to_switch_on: the check stays
-- OFF, and the owner switches it on in Settings → Checks. Only that seed row changes, through one.seed_check, which
-- changes the reason only while the row is still the seed's (a person's edit wins). No table, function or grant changes.
select one.seed_check(jsonb_build_object(
  'id', 'WEB-ERR',
  'app', 'web',
  'kind', 'sql',
  'severity', 'P2',
  'cadence_s', 300,
  'open_after', 1,
  'resolve_after', 2,
  'title', 'The website is throwing server errors',
  'description', 'The server errors the app itself reported (one.app_error_report, migration 0041, D-141: counts per route template and error name, no personal data) in the 5-minute buckets that started in the last 15 minutes, the current one and the two before it, against app_errors_15m (20). Fires above the limit and resolves by itself after two readings at or under it. The value names the three busiest route and error pairs. An app that does not throw reports nothing, so no rows reads as no errors; the reporter runs only on a deployment (production build, a hosted Supabase address and its service key). The website carries the reporter since 14 Nov 2026 (website D-097, verified in production on 19 Nov 2026, D-142); the check stays off until the owner switches it on (Settings → Checks).',
  'auto_fix_id', null,
  'tags', '[]'::jsonb,
  'enabled', false,
  'disabled_reason', 'owner:ready_to_switch_on',
  'search_path', '',
  'sql', $sql$
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
$sql$));
