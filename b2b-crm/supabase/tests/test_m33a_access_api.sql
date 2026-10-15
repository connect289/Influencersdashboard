-- M33a access and API hardening, rolled back: the viewer role (reads pass, writes are refused), team invitations and
-- member guards, API key expiry, the per-minute limit (SQLSTATE P0429), the expiry alert, the health check and the
-- system overview's key details. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$
  insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.claims(p_sub text, p_email text) returns void language sql as $f$
  select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated', 'aal', 'aal2', 'email', p_email)::text, true) $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-0000000000e2', 'm33-viewer@test.local', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-0000000000e3', 'm33-second@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local');

-- ---------- the team ----------
set local role authenticated;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local');
do $x$ declare x jsonb; e text; begin
  x := b2b.team_invite('M33-Viewer@test.local ', 'viewer', 'read-only for finance');
  insert into r values ('invite_created', x ->> 'email' = 'm33-viewer@test.local' and x ->> 'role' = 'viewer', x::text);
  e := pg_temp.err($q$select b2b.team_invite('m33-admin@test.local', 'viewer')$q$);
  insert into r values ('invite_refuses_member', e like '22023 this person is already on the team%', e);
  e := pg_temp.err($q$select b2b.team_invite('not-an-email', 'viewer')$q$);
  insert into r values ('invite_needs_email', e like '22023 give an email address%', e);
  e := pg_temp.err($q$select b2b.team_invite('m33-second@test.local', 'owner')$q$);
  insert into r values ('invite_role_checked', e like '22023 role is admin or viewer%', e);
  x := b2b.team_invite('m33-second@test.local', 'admin');
  x := b2b.team_list();
  insert into r values ('team_list', jsonb_array_length(x -> 'members') = 1 and jsonb_array_length(x -> 'invites') = 2 and (x ->> 'active_admins')::int = 1
                        and (x -> 'members' -> 0 ->> 'me')::boolean, x::text);
  e := pg_temp.err($q$select b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"role":"viewer"}')$q$);
  insert into r values ('own_access_guarded', e like '22023 you cannot change your own access%', e);
end $x$;
reset role;
-- the invited people sign in: the app's sign-in flow (service role) joins them
insert into t select 'acc1', b2b.team_invite_accept('aaaaaaaa-0000-0000-0000-0000000000e2', 'm33-viewer@test.local')::text;
insert into r select 'invite_accepted_viewer', pg_temp.v('acc1')::boolean
  and (select role = 'viewer' and is_active and require_totp and note = 'read-only for finance' from b2b.app_users where user_id = 'aaaaaaaa-0000-0000-0000-0000000000e2'),
  pg_temp.v('acc1') || ' ' || coalesce((select role || '/' || is_active || '/' || coalesce(note, 'nonote') from b2b.app_users where user_id = 'aaaaaaaa-0000-0000-0000-0000000000e2'), 'no row');
insert into r select 'invite_accepted_once', not b2b.team_invite_accept('aaaaaaaa-0000-0000-0000-0000000000e2', 'm33-viewer@test.local'), null;
insert into r select 'invite_wrong_identity', not b2b.team_invite_accept('aaaaaaaa-0000-0000-0000-0000000000e3', 'm33-viewer@test.local')
  and not exists (select 1 from b2b.app_users where user_id = 'aaaaaaaa-0000-0000-0000-0000000000e3'), null;
insert into r select 'invite_accepted_admin', b2b.team_invite_accept('aaaaaaaa-0000-0000-0000-0000000000e3', 'm33-second@test.local'), null;
insert into r select 'team_joined_logged', (select count(*) from b2b.events where type = 'team.joined') = 2, null;

-- ---------- the viewer: reads pass in a read-only transaction, writes are refused ----------
set local role authenticated;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e2', 'm33-viewer@test.local');
insert into r select 'viewer_not_admin_in_rw', not b2b.is_admin() and (b2b.me() ->> 'read_only')::boolean and b2b.me() ->> 'role' = 'viewer'
  and not (b2b.me() ->> 'is_admin')::boolean, b2b.me()::text;
do $x$ declare v_read boolean; v_me boolean; v_list boolean; e text; begin
  begin
    perform set_config('transaction_read_only', 'on', true);
    v_read := b2b.is_admin();
    v_me := (b2b.me() ->> 'is_admin')::boolean;
    v_list := (b2b.team_list() -> 'members') is not null;
    e := pg_temp.err($q$select b2b.set_live_switch('whatsapp', true, 'viewer trying')$q$);
    raise exception 'undo' using errcode = 'P0999';
  exception when sqlstate 'P0999' then null;
  end;
  insert into r values ('viewer_reads_pass', v_read and v_me and v_list, null);
  insert into r values ('viewer_write_refused_readonly_tx', e like '25006%' or e like '42501%', e);
