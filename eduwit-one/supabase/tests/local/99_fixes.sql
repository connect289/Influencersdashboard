-- The auto-fixes (migration 0019, spec §8): the fixer's rights, the settings rules (enable on evidence), a dry run of
-- every fix from a staged incident with nothing changed, the cooldown, real runs through the fixer's functions with an
-- action row before and after, test rows left out, the rate limit opening a proposal, the app's side of its two fixes,
-- verification and escalation, approvals under the owner's session, the Fixes page and the brief. Local cluster only.
\set ON_ERROR_STOP 1
-- This test rewrites histories that are append-only in production (D-085): it says so, as one.retention() does.
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
create or replace function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text) to authenticated, service_role, eduwit_one_fixer;
create or replace function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000f1"}', false)
$$;
create or replace function pg_temp.as_engineer() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000f2"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer() to authenticated;
-- Lets the next tick run every fix again (the cooldown counts the tick's own runs). The app fixes' runs keep their
-- time, so the app can still claim them; verification times are set where a test needs them.
create or replace function pg_temp.cool() returns void language sql as $$
  update one.actions set ran_at = ran_at - interval '1 day' where not (step = 'before' and fix_id in ('FIX-N8N-RETRY', 'FIX-WEBHOOK-REKICK'))
$$;

truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'owner@eduwit.in'), ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000002');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'owner@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000002', 'email_code');
create temp table t_fixes as select value from one.settings where key = 'fixes';
-- Verification reads the checks' own results: earlier tests' runs of these checks would judge this test's fixes.
delete from one.results where check_id in ('WITTY-01', 'WITTY-02', 'B2B-01', 'B2B-06', 'B2C-02', 'B2C-03', 'WEB-01', 'CAT-01', 'CAT-02');

-- The app tables the fixes read and touch, with production's columns (measured 24 Oct), owned by postgres.
set role postgres;
create table public.stub_calls (id bigserial primary key, fn text, arg jsonb, at timestamptz default now());
create table public.w2_gemini_caches (name text primary key, cache_name text, model text, prompt_hash text, prompt_text text, tokens int,
  expire_at timestamptz, error text, updated_at timestamptz default now());
create table public.web_outbox (id bigserial primary key, kind text, dedupe_key text, payload jsonb default '{}', status text, attempts int default 0,
  max_attempts int default 5, next_attempt_at timestamptz default now(), locked_until timestamptz, last_error text, request_id text,
  created_at timestamptz default now(), processed_at timestamptz);
create table b2b.integration_outbox (id bigserial primary key, event_type text, target text, payload jsonb default '{}', idempotency_key text, status text,
  attempts int default 0, next_attempt_at timestamptz default now(), last_error text, created_at timestamptz default now(), delivered_at timestamptz,
  endpoint_id bigint, source_event_id bigint, net_request_id bigint, response_status int);
alter table b2b.integration_outbox enable row level security;
create table b2b.app_users (user_id uuid primary key, role text, is_active boolean default true);
create table b2c.inbox (envelope_id text primary key, type text, lead_id bigint, occurred_at timestamptz, payload jsonb default '{}', via text, status text,
  error text, attempts int default 0, received_at timestamptz default now(), applied_at timestamptz);
create table b2c.outbox (id bigserial primary key, kind text, lead_id bigint, request_id text, body jsonb default '{}', urgent boolean default false,
  occurred_at timestamptz default now(), status text, attempts int default 0, next_attempt_at timestamptz default now(), created_at timestamptz default now());
delete from public.w2_outbox where status = 'failed';
insert into public.w2_outbox (phone, target, status, attempts, last_error) values
  ('919876500001', 'crm', 'failed', 5, 'statement timeout'),
  ('910000123456', 'crm', 'failed', 5, 'statement timeout'),
  ('919876500002', 'crm', 'failed', 2, 'INVALID_DATA: mobile'),
  ('919876500003', 'crm', 'sent', 1, null);
insert into public.w2_gemini_caches (name, expire_at) values ('counselor', now() - interval '1 hour'), ('extractor', now() + interval '1 hour');
insert into public.web_outbox (kind, status, attempts, max_attempts, payload) values
  ('lead', 'dead', 2, 5, '{}'), ('lead', 'dead', 5, 5, '{}'), ('lead', 'dead', 1, 5, '{"is_test": true}'), ('lead', 'done', 1, 5, '{}');
insert into b2b.integration_outbox (event_type, status, endpoint_id, payload, created_at) values
  ('b2c.lead_handed_off', 'dead', 1, '{"data": {"lead_id": 1}}', now() - interval '1 day'),
  ('b2c.lead_handed_off', 'failed', 1, '{"data": {"lead_id": 2}}', now() - interval '2 hours'),
  ('b2c.lead_handed_off', 'dead', 1, '{"data": {"lead_id": 3, "test": true}}', now() - interval '1 day'),
  ('b2c.lead_handed_off', 'dead', 1, '{"data": {"lead_id": 4}}', now() - interval '10 days'),
  ('b2c.lead_handed_off', 'delivered', 1, '{"data": {"lead_id": 5}}', now() - interval '1 day');
reset role;
select id as w2_retryable from public.w2_outbox where phone = '919876500001' and status = 'failed' \gset

