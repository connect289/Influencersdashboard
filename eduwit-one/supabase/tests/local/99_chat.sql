-- The command centre chat (migration 0021, D-094): a thread is its owner's only; a turn masks the message, checks the
-- budget as the worker does and opens one 'chat' task the app holds; the worker never takes a chat task and a turn the
-- app did not finish is failed; actions are proposed, confirmed or declined by the person and closed by the app; the
-- assistant's answer is stored redacted; archived threads refuse turns; retention prunes old conversations. Local only.
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
create or replace function pg_temp.errmsg(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlerrm;
end $$;
create or replace function pg_temp.q(p_sql text) returns jsonb language plpgsql security definer as $$
declare v jsonb;
begin
  execute 'select to_jsonb(x) from (' || p_sql || ') x' into v;
  return v;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text), pg_temp.errmsg(text), pg_temp.q(text) to authenticated, anon, service_role;
create or replace function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000c1"}', false)
$$;
create or replace function pg_temp.as_engineer() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000c2"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer() to authenticated;

truncate one.chat_actions, one.chat_messages, one.chat_threads restart identity cascade;
truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in'), ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002', 'email_code');
create temp table t_ai as select value from one.settings where key = 'ai';

-- 1. Settings and grants ------------------------------------------------------------------------------------------------
select pg_temp.ok(one.setting('ai') -> 'routing' ->> 'chat' = 'regular', '0021 routes the chat to the regular tier');
select pg_temp.ok((one.setting('retention') ->> 'chat_days')::int = 90, '0021 keeps conversations 90 days');
set role anon;
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_threads(10)$q$) = '42501', 'anon cannot list conversations');
reset role;
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.chat_own_thread(1)$q$) = '42501', 'the internal helpers are not callable from the API');
select pg_temp.ok(pg_temp.err($q$select one.chat_snapshot()$q$) = '42501', 'nor the snapshot');
select pg_temp.ok(one.ui_chat_threads(10) = '[]', 'no conversations yet');

