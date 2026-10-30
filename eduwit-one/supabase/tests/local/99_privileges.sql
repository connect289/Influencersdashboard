-- Acknowledging a privilege is the owner's (migration 0030, D-110): PLAT-07 passes once every API-executable SECURITY
-- DEFINER function is acknowledged, so an engineer, a stranger who signed up and anon are refused; the owner's
-- acknowledgement is recorded with the owner's name and an audit row. Local test cluster only.
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
-- Signed up through the open sign-up, with a live session, and nothing in one.users.
create or replace function pg_temp.as_stranger() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000003", "session_id": "00000000-0000-0000-0000-0000000000c3"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer(), pg_temp.as_stranger() to authenticated;

delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in'), ('00000000-0000-0000-0000-000000000003', 'someone@example.com');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-000000000003');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002', 'email_code');
delete from one.privilege_baseline where fn like 'public.audit_probe_%';
insert into one.privilege_baseline (fn, schema, roles, acknowledged) values ('public.audit_probe_new()', 'public', '{authenticated}', false);
create temp table t_audit as select coalesce(max(id), 0) as id from one.audit;

-- 1. Nobody but the owner ------------------------------------------------------------------------------------------------
set role anon;
select pg_temp.ok(pg_temp.err($q$select one.ui_privilege_ack('public.audit_probe_new()')$q$) = '42501', 'anon cannot acknowledge');
reset role;
set role authenticated;
select pg_temp.as_stranger();
select pg_temp.ok(pg_temp.err($q$select one.ui_privilege_ack('public.audit_probe_new()')$q$) = '42501', 'a stranger who signed up cannot acknowledge');
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_privilege_ack('public.audit_probe_new()')$q$) = '42501', 'an engineer cannot acknowledge (0030)');
select pg_temp.ok(pg_temp.err($q$select one.ui_privileges()$q$) = 'ok', 'an engineer still reads the Privileges page');
reset role;
select pg_temp.ok(not (pg_temp.q($q$select acknowledged from one.privilege_baseline where fn = 'public.audit_probe_new()'$q$) ->> 'acknowledged')::boolean,
                  'the refused calls changed nothing');

-- 2. The owner -------------------------------------------------------------------------------------------------------------
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok((one.ui_privilege_ack('public.audit_probe_new()', 'req-0030') ->> 'ok')::boolean, 'the owner acknowledges');
reset role;
select pg_temp.ok((pg_temp.q($q$select acknowledged and acknowledged_by = 'connect@eduwit.in' as v from one.privilege_baseline where fn = 'public.audit_probe_new()'$q$) ->> 'v')::boolean,
                  'recorded with the owner''s name');
select pg_temp.ok(exists (select 1 from one.audit a where a.id > (select id from t_audit) and a.action = 'privilege.acknowledge'
                            and a.target = 'function:public.audit_probe_new()' and a.actor = 'connect@eduwit.in' and a.request_id = 'req-0030'),
                  'and in the audit');

delete from one.privilege_baseline where fn like 'public.audit_probe_%';
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
select 'PRIVILEGES PASSED';
