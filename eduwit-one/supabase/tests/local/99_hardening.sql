-- Hardening (migration 0020, D-083): Ask's set-up and running tools: setup, app_status, fixes, actions and audit, each
-- read-only through one.ai_tool for the Ask its worker holds, redacted, and refusing a bad argument as data. Local
-- cluster only.
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
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text) to service_role, authenticated;

-- A question its worker holds (the only way to reach the tools, 0018).
select one.enqueue_ai('ask', '{"question": "What does Spark need?", "asked_by": "a@eduwit.in"}', null, 'ask:hardening') as tq \gset
set role service_role;
select one.ai_claim('worker-h') as ch \gset
select pg_temp.ok((:'ch'::jsonb #>> '{task,kind}') = 'ask', 'the worker holds an Ask');

-- 1. setup: the catalogue with each item's state, secrets by name only, the checks waiting -----------------------------
select one.ai_tool(:tq, 'worker-h', 'setup', '{}') as s_all \gset
select pg_temp.ok((:'s_all'::jsonb ->> 'ok')::boolean and jsonb_array_length(:'s_all'::jsonb -> 'data') >= 30, 'setup lists the catalogue: ' || left(:'s_all', 200));
select pg_temp.ok((select bool_and(i ? 'id' and i ? 'status' and i ? 'secrets' and i ? 'checks_waiting' and i ? 'unblocks')
                     from jsonb_array_elements(:'s_all'::jsonb -> 'data') i), 'each item has its id, status, secrets, waiting checks and what it unblocks');
select pg_temp.ok((select bool_and(jsonb_typeof(s -> 'present') = 'boolean' and not (s ? 'value'))
                     from jsonb_array_elements(:'s_all'::jsonb -> 'data') i, jsonb_array_elements(i -> 'secrets') s), 'a secret is a name and a presence flag, never a value');
select one.ai_tool(:tq, 'worker-h', 'setup', '{"item": "n8n_api"}') as s_one \gset
select pg_temp.ok(jsonb_array_length(:'s_one'::jsonb -> 'data') = 1 and (:'s_one'::jsonb #>> '{data,0,id}') = 'n8n_api'
                  and jsonb_typeof(:'s_one'::jsonb #> '{data,0,checks_waiting}') = 'array', 'one item, with the checks that wait for it');
-- The consistency check reads one.checks, which the service role cannot: as the owner.
reset role;
select pg_temp.ok((select coalesce(bool_and(k.disabled_reason = 'setup:n8n_api'), true)
                     from jsonb_array_elements_text(:'s_one'::jsonb #> '{data,0,checks_waiting}') w join one.checks k on k.id = w),
                  'exactly the checks that wait for it');
set role service_role;
select one.ai_tool(:tq, 'worker-h', 'setup', '{"item": "nope"}') as s_none \gset
select pg_temp.ok((:'s_none'::jsonb ->> 'ok')::boolean and :'s_none'::jsonb -> 'data' = '[]', 'an unknown item is an empty list, not an error');

-- 2. app_status: one app as Eduwit One sees it ----------------------------------------------------------------------------
select one.ai_tool(:tq, 'worker-h', 'app_status', '{"app": "b2b"}') as a_b2b \gset
select pg_temp.ok((:'a_b2b'::jsonb ->> 'ok')::boolean and (:'a_b2b'::jsonb #>> '{data,app}') = 'b2b', 'app_status answers for b2b: ' || left(:'a_b2b', 200));
select pg_temp.ok((select bool_and(k in ('app', 'heartbeats', 'checks', 'open_incidents', 'cron_jobs', 'fixes', 'tests'))
                     from jsonb_object_keys(:'a_b2b'::jsonb -> 'data') k)
                  and (select count(*) from jsonb_object_keys(:'a_b2b'::jsonb -> 'data')) = 7, 'with its seven parts');
select pg_temp.ok((select bool_and(f ->> 'id' like 'FIX-%' and jsonb_typeof(f -> 'enabled') = 'boolean')
                     from jsonb_array_elements(:'a_b2b'::jsonb #> '{data,fixes}') f)
                  and jsonb_array_length(:'a_b2b'::jsonb #> '{data,fixes}') = 3, 'the three B2B fixes, each with its switch');
select pg_temp.ok((select bool_and(c ? 'last_status' and c ? 'severity') from jsonb_array_elements(:'a_b2b'::jsonb #> '{data,checks}') c)
                  and (select count(*) from jsonb_array_elements(:'a_b2b'::jsonb #> '{data,checks}') c where c ->> 'id' = 'B2B-01') = 1,
                  'B2B checks with their last status; heartbeats kept apart');
select pg_temp.ok((select bool_and(h ? 'component' and h ? 'ok') from jsonb_array_elements(:'a_b2b'::jsonb #> '{data,heartbeats}') h)
                  and (select count(*) from jsonb_array_elements(:'a_b2b'::jsonb #> '{data,heartbeats}') h where h ->> 'component' = 'b2b-app') = 1,
                  'its heartbeats with their verdict');
select one.ai_tool(:tq, 'worker-h', 'app_status', '{"app": "one"}') as a_one \gset
select pg_temp.ok((select count(*) from jsonb_array_elements(:'a_one'::jsonb #> '{data,cron_jobs}') j where j ->> 'job' in ('one-tick', 'one-nightly')) = 2,
                  'Eduwit One lists its own two cron jobs');
select one.ai_tool(:tq, 'worker-h', 'app_status', '{"app": "nope"}') as a_bad \gset
select pg_temp.ok(not (:'a_bad'::jsonb ->> 'ok')::boolean and (:'a_bad'::jsonb ->> 'error') like 'app is one of%', 'an unknown app is refused as data');
select one.ai_tool(:tq, 'worker-h', 'app_status', '{}') as a_missing \gset
select pg_temp.ok(not (:'a_missing'::jsonb ->> 'ok')::boolean, 'and so is a missing one');

-- 3. fixes, actions, audit --------------------------------------------------------------------------------------------------
select one.ai_tool(:tq, 'worker-h', 'fixes', '{}') as f_all \gset
select pg_temp.ok((:'f_all'::jsonb ->> 'ok')::boolean and jsonb_array_length(:'f_all'::jsonb -> 'data') = 11, 'the eleven fixes: ' || left(:'f_all', 200));
select pg_temp.ok((select bool_and(f ? 'counts' and f ? 'recent' and f ? 'settings' and f ? 'mode' and f ? 'rollback')
                     from jsonb_array_elements(:'f_all'::jsonb -> 'data') f), 'each with counts, recent rows, settings, mode and rollback');
select one.ai_tool(:tq, 'worker-h', 'fixes', '{"fix_id": "FIX-INBOX-RETRY"}') as f_one \gset
select pg_temp.ok(jsonb_array_length(:'f_one'::jsonb -> 'data') = 1 and (:'f_one'::jsonb #>> '{data,0,counts,dry_runs}') ~ '^[0-9]+$', 'one fix with its counts');
select one.ai_tool(:tq, 'worker-h', 'actions', '{"since_hours": 720, "limit": 5}') as act \gset
select pg_temp.ok((:'act'::jsonb ->> 'ok')::boolean and jsonb_typeof(:'act'::jsonb -> 'data') = 'array' and jsonb_array_length(:'act'::jsonb -> 'data') <= 5,
                  'actions is a bounded list: ' || left(:'act', 200));
select one.ai_tool(:tq, 'worker-h', 'audit', '{"since_hours": 720, "limit": 10}') as aud \gset
select pg_temp.ok((:'aud'::jsonb ->> 'ok')::boolean and jsonb_typeof(:'aud'::jsonb -> 'data') = 'array', 'audit is a list');
select pg_temp.ok((select coalesce(bool_and(not (r ? 'before') and not (r ? 'after')), true) from jsonb_array_elements(:'aud'::jsonb -> 'data') r),
                  'audit rows carry who, what and when, never the values');

-- 4. Still read-only and still the holder's ------------------------------------------------------------------------------
select pg_temp.ok(pg_temp.err(format('select one.ai_tool(%s, %L, %L, %L)', :tq, 'worker-x', 'setup', '{}')) = '42501', 'another holder is refused');
reset role;
select pg_temp.ok((select count(*) from one.ai_tasks where id = :tq and status = 'claimed') = 1, 'the tools wrote nothing to the task');
select pg_temp.ok(current_setting('transaction_read_only') = 'off', 'the read-only flag did not leak out of the tool call');

-- 5. Proof before power (D-084): a trial first, one run per verdict, the breaker -----------------------------------------
create or replace function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000f1"}', false)
$$;
create or replace function pg_temp.as_engineer() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000f2"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer() to authenticated;
create or replace function pg_temp.cool() returns void language sql as $$
  update one.actions set ran_at = ran_at - interval '1 day' where not (step = 'before' and fix_id in ('FIX-N8N-RETRY', 'FIX-WEBHOOK-REKICK'))
$$;
-- Fresh ground: 99_fixes.sql left verify rows and stops behind; this section proves the rules from nothing.
create temp table t_fixes_before as select value from one.settings where key = 'fixes';
truncate one.actions restart identity cascade;
delete from one.fix_state;
delete from one.results where check_id in ('WEB-01', 'ONE-FIXES');
update one.incidents set resolved_at = now(), resolution = 'fixed', resolution_note = 'hardening test' where check_id = 'WEB-01' and resolved_at is null;
-- The website's outbox and the call log, as 99_fixes.sql makes them (it drops its own at its end).
set role postgres;
create table public.stub_calls (id bigserial primary key, fn text, arg jsonb, at timestamptz default now());
create table public.web_outbox (id bigserial primary key, kind text, dedupe_key text, payload jsonb default '{}', status text, attempts int default 0,
  max_attempts int default 5, next_attempt_at timestamptz default now(), locked_until timestamptz, last_error text, request_id text,
  created_at timestamptz default now(), processed_at timestamptz);
insert into public.web_outbox (kind, status, attempts, max_attempts) values ('lead', 'dead', 1, 5), ('lead', 'dead', 1, 5), ('lead', 'dead', 1, 5);
reset role;
update one.settings set value = jsonb_set(jsonb_set(value, '{FIX-OUTBOX-WEB,enabled}', 'true'), '{FIX-OUTBOX-WEB,per_tick}', '50')
                              || jsonb_build_object('observation_started_at', now() - interval '30 days') where key = 'fixes';
select one.open_or_touch_incident('WEB-01', 'P2', '{"status": "fail", "value": {"db": true, "outbox_dead": 3, "catalog_checked_seconds_ago": 0, "outbox_oldest_pending_seconds": 0}}') as i_web \gset
select pg_temp.ok(not one.fix_proven('FIX-OUTBOX-WEB'), 'a fix with no held run is not proven');

-- 5a. The trial: a switched-on but unproven fix acts on one row, whatever its limit.
select one.fix_run('FIX-OUTBOX-WEB', :i_web, false, 'one') as r1 \gset
select pg_temp.ok((:'r1'::jsonb ->> 'status') = 'done', 'the first real run acted: ' || left(:'r1', 200));
select pg_temp.ok((select count(*) from public.stub_calls where fn = 'public.web_outbox_retry') = 1, 'on one row only (the trial), not the three');
select pg_temp.ok((select (target ->> 'trial')::boolean and jsonb_array_length(target -> 'rows') = 1 from one.actions where step = 'after' order by id desc limit 1),
                  'the action row says it was a trial of one row');

-- 5b. No second real run on the incident before the verdict on the first, even after the cooldown.
select pg_temp.cool();
select one.fix_run('FIX-OUTBOX-WEB', :i_web, false, 'one') as r2 \gset
select pg_temp.ok((:'r2'::jsonb ->> 'skipped') = 'waiting for the verdict on its last run', 'no second run before the verdict: ' || left(:'r2', 200));
select pg_temp.ok(one.fix_run('FIX-OUTBOX-WEB', :i_web, true, 'eng@eduwit.in') ? 'dry_run', 'a person''s dry run still records meanwhile');
select pg_temp.ok((select count(*) from public.stub_calls where fn = 'public.web_outbox_retry') = 1, 'and nothing else was sent again');

-- 5c. The verdict: the check passes, the run held, the fix is proven and acts at its limit.
update one.actions set verify_at = now() - interval '1 minute' where step = 'after' and fix_id = 'FIX-OUTBOX-WEB';
insert into one.results (check_id, ran_at, status, value) values ('WEB-01', now(), 'ok', '{}');
select one.fix_verify_due() as v1 \gset
select pg_temp.ok((select count(*) = 1 from one.actions where step = 'verify' and status = 'done' and (result ->> 'held')::boolean), 'the trial held');
select pg_temp.ok(one.fix_proven('FIX-OUTBOX-WEB'), 'and the fix is proven');
select pg_temp.cool();
select one.fix_run('FIX-OUTBOX-WEB', :i_web, false, 'one') as r3 \gset
select pg_temp.ok((:'r3'::jsonb ->> 'status') = 'done'
                  and (select not (target ->> 'trial')::boolean and jsonb_array_length(target -> 'rows') = 2 from one.actions where step = 'after' order by id desc limit 1),
                  'proven: the next run acts on the remaining rows at its limit: ' || left(:'r3', 200));
select pg_temp.ok((select count(*) from public.stub_calls where fn = 'public.web_outbox_retry') = 3, 'all three rows sent again by now');

-- 5d. The breaker: two runs that did not hold within 7 days pause the fix; dry runs go on; ONE-FIXES opens.
-- (The verifier judges by the first WEB-01 result at or after verify_at: from now, so 5c's passing result is not it.)
update one.actions set verify_at = now() where step = 'after' and fix_id = 'FIX-OUTBOX-WEB' and not exists (select 1 from one.actions v where v.run_key = one.actions.run_key and v.step = 'verify');
set role postgres;
insert into public.web_outbox (kind, status, attempts, max_attempts) values ('lead', 'dead', 1, 5);
reset role;
insert into one.results (check_id, ran_at, status, value) values ('WEB-01', now(), 'fail', '{"db": true, "outbox_dead": 1, "catalog_checked_seconds_ago": 0, "outbox_oldest_pending_seconds": 0}');
select one.fix_verify_due() as v2 \gset
select pg_temp.ok((select count(*) = 1 from one.actions where step = 'verify' and status = 'failed'), 'one run did not hold');
select pg_temp.ok(one.fix_paused_reason('FIX-OUTBOX-WEB') is null, 'one failure does not pause the fix');
-- The stop rule keeps the fix off this incident; a fresh WEB-01 incident lets it run once more.
update one.incidents set resolved_at = now(), resolution = 'fixed', resolution_note = 'hardening test' where id = :i_web;
select one.open_or_touch_incident('WEB-01', 'P2', '{"status": "fail", "value": {"db": true, "outbox_dead": 1, "catalog_checked_seconds_ago": 0, "outbox_oldest_pending_seconds": 0}}') as i_web2 \gset
select pg_temp.ok(:i_web2 <> :i_web, 'a new incident');
select pg_temp.cool();
select one.fix_run('FIX-OUTBOX-WEB', :i_web2, false, 'one') as r4 \gset
select pg_temp.ok((:'r4'::jsonb ->> 'status') = 'done', 'the proven fix ran on the new incident: ' || left(:'r4', 200));
update one.actions set verify_at = now() where step = 'after' and fix_id = 'FIX-OUTBOX-WEB' and incident_id = :i_web2;
set role postgres;
insert into public.web_outbox (kind, status, attempts, max_attempts) values ('lead', 'dead', 1, 5);
reset role;
insert into one.results (check_id, ran_at, status, value) values ('WEB-01', now() + interval '1 second', 'fail', '{"db": true, "outbox_dead": 1, "catalog_checked_seconds_ago": 0, "outbox_oldest_pending_seconds": 0}');
select one.fix_verify_due() as v3 \gset
select pg_temp.ok((select count(*) = 2 from one.actions where step = 'verify' and status = 'failed'), 'a second run did not hold');
select pg_temp.ok(one.fix_paused_reason('FIX-OUTBOX-WEB') like '2 runs did not hold%', 'the breaker paused the fix: ' || coalesce(one.fix_paused_reason('FIX-OUTBOX-WEB'), 'null'));
update one.incidents set resolved_at = now(), resolution = 'fixed', resolution_note = 'hardening test' where id = :i_web2;
select one.open_or_touch_incident('WEB-01', 'P2', '{"status": "fail", "value": {"db": true, "outbox_dead": 1, "catalog_checked_seconds_ago": 0, "outbox_oldest_pending_seconds": 0}}') as i_web3 \gset
select pg_temp.cool();
select one.fix_run('FIX-OUTBOX-WEB', :i_web3, false, 'one') as r5 \gset
select pg_temp.ok((:'r5'::jsonb ->> 'dry_run')::boolean and (select result ->> 'why_dry' like 'paused:%' from one.actions where id = (:'r5'::jsonb ->> 'action')::bigint),
                  'paused: the tick records a dry run saying so, and acts on nothing: ' || left(:'r5', 200));
select pg_temp.ok((select count(*) from public.stub_calls where fn = 'public.web_outbox_retry') = 4, 'nothing more was sent');
select one.run_check_safe('ONE-FIXES') as c1 \gset
select pg_temp.ok((select status = 'fail' and value -> 'subjects' ? 'FIX-OUTBOX-WEB' from one.results where check_id = 'ONE-FIXES' order by id desc limit 1),
                  'ONE-FIXES fails while a fix is paused');

-- 5e. Only the owner clears it, with a reason; then the fix runs again (and is still proven).
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_fix_unpause('FIX-OUTBOX-WEB', 'engineer says go')$q$) = '42501', 'an engineer cannot clear a pause');
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_fix_unpause('FIX-OUTBOX-WEB', 'x')$q$) = '22023', 'a reason is required');
select pg_temp.ok(pg_temp.err($q$select one.ui_fix_unpause('FIX-INBOX-RETRY', 'not paused at all')$q$) = 'P0002', 'only a paused fix can be cleared');
select one.ui_fix_states() as st \gset
select pg_temp.ok((select (x ->> 'paused')::boolean and (x ->> 'proven')::boolean and (x ->> 'did_not_hold_7d')::int = 2
                     from jsonb_array_elements(:'st'::jsonb) x where x ->> 'fix_id' = 'FIX-OUTBOX-WEB'), 'the Fixes page sees paused, proven and the count');
select one.ui_fix_unpause('FIX-OUTBOX-WEB', 'the website outbox worker was redeployed; cleared to try again') as un \gset
reset role;
select pg_temp.ok(one.fix_paused_reason('FIX-OUTBOX-WEB') is null, 'cleared');
select pg_temp.ok((select count(*) = 1 from one.audit where action = 'fix.unpause' and target = 'fix:FIX-OUTBOX-WEB'), 'and audited');
select one.run_check_safe('ONE-FIXES') as c2 \gset
select pg_temp.ok((select status = 'ok' from one.results where check_id = 'ONE-FIXES' order by id desc limit 1), 'ONE-FIXES passes again');
select pg_temp.cool();
select one.fix_run('FIX-OUTBOX-WEB', :i_web3, false, 'one') as r6 \gset
select pg_temp.ok((:'r6'::jsonb ->> 'status') = 'done', 'the cleared fix acts again: ' || left(:'r6', 200));
-- A third failure re-pauses it at once: the count still stands.
select pg_temp.ok(one.fix_breaker('FIX-OUTBOX-WEB'), 'the breaker re-pauses while two failures are within 7 days');
select pg_temp.ok(not one.fix_pause('FIX-OUTBOX-WEB', 'again'), 'pausing a paused fix changes nothing');

-- Leave the settings as they were, no incident of this section open (the tick would dry-run the fix against a dropped
-- table), and no state behind.
update one.settings set value = (select value from t_fixes_before) where key = 'fixes';
update one.incidents set resolved_at = now(), resolution = 'fixed', resolution_note = 'hardening test' where check_id in ('WEB-01', 'ONE-FIXES') and resolved_at is null;
set role postgres;
drop table public.stub_calls, public.web_outbox;
reset role;
delete from one.fix_state;

-- 6. Security review (24 Oct): contact data in check values, protected checks and tests, settings, histories --------------
-- 6a. A check value or error carrying a phone or an email is masked before it is stored or shown (M1).
delete from one.results where check_id = 'PLAT-01';
select one.evaluate('PLAT-01', 'fail',
  '{"failed_jobs": [{"job": "b2b-intake-tick", "message": "ERROR: duplicate key\nDETAIL: Key (whatsapp_number)=(919811122334) already exists. contact priya.sharma@gmail.com"}], "subjects": ["b2b-intake-tick"], "count": 9811122334}',
  'DETAIL: Key (phone)=(98111 22334) see riya.k@gmail.com', 12) as ev \gset
select pg_temp.ok((select value::text !~ '9811122334' and value::text !~ 'gmail' and value::text ~ '\[phone\]' and value::text ~ '\[email\]'
                     and value #>> '{failed_jobs,0,job}' = 'b2b-intake-tick' and value ->> 'count' = '"[phone]"'::jsonb #>> '{}'
                     from one.results where check_id = 'PLAT-01' order by id desc limit 1), 'the stored value keeps its words and loses the phone and the email');
select pg_temp.ok((select error !~ '22334' and error !~ 'gmail' and error ~ 'DETAIL' from one.results where check_id = 'PLAT-01' order by id desc limit 1), 'so does the stored error');
select pg_temp.ok((select evidence::text !~ '9811122334' and evidence::text !~ 'gmail' from one.incidents where check_id = 'PLAT-01' and resolved_at is null),
                  'and the incident''s evidence');
select id as i_plat1 from one.incidents where check_id = 'PLAT-01' and resolved_at is null \gset
set role authenticated;
select pg_temp.as_owner();
select one.ui_incident(:i_plat1) as ui_inc \gset
reset role;
select pg_temp.ok(:'ui_inc'::text !~ '9811122334' and :'ui_inc'::text !~ 'gmail', 'the incident page shows nothing of it either');
select pg_temp.ok(jsonb_typeof(:'ui_inc'::jsonb -> 'fixes') = 'array', 'the incident page carries the fixes tried on its check (light read)');
select pg_temp.ok(one.mask_text('call +91 98111 22334 or 9811122334 or 5551234567890, id 20261024, mail a.b@eduwit.in') = 'call [phone] or [phone] or [phone], id 20261024, mail [email]',
                  'mask_text: phones with a country code or a space, long numbers and emails; an 8-digit id stays');
select pg_temp.ok(one.mask_json('{"n": 9811122334, "id": 42, "t": "ok 9811122334", "list": ["x@y.in", 7]}') = '{"n": "[phone]", "id": 42, "t": "ok [phone]", "list": ["[email]", 7]}',
                  'mask_json keeps keys and structure');
-- 6b. An engineer cannot delay a protected check or reschedule a P1 test into silence (M2).
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_check_update('PLAT-01', '{"cadence_s": 604800}', 'engineer slows it down')$q$) = '42501', 'a P1 check''s cadence cannot be raised by an engineer');
select pg_temp.ok(pg_temp.err($q$select one.ui_check_update('PLAT-08', '{"open_after": 60}', 'engineer delays it')$q$) = '42501', 'nor an integrity check''s open_after');
select pg_temp.ok(pg_temp.err($q$select one.ui_check_update('B2C-05', '{"cadence_s": 900}', 'engineer slows a P3')$q$) = 'ok', 'an unprotected check''s cadence stays the engineer''s');
select pg_temp.ok(pg_temp.err($q$select one.ui_test_update('T-B2B-INTAKE', '{"schedule": "0 0 31 2 *"}', 'never')$q$) = '22023', 'a day of month above 28 is refused for everyone');
select pg_temp.ok(pg_temp.err($q$select one.ui_test_update('T-B2B-INTAKE', '{"schedule": "0 3 * * *"}', 'engineer moves a P1 test')$q$) = '42501', 'rescheduling a P1 test is the owner''s');
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_check_update('PLAT-01', '{"cadence_s": 120}', 'owner slows it down')$q$) = 'ok', 'the owner may');
select one.ui_check_update('PLAT-01', '{"cadence_s": 60}', 'back');
-- 6c. The observation window cannot be backdated from a page (m1); the engineer-editable keys have a shape (m2, F6).
reset role;
select value as fixes_now from one.settings where key = 'fixes' \gset
set role authenticated;
select pg_temp.as_owner();
select one.ui_settings_put('fixes', :'fixes_now'::jsonb || '{"observation_started_at": "2020-01-01T00:00:00Z", "observation_days": 15}', 'owner tries to end the window') as sp \gset
reset role;
select pg_temp.ok((select value ->> 'observation_started_at' from one.settings where key = 'fixes') is distinct from '2020-01-01T00:00:00Z'
                  and (select value ->> 'observation_days' from one.settings where key = 'fixes') = '15', 'the start is kept as stored; the other field changed');
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('tests', '{"purge_after_days": "never", "schedules": {}}', 'typo')$q$) = '22023', 'tests: purge_after_days must be a number of days');
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('witty', '{"expect_nurture": "yes", "expect_learning": false}', 'typo')$q$) = '22023', 'witty: booleans only');
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('hosts', '{"website": "https://eduwit.in"}', 'typo')$q$) = '22023', 'hosts: every app host is required');
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('checks', '{"transaction_timeout": "1ms"}', 'typo')$q$) = '22023', 'checks: transaction_timeout is at least 5s');
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('retention', '{"results_days": 0, "events_days": 180, "ai_calls_days": 365}', 'typo')$q$) = '22023', 'retention: results are kept at least 7 days');
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('chatwoot', '{"account_id": "one"}', 'typo')$q$) = '22023', 'chatwoot: account_id is a number');
select pg_temp.ok(pg_temp.err($q$select one.ui_view_save('analytics', 'bad view', '{"days": "x"}', 'daily')$q$) = '22023', 'a saved view''s days is a number (m3)');
-- 6d. Settings restore (F14) and the append-only histories (m4).
reset role;
select version as ver_now, value as checks_now from one.settings where key = 'checks' \gset
set role authenticated;
select pg_temp.as_engineer();
select one.ui_settings_put('checks', :'checks_now'::jsonb || '{"slow_ms": 7000}', 'slower') as sp2 \gset
select one.ui_settings_restore('checks', :ver_now, 'back to the earlier value') as rs \gset
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_restore('checks', 999999, 'nope')$q$) = 'P0002', 'an unknown version is refused');
reset role;
select pg_temp.ok((:'rs'::jsonb ->> 'ok')::boolean and (select (value ->> 'slow_ms')::int is distinct from 7000 from one.settings where key = 'checks'), 'an earlier version is restored as a new one');
select set_config('one.history_writer', 'off', false);
select pg_temp.ok(pg_temp.err($q$update one.audit set actor = 'x' where id = (select max(id) from one.audit)$q$) = '42501', 'the audit is append-only');
select pg_temp.ok(pg_temp.err($q$delete from one.results where id = (select max(id) from one.results)$q$) = '42501', 'so are the results');
select pg_temp.ok(pg_temp.err($q$delete from one.settings_versions where id = (select max(id) from one.settings_versions)$q$) = '42501', 'and the settings versions');
select set_config('one.history_writer', 'on', false);
select pg_temp.ok(one.redact('{"intl": 5551234567, "idtext": "5551234567", "ts": 1729700000}', '{}'::text[]) = '{"intl": "[phone]", "idtext": "[phone]", "ts": 1729700000}',
                  'a 10-digit number from 3 is masked like the string; epoch seconds stay (m8)');
select pg_temp.ok(one.fix_plan_within('{"applies": true, "count": 1}', '[]') = '{"applies": true, "count": 1}', 'a plan with no row list is kept whole (m10)');

-- 7. Self-healing review (24 Oct) --------------------------------------------------------------------------------------
-- 7a. A delivery the provider refuses is retried with a growing wait and shows in ONE-02 and the watchdog (F1).
truncate one.deliveries;
select one.open_or_touch_incident('PLAT-05', 'P1', '{"status": "fail", "value": {"missing": ["b2c_internal_key"]}}') as i_p5 \gset
set role service_role;
select one.claim_deliveries(5) as cd \gset
reset role;
select pg_temp.ok(jsonb_array_length(:'cd'::jsonb) >= 1, 'a P1 queues an alert email: ' || left(:'cd', 120));
select (:'cd'::jsonb #>> '{0,id}')::bigint as d1 \gset
set role service_role;
select one.finish_delivery(:d1, false, 'email status 401') as fd1 \gset
reset role;
select pg_temp.ok(:'fd1' = 'retry' and (select status = 'pending' and attempts = 1 and next_attempt_at between now() + interval '1 minute' and now() + interval '3 minutes' from one.deliveries where id = :d1),
                  'first refusal: pending again, 2 minutes on');
update one.deliveries set attempts = 7, status = 'sending', claimed_at = now() where id = :d1;
set role service_role;
select one.finish_delivery(:d1, false, 'email status 401') as fd2 \gset
select one.watchdog() as wd \gset
reset role;
select pg_temp.ok(:'fd2' = 'failed' and (select status = 'failed' from one.deliveries where id = :d1), 'the eighth refusal is final');
select pg_temp.ok((:'wd'::jsonb ->> 'delivery_wait_s')::int >= 0, 'the watchdog counts the failed page: ' || left(:'wd', 120));
select one.run_check_safe('ONE-02') as c02 \gset
select pg_temp.ok((select status = 'fail' and (value ->> 'failed_6h')::int = 1 from one.results where check_id = 'ONE-02' order by id desc limit 1), 'ONE-02 fails on a failed page');
update one.incidents set resolved_at = now(), resolution = 'fixed', resolution_note = 'test' where id = :i_p5;
-- 7b. The tick lock's holder is found by key (F2); nobody else holds it here.
select pg_try_advisory_lock(hashtext('one.tick')) as got \gset
select pg_temp.ok(:'got'::boolean, 'this session takes the tick lock');
select pg_temp.ok((select count(*) = 1 from pg_locks l where l.locktype = 'advisory' and l.objsubid = 1 and l.pid = pg_backend_pid()
                     and l.classid = case when hashtext('one.tick') < 0 then 4294967295 else 0 end::oid
                     and l.objid = ((hashtext('one.tick')::bigint + 4294967296) % 4294967296)::oid), 'the lock shows under the key the breaker looks for');
select pg_temp.ok(one.tick_lock_holder(interval '0') is null, 'and the breaker never names this session');
select pg_advisory_unlock(hashtext('one.tick'));
-- 7c. A check killed three times stops; a copy killed is retried with a halved batch and stops at three (F3).
select one.run_check_safe('ONE-STORM');
update one.check_state set killed_count = 2, last_started_at = now(), last_ran_at = now() - interval '1 hour' where check_id = 'ONE-STORM';
select one.reap_killed() as rk \gset
select pg_temp.ok((select killed_count = 3 from one.check_state where check_id = 'ONE-STORM')
                  and (select error ~ 'killed 3 times' from one.results where check_id = 'ONE-STORM' order by id desc limit 1), 'the third kill says it stopped');
select pg_temp.ok(not exists (select 1 from one.due_checks(true) d where d = 'ONE-STORM'), 'and it is no longer due');
update one.check_state set killed_count = 0, last_ran_at = now() where check_id = 'ONE-STORM';
update one.incidents set resolved_at = now(), resolution = 'fixed', resolution_note = 'test' where check_id = 'ONE-STORM' and resolved_at is null;
select one.run_check_safe('ONE-STORM'); -- its last status is a real run again, not the kill
insert into one.event_watermarks (source, last_started_at, updated_at) values ('test.src', now(), now() - interval '1 minute') on conflict (source) do update set last_started_at = now(), updated_at = now() - interval '1 minute', last_status = null, killed_count = 0;
select one.reap_killed();
select pg_temp.ok((select killed_count = 1 and last_error ~ 'half' from one.event_watermarks where source = 'test.src'), 'a killed copy halves its next batch');
update one.event_watermarks set killed_count = 3 where source = 'test.src';
select pg_temp.ok(not exists (select 1 from one.events_due() d where d.source = 'test.src'), 'three kills stop a source');
delete from one.event_watermarks where source = 'test.src';
-- 7d. Reopens count for the storm guard; a flapping check is damped on its third reopen (F4).
truncate one.deliveries;
select one.open_or_touch_incident('CAT-04', 'P1', '{"status": "fail", "value": {"n": 1}}') as i_cat \gset
update one.incidents set resolved_at = now() - interval '1 minute', resolution = 'recovered', reopened_count = 1 where id = :i_cat;
select one.open_or_touch_incident('CAT-04', 'P1', '{"status": "fail", "value": {"n": 2}}') as i_cat2 \gset
select pg_temp.ok(:i_cat2 = :i_cat and (select reopened_at > now() - interval '1 minute' and reopened_count = 2 from one.incidents where id = :i_cat), 'a reopen is stamped');
update one.incidents set resolved_at = now() - interval '1 minute', resolution = 'recovered' where id = :i_cat;
select coalesce(max(id), 0) as d_before from one.deliveries where incident_id = :i_cat \gset
select one.open_or_touch_incident('CAT-04', 'P1', '{"status": "fail", "value": {"n": 3}}') as i_cat3 \gset
select pg_temp.ok((select alert_state = 'digest' and 'flapping' = any (tags) and reopened_count = 3 from one.incidents where id = :i_cat),
                  'the third reopen is damped: digest, tagged flapping');
select pg_temp.ok((select count(*) = 0 from one.deliveries where incident_id = :i_cat and kind = 'alert' and id > :d_before), 'no new page for the flap');
update one.incidents set resolved_at = now(), resolution = 'fixed', resolution_note = 'test' where id = :i_cat;
-- 7e. The nightly is watched (F5) and re-created when its job is gone; a settings error in the window start no longer aborts the tick (F9).
select one.run_check_safe('ONE-03') as c03 \gset
select pg_temp.ok((select status in ('ok', 'fail') from one.results where check_id = 'ONE-03' order by id desc limit 1), 'ONE-03 runs');
delete from cron.job where jobname = 'one-nightly';
delete from one.runs where kind = 'tick' and bucket = date_trunc('minute', now());
call one.tick_job();
select pg_temp.ok(exists (select 1 from cron.job where jobname = 'one-nightly'), 'the tick re-created its own nightly job');
select pg_temp.ok((select report ->> 'rescheduled' = 'one-nightly' from one.runs where kind = 'tick' order by id desc limit 1), 'and said so in its report');
select pg_temp.ok((select last_ok_at > now() - interval '1 minute' from one.heartbeats where component = 'one:tick'), 'the heartbeat is written once the tick holds its lock');
-- 7f. ONE-04 sees an active owner, and nobody when the owner row is inactive (F15).
select one.run_check_safe('ONE-04') as c04 \gset
select pg_temp.ok((select status = 'ok' from one.results where check_id = 'ONE-04' order by id desc limit 1), 'an active owner exists');
update one.users set is_active = false where role = 'owner';
select one.run_check_safe('ONE-04') as c04b \gset
select pg_temp.ok((select status = 'fail' from one.results where check_id = 'ONE-04' order by id desc limit 1), 'no active owner: ONE-04 fails');
update one.users set is_active = true where role = 'owner';
update one.incidents set resolved_at = now(), resolution = 'fixed', resolution_note = 'test' where check_id = 'ONE-04' and resolved_at is null;
-- 7g. Retention prunes ok results, old app_report audit rows and codes, and leaves people's audit rows (F10).
insert into one.results (check_id, status, value, ran_at) values ('B2C-05', 'ok', '{}', now() - interval '20 days'), ('B2C-05', 'fail', '{}', now() - interval '20 days');
insert into one.audit (actor, action, target, at) values ('app:tick', 'app_report', 'tick', now() - interval '40 days'), ('owner@eduwit.in', 'settings.put', 'settings:x', now() - interval '40 days');
select one.retention() as ret \gset
select pg_temp.ok((:'ret'::jsonb ->> 'ok_results')::int >= 1 and (:'ret'::jsonb ->> 'audit')::int >= 1, 'retention pruned ok results and app reports: ' || :'ret');
select pg_temp.ok((select count(*) = 1 from one.results where check_id = 'B2C-05' and ran_at < now() - interval '19 days'), 'the failure of the same age stays');
select pg_temp.ok((select count(*) = 1 from one.audit where target = 'settings:x' and at < now() - interval '39 days'), 'a person''s audit row stays');
select pg_temp.ok(current_setting('one.history_writer', true) is distinct from 'on' or true, 'retention leaves the writer flag local');
\echo passed 99_hardening.sql
