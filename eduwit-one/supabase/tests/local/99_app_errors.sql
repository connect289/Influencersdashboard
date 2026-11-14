-- The apps report their server-error counts (migration 0041, D-141). The service role reports and nobody else; an
-- unknown app and a malformed batch are refused; nothing that reads as an email or a phone is stored, whatever field it
-- came in; every field and count is capped, and past the hourly row cap only the bucket's "(overflow)" row grows; a
-- second report of the same route and error adds to the bucket's row; the check of an app fails above the threshold
-- and resolves by itself under it; the nightly retention prunes old buckets; a signed-in person reads the page's
-- summary and anon does not; the rollback file removes all of it and the migration applies again over it.
-- Everything here runs in one transaction that is rolled back. Local test cluster only.
\set ON_ERROR_STOP 1
do $$ begin
  if current_database() <> 'rehearsal' or to_regclass('public.stub_health') is null then
    raise exception 'refused: this test rewrites fixtures and runs only on the local test cluster';
  end if;
end $$;
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;
-- 'ok', or the refusal as "SQLSTATE: message".
create or replace function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate || ': ' || sqlerrm;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text) to authenticated, anon, service_role;
create or replace function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000c1"}', false)
$$;
create or replace function pg_temp.as_engineer() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000c2"}', false)
$$;
create or replace function pg_temp.as_stranger() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000009", "session_id": "00000000-0000-0000-0000-0000000000c9"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer(), pg_temp.as_stranger() to authenticated;

begin;
-- The histories are append-only (D-085); this local test may rewrite them, as one.retention() does.
select set_config('one.history_writer', 'on', true);
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002', 'email_code');
delete from one.app_errors;
delete from one.incidents where check_id like '%-ERR';

-- 0. What the migration seeded ------------------------------------------------------------------------------------------
select pg_temp.ok((select count(*) = 5 and bool_and(severity = 'P2' and cadence_s = 300 and kind = 'sql' and open_after = 1 and resolve_after = 2)
                     from one.checks where id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR')),
                  'five checks, one per app that reports: P2, every 5 minutes, resolving after two good readings');
select pg_temp.ok((select bool_and(enabled) from one.checks where id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR'))
                  and (select not enabled and disabled_reason = 'blocked:web_error_reporter_not_ported' from one.checks where id = 'WEB-ERR'),
                  'four are on; the website''s is off until the website carries the reporter');
select pg_temp.ok((select one.threshold('app_errors_15m')) = 20, 'the threshold is seeded at 20 errors in 15 minutes');
select pg_temp.ok(one.setting_owner_only('thresholds'), 'and changing the thresholds stays the owner''s (0039)');
select pg_temp.ok((select relrowsecurity from pg_class where oid = 'one.app_errors'::regclass)
                  and not has_table_privilege('service_role', 'one.app_errors', 'select, insert, update, delete')
                  and not has_table_privilege('authenticated', 'one.app_errors', 'select')
                  and not has_table_privilege('anon', 'one.app_errors', 'select'),
                  'the table is closed to every API role, the service role included');
select pg_temp.ok((select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p where p.oid = 'one.app_error_report(text,jsonb)'::regprocedure)
                  and (select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p where p.oid = 'one.ui_app_errors(text,integer)'::regprocedure),
                  'both doors are SECURITY DEFINER with an empty search_path');

-- 1. Who may report ---------------------------------------------------------------------------------------------------------
select pg_temp.ok(has_function_privilege('service_role', 'one.app_error_report(text,jsonb)', 'execute')
                  and not has_function_privilege('authenticated', 'one.app_error_report(text,jsonb)', 'execute')
                  and not has_function_privilege('anon', 'one.app_error_report(text,jsonb)', 'execute')
                  and not has_function_privilege('eduwit_one_reader', 'one.app_error_report(text,jsonb)', 'execute')
                  and not has_function_privilege('service_role', 'one.app_error_text(text,integer)', 'execute'),
                  'the service role alone executes the writer; its helper is nobody''s');
set role anon;
select pg_temp.ok(pg_temp.err($q$select one.app_error_report('b2b', '[{"route": "/leads", "name": "Error", "n": 1}]')$q$) like '42501:%', 'anon cannot report');
reset role;
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.app_error_report('b2b', '[{"route": "/leads", "name": "Error", "n": 1}]')$q$) like '42501:%',
                  'a signed-in engineer cannot report');
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.app_error_report('b2b', '[{"route": "/leads", "name": "Error", "n": 1}]')$q$) like '42501:%',
                  'nor the owner: the pages have no way to write a count');
