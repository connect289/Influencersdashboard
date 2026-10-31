-- The audit's second round (migration 0031): one.mask_text holds to the app's corpus (D-119); an action's arguments are
-- stored as proposed and a confirmation binds what its card showed (D-115); an address maps only to a confirmed user
-- (D-117); model calls reserve their worst case so calls in parallel cannot pass the day's cap (D-118). Local only.
\set ON_ERROR_STOP 1
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
create or replace function pg_temp.q(p_sql text) returns jsonb language plpgsql security definer as $$
declare v jsonb;
begin
  execute 'select to_jsonb(x) from (' || p_sql || ') x' into v;
  return v;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text), pg_temp.q(text) to authenticated, anon, service_role;
create or replace function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000c1"}', false)
$$;
grant execute on function pg_temp.as_owner() to authenticated;

truncate one.chat_actions, one.chat_messages, one.chat_threads restart identity cascade;
truncate one.ai_tasks restart identity cascade;
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001', 'email_code');
create temp table t_ai as select value from one.settings where key = 'ai';
select one.settings_put('ai', (select value from t_ai) || '{"daily_cap_inr": 10}', 'test@eduwit.in', 'audit test: cap 10');

-- 1. one.mask_text and the shared corpus (D-119) --------------------------------------------------------------------------
\set corpus `cat supabase/tests/mask-corpus.json`
create temp table t_corpus as select :'corpus'::jsonb as c;
do $$
declare r record;
begin
  for r in select m ->> 'text' as t, h from jsonb_array_elements((select c -> 'mask' from t_corpus) || (select c -> 'db_mask' from t_corpus)) m,
                  jsonb_array_elements_text(m -> 'hide') h loop
    if strpos(one.mask_text(r.t), r.h) > 0 then
      raise exception 'ASSERT FAILED: mask_text leaves "%" in "%": %', r.h, r.t, one.mask_text(r.t);
    end if;
  end loop;
  for r in select m ->> 'text' as t, k from jsonb_array_elements((select c -> 'keep' from t_corpus)) m, jsonb_array_elements_text(m -> 'keep') k loop
    if strpos(one.mask_text(r.t), r.k) = 0 then
      raise exception 'ASSERT FAILED: mask_text loses "%" in "%": %', r.k, r.t, one.mask_text(r.t);
    end if;
  end loop;
end $$;
select pg_temp.ok((select count(*) from jsonb_array_elements((select c -> 'mask' from t_corpus))) > 20, 'the corpus was read');
select pg_temp.ok(one.mask_json('{"a": "ring ९८७६५४३२१०", "b": ["x 987 654 3210"], "n": 9811122334, "at": "2026-10-30 12:34"}')
                  = '{"a": "ring [phone]", "b": ["x [phone]"], "n": "[phone]", "at": "2026-10-30 12:34"}', 'mask_json masks through mask_text');

-- 2. An action's arguments are stored as proposed, and a confirmation binds what the card showed (D-115) -----------------
create temp table t_audit as select coalesce(max(id), 0) as id from one.audit;
set role authenticated;
select pg_temp.as_owner();
select one.ui_chat_turn_start(null, 'Mute WITTY-04 for an hour', 'chat-auditfix1', 'req-a1') as t1 \gset
select (:'t1'::jsonb ->> 'task_id')::bigint as task1 \gset
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_propose($q$ || :task1 || $q$, 'chat-auditfix1', 'create_proposal', '{"title": "Ask connect@eduwit.in", "rationale": "x"}', 'Open a proposal', 'medium')$q$) = '22023',
                  'arguments with an email are refused, not stored masked');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_propose($q$ || :task1 || $q$, 'chat-auditfix1', 'put_setting', '{"key": "whatsapp", "value": {"waba_ids": ["123456789012345"]}}', 'Change setting whatsapp', 'high')$q$) = '22023',
                  'and so are phone-shaped numbers');
select (one.ui_chat_action_propose(:task1, 'chat-auditfix1', 'mute', '{"target_type": "check", "target": "WITTY-04", "minutes": 60, "reason": "deploy at 10:30"}', 'Mute check WITTY-04 for 60 minutes', 'medium') ->> 'id')::bigint as a1 \gset
reset role;
select pg_temp.ok((select count(*) from one.chat_actions) = 1 and (select args from one.chat_actions where id = :a1)
                  = '{"target_type": "check", "target": "WITTY-04", "minutes": 60, "reason": "deploy at 10:30"}', 'the stored arguments are the proposed ones');
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_decide($q$ || :a1 || $q$, 'confirm', 'req-a2')$q$) = '22023', 'a confirmation without the card''s arguments is refused');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_decide($q$ || :a1 || $q$, 'confirm', 'req-a3', '{"target_type": "check", "target": "WITTY-04", "minutes": 600, "reason": "deploy at 10:30"}')$q$) = '22023',
                  'and so is one whose card showed other arguments');
reset role;
select pg_temp.ok((select status = 'proposed' and decided_at is null from one.chat_actions where id = :a1)
                  and not exists (select 1 from one.audit where id > (select id from t_audit) and action = 'chat.action.confirm'),
                  'nothing was confirmed or audited');
