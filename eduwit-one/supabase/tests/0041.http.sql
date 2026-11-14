-- Test for 0041_app_errors.sql (D-141): the apps report their server-error counts to Eduwit One. Plain SQL for an
-- executor that takes one SQL text (Supabase's Management API through scripts/db/with-api.ts, the SQL editor): no psql
-- meta-commands.
--
-- How it runs
--   The whole test is ONE statement (the DO block below) that always ends with
--   "raise exception 'TESTRESULT total=… failed=… …'": that error is the result, and it undoes everything the test
--   wrote, whichever way the script is sent. begin/rollback around it say the same thing twice on purpose.
--   Expected: ERROR: TESTRESULT total=N failed=0 all passed
--   It tests the objects that are in the database when it runs. To try 0041 without keeping it, send the migration's
--   text and then this file as one payload in one transaction ("begin;", 0041_app_errors.sql, this file): the final
--   error rolls the migration back with the rest. (A second "begin" inside a transaction is only a warning.)
--
-- Who the calls run as
--   The reports run as role service_role, as each app's service client does, and are tried as anon and as
--   authenticated. The page's read runs as the pages' calls do: role authenticated with request.jwt.claims holding a
--   subject and a session id, set for the transaction only (PostgREST's form; supabase/tests/0040.http.sql does the
--   same). So the test makes two people of its own, an owner and an engineer (auth.users, auth.sessions, one.users,
--   one.session_checks; addresses one-0041-test-…@eduwit.in, random ids), and a third subject with no rows at all (a
--   stranger). Nothing is forged past one.ui_require(), and all of it is rolled back.
--
-- Data
--   Its rows go into an app that never reports and holds no count (integrity, catalogue, platform or witty, the first
--   that is empty), every route starting with /__one-0041-test__/. One check of its own, ONE-T0041-ERR, with ONE-ERR's
--   statement pointed at that app. No existing check, setting or count is changed. one.retention() is called once: what
--   it prunes besides the test rows is what tonight's run would prune, and it is rolled back with the rest. Each step
--   runs in its own guarded block: an unexpected error becomes a failed check with the error text, not an aborted
--   script. Results are gathered in a variable and written to a temporary table at the end, which the final message is
--   read from.

begin;

do $test$
declare
  v_me       constant text := current_user;
  v_owner    constant uuid := gen_random_uuid();
  v_owner_s  constant uuid := gen_random_uuid();
  v_eng      constant uuid := gen_random_uuid();
  v_eng_s    constant uuid := gen_random_uuid();
  c_check    constant text := 'ONE-T0041-ERR';
  c_p        constant text := '/__one-0041-test__';
  v_bucket   constant timestamptz := date_bin(interval '5 minutes', now(), timestamptz '2000-01-01 00:00:00+00');
  v_app      text;
  v_limit    integer;
  v_setup    boolean := false;
  v_cases    jsonb;
  r          jsonb := '[]'::jsonb; -- the results: [{name, ok, detail}]
  c          jsonb;
  v_state    text;
  v_text     text;
  v_out      jsonb;
  v_ok       boolean;
  v_n        bigint;
  v_total    int;
  v_failed   int;
  v_msg      text;
begin
  -- ---------------------------------------------------------------- set-up
  begin
    if to_regclass('one.app_errors') is null or to_regprocedure('one.app_error_report(text,jsonb)') is null
       or to_regprocedure('one.ui_app_errors(text,integer)') is null then
      raise exception '0041 is not in this database (one.app_errors, one.app_error_report, one.ui_app_errors)';
    end if;
    select a.key into v_app
      from one.apps a
     where a.key in ('integrity', 'catalogue', 'platform', 'witty') and not exists (select 1 from one.app_errors e where e.app = a.key)
     order by array_position(array['integrity', 'catalogue', 'platform', 'witty'], a.key)
     limit 1;
    if v_app is null then
      raise exception 'no app without counts to hold the test rows (integrity, catalogue, platform, witty)';
    end if;
    v_limit := coalesce(one.threshold('app_errors_15m'), 20)::int;
    insert into auth.users (id, email, email_confirmed_at)
    values (v_owner, 'one-0041-test-owner@eduwit.in', now()), (v_eng, 'one-0041-test-engineer@eduwit.in', now());
    insert into auth.sessions (id, user_id) values (v_owner_s, v_owner), (v_eng_s, v_eng);
    insert into one.users (user_id, email, role) values (v_owner, 'one-0041-test-owner@eduwit.in', 'owner'), (v_eng, 'one-0041-test-engineer@eduwit.in', 'engineer');
    insert into one.session_checks (session_id, user_id, method) values (v_owner_s, v_owner, 'email_code'), (v_eng_s, v_eng, 'email_code');
    insert into one.checks (id, app, title, kind, sql, severity, cadence_s, open_after, resolve_after, created_by, updated_by)
    select c_check, v_app, '0041 test: server errors of the test app', 'sql', replace(k.sql, 'x.app = ''one''', format('x.app = %L', v_app)),
           'P2', 300, 1, 2, '0041.http.sql', '0041.http.sql'
      from one.checks k where k.id = 'ONE-ERR';
    if not found then
      raise exception 'the check ONE-ERR is not seeded';
    end if;
    -- The calls below run as other roles: prove here that this session may take them and come back.
    set local role service_role;
    set local role anon;
    set local role authenticated;
    execute format('set local role %I', v_me);
    v_setup := true;
  exception when others then
    r := r || jsonb_build_object('name', 'set-up: an empty app, two test people, a test check and the roles', 'ok', false, 'detail', sqlstate || ': ' || sqlerrm);
  end;

  -- ---------------------------------------------------------------- what the migration made
  begin
    r := r || jsonb_build_object('name', 'five checks are seeded: P2, every 5 minutes, the website''s off until it reports',
      'ok', (select count(*) = 5 and bool_and(k.severity = 'P2' and k.kind = 'sql')
                    and bool_and(k.enabled or k.updated_by <> 'seed') filter (where k.id <> 'WEB-ERR')
               from one.checks k where k.id in ('B2B-ERR', 'B2C-ERR', 'INF-ERR', 'ONE-ERR', 'WEB-ERR')),
      'detail', (select string_agg(k.id || ':' || k.severity || ':' || k.enabled, ' ' order by k.id) from one.checks k where k.id like '%-ERR'));
    r := r || jsonb_build_object('name', 'the service role alone executes the writer; signed-in people execute the reader; anon neither',
      'ok', has_function_privilege('service_role', 'one.app_error_report(text,jsonb)', 'execute')
            and not has_function_privilege('authenticated', 'one.app_error_report(text,jsonb)', 'execute')
            and not has_function_privilege('anon', 'one.app_error_report(text,jsonb)', 'execute')
            and has_function_privilege('authenticated', 'one.ui_app_errors(text,integer)', 'execute')
            and not has_function_privilege('anon', 'one.ui_app_errors(text,integer)', 'execute')
            and not has_function_privilege('service_role', 'one.app_error_text(text,integer)', 'execute'),
      'detail', null);
    r := r || jsonb_build_object('name', 'the table is closed to every API role, with row level security on',
      'ok', (select k.relrowsecurity from pg_class k where k.oid = 'one.app_errors'::regclass)
            and not has_table_privilege('service_role', 'one.app_errors', 'select, insert, update, delete')
            and not has_table_privilege('authenticated', 'one.app_errors', 'select')
            and not has_table_privilege('anon', 'one.app_errors', 'select'),
      'detail', null);
    r := r || jsonb_build_object('name', 'both doors are SECURITY DEFINER with an empty search_path',
      'ok', (select bool_and(p.prosecdef and p.proconfig @> array['search_path=""']) from pg_proc p
              where p.oid in ('one.app_error_report(text,jsonb)'::regprocedure, 'one.ui_app_errors(text,integer)'::regprocedure)),
      'detail', null);
    r := r || jsonb_build_object('name', 'the thresholds stay the owner''s to change (0039)', 'ok', one.setting_owner_only('thresholds'), 'detail', null);
  exception when others then
    r := r || jsonb_build_object('name', 'reading what the migration made', 'ok', false, 'detail', sqlstate || ': ' || sqlerrm);
  end;

  if v_setup then
    -- ---------------------------------------------------------------- the calls, each as its role
    -- expect is 'ok' or the SQLSTATE; msg is the exact message, or its beginning when it ends with %; out is what an
    -- answer must contain.
    v_cases := jsonb_build_array(
      jsonb_build_object('who', 'anon', 'sql', format('select one.app_error_report(%L, %L::jsonb)', v_app, '[{"route": "' || c_p || '/anon", "name": "Error", "n": 1}]'),
                         'expect', '42501', 'name', 'anon cannot report (42501)'),
      jsonb_build_object('who', 'engineer', 'sql', format('select one.app_error_report(%L, %L::jsonb)', v_app, '[{"route": "' || c_p || '/eng", "name": "Error", "n": 1}]'),
                         'expect', '42501', 'name', 'a signed-in engineer cannot report (42501)'),
      jsonb_build_object('who', 'owner', 'sql', format('select one.app_error_report(%L, %L::jsonb)', v_app, '[{"route": "' || c_p || '/owner", "name": "Error", "n": 1}]'),
                         'expect', '42501', 'name', 'nor the owner: no page can write a count (42501)'),
      jsonb_build_object('who', 'service', 'sql', format('select one.app_error_report(%L, %L::jsonb)', 'one-0041-no-such-app', '[{"route": "/x", "name": "Error", "n": 1}]'),
                         'expect', '22023', 'msg', 'one.app_error_report: unknown app', 'name', 'an app that is not in one.apps is refused (22023)'),
      jsonb_build_object('who', 'service', 'sql', format('select one.app_error_report(%L, %L::jsonb)', v_app, '{"route": "/x"}'),
                         'expect', '22023', 'msg', 'one.app_error_report: the items are%', 'name', 'items that are not an array are refused (22023)'),
      jsonb_build_object('who', 'service', 'sql', format('select one.app_error_report(%L, %L::jsonb)', v_app,
                           (select jsonb_agg(jsonb_build_object('route', c_p || '/many/' || g, 'name', 'Error', 'n', 1)) from generate_series(1, 51) g)),
                         'expect', '22023', 'msg', 'one.app_error_report: the items are a JSON array of at most 50 objects', 'name', 'a batch of 51 is refused whole (22023)'),
      jsonb_build_object('who', 'service', 'sql', format('select one.app_error_report(%L, %L::jsonb)', v_app, '[1, "x", null]'),
                         'expect', 'ok', 'out', '{"ok": true, "items": 0, "errors": 0, "overflow": 0}'::jsonb, 'name', 'items that are not objects are skipped'),
      jsonb_build_object('who', 'service', 'sql', format('select one.app_error_report(%L, %L::jsonb)', v_app,
                           '[{"route": "' || c_p || '/leads/[id]", "name": "TypeError", "n": 3, "message": "cannot read owner of undefined", "digest": "1234567", "kind": "render"},'
                           || ' {"route": "' || c_p || '/api/health", "name": "Error", "n": 1, "kind": "route"}]'),
                         'expect', 'ok', 'out', '{"ok": true, "items": 2, "errors": 4, "overflow": 0}'::jsonb, 'name', 'the service role reports two pairs'),
      jsonb_build_object('who', 'service', 'sql', format('select one.app_error_report(%L, %L::jsonb)', v_app,
                           '[{"route": "' || c_p || '/leads/[id]", "name": "TypeError", "n": 2, "message": "a second message", "digest": "7654321", "kind": "action"}]'),
                         'expect', 'ok', 'out', '{"errors": 2}'::jsonb, 'name', 'and the first pair again'),
      jsonb_build_object('who', 'service', 'sql', 'select count(*) from one.app_errors', 'expect', '42501', 'name', 'the service role cannot read the table itself (42501)'),
      jsonb_build_object('who', 'service', 'sql', format('select one.app_error_report(%L, %L::jsonb)', v_app, jsonb_build_array(
                           jsonb_build_object('route', c_p || '/m/[handle]?email=asha@example.com&phone=9876543210', 'name', 'RangeError', 'n', 1,
                                              'message', 'lead 98765 43210 (asha.rao@example.com) has no owner; call +91 98765-43210', 'digest', '9876543210', 'kind', 'render'),
                           jsonb_build_object('route', c_p || '/u/9876543210/edit', 'name', 'asha@example.com', 'n', 1, 'message', 'asha@example.com',
                                              'digest', 'asha@example.com', 'kind', 'asha@example.com'),
                           jsonb_build_object('route', c_p || '/' || repeat('a', 500), 'name', repeat('N', 61), 'n', 999999999, 'message', repeat('word ', 400),
                                              'digest', repeat('d', 65), 'kind', repeat('k', 21)),
                           jsonb_build_object('route', c_p || '/zero', 'name', 'Error', 'n', 0),
                           jsonb_build_object('route', c_p || '/text', 'name', 'Error', 'n', 'many'))),
                         'expect', 'ok', 'out', '{"ok": true, "items": 5, "overflow": 0}'::jsonb, 'name', 'a report with contacts, oversized fields and bad counts is taken'),
      jsonb_build_object('who', 'anon', 'sql', format('select one.ui_app_errors(%L)', v_app), 'expect', '42501', 'name', 'anon cannot read the page''s summary (42501)'),
      jsonb_build_object('who', 'stranger', 'sql', format('select one.ui_app_errors(%L)', v_app), 'expect', '42501', 'msg', 'not allowed',
                         'name', 'a signed-in subject who is not a user of Eduwit One cannot read it (42501, not allowed)'),
      jsonb_build_object('who', 'engineer', 'sql', 'select one.ui_app_errors(''one-0041-no-such-app'')', 'expect', 'P0002', 'msg', 'unknown app',
                         'name', 'an unknown app is not found (P0002)'),
      jsonb_build_object('who', 'engineer', 'sql', format('select one.ui_app_errors(%L)', v_app), 'expect', 'ok',
                         'out', jsonb_build_object('app', v_app, 'hours', 24, 'pairs', 7, 'total', 10010), 'name', 'an engineer reads the last 24 hours of the app'),
      jsonb_build_object('who', 'owner', 'sql', format('select one.ui_app_errors(%L, 100000)', v_app), 'expect', 'ok',
                         'out', jsonb_build_object('hours', 168, 'limit_15m', v_limit), 'name', 'the owner too, for a week at most'));
    for c in select e.item from jsonb_array_elements(v_cases) with ordinality e(item, ord) order by e.ord loop
      v_state := 'ok'; v_text := null; v_out := null;
      begin
        if c ->> 'who' in ('owner', 'engineer', 'stranger') then
          perform set_config('request.jwt.claims', case c ->> 'who'
              when 'owner' then jsonb_build_object('sub', v_owner, 'session_id', v_owner_s, 'role', 'authenticated', 'aud', 'authenticated')
              when 'engineer' then jsonb_build_object('sub', v_eng, 'session_id', v_eng_s, 'role', 'authenticated', 'aud', 'authenticated')
              else jsonb_build_object('sub', gen_random_uuid(), 'session_id', gen_random_uuid(), 'role', 'authenticated', 'aud', 'authenticated')
            end::text, true);
          set local role authenticated;
        elsif c ->> 'who' = 'anon' then
          perform set_config('request.jwt.claims', '{"role": "anon"}', true);
          set local role anon;
        else
          perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
          set local role service_role;
        end if;
        execute 'select to_jsonb(q) from (' || (c ->> 'sql') || ') q' into v_out;
        execute format('set local role %I', v_me);
      exception when others then
        v_state := sqlstate; v_text := sqlerrm;
      end;
      execute format('set local role %I', v_me);
      perform set_config('request.jwt.claims', '', true);
      v_ok := v_state = c ->> 'expect'
              and (c ->> 'msg' is null or case when right(c ->> 'msg', 1) = '%' then v_text like (c ->> 'msg') else v_text = c ->> 'msg' end)
              and (c -> 'out' is null or (select bool_or(o.value @> (c -> 'out')) from jsonb_each(v_out) o));
      r := r || jsonb_build_object('name', c ->> 'name', 'ok', v_ok,
                                   'detail', case when not v_ok then coalesce(v_state || ': ' || coalesce(v_text, v_out::text), 'no answer') end);
    end loop;

    -- ---------------------------------------------------------------- what the calls left behind
    begin
      r := r || jsonb_build_object('name', 'the refused calls stored nothing',
        'ok', not exists (select 1 from one.app_errors e where e.route in (c_p || '/anon', c_p || '/eng', c_p || '/owner', '/x') or e.route like c_p || '/many/%'),
        'detail', null);
      r := r || jsonb_build_object('name', 'the counts of one pair add up in the 5-minute bucket the database chose, and the first sample is kept',
        'ok', (select e.n = 5 and e.sample_message = 'cannot read owner of undefined' and e.sample_digest = '1234567' and e.sample_kind = 'render' and e.bucket = v_bucket
                 from one.app_errors e where e.app = v_app and e.route = c_p || '/leads/[id]' and e.error_name = 'TypeError'),
        'detail', (select to_jsonb(e)::text from one.app_errors e where e.app = v_app and e.route = c_p || '/leads/[id]'));
      r := r || jsonb_build_object('name', 'no stored row holds an email or a phone, whatever field it came in',
        'ok', not exists (select 1 from one.app_errors e where e.app = v_app
                             and (one.has_contact(concat_ws(' | ', e.route, e.error_name, e.sample_kind, e.sample_message, e.sample_digest)) is not null
                                  or to_jsonb(e)::text ~ '9876543210|98765 43210|98765-43210|asha|example\.com')),
        'detail', (select string_agg(to_jsonb(e)::text, ' ') from one.app_errors e where e.app = v_app and to_jsonb(e)::text ~ '9876543210|asha|example'));
      r := r || jsonb_build_object('name', 'the query string is dropped, the message keeps its sentence with the contacts replaced, a phone-shaped digest is not kept',
        'ok', exists (select 1 from one.app_errors e where e.app = v_app and e.route = c_p || '/m/[handle]' and e.error_name = 'RangeError' and e.sample_digest is null
                         and e.sample_message = 'lead [phone] ([email]) has no owner; call [phone]'),
        'detail', (select to_jsonb(e)::text from one.app_errors e where e.app = v_app and e.error_name = 'RangeError'));
      r := r || jsonb_build_object('name', 'a phone in the path is replaced; a name, kind or digest that is not one is not kept',
        'ok', exists (select 1 from one.app_errors e where e.app = v_app and e.route = c_p || '/u/[phone]/edit' and e.error_name = 'Error' and e.sample_kind is null
                         and e.sample_message = '[email]' and e.sample_digest is null),
        'detail', null);
      r := r || jsonb_build_object('name', 'a count is capped at 10 000 and every text at its length',
        'ok', (select e.n = 10000 and length(e.route) = 200 and e.error_name = 'Error' and length(e.sample_message) = 200 and e.sample_digest is null and e.sample_kind is null
                 from one.app_errors e where e.app = v_app and e.route like c_p || '/aaa%'),
        'detail', null);
      r := r || jsonb_build_object('name', 'a count that is not a number of at least 1 is made one',
        'ok', (select count(*) = 2 and bool_and(e.n = 1) from one.app_errors e where e.app = v_app and e.route in (c_p || '/zero', c_p || '/text')),
        'detail', null);
    exception when others then
      r := r || jsonb_build_object('name', 'reading what the calls left behind', 'ok', false, 'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- ---------------------------------------------------------------- the hourly row cap
    begin
      select count(*) into v_n from one.app_errors e where e.app = v_app and e.bucket > now() - interval '1 hour';
      insert into one.app_errors (app, bucket, route, error_name, n)
      select v_app, v_bucket - interval '10 minutes', c_p || '/filler/' || g, 'Error', 1 from generate_series(1, 299 - v_n::int) g;
      set local role service_role;
      v_out := one.app_error_report(v_app, jsonb_build_array(
        jsonb_build_object('route', c_p || '/cap/a', 'name', 'Error', 'n', 2), jsonb_build_object('route', c_p || '/cap/b', 'name', 'Error', 'n', 3),
        jsonb_build_object('route', c_p || '/cap/c', 'name', 'Error', 'n', 4), jsonb_build_object('route', c_p || '/cap/a', 'name', 'Error', 'n', 5)));
      execute format('set local role %I', v_me);
      r := r || jsonb_build_object('name', 'past 300 rows of an app in an hour the counts are still taken, into the bucket''s overflow row',
        'ok', v_out = '{"ok": true, "items": 4, "errors": 14, "overflow": 7}'::jsonb
              and (select count(*) = 301 from one.app_errors e where e.app = v_app and e.bucket > now() - interval '1 hour')
              and (select e.n = 7 from one.app_errors e where e.app = v_app and e.bucket = v_bucket and e.route = '(overflow)' and e.error_name = '(overflow)')
              and (select e.n = 7 from one.app_errors e where e.app = v_app and e.route = c_p || '/cap/a')
              and not exists (select 1 from one.app_errors e where e.app = v_app and e.route in (c_p || '/cap/b', c_p || '/cap/c')),
        'detail', v_out::text);
    exception when others then
      execute format('set local role %I', v_me);
      r := r || jsonb_build_object('name', 'the hourly row cap', 'ok', false, 'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- ---------------------------------------------------------------- the check
    begin
      delete from one.app_errors where app = v_app;
      perform one.run_check_safe(c_check);
      r := r || jsonb_build_object('name', 'the check passes when nothing was reported',
        'ok', (select s.last_status = 'ok' from one.check_state s where s.check_id = c_check), 'detail', null);
      set local role service_role;
      perform one.app_error_report(v_app, jsonb_build_array(jsonb_build_object('route', c_p || '/check', 'name', 'Error', 'n', v_limit)));
      execute format('set local role %I', v_me);
      perform one.run_check_safe(c_check);
      r := r || jsonb_build_object('name', 'errors at the limit do not open an incident',
        'ok', (select s.last_status = 'ok' from one.check_state s where s.check_id = c_check) and not exists (select 1 from one.incidents i where i.check_id = c_check),
        'detail', null);
      set local role service_role;
      perform one.app_error_report(v_app, jsonb_build_array(jsonb_build_object('route', c_p || '/check', 'name', 'Error', 'n', 1)));
      execute format('set local role %I', v_me);
      perform one.run_check_safe(c_check);
      r := r || jsonb_build_object('name', 'one more opens a P2 incident, and the value holds the count and the limit',
        'ok', (select i.severity = 'P2' from one.incidents i where i.check_id = c_check and i.resolved_at is null)
              and (select (x.value ->> 'errors_15m')::int = v_limit + 1 and (x.value ->> 'limit')::int = v_limit and x.value #>> '{top,0,route}' = c_p || '/check'
                     from one.results x where x.check_id = c_check order by x.id desc limit 1),
        'detail', (select x.value::text from one.results x where x.check_id = c_check order by x.id desc limit 1));
      update one.app_errors set bucket = bucket - interval '15 minutes' where app = v_app;
      perform one.run_check_safe(c_check);
      v_ok := exists (select 1 from one.incidents i where i.check_id = c_check and i.resolved_at is null);
      perform one.run_check_safe(c_check);
      r := r || jsonb_build_object('name', 'when the errors leave the 15 minutes, the incident resolves by itself after two good readings',
        'ok', v_ok and not exists (select 1 from one.incidents i where i.check_id = c_check and i.resolved_at is null)
              and (select count(*) = 1 from one.incidents i where i.check_id = c_check and i.resolved_at is not null),
        'detail', null);
    exception when others then
      execute format('set local role %I', v_me);
      r := r || jsonb_build_object('name', 'the check', 'ok', false, 'detail', sqlstate || ': ' || sqlerrm);
    end;

    -- ---------------------------------------------------------------- retention
    begin
      insert into one.app_errors (app, bucket, route, error_name, n)
      values (v_app, now() - interval '3651 days', c_p || '/gone', 'Error', 1), (v_app, now() - interval '12 hours', c_p || '/kept', 'Error', 1);
      v_out := one.retention();
      r := r || jsonb_build_object('name', 'the nightly retention prunes old counts and keeps recent ones',
        'ok', (v_out ->> 'app_errors')::int >= 1 and not exists (select 1 from one.app_errors e where e.app = v_app and e.route = c_p || '/gone')
              and exists (select 1 from one.app_errors e where e.app = v_app and e.route = c_p || '/kept'),
        'detail', v_out::text);
    exception when others then
      r := r || jsonb_build_object('name', 'retention', 'ok', false, 'detail', sqlstate || ': ' || sqlerrm);
    end;
  end if;

  -- ---------------------------------------------------------------- result
  create temp table one_0041_test_results (n int, name text, ok boolean, detail text) on commit drop;
  insert into one_0041_test_results (n, name, ok, detail)
  select e.ord, e.item ->> 'name', coalesce((e.item ->> 'ok')::boolean, false), e.item ->> 'detail'
    from jsonb_array_elements(r) with ordinality e(item, ord);
  select count(*), count(*) filter (where not ok),
         coalesce(string_agg(format('[%s] %s%s', n, name, coalesce(' (' || left(detail, 300) || ')', '')), ' | ' order by n) filter (where not ok), 'all passed')
    into v_total, v_failed, v_msg
    from one_0041_test_results;
  raise exception 'TESTRESULT total=% failed=% %', v_total, v_failed, v_msg;
end
$test$;

rollback;
