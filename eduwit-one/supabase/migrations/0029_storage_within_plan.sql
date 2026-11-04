-- 0029 storage within the plan (D-103). Found on 30 Oct 2026 during the estate audit: production is on Supabase's FREE
-- plan, which turns the whole project READ-ONLY once the database passes 500 MB (every app stops saving: leads, Witty's
-- messages, the CRMs). It held 394 MB that day, and Eduwit One was its main grower: one.results 74 MB (about 40,000
-- rows a day, ok results kept 14 days, failures 90), one.runs 18 MB (one report a minute, 30 days), one.events 10 MB
-- (180 days). At those rates Eduwit One alone would have settled near 590 MB. What changes:
--   1. one.retention(): ok results 2 days, failures and errors 14, copied events 30, and the tick reports and the
--      app_report audit rows by setting (runs_days 7, app_report_days 7) instead of a fixed 30 days. Every value is a
--      versioned setting (Settings, retention), restorable, and the checks read 26 hours of history at most.
--   2. The retention and thresholds settings carry the new values as seed versions while their rows are still the
--      seed's (a person's edit wins).
--   3. PLAT-10, a new check: the database's size against the plan's limit (thresholds db_size_limit_mb 500,
--      db_size_warn_pct 80 as a P2, db_size_crit_pct 90 as a P1), every 15 minutes. Seeded here with the statement 0006
--      carries (a unit test keeps them equal).
--   4. One pass of the new retention now, so the space is reusable at once (deleted rows are reused by new ones;
--      the files do not shrink without a VACUUM FULL, which this migration does not run).
--   5. Load: Eduwit One's checks spent about 9.5 s of database time a minute on this small, stalling instance, 57 % of
--      it in B2C-01 (Spark's timers), whose per-job lookups walked pg_cron's history once per job (9.2 s median, 12 s
--      cold). B2C-01 now reads the same window in one pass (0.08 s warm, 0.14 s cold; the same answer job by job, checked
--      on production 30 Oct). Seeded here with the statement 0006 carries.
-- Nothing of the five apps is touched; only schema one. Rollback: 0029_storage_within_plan.rollback.sql.

create or replace function one.retention() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('retention'), '{}');
  v_results integer;
  v_events integer;
  v_calls integer;
  v_ok integer;
  v_audit integer;
  v_chat integer;
begin
  -- The histories are append-only (D-085); this is the one step that may prune them.
  perform set_config('one.history_writer', 'on', true);
  -- Two tiers: ok results repeat the value before them and are kept ok_results_days (2 since 0029; 14 before); failures
  -- and errors stay results_days (14 since 0029; 90 before) for the incident pages and the comparisons (efficiency
  -- review 10; D-103: the Free plan's 500 MB database limit).
  delete from one.results where status = 'ok' and ran_at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'ok_results_days')::int, 2)));
  get diagnostics v_ok = row_count;
  delete from one.results where ran_at < now() - make_interval(days => coalesce((v_cfg ->> 'results_days')::int, 14));
  get diagnostics v_results = row_count;
  -- The app's minute-by-minute report rows (one per tick) are kept app_report_days (7; 30 before 0029); a person's
  -- audit rows are kept for good.
  delete from one.audit where action = 'app_report' and at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'app_report_days')::int, 7)));
  get diagnostics v_audit = row_count;
  delete from one.email_codes where created_at < now() - interval '7 days';
  delete from one.sign_in_log where at < now() - interval '365 days';
  delete from one.events where occurred_at < now() - make_interval(days => coalesce((v_cfg ->> 'events_days')::int, 30));
  get diagnostics v_events = row_count;
  delete from one.ai_calls where created_at < now() - make_interval(days => coalesce((v_cfg ->> 'ai_calls_days')::int, 365));
  get diagnostics v_calls = row_count;
  -- The tick and nightly reports are kept runs_days (7; 30 before 0029): the checks read 26 hours of them at most.
  delete from one.runs where started_at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'runs_days')::int, 7)));
  -- Conversations with the command centre (0021) and their actions go with their thread.
  delete from one.chat_threads where updated_at < now() - make_interval(days => coalesce((v_cfg ->> 'chat_days')::int, 90));
  get diagnostics v_chat = row_count;
  perform set_config('one.history_writer', 'off', true);
  return jsonb_build_object('results', v_results + v_ok, 'ok_results', v_ok, 'events', v_events, 'ai_calls', v_calls, 'audit', v_audit, 'chat_threads', v_chat);
end $$;

-- 2. The settings, as seed versions while their rows are still the seed's.
do $$
declare
  v_row one.settings;
