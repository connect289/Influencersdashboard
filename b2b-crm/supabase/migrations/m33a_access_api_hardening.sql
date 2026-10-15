-- M33a (15 Oct): access and API hardening, the first of the "industry grade" gap closures (docs/b2b-design.md, M33).
--   (1) Roles. b2b.app_users.role is 'admin' or 'viewer'. A viewer sees every screen and changes nothing: b2b.is_admin()
--       is true for a viewer only inside a read-only transaction. PostgREST runs STABLE / IMMUTABLE functions and every
--       GET in a READ ONLY transaction, so reads pass; every write function is VOLATILE and runs READ WRITE, so a viewer
--       is refused with 'not allowed' (42501) at the database, whatever the screen offered. b2b.me() reports read_only.
--   (2) Team. Invitations by email (b2b.team_invites, 14 days): the first sign-in with that Google or password identity
--       creates the b2b.app_users row with the invited role (team_invite_accept, called by the app's sign-in flow as the
--       service role). team_list, team_invite, team_invite_revoke, team_member_update (role, active, TOTP rule, note),
--       with guards: you cannot change your own access, and the last active admin cannot be removed or demoted.
--   (3) API keys. expires_at (optional, at most 2 years; an expired key answers 401), rate_per_minute (per key) with
--       defaults per scope in setting api_limits, counted in b2b.api_key_usage per minute. Over the limit, api_key_check
--       raises SQLSTATE P0429 and the API routes answer HTTP 429 with Retry-After. api_key_create(p jsonb) and
--       api_key_update replace the two-argument create_api_key for the screen (the old function stays).
--       b2b-api-keys-expiry (daily) alerts 7 days before a key expires (alert.api_key_expiring) and prunes old usage rows.
--   (4) health_check(): a small, non-sensitive status for uptime monitors (GET /api/health), callable by anon.
--   (5) system_overview REPLACED (m14b): the keys carry expiry, limit and recent use.
-- No change to student_leads, Witty or the B2C contract. Re-appliable.

-- ---------- (1) roles ----------
alter table b2b.app_users drop constraint if exists app_users_role_check;
alter table b2b.app_users add constraint app_users_role_check check (role in ('admin', 'viewer'));
alter table b2b.app_users add column if not exists invited_by uuid;
alter table b2b.app_users add column if not exists note text;
alter table b2b.app_users add column if not exists last_seen_at timestamptz;

/* The signed-in user's role (null when not on the team or inactive). */
create or replace function b2b.my_role()
returns text language sql stable security definer set search_path = '' as $fn$
  select u.role from b2b.app_users u where u.user_id = auth.uid() and u.is_active;
$fn$;

/* True for an active admin whose session meets the TOTP rule (m2g), and for an active viewer under the same rule inside
   a read-only transaction (PostgREST: GET, or a STABLE / IMMUTABLE function). Writes are VOLATILE, so a viewer never
   passes a write. */
create or replace function b2b.is_admin()
returns boolean language sql stable security definer set search_path = '' as $fn$
  select exists (
    select 1 from b2b.app_users u
     where u.user_id = auth.uid() and u.is_active
       and (u.role = 'admin' or (u.role = 'viewer' and current_setting('transaction_read_only', true) = 'on'))
       and (
         coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
         or (
           not u.require_totp
           and jsonb_typeof(auth.jwt() -> 'amr') = 'array'
           and jsonb_array_length(auth.jwt() -> 'amr') > 0
           and not exists (select 1 from jsonb_array_elements(auth.jwt() -> 'amr') m where coalesce(m ->> 'method', '') <> 'oauth')
         )
       ));
$fn$;

create or replace function b2b.me()
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select jsonb_build_object(
    'user_id',      auth.uid(),
    'email',        auth.jwt() ->> 'email',
    'aal',          coalesce(auth.jwt() ->> 'aal', 'aal1'),
    'allowlisted',  u.user_id is not null and coalesce(u.is_active, false),
    'role',         u.role,
    'read_only',    coalesce(u.role = 'viewer', false),
    'require_totp', coalesce(u.require_totp, true),
    'is_admin',     b2b.is_admin())
  from (select 1) one
  left join b2b.app_users u on u.user_id = auth.uid();
$fn$;

