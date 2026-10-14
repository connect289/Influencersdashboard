-- B2C CRM b1: schema b2c, people and access, settings, events and audit.
-- Staging first. Nothing here touches student_leads, w2_*, lead_intake() or b2b.*.
--   users            B2C staff (spec B14 crm_users columns; crm_users itself stays for the old CRM until cut-over)
--   me() / can()     who is signed in, their role, and whether this session passed the email code (2FA, B3.2)
--   email codes      mfa_issue() (service role: the app emails the code), mfa_verify() (the user), trusted devices
--   settings         versioned key/value, written only through set_setting() with a reason
--   events, audit_log, sign_in_log   append-only

create schema if not exists b2c;
grant usage on schema b2c to authenticated, service_role;
-- functions are private unless granted explicitly (Postgres otherwise lets PUBLIC execute every new function)
alter default privileges in schema b2c revoke execute on functions from public;

-- ---------- people ----------
create table if not exists b2c.users (
  user_id uuid primary key references auth.users (id) on delete restrict,
  email text not null unique check (email = lower(email)),
  full_name text,
  role text not null default 'counsellor' check (role in ('admin', 'marketing', 'counsellor', 'sales_head')),
  is_active boolean not null default false,
  phone text,
  team text,
  languages text[] not null default '{}',
  skills jsonb not null default '{}'::jsonb,          -- {programmes:[], universities:[], levels:[], territories:[], sources:[]}
  weight int not null default 1 check (weight between 1 and 10),
  monthly_cap int not null default 200 check (monthly_cap >= 0),
  open_cap int check (open_cap is null or open_cap >= 0),
  daily_cap int check (daily_cap is null or daily_cap >= 0),
  monthly_target jsonb not null default '{}'::jsonb,  -- {calls, connected, counselled, applications, enrollments, commission}
  takes_leads boolean not null default true,          -- for the Admin: "Admin takes leads" (B7.3)
  is_test_user boolean not null default false,        -- test accounts: the only people test leads are ever allocated to
  on_call boolean not null default false,
  away_until timestamptz,
  tz text not null default 'Asia/Kolkata',
  workspace_user_id text,
  job_title text,
  photo_url text,
  synced_at timestamptz,
  invited_at timestamptz,
  invite_token_hash text,
  push_subscription jsonb,
  deactivated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  actor_id uuid
);
alter table b2c.users enable row level security;

create table if not exists b2c.sign_in_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  email text,
  user_id uuid,
  method text not null,
  outcome text not null,
  ip text,
  user_agent text,
  detail jsonb not null default '{}'::jsonb
);
alter table b2c.sign_in_log enable row level security;
create index if not exists sign_in_log_email_at on b2c.sign_in_log (email, at desc);

-- 2FA: a session passes once per sign-in (or on a trusted device)
create table if not exists b2c.session_checks (
  session_id uuid primary key,
  user_id uuid not null references b2c.users (user_id),
  method text not null check (method in ('email_code', 'trusted_device')),
  at timestamptz not null default now()
);
alter table b2c.session_checks enable row level security;

