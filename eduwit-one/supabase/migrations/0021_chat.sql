-- 0021 the command centre (D-094): a chat with Claude inside Eduwit One. It reads through the same fixed tools as Ask
-- and acts only through the page functions the signed-in person could press themselves (one.ui_*): every write is
-- first an action card in the chat that the person confirms, and a confirmed action is the same one.ui_* call a page
-- makes, as the same person, with the same role check, audit row and request id. The AI's words never run; the checks'
-- SQL still decides what is broken (D-075); the fixes keep their proof-before-power rules (D-084); a secret never passes
-- through the model (the chat shows a Vault card instead, D-094).
--   one.chat_threads, chat_messages, chat_actions   a person's conversations, their turns (contact data masked before
--                                                   they are stored) and the actions proposed in them
--   one.ui_chat_*                                   the page functions (authenticated, one.ui_require; a thread is its
--                                                   owner's only)
--   one.ai_tasks.kind 'chat'                        one task per turn, claimed by the app for its budget rows; the
--                                                   worker never gets it (ai_claim); a turn not finished in 10 minutes
--                                                   is failed, so it never counts as waiting work (ONE-01)
--   one.ai_tool                                     also answers a chat task (read-only transaction, redacted)
--   one.retention                                   prunes conversations older than retention.chat_days (90)
--   settings                                        ai.routing.chat = regular; retention.chat_days = 90

alter table one.ai_tasks drop constraint ai_tasks_kind_check;
alter table one.ai_tasks add constraint ai_tasks_kind_check
  check (kind in ('classify', 'triage', 'explain', 'brief', 'propose_fix', 'propose_feature', 'ask', 'test_author', 'chat'));

create table one.chat_threads (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  email text not null,
  title text not null default 'New conversation',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);
create index chat_threads_user_idx on one.chat_threads (user_id, updated_at desc);

-- One row per turn of the conversation: what the person said (masked), what the assistant answered with the tools it
-- used (their results bounded and redacted), and each action's outcome.
create table one.chat_messages (
  id bigint generated always as identity primary key,
  thread_id bigint not null references one.chat_threads (id) on delete cascade,
  seq integer not null,
  role text not null check (role in ('user', 'assistant', 'action')),
  content jsonb not null default '{}',
  task_id bigint references one.ai_tasks (id),
  created_at timestamptz not null default now(),
  unique (thread_id, seq)
);

-- An action the assistant proposed: a one.ui_* call with its arguments, waiting for the person's confirmation in the
-- chat (two hours), then run by the app as that person and closed with its result.
create table one.chat_actions (
  id bigint generated always as identity primary key,
  thread_id bigint not null references one.chat_threads (id) on delete cascade,
  task_id bigint references one.ai_tasks (id),
  tool text not null check (tool ~ '^[a-z_]{3,40}$'),
  args jsonb not null default '{}',
  summary text not null,
  risk text not null check (risk in ('low', 'medium', 'high')),
  status text not null default 'proposed' check (status in ('proposed', 'confirmed', 'done', 'failed', 'declined', 'expired')),
  proposed_by text not null,
  proposed_at timestamptz not null default now(),
  decided_by text,
  decided_at timestamptz,
  result jsonb,
  error text,
  request_id text
);
create index chat_actions_thread_idx on one.chat_actions (thread_id, id desc);

-- The signed-in person's own thread, or P0002. Internal.
create or replace function one.chat_own_thread(p_id bigint) returns one.chat_threads
language plpgsql set search_path = '' as $$
declare
  v one.chat_threads;
begin
  select * into v from one.chat_threads where id = p_id and user_id = one.uid();
  if not found then
    raise exception 'no conversation %', p_id using errcode = 'P0002';
  end if;
  return v;
end $$;

-- Appends one row to a thread and marks it current. Internal.
create or replace function one.chat_append(p_thread bigint, p_role text, p_content jsonb, p_task bigint default null) returns bigint
language plpgsql set search_path = '' as $$
declare
  v_id bigint;
begin
  insert into one.chat_messages (thread_id, seq, role, content, task_id)
  select p_thread, coalesce(max(seq), 0) + 1, p_role, p_content, p_task from one.chat_messages where thread_id = p_thread
  returning id into v_id;
  update one.chat_threads set updated_at = now() where id = p_thread;
  return v_id;
end $$;

-- What the assistant is told at the start of every turn: the console's state in a few numbers (no contact data).
create or replace function one.chat_snapshot() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'now_ist', to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD HH24:MI'),
    'tick_age_s', (select round(extract(epoch from now() - max(finished_at))) from one.runs where kind = 'tick'),
    'open_incidents', (select jsonb_build_object('P1', count(*) filter (where severity = 'P1'), 'P2', count(*) filter (where severity = 'P2'),
                                                 'P3', count(*) filter (where severity = 'P3'))
                         from one.incidents where resolved_at is null and check_id <> 'ONE-SYNTH'),
    'unacknowledged_p1', (select count(*) from one.incidents where resolved_at is null and severity = 'P1' and acknowledged_at is null),
    'proposals_open', (select count(*) from one.proposals where status = 'open'),
    'setup_open', (select count(*) from jsonb_each(coalesce(one.setting('setup') -> 'items', '{}')) i
                    where not coalesce((i.value ->> 'validated')::boolean, false) and i.value ->> 'status' is distinct from 'not_applicable'),
    'mutes_active', (select count(*) from one.mutes m where now() between m.starts_at and m.ends_at)
                  + (select count(*) from one.checks c where c.muted_until > now()),
    'fixes_enabled', (select coalesce(jsonb_agg(k.key order by k.key), '[]') from jsonb_each(coalesce(one.setting('fixes'), '{}')) k
                       where jsonb_typeof(k.value) = 'object' and coalesce((k.value ->> 'enabled')::boolean, false)),
    'ai_spent_inr_today', one.ai_spent_today())