-- ---------- (2) the team ----------
create table if not exists b2b.team_invites (
  id                bigint generated always as identity primary key,
  email             text not null check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  role              text not null check (role in ('admin', 'viewer')),
  note              text,
  invited_by        uuid,
  created_at        timestamptz not null default now(),
  expires_at        timestamptz not null default now() + interval '14 days',
  accepted_at       timestamptz,
  accepted_user_id  uuid,
  revoked_at        timestamptz
);
create unique index if not exists team_invites_open_uq on b2b.team_invites (email) where accepted_at is null and revoked_at is null;
alter table b2b.team_invites enable row level security;
do $p$ begin
  if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = 'team_invites' and policyname = 'admin_read') then
    create policy admin_read on b2b.team_invites for select to authenticated using ((select b2b.is_admin()));
  end if;
end $p$;
revoke all on b2b.team_invites from public, anon, authenticated;
grant select on b2b.team_invites to authenticated;
grant all on b2b.team_invites to service_role;

/* The team: members with their last successful sign-in, and open invitations. */
create or replace function b2b.team_list()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'members', coalesce((select jsonb_agg(jsonb_build_object(
        'user_id', u.user_id, 'email', u.email, 'role', u.role, 'is_active', u.is_active, 'require_totp', u.require_totp, 'note', u.note,
        'created_at', u.created_at, 'invited_by', (select i.email from b2b.app_users i where i.user_id = u.invited_by),
        'last_sign_in_at', (select max(s.at) from b2b.sign_in_log s where lower(s.email) = u.email and s.outcome = 'success'),
        'me', u.user_id = auth.uid()) order by u.is_active desc, u.role, u.email) from b2b.app_users u), '[]'),
    'invites', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'email', i.email, 'role', i.role, 'note', i.note, 'created_at', i.created_at, 'expires_at', i.expires_at,
        'expired', i.expires_at < now(), 'invited_by', (select x.email from b2b.app_users x where x.user_id = i.invited_by)) order by i.created_at desc)
        from b2b.team_invites i where i.accepted_at is null and i.revoked_at is null), '[]'),
    'active_admins', (select count(*) from b2b.app_users where is_active and role = 'admin'));
end $fn$;

/* Invite someone by email. They sign in with Google or a password on that address; the first sign-in joins them with
   this role. An open invitation for the address is replaced. */