reset role;
select pg_temp.ok((select count(*) = 0 from one.app_errors), 'the refused calls stored nothing');

-- 2. The service role reports; the same route and error add to the bucket's row -----------------------------------------------
set role service_role;
select one.app_error_report('b2b', '[{"route": "/leads/[id]", "name": "TypeError", "n": 3, "message": "cannot read owner of undefined", "digest": "1234567", "kind": "render"},
                                     {"route": "/api/health", "name": "Error", "n": 1, "kind": "route"}]') as first_report \gset
select pg_temp.ok((:'first_report'::jsonb) = '{"ok": true, "items": 2, "errors": 4, "overflow": 0}'::jsonb, 'the answer counts what was taken: ' || :'first_report');
select pg_temp.ok((one.app_error_report('b2b', '[{"route": "/leads/[id]", "name": "TypeError", "n": 2, "message": "a second message", "digest": "7654321", "kind": "action"}]')
                   ->> 'errors')::int = 2, 'a second report of the same pair is taken');
select pg_temp.ok((one.app_error_report('b2c', '[{"route": "/leads/[id]", "name": "TypeError", "n": 7}]') ->> 'ok')::boolean, 'another app reports the same pair');
select pg_temp.ok(pg_temp.err($q$select * from one.app_errors$q$) like '42501:%', 'the service role cannot read the table itself');
reset role;
select pg_temp.ok((select count(*) = 3 from one.app_errors), 'one row per app, bucket, route and error name');
select pg_temp.ok((select n = 5 and sample_message = 'cannot read owner of undefined' and sample_digest = '1234567' and sample_kind = 'render'
                          and bucket = date_bin(interval '5 minutes', now(), timestamptz '2000-01-01 00:00:00+00') and bucket <= now() and bucket > now() - interval '5 minutes'
                     from one.app_errors where app = 'b2b' and route = '/leads/[id]' and error_name = 'TypeError'),
                  'the counts add up in the 5-minute bucket the database chose, and the first sample is kept');
select pg_temp.ok((select n = 7 and sample_message is null and sample_digest is null from one.app_errors where app = 'b2c'), 'each app has its own rows');

-- 3. What is refused -------------------------------------------------------------------------------------------------------------
set role service_role;
select pg_temp.ok(pg_temp.err($q$select one.app_error_report('nowhere', '[{"route": "/x", "name": "Error", "n": 1}]')$q$) = '22023: one.app_error_report: unknown app',
                  'an app that is not in one.apps is refused');
select pg_temp.ok(pg_temp.err($q$select one.app_error_report(null, '[]')$q$) like '22023:%', 'and no app at all');
select pg_temp.ok(pg_temp.err($q$select one.app_error_report('b2b', '{"route": "/x"}')$q$) like '22023:%', 'items that are not an array are refused');
select pg_temp.ok(pg_temp.err($q$select one.app_error_report('b2b', null)$q$) like '22023:%', 'and no items');
select pg_temp.ok(pg_temp.err(format('select one.app_error_report(%L, %L)', 'b2b',
                    (select jsonb_agg(jsonb_build_object('route', '/r' || g, 'name', 'Error', 'n', 1)) from generate_series(1, 51) g)))
                  like '22023: one.app_error_report: the items are a JSON array of at most 50 objects', 'a batch of 51 is refused whole');
select pg_temp.ok((one.app_error_report('b2b', '[]') ->> 'errors')::int = 0, 'an empty batch is fine');
select pg_temp.ok((one.app_error_report('b2b', '[1, "x", null, [2]]')) = '{"ok": true, "items": 0, "errors": 0, "overflow": 0}'::jsonb,
                  'items that are not objects are skipped');
reset role;
select pg_temp.ok((select count(*) = 3 from one.app_errors), 'none of that stored a row');

