-- Influencer Portal: identity, roles, sessions, staff 2FA, creators core.
-- Spec 4 (roles, permission matrix, staff 2FA, creator auth), 19 (sessions, remote logout), ERD §1.
-- Access model:
--   * staff     = active inf.staff_profiles row + a VERIFIED session (emailed code or trusted device) → inf.has_perm()
--   * creator   = inf.creator_accounts link + creator not blocked/archived + a live session → inf.current_creator_id()
--   * anyone else on the shared Supabase Auth (B2B, B2C, Witty staff, strangers) gets nothing from `inf`.

-- ---------------------------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------------------------
create table inf.permissions (
  key         text primary key check (key ~ '^[a-z_]+\.[a-z_]+$'),
  area        text not null,
  label       text not null
);

create table inf.role_permissions (
  role        text not null check (role in ('super_admin', 'influencer_manager', 'content_reviewer', 'finance', 'viewer')),
  permission  text not null references inf.permissions (key) on delete cascade,
  primary key (role, permission)
);

create table inf.staff_profiles (
  user_id               uuid primary key references auth.users (id) on delete restrict,
  full_name             text not null check (char_length(full_name) between 1 and 120),
  email                 text not null check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  status                text not null default 'active' check (status in ('active', 'suspended')),
  is_signatory          boolean not null default false,
  signatory_designation text check (signatory_designation is null or char_length(signatory_designation) between 2 and 120),
  created_by            uuid,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  last_seen_at          timestamptz,
  constraint signatory_needs_designation check (not is_signatory or signatory_designation is not null)
);
create unique index staff_profiles_email_uq on inf.staff_profiles (lower(email));

create table inf.staff_role_grants (
  user_id     uuid not null references inf.staff_profiles (user_id) on delete cascade,
  role        text not null check (role in ('super_admin', 'influencer_manager', 'content_reviewer', 'finance', 'viewer')),
  granted_by  uuid,
  granted_at  timestamptz not null default now(),
  primary key (user_id, role)
);

-- One row per Supabase Auth session that has touched the portal. The JWT's session_id claim is the key.
create table inf.user_sessions (
  session_id     uuid primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  kind           text not null check (kind in ('staff', 'creator', 'agency')),
  auth_method    text,
  verified_at    timestamptz,
  verified_via   text check (verified_via in ('email_code', 'trusted_device', 'otp', 'oauth', 'password')),
  created_at     timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  ip             inet,
  user_agent     text,
  revoked_at     timestamptz,
  revoked_by     uuid,
  revoke_reason  text
);
create index user_sessions_user_idx on inf.user_sessions (user_id, last_seen_at desc);

create table inf.email_codes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  session_id   uuid not null,
  purpose      text not null default 'staff_2fa' check (purpose in ('staff_2fa')),
  code_hash    text not null,
  salt         text not null,
  attempts     int not null default 0,
  expires_at   timestamptz not null,
  consumed_at  timestamptz,
  created_at   timestamptz not null default now()
);
create index email_codes_user_idx on inf.email_codes (user_id, created_at desc);

create table inf.trusted_devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  token_hash    text not null unique,
  label         text check (char_length(label) <= 120),
  created_at    timestamptz not null default now(),
  last_used_at  timestamptz,
  expires_at    timestamptz not null,
  revoked_at    timestamptz
);
create index trusted_devices_user_idx on inf.trusted_devices (user_id);

create table inf.sign_in_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  user_id     uuid,
  email       text,
  portal      text not null check (portal in ('staff', 'creator')),
  method      text not null check (method in ('password', 'google', 'email_otp', 'email_code', 'trusted_device', 'magic_link')),
  outcome     text not null check (outcome in ('ok', 'failed', 'refused', 'locked')),
  reason      text,
  ip          inet,
  user_agent  text
);
create index sign_in_log_email_idx on inf.sign_in_log (lower(email), at desc);
create index sign_in_log_at_idx on inf.sign_in_log (at desc);