set role authenticated;
select pg_temp.as_owner();
select one.ui_chat_action_decide(:a1, 'confirm', 'req-a4', '{"reason": "deploy at 10:30", "minutes": 60, "target": "WITTY-04", "target_type": "check"}') as d1 \gset
select pg_temp.ok(:'d1'::jsonb ->> 'status' = 'confirmed' and :'d1'::jsonb -> 'args' = '{"target_type": "check", "target": "WITTY-04", "minutes": 60, "reason": "deploy at 10:30"}',
                  'the card''s own arguments confirm it, in any key order');
reset role;
select pg_temp.ok(has_function_privilege('authenticated', 'one.ui_chat_action_decide(bigint,text,text,jsonb)', 'execute')
                  and to_regprocedure('one.ui_chat_action_decide(bigint,text,text)') is null, 'only the binding form exists, and the person may call it');

-- 3. An address maps only to a Supabase user who has confirmed it (D-117) ---------------------------------------------------
insert into auth.users (id, email, email_confirmed_at) values ('00000000-0000-0000-0000-000000000009', 'new.hire@eduwit.in', null);
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_user_put('new.hire@eduwit.in', 'engineer', true)$q$) = '22023', 'an unconfirmed user of the address is refused');
reset role;
select pg_temp.ok(not exists (select 1 from one.users where email = 'new.hire@eduwit.in'), 'and not mapped');
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-000000000009';
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok((one.ui_user_put('new.hire@eduwit.in', 'engineer', true) ->> 'ok')::boolean, 'once confirmed, it is mapped');
reset role;
select pg_temp.ok((select user_id = '00000000-0000-0000-0000-000000000009' and role = 'engineer' from one.users where email = 'new.hire@eduwit.in'), 'to that user');

-- 4. Model calls reserve their worst case; calls in parallel cannot pass the day's cap together (D-118) -------------------
insert into one.ai_tasks (kind, input, status, claimed_by, claimed_at, attempts) values
  ('ask', '{"question": "a"}', 'claimed', 'worker-a1', now(), 1), ('ask', '{"question": "b"}', 'claimed', 'worker-b1', now(), 1);
select (select id from one.ai_tasks where claimed_by = 'worker-a1') as ta, (select id from one.ai_tasks where claimed_by = 'worker-b1') as tb \gset
set role anon;
select pg_temp.ok(pg_temp.err($q$select one.ai_reserve($q$ || :ta || $q$, 'worker-a1', 1)$q$) = '42501', 'anon cannot reserve');
reset role;
set role authenticated;
select pg_temp.ok(pg_temp.err($q$select one.ai_reserve($q$ || :ta || $q$, 'worker-a1', 1)$q$) = '42501', 'nor a signed-in person');
reset role;
set role service_role;
select pg_temp.ok(pg_temp.err($q$select one.ai_reserve($q$ || :ta || $q$, 'worker-b1', 1)$q$) = '55000', 'only the task''s holder reserves');
select pg_temp.ok(pg_temp.err($q$select one.ai_reserve($q$ || :ta || $q$, 'worker-a1', -1)$q$) = '22023', 'an amount is 0 or more');
select pg_temp.ok((one.ai_reserve(:ta, 'worker-a1', 6) ->> 'ok')::boolean, 'a call within the cap is reserved');
select one.ai_reserve(:tb, 'worker-b1', 6) as rb \gset
select pg_temp.ok(not (:'rb'::jsonb ->> 'ok')::boolean and (:'rb'::jsonb ->> 'remaining_inr')::numeric = 4,
                  'a second call in parallel that would pass the cap with the first is refused, and told what is left');
select pg_temp.ok((one.ai_reserve(:tb, 'worker-b1', 4) ->> 'ok')::boolean, 'one that fits is reserved');
select one.ai_calls_add(:ta, 'worker-a1', '[{"provider": "anthropic", "model": "claude-test", "purpose": "audit", "ok": true, "cost_inr": 1}]') as ca \gset
select pg_temp.ok((:'ca'::jsonb ->> 'remaining_inr')::numeric = 5, 'recording the call settles its reservation at its real cost (10 - 1 - 4)');
select pg_temp.ok((one.ai_reserve(:ta, 'worker-a1', 5) ->> 'ok')::boolean and not (one.ai_reserve(:ta, 'worker-a1', 5.01) ->> 'ok')::boolean,
                  'the room freed by the settlement is usable, and no more');
reset role;
update one.ai_tasks set status = 'done' where id = :tb;
set role service_role;
select pg_temp.ok((one.ai_reserve(:ta, 'worker-a1', 9) ->> 'ok')::boolean, 'a task that ended holds nothing');
reset role;
select pg_temp.ok((select count(*) from one.ai_reservations) = 1, 'and its reservation is gone');

-- Clean up ------------------------------------------------------------------------------------------------------------------
select one.settings_put('ai', (select value from t_ai), 'test@eduwit.in', 'audit test: restore');
delete from one.ai_calls where purpose = 'audit';
truncate one.chat_actions, one.chat_messages, one.chat_threads restart identity cascade;
truncate one.ai_tasks restart identity cascade;
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
select 'AUDIT FIXES PASSED';