begin
  select * into v_row from one.settings where key = 'retention';
  if not found then
    raise exception '0029: no retention setting; 0007 must be applied first';
  end if;
  if v_row.actor <> 'seed' then
    raise notice '0029: the retention setting was changed by % (version %), so it is left as it is; one.retention() uses the new defaults only for keys it lacks', v_row.actor, v_row.version;
  else
    perform one.settings_put('retention', v_row.value || '{"results_days": 14, "events_days": 30, "ok_results_days": 2, "runs_days": 7, "app_report_days": 7}',
                             'seed', 'D-103 (0029): history kept within the Free plan''s 500 MB database limit');
  end if;
  select * into v_row from one.settings where key = 'thresholds';
  if not found then
    raise exception '0029: no thresholds setting; 0007 must be applied first';
  end if;
  if v_row.actor <> 'seed' then
    raise notice '0029: the thresholds setting was changed by % (version %), so it is left as it is; PLAT-10 uses its defaults (500 MB, 80 %%, 90 %%) until they are set', v_row.actor, v_row.version;
  else
    perform one.settings_put('thresholds', '{"db_size_limit_mb": 500, "db_size_warn_pct": 80, "db_size_crit_pct": 90}' || v_row.value,
                             'seed', 'D-103 (0029): PLAT-10, the database size against the plan''s limit');
  end if;
end $$;

-- 3. PLAT-10, as 0006 now seeds it.
select one.seed_check(jsonb_build_object(
  'id', 'PLAT-10',
  'app', 'platform',
  'kind', 'sql',
  'severity', 'P1',
  'cadence_s', 900,
  'open_after', 1,
  'resolve_after', 3,
  'title', 'The database is close to its plan''s size limit (the Free plan turns the whole project read-only above 500 MB)',
  'description', 'The sum of pg_database_size over the cluster''s databases (how Supabase counts the quota) against db_size_limit_mb (500, the Free plan): fails at db_size_warn_pct (80) as a P2 and at db_size_crit_pct (90) as a P1. Above the limit Supabase stops every write of every app until space is freed or the plan is upgraded (D-103).',
  'auto_fix_id', null,
  'tags', '["capacity"]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with cfg as (
  select coalesce((select one.threshold('db_size_limit_mb')), 500)::numeric as limit_mb,
         coalesce((select one.threshold('db_size_warn_pct')), 80)::numeric as warn_pct,
         coalesce((select one.threshold('db_size_crit_pct')), 90)::numeric as crit_pct),
cur as (select sum(pg_database_size(d.datname))::numeric / 1048576 as mb from pg_database d)
select cur.mb < cfg.limit_mb * cfg.warn_pct / 100 as ok,
       jsonb_build_object('db_mb', round(cur.mb), 'limit_mb', cfg.limit_mb, 'used_pct', round(100 * cur.mb / cfg.limit_mb, 1),
                          'severity', case when cur.mb >= cfg.limit_mb * cfg.crit_pct / 100 then 'P1' else 'P2' end) as value
  from cfg, cur
$sql$));

-- 5. B2C-01 in one pass, as 0006 now seeds it.
select one.seed_check(jsonb_build_object(
  'id', 'B2C-01',
  'app', 'b2c',
  'kind', 'sql',
  'severity', 'P1',
  'cadence_s', 60,
  'open_after', 1,
  'resolve_after', 3,
  'title', 'Spark''s timers or its answers to them are failing',
  'description', 'Direct read of system_health''s "timers" and "app" checks: no b2c-* job at all, a b2c-* job whose latest finished run failed (a run in progress is ignored; startup timeouts excluded, see PLAT-01B; b2c-capacity left to B2C-10), or a Spark job call answered with an error status in the last hour. Reads the newest cron_scan_runs runs through the runid key in one pass for all of Spark''s jobs (M3, M7 of the second review; one pass since 0029, D-103: the per-job lookups took 9 s a minute).',
  'auto_fix_id', null,
  'tags', '["cron"]'::jsonb,
  'enabled', true,
  'disabled_reason', null,
  'search_path', '',
  'sql', $sql$
with w as (select coalesce(max(runid), 0) - (select one.threshold('cron_scan_runs'))::bigint as from_runid from cron.job_run_details),
timers as (select j.jobid, j.jobname from cron.job j where j.jobname like 'b2c-%' and j.jobname <> 'b2c-capacity' and j.active),
last_run as (
  select distinct on (d.jobid) d.jobid, d.status
    from cron.job_run_details d, w
   where d.runid > w.from_runid and d.jobid in (select t.jobid from timers t)
     and d.status in ('succeeded', 'failed') and d.return_message is distinct from 'job startup timeout'
   order by d.jobid, d.runid desc),
jobs as (select t.jobname, r.status as last_status from timers t left join last_run r on r.jobid = t.jobid),
calls as (
  select count(*) as failed from b2c.job_calls c, jsonb_array_elements(c.calls) e join net._http_response r on r.id = (e ->> 'id')::bigint
   where r.created > now() - interval '1 hour' and (r.status_code is null or r.status_code >= 400))
select (select count(*) from jobs) > 0 and not exists (select 1 from jobs where last_status = 'failed') and (select failed from calls) = 0 as ok,
       jsonb_build_object('timers', (select count(*) from jobs),
                          'failed_jobs', (select coalesce(jsonb_agg(jobname order by jobname), '[]') from jobs where last_status = 'failed'),
                          'subjects', (select coalesce(jsonb_agg(jobname order by jobname), '[]') from jobs where last_status = 'failed'),
                          'failed_calls_1h', (select failed from calls)) as value
$sql$));

-- 4. One pass of the new retention.
select one.retention();

call one.apply_grants();
