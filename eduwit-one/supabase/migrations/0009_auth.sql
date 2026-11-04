-- 0009 sign-in (spec §13, phase 4): Google restricted to @eduwit.in, then a 6-digit code emailed to the person, or a
-- trusted device for access.trusted_days (30). Spark's flow (b2c-crm b1_access.sql), copied into schema one. one.users
-- is the allow-list: a Supabase user without an active row sees nothing. Every UI function starts with
-- one.ui_require(), which takes the caller from the signed JWT, never from a parameter (D-058).

-- A code is stored as sha256(salt || code), never in clear. 5 codes an hour per person, 5 tries per code.
create table one.email_codes (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  session_id uuid not null,
  salt text not null,
  code_hash text not null,
  attempts integer not null default 0 check (attempts between 0 and 10),
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index email_codes_user_idx on one.email_codes (user_id, created_at desc);

-- A session (the JWT's session_id) that passed the second step.
create table one.session_checks (
  session_id uuid primary key,
  user_id uuid not null,
  method text not null check (method in ('email_code', 'trusted_device')),
  label text,
  created_at timestamptz not null default now()
);

-- A browser the person chose to trust: only the sha256 of the cookie's token is kept.
create table one.trusted_devices (
  id bigint generated always as identity primary key,
  token_hash text not null unique,
  user_id uuid not null,
  label text,
  expires_at timestamptz not null,
  last_used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index trusted_devices_user_idx on one.trusted_devices (user_id) where revoked_at is null;

create table one.sign_in_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  email text,
  user_id uuid,
  method text not null check (method in ('google', 'email_code', 'trusted_device', 'sign_out')),
  outcome text not null check (outcome in ('success', 'refused_domain', 'refused_unknown', 'code_sent', 'failed_code', 'mail_failed',
                                           'signed_out', 'too_many_codes', 'revoked', 'idle')),
  ip text,
  user_agent text,
  detail jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index sign_in_log_time_idx on one.sign_in_log (at desc);

-- Who is calling: the JWT's subject and session, as PostgREST sets them. Null for the service role and the database.
create or replace function one.uid() returns uuid
language sql stable set search_path = '' as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid
$$;

create or replace function one.session_id() returns uuid
language sql stable set search_path = '' as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id', '')::uuid
$$;

-- The session still exists in Supabase Auth: signing out (or an admin revoking it) ends access at once, although
-- the JWT itself stays valid until it expires.
create or replace function one.session_alive() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.sessions s
                  where s.id = one.session_id() and s.user_id = one.uid() and (s.not_after is null or s.not_after > now()))
$$;

create or replace function one.session_checked() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from one.session_checks c where c.session_id = one.session_id() and c.user_id = one.uid())
$$;

-- The signed-in person's access. The database is the authority; the app's checks only route.
create or replace function one.me() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id', one.uid(),
    'email', (select lower(u.email) from auth.users u where u.id = one.uid()),
    'known', o.user_id is not null,
    'active', coalesce(o.is_active, false),
    'role', o.role,
    'checked', one.session_checked(),
    'alive', one.session_alive(),
    -- access.idle_hours: the web app signs out a session idle this long (phase review m7).
    'idle_hours', coalesce((one.setting('access') ->> 'idle_hours')::numeric, 12))
  from (select 1) x left join one.users o on o.user_id = one.uid()
$$;

-- The gate of every UI function: an active Eduwit One user, on a live session that passed the second step. p_perm:
-- 'read' and 'operate' for owner and engineer; 'owner' for the owner only (spec §12: approving proposals that touch
-- money or allocation, alert recipients, fixes, users, PII and access settings). Returns the actor's email.
create or replace function one.ui_require(p_perm text default 'read') returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  v_role text;
  v_email text;
begin
  select o.role, o.email into v_role, v_email from one.users o
   where o.user_id = one.uid() and o.is_active and one.session_checked() and one.session_alive();
  if v_role is null or p_perm not in ('read', 'operate', 'owner') or (p_perm = 'owner' and v_role <> 'owner') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return v_email;
end $$;

