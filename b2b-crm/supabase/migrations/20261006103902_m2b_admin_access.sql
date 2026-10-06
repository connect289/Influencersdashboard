-- M2 part b of 5 (see 20261006103851_m2a_extensions_and_schema.sql for the overview).

-- ---------- access: the Admin allowlist ----------
create table if not exists b2b.app_users (
  user_id      uuid primary key references auth.users (id) on delete restrict,
  email        text not null unique check (email = lower(email)),
  role         text not null default 'admin' check (role in ('admin')),   -- widen by migration when roles are added
  is_active    boolean not null default true,
  require_totp boolean not null default true,                              -- password sign-in always needs TOTP; Google too while this is on
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- The B2B CRM's single Admin: the existing auth identity, never a new one (no row on a database without it).
insert into b2b.app_users (user_id, email)
select id, lower(email) from auth.users where lower(email) = 'connect@eduwit.in'
on conflict (user_id) do nothing;

create table if not exists b2b.sign_in_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  user_id    uuid,
  email      text,
  method     text not null check (method in ('google', 'password', 'totp', 'password_reset', 'sign_out', 'session')),
  outcome    text not null check (outcome in ('success', 'refused_not_allowlisted', 'failed_password', 'failed_totp',
                                              'locked', 'signed_out', 'session_expired')),
  ip         inet,
  user_agent text,
  detail     jsonb not null default '{}'
);
create index if not exists sign_in_log_email_idx on b2b.sign_in_log (lower(email), at desc);
create index if not exists sign_in_log_at_idx on b2b.sign_in_log (at desc);

-- True only for an allowlisted, active Admin whose session meets the TOTP rule. Used by RLS and every Admin function.
create or replace function b2b.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from b2b.app_users u
     where u.user_id = auth.uid() and u.is_active and u.role = 'admin'
       and (not u.require_totp or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'));
$$;

-- What the app needs to decide where to send a signed-in session: allowed? needs a TOTP step?
create or replace function b2b.me()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id',      auth.uid(),
    'email',        auth.jwt() ->> 'email',
    'aal',          coalesce(auth.jwt() ->> 'aal', 'aal1'),
    'allowlisted',  u.user_id is not null and coalesce(u.is_active, false),
    'role',         u.role,
    'require_totp', coalesce(u.require_totp, true),
    'is_admin',     b2b.is_admin())
  from (select 1) one
  left join b2b.app_users u on u.user_id = auth.uid();
$$;

-- 5 failed password or TOTP attempts in 15 minutes (since the last success) lock sign-in for that email.
create or replace function b2b.sign_in_locked(p_email text)
returns boolean language sql stable security definer set search_path = '' as $$
  select count(*) >= 5
    from b2b.sign_in_log l
   where lower(l.email) = lower(p_email)
     and l.outcome in ('failed_password', 'failed_totp')
     and l.at > now() - interval '15 minutes'
     and l.at > coalesce((select max(s.at) from b2b.sign_in_log s
                           where lower(s.email) = lower(p_email) and s.outcome = 'success'), '-infinity');
$$;

-- Called by the app's server (service role) for every attempt, including refused accounts.
create or replace function b2b.record_sign_in(p jsonb)
returns bigint language sql volatile security definer set search_path = '' as $$
  insert into b2b.sign_in_log (user_id, email, method, outcome, ip, user_agent, detail)
  values ((p ->> 'user_id')::uuid, lower(p ->> 'email'), p ->> 'method', p ->> 'outcome',
          nullif(p ->> 'ip', '')::inet, left(p ->> 'user_agent', 500), coalesce(p -> 'detail', '{}'))
  returning id;
$$;

-- Active sessions of the signed-in Admin (read from Supabase Auth).
create or replace function b2b.my_sessions()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'created_at', s.created_at, 'updated_at', s.updated_at,
                                        'refreshed_at', s.refreshed_at, 'aal', s.aal, 'user_agent', s.user_agent,
                                        'ip', host(s.ip), 'current', s.id::text = auth.jwt() ->> 'session_id')
                     order by coalesce(s.refreshed_at, s.updated_at) desc)
      from auth.sessions s where s.user_id = auth.uid()), '[]'::jsonb);
end $$;

-- Signing devices out uses Supabase Auth itself from the app (signOut({ scope: 'others' })), not SQL on auth tables.