-- 4. No contact is stored, whatever field it came in ----------------------------------------------------------------------------
delete from one.app_errors;
set role service_role;
select one.app_error_report('influencer', $j$[
  {"route": "/m/[handle]?email=asha@example.com&phone=9876543210", "name": "TypeError", "n": 1,
   "message": "lead 98765 43210 (asha.rao@example.com) has no owner; call +91 98765-43210", "digest": "9876543210", "kind": "render"},
  {"route": "/u/9876543210/edit", "name": "asha@example.com", "n": 1, "message": "asha@example.com", "digest": "asha@example.com", "kind": "asha@example.com"},
  {"route": "/creators/[id]#9876543210", "name": "Err9876543210", "n": 1, "message": "user ９８７６５４３２１０ failed", "digest": "+919876543210", "kind": "RENDER 9876543210"},
  {"route": "", "name": "", "n": 1, "message": "   ", "digest": "", "kind": ""}
]$j$);
reset role;
select pg_temp.ok((select count(*) = 4 from one.app_errors where app = 'influencer'), 'four rows were stored');
select pg_temp.ok(not exists (select 1 from one.app_errors e
                               where one.has_contact(concat_ws(' | ', e.route, e.error_name, e.sample_kind, e.sample_message, e.sample_digest)) is not null
                                  or to_jsonb(e)::text ~ '9876543210|98765 43210|98765-43210|asha|example\.com|９８７６'),
                  'no row holds an email or a phone: ' || (select string_agg(to_jsonb(e)::text, ' ') from one.app_errors e));
select pg_temp.ok(exists (select 1 from one.app_errors where route = '/m/[handle]' and error_name = 'TypeError' and sample_digest is null
                             and sample_message = 'lead [phone] ([email]) has no owner; call [phone]' and sample_kind = 'render'),
                  'the query string is dropped, the message keeps its sentence with the contacts replaced, a phone-shaped digest is not kept');
select pg_temp.ok(exists (select 1 from one.app_errors where route = '/u/[phone]/edit' and error_name = 'Error' and sample_kind is null
                             and sample_message = '[email]' and sample_digest is null),
                  'a phone in the path is replaced; a name, kind or digest that is not one is not kept');
select pg_temp.ok(exists (select 1 from one.app_errors where route = '/creators/[id]' and error_name = 'Error' and sample_digest is null and sample_kind is null),
                  'the fragment is dropped, and a name with a phone in it becomes Error');
select pg_temp.ok(exists (select 1 from one.app_errors where route = '(unknown)' and error_name = 'Error' and sample_message is null), 'empty fields get their defaults');

-- 5. Caps -----------------------------------------------------------------------------------------------------------------------------
delete from one.app_errors;
set role service_role;
select one.app_error_report('one', jsonb_build_array(
  jsonb_build_object('route', '/' || repeat('a', 500), 'name', repeat('N', 61), 'n', 999999999, 'message', repeat('word ', 400), 'digest', repeat('d', 65), 'kind', repeat('k', 21)),
  jsonb_build_object('route', '/zero', 'name', 'Error', 'n', 0),
  jsonb_build_object('route', '/negative', 'name', 'Error', 'n', -5),
  jsonb_build_object('route', '/text', 'name', 'Error', 'n', 'many'),
  jsonb_build_object('route', '/fraction', 'name', 'Error', 'n', 2.9),
  jsonb_build_object('route', '/missing', 'name', 'Error')));
reset role;
select pg_temp.ok((select n = 10000 and length(route) = 200 and error_name = 'Error' and length(sample_message) = 200 and sample_digest is null and sample_kind is null
                     from one.app_errors where route like '/aaa%'),
                  'a count is capped at 10 000 and every text at its length; a name, digest or kind that is too long is not kept');
select pg_temp.ok((select bool_and(n = 1) from one.app_errors where route in ('/zero', '/negative', '/text', '/missing'))
                  and (select n = 2 from one.app_errors where route = '/fraction'), 'a count that is not a whole number of at least 1 is made one');
