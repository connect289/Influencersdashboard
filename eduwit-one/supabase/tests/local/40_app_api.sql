-- The app's database API (0008): tick state, batch report with per-item isolation and redaction, escalations without
-- phones, watchdog ages. Local test cluster only.
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

truncate public.w2_conversations;
insert into public.w2_conversations (phone, conversation_id, account_id, bot_paused, escalated_at)
values ('+910000000002', 4242, 1, true, now() - interval '1 hour'), ('+910000000003', 4243, 1, false, now());

-- 1. Tick state: the settings the probes read, the app-run checks, no setup evidence text --------------------------
set role service_role;
create temp table t_state as select one.app_tick_state() as s;
select pg_temp.ok((select s -> 'settings' ? 'hosts' and s -> 'settings' ? 'vercel' and not (s -> 'settings' ? 'setup') from t_state), 'state carries the probe settings only');
select pg_temp.ok((select (s #>> '{setup,vercel,status}') is not null and not (s -> 'setup' -> 'vercel' ? 'detail') from t_state), 'setup reduced to status');
select pg_temp.ok((select exists (select 1 from jsonb_array_elements(s -> 'checks') c where c ->> 'id' = 'WEB-02') from t_state), 'app-run checks listed');

-- 2. Report: heartbeats and results applied one by one; a bad item is refused alone; values are redacted ------------
create temp table t_rep as select one.app_report($j${
  "heartbeats": [{"component": "website", "ok": true, "detail": {"status": 200, "contact": {"email": "x@example.com"}}, "expected_interval_s": 60},
                 {"component": "BAD COMPONENT", "ok": true}],
  "results": [{"check_id": "WEB-02", "status": "ok", "value": {"status": 200}, "duration_ms": 120},
              {"check_id": "WITTY-02", "status": "fail", "value": {}},
              {"check_id": "WEB-07", "status": "weird"}]}$j$::jsonb, 'app:test', 'req-1') as r;
select pg_temp.ok((select r #>> '{heartbeats,website}' = 'ok' and r #>> '{heartbeats,BAD COMPONENT}' <> 'ok' from t_rep), 'good heartbeat applied, bad one refused: ' || (select r::text from t_rep));
select pg_temp.ok((select r #>> '{results,WEB-02}' = 'none' and r #>> '{results,WITTY-02}' like 'refused%' and r #>> '{results,WEB-07}' like 'refused%' from t_rep),
                  'enabled check accepted; disabled check and bad status refused');
reset role;
select pg_temp.ok((select detail::text !~ 'example.com' from one.heartbeats where component = 'website'), 'heartbeat detail redacted');
select pg_temp.ok(exists (select 1 from one.audit where action = 'app_report' and request_id = 'req-1'), 'the write is audited');

-- 3. Escalations: conversation ids only, never the phone -----------------------------------------------------------
set role service_role;
select pg_temp.ok((select count(*) = 1 and bool_and(conversation_id = 4242) from one.witty_escalations()), 'only paused, escalated conversations');
select pg_temp.ok((select row_to_json(e)::text !~ '910000' from one.witty_escalations() e limit 1), 'no phone in the result');

-- 4. Watchdog ages, and the API roles cannot reach any of it ---------------------------------------------------------
select pg_temp.ok((select one.watchdog() ? 'tick_age_s'), 'watchdog reports the tick age');
reset role;
select pg_temp.ok(not has_function_privilege('anon', 'one.app_report(jsonb, text, text)', 'EXECUTE')
                  and not has_function_privilege('authenticated', 'one.witty_escalations(integer)', 'EXECUTE'), 'API roles cannot call the app functions');