create table inf.tiers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique check (char_length(name) between 2 and 40),
  rank        int not null unique check (rank between 1 and 100),
  entry_rules jsonb not null default '{}'::jsonb,
  benefits    jsonb not null default '{}'::jsonb,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table inf.creators (
  id                  uuid primary key default gen_random_uuid(),
  legal_name          text check (char_length(legal_name) <= 200),
  display_name        text not null check (char_length(display_name) between 1 and 120),
  handle              text not null check (handle ~ '^[a-z0-9._]{3,30}$'),
  email               text check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone_e164          text check (phone_e164 ~ '^\+[1-9]\d{7,14}$'),
  city                text check (char_length(city) <= 80),
  state               text check (char_length(state) <= 80),
  languages           text[] not null default '{}',
  niches              text[] not null default '{}',
  bio                 text check (char_length(bio) <= 2000),
  avatar_path         text,
  status              text not null default 'prospect'
                        check (status in ('prospect', 'invited', 'onboarding', 'active', 'paused', 'blocked', 'archived')),
  pipeline_stage      text not null default 'prospect'
                        check (pipeline_stage in ('prospect', 'contacted', 'negotiating', 'contracted', 'onboarding', 'active', 'paused', 'dormant', 'archived')),
  is_blocked          boolean not null default false,
  blocked_reason      text,
  tier_id             uuid references inf.tiers (id) on delete set null,
  owner_id            uuid references inf.staff_profiles (user_id) on delete set null,
  source              text check (char_length(source) <= 80),
  tags                text[] not null default '{}',
  public_page_enabled boolean not null default false,
  leaderboard_opt_in  boolean not null default false,
  is_test             boolean not null default false,
  last_activity_at    timestamptz,
  created_by          uuid,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint blocked_needs_reason check (not is_blocked or blocked_reason is not null)
);
create unique index creators_handle_uq on inf.creators (handle);
create unique index creators_email_uq on inf.creators (lower(email)) where email is not null;
create unique index creators_phone_uq on inf.creators (phone_e164) where phone_e164 is not null;
create index creators_status_idx on inf.creators (status, pipeline_stage);
create index creators_owner_idx on inf.creators (owner_id);

create table inf.creator_accounts (
  creator_id  uuid primary key references inf.creators (id) on delete restrict,
  user_id     uuid not null unique references auth.users (id) on delete restrict,
  linked_at   timestamptz not null default now()
);

-- A person is staff or a creator, never both (separate portals, separate data rules).
create or replace function inf.check_identity_kind() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'staff_profiles' and exists (select 1 from inf.creator_accounts where user_id = new.user_id) then
    raise exception 'this account is a creator account and cannot be staff' using errcode = 'check_violation';
  elsif tg_table_name = 'creator_accounts' and exists (select 1 from inf.staff_profiles where user_id = new.user_id) then
    raise exception 'this account is a staff account and cannot be linked to a creator' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger staff_profiles_kind before insert or update of user_id on inf.staff_profiles
  for each row execute function inf.check_identity_kind();
create trigger creator_accounts_kind before insert or update of user_id on inf.creator_accounts
  for each row execute function inf.check_identity_kind();

create trigger staff_profiles_touch before update on inf.staff_profiles for each row execute function inf.touch_updated_at();
create trigger creators_touch before update on inf.creators for each row execute function inf.touch_updated_at();
create trigger tiers_touch before update on inf.tiers for each row execute function inf.touch_updated_at();

create trigger staff_profiles_audit after insert or update or delete on inf.staff_profiles
  for each row execute function inf.audit_row('staff_profile');
create trigger staff_role_grants_audit after insert or update or delete on inf.staff_role_grants
  for each row execute function inf.audit_row('staff_role_grant');
create trigger creators_audit after insert or update or delete on inf.creators
  for each row execute function inf.audit_row('creator');
create trigger creator_accounts_audit after insert or update or delete on inf.creator_accounts
  for each row execute function inf.audit_row('creator_account');
create trigger tiers_audit after insert or update or delete on inf.tiers
  for each row execute function inf.audit_row('tier');
create trigger role_permissions_audit after insert or update or delete on inf.role_permissions
  for each row execute function inf.audit_row('role_permission');

create trigger sign_in_log_append_only before update or delete on inf.sign_in_log
  for each row execute function inf.forbid_mutation();

-- ---------------------------------------------------------------------------------------------------------------
-- Access helpers (used by RLS as `(select inf.fn())` so they run once per statement)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.current_session_id() returns uuid
language plpgsql stable set search_path = '' as $$
begin
  return nullif(auth.jwt() ->> 'session_id', '')::uuid;