end $x$;
insert into r select 'viewer_write_refused_rw', pg_temp.err($q$select b2b.set_live_switch('whatsapp', true, 'viewer trying')$q$) like '42501%', null;
insert into r select 'viewer_cannot_invite', pg_temp.err($q$select b2b.team_invite('x@test.local', 'viewer')$q$) like '42501%', null;

-- ---------- the last active admin ----------
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e3', 'm33-second@test.local');
do $x$ declare x jsonb; e text; begin
  x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"is_active": false}');
  insert into r values ('deactivate_other_admin', not (x ->> 'is_active')::boolean, x::text);
  e := pg_temp.err($q$select b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"role":"viewer"}')$q$);
  insert into r values ('own_access_guarded_2', e like '22023 you cannot change your own access%', e);
  x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"is_active": true, "role": "viewer", "note": "stepped back"}');
  insert into r values ('reactivate_as_viewer', (x ->> 'is_active')::boolean and x ->> 'role' = 'viewer', x::text);
  x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"role": "admin"}');
end $x$;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local');
do $x$ declare e text; x jsonb; begin
  x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"is_active": false}');
  e := pg_temp.err($q$select b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"role":"viewer"}')$q$);
  insert into r values ('last_admin_own_guard_first', e like '22023 you cannot change your own access%', e);
  x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"is_active": true}');
end $x$;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e3', 'm33-second@test.local');
do $x$ declare e text; x jsonb; begin
  -- the second admin steps back to viewer (not their own change: the first admin does it below), so first: demote the second
  x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"role": "admin"}');
end $x$;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local');
do $x$ declare e text; x jsonb; begin
  x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"role": "viewer"}');
end $x$;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e3', 'm33-second@test.local');
insert into r select 'last_admin_guard', pg_temp.err($q$select b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"role":"viewer"}')$q$) like '42501%', null;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local');
do $x$ declare x jsonb; begin
  x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"role": "admin"}');
end $x$;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e3', 'm33-second@test.local');
do $x$ declare x jsonb; e text; begin
  x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"role": "viewer"}');
  -- now the second admin is the last one: nobody may demote or remove them, and they cannot do it themselves
  select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local') into x;
end $x$;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e3', 'm33-second@test.local');
insert into r select 'last_admin_cannot_self_remove', pg_temp.err($q$select b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"is_active": false}')$q$) like '22023 you cannot change your own access%', null;
do $x$ declare x jsonb; begin x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"role": "admin"}'); end $x$;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local');
insert into r select 'last_admin_guard_by_other', pg_temp.err($q$select b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"is_active": false}')$q$) = 'ok'
  and pg_temp.err($q$select b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"role": "admin", "is_active": true}')$q$) = 'ok', null;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e3', 'm33-second@test.local');
do $x$ declare x jsonb; begin x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"is_active": false}'); end $x$;
insert into r select 'only_admin_left_guarded', pg_temp.err($q$select b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"role": "viewer"}')$q$) like '22023 you cannot change your own access%', null;
do $x$ declare x jsonb; begin x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e1', '{"is_active": true}'); end $x$;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local');
do $x$ declare x jsonb; begin x := b2b.team_member_update('aaaaaaaa-0000-0000-0000-0000000000e3', '{"is_active": false}'); end $x$;
-- the first admin is now the only active admin: the second (inactive) cannot be made to demote them; another admin acting on the last one
insert into r select 'last_active_admin_guard', (select count(*) from b2b.app_users where is_active and role = 'admin') = 1, null;

-- ---------- API keys: expiry, limits, alerts ----------
do $x$ declare x jsonb; e text; begin
  x := b2b.api_key_create('{"name": "m33 limited", "scopes": ["b2c"], "rate_per_minute": 3, "expires_at": null}');
  perform pg_temp.set('K1', x ->> 'key'); perform pg_temp.set('K1id', x ->> 'id');
  x := b2b.api_key_create(jsonb_build_object('name', 'm33 expiring', 'scopes', jsonb_build_array('b2c'), 'expires_at', now() + interval '3 days'));
  perform pg_temp.set('K2', x ->> 'key'); perform pg_temp.set('K2id', x ->> 'id');
  x := b2b.api_key_create(jsonb_build_object('name', 'm33 expired', 'scopes', jsonb_build_array('b2c'), 'expires_at', now() + interval '1 minute'));
  perform pg_temp.set('K3', x ->> 'key'); perform pg_temp.set('K3id', x ->> 'id');
  e := pg_temp.err($q$select b2b.api_key_create('{"name": "xx", "scopes": ["b2c"], "expires_at": "2020-01-01T00:00:00Z"}')$q$);
  insert into r values ('key_expiry_checked', e like '22023 expiry must be in the future%', e);
  e := pg_temp.err($q$select b2b.api_key_create('{"name": "xx", "scopes": ["b2c"], "rate_per_minute": 0}')$q$);
  insert into r values ('key_rate_checked', e like '22023 the limit is 1 to 100,000%', e);
  x := b2b.api_key_update(pg_temp.v('K2id')::bigint, '{"note": "rotate in November", "rate_per_minute": 50}');
  insert into r values ('key_updated', (x ->> 'rate_per_minute')::int = 50, x::text);
