-- 0006 the apps and the first checks (spec §6). The rest of the catalogue is seeded in phase 2 through the same
-- one.seed_check(). Seeding rule (spec §16.8): a check's rule (sql, kind, title, description, app) always follows the
-- migration; its operational fields (enabled, severity, cadence, threshold) keep a person's edit (updated_by <> 'seed').

insert into one.apps (key, name) values
  ('witty', 'Witty'), ('b2b', 'B2B CRM'), ('b2c', 'Spark (B2C CRM)'), ('web', 'Website and web advisor'),
  ('influencer', 'Influencer portal'), ('one', 'Eduwit One'), ('platform', 'Platform (Supabase, pg_cron)'),
  ('catalogue', 'Shared catalogue'), ('integrity', 'Cross-app integrity')
on conflict (key) do update set name = excluded.name;

create or replace function one.seed_check(p jsonb) returns void
language plpgsql set search_path = '' as $$
begin
  insert into one.checks as c (id, app, title, description, kind, sql, severity, cadence_s, threshold, open_after,
                               resolve_after, tags, enabled, disabled_reason, auto_fix_id)
  values (p ->> 'id', p ->> 'app', p ->> 'title', p ->> 'description', p ->> 'kind', p ->> 'sql',
          (p ->> 'severity')::one.severity, (p ->> 'cadence_s')::int, coalesce(p -> 'threshold', '{}'),
          coalesce((p ->> 'open_after')::int, 1), coalesce((p ->> 'resolve_after')::int, 3),
          coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}'),
          coalesce((p ->> 'enabled')::boolean, true), p ->> 'disabled_reason', p ->> 'auto_fix_id')
  on conflict (id) do update set
    app = excluded.app, title = excluded.title, description = excluded.description, kind = excluded.kind,
    sql = excluded.sql, auto_fix_id = excluded.auto_fix_id, tags = excluded.tags,
    severity = case when c.updated_by = 'seed' then excluded.severity else c.severity end,
    cadence_s = case when c.updated_by = 'seed' then excluded.cadence_s else c.cadence_s end,
    threshold = case when c.updated_by = 'seed' then excluded.threshold else c.threshold end,
    open_after = case when c.updated_by = 'seed' then excluded.open_after else c.open_after end,
    resolve_after = case when c.updated_by = 'seed' then excluded.resolve_after else c.resolve_after end,
    enabled = case when c.updated_by = 'seed' then excluded.enabled else c.enabled end,
    disabled_reason = case when c.updated_by = 'seed' then excluded.disabled_reason else c.disabled_reason end,
    version = c.version + 1, updated_at = now()
  where (c.sql, c.title, c.kind, c.description, c.severity, c.cadence_s, c.enabled)
        is distinct from (excluded.sql, excluded.title, excluded.kind, excluded.description, excluded.severity, excluded.cadence_s, excluded.enabled);
end $$;

-- PLAT-01: the latest run of an active job failed. Startup timeouts are counted by PLAT-01B instead (D-008).
select one.seed_check(jsonb_build_object(
  'id', 'PLAT-01', 'app', 'platform', 'kind', 'sql', 'severity', 'P1', 'cadence_s', 60, 'tags', '["code"]'::jsonb,
  'title', 'A cron job''s latest run failed',
  'description', 'Latest run in the last 26 h of each active cron job; "job startup timeout" is excluded and counted by PLAT-01B.',
  'sql', $sql$
    with last_run as (
      select distinct on (d.jobid) d.jobid, d.status, d.return_message, d.start_time
        from cron.job_run_details d where d.start_time > now() - interval '26 hours'
       order by d.jobid, d.start_time desc),
    failed as (
      select j.jobname, r.start_time, left(r.return_message, 200) as message
        from cron.job j join last_run r on r.jobid = j.jobid
       where j.active and r.status = 'failed' and r.return_message is distinct from 'job startup timeout')
    select count(*) = 0 as ok,
           jsonb_build_object('failed_jobs', coalesce(jsonb_agg(jsonb_build_object('job', jobname, 'at', start_time, 'message', message)), '[]')) as value
      from failed
  $sql$));

-- PLAT-01B: pg_cron could not start jobs (connection slots or worker saturation), grouped into one incident.
select one.seed_check(jsonb_build_object(
  'id', 'PLAT-01B', 'app', 'platform', 'kind', 'sql', 'severity', 'P2', 'cadence_s', 60,
  'title', 'pg_cron could not start jobs (startup timeouts)',
  'description', 'Runs ending in "job startup timeout" in the last 15 min; P1 from the p1 count up (D-008).',
  'threshold', '{"max_15m": 2, "p1_15m": 10}'::jsonb,
  'sql', $sql$
    select count(*) <= coalesce((select (threshold ->> 'max_15m')::int from one.checks where id = 'PLAT-01B'), 2) as ok,
           jsonb_build_object('timeouts_15m', count(*), 'jobs', coalesce(jsonb_agg(distinct j.jobname), '[]'),
             'severity', case when count(*) >= coalesce((select (threshold ->> 'p1_15m')::int from one.checks where id = 'PLAT-01B'), 10) then 'P1' else 'P2' end) as value
      from cron.job_run_details d join cron.job j on j.jobid = d.jobid
     where d.start_time > now() - interval '15 minutes' and d.return_message = 'job startup timeout'
  $sql$));