-- The staged incidents: one per trigger, with the evidence each check reports (as one.evaluate records it).
select one.open_or_touch_incident('WITTY-01', 'P1', '{"status": "fail", "value": {"alerts": [{"alert": "outbox_failed"}, {"alert": "cache_expired"}]}}', '{outbox_failed,cache_expired}');
select one.open_or_touch_incident('WITTY-02', 'P1', '{"status": "fail", "value": {"active": true, "failed_15m": ["9001", "9002"]}}');
select one.open_or_touch_incident('B2B-01', 'P1', '{"status": "fail", "value": {"ok": false, "deliveries": {"dead_7d": 2, "waiting_over_1h": 1}, "b2c_sync": {"cursor_age_seconds": 900}}}');
select one.open_or_touch_incident('B2B-06', 'P1', '{"status": "fail", "value": {"endpoints": [{"id": 1}]}}');
select one.open_or_touch_incident('B2C-02', 'P1', '{"status": "fail", "value": {"error": 2, "stuck": 1}}');
select one.open_or_touch_incident('B2C-03', 'P2', '{"status": "fail", "value": {"count": 3, "by_status": {"failed": 3}}}');
select one.open_or_touch_incident('WEB-01', 'P1', '{"status": "fail", "value": {"db": true, "outbox_dead": 3, "catalog_checked_seconds_ago": 900, "outbox_oldest_pending_seconds": 0}}');
select one.open_or_touch_incident('CAT-01', 'P2', '{"status": "fail", "value": {"cache_at": "2026-10-01T00:00:00Z", "catalogue_at": "2026-10-24T00:00:00Z"}}');
select one.open_or_touch_incident('CAT-02', 'P2', '{"status": "fail", "value": {"changed_at": "2026-10-24T00:00:00Z", "refreshed_at": null}}');
reset role;
select id as i_witty1 from one.incidents where check_id = 'WITTY-01' \gset
select id as i_witty2 from one.incidents where check_id = 'WITTY-02' \gset
select id as i_b2b1 from one.incidents where check_id = 'B2B-01' \gset
select id as i_b2b6 from one.incidents where check_id = 'B2B-06' \gset
select id as i_b2c2 from one.incidents where check_id = 'B2C-02' \gset
select id as i_web1 from one.incidents where check_id = 'WEB-01' \gset
select id as i_cat1 from one.incidents where check_id = 'CAT-01' \gset

-- 1. The fixer's rights (spec §8, D-079) -----------------------------------------------------------------------------
select pg_temp.ok((select count(*) = 11 from one.fixes), 'the catalogue has the eleven fixes of spec §8');
select pg_temp.ok((select array_agg(p.proname order by p.proname) from pg_proc p where p.proowner = 'eduwit_one_fixer'::regrole)
                  = array['fixer_b2b_outbox_retry', 'fixer_b2c_outbox', 'fixer_b2c_sync', 'fixer_catalog_poll', 'fixer_inbox_retry',
                          'fixer_outbox_kick', 'fixer_programme_cache', 'fixer_web_outbox']::name[], 'the fixer owns exactly its eight functions');
select pg_temp.ok(not exists (select 1 from pg_proc p, unnest(array['public', 'anon', 'authenticated', 'service_role', 'eduwit_one_reader']) r
                               where p.proowner = 'eduwit_one_fixer'::regrole
                                 and (r = 'public' and p.proacl is null or r <> 'public' and has_function_privilege(r, p.oid, 'EXECUTE'))),
                  'no API role, the reader or PUBLIC can call the fixer''s functions');
select pg_temp.ok((select count(*) = 10 and bool_and(coalesce(has_function_privilege('eduwit_one_fixer', to_regprocedure(fn), 'EXECUTE'), false))
                     from one.fixes f, unnest(f.app_functions) fn), 'the fixer can execute each of the 10 catalogue functions');
select pg_temp.ok(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                               where n.nspname in ('public', 'b2b', 'b2c', 'one') and c.relkind in ('r', 'v', 'm', 'p')
                                 and (has_table_privilege('eduwit_one_fixer', c.oid, 'SELECT') or has_table_privilege('eduwit_one_fixer', c.oid, 'INSERT')
                                      or has_table_privilege('eduwit_one_fixer', c.oid, 'UPDATE') or has_table_privilege('eduwit_one_fixer', c.oid, 'DELETE'))),
                  'the fixer holds no table privilege anywhere');
select pg_temp.ok(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                               where n.nspname in ('public', 'b2b', 'b2c', 'one') and c.relkind in ('r', 'v', 'm', 'p')
                                 and (has_any_column_privilege('eduwit_one_fixer', c.oid, 'SELECT') or has_any_column_privilege('eduwit_one_fixer', c.oid, 'INSERT')
                                      or has_any_column_privilege('eduwit_one_fixer', c.oid, 'UPDATE') or has_any_column_privilege('eduwit_one_fixer', c.oid, 'REFERENCES'))),
                  'nor any column privilege (phase 7 review B1)');
select pg_temp.ok((select array_agg(distinct m.member::regrole::text) from pg_auth_members m where m.roleid = 'eduwit_one_fixer'::regrole) = array['postgres'],
                  'only the migrating user is a member of the fixer: that is how Eduwit One''s functions call the fixer''s (review m11)');
select pg_temp.ok(not has_schema_privilege('eduwit_one_fixer', 'one', 'CREATE'), 'the fixer kept no CREATE on schema one');
select pg_temp.ok((select not (rolbypassrls or rolsuper or rolcanlogin) from pg_roles where rolname = 'eduwit_one_fixer'), 'the fixer bypasses nothing and cannot log in');
select pg_temp.ok(not exists (select 1 from pg_auth_members where member = 'eduwit_one_fixer'::regrole), 'the fixer is a member of no role');
set role eduwit_one_fixer;
select pg_temp.ok(pg_temp.err('select count(*) from public.student_leads') = '42501', 'the fixer cannot read student_leads');
select pg_temp.ok(pg_temp.err('select count(*) from b2b.allocations') = '42501', 'nor allocations');
select pg_temp.ok(pg_temp.err($q$update b2b.integration_outbox set status = 'pending'$q$) = '42501', 'nor change an app''s rows itself');
select pg_temp.ok(pg_temp.err('select one.fix_run(''FIX-CACHE-B2C'', 1)') = '42501', 'nor run Eduwit One''s fix engine');
reset role;

