-- Rollback of 0035: CE-03 as 0023 seeded it before 0035 (the newest ce.health row per metric and partner in 24 hours,
-- with no exception for a login that is valid again). The check's switch, severity and cadence stay.

with before as (
  select $d$The latest ce.health row of a metric (per partner) in the last 24 h has status alert: written every 15 min by ce.health_collect() (the engine's and the shared database's size, its storage against the cap, dead jobs, stale heartbeats) and by the engine's own alerts such as queue.dead_job. One alert per metric (subjects); the value carries the engine's own message for each, which holds no personal data. Warnings are counted, not raised.$d$::text as description,
         $sql$with latest as (
  select distinct on (metric, partner_id) metric, partner_id, status, message, observed_at
    from ce.health
   where observed_at > now() - interval '24 hours'
   order by metric, partner_id, observed_at desc, id desc)
select count(*) filter (where status = 'alert') = 0 as ok,
       jsonb_build_object('alerts', count(*) filter (where status = 'alert'), 'warnings', count(*) filter (where status = 'warn'),
                          'subjects', coalesce(jsonb_agg(distinct metric order by metric) filter (where status = 'alert'), '[]'),
                          'messages', coalesce(to_jsonb((array_agg(jsonb_build_object('metric', metric, 'partner_id', partner_id,
                                                                                      'message', left(message, 300), 'at', observed_at)
                                                                   order by metric, partner_id) filter (where status = 'alert'))[1:20]), '[]')) as value
  from latest$sql$::text as sql)
update one.checks c
   set description = before.description, sql = before.sql, version = c.version + 1, updated_at = now()
  from before
 where c.id = 'CE-03' and (c.sql, c.description) is distinct from (before.sql, before.description);

-- The Setup validator as 0022 defined it (without ce.session).
create or replace function one.setup_engine_facts() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('tables', jsonb_object_agg(t.name, jsonb_build_object(
           'exists', to_regclass(t.name) is not null,
           'readable', to_regclass(t.name) is not null and has_table_privilege(to_regclass(t.name), 'SELECT'),
           'missing_columns', (select coalesce(jsonb_agg(c.col order by c.ord), '[]')
                                 from unnest(t.cols) with ordinality c(col, ord)
                                where not exists (select 1 from pg_catalog.pg_attribute a
                                                   where a.attrelid = to_regclass(t.name) and a.attname = c.col
                                                     and a.attnum > 0 and not a.attisdropped)))))
    from (values
      ('ce.heartbeat', array['component', 'last_ok_at', 'last_error_at', 'expected_interval_s']),
      ('ce.job', array['id', 'stage', 'kind', 'status', 'next_run_at', 'locked_until']),
      ('ce.health', array['id', 'metric', 'partner_id', 'status', 'message', 'observed_at']),
      ('ce.run', array['id', 'kind', 'partner_id', 'status', 'created_at', 'updated_at']),
      ('ce.events', array['id', 'occurred_at', 'type', 'partner_id', 'run_id', 'actor', 'payload'])) t(name, cols)
$$;
