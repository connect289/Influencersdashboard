-- Phase 4 page reads and writes (migrations 0010, 0011): roles, the owner-only rules, audit, Setup and Vault. The
-- PostgREST JWT is simulated with request.jwt.claims. Local test cluster only.
\set ON_ERROR_STOP 1
-- The histories are append-only in production (D-085); this local test may rewrite them, as one.retention() does.
select set_config('one.history_writer', 'on', false);
do $$ begin
  if current_database() <> 'rehearsal' or to_regclass('public.stub_health') is null then
    raise exception 'refused: this test rewrites fixtures and runs only on the local test cluster';
  end if;
end $$;
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;
-- The SQLSTATE a statement fails with, or 'ok'.
create or replace function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text) to authenticated, anon, service_role;
create or replace function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000b1"}', false)
$$;
create or replace function pg_temp.as_engineer() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000b2"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer() to authenticated;

truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in'), ('00000000-0000-0000-0000-000000000004', 'new@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000002');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000002', 'email_code');
create temp table t_settings as select key, value from one.settings;
set role postgres;
select one.open_or_touch_incident('PLAT-05', 'P1', '{"value": {"spark_base_url": false}}');
reset role;

-- 1. Reads: the shell, the overview, the incident list and page ------------------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok((select s #>> '{me,email}' = 'eng@eduwit.in' and (s #>> '{open,P1}')::int = 1 and (s ->> 'unacked_p1')::int = 1 from (select one.ui_shell() as s) x),
                  'the shell names the engineer and counts the open P1');
select pg_temp.ok((select jsonb_array_length(o -> 'apps') = 9 and o -> 'actions' -> 0 ->> 'kind' = 'incident' from (select one.ui_overview() as o) x),
                  'the overview has a tile per app and the P1 first in the action list');
select pg_temp.ok((select (r -> 'rows' -> 0 ->> 'check_id') = 'PLAT-05' from (select one.ui_incidents() as r) x), 'the incident list');
select pg_temp.ok((select i #>> '{check,id}' = 'PLAT-05' and jsonb_typeof(i -> 'timeline') = 'array' and jsonb_typeof(i -> 'deliveries') = 'array'
                     from (select one.ui_incident(1) as i) x), 'the incident page');
select pg_temp.ok(jsonb_array_length(one.ui_setup()) > 30, 'the Setup checklist');
select pg_temp.ok((select (one.ui_settings() -> 'thresholds' ->> 'version')::int >= 1), 'settings with versions');

-- 2. Incidents: acknowledge (audited with actor and request id), resolve with a note, mute --------------------------------
select pg_temp.ok((one.ui_ack(1, 'req-1') ->> 'ok')::boolean, 'the engineer acknowledges');
select pg_temp.ok(pg_temp.err('select one.ui_resolve(1, ''fixed'', '''')') = '22023', 'resolving needs a note');
select pg_temp.ok((one.ui_resolve(1, 'fixed', 'base URL set in Spark', 'req-2') ->> 'ok')::boolean, 'and resolves with one');
select pg_temp.ok((one.ui_mute('check', 'WEB-01', 60, 'deploy window', 'req-3') ->> 'ok')::boolean, 'and mutes a check');
reset role;
select pg_temp.ok((select actor = 'eng@eduwit.in' and request_id = 'req-1' from one.audit where action = 'incident.acknowledge'), 'the audit row has the actor from the JWT and the request id');
select pg_temp.ok((select resolution = 'fixed' and resolved_by = 'eng@eduwit.in' from one.incidents where id = 1), 'resolved by the engineer');

-- 3. Proposals: the owner approves what touches money or does not say what it touches -----------------------------------
set role authenticated;
select pg_temp.as_engineer();
select one.ui_proposal_create('fix', 'b2b', 'Retry stuck partner pushes', 'Ten pushes are stuck since the partner API timed out.', '{"rpc": "b2b.retry_push"}', 'medium', null, 'req-4');
select one.ui_proposal_create('cleanup', 'web', 'Drop the 19 backup tables', 'They are copies from October and nothing reads them.', '{"touches": []}', 'low', null, 'req-5');
select pg_temp.ok(pg_temp.err('select one.ui_proposal_decide(1, ''approve'', ''ok'')') = '42501', 'a fix that does not say what it touches needs the owner');
select pg_temp.ok((one.ui_proposal_decide(2, 'approve', 'agreed') ->> 'ok')::boolean, 'the engineer approves a cleanup that touches nothing sensitive');
select pg_temp.ok(pg_temp.err('select one.ui_proposal_decide(1, ''reject'', '''')') = '22023', 'rejecting needs a note');
select pg_temp.as_owner();
select pg_temp.ok((one.ui_proposal_decide(1, 'approve', 'go', '{"rpc": "b2b.retry_push", "args": {"limit": 5}, "touches": []}') ->> 'ok')::boolean,
                  'the owner approves, with edited arguments');
reset role;
select pg_temp.ok((select status = 'approved' and change -> 'args' ->> 'limit' = '5' and decided_by = 'connect@eduwit.in' from one.proposals where id = 1),
                  'the edited change is the approved one');
select pg_temp.ok((select after -> 'change' -> 'args' ->> 'limit' = '5' and before -> 'change' ->> 'rpc' = 'b2b.retry_push' from one.audit where action = 'proposal.approve' and target = 'proposal:1'),
                  'both versions are in the audit');

-- 4. Settings: versioned with a reason; recipients, fixes and access are the owner's ----------------------------------------
-- The page sends a whole value it read through one.ui_settings(); here the values are prepared as the test runner.
reset role;
select (value || '{"job_silent_min": 20}')::text as thr from one.settings where key = 'thresholds' \gset
select jsonb_set(value, '{escalation,resend_min}', '20')::text as al_timing, jsonb_set(value, '{p1,email}', '["eng@eduwit.in"]')::text as al_p1,
       jsonb_set(value, '{escalation,second_contact}', '["ops@eduwit.in"]')::text as al_second, jsonb_set(value, '{p1,email}', '"connect@eduwit.in"')::text as al_bad
  from one.settings where key = 'alerts' \gset
select value::text as fixes from one.settings where key = 'fixes' \gset
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok((one.ui_settings_put('thresholds', :'thr', 'cron jobs are slower on Sundays') ->> 'version')::int >= 2,
                  'the engineer changes a threshold');
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('thresholds', '{"job_silent_min": 25}', '')$q$) = '22023', 'a change needs a reason');
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L)', 'alerts', :'al_timing', 'slower reminders')) = '42501',
                  'but not the alerts, timing included (security review S7)');
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L)', 'alerts', :'al_p1', 'me instead')) = '42501',
                  'nor the alert recipients');
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L)', 'fixes', :'fixes', 'no change')) = '42501', 'nor fixes');
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('setup', '{}', 'wipe it')$q$) = '42501' or pg_temp.err($q$select one.ui_settings_put('setup', '{}', 'wipe it')$q$) = '22023',
                  'the Setup statuses are not edited as a setting');
