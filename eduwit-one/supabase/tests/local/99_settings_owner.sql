-- The thresholds are the owner's, and a setting is saved only over the version the page loaded (migration 0039, D-137).
-- Sixteen P1 checks read one.settings.thresholds, so loosening one could silence a P1: an engineer is refused on both
-- doors (ui_settings_put and ui_settings_restore) and still reads the values; the owner changes and restores them. A
-- save that names a version which is no longer current is refused with 40001 and saves nothing. Local test cluster only.
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
create or replace function pg_temp.q(p_sql text) returns jsonb language plpgsql security definer as $$
declare v jsonb;
begin
  execute 'select to_jsonb(x) from (' || p_sql || ') x' into v;
  return v;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text), pg_temp.q(text) to authenticated, anon;
create or replace function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000c1"}', false)
$$;
create or replace function pg_temp.as_engineer() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000c2"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer() to authenticated;

delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002', 'email_code');

-- Earlier files leave the stored value without a version row of its own (a fixture written back directly), so the
-- value this file starts from is saved as a version first: a restore of that version must bring exactly it back.
select one.settings_put('thresholds', (select value from one.settings where key = 'thresholds') || '{"job_silent_min": 16}',
                        'test@eduwit.in', 'a version row for the value this file starts from');
create temp table t_thr as select value, version from one.settings where key = 'thresholds';
select (value || '{"job_silent_min": 600}')::text as thr_loose, (value || '{"job_silent_min": 25}')::text as thr_owner,
       version as thr_v from t_thr \gset
grant select on t_thr to authenticated;

-- 1. An engineer cannot loosen a threshold, by a save or by a restore -----------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L)', 'thresholds', :'thr_loose', 'quieter')) = '42501',
                  'an engineer cannot change the thresholds');
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L, null, %s)', 'thresholds', :'thr_loose', 'quieter', :thr_v)) = '42501',
                  'not with the right version either');
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_restore(%L, %s, %L)', 'thresholds', :thr_v, 'back')) = '42501',
                  'nor restore one of their versions');
select pg_temp.ok((one.ui_settings() -> 'thresholds' ->> 'owner_only')::boolean, 'the Settings page shows the thresholds as the owner''s');
select pg_temp.ok((one.ui_settings() -> 'thresholds' -> 'value') = (select value from t_thr), 'an engineer still reads them');
select pg_temp.ok(jsonb_array_length(one.ui_setting_versions('thresholds', 5)) >= 1, 'and their versions');
select pg_temp.ok(not (one.ui_settings() -> 'checks' ->> 'owner_only')::boolean, 'the check runner stays the engineers''');
reset role;
select pg_temp.ok((select version = :thr_v and value = (select value from t_thr) from one.settings where key = 'thresholds'),
                  'the refused calls changed nothing');

-- 2. The owner changes and restores them ------------------------------------------------------------------------------------
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok((one.ui_settings_put('thresholds', :'thr_owner', 'cron jobs are slower on Sundays', 'req-0039a', :thr_v) ->> 'version')::int = :thr_v + 1,
                  'the owner changes a threshold over the version the page loaded');
select pg_temp.ok((one.ui_settings_restore('thresholds', :thr_v, 'back to the earlier value', 'req-0039b') ->> 'version')::int = :thr_v + 2,
                  'and restores an earlier version');
reset role;
select pg_temp.ok((select value = (select value from t_thr) from one.settings where key = 'thresholds'), 'the restore brought the old value back');
select pg_temp.ok((select count(*) = 2 from one.audit where action = 'settings.put' and target = 'settings:thresholds'
                     and actor = 'connect@eduwit.in' and request_id in ('req-0039a', 'req-0039b')), 'both in the audit under the owner''s name');

-- 3. A version that is no longer current saves nothing (lost update) ----------------------------------------------------------
select version as thr_now from one.settings where key = 'thresholds' \gset
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L, null, %s)', 'thresholds', :'thr_owner', 'stale page', :thr_v)) = '40001',
                  'a save over an older version is refused with 40001');
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L, null, %s)', 'thresholds', :'thr_owner', 'future page', :thr_now + 5)) = '40001',
                  'and so is one over a version that does not exist');
reset role;
select pg_temp.ok((select version = :thr_now and value = (select value from t_thr) from one.settings where key = 'thresholds'),
                  'the refused saves changed nothing');
select value::text as checks_now, version as checks_v from one.settings where key = 'checks' \gset
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L, null, %s)', 'checks', (:'checks_now'::jsonb || '{"slow_ms": 6100}')::text, 'stale', :checks_v - 1)) = '40001',
                  'the same on an engineer''s key');
select pg_temp.ok((one.ui_settings_put('checks', (:'checks_now'::jsonb || '{"slow_ms": 6100}'), 'slower checks', null, :checks_v) ->> 'version')::int = :checks_v + 1,
                  'the current version saves');
select pg_temp.ok((one.ui_settings_put('checks', :'checks_now'::jsonb, 'back again') ->> 'ok')::boolean,
                  'and a save that names no version saves as before (the chat''s card, a restore)');
reset role;
select pg_temp.ok(has_function_privilege('authenticated', 'one.ui_settings_put(text,jsonb,text,text,integer)', 'execute')
                  and to_regprocedure('one.ui_settings_put(text,jsonb,text,text)') is null,
                  'one form of the function, executable by signed-in people');

drop table t_thr;
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
select 'SETTINGS OWNER PASSED';
