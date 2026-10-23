-- Shared catalogue checks (spec §6, CAT-*). Sources for scripts/db/gen-checks.ts.

-- check: CAT-01
-- app: catalogue
-- kind: sql
-- severity: P2
-- cadence_s: 900
-- fix: FIX-CACHE-B2C
-- title: Spark's programme cache is behind the catalogue
-- description: max(b2c.programme_cache.catalog_updated_at) more than catalogue_min minutes behind max(public.catalog_programs.updated_at).
with v as (select (select max(updated_at) from public.catalog_programs) as catalogue_at, (select max(catalog_updated_at) from b2c.programme_cache) as cache_at)
select coalesce(cache_at >= catalogue_at - make_interval(mins => one.threshold('catalogue_min')::int), catalogue_at is null) as ok, to_jsonb(v) as value
  from v

-- check: CAT-02
-- app: catalogue
-- kind: sql
-- severity: P2
-- cadence_s: 300
-- fix: FIX-CATALOG-POLL
-- title: The website has not picked up a catalogue change
-- description: The newest catalog.changes row is more than 5 min old and newer than web_catalog_state.refreshed_at.
with v as (select (select max(at) from catalog.changes) as changed_at, (select max(refreshed_at) from public.web_catalog_state) as refreshed_at)
select not coalesce(changed_at < now() - interval '5 minutes' and changed_at > coalesce(refreshed_at, '-infinity'::timestamptz), false) as ok, to_jsonb(v) as value
  from v

-- check: CAT-03
-- app: catalogue
-- kind: sql
-- severity: P2
-- cadence_s: 900
-- title: Witty did not move to the new catalogue version
-- description: A catalog.changes row more than 15 min old is newer than the last change of w2_meta catalog_version, so catalog_commit ran and Witty kept the old version.
with v as (select (select max(at) from catalog.changes) as changed_at,
                  (select updated_at from public.w2_meta where key = 'catalog_version') as witty_version_at,
                  (select value from public.w2_meta where key = 'catalog_version') as witty_version)
select not coalesce(changed_at < now() - interval '15 minutes' and changed_at > coalesce(witty_version_at, '-infinity'::timestamptz), false) as ok, to_jsonb(v) as value
  from v

-- check: CAT-04
-- app: catalogue
-- kind: sql
-- severity: P3
-- cadence_s: 86400
-- title: An active programme has no fee
-- description: public.catalog_programs active with fee_total null or 0 and not flagged fee_on_request.
select count(*) = 0 as ok, jsonb_build_object('count', count(*), 'ids', coalesce(to_jsonb((array_agg(id order by id) filter (where id is not null))[1:20]), '[]')) as value
  from public.catalog_programs
 where active and coalesce(fee_total, 0) = 0 and not ('fee_on_request' = any (coalesce(flags, '{}')))