-- 2. The settings: enable on evidence ------------------------------------------------------------------------------------
select pg_temp.ok(pg_temp.err($q$select one.settings_check('fixes', '{"FIX-NOPE ": {"enabled": false, "per_tick": 1, "cooldown_min": 5}}')$q$) = '22023', 'a fix id is FIX-…');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('fixes', '{"FIX-CACHE-B2C": {"enabled": false, "per_tick": 0, "cooldown_min": 5}}')$q$) = '22023', 'per_tick is 1 to 500');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('fixes', '{"FIX-CACHE-B2C": {"enabled": false, "per_tick": 1, "cooldown_min": 1.5}}')$q$) = '22023', 'cooldown_min is whole minutes');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('fixes', '{"FIX-CACHE-B2C": {"enabled": "yes", "per_tick": 1, "cooldown_min": 5}}')$q$) = '22023', 'enabled is a boolean');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('fixes', '{"FIX-CACHE-B2C": {"enabled": false, "per_tick": 1, "cooldown_min": 5, "sql": "x"}}')$q$) = '22023', 'no other key');
select pg_temp.ok(pg_temp.err(format($q$select one.settings_check('fixes', %L)$q$, jsonb_build_object('observation_started_at', now() - interval '30 days',
                    'FIX-CACHE-B2C', jsonb_build_object('enabled', true, 'per_tick', 1, 'cooldown_min', 15)))) = '22023', 'no switch-on without a dry run');
select pg_temp.ok(pg_temp.err(format($q$select one.settings_check('fixes', %L)$q$, jsonb_build_object('observation_started_at', now() - interval '3 days',
                    'FIX-CACHE-B2C', jsonb_build_object('enabled', true, 'per_tick', 1, 'cooldown_min', 15)))) = '22023', 'no switch-on during the window');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('fixes', '{"observation_days": 1}')$q$) = '22023', 'the window is two weeks at least (review m8)');
select pg_temp.ok((one.fix_window() ->> 'running')::boolean, 'a window not yet started counts as running');

-- 3. A dry run of every fix from its staged incident; nothing changes (acceptance: every fix has a dry-run row) ------------
select one.fixes_step() as step1 \gset
select pg_temp.ok((one.setting('fixes') ->> 'observation_started_at') is not null, 'the first fix step starts the observation window');
select pg_temp.ok((select count(distinct fix_id) = 11 from one.actions where step = 'dry_run' and dry_run and status = 'planned' and ran_by = 'one'),
                  'every fix recorded a dry run on its staged incident: ' || (select string_agg(id, ',') from one.fixes f where not exists (select 1 from one.actions a where a.fix_id = f.id))
                  || ' ' || :'step1');
select pg_temp.ok((select count(*) = 0 from public.stub_calls), 'a dry run calls no app function');
select pg_temp.ok((select count(*) = 0 from one.proposals), 'a dry run opens no proposal');
select pg_temp.ok((select count(*) = 0 from one.actions where not dry_run), 'every row of the window is a dry run');
select pg_temp.ok((select count(*) = 2 from one.actions where fix_id = 'FIX-CATALOG-POLL'), 'a fix tried on two checks records a dry run on each incident (review M11)');
select pg_temp.ok(pg_temp.err(format($q$select one.settings_check('fixes', %L)$q$, (select value from one.settings where key = 'fixes') || '{"observation_started_at": "2026-01-01T00:00:00Z"}')) = '22023',
                  'once started, the window cannot be moved (review m8)');
select pg_temp.ok((select result ->> 'why_dry' = 'switched off' from one.actions where fix_id = 'FIX-CACHE-B2C'), 'the row says why it was dry');
select pg_temp.ok((select target -> 'rows' = jsonb_build_array(:w2_retryable) and (target ->> 'test_rows_left_out')::int = 1 from one.actions where fix_id = 'FIX-OUTBOX-W2'),
                  'FIX-OUTBOX-W2 would take the retryable row only: the test phone and the permanent error are left out');
select pg_temp.ok((select target -> 'rows' = '[1, 2]' and (target ->> 'test_rows_left_out')::int = 1 from one.actions where fix_id = 'FIX-OUTBOX-B2B'),
                  'FIX-OUTBOX-B2B would take the dead and failed deliveries of the last 7 days, not the test one');
select pg_temp.ok((select target -> 'rows' = '[1]' and (target ->> 'test_rows_left_out')::int = 1 from one.actions where fix_id = 'FIX-OUTBOX-WEB'),
                  'FIX-OUTBOX-WEB would take the dead row with attempts left, not the exhausted or the test one');
select pg_temp.ok((select target -> 'rows' = '["9001", "9002"]' from one.actions where fix_id = 'FIX-N8N-RETRY'), 'FIX-N8N-RETRY would retry the two failed executions');
select pg_temp.ok((select target -> 'caches' = '["counselor"]' from one.actions where fix_id = 'FIX-CACHE-W2'), 'FIX-CACHE-W2 names the expired cache');
select pg_temp.ok((select target ->> 'url' = 'https://spark.eduwit.in/v1/handoffs' from one.actions where fix_id = 'FIX-WEBHOOK-REKICK'), 'the Spark URL comes from hosts');
select pg_temp.ok(not exists (select 1 from one.actions where target::text ~ '9198765' or result::text ~ '9198765'), 'no phone in any action row');
select one.fixes_step() as step2 \gset
select pg_temp.ok((select count(*) = 12 from one.actions), 'the cooldown holds each fix to one dry run per incident');
select pg_temp.ok((one.fix_run('FIX-CACHE-B2C', :i_cat1, true, 'eng@eduwit.in') ->> 'dry_run')::boolean, 'a person''s dry run runs');
select pg_temp.ok((select count(*) = 13 from one.actions), 'a person''s dry run is not held by the cooldown');
select pg_temp.ok((one.fix_cache_b2c(:i_cat1, false) ->> 'dry_run')::boolean, 'one.fix_<id>() by hand acts only when switched on');
select pg_temp.ok(one.fix_run('FIX-CACHE-B2C', :i_web1, true, 'sql:test') ->> 'why_not' = 'not one of this fix''s checks', 'a fix is tried only on its own checks');
update one.incidents set evidence = '{"status": "source_missing", "value": null}' where id = :i_cat1;
select pg_temp.ok(one.fix_run('FIX-CACHE-B2C', :i_cat1, true, 'sql:test') ->> 'why_not' ~ 'could not run', 'nor on an incident whose check could not run');
update one.incidents set evidence = '{"status": "fail", "value": {}}' where id = :i_cat1;

