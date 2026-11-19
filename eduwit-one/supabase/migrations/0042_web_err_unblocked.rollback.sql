-- Rollback of 0042: WEB-ERR's seed returns to 0041's (off, blocked:web_error_reporter_not_ported). one.seed_check changes
-- the reason only while the row is still the seed's: once the owner has switched the check on (updated_by is then a
-- person), this rollback leaves it as the owner set it. Apply 0006_seed_checks.sql afterwards only from a tree whose
-- supabase/checks/web.sql carries the blocked reason again.
select one.seed_check(jsonb_build_object(
  'id', 'WEB-ERR',
  'app', 'web',
  'kind', 'sql',
  'severity', 'P2',
  'cadence_s', 300,
  'open_after', 1,
  'resolve_after', 2,
  'title', 'The website is throwing server errors',
  'description', 'The server errors the app itself reported (one.app_error_report, migration 0041, D-141: counts per route template and error name, no personal data) in the 5-minute buckets that started in the last 15 minutes, the current one and the two before it, against app_errors_15m (20). Fires above the limit and resolves by itself after two readings at or under it. The value names the three busiest route and error pairs. An app that does not throw reports nothing, so no rows reads as no errors; the reporter runs only on a deployment (production build, a hosted Supabase address and its service key). Off until the website carries the reporter (it lives in another repository branch): until then the website reports nothing, and a check that reads nothing must not read as passing.',
  'auto_fix_id', null,
  'tags', '[]'::jsonb,
  'enabled', false,
  'disabled_reason', 'blocked:web_error_reporter_not_ported',
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