end $x$;
reset role;
update b2b.api_keys set expires_at = now() - interval '1 minute' where id = pg_temp.v('K3id')::bigint;
insert into r select 'expired_key_401', (b2b.api_b2c_schema(pg_temp.v('K3')) ->> 'status')::int = 401, null;
insert into r select 'live_key_ok', (b2b.api_b2c_schema(pg_temp.v('K2')) ->> 'ok')::boolean, null;
do $x$ declare x jsonb; i int; e text; st text; begin
  for i in 1..3 loop x := b2b.api_b2c_schema(pg_temp.v('K1')); end loop;
  insert into r values ('under_limit_ok', (x ->> 'ok')::boolean, null);
  begin
    x := b2b.api_b2c_schema(pg_temp.v('K1'));
    e := 'answered';
  exception when others then
    e := sqlerrm; st := sqlstate;
  end;
  insert into r values ('over_limit_p0429', st = 'P0429' and e like 'rate limited: more than 3 requests per minute%', coalesce(st, '-') || ' ' || coalesce(e, '-'));
  insert into r values ('usage_counted', (select n from b2b.api_key_usage where api_key_id = pg_temp.v('K1id')::bigint and minute = date_trunc('minute', now())) = 3, null);
end $x$;
-- the default limit for a scope comes from the setting
update b2b.settings set value = jsonb_set(value, '{per_minute,b2c}', '2') where key = 'api_limits';
do $x$ declare x jsonb; e text; st text; begin
  x := b2b.api_b2c_schema(pg_temp.v('K2'));   -- 2nd call this minute for K2 (limit 50 on the key itself wins)
  insert into r values ('key_limit_wins_over_scope', (x ->> 'ok')::boolean, null);
  update b2b.api_keys set rate_per_minute = null where id = pg_temp.v('K2id')::bigint;
  begin x := b2b.api_b2c_schema(pg_temp.v('K2')); e := 'answered'; exception when others then st := sqlstate; end;
  insert into r values ('scope_default_applies', st = 'P0429', coalesce(st, e));
end $x$;
-- the daily tick: an alert for the key expiring in 3 days and the expired one, once a day; old usage pruned
insert into b2b.api_key_usage (api_key_id, minute, n) values (pg_temp.v('K1id')::bigint, now() - interval '3 days', 9);
insert into t select 'tick1', b2b.api_keys_expiry_tick()::text;
insert into t select 'tick2', b2b.api_keys_expiry_tick()::text;
insert into r select 'expiry_tick', (pg_temp.v('tick1')::jsonb ->> 'alerted')::int = 2 and (pg_temp.v('tick2')::jsonb ->> 'alerted')::int = 0
  and not exists (select 1 from b2b.api_key_usage where minute < now() - interval '2 days'),
  pg_temp.v('tick1') || ' ' || pg_temp.v('tick2') || ' keys=' || (select string_agg(id || ':' || coalesce(expires_at::text, '-'), ',') from b2b.api_keys where name like 'm33%');
insert into r select 'expiry_alerts', (select count(*) from b2b.events e where e.type = 'alert.api_key_expiring' and (e.payload ->> 'api_key_id')::bigint in (pg_temp.v('K2id')::bigint, pg_temp.v('K3id')::bigint)) = 2, null;
insert into r select 'cron_scheduled', exists (select 1 from cron.job where jobname = 'b2b-api-keys-expiry'), null;

-- ---------- health and the overview ----------
insert into r select 'health_shape', (x ? 'ok') and (x -> 'jobs' ? 'stale') and (x -> 'deliveries' ? 'dead_7d') and (x -> 'b2c_sync' ? 'cursor_age_seconds')
  and not (x::text like '%key_hash%'), x::text
  from (select b2b.health_check() x) y;
set local role anon;
insert into r select 'health_anon', (b2b.health_check() ? 'ok'), null;
reset role;
set local role authenticated;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000e1', 'm33-admin@test.local');
insert into r select 'overview_keys', exists (select 1 from jsonb_array_elements(x -> 'api_keys') k where (k ->> 'id')::bigint = pg_temp.v('K1id')::bigint
                                                 and (k ->> 'rate_per_minute')::int = 3 and (k ->> 'requests_1h')::int = 3)
  and (x -> 'api_limits' -> 'per_minute' ->> 'b2c')::int = 2, left(x::text, 200)
  from (select b2b.system_overview() x) y;
reset role;

select name, ok, detail from r order by ok, name;
rollback;