exception when others then return null;
end $$;

-- Idle limit in hours, from the security.sessions setting (default 12). plpgsql because the settings tables are
-- created by a later migration.
create or replace function inf.idle_limit() returns interval
language plpgsql stable security definer set search_path = '' as $$
declare v int;
begin
  select (coalesce(s.value, d.default_value) ->> 'idle_timeout_hours')::int into v
    from inf.setting_definitions d left join inf.settings s on s.key = d.key
   where d.key = 'security.sessions';
  return make_interval(hours => coalesce(v, 12));
exception when undefined_table then
  return interval '12 hours';
end $$;

-- A session the portal knows, not revoked, not idle past the limit, and verified (staff: emailed code or trusted
-- device; creators: their sign-in). The database enforces the idle timeout itself; the app's cookie is only a UX aid.
create or replace function inf.session_ok() returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  return exists (
    select 1 from inf.user_sessions s
     where s.session_id = inf.current_session_id() and s.user_id = auth.uid()
       and s.verified_at is not null and s.revoked_at is null
       and s.last_seen_at > now() - inf.idle_limit());
end $$;

create or replace function inf.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from inf.staff_profiles p where p.user_id = auth.uid() and p.status = 'active')
         and inf.session_ok();
$$;

create or replace function inf.has_perm(p_permission text) returns boolean
language sql stable security definer set search_path = '' as $$
  select inf.session_ok() and exists (
    select 1 from inf.staff_profiles p
     where p.user_id = auth.uid() and p.status = 'active'
       and (exists (select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
                     where g.user_id = p.user_id and rp.permission = p_permission)
            or (p_permission = 'contract.countersign' and p.is_signatory)));
$$;

create or replace function inf.current_creator_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select a.creator_id
    from inf.creator_accounts a join inf.creators c on c.id = a.creator_id
   where a.user_id = auth.uid() and c.status not in ('blocked', 'archived') and not c.is_blocked
     and inf.session_ok();
$$;

-- Replaces the stub from the schema migration: a short label of who is acting, for the audit log.
create or replace function inf.actor_role() returns text
language sql stable security definer set search_path = '' as $$
  select case
    when auth.role() = 'service_role' then 'service'
    when auth.uid() is null then coalesce(auth.role(), 'system')
    when exists (select 1 from inf.staff_profiles p where p.user_id = auth.uid()) then
      coalesce((select 'staff:' || string_agg(g.role, ',' order by g.role) from inf.staff_role_grants g where g.user_id = auth.uid()), 'staff')
    when exists (select 1 from inf.creator_accounts a where a.user_id = auth.uid()) then 'creator'
    else 'authenticated' end;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Session lifecycle
-- ---------------------------------------------------------------------------------------------------------------
-- Called by the app right after sign-in (and harmlessly on any later request). Registers the session. Creators are
-- verified by their sign-in itself (email OTP or Google); staff stay unverified until the emailed code.
create or replace function inf.session_register() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_sid     uuid := inf.current_session_id();
  v_kind    text;
  v_amr     text := coalesce(auth.jwt() -> 'amr' -> 0 ->> 'method', 'unknown');
  v_via     text;
begin
  if v_uid is null or v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'not_signed_in');
  end if;
  if exists (select 1 from inf.staff_profiles where user_id = v_uid and status = 'active') then
    v_kind := 'staff';
  elsif exists (select 1 from inf.creator_accounts a join inf.creators c on c.id = a.creator_id
                 where a.user_id = v_uid and c.status not in ('blocked', 'archived') and not c.is_blocked) then
    v_kind := 'creator';
    v_via := case when v_amr = 'oauth' then 'oauth' when v_amr in ('otp', 'magiclink', 'email/signup') then 'otp' else 'otp' end;
  else
    return jsonb_build_object('ok', false, 'error', 'no_portal_access');
  end if;

  insert into inf.user_sessions (session_id, user_id, kind, auth_method, verified_at, verified_via, ip, user_agent)
  values (v_sid, v_uid, v_kind, v_amr,
          case when v_kind = 'creator' then now() end, v_via, inf.request_ip(), inf.request_user_agent())
  on conflict (session_id) do update set last_seen_at = now()
    where inf.user_sessions.user_id = excluded.user_id;
  if not exists (select 1 from inf.user_sessions where session_id = v_sid and user_id = v_uid) then
    return jsonb_build_object('ok', false, 'error', 'session_mismatch');
  end if;
  return jsonb_build_object('ok', true, 'kind', v_kind);