-- 4. Switched on after the window: real runs, each through the fixer, with a row before and after ------------------------
update one.settings set value = value || jsonb_build_object('observation_started_at', now() - interval '30 days') where key = 'fixes';
select one.settings_put('fixes', (select value from one.settings where key = 'fixes')
         || (select jsonb_object_agg(id, (select value from one.settings where key = 'fixes') -> id || '{"enabled": true}') from one.fixes),
       'test', 'switch every fix on after the window') as v \gset
select pg_temp.ok((select bool_and((value -> id ->> 'enabled')::boolean) from one.settings, one.fixes where key = 'fixes'), 'every fix switched on, on evidence');
select pg_temp.cool();
select one.fixes_step() as step3 \gset
select pg_temp.ok((select count(*) = 1 from public.stub_calls where fn = 'b2b.b2c_sync_tick' and arg = '200'), 'FIX-CURSOR-B2C ran b2b.b2c_sync_tick(200)');
select pg_temp.ok((select count(*) = 1 from public.stub_calls where fn = 'b2c.inbox_retry' and arg = '50'), 'FIX-INBOX-RETRY ran b2c.inbox_retry(50)');
select pg_temp.ok((select array_agg(fn order by id) from public.stub_calls where fn in ('b2c.outbox_unstick', 'b2c.job_call'))
                  = array['b2c.outbox_unstick', 'b2c.job_call'] and exists (select 1 from public.stub_calls where fn = 'b2c.job_call' and arg = '"/api/internal/sync?mode=urgent"'),
                  'FIX-OUTBOX-B2C unstuck the outbox, then ran the urgent sync');
select pg_temp.ok((select count(*) = 1 from public.stub_calls where fn = 'public.web_outbox_retry' and arg = '1')
                  and exists (select 1 from public.stub_calls where fn = 'public.web_job_call' and arg = '"/api/internal/outbox"')
                  and (select status from public.web_outbox where id = 1) = 'pending' and (select status from public.web_outbox where id = 3) = 'dead',
                  'FIX-OUTBOX-WEB sent the one qualifying row again (the test row stays) and ran the worker');
select pg_temp.ok((select count(*) = 1 from public.stub_calls where fn = 'public.web_catalog_poll'), 'FIX-CATALOG-POLL ran once for its two incidents (a real run once per fix per cooldown)');
select pg_temp.ok((select count(*) = 1 from public.stub_calls where fn = 'b2c.programme_cache_refresh' and arg = 'true'), 'FIX-CACHE-B2C refreshed with force');
select pg_temp.ok((select count(*) = 0 from public.stub_calls where fn in ('b2b.outbox_kick', 'b2b.outbox_retry')), 'neither the app fixes nor the approvals ran in the tick');
select pg_temp.ok((select bool_and(b.n = 2 and b.statuses = array['planned', 'done'])
                     from (select run_key, count(*) as n, array_agg(status order by id) as statuses from one.actions
                            where not dry_run and fix_id in ('FIX-CURSOR-B2C', 'FIX-INBOX-RETRY', 'FIX-OUTBOX-B2C', 'FIX-OUTBOX-WEB', 'FIX-CATALOG-POLL', 'FIX-CACHE-B2C')
                            group by run_key) b), 'each real act has a row before and a row after, the same run');
select pg_temp.ok((select count(*) = 6 from one.actions where step = 'after' and status = 'done' and verify_at between now() + interval '1 minute' and now() + interval '3 minutes'),
                  'each act is verified 2 minutes on');
select pg_temp.ok((select count(*) = 3 from one.proposals where source = 'check' and kind = 'fix'), 'the proposing fixes opened one proposal each');
select pg_temp.ok((select change ? 'execute' from one.proposals where app = 'b2b') and not (select bool_or(change ? 'execute') from one.proposals where app = 'witty'),
                  'only FIX-OUTBOX-B2B''s proposal runs on approval; Witty''s describe a change');
select pg_temp.ok((select count(*) = 2 from one.actions where step = 'before' and fix_id in ('FIX-N8N-RETRY', 'FIX-WEBHOOK-REKICK') and not dry_run), 'the app''s two fixes wait for the app');
select pg_temp.ok((select count(*) = 1 from public.stub_calls where fn = 'lock_timeout' and arg = '"2s"'), 'a fix acts under the checks'' lock timeout (review M8)');
select pg_temp.ok(one.fix_inbox_retry(:i_b2c2, false) ->> 'skipped' = 'waiting for the verdict on its last run',
                  'a run by hand on the incident just acted on waits for the verdict (D-084)');
-- FIX-CATALOG-POLL acted on one of its two incidents; a run by hand on the other, within the cooldown, is held by it.
select i.id as i_cat_other from one.incidents i where i.check_id in ('WEB-01', 'CAT-02') and i.resolved_at is null
   and not exists (select 1 from one.actions a where a.fix_id = 'FIX-CATALOG-POLL' and a.incident_id = i.id and not a.dry_run and a.step = 'after') \gset
select pg_temp.ok(one.fix_catalog_poll(:i_cat_other, false) ->> 'skipped' = 'cooldown', 'a run by hand is held by the cooldown too (review M11)');
select pg_temp.cool();
select one.fix_run('FIX-OUTBOX-B2B', :i_b2b1, false, 'one') as again_b2b \gset
select one.fix_run('FIX-OUTBOX-W2', :i_witty1, false, 'one') as again_w2 \gset
select pg_temp.ok((select count(*) = 3 from one.proposals where source = 'check'), 'a waiting proposal is refreshed, not duplicated');

