-- Storage within the plan (migration 0029, D-103): Eduwit One's history kept by setting within the Free plan's 500 MB
-- database limit, and PLAT-10, the database's size against the plan's limit. Local cluster only.
\set ON_ERROR_STOP 1
do $$ begin
  if current_database() <> 'rehearsal' or to_regclass('public.stub_health') is null then
    raise exception 'refused: this test rewrites fixtures and runs only on the local test cluster';
  end if;
end $$;
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;
create or replace function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;

-- 1. The settings carry 0029's values, and the new keys are validated like the others.
select pg_temp.ok((select (value ->> 'ok_results_days')::int = 2 and (value ->> 'results_days')::int = 14 and (value ->> 'events_days')::int = 30
                          and (value ->> 'runs_days')::int = 7 and (value ->> 'app_report_days')::int = 7
                     from one.settings where key = 'retention'),
                  'retention carries the 0029 values: ' || (select value::text from one.settings where key = 'retention'));
select pg_temp.ok((select (value ->> 'db_size_limit_mb')::int = 500 and (value ->> 'db_size_warn_pct')::int = 80 and (value ->> 'db_size_crit_pct')::int = 90
                     from one.settings where key = 'thresholds'), 'thresholds carry PLAT-10''s keys');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('retention', '{"runs_days": 0}')$q$) = '22023', 'runs_days is at least 1');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('retention', '{"runs_days": 1, "app_report_days": 1}')$q$) = 'ok', 'runs_days and app_report_days of 1 are accepted');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('retention', '{"results_days": 6}')$q$) = '22023', 'failures are still kept at least 7 days');

-- 2. One pass of retention keeps exactly what the settings say.
create temp table t_ret as select value from one.settings where key = 'retention';
insert into one.results (check_id, status, ran_at, value) values
  ('CAT-04', 'ok',   now() - interval '3 days',  '{"t": "0029-ok-old"}'),
  ('CAT-04', 'ok',   now() - interval '1 day',   '{"t": "0029-ok-new"}'),
  ('CAT-04', 'fail', now() - interval '3 days',  '{"t": "0029-fail-new"}'),
  ('CAT-04', 'fail', now() - interval '15 days', '{"t": "0029-fail-old"}');
insert into one.runs (kind, bucket, started_at, finished_at, report) values
  ('tick', date_trunc('minute', now() - interval '8 days'), now() - interval '8 days', now() - interval '8 days', '{"t": "0029-run-old"}'),
  ('tick', date_trunc('minute', now() - interval '6 days'), now() - interval '6 days', now() - interval '6 days', '{"t": "0029-run-new"}');
insert into one.audit (at, actor, action, target) values
  (now() - interval '8 days', 'one', 'app_report', '0029-report-old'),
  (now() - interval '6 days', 'one', 'app_report', '0029-report-new'),
  (now() - interval '8 days', 'test@eduwit.in', 'settings.update', '0029-person-old');
select one.retention() as r1 \gset
select pg_temp.ok(not exists (select 1 from one.results where value ->> 't' = '0029-ok-old')
                  and exists (select 1 from one.results where value ->> 't' = '0029-ok-new'),
                  'ok results older than ok_results_days (2) go, younger stay: ' || :'r1');
select pg_temp.ok(exists (select 1 from one.results where value ->> 't' = '0029-fail-new')
                  and not exists (select 1 from one.results where value ->> 't' = '0029-fail-old'),
                  'failures stay results_days (14), older go');
select pg_temp.ok(not exists (select 1 from one.runs where report ->> 't' = '0029-run-old')
                  and exists (select 1 from one.runs where report ->> 't' = '0029-run-new'), 'tick reports older than runs_days (7) go');
select pg_temp.ok(not exists (select 1 from one.audit where target = '0029-report-old')
                  and exists (select 1 from one.audit where target = '0029-report-new')
                  and exists (select 1 from one.audit where target = '0029-person-old'),
                  'app_report rows older than app_report_days (7) go; a person''s audit rows stay');
-- A longer setting keeps more: runs_days 10 keeps an 8-day-old report.
insert into one.runs (kind, bucket, started_at, finished_at, report) values
  ('tick', date_trunc('minute', now() - interval '8 days') + interval '1 minute', now() - interval '8 days', now() - interval '8 days', '{"t": "0029-run-kept"}');
select one.settings_put('retention', (select value from t_ret) || '{"runs_days": 10}', 'test@eduwit.in', 'keep runs 10 days');
select one.retention();
select pg_temp.ok(exists (select 1 from one.runs where report ->> 't' = '0029-run-kept'), 'runs_days 10 keeps an 8-day-old report');
select one.settings_put('retention', (select value from t_ret), 'test@eduwit.in', 'restore');
select set_config('one.history_writer', 'on', false);
delete from one.runs where report ->> 't' like '0029-%';
delete from one.results where value ->> 't' like '0029-%';
delete from one.audit where target like '0029-%';
select set_config('one.history_writer', 'off', false);

-- 3. PLAT-10: ok on a small database, a P2 between the warning and the critical share, a P1 above it.
select pg_temp.ok((select severity = 'P1' and cadence_s = 900 and enabled from one.checks where id = 'PLAT-10'), 'PLAT-10 is seeded: P1, every 15 minutes, on');
create temp table t_thr as select value from one.settings where key = 'thresholds';
select one.run_check_safe('PLAT-10');
select pg_temp.ok((select last_status = 'ok' from one.check_state where check_id = 'PLAT-10'), 'a small database passes');
select one.settings_put('thresholds', (select value from t_thr)
         || jsonb_build_object('db_size_limit_mb', round((select sum(pg_database_size(datname))::numeric / 1048576 from pg_database) / 0.85, 3)),
       'test@eduwit.in', 'the database at 85 % of the limit');
select one.run_check_safe('PLAT-10');
select pg_temp.ok((select severity = 'P2' from one.incidents where check_id = 'PLAT-10' and resolved_at is null),
                  'at 85 % of the limit PLAT-10 opens a P2: ' || coalesce((select value::text from one.results where check_id = 'PLAT-10' order by id desc limit 1), 'no result'));
select one.settings_put('thresholds', (select value from t_thr) || '{"db_size_limit_mb": 1}', 'test@eduwit.in', 'the database far above the limit');
select one.run_check_safe('PLAT-10');
select pg_temp.ok((select severity = 'P1' from one.incidents where check_id = 'PLAT-10' and resolved_at is null), 'above the critical share it becomes a P1');
select pg_temp.ok((select (value ->> 'used_pct')::numeric > 100 and (value ->> 'limit_mb')::numeric = 1 from one.results where check_id = 'PLAT-10' order by id desc limit 1),
                  'its value says how full the database is');
select one.settings_put('thresholds', (select value from t_thr), 'test@eduwit.in', 'restore');
update one.incidents set resolved_at = now(), resolved_by = 'test', resolution = 'manual' where check_id = 'PLAT-10' and resolved_at is null;
select 'storage tests passed' as result;