end $$;

-- Keeps an active session alive (at most one write per 2 minutes). An idle-expired session is not revived.
create or replace function inf.session_touch() returns void
language plpgsql security definer set search_path = '' as $$
begin
  update inf.user_sessions set last_seen_at = now()
   where session_id = inf.current_session_id() and user_id = auth.uid() and revoked_at is null
     and last_seen_at < now() - interval '2 minutes' and last_seen_at > now() - inf.idle_limit();
end $$;

-- Everything the app needs to render and guard a page, in one call.
create or replace function inf.me() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid  uuid := auth.uid();
  v_sid  uuid := inf.current_session_id();
  v_sess inf.user_sessions;
  v_staff inf.staff_profiles;
  v_creator inf.creators;
begin
  if v_uid is null then return jsonb_build_object('signed_in', false); end if;
  select * into v_sess from inf.user_sessions where session_id = v_sid and user_id = v_uid;
  select * into v_staff from inf.staff_profiles where user_id = v_uid;
  select c.* into v_creator from inf.creator_accounts a join inf.creators c on c.id = a.creator_id where a.user_id = v_uid;
  return jsonb_build_object(
    'signed_in', true,
    'user_id', v_uid,
    'email', auth.jwt() ->> 'email',
    'session', case when v_sess.session_id is null then null else jsonb_build_object(
        'registered', true, 'verified', v_sess.verified_at is not null,
        'revoked', v_sess.revoked_at is not null or v_sess.last_seen_at <= now() - inf.idle_limit(),
        'verified_via', v_sess.verified_via) end,
    'kind', case when v_staff.user_id is not null then 'staff' when v_creator.id is not null then 'creator' else 'none' end,
    'staff', case when v_staff.user_id is null then null else jsonb_build_object(
        'full_name', v_staff.full_name, 'status', v_staff.status, 'is_signatory', v_staff.is_signatory,
        'roles', coalesce((select jsonb_agg(g.role order by g.role) from inf.staff_role_grants g where g.user_id = v_uid), '[]'::jsonb)) end,
    'creator', case when v_creator.id is null then null else jsonb_build_object(
        'id', v_creator.id, 'display_name', v_creator.display_name, 'handle', v_creator.handle,
        'status', v_creator.status, 'is_blocked', v_creator.is_blocked, 'is_test', v_creator.is_test) end);
end $$;

-- The current user's sessions (the Account page). The JWT session_id marks the current one.
create or replace function inf.my_sessions() returns table (
  session_id uuid, kind text, created_at timestamptz, last_seen_at timestamptz, ip inet, user_agent text,
  verified boolean, revoked_at timestamptz, is_current boolean)
language sql stable security definer set search_path = '' as $$
  select s.session_id, s.kind, s.created_at, s.last_seen_at, s.ip, s.user_agent, s.verified_at is not null,
         s.revoked_at, s.session_id = inf.current_session_id()
    from inf.user_sessions s
   where s.user_id = auth.uid() and (s.revoked_at is null or s.revoked_at > now() - interval '30 days')
   order by s.last_seen_at desc
   limit 50;
$$;