-- 5. The app's side --------------------------------------------------------------------------------------------------
select max(id) as a_cache from one.actions where fix_id = 'FIX-CACHE-B2C' \gset
set role service_role;
select one.app_fixes_claim('test-app') as claim \gset
select pg_temp.ok(jsonb_array_length(:'claim'::jsonb -> 'runs') = 2, 'the app claims the runs waiting for it');
select pg_temp.ok(jsonb_array_length(one.app_fixes_claim('another') -> 'runs') = 0, 'a claimed run is held');
select (r ->> 'action_id')::bigint as a_rekick from jsonb_array_elements(:'claim'::jsonb -> 'runs') r where r ->> 'fix_id' = 'FIX-WEBHOOK-REKICK' limit 1 \gset
select (r ->> 'action_id')::bigint as a_n8n from jsonb_array_elements(:'claim'::jsonb -> 'runs') r where r ->> 'fix_id' = 'FIX-N8N-RETRY' limit 1 \gset
select pg_temp.ok(one.app_fix_report(:a_rekick, false, '{"status": null, "error": "timeout"}') ->> 'status' = 'skipped', 'Spark did not answer: nothing done');
select pg_temp.ok(pg_temp.err(format('select one.app_fix_report(%s, true, ''{}'')', :a_rekick)) = '22023', 'a run is reported once');
-- The fix is not proven yet, so the run the app was handed holds one execution (D-084): the app reports that one.
reset role;
select pg_temp.ok((select target -> 'rows' = '["9001"]' and (target ->> 'trial')::boolean from one.actions where id = :a_n8n), 'an unproven fix handed the app one execution, as a trial');
set role service_role;
select pg_temp.ok(one.app_fix_report(:a_n8n, true, '{"retried": ["9001"], "phone": "+91 98765 43210"}') ->> 'status' = 'done', 'the n8n retry is recorded');
select pg_temp.ok(pg_temp.err(format('select one.app_fix_report(%s, true, ''{}'')', :a_cache)) = '22023', 'the app reports only on its own fixes');
select pg_temp.ok(pg_temp.err('select count(*) from one.actions') = '42501', 'and cannot read the actions table');
reset role;
select pg_temp.ok((select count(*) = 0 from public.stub_calls where fn = 'b2b.outbox_kick'), 'no kick while Spark does not answer');
select pg_temp.ok((select result::text !~ '98765' from one.actions where fix_id = 'FIX-N8N-RETRY' and step = 'after'), 'the app''s report is redacted');
select pg_temp.ok(one.fix_plan('FIX-N8N-RETRY', (select i from one.incidents i where id = :i_witty2)) -> 'rows' = '["9002"]', 'an execution is retried once, never twice; the one not yet tried stays due');
select pg_temp.ok(one.fix_run('FIX-N8N-RETRY', :i_witty2, false, 'one') ->> 'skipped' = 'waiting for the verdict on its last run', 'and nothing runs on the incident before the trial''s verdict');
update one.incidents set evidence = '{"status": "fail", "value": {"failed_15m": ["9001", "9002", "9003", "9004"], "retries_15m": ["9004"]}}' where id = :i_witty2;
select pg_temp.ok(one.fix_plan('FIX-N8N-RETRY', (select i from one.incidents i where id = :i_witty2)) -> 'rows' = '["9002", "9003"]', 'nor a retry of a retry (review M10)');
update one.actions set ran_at = ran_at - interval '1 day' where fix_id = 'FIX-WEBHOOK-REKICK';
select one.fix_run('FIX-WEBHOOK-REKICK', :i_b2b6, false, 'sql:test') as rekick \gset
set role service_role;
select (one.app_fixes_claim('test-app') -> 'runs' -> 0 ->> 'action_id')::bigint as a_rekick2 \gset
select pg_temp.ok(one.app_fix_report(:a_rekick2, true, '{"status": 405}') ->> 'status' = 'done', 'Spark answered: the kick ran');
reset role;
select pg_temp.ok((select count(*) = 1 from public.stub_calls where fn = 'b2b.outbox_kick'), 'b2b.outbox_kick() ran once, through the fixer');
insert into one.actions (fix_id, incident_id, app, dry_run, status, ran_by, step, run_key, ran_at)
values ('FIX-N8N-RETRY', :i_witty2, 'witty', false, 'planned', 'one', 'before', 'stale-run', now() - interval '20 minutes');
set role service_role;
select one.app_fixes_claim('test-app') as claim2 \gset
reset role;
select pg_temp.ok((select status = 'failed' and result ->> 'error' ~ 'did not run it' from one.actions where run_key = 'stale-run' and step = 'after'),
                  'a run the app never ran is closed as failed');
-- A claimed run is handed out once: unreported, it is closed as unknown, never claimed again (review M9).
-- First the verdict on the run just reported, as the verifier records it (no B2B-06 run since: unverified); until it is
-- recorded, no run of the fix on this incident (D-084).
select pg_temp.ok(one.fix_run('FIX-WEBHOOK-REKICK', :i_b2b6, false, 'sql:test') ->> 'skipped' = 'waiting for the verdict on its last run', 'no second run before the verdict (D-084)');
-- (The verifier waits the cooldown plus two cadences for a run of the check before it gives up: the run is aged past that.)
update one.actions set verify_at = now() - interval '1 minute', ran_at = now() - interval '2 hours'
 where fix_id = 'FIX-WEBHOOK-REKICK' and step = 'after' and status = 'done' and verify_at > now();
select one.fix_verify_due() as rekick_verdict \gset
select pg_temp.ok((:'rekick_verdict'::jsonb ->> 'verified')::int = 1
                  and (select status = 'skipped' and result ->> 'held' is null from one.actions where fix_id = 'FIX-WEBHOOK-REKICK' and step = 'verify'),
                  'with no run of B2B-06 since, the verdict is "unverified"');
update one.actions set ran_at = ran_at - interval '1 day' where fix_id = 'FIX-WEBHOOK-REKICK';
select one.fix_run('FIX-WEBHOOK-REKICK', :i_b2b6, false, 'sql:test') as rekick3 \gset
set role service_role;
select (one.app_fixes_claim('test-app') -> 'runs' -> 0 ->> 'action_id')::bigint as a_rekick3 \gset
reset role;
update one.actions set claimed_at = now() - interval '6 minutes' where id = :a_rekick3;
set role service_role;
select pg_temp.ok(jsonb_array_length(one.app_fixes_claim('test-app') -> 'runs') = 0, 'a claimed run is never handed out again');
reset role;
update one.actions set ran_at = now() - interval '16 minutes' where id = :a_rekick3;
set role service_role;
select one.app_fixes_claim('test-app') as claim3 \gset
reset role;
select pg_temp.ok((select (result ->> 'unknown')::boolean from one.actions where run_key = (select run_key from one.actions where id = :a_rekick3) and step = 'after'),
                  'and closed as unknown after 15 minutes');