$$;

-- The person's conversations, newest first.
create or replace function one.ui_chat_threads(p_limit integer default 30) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'created_at', t.created_at, 'updated_at', t.updated_at,
                                                       'messages', (select count(*) from one.chat_messages m where m.thread_id = t.id),
                                                       'open_actions', (select count(*) from one.chat_actions a where a.thread_id = t.id and a.status = 'proposed'))
                                    order by t.updated_at desc), '[]')
            from (select * from one.chat_threads
                   where user_id = one.uid() and archived_at is null
                   order by updated_at desc limit least(greatest(coalesce(p_limit, 30), 1), 100)) t);
end $$;

-- One conversation: its last 200 turns and every action proposed in it.
create or replace function one.ui_chat_thread(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('read');
  v_t one.chat_threads := one.chat_own_thread(p_id);
begin
  return jsonb_build_object(
    'thread', jsonb_build_object('id', v_t.id, 'title', v_t.title, 'created_at', v_t.created_at, 'updated_at', v_t.updated_at, 'archived_at', v_t.archived_at),
    'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'seq', m.seq, 'role', m.role, 'content', m.content, 'created_at', m.created_at)
                                           order by m.seq), '[]')
                   from (select * from one.chat_messages where thread_id = v_t.id order by seq desc limit 200) m),
    'actions', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'tool', a.tool, 'args', a.args, 'summary', a.summary, 'risk', a.risk,
                                                             'status', a.status, 'proposed_at', a.proposed_at, 'decided_at', a.decided_at,
                                                             'result', a.result, 'error', a.error) order by a.id), '[]')
                  from one.chat_actions a where a.thread_id = v_t.id),
    'busy', exists (select 1 from one.ai_tasks where kind = 'chat' and status = 'claimed' and (input ->> 'thread_id')::bigint = v_t.id));
end $$;