-- 2. A turn starts: masked message, one chat task held by the app, the budget checked ------------------------------------
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_turn_start(null, 'Why is Witty slow?', 'worker-a')$q$) = '22023', 'the holder must be the chat''s');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_turn_start(null, 'x', 'chat-abcdefgh')$q$) = '22023', 'a message has at least 2 characters');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_turn_start(null, repeat('a', 4001), 'chat-abcdefgh')$q$) = '22023', 'and at most 4000');
select one.ui_chat_turn_start(null, 'Why is Witty slow today? The student 9876543210 (s@example.com) waited', 'chat-abcdefgh', 'req-1') as t1 \gset
select pg_temp.ok((:'t1'::jsonb ->> 'thread_id')::bigint = 1 and (:'t1'::jsonb ->> 'task_id')::bigint > 0, 'a turn opens a thread and a task');
select pg_temp.ok(:'t1'::jsonb #>> '{me,role}' = 'owner' and :'t1'::jsonb #>> '{me,email}' = 'connect@eduwit.in', 'the turn knows who is asking');
select pg_temp.ok(:'t1'::jsonb -> 'history' = '[]' and (:'t1'::jsonb -> 'snapshot') ? 'open_incidents' and (:'t1'::jsonb -> 'ai') ? 'routing'
                  and (:'t1'::jsonb #>> '{budget,cap_inr}')::numeric > 0, 'with an empty history, the snapshot, the AI settings and the budget');
select (:'t1'::jsonb ->> 'task_id')::bigint as task1 \gset
select pg_temp.ok((pg_temp.q($q$select content ->> 'text' as t from one.chat_messages where thread_id = 1 and role = 'user'$q$) ->> 't') !~ '9876543210|example\.com'
                  and (pg_temp.q($q$select content ->> 'text' as t from one.chat_messages where thread_id = 1 and role = 'user'$q$) ->> 't') ~ '\[phone\].*\[email\]',
                  'the stored message has its phone and email masked');
select pg_temp.ok((pg_temp.q($q$select title from one.chat_threads where id = 1$q$) ->> 'title') !~ '9876543210', 'the title is taken from the masked text');
select pg_temp.ok((pg_temp.q($q$select kind = 'chat' and status = 'claimed' and claimed_by = 'chat-abcdefgh' and attempts = 1 and (input ->> 'thread_id')::int = 1 as v
                     from one.ai_tasks where id = $q$ || :task1) ->> 'v')::boolean, 'the task is a chat task already claimed by the app');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_turn_start(1, 'and another thing', 'chat-abcdefgh')$q$) = '22023', 'one turn at a time per conversation');
select pg_temp.ok((pg_temp.q($q$select exists (select 1 from one.audit where action = 'chat.turn' and target = 'chat_thread:1' and request_id = 'req-1') as v$q$) ->> 'v')::boolean, 'the turn is audited');
reset role;

-- 3. The app records calls and reads tools against the chat task; the worker never sees it ------------------------------
set role service_role;
select pg_temp.ok((one.ai_calls_add(:task1, 'chat-abcdefgh', '[{"provider": "anthropic", "model": "claude-sonnet-5-5", "purpose": "chat:1", "ok": true, "cost_inr": 1.5, "input_tokens": 100, "output_tokens": 50}]') ->> 'spent_inr')::numeric >= 1.5,
                  'the app records the turn''s model calls against the task');
select pg_temp.ok((one.ai_tool(:task1, 'chat-abcdefgh', 'health', '{}') ->> 'ok')::boolean, 'the read tools answer for a chat task');
select pg_temp.ok(pg_temp.err($q$select one.ai_tool($q$ || :task1 || $q$, 'worker-a', 'health', '{}')$q$) = '42501', 'but only for its holder');
select pg_temp.ok((one.ai_tool(:task1, 'chat-abcdefgh', 'app_status', '{"app": "witty"}') ->> 'ok')::boolean, 'app_status too');
select pg_temp.ok(one.ai_claim('worker-a') is null or (one.ai_claim('worker-a') ->> 'task')::jsonb ->> 'kind' <> 'chat', 'the worker never claims a chat task');
select pg_temp.ok((pg_temp.q($q$select status = 'claimed' and claimed_by = 'chat-abcdefgh' as v from one.ai_tasks where id = $q$ || :task1) ->> 'v')::boolean, 'and leaves the running turn alone');
reset role;
-- A held chat task does not take a worker slot (max_parallel).
update one.ai_tasks set claimed_at = now() where id = :task1;
insert into one.ai_tasks (kind, input, status, claimed_by, claimed_at, attempts) values ('chat', '{"thread_id": 99}', 'claimed', 'chat-busybusy', now(), 1);
select one.enqueue_ai('ask', '{"question": "how many leads?"}', null, 'ask:chat-test', null) as ask_task \gset
set role service_role;
select one.ai_claim('worker-b') as c_ask \gset
reset role;
select pg_temp.ok((:'c_ask'::jsonb #>> '{task,id}')::bigint = :ask_task, 'two held chat turns do not fill the worker''s parallel slots');
update one.ai_tasks set status = 'done' where id = :ask_task;
delete from one.ai_tasks where claimed_by = 'chat-busybusy';

-- 4. Actions: proposed by the assistant, decided by the person, closed by the app ----------------------------------------
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_propose($q$ || :task1 || $q$, 'chat-abcdefgh', 'acknowledge_incident', '{"id": 1}', 'Acknowledge incident #1', 'urgent')$q$) = '22023',
                  'a risk is low, medium or high');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_propose($q$ || :task1 || $q$, 'chat-other000', 'acknowledge_incident', '{"id": 1}', 'Acknowledge incident #1', 'low')$q$) = '55000',
                  'only the turn''s holder proposes');
