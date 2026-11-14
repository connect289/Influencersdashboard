-- Test for 0040_owner_mutes_p1.sql (D-139): muting a top-priority alarm is the owner's. Plain SQL for an executor that
-- takes one SQL text (Supabase's Management API through scripts/db/with-api.ts, the SQL editor): no psql meta-commands.
--
-- How it runs
--   The whole test is ONE statement (the DO block below) that always ends with
--   "raise exception 'TESTRESULT total=… failed=… …'": that error is the result, and it undoes everything the test
--   wrote, whichever way the script is sent. begin/rollback around it say the same thing twice on purpose.
--   Expected: ERROR: TESTRESULT total=N failed=0 all passed
--   It tests the function that is in the database when it runs. To try 0040 without keeping it, send the migration's
--   text and then this file as one payload in one transaction ("begin;", 0040_owner_mutes_p1.sql, this file): the final
--   error rolls the migration back with the rest. (A second "begin" inside a transaction is only a warning.)
--
-- Who the calls run as
--   As the pages' calls do: role authenticated with request.jwt.claims holding a subject and a session id, set for
--   the transaction only (PostgREST's form; e2e/shim.ts and supabase/tests/local do the same). one.ui_require() then
--   decides as it does for a person: the subject must be an active row of one.users, the session must exist in
--   auth.sessions and be checked in one.session_checks. So the test makes two people of its own, an owner and an
--   engineer (auth.users, auth.sessions, one.users, one.session_checks; addresses one-0040-test-…@eduwit.in, random
--   ids), and a third subject with no rows at all (a stranger). Nothing is forged past those checks, and all of it is
--   rolled back.
--
-- Data
--   Three checks of its own (ONE-T0040-P3, ONE-T0040-P1 and ONE-T0040-P1OFF, the last switched off), placed in an app
--   that has no P1 check (catalogue or catalogue_engine as seeded), so the app rule is tested both ways on one app:
--   before the P1 rows exist an engineer mutes the app, after it only the owner does. If every app has a P1 check,
--   that one comparison is reported as skipped and the rows go into the app with the fewest open incidents. No
--   existing check, setting or mute is changed. An app-level mute marks the app's open incidents as muted, as it
--   always does: for the length of this transaction only, on the one app chosen. Each call runs in its own guarded
--   block: an unexpected error becomes a failed check with the error text, not an aborted script. Results are
--   gathered in a variable while the checks run and written to a temporary table at the end, which the final message
--   is read from.

begin;

do $test$
declare
  v_me        constant text := current_user;
  v_owner     constant uuid := gen_random_uuid();
  v_owner_s   constant uuid := gen_random_uuid();
  v_eng       constant uuid := gen_random_uuid();
  v_eng_s     constant uuid := gen_random_uuid();
  v_owner_em  constant text := 'one-0040-test-owner@eduwit.in';
  v_eng_em    constant text := 'one-0040-test-engineer@eduwit.in';
  c_p3        constant text := 'ONE-T0040-P3';
  c_p1        constant text := 'ONE-T0040-P1';
  c_p1off     constant text := 'ONE-T0040-P1OFF';
  c_sql       constant text := $q$select true as ok, '{}'::jsonb as value$q$;
  v_refusal   constant text := 'only the owner can mute a top-priority alarm: ';
  v_app       text;                 -- the app the test rows live in
  v_app_clean boolean := false;     -- it had no P1 check before the test rows
  v_setup     boolean := false;
  v_cases     jsonb;
  v_ids       jsonb := '{}'::jsonb; -- mute ids by case key
  r           jsonb := '[]'::jsonb; -- the results: [{name, ok, detail}]
  c           jsonb;
  v_phase     int;
  v_state     text;
  v_text      text;
  v_out       jsonb;
  v_ok        boolean;
  v_n         int;
  v_audit0    bigint;
  v_total     int;
  v_failed    int;
  v_msg       text;
begin
  -- ---------------------------------------------------------------- set-up
  begin
    if to_regprocedure('one.ui_mute(text,text,integer,text,text)') is null then
      raise exception 'one.ui_mute(text,text,integer,text,text) is not in this database';
    end if;
    select a.key, true into v_app, v_app_clean
      from one.apps a
     where not exists (select 1 from one.checks k where k.app = a.key and k.severity = 'P1')
     order by (select count(*) from one.incidents i where i.app = a.key and i.resolved_at is null), a.key
     limit 1;
    if v_app is null then
      select a.key, false into v_app, v_app_clean
        from one.apps a
       order by (select count(*) from one.incidents i where i.app = a.key and i.resolved_at is null), a.key
       limit 1;
    end if;
    insert into auth.users (id, email, email_confirmed_at) values (v_owner, v_owner_em, now()), (v_eng, v_eng_em, now());
    insert into auth.sessions (id, user_id) values (v_owner_s, v_owner), (v_eng_s, v_eng);
    insert into one.users (user_id, email, role) values (v_owner, v_owner_em, 'owner'), (v_eng, v_eng_em, 'engineer');
    insert into one.session_checks (session_id, user_id, method) values (v_owner_s, v_owner, 'email_code'), (v_eng_s, v_eng, 'email_code');
    insert into one.checks (id, app, title, kind, sql, severity, cadence_s, created_by, updated_by)
    values (c_p3, v_app, '0040 test: a P3 check', 'sql', c_sql, 'P3', 3600, '0040.http.sql', '0040.http.sql');
    select count(*) into v_audit0 from one.audit where action = 'mute';
    -- The calls below run as role authenticated: prove here that this session may take that role and come back.
    set local role authenticated;
    execute format('set local role %I', v_me);
    v_setup := true;
  exception when others then
    r := r || jsonb_build_object('name', 'set-up: two test people, their sessions, a test check and the role authenticated', 'ok', false,
                                 'detail', sqlstate || ': ' || sqlerrm);
  end;

  if v_setup then
    -- phase 1: before the app holds a P1 test check; phase 2: after; phase 3: after the owner's mute was ended.
    -- expect is 'ok' or the SQLSTATE; msg is the exact message, or its beginning when it ends with %.
    v_cases := jsonb_build_array(
      jsonb_build_object('key', 'e-app-clean', 'phase', 1, 'who', 'engineer', 'type', 'app', 'target', v_app, 'minutes', 30, 'expect', 'ok',
                         'skip', not v_app_clean, 'name', 'an engineer mutes an app that has no P1 check'),
      jsonb_build_object('key', 'e-p3', 'phase', 1, 'who', 'engineer', 'type', 'check', 'target', c_p3, 'minutes', 60, 'expect', 'ok',
                         'name', 'an engineer mutes a check that is not a P1'),
      jsonb_build_object('key', 'e-p3-short', 'phase', 1, 'who', 'engineer', 'type', 'check', 'target', c_p3, 'minutes', 0, 'expect', '22023',
                         'msg', 'one.mute: a duration%', 'name', 'a duration under a minute is refused as before (22023)'),
      jsonb_build_object('key', 'e-p3-long', 'phase', 1, 'who', 'engineer', 'type', 'check', 'target', c_p3, 'minutes', 10081, 'expect', '22023',
                         'msg', 'one.mute: a duration%', 'name', 'a duration over 7 days is refused as before (22023)'),
      jsonb_build_object('key', 'e-p3-noreason', 'phase', 1, 'who', 'engineer', 'type', 'check', 'target', c_p3, 'minutes', 60, 'reason', '',
                         'expect', '22023', 'msg', 'give a reason', 'name', 'a mute without a reason is refused as before (22023)'),
      jsonb_build_object('key', 'e-unknown', 'phase', 1, 'who', 'engineer', 'type', 'check', 'target', 'ONE-T0040-NONE', 'minutes', 60,
                         'expect', '22023', 'msg', 'one.mute: unknown check%', 'name', 'an unknown check is refused as unknown (22023)'),
      jsonb_build_object('key', 's-p3', 'phase', 1, 'who', 'stranger', 'type', 'check', 'target', c_p3, 'minutes', 60, 'expect', '42501',
                         'msg', 'not allowed', 'name', 'a signed-in subject who is not a user of Eduwit One is refused as before (42501, not allowed)'),
      jsonb_build_object('key', 'e-p1', 'phase', 2, 'who', 'engineer', 'type', 'check', 'target', c_p1, 'minutes', 60, 'expect', '42501',
                         'msg', v_refusal || 'check ' || c_p1 || ' is P1', 'name', 'an engineer is refused on a P1 check, with the message the app shows'),
      jsonb_build_object('key', 'e-p1-minute', 'phase', 2, 'who', 'engineer', 'type', 'check', 'target', c_p1, 'minutes', 1, 'expect', '42501',
                         'msg', v_refusal || '%', 'name', 'not for one minute either'),
      jsonb_build_object('key', 'e-p1off', 'phase', 2, 'who', 'engineer', 'type', 'check', 'target', c_p1off, 'minutes', 60, 'expect', '42501',
                         'msg', v_refusal || 'check ' || c_p1off || ' is P1', 'name', 'a P1 check that is switched off is still the owner''s to mute'),
      jsonb_build_object('key', 'e-app-p1', 'phase', 2, 'who', 'engineer', 'type', 'app', 'target', v_app, 'minutes', 30, 'expect', '42501',
                         'msg', v_refusal || 'app ' || v_app || ' has P1 checks', 'name', 'an engineer is refused on an app that has a P1 check'),
      jsonb_build_object('key', 'e-p1-badform', 'phase', 2, 'who', 'engineer', 'type', 'check', 'target', c_p1, 'minutes', 0, 'reason', '',
                         'expect', '42501', 'msg', v_refusal || '%', 'name', 'the refusal does not depend on the rest of the form'),
      jsonb_build_object('key', 'e-p3-again', 'phase', 2, 'who', 'engineer', 'type', 'check', 'target', c_p3, 'minutes', 15, 'expect', 'ok',
                         'name', 'an engineer still mutes the P3 check of an app that has P1 checks'),
      jsonb_build_object('key', 'o-p1', 'phase', 2, 'who', 'owner', 'type', 'check', 'target', c_p1, 'minutes', 60, 'expect', 'ok',
                         'name', 'the owner mutes a P1 check'),
      jsonb_build_object('key', 'o-app-p1', 'phase', 2, 'who', 'owner', 'type', 'app', 'target', v_app, 'minutes', 45, 'expect', 'ok',
                         'name', 'the owner mutes an app that has a P1 check'),
      jsonb_build_object('key', 'o-p3', 'phase', 2, 'who', 'owner', 'type', 'check', 'target', c_p3, 'minutes', 15, 'expect', 'ok',
                         'name', 'the owner mutes any other check, as before'),
      jsonb_build_object('key', 'e-unmute', 'phase', 2, 'who', 'engineer', 'fn', 'unmute', 'of', 'o-p1', 'expect', 'ok',
                         'name', 'an engineer ends the owner''s mute of a P1 check (ending a mute is unchanged)'),
      jsonb_build_object('key', 'e-p1-again', 'phase', 3, 'who', 'engineer', 'type', 'check', 'target', c_p1, 'minutes', 60, 'expect', '42501',
                         'msg', v_refusal || 'check ' || c_p1 || ' is P1', 'name', 'and cannot start it again when it has ended'));

    for v_phase in 1..3 loop
      if v_phase = 2 then
        begin
          insert into one.checks (id, app, title, kind, sql, severity, cadence_s, enabled, disabled_reason, created_by, updated_by)
          values (c_p1, v_app, '0040 test: a P1 check', 'sql', c_sql, 'P1', 3600, true, null, '0040.http.sql', '0040.http.sql'),
                 (c_p1off, v_app, '0040 test: a P1 check that is off', 'sql', c_sql, 'P1', 3600, false, 'builder:test-0040', '0040.http.sql', '0040.http.sql');
        exception when others then
          r := r || jsonb_build_object('name', 'set-up: the two P1 test checks', 'ok', false, 'detail', sqlstate || ': ' || sqlerrm);
        end;
      end if;
      for c in select e.item from jsonb_array_elements(v_cases) with ordinality e(item, ord)
                where (e.item ->> 'phase')::int = v_phase order by e.ord
      loop
        if coalesce((c ->> 'skip')::boolean, false) then
          r := r || jsonb_build_object('name', c ->> 'name', 'ok', true, 'skipped', true,
                                       'detail', 'skipped: every app here has a P1 check');
          continue;
        end if;
        v_state := 'ok'; v_text := null; v_out := null;
        begin
          perform set_config('request.jwt.claims', case c ->> 'who'
              when 'owner' then jsonb_build_object('sub', v_owner, 'session_id', v_owner_s, 'role', 'authenticated', 'aud', 'authenticated')
              when 'engineer' then jsonb_build_object('sub', v_eng, 'session_id', v_eng_s, 'role', 'authenticated', 'aud', 'authenticated')
              else jsonb_build_object('sub', gen_random_uuid(), 'session_id', gen_random_uuid(), 'role', 'authenticated', 'aud', 'authenticated')
            end::text, true);
          set local role authenticated;
          if c ->> 'fn' = 'unmute' then
            v_out := one.ui_unmute((v_ids ->> (c ->> 'of'))::bigint, 'req-0040-http-' || (c ->> 'key'));
          else
            v_out := one.ui_mute(c ->> 'type', c ->> 'target', (c ->> 'minutes')::int,
                                 coalesce(c ->> 'reason', '0040 http test: ' || (c ->> 'key')), 'req-0040-http-' || (c ->> 'key'));
          end if;
          execute format('set local role %I', v_me);
        exception when others then
          -- The role and whatever the call wrote go back with this block.
          v_state := sqlstate; v_text := sqlerrm;
        end;
        perform set_config('request.jwt.claims', '', true);
        if v_out ? 'mute_id' then
          v_ids := v_ids || jsonb_build_object(c ->> 'key', v_out -> 'mute_id');
        end if;
        v_ok := v_state = c ->> 'expect'
                and (c ->> 'msg' is null or v_text = c ->> 'msg'
                     or (right(c ->> 'msg', 1) = '%' and starts_with(v_text, left(c ->> 'msg', -1))))
                and (v_state <> 'ok' or coalesce((v_out ->> 'ok')::boolean, false));
        r := r || jsonb_build_object('name', c ->> 'name', 'ok', v_ok,
                                     'detail', case when v_ok then null else 'got ' || v_state || coalesce(': ' || v_text, '') end);
      end loop;
    end loop;

    -- ---------------------------------------------------------------- what the calls left behind
    begin
      select count(*) into v_n from one.mutes where reason like '0040 http test: %';
      r := r || jsonb_build_object('name', 'only the allowed calls wrote a mute', 'ok', v_n = (select count(*) from jsonb_object_keys(v_ids)),
                                   'detail', v_n || ' mutes, ' || (select count(*) from jsonb_object_keys(v_ids)) || ' allowed calls');
      select count(*) into v_n from one.audit where action = 'mute' and request_id like 'req-0040-http-%';
      r := r || jsonb_build_object('name', 'one audit row per mute, none for a refused call',
        'ok', v_n = (select count(*) from jsonb_object_keys(v_ids))
              and (select count(*) from one.audit where action = 'mute') = v_audit0 + v_n
              and not exists (select 1 from one.audit where request_id in ('req-0040-http-e-p1', 'req-0040-http-e-p1off', 'req-0040-http-e-app-p1',
                                                                          'req-0040-http-e-p1-again', 'req-0040-http-s-p3')),
        'detail', v_n || ' audit rows');
      r := r || jsonb_build_object('name', 'the engineer''s mute is audited with the actor from the session and the request id',
        'ok', (select count(*) = 1 from one.audit where action = 'mute' and target = 'check:' || c_p3 and actor = v_eng_em
                  and request_id = 'req-0040-http-e-p3' and (after ->> 'minutes')::int = 60 and (after ->> 'mute_id')::bigint = (v_ids ->> 'e-p3')::bigint),
        'detail', null);
      r := r || jsonb_build_object('name', 'the owner''s mutes are audited under the owner''s name',
        'ok', (select count(*) = 3 from one.audit where action = 'mute' and actor = v_owner_em
                  and request_id in ('req-0040-http-o-p1', 'req-0040-http-o-app-p1', 'req-0040-http-o-p3')),
        'detail', null);
      r := r || jsonb_build_object('name', 'the mute rows carry who, for how long and why',
        'ok', (select m.created_by = v_eng_em and m.ends_at - m.starts_at = interval '60 minutes' and m.target_type = 'check' and m.target = c_p3
                 from one.mutes m where m.id = (v_ids ->> 'e-p3')::bigint)
              and (select m.created_by = v_owner_em and m.target_type = 'app' and m.target = v_app from one.mutes m where m.id = (v_ids ->> 'o-app-p1')::bigint),
        'detail', null);
      r := r || jsonb_build_object('name', 'the owner''s app mute holds the app''s P1 check; the ended mute was ended, with its audit row',
        'ok', one.is_muted(c_p1off, v_app)
              and (select m.ends_at <= now() + interval '1 second' from one.mutes m where m.id = (v_ids ->> 'o-p1')::bigint)
              and exists (select 1 from one.audit where action = 'unmute' and target = 'mute:' || (v_ids ->> 'o-p1') and actor = v_eng_em),
        'detail', null);
      r := r || jsonb_build_object('name', 'one.ui_mute keeps its one signature: signed-in people may call it, anon may not, and one.mute is not an API function',
        'ok', has_function_privilege('authenticated', 'one.ui_mute(text,text,integer,text,text)', 'execute')
              and not has_function_privilege('anon', 'one.ui_mute(text,text,integer,text,text)', 'execute')
              and (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'one' and p.proname = 'ui_mute')
              and not has_function_privilege('authenticated', 'one.mute(text,text,integer,text,text,text)', 'execute')
              and not has_function_privilege('anon', 'one.mute(text,text,integer,text,text,text)', 'execute'),
        'detail', null);
      r := r || jsonb_build_object('name', 'the function is security definer with an empty search_path, owned as the other page functions are',
        'ok', (select p.prosecdef and p.proconfig @> array['search_path=""']
                      and p.proowner = (select q.proowner from pg_proc q where q.oid = 'one.ui_unmute(bigint,text)'::regprocedure)
                 from pg_proc p where p.oid = 'one.ui_mute(text,text,integer,text,text)'::regprocedure),
        'detail', null);
    exception when others then
      r := r || jsonb_build_object('name', 'reading what the calls left behind', 'ok', false, 'detail', sqlstate || ': ' || sqlerrm);
    end;
  end if;

  -- ---------------------------------------------------------------- result
  create temp table one_0040_test_results (n int, name text, ok boolean, skipped boolean, detail text) on commit drop;
  insert into one_0040_test_results (n, name, ok, skipped, detail)
  select e.ord, e.item ->> 'name', coalesce((e.item ->> 'ok')::boolean, false), coalesce((e.item ->> 'skipped')::boolean, false), e.item ->> 'detail'
    from jsonb_array_elements(r) with ordinality e(item, ord);
  select count(*), count(*) filter (where not ok),
         coalesce(string_agg(format('[%s] %s%s', n, name, coalesce(' (' || left(detail, 300) || ')', '')), ' | ' order by n) filter (where not ok),
                  'all passed')
         || coalesce(' (' || count(*) filter (where skipped) || ' skipped: ' || string_agg(name, '; ' order by n) filter (where skipped) || ')', '')
    into v_total, v_failed, v_msg
    from one_0040_test_results;
  raise exception 'TESTRESULT total=% failed=% %', v_total, v_failed, v_msg;
end
$test$;

rollback;
