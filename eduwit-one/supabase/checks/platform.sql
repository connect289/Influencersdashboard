-- Platform checks (spec §6, PLAT-*). Sources for scripts/db/gen-checks.ts; see that file for the block format.

-- check: PLAT-01
-- app: platform
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- tags: cron
-- title: A cron job's latest run failed
-- description: The latest finished run in the last 26 h of each active cron job ended in "failed" (a run still in progress is ignored, so it cannot hide the failure before it). Each job is a subject: a job joining the failing set alerts again (D-043). "job startup timeout" is left to PLAT-01B (D-008); b2c-capacity has its own P2 check, B2C-10. Reads only the newest cron_scan_runs runs, through the runid key (M3 and M7 of the second review); jobs that ran less than daily are PLAT-01W's.
with w as (select coalesce(max(runid), 0) - (select one.threshold('cron_scan_runs'))::bigint as from_runid from cron.job_run_details),
last_run as (
  select distinct on (d.jobid) d.jobid, d.status, d.return_message, d.start_time
    from cron.job_run_details d, w
   where d.runid > w.from_runid and d.start_time > now() - interval '26 hours'
     and d.status in ('succeeded', 'failed') and d.return_message is distinct from 'job startup timeout'
   order by d.jobid, d.runid desc),
failed as (
  select j.jobname, r.start_time, left(r.return_message, 200) as message
    from cron.job j join last_run r on r.jobid = j.jobid
   where j.active and r.status = 'failed' and j.jobname <> 'b2c-capacity')
select count(*) = 0 as ok,
       jsonb_build_object('failed_jobs', coalesce(jsonb_agg(jsonb_build_object('job', jobname, 'at', start_time, 'message', message) order by jobname), '[]'),
                          'subjects', coalesce(jsonb_agg(jobname order by jobname), '[]')) as value
  from failed

-- check: PLAT-01W
-- app: platform
-- kind: sql
-- severity: P1
-- cadence_s: 3600
-- tags: cron
-- title: A cron job that runs less than daily failed its latest run
-- description: PLAT-01 for the active jobs with no finished run in its 26 h window (weekly or monthly jobs): their latest finished run in the whole history ended in "failed". Hourly, because it reads the whole table (m12 of the second review). Startup timeouts and b2c-capacity are left to PLAT-01B and B2C-10.
with w as (select coalesce(max(runid), 0) - (select one.threshold('cron_scan_runs'))::bigint as from_runid from cron.job_run_details),
recent as (
  select distinct d.jobid from cron.job_run_details d, w
   where d.runid > w.from_runid and d.start_time > now() - interval '26 hours' and d.status in ('succeeded', 'failed')),
last_run as (
  select distinct on (d.jobid) d.jobid, d.status, d.return_message, d.start_time
    from cron.job_run_details d
   where d.jobid in (select j.jobid from cron.job j where j.active and j.jobid not in (select r.jobid from recent r))
     and d.status in ('succeeded', 'failed') and d.return_message is distinct from 'job startup timeout'
   order by d.jobid, d.runid desc),
failed as (
  select j.jobname, r.start_time, left(r.return_message, 200) as message
    from cron.job j join last_run r on r.jobid = j.jobid
   where r.status = 'failed' and j.jobname <> 'b2c-capacity')
select count(*) = 0 as ok,
       jsonb_build_object('failed_jobs', coalesce(jsonb_agg(jsonb_build_object('job', jobname, 'at', start_time, 'message', message) order by jobname), '[]'),
                          'subjects', coalesce(jsonb_agg(jobname order by jobname), '[]')) as value
  from failed

-- check: PLAT-01B
-- app: platform
-- kind: sql
-- severity: P2
-- cadence_s: 60
-- tags: cron
-- title: pg_cron could not start jobs (startup timeouts)
-- description: Runs ending in "job startup timeout" in the last 15 min above cron_startup_timeouts_15m; P1 from cron_startup_timeouts_p1_15m up. Usually connection-slot or worker saturation, so one incident for all jobs (D-008).
select count(*) <= (select one.threshold('cron_startup_timeouts_15m')) as ok,
       jsonb_build_object('timeouts_15m', count(*), 'jobs', coalesce(jsonb_agg(distinct j.jobname), '[]'),
         'severity', case when count(*) >= (select one.threshold('cron_startup_timeouts_p1_15m')) then 'P1' else 'P2' end) as value
  from cron.job_run_details d join cron.job j on j.jobid = d.jobid
 where d.runid > (select coalesce(max(x.runid), 0) - 20000 from cron.job_run_details x)
   and d.start_time > now() - interval '15 minutes' and d.return_message = 'job startup timeout'