select pg_temp.as_owner();
select pg_temp.ok((one.ui_settings_put('alerts', :'al_timing', 'faster reminders') ->> 'ok')::boolean, 'the owner changes the escalation timing');
select pg_temp.ok((one.ui_settings_put('alerts', :'al_second', 'second contact named') ->> 'ok')::boolean,
                  'and recipients');
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L)', 'alerts', :'al_bad', 'bad shape')) = '22023',
                  'a malformed value is refused (m1)');
reset role;
select pg_temp.ok((select count(*) >= 3 from one.settings_versions where key = 'alerts'), 'every change is a version');

-- 5. Checks: switch with a reason; a blocked check stays off ------------------------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select one.ui_check_update('WEB-05', '{"enabled": false}', 'Noisy during the catalogue migration');
select pg_temp.ok(pg_temp.err($q$select one.ui_check_update('PLAT-03', '{"enabled": true}', 'try it')$q$) = '22023', 'a blocked check cannot be switched on');
reset role;
select pg_temp.ok((select not enabled and disabled_reason ~ '^owner:noisy' and updated_by = 'eng@eduwit.in' and version >= 2 from one.checks where id = 'WEB-05'),
                  'the switch records who and why');
update one.checks set enabled = true, disabled_reason = null where id = 'WEB-05';

-- 6. Users: owner only; the Supabase user must exist; the last owner stays -----------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err('select one.ui_users()') = '42501', 'the engineer cannot list users');
select pg_temp.as_owner();
select pg_temp.ok(jsonb_array_length(one.ui_users() -> 'users') = 2, 'the owner lists users');
select pg_temp.ok(pg_temp.err($q$select one.ui_user_put('nobody@eduwit.in', 'engineer', true)$q$) = 'P0002', 'no Supabase user, no Eduwit One user (S-21)');
select pg_temp.ok(pg_temp.err($q$select one.ui_user_put('someone@gmail.com', 'engineer', true)$q$) = '22023', 'only @eduwit.in');
select pg_temp.ok((one.ui_user_put('new@eduwit.in', 'engineer', true) ->> 'ok')::boolean, 'an existing Supabase user is added');
select pg_temp.ok(pg_temp.err($q$select one.ui_user_put('connect@eduwit.in', 'engineer', true)$q$) = '22023', 'the owner cannot demote themselves');

