-- Phase 4 sign-in (spec §13, migration 0009): the allow-list, the emailed code, trusted devices, roles, revocation.
-- PostgREST's JWT is simulated with request.jwt.claims. Local test cluster only.
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
-- As a role, under a JWT for a user and session, runs a statement and says whether it was refused (42501).
create or replace function pg_temp.denied(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then return true;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.denied(text) to authenticated, anon, service_role;
-- The gate is called by the UI functions (0010), not by clients; for this test only, authenticated may call it
-- directly, so a refusal below comes from the gate itself and not from a missing grant. Revoked at the end.
grant execute on function one.ui_require(text) to authenticated;

delete from one.sign_in_log; delete from one.trusted_devices; delete from one.session_checks; delete from one.email_codes;
delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'Connect@eduwit.in'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in'),
  ('00000000-0000-0000-0000-000000000003', 'someone@gmail.com');
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000002'),
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000003'),
  ('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000001');
insert into one.users (user_id, email, role) values
  ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');

-- 1. Signed in with Google, before the second step: known, but nothing is readable -----------------------------------
set role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000a1"}', false);
select pg_temp.ok((select (m ->> 'known')::boolean and m ->> 'role' = 'owner' and not (m ->> 'checked')::boolean and m ->> 'email' = 'connect@eduwit.in'
                     from (select one.me() as m) x), 'the owner is known, not yet checked');
select pg_temp.ok(pg_temp.denied('select one.ui_require(''read'')'), 'nothing is readable before the second step');
select pg_temp.ok(pg_temp.denied('select one.auth_issue_code(one.uid(), one.session_id())'), 'a signed-in user cannot issue codes');

-- 2. The code: issued by the service role, stored hashed, five tries -------------------------------------------------
reset role;
set role service_role;
select one.auth_issue_code('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1') as code \gset
select pg_temp.ok(:'code' ~ '^[0-9]{6}$', 'a 6-digit code');
reset role;
select pg_temp.ok(not exists (select 1 from one.email_codes where code_hash = :'code' or salt = :'code'), 'only a salted hash is stored');
set role authenticated;
select pg_temp.ok((select (r ->> 'ok')::boolean = false and (r ->> 'left')::int = 4 from (select one.auth_verify_code('000000x', false, 'test') as r) x), 'a wrong code: 4 tries left');
select pg_temp.ok((select (r ->> 'ok')::boolean and length(r ->> 'device_token') = 64 from (select one.auth_verify_code(:'code', true, 'test browser') as r) x),
                  'the right code checks the session and trusts the browser');
select pg_temp.ok((select (one.me() ->> 'checked')::boolean), 'the session is checked');
select pg_temp.ok(one.ui_require('read') = 'connect@eduwit.in' and one.ui_require('owner') = 'connect@eduwit.in', 'the owner reads and owns');
reset role;
select pg_temp.ok((select count(*) = 1 from one.trusted_devices where user_id = '00000000-0000-0000-0000-000000000001' and length(token_hash) = 64),
                  'the device token is kept as a hash');

-- 3. A trusted device skips the code on a new session ---------------------------------------------------------------
create temp table t_tok as select encode(sha256(convert_to('x', 'UTF8')), 'hex') as h;
set role service_role;
select one.auth_issue_code('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a4') as code4 \gset
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000a4"}', false);
select pg_temp.ok(not one.auth_device_check(repeat('a', 64)), 'an unknown device token is refused');
select pg_temp.ok(pg_temp.denied('select one.ui_require(''read'')'), 'the new session is not checked yet');
select one.auth_verify_code(:'code4', true, 'second browser') ->> 'device_token' as token4 \gset
select one.auth_sign_out();
select pg_temp.ok(pg_temp.denied('select one.ui_require(''read'')'), 'signing out ends the second step');
select pg_temp.ok(one.auth_device_check(:'token4'), 'the trusted device checks the session again');
select pg_temp.ok(one.ui_require('read') = 'connect@eduwit.in', 'and the session reads');

-- 4. The engineer reads and operates, never owns ----------------------------------------------------------------------
reset role;
set role service_role;
select one.auth_issue_code('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a2') as code2 \gset
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000a2"}', false);
select one.auth_verify_code(:'code2', false, null);
select pg_temp.ok(one.ui_require('operate') = 'eng@eduwit.in', 'the engineer operates');
select pg_temp.ok(pg_temp.denied('select one.ui_require(''owner'')'), 'the engineer does not own');
select pg_temp.ok(pg_temp.denied('select one.ui_require(''anything'')'), 'an unknown permission is refused');

-- 5. Revoked session, inactive user, outsider ------------------------------------------------------------------------
reset role;
delete from auth.sessions where id = '00000000-0000-0000-0000-0000000000a2';
set role authenticated;
select pg_temp.ok(pg_temp.denied('select one.ui_require(''read'')'), 'a session signed out elsewhere reads nothing, although its JWT is valid');
reset role;
update one.users set is_active = false where email = 'connect@eduwit.in';
set role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000a4"}', false);
select pg_temp.ok(pg_temp.denied('select one.ui_require(''read'')'), 'an inactive user reads nothing');
reset role;
update one.users set is_active = true where email = 'connect@eduwit.in';
set role service_role;
select pg_temp.ok(pg_temp.denied('select one.auth_issue_code(''00000000-0000-0000-0000-000000000003'', ''00000000-0000-0000-0000-0000000000a3'')'),
                  'no code for a Supabase user outside the allow-list');
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000003", "session_id": "00000000-0000-0000-0000-0000000000a3"}', false);
select pg_temp.ok((select not (one.me() ->> 'known')::boolean), 'an outsider is not known');
select pg_temp.ok(pg_temp.denied('select one.ui_require(''read'')'), 'and reads nothing');
reset role;

-- 6. Five codes an hour; five tries per code ---------------------------------------------------------------------------
set role service_role;
do $$ begin
  for i in 1..4 loop perform one.auth_issue_code('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a2'); end loop;
  perform one.auth_issue_code('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a2');
  raise exception 'ASSERT FAILED: a sixth code in an hour was issued';
exception when program_limit_exceeded then null;
end $$;
reset role;

-- 7. anon reaches nothing in schema one ------------------------------------------------------------------------------------
set role anon;
select pg_temp.ok(pg_temp.denied('select one.me()'), 'anon cannot call one.me()');
reset role;
select set_config('request.jwt.claims', '', false);

revoke execute on function one.ui_require(text) from authenticated;
delete from one.sign_in_log; delete from one.trusted_devices; delete from one.session_checks; delete from one.email_codes;