-- check: PLAT-02
-- app: platform
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- tags: cron
-- title: A frequent cron job has gone silent
-- description: An active job scheduled every minute or faster (including pg_cron's "N seconds" schedules) has no run in job_silent_min minutes.
with recent as (
  select jobid from cron.job_run_details
   where runid > (select coalesce(max(x.runid), 0) - 20000 from cron.job_run_details x)
     and start_time > now() - make_interval(mins => (select one.threshold('job_silent_min'))::int) group by jobid)
select count(*) = 0 as ok, jsonb_build_object('silent_jobs', coalesce(jsonb_agg(j.jobname order by j.jobname), '[]'),
                                             'subjects', coalesce(jsonb_agg(j.jobname order by j.jobname), '[]')) as value
  from cron.job j left join recent r on r.jobid = j.jobid
 where j.active and (j.schedule ~ 'second' or j.schedule ~ '^\*(/1)? \* \* \* \*$') and r.jobid is null

-- check: PLAT-03
-- app: b2c
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- tags: cron
-- disabled: blocked:b2c_minute_report_not_persisted
-- title: Spark's minute tick reported a step error
-- description: The latest b2c-minute run's return message contains a key ending "_error". pg_cron records only "1 row" for a SELECT, so the report never reaches cron.job_run_details; off until Spark persists its report (D-007, proposal).
select coalesce(r.return_message !~ '_error', true) as ok,
       jsonb_build_object('at', r.start_time, 'message', left(r.return_message, 300)) as value
  from (select 1) x
  left join lateral (select d.start_time, d.return_message from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                      where j.jobname = 'b2c-minute' order by d.start_time desc limit 1) r on true

-- check: PLAT-04
-- app: platform
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- tags: http, jobs
-- title: A database-to-app job call was refused or failed
-- description: In the last 15 min, a pg_net response to a job call (Spark's ids in b2c.job_calls, Eduwit One's tick and AI worker calls in one.runs) had status 401, 403 or 500 and up, or no status at all (a timeout, a DNS, TLS or connection failure; M2 of the second review). Other apps' pg_net traffic (partner pushes, webhooks) is not job calls and is watched by their own checks. The website's web_job_call ids are not recorded anywhere (pg_cron keeps "1 row" for its SELECT, D-007), so its calls cannot be told apart; WEB-01 watches its outbox backlog instead (m14).
with ids as (
  select (e ->> 'id')::bigint as id, 'spark' as caller from b2c.job_calls c, jsonb_array_elements(c.calls) e
  union all
  select (r.report ->> 'app')::bigint, 'one' from one.runs r
   where r.kind = 'tick' and r.started_at > now() - interval '20 minutes' and r.report ->> 'app' ~ '^[0-9]+$'
  union all
  select (r.report #>> '{ai,request}')::bigint, 'one-ai' from one.runs r
   where r.kind = 'tick' and r.started_at > now() - interval '20 minutes' and r.report #>> '{ai,request}' ~ '^[0-9]+$')
select coalesce(sum(n), 0) = 0 as ok,
       jsonb_build_object('bad_calls', coalesce(sum(n), 0), 'by_caller', coalesce(jsonb_object_agg(caller, n), '{}')) as value
  from (select ids.caller, count(*) as n from ids join net._http_response h on h.id = ids.id
         where h.created > now() - interval '15 minutes' and (h.status_code is null or h.status_code in (401, 403) or h.status_code >= 500)
         group by ids.caller) b

-- check: PLAT-05
-- app: platform
-- kind: sql
-- severity: P1
-- cadence_s: 300
-- tags: config
-- title: An app's base URL or internal key is missing (its scheduled HTTP jobs do nothing)
-- description: b2c.settings.app.base_url, web_settings.internal_base_url and one.settings.app.base_url must be set, and Vault must hold b2c_internal_key, web_internal_key and one_internal_key (names only are read).
with v as (
  select nullif((select value ->> 'base_url' from b2c.settings where key = 'app'), '') as spark_url,
         nullif((select value #>> '{}' from public.web_settings where key = 'internal_base_url'), '') as web_url,
         nullif((select one.setting('app')) ->> 'base_url', '') as one_url,
         array(select k from unnest(array['b2c_internal_key', 'web_internal_key', 'one_internal_key']) k
                where not exists (select 1 from one.vault_names() v(name) where v.name = k)) as keys_missing)
select spark_url is not null and web_url is not null and one_url is not null and cardinality(keys_missing) = 0 as ok,
       jsonb_build_object('spark_base_url', spark_url is not null, 'web_internal_base_url', web_url is not null,
                          'one_base_url', one_url is not null, 'vault_missing', to_jsonb(keys_missing)) as value
  from v

-- check: PLAT-06
-- app: platform
-- kind: sql
-- severity: P2
-- cadence_s: 86400
-- tags: security
-- title: A security advisor-level problem exists (an app table or view readable by the API roles past RLS, or policies without RLS)
-- description: The ERROR-level Supabase lints computed in SQL for the apps' schemas (Supabase's own schemas excluded): a table the anon or authenticated role can read with RLS off, a table with policies while RLS is off, or a view the API roles can read that runs with its owner's rights (security_definer_view; the views present at install are the baseline, each tracked as a cleanup proposal; M10 of the second review). Also an API or Eduwit One role able to create objects in schema public, which would make WITTY-01's search_path unsafe (D-042). New WARN lints come from the Management API once a token is configured (Setup item supabase_advisors).
with exposed as (
  select n.oid, n.nspname from pg_namespace n
   where has_schema_privilege('anon', n.oid, 'USAGE')
     and n.nspname not in ('pg_catalog', 'information_schema', 'graphql', 'graphql_public', 'extensions', 'auth', 'storage', 'realtime',
                           'net', 'cron', 'vault', 'pgsodium', 'supabase_functions', 'supabase_migrations', 'pgbouncer', 'pgmq')),
bad as (
  select e.nspname || '.' || c.relname as rel, 'rls_disabled_in_public' as lint
    from pg_class c join exposed e on e.oid = c.relnamespace
   where c.relkind in ('r', 'p') and not c.relrowsecurity
     and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('authenticated', c.oid, 'SELECT'))
  union all
  select c.oid::regclass::text, 'policy_exists_rls_disabled'
    from pg_class c where c.relkind in ('r', 'p') and not c.relrowsecurity and exists (select 1 from pg_policy p where p.polrelid = c.oid)
  union all
  select v, 'security_definer_view' from one.security_definer_views() v
   where not coalesce((select b.value from one.baselines b where b.key = 'security_definer_views') ? v, false)
  union all
  select 'schema public: ' || r, 'create_on_public' from one.public_schema_writers() r)
select count(*) = 0 as ok,
       jsonb_build_object('count', count(*), 'items', coalesce(jsonb_agg(jsonb_build_object('lint', lint, 'table', rel) order by rel) filter (where rel is not null), '[]')) as value
  from bad

-- check: PLAT-07
-- app: platform
-- kind: sql
-- severity: P2
-- cadence_s: 86400
-- tags: security
-- title: A new anon- or authenticated-executable SECURITY DEFINER function appeared
-- description: one.privilege_audit() (run nightly) recorded a function outside the acknowledged baseline that the API roles can execute. Acknowledge it from the UI once reviewed.
select count(*) = 0 as ok,
       jsonb_build_object('unacknowledged', count(*), 'functions', coalesce(jsonb_agg(b.fn order by b.fn), '[]')) as value
  from one.privilege_baseline b
 where not b.acknowledged and b.last_seen > now() - interval '2 days'

-- check: PLAT-08
-- app: platform
-- kind: sql
-- severity: P2
-- cadence_s: 300
-- tags: code, integrity
-- title: public.lead_intake() changed since its baseline
-- description: md5 of lead_intake's source differs from the baseline captured at install. The website runbook's own canary: every app's intake goes through it.
select b.value ->> 'md5' is null or b.value ->> 'md5' = cur.md5 as ok,
       jsonb_build_object('current', cur.md5, 'baseline', b.value ->> 'md5', 'baseline_at', b.captured_at) as value
  from (select md5(string_agg(p.prosrc, '' order by p.oid)) as md5 from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = 'lead_intake') cur
  left join one.baselines b on b.key = 'lead_intake_md5'

-- check: PLAT-09
-- app: platform
-- kind: sql
-- severity: P3
-- cadence_s: 3600
-- tags: capacity
-- title: Database size, connections or the slowest query more than doubled in 24 h
-- description: Compares now with this check's own result from 23 to 25 h ago: database size, connection count, and the mean time of the slowest pg_stat_statements query (calls >= 50).
with cur as (
  select pg_database_size(current_database())::numeric as db_bytes,
         (select count(*) from pg_stat_activity)::numeric as conns,
         (select round(max(s.mean_exec_time)::numeric, 1) from extensions.pg_stat_statements s where s.calls >= 50) as top_mean_ms),
prev as (
  select r.value from one.results r
   where r.check_id = 'PLAT-09' and r.status in ('ok', 'fail') and r.ran_at between now() - interval '25 hours' and now() - interval '23 hours'
   order by r.ran_at desc limit 1)
select prev.value is null
       or (cur.db_bytes <= 2 * (prev.value ->> 'db_bytes')::numeric
           and cur.conns <= 2 * greatest((prev.value ->> 'conns')::numeric, 10)
           and coalesce(cur.top_mean_ms <= 2 * greatest((prev.value ->> 'top_mean_ms')::numeric, 50), true)) as ok,
       jsonb_build_object('db_bytes', cur.db_bytes, 'conns', cur.conns, 'top_mean_ms', cur.top_mean_ms,
                          'prev_db_bytes', prev.value ->> 'db_bytes', 'prev_conns', prev.value ->> 'conns', 'prev_top_mean_ms', prev.value ->> 'top_mean_ms') as value
  from cur left join prev on true