-- The hourly row cap: 300 rows of one app in an hour, then only the bucket's overflow row grows.
delete from one.app_errors;
insert into one.app_errors (app, bucket, route, error_name, n)
select 'one', date_bin(interval '5 minutes', now(), timestamptz '2000-01-01 00:00:00+00') - interval '10 minutes', '/filler/' || g, 'Error', 1 from generate_series(1, 299) g;
set role service_role;
select one.app_error_report('one', '[{"route": "/a", "name": "Error", "n": 2}, {"route": "/b", "name": "Error", "n": 3}, {"route": "/c", "name": "Error", "n": 4},
                                     {"route": "/a", "name": "Error", "n": 5}]') as capped \gset
select pg_temp.ok((:'capped'::jsonb) = '{"ok": true, "items": 4, "errors": 14, "overflow": 7}'::jsonb, 'past the cap the counts are still taken: ' || :'capped');
select pg_temp.ok((one.app_error_report('one', '[{"route": "/d", "name": "Error", "n": 10000}, {"route": "/a", "name": "Error", "n": 1}]') ->> 'overflow')::int = 10000,
                  'and again, while a row that exists still grows');
select pg_temp.ok((one.app_error_report('b2b', '[{"route": "/a", "name": "Error", "n": 1}]') ->> 'overflow')::int = 0, 'another app has its own cap');
select pg_temp.ok((one.app_error_report('one', '[{"route": "(overflow)", "name": "(overflow)", "n": 21}]') ->> 'errors')::int = 21,
                  'what an app''s own buffer could not hold apart is taken as the overflow pair');
reset role;
select pg_temp.ok((select count(*) = 301 from one.app_errors where app = 'one'), '300 rows and the one overflow row');
select pg_temp.ok((select n = 8 from one.app_errors where app = 'one' and route = '/a') and not exists (select 1 from one.app_errors where app = 'one' and route in ('/b', '/c', '/d'))
                  and (select n = 10028 and sample_message is null from one.app_errors where app = 'one' and route = '(overflow)' and error_name = '(overflow)'),
                  'the first new pair took the last row, the others went to the overflow row of the bucket');
update one.app_errors set bucket = bucket - interval '2 hours' where app = 'one' and route like '/filler/%';
set role service_role;
select pg_temp.ok((one.app_error_report('one', '[{"route": "/b", "name": "Error", "n": 1}]') ->> 'overflow')::int = 0, 'an hour later there is room again');
reset role;

-- 6. The check: fails above the threshold, resolves by itself under it ------------------------------------------------------------
delete from one.app_errors;
delete from one.results where check_id like '%-ERR';
delete from one.check_state where check_id like '%-ERR';
select one.run_check_safe('B2B-ERR');
select pg_temp.ok((select last_status = 'ok' from one.check_state where check_id = 'B2B-ERR'), 'no reports reads as no errors');
set role service_role;
select one.app_error_report('b2b', '[{"route": "/leads/[id]", "name": "TypeError", "n": 12}, {"route": "/api/leads", "name": "Error", "n": 8}]');
reset role;
select one.run_check_safe('B2B-ERR');
select pg_temp.ok((select last_status = 'ok' from one.check_state where check_id = 'B2B-ERR') and not exists (select 1 from one.incidents where check_id = 'B2B-ERR'),
                  '20 errors in 15 minutes is at the limit, not above it');
set role service_role;
select one.app_error_report('b2b', '[{"route": "/leads/[id]", "name": "TypeError", "n": 1}]');
select one.app_error_report('b2c', '[{"route": "/s/inbox", "name": "Error", "n": 500}]');
reset role;
select one.run_check_safe('B2B-ERR');
select pg_temp.ok((select severity = 'P2' and app = 'b2b' from one.incidents where check_id = 'B2B-ERR' and resolved_at is null),
                  '21 opens a P2 incident: ' || coalesce((select value::text from one.results where check_id = 'B2B-ERR' order by id desc limit 1), 'no result'));
select pg_temp.ok((select (value ->> 'errors_15m')::int = 21 and (value ->> 'limit')::int = 20 and (value ->> 'pairs')::int = 2
                          and value -> 'top' = '[{"n": 13, "error": "TypeError", "route": "/leads/[id]"}, {"n": 8, "error": "Error", "route": "/api/leads"}]'::jsonb
                     from one.results where check_id = 'B2B-ERR' order by id desc limit 1),
                  'the value holds the count, the limit and the busiest pairs, and nothing else of the rows');