select (one.ui_chat_action_propose(:task1, 'chat-abcdefgh', 'acknowledge_incident', '{"id": 1}', 'Acknowledge incident #1', 'low') ->> 'id')::bigint as a1 \gset
select (one.ui_chat_action_propose(:task1, 'chat-abcdefgh', 'mute', '{"target_type": "check", "target": "WITTY-04", "minutes": 60, "reason": "deploy"}', 'Mute WITTY-04 for an hour', 'medium') ->> 'id')::bigint as a2 \gset
select (one.ui_chat_action_propose(:task1, 'chat-abcdefgh', 'run_test', '{"test_id": "T-WITTY-QUALIFY"}', 'Run T-WITTY-QUALIFY now', 'medium') ->> 'id')::bigint as a3 \gset
select one.ui_chat_action_propose(:task1, 'chat-abcdefgh', 'run_test', '{"test_id": "T-B2B"}', 'Run T-B2B', 'medium');
select one.ui_chat_action_propose(:task1, 'chat-abcdefgh', 'run_test', '{"test_id": "T-B2C"}', 'Run T-B2C', 'medium');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_propose($q$ || :task1 || $q$, 'chat-abcdefgh', 'run_test', '{"test_id": "T-WEB"}', 'Run T-WEB', 'medium')$q$) = '22023',
                  'at most five actions wait in one conversation');
select pg_temp.ok((pg_temp.q($q$select count(*) as n from one.chat_actions where thread_id = 1 and status = 'proposed'$q$) ->> 'n')::int = 5, 'five proposed');
-- The engineer owns none of this.
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_decide($q$ || :a1 || $q$, 'confirm')$q$) = 'P0002', 'another person cannot decide the owner''s action');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_thread(1)$q$) = 'P0002', 'nor read the owner''s conversation');
select pg_temp.ok(one.ui_chat_threads(10) = '[]', 'nor see it in a list');
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_decide($q$ || :a1 || $q$, 'maybe')$q$) = '22023', 'the decision is confirm or decline');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_result($q$ || :a1 || $q$, true, '{}')$q$) = 'P0002', 'a result needs a confirmed action');
select one.ui_chat_action_decide(:a1, 'decline', 'req-2') as d1 \gset
select pg_temp.ok(:'d1'::jsonb ->> 'status' = 'declined' and (pg_temp.q($q$select status = 'declined' and decided_by = 'connect@eduwit.in' as v from one.chat_actions where id = $q$ || :a1) ->> 'v')::boolean, 'declined');
select pg_temp.ok((pg_temp.q($q$select exists (select 1 from one.chat_messages where thread_id = 1 and role = 'action' and (content ->> 'action_id')::bigint = $q$ || :a1 || $q$ and content ->> 'status' = 'declined') as v$q$) ->> 'v')::boolean,
                  'the decline joins the conversation');
-- A confirmation carries the arguments its card showed (0031, D-115).
select one.ui_chat_action_decide(:a2, 'confirm', 'req-3', '{"target_type": "check", "target": "WITTY-04", "minutes": 60, "reason": "deploy"}') as d2 \gset
select pg_temp.ok(:'d2'::jsonb ->> 'status' = 'confirmed' and :'d2'::jsonb ->> 'tool' = 'mute' and :'d2'::jsonb #>> '{args,target}' = 'WITTY-04',
                  'confirm hands the call back to the app');
select pg_temp.ok((pg_temp.q($q$select exists (select 1 from one.audit where action = 'chat.action.confirm' and target = 'chat_action:$q$ || :a2 || $q$' and request_id = 'req-3') as v$q$) ->> 'v')::boolean, 'confirmation is audited');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_action_decide($q$ || :a2 || $q$, 'confirm')$q$) = 'P0002', 'an action is decided once');
select pg_temp.ok((one.ui_chat_action_result(:a2, true, '{"ok": true, "id": 7, "email": "x@y.com"}') ->> 'status') = 'done', 'the app closes it done');
select pg_temp.ok((pg_temp.q($q$select result ->> 'id' = '7' and result ->> 'email' is distinct from 'x@y.com' as v from one.chat_actions where id = $q$ || :a2) ->> 'v')::boolean, 'the result is kept with contact data masked');
select pg_temp.ok((pg_temp.q($q$select exists (select 1 from one.chat_messages where thread_id = 1 and role = 'action' and (content ->> 'action_id')::bigint = $q$ || :a2 || $q$ and content ->> 'status' = 'done') as v$q$) ->> 'v')::boolean,
                  'the outcome joins the conversation');
