-- FIX-SENDQ-B2C and B2C-11 (migration 0037, D-134): the catalogue row and the fixer's one new right; the plan (B2C-07's
-- stuck_sending only, more than 50 opens a proposal); a dry run while it is off; the switch-on rule (two weeks of its own
-- dry runs); a real run through the fixer with a row before and after; the verdict; and Spark's health check and path.
-- Local cluster only; it tidies up after itself.
\set ON_ERROR_STOP 1
select set_config('one.history_writer', 'on', false);
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

truncate one.actions, one.proposals, one.incidents restart identity cascade;
create temp table t_fixes as select value from one.settings where key = 'fixes';
delete from one.results where check_id = 'B2C-07';
set role postgres;
create table public.stub_calls (id bigserial primary key, fn text, arg jsonb, at timestamptz default now());
reset role;

-- 1. The catalogue, the check and the fixer's right ----------------------------------------------------------------------
select pg_temp.ok((select mode = 'act' and app = 'b2c' and checks = '{B2C-07}' and app_functions = '{b2c.send_unstick(integer)}'
                     from one.fixes where id = 'FIX-SENDQ-B2C'), 'FIX-SENDQ-B2C acts on B2C-07 through b2c.send_unstick(integer) alone');
select pg_temp.ok((select auto_fix_id = 'FIX-SENDQ-B2C' and sql ~ 'stuck_sending' and sql ~ 'coalesce\(taken_at, not_before\)' from one.checks where id = 'B2C-07'),
                  'B2C-07 counts messages stuck mid-send and names the fix');
select pg_temp.ok(has_function_privilege('eduwit_one_fixer', 'b2c.send_unstick(integer)', 'EXECUTE'), 'the fixer may call b2c.send_unstick');
select pg_temp.ok((select pg_get_userbyid(proowner) = 'eduwit_one_fixer' and prosecdef from pg_proc where oid = 'one.fixer_b2c_sendq()'::regprocedure),
                  'through a function the fixer owns');
select pg_temp.ok(not has_function_privilege('authenticated', 'one.fixer_b2c_sendq()', 'EXECUTE')
                  and not has_function_privilege('service_role', 'one.fixer_b2c_sendq()', 'EXECUTE')
                  and not has_function_privilege('eduwit_one_reader', 'one.fixer_b2c_sendq()', 'EXECUTE'), 'which no API role and not the reader can call');
