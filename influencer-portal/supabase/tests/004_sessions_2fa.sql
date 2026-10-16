-- Staff emailed-code 2FA, trusted devices, session registration, remote logout, creator account linking.
begin;
\ir _helpers.psql
select plan(26);

-- A staff member who has just signed in: session not registered yet.
insert into tests.people select 'sam', u, gen_random_uuid(), null from tests.create_user('sam@staff.test') u;
insert into inf.staff_profiles (user_id, full_name, email) select user_id, 'Sam', 'sam@staff.test' from tests.people where label = 'sam';
insert into inf.staff_role_grants (user_id, role) select user_id, 'influencer_manager' from tests.people where label = 'sam';

select tests.as_person('sam');
select is(inf.session_register() ->> 'kind', 'staff', 'staff session registers');
select is((inf.me() -> 'session' ->> 'verified')::boolean, false, 'and starts unverified');
select is(inf.has_perm('creator.read'), false, 'no permissions before the code');

-- The app (service role) issues a code.
select tests.reset();
create temporary table issued as
  select inf.mfa_issue(user_id, session_id) as r from tests.people where label = 'sam';
select is((select r ->> 'ok' from issued), 'true', 'code issued');
select ok((select r ->> 'code' from issued) ~ '^\d{6}$', 'six digits');
select is((select count(*)::int from inf.email_codes where code_hash = (select r ->> 'code' from issued)), 0, 'only a hash is stored');
grant select on issued to authenticated;

select tests.as_person('sam');
select is(inf.mfa_verify('12345a') ->> 'error', 'invalid_code', 'malformed code refused');
select is(inf.mfa_verify(case when (select r ->> 'code' from issued) = '000000' then '000001' else '000000' end) ->> 'error', 'invalid_code', 'wrong code refused');
select is((inf.mfa_verify((select r ->> 'code' from issued), true, 'Laptop') ->> 'ok')::boolean, true, 'right code accepted');
select is((inf.me() -> 'session' ->> 'verified')::boolean, true, 'session now verified');
select is(inf.has_perm('creator.read'), true, 'permissions apply after the code');
select is(inf.mfa_verify((select r ->> 'code' from issued)) ->> 'error', 'expired', 'a code works once');
select is((select count(*)::int from inf.my_devices()), 1, 'trusted device stored');

-- Brute force: five wrong attempts lock the code.
select tests.reset();
create temporary table issued2 as select inf.mfa_issue(user_id, session_id) as r from tests.people where label = 'sam';
update inf.user_sessions set verified_at = null where session_id = (select session_id from tests.people where label = 'sam');
grant select on issued2 to authenticated;
select tests.as_person('sam');
select inf.mfa_verify('999999') from generate_series(1, 5);
select is(inf.mfa_verify((select r ->> 'code' from issued2)) ->> 'error', 'too_many_attempts', 'five wrong attempts lock the code, even for the right one');

-- Rate limit: at most five codes per hour.
select tests.reset();
select inf.mfa_issue(user_id, session_id) from tests.people, generate_series(1, 3) where label = 'sam';
select is((select inf.mfa_issue(user_id, session_id) ->> 'error' from tests.people where label = 'sam'), 'too_many_codes', 'sixth code in an hour refused');

-- Trusted device on a new session skips the code.
create temporary table dev as select encode(extensions.gen_random_bytes(32), 'hex') as token;
insert into inf.trusted_devices (user_id, token_hash, label, expires_at)
select user_id, encode(extensions.digest((select token from dev), 'sha256'), 'hex'), 'Phone', now() + interval '30 days' from tests.people where label = 'sam';
grant select on dev to authenticated;
update tests.people set session_id = gen_random_uuid() where label = 'sam';
select tests.as_person('sam');
select inf.session_register();
select is(inf.device_trust_check('f' || repeat('0', 63)), false, 'unknown device token refused');
select is(inf.device_trust_check((select token from dev)), true, 'trusted device verifies the new session');
select is(inf.has_perm('creator.read'), true, 'with permissions');

-- Remote logout: revoke the other session.
select is((select count(*)::int from inf.my_sessions()), 2, 'both sessions listed');
select is(inf.session_revoke((select session_id from inf.my_sessions() where not is_current limit 1)), true, 'other session revoked');
select is((select count(*)::int from inf.my_sessions() where revoked_at is null), 1, 'one live session left');

-- Suspension signs a staff member out everywhere.
select tests.reset();
select tests.make_staff('boss', array['super_admin']);
select tests.as_person('boss');
select lives_ok($$ select inf.staff_set_status((select user_id from tests.people where label = 'sam'), 'suspended', 'left the company') $$, 'super admin suspends');
select tests.as_person('sam');
select is(inf.has_perm('creator.read'), false, 'suspended staff lose access immediately');

-- Creator account linking by verified email.
select tests.reset();
insert into inf.creators (display_name, handle, email, status) values ('Riya', 'riya', 'riya@creator.test', 'invited');
insert into tests.people select 'riya', u, gen_random_uuid(), null from tests.create_user('riya@creator.test') u;
insert into tests.people select 'stranger', u, gen_random_uuid(), null from tests.create_user('stranger@creator.test') u;
select tests.as_person('riya');
select is((inf.creator_account_link() ->> 'linked')::boolean, true, 'invited creator links on first sign-in');
select is(inf.session_register() ->> 'kind', 'creator', 'and gets a creator session (verified by the sign-in)');
select tests.as_person('stranger');
select is(inf.creator_account_link() ->> 'error', 'not_registered', 'an unknown email is refused');

select tests.reset();
select * from finish();
rollback;