-- Expiry: two hours after the proposal, a decision is too late.
reset role;
update one.chat_actions set proposed_at = now() - interval '3 hours' where id = :a3;
set role authenticated;
select pg_temp.as_owner();
select one.ui_chat_action_decide(:a3, 'confirm') as d3 \gset
select pg_temp.ok((:'d3'::jsonb ->> 'ok')::boolean is false and :'d3'::jsonb ->> 'status' = 'expired' and (pg_temp.q($q$select status = 'expired' as v from one.chat_actions where id = $q$ || :a3) ->> 'v')::boolean,
                  'an action expires two hours after it was proposed');

-- 5. The turn ends: the answer is stored redacted, the task closed -------------------------------------------------------
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_turn_finish($q$ || :task1 || $q$, 'chat-other000', '{"text": "x"}', 'done')$q$) = '55000', 'only the holder finishes a turn');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_turn_finish($q$ || :task1 || $q$, 'chat-abcdefgh', '{"text": "x"}', 'maybe')$q$) = '22023', 'done or failed');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_turn_finish($q$ || :task1 || $q$, 'chat-abcdefgh', '[1]', 'done')$q$) = '22023', 'the answer is an object');
select one.ui_chat_turn_finish(:task1, 'chat-abcdefgh',
  '{"text": "Witty replied slowly for 40 minutes; WITTY-04 is open.", "tools": [{"name": "health", "ok": true, "rows": 1, "result": "{\"ok\": true}"}], "actions": [1, 2], "email": "lead@example.com"}',
  'done') as f1 \gset
select pg_temp.ok((:'f1'::jsonb ->> 'ok')::boolean and (pg_temp.q($q$select status = 'done' and (result ->> 'tools')::int = 1 as v from one.ai_tasks where id = $q$ || :task1) ->> 'v')::boolean, 'the task is done');
select pg_temp.ok((pg_temp.q($q$select content ->> 'text' as t, content ->> 'email' as e from one.chat_messages where id = $q$ || (:'f1'::jsonb ->> 'message_id')) ->> 't') like 'Witty replied%'
                  and (pg_temp.q($q$select content ->> 'text' as t, content ->> 'email' as e from one.chat_messages where id = $q$ || (:'f1'::jsonb ->> 'message_id')) ->> 'e') is distinct from 'lead@example.com',
                  'the answer is stored, contact data inside it masked');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_turn_finish($q$ || :task1 || $q$, 'chat-abcdefgh', '{"text": "x"}', 'done')$q$) = '55000', 'a turn finishes once');
select one.ui_chat_thread(1) as th \gset
select pg_temp.ok(jsonb_array_length(:'th'::jsonb -> 'messages') = 5 and jsonb_array_length(:'th'::jsonb -> 'actions') = 5 and (:'th'::jsonb ->> 'busy')::boolean is false,
                  'the conversation shows its turns, outcomes and actions');
select pg_temp.ok((select (x ->> 'open_actions')::int = 2 and (x ->> 'messages')::int = 5 from jsonb_array_elements(one.ui_chat_threads(10)) x), 'the list counts turns and waiting actions');

-- 6. The next turn carries the history; a stale turn is failed, never re-queued ------------------------------------------
select one.ui_chat_turn_start(1, 'And the website?', 'chat-abcdefgh') as t2 \gset
select pg_temp.ok(jsonb_array_length(:'t2'::jsonb -> 'history') = 5 and (:'t2'::jsonb -> 'history' -> 0 ->> 'role') = 'user', 'the second turn gets the conversation so far');
reset role;
update one.ai_tasks set claimed_at = now() - interval '11 minutes' where id = (:'t2'::jsonb ->> 'task_id')::bigint;
set role service_role;
select one.ai_claim('worker-a');
select pg_temp.ok((pg_temp.q($q$select status = 'failed' and error = 'the chat turn did not finish' as v from one.ai_tasks where id = $q$ || (:'t2'::jsonb ->> 'task_id')) ->> 'v')::boolean,
                  'a turn the app did not finish in 10 minutes is failed by the claim, not re-queued');