-- Revoke one of my sessions (remote logout). The revoked device loses access to everything in `inf` at once and is
-- signed out by the app on its next request.
create or replace function inf.session_revoke(p_session_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  update inf.user_sessions set revoked_at = now(), revoked_by = auth.uid(), revoke_reason = 'signed out by the user'
   where session_id = p_session_id and user_id = auth.uid() and revoked_at is null;
  get diagnostics v_n = row_count;
  if v_n > 0 then perform inf.audit('session', p_session_id::text, 'revoke', null, jsonb_build_object('by', 'self')); end if;
  return v_n > 0;
end $$;

-- Staff admin: sign a staff member out everywhere (also used when suspending).
create or replace function inf.staff_revoke_all_sessions(p_user uuid, p_reason text) returns int
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  if not inf.has_perm('staff.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.user_sessions set revoked_at = now(), revoked_by = auth.uid(), revoke_reason = left(p_reason, 300)
   where user_id = p_user and revoked_at is null;
  get diagnostics v_n = row_count;
  update inf.trusted_devices set revoked_at = now() where user_id = p_user and revoked_at is null;
  perform inf.audit('staff_profile', p_user::text, 'revoke_all_sessions', null, jsonb_build_object('reason', p_reason, 'sessions', v_n));
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Staff 2FA: an emailed 6-digit code after every sign-in (password or Google), unless the device is trusted.
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.code_hash(p_code text, p_salt text, p_user uuid) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.hmac(p_code || ':' || p_user::text, p_salt, 'sha256'), 'hex');
$$;

-- service_role only: issues a code for the staff member's current session and returns it for the app to email.
-- At most 5 codes per hour per user; issuing a new code retires the previous ones.
create or replace function inf.mfa_issue(p_user uuid, p_session uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_code text;
  v_salt text := encode(extensions.gen_random_bytes(16), 'hex');
  v_recent int;
begin
  if not exists (select 1 from inf.staff_profiles where user_id = p_user and status = 'active') then
    return jsonb_build_object('ok', false, 'error', 'not_staff');
  end if;
  if not exists (select 1 from inf.user_sessions where session_id = p_session and user_id = p_user and revoked_at is null) then
    return jsonb_build_object('ok', false, 'error', 'unknown_session');
  end if;
  select count(*) into v_recent from inf.email_codes where user_id = p_user and created_at > now() - interval '1 hour';
  if v_recent >= 5 then return jsonb_build_object('ok', false, 'error', 'too_many_codes'); end if;
  update inf.email_codes set consumed_at = now() where user_id = p_user and consumed_at is null;
  v_code := lpad((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000)::text, 6, '0');
  insert into inf.email_codes (user_id, session_id, code_hash, salt, expires_at)
  values (p_user, p_session, inf.code_hash(v_code, v_salt, p_user), v_salt, now() + interval '10 minutes');
  return jsonb_build_object('ok', true, 'code', v_code, 'expires_in_seconds', 600);
end $$;

-- As the signed-in staff member: checks the code for the current session. With p_trust, returns a device token the
-- app stores in an httpOnly cookie (only its SHA-256 is kept here).
create or replace function inf.mfa_verify(p_code text, p_trust boolean default false, p_label text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := auth.uid();
  v_sid   uuid := inf.current_session_id();
  v_row   inf.email_codes;
  v_token text;
  v_days  int;
begin
  if v_uid is null or v_sid is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  if p_code is null or p_code !~ '^\d{6}$' then return jsonb_build_object('ok', false, 'error', 'invalid_code'); end if;
  select * into v_row from inf.email_codes
   where user_id = v_uid and session_id = v_sid and consumed_at is null
   order by created_at desc limit 1 for update;
  if v_row.id is null or v_row.expires_at < now() then return jsonb_build_object('ok', false, 'error', 'expired'); end if;
  if v_row.attempts >= 5 then return jsonb_build_object('ok', false, 'error', 'too_many_attempts'); end if;
  if inf.code_hash(p_code, v_row.salt, v_uid) <> v_row.code_hash then
    update inf.email_codes set attempts = attempts + 1 where id = v_row.id;
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'attempts_left', 4 - v_row.attempts);
  end if;
  update inf.email_codes set consumed_at = now() where id = v_row.id;
  update inf.user_sessions set verified_at = now(), verified_via = 'email_code'
   where session_id = v_sid and user_id = v_uid and revoked_at is null;
  update inf.staff_profiles set last_seen_at = now() where user_id = v_uid;
  if p_trust then
    v_days := coalesce((select (value ->> 'trusted_device_days')::int from inf.settings where key = 'security.sessions'), 30);
    if v_days > 0 then
      v_token := encode(extensions.gen_random_bytes(32), 'hex');
      insert into inf.trusted_devices (user_id, token_hash, label, expires_at)
      values (v_uid, encode(extensions.digest(v_token, 'sha256'), 'hex'), left(p_label, 120), now() + make_interval(days => v_days));
    end if;
  end if;
  return jsonb_build_object('ok', true, 'device_token', v_token);
end $$;

-- As the signed-in staff member: a valid trusted-device token verifies the current session without a code.
create or replace function inf.device_trust_check(p_token text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_dev inf.trusted_devices;
begin
  if auth.uid() is null or p_token is null or p_token !~ '^[0-9a-f]{64}$' then return false; end if;
  select * into v_dev from inf.trusted_devices
   where user_id = auth.uid() and token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
     and revoked_at is null and expires_at > now();
  if v_dev.id is null then return false; end if;
  update inf.trusted_devices set last_used_at = now() where id = v_dev.id;
  update inf.user_sessions set verified_at = now(), verified_via = 'trusted_device'
   where session_id = inf.current_session_id() and user_id = auth.uid() and revoked_at is null and verified_at is null;
  return found;
end $$;

create or replace function inf.my_devices() returns table (id uuid, label text, created_at timestamptz, last_used_at timestamptz, expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select d.id, d.label, d.created_at, d.last_used_at, d.expires_at from inf.trusted_devices d
   where d.user_id = auth.uid() and d.revoked_at is null and d.expires_at > now() order by d.created_at desc;
$$;

create or replace function inf.device_revoke(p_id uuid) returns boolean
language sql security definer set search_path = '' as $$
  with u as (update inf.trusted_devices set revoked_at = now() where id = p_id and user_id = auth.uid() and revoked_at is null returning 1)
  select exists (select 1 from u);
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Sign-in log and lockout (service_role: the app calls these around Supabase Auth)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.sign_in_record(p_email text, p_portal text, p_method text, p_outcome text, p_reason text default null,
                                              p_user uuid default null, p_ip text default null, p_ua text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_ip inet;
begin
  begin v_ip := nullif(p_ip, '')::inet; exception when others then v_ip := null; end;
  insert into inf.sign_in_log (user_id, email, portal, method, outcome, reason, ip, user_agent)
  values (p_user, lower(left(p_email, 254)), p_portal, p_method, p_outcome, left(p_reason, 300), v_ip, left(p_ua, 500));
end $$;

-- Locked after 10 failed attempts for the same email in 15 minutes.
create or replace function inf.sign_in_locked(p_email text) returns boolean
language sql stable security definer set search_path = '' as $$
  select count(*) >= 10 from inf.sign_in_log
   where lower(email) = lower(p_email) and outcome = 'failed' and at > now() - interval '15 minutes';
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Staff administration (permission staff.manage). Auth users are created by the app with the Admin API first.
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.staff_save(p_user uuid, p_full_name text, p_email text, p_roles text[],
                                          p_is_signatory boolean, p_designation text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_roles text[] := (select coalesce(array_agg(distinct r order by r), '{}') from unnest(p_roles) r);
begin
  if not inf.has_perm('staff.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if cardinality(v_roles) = 0 then raise exception 'choose at least one role' using errcode = '22023'; end if;
  if exists (select 1 from unnest(v_roles) r where r not in ('super_admin', 'influencer_manager', 'content_reviewer', 'finance', 'viewer')) then
    raise exception 'unknown role' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such account' using errcode = '22023'; end if;
  -- Never leave the portal without an active Super Admin.
  if p_user = auth.uid() and not ('super_admin' = any (v_roles))
     and not exists (select 1 from inf.staff_role_grants g join inf.staff_profiles p on p.user_id = g.user_id
                      where g.role = 'super_admin' and p.status = 'active' and g.user_id <> p_user) then
    raise exception 'you are the only Super Admin; add another before removing your own role' using errcode = '22023';
  end if;
  insert into inf.staff_profiles (user_id, full_name, email, is_signatory, signatory_designation, created_by)
  values (p_user, trim(p_full_name), lower(trim(p_email)), coalesce(p_is_signatory, false), nullif(trim(p_designation), ''), auth.uid())
  on conflict (user_id) do update set full_name = excluded.full_name, email = excluded.email,
    is_signatory = excluded.is_signatory, signatory_designation = excluded.signatory_designation;
  delete from inf.staff_role_grants where user_id = p_user and not (role = any (v_roles));
  insert into inf.staff_role_grants (user_id, role, granted_by)
  select p_user, r, auth.uid() from unnest(v_roles) r
  on conflict do nothing;
end $$;

create or replace function inf.staff_set_status(p_user uuid, p_status text, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('staff.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status not in ('active', 'suspended') then raise exception 'unknown status' using errcode = '22023'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  if p_user = auth.uid() and p_status = 'suspended' then raise exception 'you cannot suspend yourself' using errcode = '22023'; end if;
  update inf.staff_profiles set status = p_status where user_id = p_user;
  if not found then raise exception 'no such staff member' using errcode = '22023'; end if;
  perform inf.audit('staff_profile', p_user::text, 'set_status', null, jsonb_build_object('status', p_status, 'reason', p_reason));
  if p_status = 'suspended' then perform inf.staff_revoke_all_sessions(p_user, 'suspended: ' || p_reason); end if;
end $$;

create or replace function inf.staff_list() returns table (
  user_id uuid, full_name text, email text, status text, is_signatory boolean, signatory_designation text,
  roles text[], last_seen_at timestamptz, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.user_id, p.full_name, p.email, p.status, p.is_signatory, p.signatory_designation,
         coalesce((select array_agg(g.role order by g.role) from inf.staff_role_grants g where g.user_id = p.user_id), '{}'),
         p.last_seen_at, p.created_at
    from inf.staff_profiles p
   where inf.has_perm('staff.manage')
   order by p.status, p.full_name;
$$;

-- One-time bootstrap (service_role only, e.g. from the SQL editor at go-live): makes an existing auth user the first
-- Super Admin and Authorised Signatory. Refuses once any active Super Admin exists.
create or replace function inf.bootstrap_super_admin(p_email text, p_full_name text, p_designation text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid;
begin
  if exists (select 1 from inf.staff_role_grants g join inf.staff_profiles p on p.user_id = g.user_id
              where g.role = 'super_admin' and p.status = 'active') then
    raise exception 'a Super Admin already exists' using errcode = '42501';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(p_email);
  if v_uid is null then raise exception 'create the auth user first (Supabase dashboard → Authentication)' using errcode = '22023'; end if;
  insert into inf.staff_profiles (user_id, full_name, email, is_signatory, signatory_designation)
  values (v_uid, p_full_name, lower(p_email), true, p_designation)
  on conflict (user_id) do update set status = 'active', is_signatory = true, signatory_designation = excluded.signatory_designation;
  insert into inf.staff_role_grants (user_id, role) values (v_uid, 'super_admin') on conflict do nothing;
  return v_uid;
end $$;

-- service_role only: the auth user id for an email (used when inviting staff or creators who may already have an
-- account on the shared Supabase Auth, e.g. from another Eduwit product).
create or replace function inf.auth_user_id_by_email(p_email text) returns uuid
language sql stable security definer set search_path = '' as $$
  select id from auth.users where lower(email) = lower(trim(p_email)) limit 1;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Creator account linking: on first sign-in, a verified email that matches exactly one invited/onboarding/active/paused
-- creator without an account is linked to it. Anything else is refused (the app then signs the user out).
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.creator_account_link() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_email   text;
  v_ok      boolean;
  v_creator uuid;
  v_n       int;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select a.creator_id into v_creator from inf.creator_accounts a where a.user_id = v_uid;
  if v_creator is not null then return jsonb_build_object('ok', true, 'creator_id', v_creator, 'linked', false); end if;
  if exists (select 1 from inf.staff_profiles where user_id = v_uid) then
    return jsonb_build_object('ok', false, 'error', 'staff_account');
  end if;
  select lower(u.email), u.email_confirmed_at is not null into v_email, v_ok from auth.users u where u.id = v_uid;
  if v_email is null or not v_ok then return jsonb_build_object('ok', false, 'error', 'email_not_verified'); end if;
  select count(*), min(c.id::text)::uuid into v_n, v_creator
    from inf.creators c
   where lower(c.email) = v_email and c.status in ('invited', 'onboarding', 'active', 'paused') and not c.is_blocked
     and not exists (select 1 from inf.creator_accounts a where a.creator_id = c.id);
  if v_n <> 1 then return jsonb_build_object('ok', false, 'error', 'not_registered'); end if;
  insert into inf.creator_accounts (creator_id, user_id) values (v_creator, v_uid);
  update inf.creators set status = case when status = 'invited' then 'onboarding' else status end,
                          last_activity_at = now()
   where id = v_creator;
  return jsonb_build_object('ok', true, 'creator_id', v_creator, 'linked', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.permissions enable row level security;
alter table inf.role_permissions enable row level security;
alter table inf.staff_profiles enable row level security;
alter table inf.staff_role_grants enable row level security;
alter table inf.user_sessions enable row level security;
alter table inf.email_codes enable row level security;
alter table inf.trusted_devices enable row level security;
alter table inf.sign_in_log enable row level security;
alter table inf.tiers enable row level security;
alter table inf.creators enable row level security;
alter table inf.creator_accounts enable row level security;

-- Staff can read the matrix (the UI shows it); writes only by migrations.
create policy permissions_staff_read on inf.permissions for select to authenticated using ((select inf.is_staff()));
create policy role_permissions_staff_read on inf.role_permissions for select to authenticated using ((select inf.is_staff()));

-- Staff directory: every active staff member sees names (for owner pickers, @mentions); staff.manage sees all.
create policy staff_profiles_read on inf.staff_profiles for select to authenticated
  using ((select inf.is_staff()) or user_id = (select auth.uid()));
create policy staff_role_grants_read on inf.staff_role_grants for select to authenticated
  using ((select inf.is_staff()) or user_id = (select auth.uid()));

-- Sign-in log: audit readers only.
create policy sign_in_log_read on inf.sign_in_log for select to authenticated using ((select inf.has_perm('audit.read')));

-- Audit log: audit readers only (the table exists since the schema migration).
create policy audit_log_read on inf.audit_log for select to authenticated using ((select inf.has_perm('audit.read')));

-- Tiers: staff, and creators (their tier and the ladder are shown to them).
create policy tiers_read on inf.tiers for select to authenticated
  using ((select inf.is_staff()) or (select inf.current_creator_id()) is not null);

-- Creators: staff with creator.read see all; a creator sees only their own row.
create policy creators_staff_read on inf.creators for select to authenticated using ((select inf.has_perm('creator.read')));
create policy creators_self_read on inf.creators for select to authenticated using (id = (select inf.current_creator_id()));
create policy creator_accounts_read on inf.creator_accounts for select to authenticated
  using ((select inf.has_perm('creator.read')) or user_id = (select auth.uid()));

-- user_sessions, email_codes, trusted_devices: no policies. Reached only through the functions above.

-- ---------------------------------------------------------------------------------------------------------------
-- Grants. Reads go through RLS; every write goes through a SECURITY DEFINER function.
-- ---------------------------------------------------------------------------------------------------------------
insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.permissions', 'authenticated', 'select'),
  ('table', 'inf.role_permissions', 'authenticated', 'select'),
  ('table', 'inf.staff_profiles', 'authenticated', 'select'),
  ('table', 'inf.staff_role_grants', 'authenticated', 'select'),
  ('table', 'inf.sign_in_log', 'authenticated', 'select'),
  ('table', 'inf.audit_log', 'authenticated', 'select'),
  ('table', 'inf.tiers', 'authenticated', 'select'),
  ('table', 'inf.creators', 'authenticated', 'select'),
  ('table', 'inf.creator_accounts', 'authenticated', 'select'),
  ('function', 'inf.current_session_id()', 'authenticated', 'execute'),
  ('function', 'inf.idle_limit()', 'authenticated', 'execute'),
  ('function', 'inf.session_ok()', 'authenticated', 'execute'),
  ('function', 'inf.is_staff()', 'authenticated', 'execute'),
  ('function', 'inf.has_perm(text)', 'authenticated', 'execute'),
  ('function', 'inf.current_creator_id()', 'authenticated', 'execute'),
  ('function', 'inf.actor_role()', 'authenticated', 'execute'),
  ('function', 'inf.session_register()', 'authenticated', 'execute'),
  ('function', 'inf.session_touch()', 'authenticated', 'execute'),
  ('function', 'inf.me()', 'authenticated', 'execute'),
  ('function', 'inf.my_sessions()', 'authenticated', 'execute'),
  ('function', 'inf.session_revoke(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.staff_revoke_all_sessions(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.mfa_verify(text, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.device_trust_check(text)', 'authenticated', 'execute'),
  ('function', 'inf.my_devices()', 'authenticated', 'execute'),
  ('function', 'inf.device_revoke(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.staff_save(uuid, text, text, text[], boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.staff_set_status(uuid, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.staff_list()', 'authenticated', 'execute'),
  ('function', 'inf.creator_account_link()', 'authenticated', 'execute');
call inf.apply_client_grants();