select one.run_check_safe('INF-ERR');
select one.run_check_safe('B2C-ERR');
select pg_temp.ok((select last_status = 'ok' from one.check_state where check_id = 'INF-ERR') and not exists (select 1 from one.incidents where check_id = 'INF-ERR')
                  and exists (select 1 from one.incidents where check_id = 'B2C-ERR' and resolved_at is null),
                  'each check reads its own app');
-- The limit is the owner's setting: raised, the same count passes; the buckets age out of the window by themselves.
select one.settings_put('thresholds', (select value from one.settings where key = 'thresholds') || '{"app_errors_15m": 30}', 'test', '0041 test: a higher limit');
select one.run_check_safe('B2B-ERR');
select pg_temp.ok((select last_status = 'ok' from one.check_state where check_id = 'B2B-ERR') and exists (select 1 from one.incidents where check_id = 'B2B-ERR' and resolved_at is null),
                  'under the raised limit the check passes; one good reading does not resolve the incident');
select one.run_check_safe('B2B-ERR');
select pg_temp.ok(not exists (select 1 from one.incidents where check_id = 'B2B-ERR' and resolved_at is null)
                  and (select count(*) = 1 from one.incidents where check_id = 'B2B-ERR' and resolved_at is not null), 'the second resolves it, without a person');
select one.settings_put('thresholds', (select value from one.settings where key = 'thresholds') || '{"app_errors_15m": 20}', 'test', '0041 test: the seeded limit');
select one.run_check_safe('B2B-ERR');
select pg_temp.ok(exists (select 1 from one.incidents where check_id = 'B2B-ERR' and resolved_at is null), 'back at 20 it fails again');
update one.app_errors set bucket = bucket - interval '15 minutes' where app = 'b2b';
select one.run_check_safe('B2B-ERR'); select one.run_check_safe('B2B-ERR');
select pg_temp.ok(not exists (select 1 from one.incidents where check_id = 'B2B-ERR' and resolved_at is null)
                  and (select (value ->> 'errors_15m')::int = 0 from one.results where check_id = 'B2B-ERR' order by id desc limit 1),
                  'buckets that started 15 minutes ago or more no longer count, and the incident resolves');
-- Without the key (a thresholds row a person changed before 0041) the check reads its default.
select one.settings_put('thresholds', (select value - 'app_errors_15m' from one.settings where key = 'thresholds'), 'test', '0041 test: no key');
update one.app_errors set bucket = bucket + interval '15 minutes' where app = 'b2b';
select one.run_check_safe('B2B-ERR');
select pg_temp.ok((select (value ->> 'limit')::int = 20 and (value ->> 'errors_15m')::int = 21 from one.results where check_id = 'B2B-ERR' order by id desc limit 1),
                  'a thresholds setting without the key means 20');
select one.settings_put('thresholds', (select value from one.settings where key = 'thresholds') || '{"app_errors_15m": 20}', 'test', '0041 test: the seeded limit again');

-- 7. What the page reads -------------------------------------------------------------------------------------------------------------
delete from one.app_errors;
set role service_role;
select one.app_error_report('b2b', '[{"route": "/r1", "name": "Error", "n": 6, "message": "six", "digest": "d-6", "kind": "render"},
  {"route": "/r2", "name": "Error", "n": 5}, {"route": "/r3", "name": "Error", "n": 4}, {"route": "/r4", "name": "Error", "n": 3},
  {"route": "/r5", "name": "Error", "n": 2}, {"route": "/r6", "name": "Error", "n": 1}]');
reset role;
insert into one.app_errors (app, bucket, route, error_name, n, first_seen, last_seen, sample_message)
values ('b2b', date_bin(interval '5 minutes', now() - interval '3 hours', timestamptz '2000-01-01 00:00:00+00'), '/r6', 'Error', 9, now() - interval '3 hours', now() - interval '3 hours', 'earlier'),
       ('b2b', date_bin(interval '5 minutes', now() - interval '30 hours', timestamptz '2000-01-01 00:00:00+00'), '/old', 'Error', 100, now() - interval '30 hours', now() - interval '30 hours', null);