reset role;
set role authenticated;
select pg_temp.as_owner();
select one.ui_chat_turn_start(1, 'Still there?', 'chat-abcdefgh') as t3 \gset
reset role;
update one.ai_tasks set claimed_at = now() - interval '11 minutes' where id = (:'t3'::jsonb ->> 'task_id')::bigint;
set role authenticated;
select pg_temp.as_owner();
select one.ui_chat_turn_start(null, 'A fresh conversation', 'chat-abcdefgh') as t4 \gset
select pg_temp.ok((pg_temp.q($q$select status = 'failed' as v from one.ai_tasks where id = $q$ || (:'t3'::jsonb ->> 'task_id')) ->> 'v')::boolean, 'and by the next turn anywhere');
select pg_temp.ok((:'t4'::jsonb ->> 'thread_id')::bigint = 2, 'a new conversation');
select one.ui_chat_turn_finish((:'t4'::jsonb ->> 'task_id')::bigint, 'chat-abcdefgh', '{"text": "Hello."}', 'done');

-- 7. Archive, the engineer's own conversations, the budget --------------------------------------------------------------
select one.ui_chat_thread_archive(2, 'req-4');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_turn_start(2, 'more', 'chat-abcdefgh')$q$) = '22023', 'an archived conversation refuses turns');
select pg_temp.ok((select count(*) from jsonb_array_elements(one.ui_chat_threads(10))) = 1, 'and leaves the list');
select pg_temp.as_engineer();
select one.ui_chat_turn_start(null, 'Engineer here', 'chat-engineer1') as te \gset
select pg_temp.ok((:'te'::jsonb #>> '{me,role}') = 'engineer' and (:'te'::jsonb ->> 'thread_id')::bigint = 3, 'an engineer has their own conversations');
select one.ui_chat_turn_finish((:'te'::jsonb ->> 'task_id')::bigint, 'chat-engineer1', '{"text": "Hi."}', 'done');
select pg_temp.ok(pg_temp.err($q$select one.ui_chat_thread_archive(1)$q$) = 'P0002', 'and cannot archive the owner''s');
reset role;
select one.settings_put('ai', (select value from t_ai) || '{"daily_cap_inr": 0}', 'test@eduwit.in', 'cap 0');
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.errmsg($q$select one.ui_chat_turn_start(1, 'budget?', 'chat-abcdefgh')$q$) like 'budget (cap reached)%', 'at the cap the chat does not answer');
reset role;
select one.settings_put('ai', (select value from t_ai) || '{"daily_cap_inr": 10, "queue_non_triage_at_pct": 80}', 'test@eduwit.in', 'cap 10');
insert into one.ai_calls (task_id, provider, model, purpose, ok, cost_inr) values (:task1, 'anthropic', 'claude-sonnet-5-5', 'chat:test', true, 7.0);
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.errmsg($q$select one.ui_chat_turn_start(1, 'budget?', 'chat-abcdefgh')$q$) like 'budget (over 80%)%', 'from 80% of the cap only classify and triage run');
reset role;
select one.settings_put('ai', (select value from t_ai), 'test@eduwit.in', 'restore');
delete from one.ai_calls where purpose = 'chat:test';

-- 8. Retention -----------------------------------------------------------------------------------------------------------
update one.chat_threads set updated_at = now() - interval '100 days' where id = 2;
select one.retention() as r \gset
select pg_temp.ok((:'r'::jsonb ->> 'chat_threads')::int = 1 and not exists (select 1 from one.chat_threads where id = 2)
                  and not exists (select 1 from one.chat_messages where thread_id = 2), 'conversations older than chat_days go with their turns');
select pg_temp.ok(exists (select 1 from one.chat_threads where id = 1), 'recent ones stay');

select 'chat tests passed' as result;