-- 7. Setup: a validate pass, recorded by the app after its probe, switches on the checks waiting for it; secrets go to
-- Vault, never back out ------------------------------------------------------------------------------------------------------
reset role;
set role service_role;
select pg_temp.ok((one.setup_validated('n8n_api', true, 'listed 18 workflows', 'connect@eduwit.in') ->> 'checks_on')::int >= 1, 'validating n8n_api switches its checks on');
reset role;
select pg_temp.ok((select enabled from one.checks where id = 'WITTY-02'), 'WITTY-02 is on');
select pg_temp.ok((select (value #>> '{items,n8n_api,validated}')::boolean and value #>> '{items,n8n_api,ran}' ~ 'connect@eduwit.in' from one.settings where key = 'setup'),
                  'the item records who validated it');
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok((one.ui_secret_put('one_n8n_key', 'n8n_api_test_value_123') ->> 'ok')::boolean, 'the owner saves a secret to Vault');
select pg_temp.ok(pg_temp.err($q$select one.ui_secret_put('b2c_internal_key', 'abcdefghijk')$q$) = '22023', 'only one_* names the checklist lists');
select pg_temp.ok(pg_temp.err($q$select one.ui_secret_put('one_internal_key', 'abcdefghijk')$q$) = '22023', 'never the internal key');
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_secret_put('one_n8n_key', 'abcdefghijk')$q$) = '42501', 'the engineer cannot set secrets');
select pg_temp.ok((select bool_and(s -> 'secrets' -> 0 ->> 'present' = 'true') from jsonb_array_elements(one.ui_setup()) s where s ->> 'id' = 'n8n_api'),
                  'the page shows the secret as present, by name');
reset role;
select pg_temp.ok((select count(*) = 1 from vault.secrets where name = 'one_n8n_key' and secret = 'n8n_api_test_value_123'), 'the value is in Vault');
select pg_temp.ok(not exists (select 1 from one.audit where after::text ~ 'n8n_api_test_value'), 'and never in the audit');
set role service_role;
select pg_temp.ok((one.app_secrets() ->> 'one_n8n_key') = 'n8n_api_test_value_123', 'the app reads it without a deploy');
reset role;

-- 8. Ask: a question is queued for the AI worker; only an answer can be pinned ------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok((one.ui_ask('How many leads came from Witty yesterday?') ->> 'ok')::boolean, 'a question is queued');
select pg_temp.ok(pg_temp.err('select one.ui_ask_pin((select max(id) from one.ai_tasks))') in ('22023', '42501'), 'an unanswered question cannot be pinned');
select pg_temp.ok((one.ui_asks() -> 0 ->> 'question') ~ 'Witty', 'the Ask page lists it');

-- 9. Without a checked session, or as anon, nothing ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000ff"}', false);
select pg_temp.ok(pg_temp.err('select one.ui_shell()') = '42501', 'an unchecked session reads nothing');
reset role;
set role anon;
select pg_temp.ok(pg_temp.err('select one.ui_shell()') = '42501', 'anon reads nothing');
reset role;
select set_config('request.jwt.claims', '', false);

-- 10. Every function the signed-in role can execute passes the gate first (or is one of the sign-in functions) --------------
select pg_temp.ok(not exists (
  select 1 from pg_proc p where p.pronamespace = 'one'::regnamespace and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and p.prosrc !~ 'one\.ui_require\(' and p.proname not in ('me', 'auth_verify_code', 'auth_device_check', 'auth_sign_out')),
  'every UI function starts with the gate');

-- Clean up ---------------------------------------------------------------------------------------------------------------
update one.settings s set value = t.value from t_settings t where s.key = t.key;
update one.checks set enabled = false, disabled_reason = 'setup:n8n_api' where id in ('WITTY-02', 'WITTY-08', 'HB-n8n:PKPs7tXg9bej8AgX', 'HB-n8n:instance');
delete from vault.secrets where name = 'one_n8n_key';
truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