set role anon;
select pg_temp.ok(pg_temp.err($q$select one.ui_app_errors('b2b')$q$) like '42501:%', 'anon cannot read the summary');
reset role;
set role authenticated;
select pg_temp.as_stranger();
select pg_temp.ok(pg_temp.err($q$select one.ui_app_errors('b2b')$q$) = '42501: not allowed', 'nor a signed-in subject who is not a user of Eduwit One');
select pg_temp.as_engineer();
select one.ui_app_errors('b2b') as page \gset
select pg_temp.ok((:'page'::jsonb ->> 'total')::int = 30 and (:'page'::jsonb ->> 'pairs')::int = 6 and (:'page'::jsonb ->> 'hours')::int = 24
                  and (:'page'::jsonb ->> 'last_15m')::int = 21 and (:'page'::jsonb ->> 'limit_15m')::int = 20 and (:'page'::jsonb ->> 'last_seen') is not null,
                  'an engineer reads the last 24 hours: ' || :'page');
select pg_temp.ok(jsonb_array_length(:'page'::jsonb -> 'top') = 5
                  and :'page'::jsonb #>> '{top,0,route}' = '/r6' and (:'page'::jsonb #>> '{top,0,n}')::int = 10 and :'page'::jsonb #>> '{top,0,message}' = 'earlier'
                  and :'page'::jsonb #> '{top,1}' @> '{"route": "/r1", "error": "Error", "n": 6, "message": "six", "digest": "d-6", "kind": "render"}'::jsonb
                  and not (:'page'::jsonb -> 'top') @> '[{"route": "/r5"}]'::jsonb,
                  'the five busiest pairs, summed over their buckets, each with one sample');
select pg_temp.ok((one.ui_app_errors('b2b', 48) ->> 'total')::int = 130 and (one.ui_app_errors('b2b', 100000) ->> 'hours')::int = 168
                  and (one.ui_app_errors('b2b', 0) ->> 'hours')::int = 1, 'the window is between an hour and a week');
select pg_temp.ok((one.ui_app_errors('witty')) @> '{"total": 0, "pairs": 0, "top": [], "last_seen": null}'::jsonb, 'an app with no reports reads as empty');
select pg_temp.ok(pg_temp.err($q$select one.ui_app_errors('nowhere')$q$) = 'P0002: unknown app', 'an unknown app is not found');
select pg_temp.as_owner();
select pg_temp.ok((one.ui_app_errors('b2b') ->> 'total')::int = 30, 'the owner reads it too');
reset role;

-- 8. Retention -------------------------------------------------------------------------------------------------------------------------
insert into one.app_errors (app, bucket, route, error_name, n)
values ('b2b', now() - interval '31 days', '/gone', 'Error', 1), ('b2b', now() - interval '29 days', '/kept', 'Error', 1);
select one.retention() as pruned \gset
select pg_temp.ok((:'pruned'::jsonb ->> 'app_errors')::int = 1 and :'pruned'::jsonb ? 'results' and :'pruned'::jsonb ? 'chat_threads',
                  'the nightly retention reports what it pruned, with the rest: ' || :'pruned');
select pg_temp.ok(not exists (select 1 from one.app_errors where route = '/gone') and exists (select 1 from one.app_errors where route = '/kept'),
                  'counts older than 30 days are gone, younger ones stay');
select one.settings_put('retention', (select value from one.settings where key = 'retention') || '{"app_errors_days": 7}', 'test', '0041 test: a shorter time');
select pg_temp.ok((one.retention() ->> 'app_errors')::int = 1, 'retention.app_errors_days changes how long they are kept');
select pg_temp.ok(not exists (select 1 from one.app_errors where route = '/kept') and exists (select 1 from one.app_errors where route = '/old'),
                  'the 29-day-old count is gone under 7 days, yesterday''s stays');

-- 9. The rollback file removes all of it; the migration applies again over it ------------------------------------------------------
-- The thresholds row as production may have it: the seed's, without the key, so that 0041 adds it and its rollback takes it back.
update one.settings set value = value - 'app_errors_15m', actor = 'seed' where key = 'thresholds';
select set_config('one.history_writer', 'on', true);
update one.settings_versions v set value = v.value - 'app_errors_15m', actor = 'seed'
 where v.key = 'thresholds' and v.version = (select s.version from one.settings s where s.key = 'thresholds');