select pg_temp.ok((select (value #>> '{FIX-SENDQ-B2C,enabled}')::boolean = false and (value #>> '{FIX-SENDQ-B2C,per_tick}')::int = 50
                          and (value #>> '{FIX-SENDQ-B2C,cooldown_min}')::int = 30 from one.settings where key = 'fixes'), 'it ships switched off, 50 messages a run');
select pg_temp.ok((select kind = 'http' and severity = 'P1' and cadence_s = 300 and open_after = 2 and enabled and sql is null and app = 'b2c'
                     from one.checks where id = 'B2C-11'), 'B2C-11 is the app''s P1 http check on Spark''s health, every 5 minutes');
select pg_temp.ok(one.setting('health_paths') ->> 'spark' = '/api/health', 'the probe reads Spark''s /api/health');
select pg_temp.ok((select description ~ 'ok when Spark can work' from one.checks where id = 'HB-spark'), 'HB-spark says what its reading means');

-- 2. The plan: stuck_sending only ----------------------------------------------------------------------------------------
select one.open_or_touch_incident('B2C-07', 'P2', '{"status": "fail", "value": {"queue_stuck": 0, "stuck_sending": 3, "leads_over_1_today": 0}}');
select id as i7 from one.incidents where check_id = 'B2C-07' \gset
select one.fix_run('FIX-SENDQ-B2C', :i7, true, 'sql:test') as d1 \gset
select pg_temp.ok((:'d1'::jsonb ->> 'dry_run')::boolean, 'a dry run: ' || :'d1');
select pg_temp.ok((select (target ->> 'stuck_sending')::int = 3 and (target ->> 'count')::int = 3 and result ->> 'would' ~ 'send_unstick\(15\)'
                          and result ->> 'would' ~ 'never sent again' from one.actions where id = (:'d1'::jsonb ->> 'action')::bigint),
                  'it would mark the three stuck messages failed, never resent');
select pg_temp.ok((select count(*) = 0 from public.stub_calls), 'a dry run calls nothing in Spark');
update one.incidents set evidence = '{"status": "fail", "value": {"queue_stuck": 0, "stuck_sending": 0, "leads_over_1_today": 2}}' where id = :i7;
select pg_temp.ok(one.fix_run('FIX-SENDQ-B2C', :i7, true, 'sql:test') ->> 'why_not' ~ 'no message stuck mid-send', 'a pacing finding is a person''s, not the fix''s');
update one.incidents set evidence = '{"status": "error", "value": null}' where id = :i7;
select pg_temp.ok(one.fix_run('FIX-SENDQ-B2C', :i7, true, 'sql:test') ->> 'why_not' ~ 'could not run', 'nor a run of B2C-07 that could not read');
update one.incidents set evidence = '{"status": "fail", "value": {"queue_stuck": 0, "stuck_sending": 3}}' where id = :i7;

-- 3. The switch-on rule: the window over, still two weeks of its own dry runs ------------------------------------------------
update one.settings set value = value || jsonb_build_object('observation_started_at', now() - interval '30 days') where key = 'fixes';
select pg_temp.ok(pg_temp.err(format($q$select one.settings_put('fixes', %L, 'test', 'on too early')$q$,
                    jsonb_set((select value from one.settings where key = 'fixes'), '{FIX-SENDQ-B2C,enabled}', 'true'))) = '22023',
                  'not switched on while its first dry run is younger than 14 days (D-134)');
update one.actions set ran_at = now() - interval '15 days' where fix_id = 'FIX-SENDQ-B2C' and dry_run;
select one.settings_put('fixes', jsonb_set((select value from one.settings where key = 'fixes'), '{FIX-SENDQ-B2C,enabled}', 'true'), 'test', 'two weeks of dry runs') as v \gset
select pg_temp.ok((select (value #>> '{FIX-SENDQ-B2C,enabled}')::boolean from one.settings where key = 'fixes'), 'switched on with two weeks of dry runs');
update one.actions set ran_at = now() where fix_id = 'FIX-SENDQ-B2C' and dry_run;
select pg_temp.ok(pg_temp.err(format($q$select one.settings_check('fixes', %L)$q$,
                    jsonb_set((select value from one.settings where key = 'fixes'), '{FIX-SENDQ-B2C,cooldown_min}', '20'))) = 'ok',
                  'a fix already on is not judged again when another value changes');

-- 4. Over the limit: a proposal, nothing done -----------------------------------------------------------------------------
update one.incidents set evidence = '{"status": "fail", "value": {"stuck_sending": 60}}' where id = :i7;
select one.fix_run('FIX-SENDQ-B2C', :i7, false, 'one') as o1 \gset
select pg_temp.ok(:'o1'::jsonb ->> 'skipped' = 'over_limit' and (:'o1'::jsonb ->> 'proposal') is not null, '60 stuck messages open a proposal: ' || :'o1');
select pg_temp.ok((select count(*) = 0 from public.stub_calls), 'and call nothing');
select pg_temp.ok((select risk = 'high' and kind = 'fix' and app = 'b2c' and source_key like 'fix:FIX-SENDQ-B2C:%' from one.proposals), 'a high-risk proposal for the owner');
update one.actions set ran_at = ran_at - interval '1 day' where fix_id = 'FIX-SENDQ-B2C' and not dry_run;
update one.incidents set evidence = '{"status": "fail", "value": {"queue_stuck": 0, "stuck_sending": 3}}' where id = :i7;

-- 5. A real run through the fixer, a row before and after ---------------------------------------------------------------------
select one.fix_run('FIX-SENDQ-B2C', :i7, false, 'one') as r1 \gset
select pg_temp.ok(:'r1'::jsonb ->> 'status' = 'done', 'a real run: ' || :'r1');
select pg_temp.ok((select count(*) = 1 from public.stub_calls where fn = 'b2c.send_unstick' and arg = '15'), 'it called b2c.send_unstick(15) once');
select pg_temp.ok((select array_agg(step order by id) = array['skip', 'before', 'after'] from one.actions where fix_id = 'FIX-SENDQ-B2C' and not dry_run),
                  'with a row before and after (after the over-limit skip)');
select pg_temp.ok((select (result ->> 'marked_failed')::int = 3 and verify_at > now() from one.actions where fix_id = 'FIX-SENDQ-B2C' and step = 'after'),
                  'it records what Spark marked, and is judged later');
select pg_temp.ok(one.fix_run('FIX-SENDQ-B2C', :i7, false, 'one') ->> 'skipped' in ('waiting for the verdict on its last run', 'cooldown'), 'no second run before the verdict');

-- 6. The verdict: nothing stuck any more, B2C-07 failing on a pacing rule only: held -------------------------------------------
update one.actions set verify_at = now() - interval '1 minute', ran_at = now() - interval '3 minutes'
 where fix_id = 'FIX-SENDQ-B2C' and step = 'after' and not dry_run;
insert into one.results (check_id, ran_at, status, value) values ('B2C-07', now(), 'fail', '{"queue_stuck": 0, "stuck_sending": 0, "leads_over_1_today": 1}');
select one.fix_verify_due() as v1 \gset
select pg_temp.ok((select status = 'done' and (result ->> 'held')::boolean and result ->> 'why' ~ 'another reason'
                     from one.actions where fix_id = 'FIX-SENDQ-B2C' and step = 'verify'), 'it held: B2C-07 still fails, for another reason');
select pg_temp.ok((select severity = 'P2' and not ('fix_failed' = any (tags)) from one.incidents where id = :i7), 'and the incident was not escalated');
select pg_temp.ok(not exists (select 1 from one.actions where target::text ~ '91000|@' or result::text ~ '91000|@'), 'no phone or address in the history');

-- Tidy up ----------------------------------------------------------------------------------------------------------------
truncate one.actions, one.proposals, one.incidents restart identity cascade;
update one.settings s set value = t.value from t_fixes t where s.key = 'fixes';
delete from one.results where check_id = 'B2C-07';
set role postgres;
drop table public.stub_calls;
reset role;