-- A turn begins: the person's message is masked and stored, the budget is checked the way the worker checks it (at the
-- day's cap nothing runs; from queue_non_triage_at_pct only classification and triage), and one 'chat' task is created
-- already claimed by the app, which records every model call against it (one.ai_calls_add). Returns what the app needs
-- to answer: the thread, the task, the AI settings, the budget, the last 40 turns and the console's snapshot.
create or replace function one.ui_chat_turn_start(p_thread bigint, p_text text, p_holder text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_role text := (select o.role from one.users o where o.user_id = one.uid());
  v_ai jsonb := coalesce(one.setting('ai'), '{}');
  v_cap numeric := coalesce((v_ai ->> 'daily_cap_inr')::numeric, 0);
  v_pct numeric := coalesce((v_ai ->> 'queue_non_triage_at_pct')::numeric, 80);
  v_spent numeric;
  v_raw text := trim(coalesce(p_text, ''));
  v_text text;
  v_t one.chat_threads;
  v_task bigint;
  v_msg bigint;
begin
  if coalesce(p_holder, '') !~ '^chat-[a-z0-9]{8,40}$' then
    raise exception 'bad holder' using errcode = '22023';
  end if;
  if length(v_raw) < 2 then
    raise exception 'say what you need, in at least 2 characters' using errcode = '22023';
  end if;
  if length(v_raw) > 4000 then
    raise exception 'a message is at most 4000 characters' using errcode = '22023';
  end if;
  v_text := one.mask_text(v_raw);
  -- A turn the app never finished (it died mid-answer) is failed after 10 minutes, so it neither blocks its thread nor
  -- counts as waiting AI work (ONE-01); an action nobody decided in two hours expires.
  update one.ai_tasks set status = 'failed', error = 'the chat turn did not finish'
   where kind = 'chat' and status = 'claimed' and claimed_at < now() - interval '10 minutes';
  update one.chat_actions set status = 'expired' where status in ('proposed', 'confirmed') and proposed_at < now() - interval '2 hours';
  if p_thread is null then
    insert into one.chat_threads (user_id, email, title)
    values (one.uid(), v_actor, left(regexp_replace(v_text, '\s+', ' ', 'g'), 80)) returning * into v_t;
  else
    v_t := one.chat_own_thread(p_thread);
    perform 1 from one.chat_threads where id = v_t.id for update;
    if v_t.archived_at is not null then
      raise exception 'this conversation is archived; start a new one' using errcode = '22023';
    end if;
    if exists (select 1 from one.ai_tasks where kind = 'chat' and status = 'claimed' and (input ->> 'thread_id')::bigint = v_t.id) then
      raise exception 'a reply is still being written in this conversation; wait for it' using errcode = '22023';
    end if;
  end if;
  v_spent := one.ai_spent_today();
  if v_cap <= 0 or v_spent >= v_cap then
    raise exception '%', format('budget (cap reached): today''s AI spend ₹%s has reached the cap ₹%s (Settings → AI); the chat answers again after midnight IST',
                                round(v_spent, 2), v_cap) using errcode = '22023';
  elsif v_spent >= v_cap * v_pct / 100 then
    raise exception '%', format('budget (over %s%%): today''s AI spend ₹%s is %s%% of the cap ₹%s, so only classification and triage run until midnight IST',
                                v_pct, round(v_spent, 2), round(v_spent / v_cap * 100), v_cap) using errcode = '22023';
  end if;
  insert into one.ai_tasks (kind, input, status, claimed_by, claimed_at, attempts)
  values ('chat', jsonb_build_object('thread_id', v_t.id, 'asked_by', v_actor), 'claimed', p_holder, now(), 1) returning id into v_task;
  v_msg := one.chat_append(v_t.id, 'user', jsonb_build_object('text', v_text), v_task);
  update one.ai_tasks set input = input || jsonb_build_object('message_id', v_msg) where id = v_task;
  perform one.ui_audit_write(v_actor, 'chat.turn', 'chat_thread:' || v_t.id, null, jsonb_build_object('task_id', v_task), p_request_id);
  return jsonb_build_object(
    'thread_id', v_t.id, 'message_id', v_msg, 'task_id', v_task,
    'me', jsonb_build_object('email', v_actor, 'role', v_role),
    'ai', v_ai,
    'budget', jsonb_build_object('spent_inr', v_spent, 'cap_inr', v_cap, 'remaining_inr', greatest(v_cap - v_spent, 0)),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('role', m.role, 'content', m.content) order by m.seq), '[]')
                  from (select * from one.chat_messages where thread_id = v_t.id and id <> v_msg order by seq desc limit 40) m),
    'snapshot', one.chat_snapshot());
