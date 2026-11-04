-- 0035 CE-03: a login-expiry alert is over once the login is valid again (D-132). Eduwit Scout writes a ce.health row
-- with status alert when a partner's portal login expires (metric session.expired) and no ok row when a person logs in
-- again, so CE-03, which reads the newest row per metric and partner in 24 hours, kept the degreepartner incident open
-- for a day after every new login (2 and 3 Nov: the login was valid again at 02:00 UTC, the alert row of 01:52 stayed
-- the newest). The rule now leaves a session.expired alert out when that partner's ce.session is valid and newer than
-- the alert row; every other metric is read as before. The source is supabase/checks/catalogue_engine.sql (0023 is
-- regenerated from it for a fresh install); this file carries the same text to a database that already has 0023. A
-- direct update rather than one.seed_check, so the check's switch, severity and cadence stay whatever they are (on a
-- fresh install CE-03 stays off until its Setup item is validated). Nothing of the five apps is touched; only schema
-- one. Rollback: 0035_ce03_login_alert_clears.rollback.sql.

with next as (
  select $d$The latest ce.health row of a metric (per partner) in the last 24 h has status alert: written every 15 min by ce.health_collect() (the engine's and the shared database's size, its storage against the cap, dead jobs, stale heartbeats) and by the engine's own alerts such as queue.dead_job. A session.expired alert is over once that partner's ce.session is valid again and newer than the alert (Scout writes no ok row when a person logs in again, D-132). One alert per metric (subjects); the value carries the engine's own message for each, which holds no personal data. Warnings are counted, not raised.$d$::text as description,
         $sql$with latest as (
  select distinct on (metric, partner_id) metric, partner_id, status, message, observed_at
    from ce.health
   where observed_at > now() - interval '24 hours'
   order by metric, partner_id, observed_at desc, id desc),
live as (
  select l.* from latest l
   where not (l.metric = 'session.expired' and l.status = 'alert'
              and exists (select 1 from ce.session s
                           where s.partner_id = l.partner_id and s.status = 'valid' and s.updated_at > l.observed_at)))
select count(*) filter (where status = 'alert') = 0 as ok,
       jsonb_build_object('alerts', count(*) filter (where status = 'alert'), 'warnings', count(*) filter (where status = 'warn'),
                          'subjects', coalesce(jsonb_agg(distinct metric order by metric) filter (where status = 'alert'), '[]'),
                          'messages', coalesce(to_jsonb((array_agg(jsonb_build_object('metric', metric, 'partner_id', partner_id,
                                                                                      'message', left(message, 300), 'at', observed_at)
                                                                   order by metric, partner_id) filter (where status = 'alert'))[1:20]), '[]')) as value
  from live$sql$::text as sql)
update one.checks c
   set description = next.description, sql = next.sql, version = c.version + 1, updated_at = now()
  from next
 where c.id = 'CE-03' and (c.sql, c.description) is distinct from (next.sql, next.description);

-- The Setup validator (0022) names every Scout table and column the checks read, so a fresh install switches CE-01 to
-- CE-05 on only once they all exist: ce.session joins the list with the three columns CE-03 reads. Otherwise 0022's
-- function, byte for byte.
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
      ('ce.session', array['partner_id', 'status', 'updated_at']),
      ('ce.run', array['id', 'kind', 'partner_id', 'status', 'created_at', 'updated_at']),
      ('ce.events', array['id', 'occurred_at', 'type', 'partner_id', 'run_id', 'actor', 'payload'])) t(name, cols)
$$;
