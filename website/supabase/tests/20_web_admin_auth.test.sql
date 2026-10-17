-- web2_admin_auth: allow-list resolution, code lifecycle (expiry, attempts, single use, hourly cap), trusted devices.
begin;
create temp table r (ok boolean, name text) on commit drop;
insert into public.web_admin_users (email, role) values ('editor@eduwit.in', 'content_editor'), ('old@eduwit.in', 'viewer');
update public.web_admin_users set active = false where email = 'old@eduwit.in';
-- Supabase Auth records (web11 / L13: the first link needs a confirmed auth email)
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000001', 'editor@eduwit.in', now()),
  ('00000000-0000-0000-0000-000000000004', 'unconfirmed@eduwit.in', null);
insert into public.web_admin_users (email, role) values ('unconfirmed@eduwit.in', 'viewer');
insert into r select public.web_admin_resolve('00000000-0000-0000-0000-000000000004', 'unconfirmed@eduwit.in') is null, 'unconfirmed auth email is not linked';
insert into r select public.web_admin_resolve('00000000-0000-0000-0000-000000000005', 'editor@eduwit.in') is null, 'a token claim alone (no matching confirmed auth user) is not linked';

insert into r select (public.web_admin_resolve('00000000-0000-0000-0000-000000000001', 'Editor@Eduwit.in') ->> 'role') = 'content_editor', 'allow-listed email resolves and links (case-insensitive)';
insert into r select (select user_id from public.web_admin_users where email = 'editor@eduwit.in') = '00000000-0000-0000-0000-000000000001', 'user id linked on first sign-in';
insert into r select public.web_admin_resolve('00000000-0000-0000-0000-000000000002', 'stranger@gmail.com') is null, 'unknown email refused';
insert into r select public.web_admin_resolve('00000000-0000-0000-0000-000000000003', 'old@eduwit.in') is null, 'inactive admin refused';

-- codes
insert into r select (public.web_admin_code_issue('00000000-0000-0000-0000-000000000001', 'h1') ->> 'ok')::boolean, 'code issued';
insert into r select (public.web_admin_code_verify('00000000-0000-0000-0000-000000000001', 'wrong') ->> 'reason') = 'wrong_code', 'wrong code rejected';
insert into r select (public.web_admin_code_verify('00000000-0000-0000-0000-000000000001', 'h1') ->> 'ok')::boolean, 'right code accepted';
insert into r select (public.web_admin_code_verify('00000000-0000-0000-0000-000000000001', 'h1') ->> 'reason') = 'expired', 'code is single use';
select public.web_admin_code_issue('00000000-0000-0000-0000-000000000001', 'h2');
select public.web_admin_code_verify('00000000-0000-0000-0000-000000000001', 'x') from generate_series(1, 5);
insert into r select (public.web_admin_code_verify('00000000-0000-0000-0000-000000000001', 'h2') ->> 'reason') = 'too_many_attempts', 'locked after 5 wrong attempts';
update public.web_admin_codes set expires_at = now() - interval '1 second' where user_id = '00000000-0000-0000-0000-000000000001';
select public.web_admin_code_issue('00000000-0000-0000-0000-000000000001', 'h3');
update public.web_admin_codes set expires_at = now() - interval '1 second' where code_hash = 'h3';
insert into r select (public.web_admin_code_verify('00000000-0000-0000-0000-000000000001', 'h3') ->> 'reason') = 'expired', 'expired code rejected';
select public.web_admin_code_issue('00000000-0000-0000-0000-000000000001', 'h' || g) from generate_series(4, 5) g;
insert into r select (public.web_admin_code_issue('00000000-0000-0000-0000-000000000001', 'h6') ->> 'reason') = 'too_many_codes', 'at most 5 codes per hour';
insert into r select exists (select 1 from public.web_audit_log where action = 'admin.second_factor'), 'second factor audited';

-- devices
select public.web_admin_device_add('00000000-0000-0000-0000-000000000001', 'dev1', 'Chrome on Android');
insert into r select public.web_admin_device_check('00000000-0000-0000-0000-000000000001', 'dev1'), 'trusted device accepted';
insert into r select not public.web_admin_device_check('00000000-0000-0000-0000-000000000009', 'dev1'), 'device bound to its user';
update public.web_admin_trusted_devices set expires_at = now() - interval '1 day' where token_hash = 'dev1';
insert into r select not public.web_admin_device_check('00000000-0000-0000-0000-000000000001', 'dev1'), 'expired device refused';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