end $$;

-- The turn ends: the assistant's answer (its text, the tools it used with bounded results, the actions it proposed) is
-- stored with every phone and email inside it masked (one.mask_json; the key-based one.redact would drop the answer's own
-- 'text' and an action's 'note'), and the task is closed done or failed. The tool data itself was redacted by the tools.
create or replace function one.ui_chat_turn_finish(p_task bigint, p_holder text, p_assistant jsonb, p_status text, p_error text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_task one.ai_tasks;
  v_t one.chat_threads;
  v_msg bigint;
begin
  select * into v_task from one.ai_tasks where id = p_task and kind = 'chat' and status = 'claimed' and claimed_by = p_holder for update;
  if not found then
    raise exception 'turn % is not open for this holder', p_task using errcode = '55000';
  end if;
  v_t := one.chat_own_thread((v_task.input ->> 'thread_id')::bigint);
  if p_status not in ('done', 'failed') then
    raise exception 'status is done or failed' using errcode = '22023';
  end if;
  if jsonb_typeof(p_assistant) <> 'object' or pg_column_size(p_assistant) > 200000 then
    raise exception 'the answer is an object under 200 kB' using errcode = '22023';
  end if;
  v_msg := one.chat_append(v_t.id, 'assistant',
                           one.mask_json(p_assistant) || case when p_error is not null then jsonb_build_object('error', left(p_error, 300)) else '{}' end,
                           p_task);
  update one.ai_tasks
     set status = p_status, error = left(p_error, 300),
         result = jsonb_build_object('message_id', v_msg,
                                     'tools', case when jsonb_typeof(p_assistant -> 'tools') = 'array' then jsonb_array_length(p_assistant -> 'tools') else 0 end)
   where id = p_task;
  return jsonb_build_object('ok', true, 'message_id', v_msg);
end $$;

-- The assistant proposes an action: a one.ui_* call it may not make itself. At most five wait in one conversation.
create or replace function one.ui_chat_action_propose(p_task bigint, p_holder text, p_tool text, p_args jsonb, p_summary text, p_risk text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_task one.ai_tasks;
  v_t one.chat_threads;
  v_id bigint;
begin
  select * into v_task from one.ai_tasks where id = p_task and kind = 'chat' and status = 'claimed' and claimed_by = p_holder;
  if not found then
    raise exception 'turn % is not open for this holder', p_task using errcode = '55000';
  end if;
  v_t := one.chat_own_thread((v_task.input ->> 'thread_id')::bigint);
  if coalesce(p_tool, '') !~ '^[a-z_]{3,40}$' or coalesce(p_risk, '') not in ('low', 'medium', 'high')
     or length(trim(coalesce(p_summary, ''))) not between 3 and 500
     or jsonb_typeof(coalesce(p_args, '{}'::jsonb)) <> 'object' or pg_column_size(coalesce(p_args, '{}'::jsonb)) > 20000 then
    raise exception 'an action names a tool, a risk (low, medium, high), a summary of 3 to 500 characters and an object of arguments' using errcode = '22023';
  end if;
  if (select count(*) from one.chat_actions where thread_id = v_t.id and status = 'proposed') >= 5 then
    raise exception 'five actions already wait for a decision in this conversation' using errcode = '22023';
  end if;
  insert into one.chat_actions (thread_id, task_id, tool, args, summary, risk, proposed_by)
  values (v_t.id, p_task, p_tool, one.mask_json(coalesce(p_args, '{}'::jsonb)), trim(p_summary), p_risk, v_actor) returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

-- The person decides in the chat. Decline closes the action. Confirm marks it and hands the call back to the app, which
-- runs the one.ui_* function as this person (its own role check and audit row, under the same request id) and closes
-- the action with one.ui_chat_action_result. Two hours after the proposal the action has expired.
create or replace function one.ui_chat_action_decide(p_id bigint, p_decision text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_a one.chat_actions;
  v_t one.chat_threads;
begin
  select * into v_a from one.chat_actions where id = p_id for update;
  if not found then
    raise exception 'no action %', p_id using errcode = 'P0002';
  end if;
  v_t := one.chat_own_thread(v_a.thread_id);
  if p_decision not in ('confirm', 'decline') then
    raise exception 'the decision is confirm or decline' using errcode = '22023';
  end if;
  if v_a.status <> 'proposed' then
    raise exception 'action % is not waiting for a decision (%)', p_id, v_a.status using errcode = 'P0002';
  end if;
  if v_a.proposed_at < now() - interval '2 hours' then
    update one.chat_actions set status = 'expired' where id = p_id;
    perform one.chat_append(v_t.id, 'action', jsonb_build_object('action_id', p_id, 'tool', v_a.tool, 'status', 'expired', 'summary', v_a.summary));
    return jsonb_build_object('ok', false, 'status', 'expired', 'error', 'this action expired two hours after it was proposed; ask for it again');
  end if;
  if p_decision = 'decline' then
    update one.chat_actions set status = 'declined', decided_by = v_actor, decided_at = now(), request_id = p_request_id where id = p_id;
    perform one.chat_append(v_t.id, 'action', jsonb_build_object('action_id', p_id, 'tool', v_a.tool, 'status', 'declined', 'summary', v_a.summary));
    perform one.ui_audit_write(v_actor, 'chat.action.decline', 'chat_action:' || p_id, null, jsonb_build_object('tool', v_a.tool), p_request_id);
    return jsonb_build_object('ok', true, 'status', 'declined');
  end if;
  update one.chat_actions set status = 'confirmed', decided_by = v_actor, decided_at = now(), request_id = p_request_id where id = p_id;
  perform one.ui_audit_write(v_actor, 'chat.action.confirm', 'chat_action:' || p_id, null, jsonb_build_object('tool', v_a.tool, 'args', v_a.args), p_request_id);
  return jsonb_build_object('ok', true, 'status', 'confirmed', 'id', p_id, 'tool', v_a.tool, 'args', v_a.args, 'summary', v_a.summary, 'risk', v_a.risk);
end $$;

-- The app reports what the confirmed call did; the outcome joins the conversation so the next turn knows it.
create or replace function one.ui_chat_action_result(p_id bigint, p_ok boolean, p_result jsonb default null, p_error text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_a one.chat_actions;
  v_t one.chat_threads;
  v_status text := case when coalesce(p_ok, false) then 'done' else 'failed' end;
begin
  select * into v_a from one.chat_actions where id = p_id for update;
  if not found then
    raise exception 'no action %', p_id using errcode = 'P0002';
  end if;
  v_t := one.chat_own_thread(v_a.thread_id);
  if v_a.status <> 'confirmed' then
    raise exception 'action % was not confirmed (%)', p_id, v_a.status using errcode = 'P0002';
  end if;
  if p_result is not null and pg_column_size(p_result) > 20000 then
    raise exception 'the result is at most 20 kB' using errcode = '22023';
  end if;
  update one.chat_actions set status = v_status, result = one.mask_json(p_result), error = one.mask_text(left(p_error, 300)) where id = p_id;
  perform one.chat_append(v_t.id, 'action', jsonb_build_object('action_id', p_id, 'tool', v_a.tool, 'status', v_status, 'summary', v_a.summary)
                                            || case when p_error is not null then jsonb_build_object('error', left(p_error, 300)) else '{}' end);
  return jsonb_build_object('ok', true, 'status', v_status);
end $$;

-- A conversation leaves the list; its rows stay until retention.chat_days.
create or replace function one.ui_chat_thread_archive(p_id bigint, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_t one.chat_threads := one.chat_own_thread(p_id);
begin
  update one.chat_threads set archived_at = coalesce(archived_at, now()) where id = v_t.id;
  perform one.ui_audit_write(v_actor, 'chat.archive', 'chat_thread:' || v_t.id, null, null, p_request_id);
  return jsonb_build_object('ok', true);
end $$;

-- Settings: the chat's tier and the conversations' retention, added where missing (the row keeps its actor, so a seed
-- row stays a seed row and a person's edit stays theirs).
do $$
declare
  v one.settings;
begin
  select * into v from one.settings where key = 'ai';
  if found and not (coalesce(v.value -> 'routing', '{}'::jsonb) ? 'chat') then
    perform one.settings_put('ai', jsonb_set(v.value || jsonb_build_object('routing', coalesce(v.value -> 'routing', '{}'::jsonb)), '{routing,chat}', '"regular"', true), v.actor, '0021: the command centre chat runs on the regular tier');
  end if;
  select * into v from one.settings where key = 'retention';
  if found and not (v.value ? 'chat_days') then
    perform one.settings_put('retention', v.value || '{"chat_days": 90}'::jsonb, v.actor, '0021: conversations are kept 90 days');
  end if;
end $$;

-- one.ai_tool (0018) also answers a chat turn: the same read-only transaction and the same redaction.
create or replace function one.ai_tool(p_task bigint, p_holder text, p_name text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_started timestamptz := clock_timestamp();
  v jsonb;
begin
  if not exists (select 1 from one.ai_tasks where id = p_task and status = 'claimed' and claimed_by = p_holder and kind in ('ask', 'chat')) then
    raise exception 'task % is not a question or chat turn held by this caller', p_task using errcode = '42501';
  end if;
  perform set_config('transaction_read_only', 'on', true);
  begin
    perform set_config('lock_timeout', '2s', true);
    v := jsonb_build_object('ok', true, 'data', one.ai_tool_data(p_name, p_args));
  exception
    when sqlstate '22023' or sqlstate 'P0002' or invalid_text_representation or numeric_value_out_of_range then
      v := jsonb_build_object('ok', false, 'error', left(sqlerrm, 200));
    when undefined_table or undefined_function or undefined_column or invalid_schema_name then
      v := jsonb_build_object('ok', false, 'error', 'not available on this database');
    when insufficient_privilege then
      v := jsonb_build_object('ok', false, 'error', 'needs a person''s own access in the app');
    when lock_not_available or query_canceled then
      v := jsonb_build_object('ok', false, 'error', 'the read took too long; try a smaller range');
    when others then
      v := jsonb_build_object('ok', false, 'error', left(sqlerrm, 200));
  end;
  perform set_config('search_path', '', true);
  return v || jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_started) * 1000));
end $$;

-- one.ai_claim (0018): a chat turn is never offered to the worker; one the app did not finish is failed, not re-queued.
create or replace function one.ai_claim(p_holder text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ai jsonb := coalesce(one.setting('ai'), '{}');
  v_cap numeric := coalesce((one.setting('ai') ->> 'daily_cap_inr')::numeric, 0);
  v_pct numeric := coalesce((one.setting('ai') ->> 'queue_non_triage_at_pct')::numeric, 80);
  v_all text[] := array['classify', 'triage', 'explain', 'brief', 'propose_fix', 'propose_feature', 'ask', 'test_author'];
  v_spent numeric;
  v_allowed text[];
  v_task one.ai_tasks;
  v_context jsonb;
begin
  if coalesce(p_holder, '') !~ '^[a-z0-9:._-]{3,80}$' then
    raise exception 'one.ai_claim: bad holder' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('one.ai_claim'));
  update one.ai_tasks set status = 'cancelled', error = 'older than ai.task_max_age_h', claimed_by = null
   where status in ('pending', 'deferred') and created_at < now() - make_interval(hours => coalesce((v_ai ->> 'task_max_age_h')::int, 48));
  update one.ai_tasks t set status = 'cancelled', error = 'a synthetic test incident is not analysed'
    from one.incidents i
   where t.incident_id = i.id and t.status in ('pending', 'deferred') and (i.check_id = 'ONE-SYNTH' or 'synthetic' = any (i.tags));
  -- A chat turn (0021) belongs to the app, never to the worker: one the app did not finish in 10 minutes is failed.
  update one.ai_tasks set status = 'failed', error = 'the chat turn did not finish'
   where kind = 'chat' and status = 'claimed' and claimed_at < now() - interval '10 minutes';
  update one.ai_tasks set status = case when attempts >= 3 then 'failed' else 'pending' end,
                          error = 'the worker stopped during this task', claimed_by = null
   where status = 'claimed' and kind <> 'chat' and claimed_at < now() - interval '10 minutes';
  if (select count(*) from one.ai_tasks where status = 'claimed' and kind <> 'chat') >= coalesce((v_ai ->> 'max_parallel')::int, 2) then
    return null;
  end if;
  v_spent := one.ai_spent_today();
  v_allowed := case when v_cap <= 0 or v_spent >= v_cap then '{}'::text[]
                    when v_spent >= v_cap * v_pct / 100 then array['classify', 'triage']
                    else v_all end;
  -- The reason is also the task's error, which the incident and Ask pages show.
  update one.ai_tasks
     set status = 'deferred', not_before = now() + interval '15 minutes',
         deferred_reason = case when cardinality(v_allowed) = 0
                                then format('budget (cap reached): today''s AI spend ₹%s has reached the cap ₹%s', round(v_spent, 2), v_cap)
                                else format('budget (over %s%%): today''s AI spend ₹%s is %s%% of the cap ₹%s, so only classify and triage run', v_pct,
                                            round(v_spent, 2), round(v_spent / v_cap * 100), v_cap) end
   where (status = 'pending' or (status = 'deferred' and coalesce(not_before, '-infinity') <= now()))
     and not (kind = any (v_allowed));
  update one.ai_tasks set error = deferred_reason where status = 'deferred' and deferred_reason like 'budget (%' and error is distinct from deferred_reason;
  for i in 1..5 loop
    select * into v_task from one.ai_tasks
     where (status = 'pending' or (status = 'deferred' and coalesce(not_before, '-infinity') <= now()))
       and kind = any (v_allowed)
     order by one.ai_priority(kind), id
     limit 1 for update skip locked;
    if not found then
      return null;
    end if;
    begin
      v_context := one.ai_context(v_task);
    exception
      -- OTHERS does not catch a cancelled statement: a statement timeout while one context is built must fail that
      -- task, or it would come first again every minute (review M3).
      when query_canceled then
        update one.ai_tasks set status = 'failed', error = 'building the data for this task took too long' where id = v_task.id;
        continue;
      when others then
        update one.ai_tasks set status = 'failed', error = left('could not build the data for this task: ' || sqlerrm, 300) where id = v_task.id;
        continue;
    end;
    update one.ai_tasks
       set status = 'claimed', claimed_by = p_holder, claimed_at = now(), attempts = attempts + 1, deferred_reason = null, not_before = null,
           -- A brief keeps the numbers it was written from (they become the brief's stats).
           input = case when kind = 'brief' then input || jsonb_build_object('stats', v_context -> 'stats') else input end
     where id = v_task.id returning * into v_task;
    return jsonb_build_object(
      'task', jsonb_build_object('id', v_task.id, 'kind', v_task.kind, 'input', v_task.input - 'stats', 'model_hint', v_task.model_hint,
                                 'attempts', v_task.attempts, 'incident_id', v_task.incident_id),
      'ai', v_ai,
      -- task_spent_inr: what earlier attempts of this task spent, so per_task_cap_inr holds across attempts (review M6).
      'budget', jsonb_build_object('spent_inr', v_spent, 'cap_inr', v_cap, 'remaining_inr', greatest(v_cap - v_spent, 0),
                                   'task_spent_inr', (select coalesce(sum(cost_inr), 0) from one.ai_calls where task_id = v_task.id)),
      'context', v_context);
  end loop;
  return null;
end $$;

-- one.retention (0020) also prunes conversations older than retention.chat_days.
create or replace function one.retention() returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_cfg jsonb := coalesce(one.setting('retention'), '{}');
  v_results integer;
  v_events integer;
  v_calls integer;
  v_ok integer;
  v_audit integer;
  v_chat integer;
begin
  -- The histories are append-only (D-085); this is the one step that may prune them.
  perform set_config('one.history_writer', 'on', true);
  -- Two tiers: ok results repeat the value before them and are kept ok_results_days (14); failures and errors stay
  -- results_days (90) for the incident pages and the comparisons (efficiency review 10).
  delete from one.results where status = 'ok' and ran_at < now() - make_interval(days => greatest(1, coalesce((v_cfg ->> 'ok_results_days')::int, 14)));
  get diagnostics v_ok = row_count;
  delete from one.results where ran_at < now() - make_interval(days => coalesce((v_cfg ->> 'results_days')::int, 90));
  get diagnostics v_results = row_count;
  -- The app's minute-by-minute report rows (one per tick) are kept 30 days; a person's audit rows are kept for good.
  delete from one.audit where action = 'app_report' and at < now() - interval '30 days';
  get diagnostics v_audit = row_count;
  delete from one.email_codes where created_at < now() - interval '7 days';
  delete from one.sign_in_log where at < now() - interval '365 days';
  delete from one.events where occurred_at < now() - make_interval(days => coalesce((v_cfg ->> 'events_days')::int, 180));
  get diagnostics v_events = row_count;
  delete from one.ai_calls where created_at < now() - make_interval(days => coalesce((v_cfg ->> 'ai_calls_days')::int, 365));
  get diagnostics v_calls = row_count;
  delete from one.runs where started_at < now() - interval '30 days';
  -- Conversations with the command centre (0021) and their actions go with their thread.
  delete from one.chat_threads where updated_at < now() - make_interval(days => coalesce((v_cfg ->> 'chat_days')::int, 90));
  get diagnostics v_chat = row_count;
  perform set_config('one.history_writer', 'off', true);
  return jsonb_build_object('results', v_results + v_ok, 'ok_results', v_ok, 'events', v_events, 'ai_calls', v_calls, 'audit', v_audit, 'chat_threads', v_chat);
end $$;

insert into one.api_grants (fn, role, why)
select f, 'authenticated', 'the command centre chat (0021)' from unnest(array[
  'one.ui_chat_threads(integer)', 'one.ui_chat_thread(bigint)', 'one.ui_chat_turn_start(bigint,text,text,text)',
  'one.ui_chat_turn_finish(bigint,text,jsonb,text,text)', 'one.ui_chat_action_propose(bigint,text,text,jsonb,text,text)',
  'one.ui_chat_action_decide(bigint,text,text)', 'one.ui_chat_action_result(bigint,boolean,jsonb,text)',
  'one.ui_chat_thread_archive(bigint,text)']) f
on conflict do nothing;
call one.apply_grants();