-- A tick's run of a fix switched off before the app ran it is closed as skipped (review m5).
update one.actions set ran_at = ran_at - interval '1 day' where fix_id = 'FIX-WEBHOOK-REKICK';
select one.fix_run('FIX-WEBHOOK-REKICK', :i_b2b6, false, 'one') as rekick4 \gset
update one.settings set value = jsonb_set(value, '{FIX-WEBHOOK-REKICK,enabled}', 'false') where key = 'fixes';
set role service_role;
select pg_temp.ok(jsonb_array_length(one.app_fixes_claim('test-app') -> 'runs') = 0, 'a run of a fix switched off is not handed out');
reset role;
select pg_temp.ok((select result ->> 'reason' ~ 'switched off' from one.actions where run_key = (select run_key from one.actions where id = (:'rekick4'::jsonb ->> 'queued_for_app')::bigint) and step = 'skip'),
                  'but closed as skipped');
update one.settings set value = jsonb_set(value, '{FIX-WEBHOOK-REKICK,enabled}', 'true') where key = 'fixes';

-- 6. Verification: held, or a second failure that escalates instead of a retry -------------------------------------------
update one.actions set verify_at = now() - interval '1 minute' where step = 'after' and fix_id in ('FIX-CURSOR-B2C', 'FIX-CACHE-B2C', 'FIX-INBOX-RETRY') and verify_at is not null;
update one.actions set ran_at = now() - interval '3 minutes' where step = 'after' and fix_id in ('FIX-CURSOR-B2C', 'FIX-CACHE-B2C') and verify_at is not null;
update one.actions set ran_at = now() - interval '10 minutes' where step = 'after' and fix_id = 'FIX-INBOX-RETRY' and verify_at is not null;
select alert_seq as b2b_seq from one.incidents where id = :i_b2b1 \gset
insert into one.results (check_id, ran_at, status, value) values
  ('B2B-01', now(), 'fail', '{"b2c_sync": {"cursor_age_seconds": 900}, "deliveries": {"dead_7d": 0}}'), ('CAT-01', now(), 'fail', '{}'), ('B2C-02', now(), 'ok', '{}');
select one.fix_verify_due() as verified \gset
select pg_temp.ok((select status = 'failed' and (result ->> 'escalated')::boolean from one.actions where fix_id = 'FIX-CACHE-B2C' and step = 'verify'),
                  'FIX-CACHE-B2C did not hold: verified as failed');
select pg_temp.ok((select severity = 'P1' and 'fix_failed' = any (tags) from one.incidents where id = :i_cat1), 'its P2 incident went up one level to P1');
select pg_temp.ok((select alert_seq > :b2b_seq and severity = 'P1' from one.incidents where id = :i_b2b1), 'a P1 whose fix did not hold is routed again');
select pg_temp.ok((select status = 'done' and (result ->> 'held')::boolean and result ? 'judged_by' from one.actions where fix_id = 'FIX-INBOX-RETRY' and step = 'verify'),
                  'its check passed afterwards: it held, judged by that run (review M5)');
select pg_temp.cool();
select pg_temp.ok(one.fix_run('FIX-CURSOR-B2C', :i_b2b1, false, 'one') ->> 'skipped' ~ '^stopped', 'FIX-CURSOR-B2C stops on an incident it did not fix');
select pg_temp.ok((select count(*) from one.actions where step = 'verify') = 4, 'each run due is verified once (the rekick''s verdict above included)');
select one.fix_verify_due() as verified_again \gset
select pg_temp.ok((select count(*) from one.actions where step = 'verify') = 4, 'and never twice');
-- No run of the check to judge by: unverified, not held (review M5).
insert into one.actions (fix_id, incident_id, app, dry_run, status, ran_by, step, run_key, ran_at, verify_at)
values ('FIX-OUTBOX-B2C', (select id from one.incidents where check_id = 'B2C-03'), 'b2c', false, 'done', 'one', 'after', 'quiet-run', now() - interval '2 hours', now() - interval '2 hours');
-- A run that cannot be judged gets a row saying why and holds nobody up (review M7).
insert into one.actions (fix_id, incident_id, app, dry_run, status, ran_by, step, run_key, ran_at, verify_at)
values ('FIX-CURSOR-B2C', :i_b2b1, 'b2b', false, 'done', 'one', 'after', 'bad-run', now() - interval '1 minute', now() - interval '30 seconds');
insert into one.results (check_id, ran_at, status, value) values ('B2B-01', now() - interval '10 seconds', 'fail', '{"b2c_sync": {"cursor_age_seconds": "n/a"}}');
select one.fix_verify_due() as verified_odd \gset
select pg_temp.ok((select status = 'skipped' and result -> 'held' = 'null'::jsonb and result ->> 'why' ~ 'no run' from one.actions where run_key = 'quiet-run' and step = 'verify'),
                  'no run to judge by: unverified');
select pg_temp.ok((select status = 'skipped' and result ? 'error' from one.actions where run_key = 'bad-run' and step = 'verify'), 'a run that cannot be judged says why');

