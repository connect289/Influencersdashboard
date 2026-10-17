-- web2_admin_auth — staff access to /admin (spec 11): Supabase Auth sign-in (Google or email) + an email-code second
-- factor issued by the website, roles, trusted devices. Students never use these tables (D-005).

create table if not exists public.web_admin_users (
  email text primary key check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'),
  user_id uuid unique,
  role text not null check (role in ('super_admin', 'content_editor', 'viewer')),
  active boolean not null default true,
  display_name text,
  created_at timestamptz not null default now(),
  last_sign_in_at timestamptz
);

insert into public.web_admin_users (email, role, display_name)
values ('connect@eduwit.in', 'super_admin', 'Eduwit owner')
on conflict (email) do nothing;

create table if not exists public.web_admin_codes (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0,
  consumed_at timestamptz,
  ip_hash text,
  created_at timestamptz not null default now()
);
create index if not exists web_admin_codes_user_idx on public.web_admin_codes (user_id, created_at desc);

create table if not exists public.web_admin_trusted_devices (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  token_hash text not null unique,
  label text,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
create index if not exists web_admin_trusted_devices_user_idx on public.web_admin_trusted_devices (user_id);

alter table public.web_admin_users enable row level security;
alter table public.web_admin_codes enable row level security;
alter table public.web_admin_trusted_devices enable row level security;
revoke all on public.web_admin_users, public.web_admin_codes, public.web_admin_trusted_devices from anon, authenticated, public;

-- Resolves a signed-in Supabase user to an active admin (links user_id on first sign-in by verified email).
create or replace function public.web_admin_resolve(p_user_id uuid, p_email text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v public.web_admin_users;
begin
  select * into v from public.web_admin_users where user_id = p_user_id;
  if v.email is null then
    update public.web_admin_users set user_id = p_user_id where email = lower(p_email) and user_id is null returning * into v;
  end if;
  if v.email is null or not v.active then return null; end if;
  return jsonb_build_object('email', v.email, 'role', v.role, 'display_name', v.display_name);
end $$;

-- Stores a new hashed code (10 minutes, 5 attempts). At most 5 codes per user per hour. Older open codes are retired.
create or replace function public.web_admin_code_issue(p_user_id uuid, p_code_hash text, p_ip_hash text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_recent integer;
begin
  select count(*) into v_recent from public.web_admin_codes where user_id = p_user_id and created_at > now() - interval '1 hour';
  if v_recent >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_codes'); end if;
  update public.web_admin_codes set consumed_at = now() where user_id = p_user_id and consumed_at is null;
  insert into public.web_admin_codes (user_id, code_hash, expires_at, ip_hash) values (p_user_id, p_code_hash, now() + interval '10 minutes', p_ip_hash);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.web_admin_code_verify(p_user_id uuid, p_code_hash text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v public.web_admin_codes;
begin
  select * into v from public.web_admin_codes
   where user_id = p_user_id and consumed_at is null and expires_at > now()
   order by created_at desc limit 1 for update;
  if v.id is null then return jsonb_build_object('ok', false, 'reason', 'expired'); end if;
  if v.attempts >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_attempts'); end if;
  if v.code_hash <> p_code_hash then
    update public.web_admin_codes set attempts = attempts + 1 where id = v.id;
    return jsonb_build_object('ok', false, 'reason', 'wrong_code', 'attempts_left', 4 - v.attempts);
  end if;
  update public.web_admin_codes set consumed_at = now() where id = v.id;
  update public.web_admin_users set last_sign_in_at = now() where user_id = p_user_id;
  insert into public.web_audit_log (actor, action, entity, entity_id) values (p_user_id, 'admin.second_factor', 'web_admin_users', p_user_id::text);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.web_admin_device_add(p_user_id uuid, p_token_hash text, p_label text default null)
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.web_admin_trusted_devices (user_id, token_hash, label, expires_at) values (p_user_id, p_token_hash, left(p_label, 120), now() + interval '30 days');
$$;

create or replace function public.web_admin_device_check(p_user_id uuid, p_token_hash text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare v_id bigint;
begin
  update public.web_admin_trusted_devices set last_used_at = now()
   where user_id = p_user_id and token_hash = p_token_hash and revoked_at is null and expires_at > now()
   returning id into v_id;
  return v_id is not null;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.web_admin_resolve(uuid, text)', 'public.web_admin_code_issue(uuid, text, text)', 'public.web_admin_code_verify(uuid, text)',
    'public.web_admin_device_add(uuid, text, text)', 'public.web_admin_device_check(uuid, text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