-- Service role (the app's signed-out flow): a code for this user's session, which the app emails. 6 digits from the
-- server's strong random (gen_random_uuid), valid access.code_minutes (10).
create or replace function one.auth_issue_code(p_user uuid, p_session uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_code text;
  v_salt text := replace(gen_random_uuid()::text, '-', '');
  v_minutes integer := coalesce((one.setting('access') ->> 'code_minutes')::int, 10);
begin
  if p_user is null or p_session is null or not exists (select 1 from one.users where user_id = p_user and is_active) then
    raise exception 'not an active Eduwit One user' using errcode = '42501';
  end if;
  if (select count(*) from one.email_codes where user_id = p_user and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'too many codes: try again in an hour' using errcode = '54000';
  end if;
  v_code := lpad(((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint % 1000000))::text, 6, '0');
  insert into one.email_codes (user_id, session_id, salt, code_hash, expires_at)
  values (p_user, p_session, v_salt, encode(sha256(convert_to(v_salt || v_code, 'UTF8')), 'hex'), now() + make_interval(mins => v_minutes));
  return v_code;
end $$;

-- The signed-in person enters the code. On success the session is checked; with p_trust, this browser is trusted for
-- access.trusted_days and the token is returned once, for an httpOnly cookie (only its hash is kept).
create or replace function one.auth_verify_code(p_code text, p_trust boolean default false, p_label text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c one.email_codes;
  v_token text;
  v_email text;
  v_days integer := coalesce((one.setting('access') ->> 'trusted_days')::int, 30);
begin
  select o.email into v_email from one.users o where o.user_id = one.uid() and o.is_active;
  if v_email is null or one.session_id() is null or not one.session_alive() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into c from one.email_codes
   where user_id = one.uid() and session_id = one.session_id() and used_at is null
   order by created_at desc limit 1 for update;
  if c.id is null then
    raise exception 'no code was sent: ask for a new one' using errcode = '22023';
  end if;
  if c.expires_at < now() then
    raise exception 'the code has expired: ask for a new one' using errcode = '22023';
  end if;
  if c.attempts >= 5 then
    raise exception 'too many attempts: ask for a new code' using errcode = '22023';
  end if;
  if encode(sha256(convert_to(c.salt || coalesce(p_code, ''), 'UTF8')), 'hex') <> c.code_hash then
    update one.email_codes set attempts = attempts + 1 where id = c.id;
    insert into one.sign_in_log (email, user_id, method, outcome) values (v_email, c.user_id, 'email_code', 'failed_code');
    return jsonb_build_object('ok', false, 'left', greatest(4 - c.attempts, 0));
  end if;
  update one.email_codes set used_at = now() where id = c.id;
  insert into one.session_checks (session_id, user_id, method, label) values (c.session_id, c.user_id, 'email_code', left(p_label, 120))
  on conflict (session_id) do nothing;
  if p_trust and v_days > 0 then
    v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    insert into one.trusted_devices (token_hash, user_id, label, expires_at)
    values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), c.user_id, left(p_label, 120), now() + make_interval(days => v_days));
  end if;
  insert into one.sign_in_log (email, user_id, method, outcome) values (v_email, c.user_id, 'email_code', 'success');
  return jsonb_build_object('ok', true, 'device_token', v_token, 'trusted_days', v_days);
end $$;

-- A trusted device skips the code: the app passes the cookie's token right after sign-in.
create or replace function one.auth_device_check(p_token text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_email text;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' or one.session_id() is null or not one.session_alive() then
    return false;
  end if;
  select d.id, o.email into v_id, v_email from one.trusted_devices d join one.users o on o.user_id = d.user_id and o.is_active
   where d.token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') and d.user_id = one.uid()
     and d.revoked_at is null and d.expires_at > now();
  if v_id is null then
    return false;
  end if;
  update one.trusted_devices set last_used_at = now() where id = v_id;
  insert into one.session_checks (session_id, user_id, method) values (one.session_id(), one.uid(), 'trusted_device')
  on conflict (session_id) do nothing;
  insert into one.sign_in_log (email, user_id, method, outcome) values (v_email, one.uid(), 'trusted_device', 'success');
  return true;
end $$;

-- The session ends its second step on sign-out (the trusted-device cookie stays, as in Spark).
create or replace function one.auth_sign_out() returns void
language sql security definer set search_path = '' as $$
  delete from one.session_checks where session_id = one.session_id() and user_id = one.uid();
  insert into one.sign_in_log (email, user_id, method, outcome)
  select o.email, o.user_id, 'sign_out', 'signed_out' from one.users o where o.user_id = one.uid();
$$;

-- Service role: one sign-in attempt for the log, from the signed-out flow (Google callback, code sent, refusals).
create or replace function one.auth_record(p jsonb) returns void
language sql security definer set search_path = '' as $$
  insert into one.sign_in_log (email, user_id, method, outcome, ip, user_agent, detail)
  values (left(lower(p ->> 'email'), 254), nullif(p ->> 'user_id', '')::uuid, p ->> 'method', p ->> 'outcome',
          left(p ->> 'ip', 45), left(p ->> 'user_agent', 300), coalesce(p -> 'detail', '{}'))
$$;

-- The owners named in access.owners become owners here if their Supabase user already exists. No user is created:
-- a new Supabase user fires the CRM's new-user trigger (website runbook S-21), so users are agreed with its owner first.
insert into one.users (user_id, email, role)
select u.id, lower(u.email), 'owner'
  from auth.users u
 where lower(u.email) in (select lower(x) from jsonb_array_elements_text(coalesce(one.setting('access') -> 'owners', '[]')) x)
   and lower(u.email) ~ '^[^@\s]+@eduwit\.in$'
on conflict do nothing;

grant usage on schema one to authenticated;
insert into one.api_grants (fn, role, why) values
  ('one.me()', 'authenticated', 'who is signed in and what they may use'),
  ('one.auth_verify_code(text,boolean,text)', 'authenticated', 'the second step'),
  ('one.auth_device_check(text)', 'authenticated', 'a trusted device skips the second step'),
  ('one.auth_sign_out()', 'authenticated', 'ends the second step of this session'),
  ('one.auth_issue_code(uuid,uuid)', 'service_role', 'the signed-out flow issues a code the app emails'),
  ('one.auth_record(jsonb)', 'service_role', 'the signed-out flow logs attempts')
on conflict do nothing;
call one.apply_grants();