-- 7. The rate limit: more rows than per_tick opens a proposal; approving runs it once ------------------------------------
insert into public.web_outbox (kind, status, attempts, max_attempts) values ('lead', 'dead', 1, 5), ('lead', 'dead', 1, 5);
update one.settings set value = jsonb_set(value, '{FIX-OUTBOX-WEB,per_tick}', '1') where key = 'fixes';
select pg_temp.cool();
-- The verdict on the fix's earlier run on this incident first (D-084; WEB-01 has not run since: unverified).
update one.actions set verify_at = now() - interval '1 minute' where fix_id = 'FIX-OUTBOX-WEB' and step = 'after' and status = 'done' and verify_at > now();
select one.fix_verify_due() as verified_web \gset
select one.fix_run('FIX-OUTBOX-WEB', :i_web1, false, 'one') as over \gset
select pg_temp.ok(:'over'::jsonb ->> 'skipped' = 'over_limit', 'two rows over a limit of one: nothing done: ' || :'over');
select pg_temp.ok((select count(*) = 1 from public.stub_calls where fn = 'public.web_outbox_retry'), 'no row was sent again');
select (:'over'::jsonb ->> 'proposal')::bigint as p_over \gset
select pg_temp.ok((select risk = 'high' and change -> 'execute' -> 'rows' = '[5, 6]' from one.proposals where id = :p_over), 'the proposal names the rows');
-- What the approver sees is the proposal now; the tick then refreshes it with two more rows before they approve.
select change as shown from one.proposals where id = :p_over \gset
insert into public.web_outbox (kind, status, attempts, max_attempts) values ('lead', 'dead', 1, 5), ('lead', 'dead', 1, 5);
select pg_temp.cool();
select one.fix_run('FIX-OUTBOX-WEB', :i_web1, false, 'one') as over2 \gset
select pg_temp.ok((select change -> 'execute' -> 'rows' = '[5, 6, 7, 8]' from one.proposals where id = :p_over), 'the waiting proposal was refreshed with the new rows');
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err(format($q$select one.ui_proposal_decide(%s, 'approve')$q$, :p_over)) = '42501', 'a fix proposal is the owner''s');
select pg_temp.as_owner();
-- The owner approves the change as shown, with row 6 removed and rows 2 and 3 added by hand.
select one.ui_proposal_decide(:p_over, 'approve', 'go', jsonb_set(:'shown'::jsonb, '{execute,rows}', '[2, 3, 5]')) as dec_over \gset
reset role;
select pg_temp.ok((:'dec_over'::jsonb -> 'executed' ->> 'status') = 'done', 'approving ran it');
select pg_temp.ok((select array_agg(arg::text::bigint order by arg::text::bigint) from public.stub_calls where fn = 'public.web_outbox_retry') = array[1, 5]::bigint[],
                  'on the rows both proposed and approved: a removed row stays out, an added one or a refresh cannot widen it (review M2)');
select pg_temp.ok((select status = 'applied' and check_due_at between now() + interval '9 minutes' and now() + interval '11 minutes'
                          and change -> 'approved_rows' = '[5]' and change ? 'approved_change'
                     from one.proposals where id = :p_over), 'applied, checked in 10 minutes, what was approved kept');
select pg_temp.ok((select ran_by = 'owner@eduwit.in' and proposal_id = :p_over from one.actions where fix_id = 'FIX-OUTBOX-WEB' and step = 'after' order by id desc limit 1),
                  'the run is the owner''s, tied to the proposal');

-- 8. FIX-OUTBOX-B2B: B2B's admin action under the owner's session --------------------------------------------------------
select id as p_b2b from one.proposals where app = 'b2b' and status = 'open' \gset
set role authenticated;
select pg_temp.as_owner();
select one.ui_proposal_decide(:p_b2b, 'approve', 'send them') as dec_b2b \gset
reset role;
select pg_temp.ok((:'dec_b2b'::jsonb -> 'executed' ->> 'status') = 'failed'
                  and (select jsonb_array_length(result -> 'refused') = 2 from one.actions where fix_id = 'FIX-OUTBOX-B2B' and step = 'after' and not dry_run order by id desc limit 1),
                  'B2B refuses an owner who is not a B2B admin: nothing sent: ' || :'dec_b2b' || ' / '
                  || coalesce((select result::text from one.actions where fix_id = 'FIX-OUTBOX-B2B' and step = 'after' and not dry_run order by id desc limit 1), 'no after row'));
select pg_temp.ok((select status = 'approved' and check_due_at is null and check_result ->> 'ran' = 'false' from one.proposals where id = :p_b2b),
                  'a refused approval is not marked applied, and says it did not run (review M12)');
insert into b2b.app_users (user_id, role) values ('00000000-0000-0000-0000-000000000001', 'admin');
select pg_temp.cool();
select one.fix_run('FIX-OUTBOX-B2B', :i_b2b1, false, 'one') as again \gset
select (:'again'::jsonb ->> 'proposal')::bigint as p_b2b2 \gset
set role authenticated;
select pg_temp.as_owner();
select one.ui_proposal_decide(:p_b2b2, 'approve', 'send them') as dec_b2b2 \gset
reset role;
select pg_temp.ok((select array_agg(arg::text::bigint order by arg::text::bigint) from public.stub_calls where fn = 'b2b.outbox_retry') = array[1, 2]::bigint[]
                  and (select array_agg(status order by id) from b2b.integration_outbox where id in (1, 2, 3)) = array['pending', 'pending', 'dead'],
                  'a B2B admin''s approval sent the two deliveries again (not the test one), with the fixer''s rights');
select pg_temp.ok((select status = 'applied' from one.proposals where id = :p_b2b2), 'applied');
update one.proposals set check_due_at = now() - interval '1 minute' where id = :p_b2b2;
select one.proposals_verify_due() as pv \gset
select pg_temp.ok((select not (check_result ->> 'ok')::boolean and (check_result ->> 'delivered')::int = 0 and (check_result ->> 'still_sending')::int = 2
                     from one.proposals where id = :p_b2b2), 'checked at check_due_at: sent again is not yet delivered (review M4)');
update b2b.integration_outbox set status = 'delivered' where id in (1, 2);
update one.proposals set check_result = null where id = :p_b2b2;
select one.proposals_verify_due() as pv2 \gset
select pg_temp.ok((select (check_result ->> 'ok')::boolean and (check_result ->> 'delivered')::int = 2 from one.proposals where id = :p_b2b2),
                  'delivered: ok');
set role authenticated;
select pg_temp.as_owner();
select (one.ui_proposal_create('fix', 'b2b', 'Run the B2B retry by hand', 'a person''s own proposal, with an execute key in it',
                               '{"execute": {"fix": "FIX-OUTBOX-B2B", "incident": 1, "rows": [4]}}', 'low') ->> 'id')::bigint as p_person \gset
select pg_temp.ok((one.ui_proposal_decide(:p_person, 'approve', 'ok') -> 'executed') = 'null'::jsonb, 'a person''s proposal never runs anything');
reset role;
select pg_temp.ok((select check_due_at is null from one.proposals where id = :p_person), 'and is not waiting for a check that never comes');
set role authenticated;
select pg_temp.as_owner();
reset role;
select pg_temp.ok((select count(*) = 2 from public.stub_calls where fn = 'b2b.outbox_retry'), 'nothing more was sent');