create or replace function b2b.team_invite(p_email text, p_role text, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_id bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 200 then raise exception 'give an email address' using errcode = '22023'; end if;
  if coalesce(p_role, '') not in ('admin', 'viewer') then raise exception 'role is admin or viewer' using errcode = '22023'; end if;
  if exists (select 1 from b2b.app_users u where u.email = v_email) then raise exception 'this person is already on the team' using errcode = '22023'; end if;
  update b2b.team_invites set revoked_at = now() where email = v_email and accepted_at is null and revoked_at is null;
  insert into b2b.team_invites (email, role, note, invited_by) values (v_email, p_role, left(trim(p_note), 300), auth.uid()) returning id into v_id;
  perform b2b.log_event('team.invited', null, null, null, jsonb_build_object('invite_id', v_id, 'email', v_email, 'role', p_role));
  return jsonb_build_object('id', v_id, 'email', v_email, 'role', p_role, 'expires_at', now() + interval '14 days');
end $fn$;

create or replace function b2b.team_invite_revoke(p_id bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare v_email text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.team_invites set revoked_at = now() where id = p_id and accepted_at is null and revoked_at is null returning email into v_email;
  if v_email is not null then perform b2b.log_event('team.invite_revoked', null, null, null, jsonb_build_object('invite_id', p_id, 'email', v_email)); end if;
  return v_email is not null;
end $fn$;

/* The app's sign-in flow (service role) calls this for an authenticated identity that is not on the team yet: an open,
   unexpired invitation for the address joins them. Returns true when a member row was created. */
create or replace function b2b.team_invite_accept(p_user_id uuid, p_email text)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.team_invites;
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if p_user_id is null or v_email = '' then return false; end if;
  if exists (select 1 from b2b.app_users u where u.user_id = p_user_id) then return false; end if;
  if not exists (select 1 from auth.users a where a.id = p_user_id and lower(a.email) = v_email) then return false; end if;
  select * into i from b2b.team_invites t where t.email = v_email and t.accepted_at is null and t.revoked_at is null and t.expires_at > now()
   order by t.id desc limit 1 for update;
  if i.id is null then return false; end if;
  insert into b2b.app_users (user_id, email, role, is_active, require_totp, invited_by, note)
  values (p_user_id, v_email, i.role, true, true, i.invited_by, i.note)
  on conflict (user_id) do nothing;
  update b2b.team_invites set accepted_at = now(), accepted_user_id = p_user_id where id = i.id;
  perform set_config('b2b.actor', 'system', true);
  perform b2b.log_event('team.joined', null, null, null, jsonb_build_object('invite_id', i.id, 'email', v_email, 'role', i.role, 'user_id', p_user_id));
  return true;
end $fn$;

/* Change a member: p = {role?, is_active?, require_totp?, note?}. Not your own access; never the last active admin. */
create or replace function b2b.team_member_update(p_user_id uuid, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  u b2b.app_users;
  v_role text;
  v_active boolean;
  v_totp boolean;
  v_admins int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into u from b2b.app_users where user_id = p_user_id for update;
  if u.user_id is null then raise exception 'member not found' using errcode = 'P0002'; end if;
  v_role := coalesce(p ->> 'role', u.role);
  v_active := coalesce((p ->> 'is_active')::boolean, u.is_active);
  v_totp := coalesce((p ->> 'require_totp')::boolean, u.require_totp);
  if v_role not in ('admin', 'viewer') then raise exception 'role is admin or viewer' using errcode = '22023'; end if;
  if u.user_id = auth.uid() and (v_role <> u.role or v_active <> u.is_active) then
    raise exception 'you cannot change your own access; ask another admin' using errcode = '22023';
  end if;
  select count(*) into v_admins from b2b.app_users x where x.is_active and x.role = 'admin' and x.user_id <> u.user_id;
  if v_admins = 0 and (v_role <> 'admin' or not v_active) then
    raise exception 'this is the last active admin; add another admin first' using errcode = '22023';
  end if;
  update b2b.app_users
     set role = v_role, is_active = v_active, require_totp = v_totp,
         note = case when p ? 'note' then left(nullif(trim(p ->> 'note'), ''), 300) else note end, updated_at = now()
   where user_id = u.user_id;
  perform b2b.log_event('team.updated', null, null, null, jsonb_build_object('user_id', u.user_id, 'email', u.email,
                        'changes', jsonb_strip_nulls(jsonb_build_object(
                          'role', case when v_role <> u.role then jsonb_build_object('from', u.role, 'to', v_role) end,
                          'is_active', case when v_active <> u.is_active then jsonb_build_object('from', u.is_active, 'to', v_active) end,
                          'require_totp', case when v_totp <> u.require_totp then jsonb_build_object('from', u.require_totp, 'to', v_totp) end))));
  return jsonb_build_object('user_id', u.user_id, 'role', v_role, 'is_active', v_active, 'require_totp', v_totp);
end $fn$;

-- ---------- (3) API keys: expiry and rate limits ----------
alter table b2b.api_keys add column if not exists expires_at timestamptz;
alter table b2b.api_keys add column if not exists rate_per_minute int check (rate_per_minute is null or rate_per_minute between 1 and 100000);
alter table b2b.api_keys add column if not exists note text;

create table if not exists b2b.api_key_usage (
  api_key_id  bigint not null,
  minute      timestamptz not null,
  n           int not null default 0,
  primary key (api_key_id, minute)
);
alter table b2b.api_key_usage enable row level security;
revoke all on b2b.api_key_usage from public, anon, authenticated;
grant all on b2b.api_key_usage to service_role;

insert into b2b.settings (key, value)
values ('api_limits', '{"per_minute": {"intake": 120, "referrals": 60, "events": 300, "b2c": 600, "ai_worker": 600}, "default": 300}')
on conflict (key) do nothing;

/* Checks a key for a scope and counts the call. Answers {ok:false} for an unknown, revoked, expired or out-of-scope key
   (the callers answer 401). Over the key's limit (its own rate_per_minute, else api_limits.per_minute[scope], else
   api_limits.default), raises SQLSTATE P0429 'rate limited', which the API routes turn into HTTP 429 + Retry-After.
   The raise rolls back the caller's transaction, so a refused call writes nothing, and its count stays at the limit. */
create or replace function b2b.api_key_check(p_key text, p_scope text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k b2b.api_keys;
  v_limit int;
  v_n int;
  v_minute timestamptz := date_trunc('minute', now());
  lim jsonb := coalesce((select value from b2b.settings where key = 'api_limits'), '{}');
begin
  select * into k from b2b.api_keys
   where key_hash = encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex') and revoked_at is null;
  if k.id is null or not (p_scope = any (k.scopes)) then
    return jsonb_build_object('ok', false);
  end if;
  if k.expires_at is not null and k.expires_at <= now() then
    return jsonb_build_object('ok', false, 'why', 'expired');
  end if;
  v_limit := coalesce(k.rate_per_minute,
                      case when (lim -> 'per_minute' ->> p_scope) ~ '^[0-9]+$' then (lim -> 'per_minute' ->> p_scope)::int end,
                      case when (lim ->> 'default') ~ '^[0-9]+$' then (lim ->> 'default')::int end, 300);
  insert into b2b.api_key_usage (api_key_id, minute, n) values (k.id, v_minute, 1)
  on conflict (api_key_id, minute) do update set n = b2b.api_key_usage.n + 1
  returning n into v_n;
  if v_n > v_limit then
    -- the raise rolls this transaction back, so the usage row stays at the limit and nothing else is written
    raise exception 'rate limited: more than % requests per minute for this key (scope %)', v_limit, p_scope
      using errcode = 'P0429', hint = 'retry after ' || (60 - extract(second from now()))::int || ' seconds';
  end if;
  update b2b.api_keys set last_used_at = now() where id = k.id and (last_used_at is null or last_used_at < now() - interval '1 minute');
  return jsonb_build_object('ok', true, 'api_key_id', k.id, 'name', k.name, 'remaining', v_limit - v_n);
end $fn$;

/* Admin: a new key. p = {name, scopes [], expires_at?, rate_per_minute?, note?}. The key is shown once. */
create or replace function b2b.api_key_create(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_key text := 'eb2b_' || encode(extensions.gen_random_bytes(24), 'hex');
  v_id bigint;
  v_scopes text[];
  v_exp timestamptz := b2b.try_timestamptz(p ->> 'expires_at');
  v_rate int := case when (p ->> 'rate_per_minute') ~ '^[0-9]{1,6}$' then (p ->> 'rate_per_minute')::int end;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p ->> 'name', ''))) < 2 then raise exception 'give the key a name' using errcode = '22023'; end if;
  select array_agg(x) into v_scopes from jsonb_array_elements_text(case when jsonb_typeof(p -> 'scopes') = 'array' then p -> 'scopes' else '[]'::jsonb end) x;
  if v_scopes is null or cardinality(v_scopes) = 0 then raise exception 'choose at least one scope' using errcode = '22023'; end if;
  if p ? 'expires_at' and nullif(p ->> 'expires_at', '') is not null and v_exp is null then raise exception 'expires_at must be a date and time' using errcode = '22023'; end if;
  if v_exp is not null and (v_exp <= now() or v_exp > now() + interval '2 years') then raise exception 'expiry must be in the future and within 2 years' using errcode = '22023'; end if;
  if p ? 'rate_per_minute' and nullif(p ->> 'rate_per_minute', '') is not null and (v_rate is null or v_rate not between 1 and 100000) then
    raise exception 'the limit is 1 to 100,000 requests per minute' using errcode = '22023';
  end if;
  insert into b2b.api_keys (name, scopes, key_prefix, key_hash, created_by, expires_at, rate_per_minute, note)
  values (left(trim(p ->> 'name'), 80), v_scopes, left(v_key, 12), encode(extensions.digest(v_key, 'sha256'), 'hex'), auth.uid(), v_exp, v_rate, left(nullif(trim(p ->> 'note'), ''), 300))
  returning id into v_id;
  perform b2b.log_event('api_key.created', null, null, null, jsonb_build_object('api_key_id', v_id, 'name', p ->> 'name', 'scopes', to_jsonb(v_scopes),
                        'expires_at', v_exp, 'rate_per_minute', v_rate));
  return jsonb_build_object('id', v_id, 'key', v_key);
end $fn$;

/* Admin: rename, re-date or re-limit a key. p = {name?, expires_at? (null clears), rate_per_minute? (null clears), note?}. */
create or replace function b2b.api_key_update(p_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k b2b.api_keys;
  v_exp timestamptz;
  v_rate int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into k from b2b.api_keys where id = p_id and revoked_at is null for update;
  if k.id is null then raise exception 'key not found' using errcode = 'P0002'; end if;
  v_exp := case when p ? 'expires_at' then b2b.try_timestamptz(p ->> 'expires_at') else k.expires_at end;
  if p ? 'expires_at' and nullif(p ->> 'expires_at', '') is not null and v_exp is null then raise exception 'expires_at must be a date and time' using errcode = '22023'; end if;
  if v_exp is not null and v_exp > now() + interval '2 years' then raise exception 'expiry must be within 2 years' using errcode = '22023'; end if;
  v_rate := case when p ? 'rate_per_minute' then case when (p ->> 'rate_per_minute') ~ '^[0-9]{1,6}$' then (p ->> 'rate_per_minute')::int end else k.rate_per_minute end;
  if p ? 'rate_per_minute' and nullif(p ->> 'rate_per_minute', '') is not null and (v_rate is null or v_rate not between 1 and 100000) then
    raise exception 'the limit is 1 to 100,000 requests per minute' using errcode = '22023';
  end if;
  update b2b.api_keys
     set name = coalesce(nullif(left(trim(p ->> 'name'), 80), ''), name), expires_at = v_exp, rate_per_minute = v_rate,
         note = case when p ? 'note' then left(nullif(trim(p ->> 'note'), ''), 300) else note end
   where id = k.id;
  perform b2b.log_event('api_key.updated', null, null, null, jsonb_build_object('api_key_id', k.id, 'changes', p));
  return jsonb_build_object('id', k.id, 'expires_at', v_exp, 'rate_per_minute', v_rate);
end $fn$;

/* Daily: an alert 7 days before a key expires (once a day per key) and when it has expired; usage rows older than 2 days go. */
create or replace function b2b.api_keys_expiry_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  n int := 0;
begin
  perform set_config('b2b.actor', 'engine', true);
  for r in select k.* from b2b.api_keys k where k.revoked_at is null and k.expires_at is not null and k.expires_at < now() + interval '7 days' loop
    if not exists (select 1 from b2b.events e where e.type = 'alert.api_key_expiring' and (e.payload ->> 'api_key_id')::bigint = r.id and e.occurred_at > now() - interval '23 hours') then
      perform b2b.log_event('alert.api_key_expiring', null, null, null, jsonb_build_object('api_key_id', r.id, 'name', r.name, 'expires_at', r.expires_at,
                            'expired', r.expires_at <= now(), 'scopes', to_jsonb(r.scopes)));
      n := n + 1;
    end if;
  end loop;
  delete from b2b.api_key_usage where minute < now() - interval '2 days';
  return jsonb_build_object('alerted', n);
end $fn$;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-api-keys-expiry';
  perform cron.schedule('b2b-api-keys-expiry', '15 3 * * *', 'select b2b.api_keys_expiry_tick()');
end $cron$;

-- ---------- (4) health for uptime monitors ----------
/* No admin check and nothing sensitive: counts only. ok is false when a frequent job (every minute or faster) has not
   run for 15 minutes, when the last run of any b2b job failed, or when the B2C sync cursor is older than 10 minutes. */
create or replace function b2b.health_check()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_stale int;
  v_failed int;
  v_dead int;
  v_waiting int;
  v_cursor_age numeric;
begin
  select count(*) into v_stale
    from cron.job j
   where j.jobname like 'b2b-%' and j.active and (j.schedule ~ 'second' or j.schedule ~ '^\* \* \* \* \*$')
     and coalesce((select max(d.start_time) from cron.job_run_details d where d.jobid = j.jobid), '-infinity') < now() - interval '15 minutes';
  select count(*) into v_failed
    from cron.job j
   where j.jobname like 'b2b-%' and j.active
     and (select d.status from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1) = 'failed';
  select count(*) filter (where status = 'dead'), count(*) filter (where status in ('pending', 'failed') and created_at < now() - interval '1 hour')
    into v_dead, v_waiting from b2b.integration_outbox where endpoint_id is not null and created_at > now() - interval '7 days';
  select extract(epoch from now() - (value ->> 'last_run')::timestamptz) into v_cursor_age from b2b.b2c_link_state where key = 'cursor';
  return jsonb_build_object(
    'ok', v_stale = 0 and v_failed = 0 and coalesce(v_cursor_age, 0) < 600,
    'at', now(),
    'jobs', jsonb_build_object('stale', v_stale, 'last_run_failed', v_failed),
    'deliveries', jsonb_build_object('dead_7d', v_dead, 'waiting_over_1h', v_waiting),
    'b2c_sync', jsonb_build_object('cursor_age_seconds', round(coalesce(v_cursor_age, 0))));
end $fn$;

-- ---------- (5) system overview with the key details ----------
create or replace function b2b.system_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'api_keys', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'scopes', k.scopes, 'prefix', k.key_prefix, 'created_at', k.created_at,
                                                              'last_used_at', k.last_used_at, 'revoked_at', k.revoked_at,
                                                              -- M33a: expiry, the per-minute limit and recent use
                                                              'expires_at', k.expires_at, 'rate_per_minute', k.rate_per_minute, 'note', k.note,
                                                              'requests_1h', (select coalesce(sum(u.n), 0) from b2b.api_key_usage u where u.api_key_id = k.id and u.minute > now() - interval '1 hour'),
                                                              'requests_24h', (select coalesce(sum(u.n), 0) from b2b.api_key_usage u where u.api_key_id = k.id and u.minute > now() - interval '24 hours'))
                                                   order by k.revoked_at nulls first, k.created_at desc)
                          from b2b.api_keys k), '[]'),
    'api_limits', coalesce((select value from b2b.settings where key = 'api_limits'), '{}'),
    'endpoints', coalesce((select jsonb_agg(to_jsonb(w) - 'secret_id' || jsonb_build_object('has_secret', w.secret_id is not null,
                             'pending', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')),
                             'dead', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'dead'),
                             'delivered_24h', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'delivered' and o.delivered_at > now() - interval '1 day'))
                           order by w.id) from b2b.webhook_endpoints w), '[]'),
    'deliveries', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'event_type', o.event_type, 'endpoint_id', o.endpoint_id,
                              'endpoint', (select w.name from b2b.webhook_endpoints w where w.id = o.endpoint_id), 'status', o.status, 'attempts', o.attempts,
                              'response_status', o.response_status, 'last_error', o.last_error, 'created_at', o.created_at, 'delivered_at', o.delivered_at,
                              'next_attempt_at', o.next_attempt_at, 'lead_id', (o.payload ->> 'lead_id')::bigint) order by o.id desc)
                            from (select * from b2b.integration_outbox where endpoint_id is not null order by id desc limit 100) o), '[]'),
    'product_events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'source', e.source, 'event_type', e.event_type, 'lead_id', e.lead_id,
                                  'status', e.status, 'result', e.result, 'received_at', e.received_at) order by e.id desc)
                                from (select * from b2b.product_events order by id desc limit 50) e), '[]'),
    'erasure_open', (select count(*) from b2b.erasure_requests where status = 'open'),
    'jobs', coalesce((select jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active,
                         'last_status', (select d.status from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1),
                         'last_run', (select d.start_time from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1),
                         'last_error', (select left(d.return_message, 200) from cron.job_run_details d where d.jobid = j.jobid and d.status = 'failed'
                                          and d.start_time > now() - interval '1 day' order by d.start_time desc limit 1),
                         'failed_24h', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.status = 'failed' and d.start_time > now() - interval '1 day'))
                       order by j.jobname) from cron.job j where j.jobname like 'b2b-%'), '[]'));
