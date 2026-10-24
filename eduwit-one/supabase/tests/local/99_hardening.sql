-- Hardening (migration 0020, D-083): Ask's set-up and running tools: setup, app_status, fixes, actions and audit, each
-- read-only through one.ai_tool for the Ask its worker holds, redacted, and refusing a bad argument as data. Local
-- cluster only.
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
\echo passed 99_hardening.sql