-- Two fixes on one check and one failing run: the incident goes up one level, not two (review M6).
update one.incidents set severity = 'P3' where id = :i_web1;
update one.actions set verify_at = now() - interval '1 minute', ran_at = now() - interval '3 minutes'
 where step = 'after' and fix_id in ('FIX-OUTBOX-WEB', 'FIX-CATALOG-POLL') and verify_at is not null;
insert into one.results (check_id, ran_at, status, value)
values ('WEB-01', now(), 'fail', '{"outbox_dead": 3, "outbox_oldest_pending_seconds": 1000, "catalog_checked_seconds_ago": 900}');
select one.fix_verify_due() as verified_web \gset
select pg_temp.ok((select severity = 'P2' from one.incidents where id = :i_web1)
                  and (select count(*) >= 2 from one.actions where step = 'verify' and status = 'failed' and incident_id = :i_web1)
                  and (select count(*) = 1 from one.actions where step = 'verify' and incident_id = :i_web1 and (result ->> 'escalated')::boolean),
                  'two fixes did not hold on one failing run: one level up');

-- 9. The Fixes page ----------------------------------------------------------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select one.ui_fixes() as fixes \gset
select pg_temp.ok(jsonb_array_length(:'fixes'::jsonb -> 'fixes') = 11 and not (:'fixes'::jsonb #>> '{window,running}')::boolean, 'the page lists every fix and the window');
select pg_temp.ok((select bool_and((f -> 'grants_state' ->> 'ok')::boolean) from jsonb_array_elements(:'fixes'::jsonb -> 'fixes') f),
                  'every grant is in place: ' || (select string_agg((f ->> 'id') || '=' || (f ->> 'grants_state'), '; ') from jsonb_array_elements(:'fixes'::jsonb -> 'fixes') f));
select pg_temp.ok((select (f -> 'counts' ->> 'dry_runs')::int >= 1 and jsonb_array_length(f -> 'recent') > 0
                            and (f -> 'counts' ->> 'runs')::int = 0 and (f -> 'counts' ->> 'proposals')::int = 1
                     from jsonb_array_elements(:'fixes'::jsonb -> 'fixes') f where f ->> 'id' = 'FIX-OUTBOX-W2'),
                  'with its dry-run history; a proposing fix counts proposals, not runs (review m3)');
select pg_temp.ok((select (i -> 'stopped')::boolean from jsonb_array_elements(:'fixes'::jsonb -> 'fixes') f, jsonb_array_elements(f -> 'open_incidents') i
                    where f ->> 'id' = 'FIX-CURSOR-B2C'), 'and the incidents it stopped on');
select pg_temp.ok(pg_temp.err($q$select one.ui_fix_set('FIX-CACHE-B2C', '{"enabled": false}', 'off for now')$q$) = '42501', 'switching a fix is the owner''s');
select pg_temp.ok(pg_temp.err($q$select one.ui_fix_dry_run('FIX-CACHE-B2C', 999999)$q$) = 'P0002', 'a dry run needs a real incident');
select pg_temp.ok((one.ui_fix_dry_run('FIX-CACHE-B2C', :i_cat1) ->> 'dry_run')::boolean, 'an engineer may run a dry run');
select pg_temp.as_owner();
select pg_temp.ok((one.ui_fix_set('FIX-CACHE-B2C', '{"enabled": false, "cooldown_min": 30}', 'off for now') ->> 'ok')::boolean, 'the owner switches a fix off');
select pg_temp.ok(pg_temp.err($q$select one.ui_fix_set('FIX-CACHE-B2C', '{"sql": "x"}', 'sneak')$q$) = '22023', 'only the switch and the limits change here');
select pg_temp.ok(pg_temp.err($q$select one.ui_fix_set('FIX-CACHE-B2C', '{"cooldown_min": 30}', 'again')$q$) = '22023', 'nothing changed is refused');
reset role;
select pg_temp.ok((select count(*) = 1 from one.audit where action = 'fix.set' and target = 'fix:FIX-CACHE-B2C'), 'audited');
select pg_temp.ok((select (value #>> '{FIX-CACHE-B2C,cooldown_min}')::int = 30 from one.settings where key = 'fixes'), 'versioned in settings');

-- 10. The brief and the tick ---------------------------------------------------------------------------------------------
select pg_temp.ok(jsonb_array_length(one.ai_brief_stats(((now() at time zone 'Asia/Kolkata')::date + 1)) #> '{fixes,by_fix}') >= 1
                  and (one.ai_brief_stats(((now() at time zone 'Asia/Kolkata')::date + 1)) #> '{fixes,window}') is not null, 'the next brief counts what each fix did');
select pg_temp.ok(one.fixes_step() ? 'fixes', 'the fix step reports what each fix did');
select pg_temp.ok(not (one.tick_app_call() ? 'fixes'), 'the app call no longer runs the fixes');
call one.fixes_job(null) \gset job_
select pg_temp.ok(:'job_p_report'::jsonb ? 'fixes', 'the minute job''s fix step runs, committing as it goes');
select pg_temp.ok(pg_get_functiondef('one.tick_job()'::regprocedure) ~ 'call one\.fixes_job\(v_fixes\)', 'the minute job runs them after the app call, in their own transactions (review M8)');
select pg_temp.ok(not exists (select 1 from one.actions where target::text ~ '9198765|910000' or result::text ~ '9198765|910000'), 'still no phone anywhere in the history');

-- Tidy up --------------------------------------------------------------------------------------------------------------
truncate one.actions, one.proposals, one.incidents restart identity cascade;
update one.settings s set value = t.value from t_fixes t where s.key = 'fixes';
delete from public.w2_outbox where phone in ('919876500001', '910000123456', '919876500002', '919876500003');
set role postgres;
drop table public.stub_calls, public.w2_gemini_caches, public.web_outbox, b2b.integration_outbox, b2b.app_users, b2c.inbox, b2c.outbox;
reset role;
select set_config('request.jwt.claims', '', false);