end $fn$;

-- ---------- grants ----------
revoke execute on function b2b.my_role(), b2b.is_admin(), b2b.me() from public, anon;
grant execute on function b2b.my_role(), b2b.is_admin(), b2b.me() to authenticated, service_role;
revoke execute on function b2b.team_list(), b2b.team_invite(text, text, text), b2b.team_invite_revoke(bigint), b2b.team_member_update(uuid, jsonb),
                           b2b.api_key_create(jsonb), b2b.api_key_update(bigint, jsonb), b2b.system_overview() from public, anon;
grant execute on function b2b.team_list(), b2b.team_invite(text, text, text), b2b.team_invite_revoke(bigint), b2b.team_member_update(uuid, jsonb),
                          b2b.api_key_create(jsonb), b2b.api_key_update(bigint, jsonb), b2b.system_overview() to authenticated, service_role;
revoke execute on function b2b.team_invite_accept(uuid, text), b2b.api_keys_expiry_tick() from public, anon, authenticated;
grant execute on function b2b.team_invite_accept(uuid, text), b2b.api_keys_expiry_tick() to service_role;
revoke execute on function b2b.api_key_check(text, text) from public, anon, authenticated;
grant execute on function b2b.api_key_check(text, text) to service_role;
revoke execute on function b2b.health_check() from public;
grant execute on function b2b.health_check() to anon, authenticated, service_role;