select version as thresholds_version from one.settings where key = 'thresholds' \gset
set role postgres;
select pg_temp.ok(pg_temp.err($q$do $d$ begin
    if exists (select 1 from one.incidents where check_id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR'))
       and coalesce(current_setting('one.rollback_discards_history', true), '') <> 'on' then raise exception 'would refuse' using errcode = '55000'; end if; end $d$$q$)
                  = '55000: would refuse', 'fixture: incidents of the checks exist, so the rollback asks before discarding them');
select set_config('one.rollback_discards_history', 'on', true);
\ir ../../migrations/0041_app_errors.rollback.sql
reset role;
select pg_temp.ok(to_regclass('one.app_errors') is null and to_regprocedure('one.app_error_report(text,jsonb)') is null
                  and to_regprocedure('one.ui_app_errors(text,integer)') is null and to_regprocedure('one.app_error_text(text,integer)') is null,
                  'after the rollback the table and the three functions are gone');
select pg_temp.ok(not exists (select 1 from one.checks where id like '%-ERR') and not exists (select 1 from one.incidents where check_id like '%-ERR')
                  and not exists (select 1 from one.results where check_id like '%-ERR')
                  and not exists (select 1 from one.api_grants where fn in ('one.app_error_report(text,jsonb)', 'one.ui_app_errors(text,integer)')),
                  'and the five checks with their state, results, incidents and the two grants');
select pg_temp.ok(not (one.retention() ? 'app_errors') and one.retention() ? 'chat_threads', 'one.retention is 0029''s again');
select pg_temp.ok((select not (value ? 'app_errors_15m') and version = :thresholds_version from one.settings where key = 'thresholds'),
                  'a thresholds row 0041 did not seed is left as it was');
set role postgres;
\ir ../../migrations/0041_app_errors.sql
reset role;
select pg_temp.ok((select (value ->> 'app_errors_15m')::int = 20 and actor = 'seed' and version = :thresholds_version + 1 from one.settings where key = 'thresholds')
                  and exists (select 1 from one.settings_versions where key = 'thresholds' and version = :thresholds_version + 1 and reason like 'D-141 (0041)%'),
                  'applied again, 0041 adds the threshold as a seed version when the row is still the seed''s');
select pg_temp.ok((select count(*) = 5 from one.checks where id like '%-ERR') and to_regclass('one.app_errors') is not null
                  and has_function_privilege('service_role', 'one.app_error_report(text,jsonb)', 'execute')
                  and not has_function_privilege('authenticated', 'one.app_error_report(text,jsonb)', 'execute')
                  and has_function_privilege('authenticated', 'one.ui_app_errors(text,integer)', 'execute')
                  and not has_function_privilege('anon', 'one.ui_app_errors(text,integer)', 'execute'),
                  'and the table, the checks and the grants are back');
set role service_role;
select pg_temp.ok((one.app_error_report('b2b', '[{"route": "/again", "name": "Error", "n": 1}]') ->> 'errors')::int = 1, 'the service role reports again');
reset role;
-- Rolled back once more, the seed version is taken back; a person's later edit would stay.
set role postgres;
select set_config('one.rollback_discards_history', 'on', true);
\ir ../../migrations/0041_app_errors.rollback.sql
reset role;
select pg_temp.ok((select not (value ? 'app_errors_15m') and actor = 'seed' from one.settings where key = 'thresholds'),
                  'the rollback takes the seeded threshold back');
select one.settings_put('thresholds', (select value from one.settings where key = 'thresholds') || '{"lead_visible_min": 3}', 'connect@eduwit.in', '0041 test: a person''s edit');
set role postgres;
\ir ../../migrations/0041_app_errors.sql
reset role;
select pg_temp.ok((select not (value ? 'app_errors_15m') and actor = 'connect@eduwit.in' from one.settings where key = 'thresholds')
                  and (select count(*) = 5 from one.checks where id like '%-ERR'),
                  'a thresholds row a person changed is left as it is; the checks then read their default');

rollback;