-- PLAT-02: a job scheduled every minute or faster has not run in job_silent_min minutes.
select one.seed_check(jsonb_build_object(
  'id', 'PLAT-02', 'app', 'platform', 'kind', 'sql', 'severity', 'P1', 'cadence_s', 60,
  'title', 'A frequent cron job has gone silent',
  'sql', $sql$
    with recent as (
      select jobid, max(start_time) as last_start from cron.job_run_details
       where start_time > now() - make_interval(mins => coalesce(one.threshold('job_silent_min'), 15)::int) group by jobid)
    select count(*) = 0 as ok, jsonb_build_object('silent_jobs', coalesce(jsonb_agg(j.jobname order by j.jobname), '[]')) as value
      from cron.job j left join recent r on r.jobid = j.jobid
     where j.active and (j.schedule ~ 'second' or j.schedule ~ '^\*(/1)? \* \* \* \*$') and r.jobid is null
  $sql$));

-- PLAT-05: base URLs and internal keys the database→app job calls need.
select one.seed_check(jsonb_build_object(
  'id', 'PLAT-05', 'app', 'platform', 'kind', 'sql', 'severity', 'P1', 'cadence_s', 300,
  'title', 'An app''s base URL or internal key is missing (its scheduled HTTP jobs do nothing)',
  'sql', $sql$
    with v as (
      select nullif((select value ->> 'base_url' from b2c.settings where key = 'app'), '') as spark_url,
             nullif((select value #>> '{}' from public.web_settings where key = 'internal_base_url'), '') as web_url,
             nullif(one.setting('app') ->> 'base_url', '') as one_url,
             array(select k from unnest(array['b2c_internal_key', 'web_internal_key', 'one_internal_key']) k
                    where k not in (select n from one.vault_names() n)) as keys_missing)
    select spark_url is not null and web_url is not null and one_url is not null and cardinality(keys_missing) = 0 as ok,
           jsonb_build_object('spark_base_url', spark_url is not null, 'web_internal_base_url', web_url is not null,
                              'one_base_url', one_url is not null, 'vault_missing', to_jsonb(keys_missing)) as value
      from v
  $sql$));

-- PLAT-08: lead_intake changed since its baseline (the website runbook's own canary).
select one.seed_check(jsonb_build_object(
  'id', 'PLAT-08', 'app', 'platform', 'kind', 'sql', 'severity', 'P2', 'cadence_s', 300, 'tags', '["code"]'::jsonb,
  'title', 'public.lead_intake() changed since its baseline',
  'sql', $sql$
    select b.value ->> 'md5' is null or b.value ->> 'md5' = cur.md5 as ok,
           jsonb_build_object('current', cur.md5, 'baseline', b.value ->> 'md5', 'baseline_at', b.captured_at) as value
      from (select md5(string_agg(p.prosrc, '' order by p.oid)) as md5 from pg_proc p
             where p.pronamespace = 'public'::regnamespace and p.proname = 'lead_intake') cur
      left join one.baselines b on b.key = 'lead_intake_md5'
  $sql$));

-- Federated app health: the apps' own probes, stored rather than rebuilt (System Map §11 principle 2).
select one.seed_check(jsonb_build_object(
  'id', 'WITTY-01', 'app', 'witty', 'kind', 'rpc', 'severity', 'P2', 'cadence_s', 60, 'auto_fix_id', 'FIX-OUTBOX-W2',
  'title', 'Witty''s own health alerts are firing',
  'description', 'public.w2_health_alerts(); P1 when outbox_failed or send_failed_last_hour is present, P2 otherwise.',
  'sql', $sql$
    select jsonb_array_length(a) = 0 as ok,
           jsonb_build_object('alerts', a, 'severity', case when exists (select 1 from jsonb_array_elements(a) e
                               where e ->> 'alert' in ('outbox_failed', 'send_failed_last_hour')) then 'P1' else 'P2' end) as value
      from (select public.w2_health_alerts() as a) x
  $sql$));

select one.seed_check(jsonb_build_object(
  'id', 'B2B-01', 'app', 'b2b', 'kind', 'rpc', 'severity', 'P1', 'cadence_s', 60, 'auto_fix_id', 'FIX-OUTBOX-B2B',
  'title', 'The B2B CRM''s own health check is not ok',
  'description', 'b2b.health_check(): stale or failed b2b-* job, dead or waiting delivery, B2C sync cursor over 600 s.',
  'sql', $sql$ select coalesce((h ->> 'ok')::boolean, false) as ok, h as value from (select b2b.health_check() as h) x $sql$));

select one.seed_check(jsonb_build_object(
  'id', 'WEB-01', 'app', 'web', 'kind', 'rpc', 'severity', 'P1', 'cadence_s', 60, 'auto_fix_id', 'FIX-OUTBOX-WEB',
  'title', 'The website''s database health is not ok',
  'description', 'public.web_health(): db false, catalogue poll older than 600 s, dead outbox rows, or oldest pending over 900 s.',
  'sql', $sql$
    select coalesce((h ->> 'db')::boolean, false)
           and coalesce((h ->> 'catalog_checked_seconds_ago')::numeric, 0) <= 600
           and coalesce((h ->> 'outbox_dead')::int, 0) = 0
           and coalesce((h ->> 'outbox_oldest_pending_seconds')::numeric, 0) <= 900 as ok, h as value
      from (select public.web_health() as h) x
  $sql$));

select one.seed_check(jsonb_build_object(
  'id', 'INF-05', 'app', 'influencer', 'kind', 'rpc', 'severity', 'P1', 'cadence_s', 60,
  'title', 'The influencer portal''s database health is not ok',
  'description', 'inf.health() through one.inf_health(): database or job queue not ok (D-019, D-020).',
  'sql', $sql$
    select coalesce((h ->> 'db')::boolean, false) and coalesce((h ->> 'queue_ok')::boolean, false) as ok, h as value
      from (select one.inf_health() as h) x
  $sql$));

select one.capture_baselines();
call one.apply_grants();
