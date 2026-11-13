-- Test for w2_optout.sql (Witty opt-out fixes H3 and H4, 13 Nov 2026). Run it after the migration.
--
-- How it runs
--   One transaction, nothing kept. The whole test is ONE statement (the DO block below) that always ends with
--   "raise exception 'TESTRESULT total=… failed=… …'": that error is the result, and it also undoes everything the
--   test wrote, whichever way the script is sent (as one script, or statement by statement). begin/rollback around
--   it say the same thing twice on purpose. No psql meta-commands.
--   Expected: ERROR: TESTRESULT total=N failed=0 all passed
--   (Identity sequences of student_leads and touchpoints move forward by a few numbers; sequences never roll back.)
--
-- Data
--   Only numbers in the reserved test range 910000xxxxxx (910000997701 to 910000997707), which every app treats as
--   test traffic; leads are created through lead_intake with is_test = true. Each check runs in its own guarded block:
--   an unexpected error becomes a failed check with the error text, not an aborted script. Results are gathered in a
--   variable while the checks run (a variable survives a guarded block that fails) and written to a temporary table
--   at the end, which the final message is read from.
--
-- What cannot be tested head-on, and what is done instead (H4)
--   public.w2_nurture_due never returns a test number (not w2_is_test(phone)) and returns nothing outside
--   09:00-20:00 IST, so calling it with test numbers proves nothing. Three checks replace the direct call:
--     1. the new predicate on its own, against the harness leads;
--     2. the deployed function, called with p_limit = 0: it runs (inside the time window the whole statement is
--        planned and the Spark list is read) but can select and lease no conversation;
--     3. a throw-away copy of the DEPLOYED text (pg_get_functiondef) created in pg_temp with exactly three
--        substitutions (the name, the time-of-day guard, and "not w2_is_test(phone)" replaced by "phone is one of the
--        harness numbers"), run end to end. The copy can only ever touch the harness numbers. If any substitution
--        does not match exactly once, the check fails instead of testing something else.
--
-- CRM ownership (H3) is set the way public.w2_crm_owned checks it: the harness lead gets destination_type = 'partner'
-- with no b2b.allocations row (its third rule, the legacy allocation), which needs no user, partner or allocation row.

begin;

do $test$
declare
  p_stop   constant text := '910000997701';   -- CRM-owned, replies "Stop."
  p_hello  constant text := '910000997702';   -- CRM-owned, sends an ordinary message
  p_batch  constant text := '910000997703';   -- CRM-owned, a long message and then "STOP" claimed together
  p_n_out  constant text := '910000997704';   -- follow-up due, shared lead opted out
  p_n_ok   constant text := '910000997705';   -- follow-up due, shared lead not opted out
  p_n_supp constant text := '910000997706';   -- follow-up due, number on Spark's suppression list
  p_n_lift constant text := '910000997707';   -- follow-up due, Spark suppression lifted
  phones   constant text[] := array['910000997701', '910000997702', '910000997703', '910000997704', '910000997705',
                                    '910000997706', '910000997707'];
  r        jsonb := '[]'::jsonb;              -- the results: [{name, ok, detail}]
  x        record;
  v        jsonb;
  v_lead   bigint;
  v_conv   public.w2_conversations;
  v_sl     public.student_leads;
  v_n      int;
  v_ok     boolean;
  v_def    text;
  v_sub    text[];
  v_spark  boolean := false;
  v_phones text[];
  v_total  int;
  v_failed int;
  v_msg    text;
begin
  -- ---------------------------------------------------------------- 0. a clean start for the harness numbers
  begin
    for x in select unnest(phones) as phone loop
      perform public.w2_test_reset(x.phone);
    end loop;
    r := r || jsonb_build_object('name', 'setup: harness numbers reset (w2_test_reset)', 'ok', true);
  exception when others then
    r := r || jsonb_build_object('name', 'setup: harness numbers reset (w2_test_reset)', 'ok', false, 'detail', sqlerrm);
  end;

  -- ---------------------------------------------------------------- 1. the matcher
  for x in
    select * from (values
      ('STOP', true), ('Stop.', true), ('please stop', true), ('band karo', true), ('बंद करो', true), ('मत भेजो!', true),
      ('hello', false), ('क्या कॉलेज बंद है', false), ('', false),
      ('when do classes stop for summer vacation this year please', false),
      -- beyond the brief: the same rules, more shapes
      ('STOP!!', true), ('  stop  ', true), ('Stop messaging me', true), ('unsubscribe', true), ('UNSUB', true),
      ('Bandh karo yaar', true), ('mat bhejo', true), ('No more messages', true), ('रोको', true), ('STOP 🙏', true),
      (E'st​op', true), (E'Hi\nStop', true),
      ('बंद', false), ('nonstop', false), ('stopped', false), ('ok', false), ('🙏', false), ('fees?', false),
      ('I will stop by the campus office on Monday morning', false)
    ) t(msg, want)
  loop
    begin
      v_ok := public.w2_is_stop_message(x.msg);
      r := r || jsonb_build_object('name', format('matcher: %L is %s', x.msg, case when x.want then 'a stop message' else 'not a stop message' end),
                                   'ok', v_ok is not distinct from x.want, 'detail', format('got %s', v_ok));
    exception when others then
      r := r || jsonb_build_object('name', format('matcher: %L', x.msg), 'ok', false, 'detail', sqlerrm);
    end;
  end loop;
  begin
    r := r || jsonb_build_object('name', 'matcher: null is not a stop message', 'ok', public.w2_is_stop_message(null) is false);
  exception when others then
    r := r || jsonb_build_object('name', 'matcher: null is not a stop message', 'ok', false, 'detail', sqlerrm);
  end;
  begin
    r := r || jsonb_build_object('name', 'matcher: anon and authenticated cannot execute it',
      'ok', not has_function_privilege('anon', 'public.w2_is_stop_message(text)', 'execute')
        and not has_function_privilege('authenticated', 'public.w2_is_stop_message(text)', 'execute'));
  exception when others then
    r := r || jsonb_build_object('name', 'matcher: anon and authenticated cannot execute it', 'ok', false, 'detail', sqlerrm);
  end;

  -- ---------------------------------------------------------------- 2. H3: STOP from a CRM-owned lead
  -- 2a. three test leads, CRM-owned the way w2_crm_owned checks it (legacy partner allocation)
  begin
    for x in select unnest(array[p_stop, p_hello, p_batch]) as phone loop
      v := public.lead_intake(jsonb_build_object('source_system', 'witty', 'event_type', 'chat.turn', 'phone', x.phone,
                                                 'is_test', true, 'idempotency_key', x.phone || ':w2-optout-test:create',
                                                 'lead', '{}'::jsonb));
      update public.student_leads set destination_type = 'partner' where id = (v->>'lead_id')::bigint and is_test;
    end loop;
    -- the conversation of the STOP number already has a follow-up planned, so the test can see it being cancelled
    insert into public.w2_conversations (phone, nurture_next_at) values (p_stop, now() + interval '3 hours');
    r := r || jsonb_build_object('name', 'H3 setup: the three harness leads are CRM-owned (w2_crm_owned) and not opted out',
      'ok', public.w2_crm_owned(p_stop) and public.w2_crm_owned(p_hello) and public.w2_crm_owned(p_batch)
            and not exists (select 1 from public.student_leads l where l.whatsapp_number = any(array[p_stop, p_hello, p_batch]) and l.is_opted_out)
            and (select count(*) from public.student_leads l where l.whatsapp_number = any(array[p_stop, p_hello, p_batch]) and l.is_test) = 3);
  exception when others then
    r := r || jsonb_build_object('name', 'H3 setup: the three harness leads are CRM-owned (w2_crm_owned) and not opted out', 'ok', false, 'detail', sqlerrm);
  end;

  -- 2b. "Stop." from a CRM-owned lead
  begin
    insert into public.w2_inbox (message_id, phone, content) values ('w2-optout-test-stop-1', p_stop, 'Stop.');
    v := public.w2_try_claim(p_stop, 'w2-optout-test', 45);
    select * into v_conv from public.w2_conversations where phone = p_stop;
    v_sl := public.crm_find_lead(p_stop);
    r := r || jsonb_build_object('name', 'H3 stop: w2_try_claim returns acquired and crm_paused',
      'ok', (v->>'acquired')::boolean and (v->>'crm_paused')::boolean, 'detail', left(v::text, 200));
    r := r || jsonb_build_object('name', 'H3 stop: still no reply (messages is empty, nothing but the crm_paused keys returned)',
      'ok', v->'messages' = '[]'::jsonb and not (v ? 'access') and not (v ? 'prompts'));
    r := r || jsonb_build_object('name', 'H3 stop: w2_conversations.opted_out is true', 'ok', v_conv.opted_out);
    r := r || jsonb_build_object('name', 'H3 stop: the planned follow-up is cancelled (nurture_next_at is null)', 'ok', v_conv.nurture_next_at is null);
    r := r || jsonb_build_object('name', 'H3 stop: state.opted_out is true (so w2_commit_turn keeps the flag)',
      'ok', (v_conv.state->>'opted_out')::boolean, 'detail', v_conv.state::text);
    r := r || jsonb_build_object('name', 'H3 stop: the returned conversation shows opted_out', 'ok', (v->'conversation'->>'opted_out')::boolean);
    r := r || jsonb_build_object('name', 'H3 stop: the shared lead is opted out (is_opted_out, opted_out_at)',
      'ok', v_sl.is_opted_out and v_sl.opted_out_at is not null);
    r := r || jsonb_build_object('name', 'H3 stop: one lead.opted_out touchpoint from witty with the day key',
      'ok', (select count(*) from public.touchpoints t where t.lead_id = v_sl.id and t.event_type = 'lead.opted_out'
                and t.source_system = 'witty' and t.idempotency_key like p_stop || ':optout:%') = 1);
    r := r || jsonb_build_object('name', 'H3 stop: the message is marked processed and the chat.reenquiry touchpoint is still written',
      'ok', (select processed_at is not null from public.w2_inbox where message_id = 'w2-optout-test-stop-1')
            and exists (select 1 from public.touchpoints t where t.lead_id = v_sl.id and t.event_type = 'chat.reenquiry'));
    r := r || jsonb_build_object('name', 'H3 stop: the lead is still CRM-owned and not reassigned', 'ok', public.w2_crm_owned(p_stop) and v_sl.destination_type = 'partner');
  exception when others then
    r := r || jsonb_build_object('name', 'H3 stop: w2_try_claim on "Stop." from a CRM-owned lead', 'ok', false, 'detail', sqlerrm);
  end;

  -- 2c. a second STOP the same day: no error, still opted out, still one touchpoint (idempotency key)
  begin
    insert into public.w2_inbox (message_id, phone, content) values ('w2-optout-test-stop-2', p_stop, 'STOP');
    v := public.w2_try_claim(p_stop, 'w2-optout-test', 45);
    v_sl := public.crm_find_lead(p_stop);
    r := r || jsonb_build_object('name', 'H3 stop again: crm_paused, still opted out, still one lead.opted_out touchpoint',
      'ok', (v->>'crm_paused')::boolean and v_sl.is_opted_out
            and (select opted_out from public.w2_conversations where phone = p_stop)
            and (select count(*) from public.touchpoints t where t.lead_id = v_sl.id and t.event_type = 'lead.opted_out') = 1);
  exception when others then
    r := r || jsonb_build_object('name', 'H3 stop again: crm_paused, still opted out, still one lead.opted_out touchpoint', 'ok', false, 'detail', sqlerrm);
  end;

  -- 2d. an ordinary message from a CRM-owned lead does not opt out
  begin
    insert into public.w2_inbox (message_id, phone, content) values ('w2-optout-test-hello-1', p_hello, 'Hello, what are the fees for the MBA?');
    v := public.w2_try_claim(p_hello, 'w2-optout-test', 45);
    select * into v_conv from public.w2_conversations where phone = p_hello;
    v_sl := public.crm_find_lead(p_hello);
    r := r || jsonb_build_object('name', 'H3 no stop: w2_try_claim returns acquired and crm_paused',
      'ok', (v->>'acquired')::boolean and (v->>'crm_paused')::boolean, 'detail', left(v::text, 200));
    r := r || jsonb_build_object('name', 'H3 no stop: w2_conversations.opted_out stays false and state has no opted_out',
      'ok', not v_conv.opted_out and not (v_conv.state ? 'opted_out'));
    r := r || jsonb_build_object('name', 'H3 no stop: the shared lead is not opted out', 'ok', not v_sl.is_opted_out and v_sl.opted_out_at is null);
    r := r || jsonb_build_object('name', 'H3 no stop: no lead.opted_out touchpoint, the chat.reenquiry touchpoint is written',
      'ok', not exists (select 1 from public.touchpoints t where t.lead_id = v_sl.id and t.event_type = 'lead.opted_out')
            and exists (select 1 from public.touchpoints t where t.lead_id = v_sl.id and t.event_type = 'chat.reenquiry'));
  exception when others then
    r := r || jsonb_build_object('name', 'H3 no stop: w2_try_claim on an ordinary message from a CRM-owned lead', 'ok', false, 'detail', sqlerrm);
  end;

  -- 2e. two messages claimed together: a long one, then "STOP". The joined text is too long to match; the single
  --     message does (the fix checks the joined text and each message).
  begin
    insert into public.w2_inbox (message_id, phone, content, received_at) values
      ('w2-optout-test-batch-1', p_batch, 'I am not interested in this course any more, thank you for the information', now() - interval '20 seconds'),
      ('w2-optout-test-batch-2', p_batch, 'STOP', now());
    v := public.w2_try_claim(p_batch, 'w2-optout-test', 45);
    v_sl := public.crm_find_lead(p_batch);
    r := r || jsonb_build_object('name', 'H3 batch: a long message and "STOP" claimed together opt the lead out',
      'ok', (v->>'crm_paused')::boolean and v_sl.is_opted_out and (select opted_out from public.w2_conversations where phone = p_batch));
  exception when others then
    r := r || jsonb_build_object('name', 'H3 batch: a long message and "STOP" claimed together opt the lead out', 'ok', false, 'detail', sqlerrm);
  end;

  -- ---------------------------------------------------------------- 3. H4: the follow-up respects the shared opt-out
  -- 3a. the new predicate on its own (see the header): true for the lead opted out in 2b, false for the lead of 2d
  begin
    r := r || jsonb_build_object('name', 'H4 predicate: true for an opted-out shared lead, false for one that is not, false for no lead',
      'ok', exists (select 1 from public.crm_find_lead(p_stop) l where l.id is not null and coalesce(l.is_opted_out, false))
            and not exists (select 1 from public.crm_find_lead(p_hello) l where l.id is not null and coalesce(l.is_opted_out, false))
            and not exists (select 1 from public.crm_find_lead(p_n_supp) l where l.id is not null and coalesce(l.is_opted_out, false)));
  exception when others then
    r := r || jsonb_build_object('name', 'H4 predicate: true for an opted-out shared lead, false for one that is not, false for no lead', 'ok', false, 'detail', sqlerrm);
  end;

  -- 3b. the deployed function carries the new lines and keeps the old ones
  begin
    v_def := pg_get_functiondef('public.w2_nurture_due(integer)'::regprocedure);
    r := r || jsonb_build_object('name', 'H4 deployed text: has the shared opt-out and Spark checks, keeps the old guards',
      'ok', position('and not exists (select 1 from crm_find_lead(phone) l where l.id is not null and coalesce(l.is_opted_out, false))' in v_def) > 0
            and position('and not (phone = any(v_supp))' in v_def) > 0
            and position('to_regclass(''b2c.suppressions'')' in v_def) > 0
            and position('where nurture_next_at <= now() and not opted_out and not bot_paused and access_code is not null' in v_def) > 0
            and position('and not exists (select 1 from crm_find_lead(phone) l where l.id is not null and l.destination_type is not null)' in v_def) > 0
            and position('SECURITY DEFINER' in v_def) = 0);
  exception when others then
    r := r || jsonb_build_object('name', 'H4 deployed text: has the shared opt-out and Spark checks, keeps the old guards', 'ok', false, 'detail', sqlerrm);
  end;

  -- 3c. the deployed function runs. p_limit = 0: it can select and lease no conversation.
  begin
    v := public.w2_nurture_due(0);
    r := r || jsonb_build_object('name', 'H4 deployed function: w2_nurture_due(0) runs and returns []', 'ok', v = '[]'::jsonb,
      'detail', case when extract(hour from now() at time zone 'Asia/Kolkata') between 9 and 19
                     then 'inside 09:00-20:00 IST: the whole statement ran'
                     else 'outside 09:00-20:00 IST: only the early return ran; 3d covers the statement' end);
  exception when others then
    r := r || jsonb_build_object('name', 'H4 deployed function: w2_nurture_due(0) runs and returns []', 'ok', false, 'detail', sqlerrm);
  end;

  -- 3d. end to end on a throw-away copy of the deployed text (see the header)
  begin
    -- four conversations whose 3-hour check-in is due, each passing every older rule of w2_nurture_due
    insert into public.w2_conversations (phone, access_code, access_at, classification, nurture_step, nurture_next_at, last_student_at)
    select p, 'DIRECT', now() - interval '4 hours', 'UNQUALIFIED', 0, now() - interval '5 minutes', now() - interval '4 hours'
      from unnest(array[p_n_out, p_n_ok, p_n_supp, p_n_lift]) p;
    -- shared leads: one opted out, one not; neither routed (destination_type stays null)
    perform public.lead_intake(jsonb_build_object('source_system', 'witty', 'event_type', 'chat.turn', 'phone', p_n_out, 'is_test', true,
                                                  'idempotency_key', p_n_out || ':w2-optout-test:create', 'lead', jsonb_build_object('is_opted_out', true)));
    perform public.lead_intake(jsonb_build_object('source_system', 'witty', 'event_type', 'chat.turn', 'phone', p_n_ok, 'is_test', true,
                                                  'idempotency_key', p_n_ok || ':w2-optout-test:create', 'lead', '{}'::jsonb));
    -- Spark's list, when Spark is installed: one number suppressed, one whose suppression was lifted
    if to_regclass('b2c.suppressions') is not null then
      execute $q$insert into b2c.suppressions (value_norm, kind, reason, lifted_at)
                 values ($1, 'phone', 'stop_word', null), ($2, 'phone', 'stop_word', now())$q$ using p_n_supp, p_n_lift;
      v_spark := true;
    end if;

    v_def := pg_get_functiondef('public.w2_nurture_due(integer)'::regprocedure);
    v_sub := array[
      'FUNCTION public.w2_nurture_due(',     'FUNCTION pg_temp.w2_optout_test_nurture_copy(',
      'if v_hour < 9 or v_hour >= 20 then',  'if false then',
      'and not w2_is_test(phone)',           format('and phone = any(%L::text[])', array[p_n_out, p_n_ok, p_n_supp, p_n_lift])];
    for i in 1..3 loop
      if (length(v_def) - length(replace(v_def, v_sub[2 * i - 1], ''))) / length(v_sub[2 * i - 1]) <> 1 then
        raise exception 'the deployed w2_nurture_due does not contain "%" exactly once; the copy was not built', v_sub[2 * i - 1];
      end if;
      v_def := replace(v_def, v_sub[2 * i - 1], v_sub[2 * i]);
    end loop;
    execute v_def;
    execute 'select pg_temp.w2_optout_test_nurture_copy(100)' into v;
    select coalesce(array_agg(e->>'phone'), '{}') into v_phones from jsonb_array_elements(v) e;

    r := r || jsonb_build_object('name', 'H4 copy: a due conversation whose shared lead is not opted out is returned (step 1)',
      'ok', p_n_ok = any(v_phones) and (select (e->>'step')::int from jsonb_array_elements(v) e where e->>'phone' = p_n_ok) = 1, 'detail', array_to_string(v_phones, ','));
    r := r || jsonb_build_object('name', 'H4 copy: a due conversation whose shared lead is opted out is not returned',
      'ok', not (p_n_out = any(v_phones)), 'detail', array_to_string(v_phones, ','));
    r := r || jsonb_build_object('name', 'H4 copy: the skipped conversation is not leased, the returned one is',
      'ok', (select nurture_next_at <= now() from public.w2_conversations where phone = p_n_out)
            and (select nurture_next_at > now() + interval '25 minutes' from public.w2_conversations where phone = p_n_ok));
    r := r || jsonb_build_object('name', 'H4 copy: Witty''s own flag is untouched on the skipped conversation',
      'ok', (select not opted_out from public.w2_conversations where phone = p_n_out));
    if v_spark then
      r := r || jsonb_build_object('name', 'H4 copy: a number on Spark''s suppression list is not returned and not leased',
        'ok', not (p_n_supp = any(v_phones)) and (select nurture_next_at <= now() from public.w2_conversations where phone = p_n_supp),
        'detail', array_to_string(v_phones, ','));
      r := r || jsonb_build_object('name', 'H4 copy: a number whose Spark suppression was lifted is returned',
        'ok', p_n_lift = any(v_phones), 'detail', array_to_string(v_phones, ','));
    else
      r := r || jsonb_build_object('name', 'H4 copy: without Spark (no b2c.suppressions) the follow-up still runs for the other numbers',
        'ok', p_n_supp = any(v_phones) and p_n_lift = any(v_phones), 'detail', 'b2c.suppressions is not installed here; the Spark check was not exercised');
    end if;
    r := r || jsonb_build_object('name', 'H4 copy: nothing outside the harness numbers was returned',
      'ok', v_phones <@ array[p_n_out, p_n_ok, p_n_supp, p_n_lift], 'detail', array_to_string(v_phones, ','));
  exception when others then
    r := r || jsonb_build_object('name', 'H4 copy: w2_nurture_due end to end on the harness numbers', 'ok', false, 'detail', sqlerrm);
  end;

  -- ---------------------------------------------------------------- result
  create temp table w2_optout_test_results (n int, name text, ok boolean, detail text) on commit drop;
  insert into w2_optout_test_results (n, name, ok, detail)
  select e.ord, e.item->>'name', coalesce((e.item->>'ok')::boolean, false), e.item->>'detail'
    from jsonb_array_elements(r) with ordinality e(item, ord);
  select count(*), count(*) filter (where not ok),
         coalesce(string_agg(format('[%s] %s%s', n, name, coalesce(' (' || left(detail, 300) || ')', '')), ' | ' order by n) filter (where not ok),
                  'all passed')
    into v_total, v_failed, v_msg
    from w2_optout_test_results;
  raise exception 'TESTRESULT total=% failed=% %', v_total, v_failed, v_msg;
end
$test$;

rollback;