create table if not exists b2c.email_codes (
  id bigint generated always as identity primary key,
  user_id uuid not null references b2c.users (user_id),
  session_id uuid not null,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
alter table b2c.email_codes enable row level security;
create index if not exists email_codes_session on b2c.email_codes (session_id, created_at desc);

create table if not exists b2c.trusted_devices (
  token_hash text primary key,
  user_id uuid not null references b2c.users (user_id),
  label text,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
alter table b2c.trusted_devices enable row level security;

-- ---------- settings, events, audit ----------
create table if not exists b2c.settings (
  key text primary key,
  value jsonb not null,
  version int not null default 1,
  updated_at timestamptz not null default now(),
  actor_id uuid
);
alter table b2c.settings enable row level security;

create table if not exists b2c.settings_versions (
  id bigint generated always as identity primary key,
  key text not null,
  version int not null,
  value jsonb not null,
  reason text not null,
  actor_id uuid,
  at timestamptz not null default now()
);
alter table b2c.settings_versions enable row level security;

create table if not exists b2c.events (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  type text not null,
  lead_id bigint,
  actor_type text not null default 'user',
  actor_id uuid,
  payload jsonb not null default '{}'::jsonb
);
alter table b2c.events enable row level security;
create index if not exists events_lead_at on b2c.events (lead_id, at desc);
create index if not exists events_type_at on b2c.events (type, at desc);

create table if not exists b2c.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id uuid,
  action text not null,          -- phone_reveal, call_tap, export, view_as_sales, contact_edit, delete, settings …
  lead_id bigint,
  detail jsonb not null default '{}'::jsonb
);
alter table b2c.audit_log enable row level security;
create index if not exists audit_log_actor_at on b2c.audit_log (actor_id, at desc);

-- append-only: no update or delete on events, audit_log, sign_in_log, settings_versions
create or replace function b2c.forbid_change() returns trigger language plpgsql set search_path = '' as $f$
begin
  raise exception '% is append-only', tg_table_name;
end $f$;
do $d$
declare t text;
begin
  foreach t in array array['events', 'audit_log', 'sign_in_log', 'settings_versions'] loop
    if not exists (select 1 from pg_trigger where tgname = t || '_append_only') then
      execute format('create trigger %I before update or delete on b2c.%I for each row execute function b2c.forbid_change()', t || '_append_only', t);
    end if;
  end loop;
end $d$;

-- ---------- who is signed in ----------
create or replace function b2c.uid() returns uuid language sql stable set search_path = '' as $f$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid
$f$;

create or replace function b2c.session_id() returns uuid language sql stable set search_path = '' as $f$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id', '')::uuid
$f$;

/* The signed-in user's B2C access. checked = this session passed the email code or came from a trusted device. */
create or replace function b2c.me() returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object(
    'user_id', b2c.uid(),
    'email', (select u.email from auth.users u where u.id = b2c.uid()),
    'known', u.user_id is not null,
    'active', coalesce(u.is_active, false),
    'role', u.role,
    'full_name', u.full_name,
    'checked', exists (select 1 from b2c.session_checks c where c.session_id = b2c.session_id() and c.user_id = b2c.uid()),
    'interface', case u.role when 'counsellor' then 'sales' when 'sales_head' then 'sales' when 'marketing' then 'marketing' when 'admin' then 'admin' end)
  from (select 1) one left join b2c.users u on u.user_id = b2c.uid()
$f$;

/* Staff = active user whose session passed 2FA. Every b2c function a person calls starts with b2c.require(...). */
create or replace function b2c.my_role() returns text language sql stable security definer set search_path = '' as $f$
  select u.role from b2c.users u
   where u.user_id = b2c.uid() and u.is_active
     and exists (select 1 from b2c.session_checks c where c.session_id = b2c.session_id() and c.user_id = u.user_id)
$f$;

/* Permissions by role (B3.1). Marketing sees everything and acts only on marketing. */
create or replace function b2c.can(p_perm text) returns boolean language sql stable security definer set search_path = '' as $f$
  select case b2c.my_role()
    when 'admin' then true
    when 'marketing' then p_perm in ('read_all', 'read_money', 'marketing', 'tags', 'journey_membership', 'replies', 'templates_marketing', 'analytics')
    when 'sales_head' then p_perm in ('read_team', 'work_leads', 'reassign', 'stage_override', 'templates_sales_email')
    when 'counsellor' then p_perm in ('work_leads', 'templates_sales_email')
    else false end
$f$;

create or replace function b2c.require(p_perm text) returns uuid language plpgsql stable security definer set search_path = '' as $f$
begin
  if not coalesce(b2c.can(p_perm), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2c.uid();
end $f$;

create or replace function b2c.is_staff() returns boolean language sql stable security definer set search_path = '' as $f$
  select b2c.my_role() is not null
$f$;

-- ---------- email code (2FA) ----------
/* Service role only: issues a code for this user's session; the app emails it. 6 digits, 10 minutes, 5 attempts.
   At most 5 codes per user per hour. */
create or replace function b2c.mfa_issue(p_user uuid, p_session uuid) returns text language plpgsql security definer set search_path = '' as $f$
declare v_code text;
begin
  if not exists (select 1 from b2c.users where user_id = p_user and is_active) then raise exception 'not an active user'; end if;
  if (select count(*) from b2c.email_codes where user_id = p_user and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'too many codes: try again in an hour';
  end if;
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into b2c.email_codes (user_id, session_id, code_hash, expires_at)
  values (p_user, p_session, extensions.crypt(v_code, extensions.gen_salt('bf', 8)), now() + interval '10 minutes');
  return v_code;
end $f$;

/* The signed-in user enters the code. Optionally trusts this device for 30 days: returns a device token the app keeps
   in an httpOnly cookie (only its hash is stored). */
create or replace function b2c.mfa_verify(p_code text, p_trust boolean default false, p_label text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare c b2c.email_codes; v_token text;
begin
  if b2c.uid() is null or b2c.session_id() is null then raise exception 'sign in first'; end if;
  select * into c from b2c.email_codes
   where user_id = b2c.uid() and session_id = b2c.session_id() and used_at is null
   order by created_at desc limit 1 for update;
  if c.id is null then raise exception 'no code was sent: ask for a new one'; end if;
  if c.expires_at < now() then raise exception 'the code has expired: ask for a new one'; end if;
  if c.attempts >= 5 then raise exception 'too many attempts: ask for a new code'; end if;
  if extensions.crypt(coalesce(p_code, ''), c.code_hash) <> c.code_hash then
    update b2c.email_codes set attempts = attempts + 1 where id = c.id;
    insert into b2c.sign_in_log (email, user_id, method, outcome) select u.email, u.user_id, 'email_code', 'failed_code' from b2c.users u where u.user_id = c.user_id;
    return jsonb_build_object('ok', false, 'left', 4 - c.attempts);
  end if;
  update b2c.email_codes set used_at = now() where id = c.id;
  insert into b2c.session_checks (session_id, user_id, method) values (c.session_id, c.user_id, 'email_code') on conflict (session_id) do nothing;
  if p_trust then
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into b2c.trusted_devices (token_hash, user_id, label, expires_at)
    values (encode(extensions.digest(v_token, 'sha256'), 'hex'), c.user_id, left(p_label, 120), now() + interval '30 days');
  end if;
  insert into b2c.sign_in_log (email, user_id, method, outcome) select u.email, u.user_id, 'email_code', 'success' from b2c.users u where u.user_id = c.user_id;
  return jsonb_build_object('ok', true, 'device_token', v_token);
end $f$;

/* A trusted device skips the code: the app passes the cookie's token right after sign-in. */
create or replace function b2c.device_trust_check(p_token text) returns boolean language plpgsql security definer set search_path = '' as $f$
declare v_ok boolean;
begin
  if b2c.uid() is null or b2c.session_id() is null or p_token is null then return false; end if;
  select true into v_ok from b2c.trusted_devices d join b2c.users u on u.user_id = d.user_id and u.is_active
   where d.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and d.user_id = b2c.uid()
     and d.revoked_at is null and d.expires_at > now();
  if coalesce(v_ok, false) then
    insert into b2c.session_checks (session_id, user_id, method) values (b2c.session_id(), b2c.uid(), 'trusted_device') on conflict (session_id) do nothing;
  end if;
  return coalesce(v_ok, false);
end $f$;

/* Service role: log a sign-in attempt; the 15-minute lock after 5 failed passwords (B3.2). */
create or replace function b2c.record_sign_in(p jsonb) returns void language sql security definer set search_path = '' as $f$
  insert into b2c.sign_in_log (email, user_id, method, outcome, ip, user_agent, detail)
  values (lower(p ->> 'email'), nullif(p ->> 'user_id', '')::uuid, p ->> 'method', p ->> 'outcome', p ->> 'ip', left(p ->> 'user_agent', 300), coalesce(p -> 'detail', '{}'))
$f$;
create or replace function b2c.sign_in_locked(p_email text) returns boolean language sql stable security definer set search_path = '' as $f$
  select count(*) >= 5 from b2c.sign_in_log
   where email = lower(p_email) and outcome = 'failed_password' and at > now() - interval '15 minutes'
$f$;

-- ---------- settings ----------
create or replace function b2c.setting(p_key text) returns jsonb language sql stable security definer set search_path = '' as $f$
  select value from b2c.settings where key = p_key
$f$;

create or replace function b2c.set_setting(p_key text, p_value jsonb, p_reason text) returns int language plpgsql security definer set search_path = '' as $f$
declare v int;
begin
  perform b2c.require('settings');
  if not exists (select 1 from b2c.settings where key = p_key) then raise exception 'unknown setting %', p_key; end if;
  if jsonb_typeof(p_value) not in ('object', 'array') then raise exception 'a setting is an object or an array'; end if;
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'give a reason'; end if;
  update b2c.settings set value = p_value, version = version + 1, updated_at = now(), actor_id = b2c.uid() where key = p_key returning version into v;
  insert into b2c.settings_versions (key, version, value, reason, actor_id) values (p_key, v, p_value, p_reason, b2c.uid());
  insert into b2c.events (type, actor_id, payload) values ('setting.changed', b2c.uid(), jsonb_build_object('key', p_key, 'version', v, 'reason', p_reason));
  return v;
end $f$;

insert into b2c.settings (key, value) values
  ('live_mode', '{"whatsapp": false, "email": false}'),
  ('working_defaults', '{"days": [1,2,3,4,5,6], "start": "10:00", "end": "19:00", "tz": "Asia/Kolkata"}'),
  ('sla_minutes', '{"hot": 15, "warm": 240, "cold": 1440}'),
  ('allocation', '{"admin_takes_leads": true, "allow_outside_hours_non_hot": true, "unassigned_alert_minutes": 5, "hiring_trigger_enrollments": 10, "capacity_alert_pct": 90}'),
  ('followups', '{"reminder_minutes_before": 10, "escalate_after_minutes": 120, "call_unlogged_minutes": 10, "untouched_hours": 48}'),
  ('sync', '{"batch_minutes": 15, "reconcile_minutes": 5}'),
  ('messaging', '{"quiet_start": "09:00", "quiet_end": "20:00", "wa_marketing_per_day": 1, "wa_marketing_per_30d": 6, "email_marketing_per_day": 2, "witty_idle_minutes": 10, "gmail_daily_allowance": 2000}'),
  ('test_phones', '{"prefixes": ["910000", "9190000000"]}'),
  ('opt_out_words', '{"words": ["stop", "unsubscribe", "band karo", "bandh karo", "mat bhejo", "no more messages"]}')
on conflict (key) do nothing;

-- ---------- grants and read policies ----------
revoke all on b2c.users, b2c.sign_in_log, b2c.session_checks, b2c.email_codes, b2c.trusted_devices, b2c.settings, b2c.settings_versions, b2c.events, b2c.audit_log from anon, authenticated;
grant select on b2c.users, b2c.settings to authenticated;
do $p$
begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'users' and policyname = 'staff read users') then
    create policy "staff read users" on b2c.users for select to authenticated using ((select b2c.is_staff()) or user_id = (select b2c.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'settings' and policyname = 'staff read settings') then
    create policy "staff read settings" on b2c.settings for select to authenticated using ((select b2c.is_staff()));
  end if;
end $p$;

revoke all on all functions in schema b2c from public, anon;   -- at this point: b1's own functions
grant execute on function b2c.me(), b2c.can(text), b2c.is_staff(), b2c.uid(), b2c.session_id(), b2c.my_role(), b2c.mfa_verify(text, boolean, text), b2c.device_trust_check(text),
  b2c.setting(text), b2c.set_setting(text, jsonb, text) to authenticated;
revoke execute on function b2c.mfa_issue(uuid, uuid), b2c.record_sign_in(jsonb), b2c.sign_in_locked(text) from authenticated;
grant execute on function b2c.mfa_issue(uuid, uuid), b2c.record_sign_in(jsonb), b2c.sign_in_locked(text) to service_role;
grant all on all tables in schema b2c to service_role;
grant all on all sequences in schema b2c to service_role;
