-- The AI worker's database side (migration 0018): the schedule and its rules, the budget gate at 80% and 100%, the
-- claim with its lease and parallel limit, the redacted context, what each kind may write, the morning brief email,
-- Ask's tools (held tasks only, read-only, redacted), the AI settings check and the role surface. Local cluster only.
\set ON_ERROR_STOP 1
-- The histories are append-only in production (D-085); this local test may rewrite them, as one.retention() does.
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

truncate one.ai_calls, one.brief_pins, one.briefs, one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes
  restart identity cascade;
delete from one.saved_views;
select value as ai_before from one.settings where key = 'ai' \gset
select value as alerts_before from one.settings where key = 'alerts' \gset

-- 1. The AI settings are checked on every write ---------------------------------------------------------------------
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"prices": {"m": {"input": "cheap", "output": 1}}}')$q$) = '22023', 'a price is a number');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"prices": {"m": {"input": 1}}}')$q$) = '22023', 'a price has input and output');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"prices": {"m": {"input": -1, "output": 1}}}')$q$) = '22023', 'a price is not negative');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"provider": {"quick": "gemini"}}')$q$) = '22023', 'Claude only: no provider to choose');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"models": {"quick": "gemini-3.6-flash"}}')$q$) = '22023', 'a model is a Claude model');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"refusal_fallback": "gpt-5"}')$q$) = '22023', 'so is the refusal fallback');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"effort": {"deep": "huge"}}')$q$) = '22023', 'an effort is a known level');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"schedule": {"brief_mail_at_ist": "8am"}}')$q$) = '22023', 'the mail time is HH:MM');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"max_parallel": 50}')$q$) = '22023', 'parallel workers are bounded');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"routing": {"propose_fix_high_risk": "opus"}}')$q$) = '22023', 'a route names a tier (review m1)');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"usd_inr": 0}')$q$) = '22023', 'the exchange rate is above 0');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"models": {"deep": "drop table x;"}}')$q$) = '22023', 'a model is a model name');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"fallback_when_model_missing": "best"}')$q$) = '22023', 'the fallback is a tier');
select pg_temp.ok(pg_temp.err(format('select one.settings_check(%L, %L)', 'ai', :'ai_before')) = 'ok', 'the seeded AI settings pass');

select one.settings_put('ai', (:'ai_before')::jsonb || '{"daily_cap_inr": 100, "queue_non_triage_at_pct": 80, "max_parallel": 2}'::jsonb, 'test');
select one.settings_put('alerts', jsonb_set((:'alerts_before')::jsonb, '{p1,email}', '["connect@eduwit.in"]'), 'test');

-- 2. The schedule: fixed rules, each task once ------------------------------------------------------------------------
select one.open_or_touch_incident('PLAT-04', 'P1', '{"value": {"bad_calls": 2, "phone": "9876543210", "contact": "priya@gmail.com", "note": "call 9876543210"}}') as p1 \gset
select one.open_or_touch_incident('ONE-01', 'P2', '{"value": {"tick_errors_10m": 1}}') as p2 \gset
select one.open_or_touch_incident('ONE-SYNTH', 'P2', '{"value": {"synthetic": true}}') as syn \gset
update one.incidents set tags = array['synthetic'] where id = :syn;
select pg_temp.ok((select count(*) from one.ai_tasks where kind = 'triage') = 3, 'opening routes, and routing queues a triage each');

select one.ai_schedule() as s1 \gset
select pg_temp.ok((:'s1'::jsonb ->> 'classify')::int = 2 and (:'s1'::jsonb ->> 'explain')::int = 0 and (:'s1'::jsonb ->> 'propose_fix')::int = 0,
                  'new incidents are classified (not the synthetic one); nothing is old enough to explain: ' || :'s1');
update one.incidents set opened_at = now() - interval '20 minutes' where id in (:p1, :p2, :syn);
select one.ai_schedule() as s2 \gset
select pg_temp.ok((:'s2'::jsonb ->> 'classify')::int = 0 and (:'s2'::jsonb ->> 'explain')::int = 2 and (:'s2'::jsonb ->> 'propose_fix')::int = 0,
                  'P1 and P2 open 15 minutes get an explanation, once: ' || :'s2');
update one.incidents set opened_at = now() - interval '70 minutes' where id in (:p1, :p2, :syn);
select one.ai_schedule() as s3 \gset
select pg_temp.ok((:'s3'::jsonb ->> 'propose_fix')::int = 2, 'after an hour, a fix proposal each: ' || :'s3');
select pg_temp.ok((select model_hint from one.ai_tasks where idempotency_key = 'propose_fix:' || :p1) = 'deep'
                  and (select model_hint from one.ai_tasks where idempotency_key = 'propose_fix:' || :p2) is null,
                  'a P1 fix is proposed on the deep tier, a P2 one on the routing table''s');
select pg_temp.ok(one.ai_schedule() = '{"classify": 0, "explain": 0, "propose_fix": 0, "test_author": 0}'::jsonb
                  or (one.ai_schedule() ->> 'propose_feature') is not null, 'a second pass queues nothing new');
select pg_temp.ok((one.ai_step() #>> '{ai,request}') = 'not_configured', 'the worker is called only once the app is configured');
select pg_temp.ok(one.tick_app_call() ? 'ai', 'the tick''s app call runs the AI step');

-- 3. The role surface -------------------------------------------------------------------------------------------------
set role authenticated;
select pg_temp.ok(pg_temp.err($q$select one.ai_claim('ui-a')$q$) = '42501', 'a signed-in person cannot claim AI work');
select pg_temp.ok(pg_temp.err($q$select one.ai_tool(1, 'ui-a', 'health', '{}')$q$) = '42501', 'nor call its tools');
reset role;
set role anon;
select pg_temp.ok(pg_temp.err($q$select one.ai_finish(1, 'x', '{}', '[]')$q$) = '42501', 'nor can anyone signed out');
reset role;

-- 4. The claim: most urgent first, synthetic work dropped, a lease, a parallel limit ----------------------------------
set role service_role;
select pg_temp.ok(pg_temp.err($q$select one.ai_claim('Bad Holder!')$q$) = '22023', 'a holder name is checked');
select one.ai_claim('worker-a') as c1 \gset
reset role;
select pg_temp.ok((:'c1'::jsonb #>> '{task,kind}') = 'triage' and (:'c1'::jsonb #>> '{task,incident_id}')::bigint = :p1,
                  'the oldest triage comes first: ' || left(:'c1', 200));
select (:'c1'::jsonb #>> '{task,id}')::bigint as t1 \gset
select pg_temp.ok((select status from one.ai_tasks t where t.incident_id = :syn and t.kind = 'triage') = 'cancelled',
                  'a synthetic test incident is never analysed');
select pg_temp.ok((:'c1'::jsonb #>> '{context,incident,check_id}') = 'PLAT-04' and (:'c1'::jsonb #> '{context,check,rule_sql}') = 'null'::jsonb
                  and jsonb_typeof(:'c1'::jsonb #> '{context,recent_results}') = 'array', 'the context holds the incident and its check, no rule for triage');
select pg_temp.ok(:'c1' !~ '9876543210' and :'c1' !~ 'priya@' and not ((:'c1'::jsonb #> '{context,incident,evidence,value}') ?| array['phone', 'note', 'contact']),
                  'the context carries no contact: ' || (:'c1'::jsonb #>> '{context,incident,evidence}'));
select pg_temp.ok((:'c1'::jsonb #>> '{budget,cap_inr}')::numeric = 100 and (:'c1'::jsonb #>> '{ai,daily_cap_inr}')::numeric = 100, 'with the budget and settings');
set role service_role;
select one.ai_claim('worker-b') as c2 \gset
select pg_temp.ok(one.ai_claim('worker-c') is null, 'at most max_parallel tasks run at once');
reset role;
select (:'c2'::jsonb #>> '{task,id}')::bigint as t2 \gset

-- 5. Finish: only the holder, once; the calls are kept; triage writes the summary -----------------------------------------
set role service_role;
select pg_temp.ok(pg_temp.err(format('select one.ai_finish(%s, %L, %L, %L)', :t1, 'worker-b', '{"summary": "x"}', '[]')) = '55000', 'only the holder finishes');
select pg_temp.ok(pg_temp.err(format('select one.ai_finish(%s, %L, %L, %L)', :t1, 'worker-a', '{"summary": "x"}',
                                     '[{"provider": "openai", "model": "x"}]')) = '22023', 'a malformed call record is refused');
select one.ai_finish(:t1, 'worker-a',
  '{"summary": "Two job calls from the database to the app failed with 500.", "likely_cause": "the app is down", "propose_fix": true, "meta": {"model": "claude-sonnet-5-5", "tier": "regular", "prompt_version": "triage@abc"}}',
  '[{"provider": "anthropic", "model": "claude-sonnet-5-5", "purpose": "triage", "prompt_version": "triage@abc", "input_tokens": 1200, "output_tokens": 300, "cache_read": 0, "cost_usd": 0.0054, "cost_inr": 0.46, "latency_ms": 2100, "ok": true}]');
select pg_temp.ok(pg_temp.err(format('select one.ai_finish(%s, %L, %L, %L)', :t1, 'worker-a', '{}', '[]')) = '55000', 'a task finishes once');
reset role;
select pg_temp.ok((select summary from one.incidents where id = :p1) = 'Two job calls from the database to the app failed with 500.', 'triage writes the summary');
select pg_temp.ok((select count(*) from one.ai_calls where task_id = :t1 and cost_inr = 0.46 and model = 'claude-sonnet-5-5') = 1, 'its call is recorded');
select pg_temp.ok((select count(*) from one.ai_tasks where idempotency_key = 'propose_fix:' || :p1) = 1, 'a fix asked for by triage is queued once');
select pg_temp.ok((select status = 'done' and claimed_by is null from one.ai_tasks where id = :t1), 'the task is done');

-- 6. Fail and defer ---------------------------------------------------------------------------------------------------
set role service_role;
select pg_temp.ok(one.ai_fail(:t2, 'worker-b', 'anthropic: rate limited (429)', '[{"provider": "anthropic", "model": "claude-sonnet-5-5", "ok": false, "error": "429"}]', true) = 'pending',
                  'a retryable failure goes back to the queue');
reset role;
select pg_temp.ok((select status = 'deferred' and not_before between now() + interval '110 seconds' and now() + interval '130 seconds'
                          and deferred_reason like 'retry: %429%' from one.ai_tasks where id = :t2),
                  'after a 2-minute wait, not at once (review M5)');
update one.ai_tasks set attempts = 3, status = 'claimed', claimed_by = 'worker-b' where id = :t2;
set role service_role;
select pg_temp.ok(one.ai_fail(:t2, 'worker-b', 'still rate limited', null, true) = 'failed', 'the third attempt is final');
reset role;
select pg_temp.ok((select count(*) from one.ai_calls where task_id = :t2 and not ok) = 1, 'failed calls count too');

-- 7. The budget gate: at 80% only classify and triage run, at 100% nothing --------------------------------------------
insert into one.ai_calls (provider, model, purpose, cost_inr, ok) values ('anthropic', 'claude-opus-5-5', 'test', 85, true);
set role service_role;
select one.ai_claim('worker-a') as c3 \gset
reset role;
select pg_temp.ok((:'c3'::jsonb #>> '{task,kind}') in ('classify', 'triage'), 'at 85% of the cap a classify or triage still runs: ' || (:'c3'::jsonb #>> '{task,kind}'));
select pg_temp.ok((select count(*) from one.ai_tasks where status = 'deferred' and deferred_reason like 'budget (over 80%%only classify and triage run'
                     and kind in ('explain', 'propose_fix') and not_before > now()) = 4, 'explanations and fix proposals wait, saying why');
update one.ai_tasks set status = 'done', claimed_by = null where id = (:'c3'::jsonb #>> '{task,id}')::bigint;
insert into one.ai_calls (provider, model, purpose, cost_inr, ok) values ('anthropic', 'claude-opus-5-5', 'test', 20, true);
set role service_role;
select pg_temp.ok(one.ai_claim('worker-a') is null, 'at the cap nothing runs');
reset role;
select pg_temp.ok((select count(*) from one.ai_tasks where status = 'pending') = 0
                  and exists (select 1 from one.ai_tasks where deferred_reason like 'budget (cap reached)%'), 'everything waits at the cap');
-- ONE-01 fires at the cap (spec §11), and while work is held back because the cap is reached (review M1).
do $$
declare
  v_ok boolean;
  v_value jsonb;
begin
  execute (select sql from one.checks where id = 'ONE-01') into v_ok, v_value;
  if v_ok or (v_value ->> 'ai_held_at_cap')::int < 1 or (v_value ->> 'ai_spent_inr_today')::numeric < 100 then
    raise exception 'ASSERT FAILED: ONE-01 fires at the cap: %', v_value;
  end if;
end $$;

delete from one.ai_calls where purpose = 'test';
do $$
declare
  v_ok boolean;
  v_value jsonb;
begin
  execute (select sql from one.checks where id = 'ONE-01') into v_ok, v_value;
  if v_ok or (v_value ->> 'ai_spent_inr_today')::numeric >= 100 or (v_value ->> 'ai_held_at_cap')::int < 1 then
    raise exception 'ASSERT FAILED: below the cap, held-back work still fires ONE-01: %', v_value;
  end if;
end $$;
update one.ai_tasks set not_before = now() - interval '1 second' where status = 'deferred';

-- 8. A worker that died: its task is taken back; a stale task expires -------------------------------------------------
set role service_role;
select one.ai_claim('worker-a') as c4 \gset
reset role;
select (:'c4'::jsonb #>> '{task,id}')::bigint as t4 \gset
set role service_role;
select one.ai_calls_add(:t4, 'worker-a', '[{"provider": "anthropic", "model": "claude-haiku-4-5-20251001", "cost_inr": 3, "ok": true}]') as added \gset
select pg_temp.ok(pg_temp.err(format('select one.ai_calls_add(%s, %L, %L)', :t4, 'worker-b', '[]')) = '55000', 'only the holder records calls');
reset role;
select pg_temp.ok((:'added'::jsonb ->> 'remaining_inr')::numeric = 100 - 0.46 - 3, 'recording a call answers with today''s budget: ' || :'added');
update one.ai_tasks set claimed_at = now() - interval '11 minutes' where id = :t4;
insert into one.ai_tasks (kind, input, created_at, idempotency_key) values ('ask', '{"question": "old"}', now() - interval '3 days', 'ask:old');
set role service_role;
select one.ai_claim('worker-b') as c5 \gset
reset role;
select pg_temp.ok((:'c5'::jsonb #>> '{task,id}')::bigint = :t4 and (:'c5'::jsonb #>> '{task,attempts}')::int = 2, 'an abandoned task is claimed again');
select pg_temp.ok((:'c5'::jsonb #>> '{budget,task_spent_inr}')::numeric = 3, 'with what its earlier attempt spent (review M6)');
select pg_temp.ok((select status from one.ai_tasks where idempotency_key = 'ask:old') = 'cancelled', 'a task older than task_max_age_h is cancelled');
set role service_role;
select pg_temp.ok(one.ai_defer(:t4, 'worker-b', 'setup: no key for anthropic', 30) = 'deferred', 'a task without a key waits');
reset role;
select pg_temp.ok((select status = 'deferred' and attempts = 1 and not_before > now() + interval '29 minutes' and error = 'setup: no key for anthropic'
                      from one.ai_tasks where id = :t4), 'deferral is not an attempt, and the pages see why it waits');
update one.ai_tasks set not_before = now() - interval '1 second' where status = 'deferred';
update one.ai_tasks set status = 'cancelled' where status in ('pending', 'deferred') and kind in ('classify', 'triage');

-- 9. Explain and a fix proposal: the likely cause, an open proposal a person decides, risk never below the floor ------
set role service_role;
select one.ai_claim('worker-a') as c6 \gset
reset role;
select pg_temp.ok((:'c6'::jsonb #>> '{task,kind}') = 'explain' and (:'c6'::jsonb #>> '{context,check,rule_sql}') ~ 'with ids as',
                  'an explanation sees the check''s rule');
set role service_role;
select one.ai_finish((:'c6'::jsonb #>> '{task,id}')::bigint, 'worker-a', '{"explanation": "…", "likely_cause": "The app answered 500 to the tick.", "meta": {"model": "m"}}', '[]');
reset role;
select pg_temp.ok((select root_cause from one.incidents where id = (:'c6'::jsonb #>> '{task,incident_id}')::bigint) = 'The app answered 500 to the tick.', 'explain writes the likely cause');
update one.ai_tasks set status = 'cancelled' where status in ('pending', 'deferred') and kind = 'explain';
set role service_role;
select one.ai_claim('worker-a') as c7 \gset
reset role;
select pg_temp.ok((:'c7'::jsonb #>> '{task,kind}') = 'propose_fix' and (:'c7'::jsonb #>> '{task,incident_id}')::bigint = :p1, 'then the P1''s fix proposal');
set role service_role;
select one.ai_finish((:'c7'::jsonb #>> '{task,id}')::bigint, 'worker-a',
  '{"title": "Restart the app deployment", "rationale": "The tick''s calls fail with 500 since the last deploy.", "where": "Vercel eduwit-one", "owner_action": "Redeploy the last good build.", "steps": ["Open Vercel", "Redeploy"], "touches": [], "risk": "low", "uses_fix": null, "verify": "PLAT-04 passes", "meta": {"model": "claude-opus-5-5", "tier": "deep", "prompt_version": "propose_fix@1"}}', '[]');
reset role;
select pg_temp.ok((select kind = 'fix' and source = 'ai' and status = 'open' and risk = 'medium' and model = 'claude-opus-5-5' and incident_id = :p1
                          and evidence ->> 'written_by' = 'ai' and change ->> 'owner_action' = 'Redeploy the last good build.'
                     from one.proposals where source_key = 'ai:' || (:'c7'::jsonb #>> '{task,id}')), 'an open fix proposal, at least medium for a P1');
select pg_temp.ok(one.proposal_sensitive('fix', '{}'), 'and, being a fix, only the owner can approve it');

-- 10. Feature review and a test idea: proposals, at most three, apps checked --------------------------------------------
update one.ai_tasks set status = 'cancelled' where status in ('pending', 'deferred');
select one.enqueue_ai('propose_feature', '{"week": "2026-W43"}', null, 'propose_feature:local-test', null) as tf \gset
set role service_role;
select one.ai_claim('worker-a') as c8 \gset
select pg_temp.ok(jsonb_typeof(:'c8'::jsonb #> '{context,incidents_by_check}') = 'array' and (:'c8'::jsonb #> '{context,apps}') ? 'witty', 'the week''s context');
select pg_temp.ok(pg_temp.err(format('select one.ai_finish(%s, %L, %L, %L)', :tf, 'worker-a',
  '{"proposals": [{"app": "nowhere", "title": "A feature", "rationale": "Because it would help a lot."}]}', '[]')) = '23503', 'an unknown app is refused');
select one.ai_finish(:tf, 'worker-a', jsonb_build_object('proposals', (select jsonb_agg(jsonb_build_object('app', 'witty', 'kind', 'feature', 'title', 'Idea ' || g,
  'rationale', 'Witty timed out on twelve replies this week.', 'risk', 'low')) from generate_series(1, 5) g)), '[]');
reset role;
select pg_temp.ok((select count(*) from one.proposals where source = 'ai' and kind = 'feature' and source_key like 'ai:' || :tf || ':%') = 3, 'three proposals at most');
select pg_temp.ok((select bool_and(one.proposal_sensitive(kind, change)) and bool_and(change -> 'touches' ? 'ai_written')
                     from one.proposals where source = 'ai'), 'every AI proposal is the owner''s to approve, whatever it says it touches (review B1)');
select pg_temp.ok(one.ai_touches('["app_settings", "BAD; drop", 3]') = '["ai_written", "app_settings"]'::jsonb, 'a model''s touches are filtered and marked');

update one.incidents set resolved_at = now(), resolution = 'fixed', resolved_by = 'test' where id = :p2;
select one.ai_schedule() ->> 'test_author' as ta \gset
select pg_temp.ok(:ta = '1', 'a fixed incident gets a test idea');
set role service_role;
select one.ai_claim('worker-a') as c9 \gset
select pg_temp.ok((:'c9'::jsonb #>> '{task,kind}') = 'test_author' and jsonb_typeof(:'c9'::jsonb #> '{context,tests}') = 'array', 'with the existing tests');
select one.ai_finish((:'c9'::jsonb #>> '{task,id}')::bigint, 'worker-a',
  '{"needed": true, "rationale": "Nothing exercises the tick end to end.", "test": {"title": "The tick reaches the app", "app": "one", "steps": [{"title": "Tick", "expect": "200"}], "safety": "reads only"}, "meta": {"model": "m"}}', '[]');
reset role;
select pg_temp.ok((select title from one.proposals where incident_id = :p2 and source = 'ai') = 'Test: The tick reaches the app', 'a test proposal');

-- 11. The brief: its numbers kept, the nightly one mailed in the morning, a regenerated one not ------------------------
update one.ai_tasks set status = 'cancelled' where status in ('pending', 'deferred');
select ((now() at time zone 'Asia/Kolkata')::date)::text as today \gset
select one.enqueue_ai('brief', jsonb_build_object('for_date', :'today'), null, 'brief:' || :'today') as tb \gset
set role service_role;
select one.ai_claim('worker-a') as c10 \gset
reset role;
select pg_temp.ok(jsonb_typeof(:'c10'::jsonb #> '{context,stats,incidents_opened}') = 'array' and (:'c10'::jsonb #> '{context,stats}') ? 'pins'
                  and not ((:'c10'::jsonb #> '{task,input}') ? 'stats'), 'the brief''s numbers');
select pg_temp.ok((select input ? 'stats' from one.ai_tasks where id = :tb), 'kept on the task for the brief');
set role service_role;
select pg_temp.ok(pg_temp.err(format('select one.ai_finish(%s, %L, %L, %L)', :tb, 'worker-a', '{"body_md": "  "}', '[]')) = '22023', 'a brief needs its text');
select one.ai_finish(:tb, 'worker-a', '{"body_md": "# Brief\n\nAll quiet.", "meta": {"model": "claude-sonnet-5-5", "tier": "regular"}}',
  '[{"provider": "anthropic", "model": "claude-sonnet-5-5", "cost_usd": 0.02, "cost_inr": 1.7, "ok": true}]');
reset role;
select pg_temp.ok((select stats ? 'incidents_opened' and tier = 'regular' and cost_usd = 0.02 and task_id = :tb from one.briefs where for_date = :'today'::date),
                  'a brief with its stats and cost');
select pg_temp.ok((select count(*) from one.deliveries where kind = 'brief') = 1
                  and (select recipient = 'connect@eduwit.in' and brief_id is not null
                              and next_attempt_at >= ((:'today'::date + time '08:00')::timestamp at time zone 'Asia/Kolkata')
                              and next_attempt_at >= now() - interval '1 minute'
                         from one.deliveries where kind = 'brief'), 'one email to each P1 address, at 08:00 IST or now if later');
delete from one.deliveries where kind <> 'brief';
update one.deliveries set next_attempt_at = now() where kind = 'brief';
delete from one.saved_views;
insert into one.saved_views (page, name, params, schedule, created_by) values
  ('analytics', 'Daily funnel', '{"days": 7}', 'daily', 'a@eduwit.in'),
  ('marketing', 'Not mailed', '{"days": 30}', null, 'a@eduwit.in');
set role service_role;
select one.claim_deliveries(5) as d \gset
reset role;
select pg_temp.ok((:'d'::jsonb #>> '{0,kind}') = 'brief' and (:'d'::jsonb #>> '{0,brief,body_md}') like '# Brief%'
                  and (:'d'::jsonb #>> '{0,brief,views,0,name}') = 'Daily funnel' and jsonb_array_length(:'d'::jsonb #> '{0,brief,views}') = 1,
                  'the sender gets the brief''s text and the daily saved views: ' || left(:'d', 400));
set role service_role;
select one.finish_delivery((:'d'::jsonb #>> '{0,id}')::bigint, true, null, 'resend-1');
reset role;
select pg_temp.ok((select sent_at is not null from one.briefs where for_date = :'today'::date), 'and the brief is marked mailed');
select one.enqueue_ai('brief', jsonb_build_object('for_date', :'today', 'tier', 'deep', 'requested_by', 'a@eduwit.in'), 'deep', 'brief:regen') as tr \gset
set role service_role;
select one.ai_claim('worker-a') as c11 \gset
select one.ai_finish(:tr, 'worker-a', '{"body_md": "Again.", "meta": {"tier": "deep"}}', '[]');
reset role;
select pg_temp.ok((select count(*) from one.deliveries where kind = 'brief') = 1, 'a regenerated brief is not mailed');

-- 12. Ask's tools: only for the Ask its worker holds, read-only, redacted ---------------------------------------------
select one.enqueue_ai('ask', '{"question": "What is failing?", "asked_by": "a@eduwit.in"}', null, 'ask:1') as tq \gset
set role service_role;
select one.ai_claim('worker-a') as c12 \gset
select pg_temp.ok((:'c12'::jsonb #>> '{task,kind}') = 'ask' and (:'c12'::jsonb #>> '{context,question}') = 'What is failing?', 'an Ask with its question');
select pg_temp.ok(pg_temp.err(format('select one.ai_tool(%s, %L, %L, %L)', :tq, 'worker-b', 'health', '{}')) = '42501', 'only its holder');
select pg_temp.ok(pg_temp.err(format('select one.ai_tool(%s, %L, %L, %L)', :tb, 'worker-a', 'health', '{}')) = '42501', 'only for an Ask');
select one.ai_tool(:tq, 'worker-a', 'incidents', '{"status": "all", "since_hours": 48}') as inc \gset
select pg_temp.ok((:'inc'::jsonb ->> 'ok')::boolean and jsonb_array_length(:'inc'::jsonb -> 'data') = 2 and :'inc' !~ '9876543210' and :'inc' !~ 'priya@',
                  'incidents, without the synthetic one and without contacts: ' || left(:'inc', 300));
select one.ai_tool(:tq, 'worker-a', 'incident', jsonb_build_object('id', :p1)) as one_inc \gset
select pg_temp.ok((:'one_inc'::jsonb ->> 'ok')::boolean and :'one_inc' !~ '9876543210', 'one incident, redacted');
select pg_temp.ok((one.ai_tool(:tq, 'worker-a', 'drop_everything', '{}') ->> 'ok')::boolean is false, 'an unknown tool is an answer, not an error');
select pg_temp.ok((one.ai_tool(:tq, 'worker-a', 'witty', '{"panel": "../etc"}') ->> 'error') like 'panel is one of%', 'a panel is one of the list');
select pg_temp.ok((one.ai_tool(:tq, 'worker-a', 'check', '{"check_id": "NOPE-1"}') ->> 'error') like 'no check%', 'a missing check says so');
select pg_temp.ok((one.ai_tool(:tq, 'worker-a', 'health', '{}') #> '{data,one}') ? 'open_p1', 'health');
select pg_temp.ok((one.ai_tool(:tq, 'worker-a', 'ai_spend', '{"days": 3}') ->> 'ok')::boolean, 'AI spend');
select pg_temp.ok((one.ai_tool(:tq, 'worker-a', 'events', '{"since_hours": 9999, "bucket": "hour"}') ->> 'ok')::boolean, 'events, range bounded');
select pg_temp.ok((one.ai_tool(:tq, 'worker-a', 'analytics', '{"days": 7}') #> '{data}') ? 'funnel', 'analytics as data');
select pg_temp.ok((one.ai_tool(:tq, 'worker-a', 'tests', '{}') ->> 'ok')::boolean, 'tests');
select pg_temp.ok((one.ai_tool(:tq, 'worker-a', 'cron', '{}') ? 'ok'), 'cron');
reset role;
do $$
declare
  v_task bigint := (select id from one.ai_tasks where idempotency_key = 'ask:1');
begin
  perform one.ai_tool(v_task, 'worker-a', 'health', '{}');
  if current_setting('transaction_read_only') <> 'on' then
    raise exception 'ASSERT FAILED: a tool call leaves its transaction read-only';
  end if;
  begin
    insert into one.audit (actor, action, target) values ('x', 'x', 'x');
    raise exception 'ASSERT FAILED: a write after a tool call succeeded';
  exception when read_only_sql_transaction then null;
  end;
end $$;
set role service_role;
select one.ai_finish(:tq, 'worker-a', '{"answer": "PLAT-04 is failing.", "queries": [{"tool": "incidents", "args": {}, "rows": 2}]}', '[]');
reset role;

-- 13. Message excerpts: only for explain on a Witty incident, only when the owner allows them ---------------------------
select one.open_or_touch_incident('WITTY-02', 'P1', '{"value": {"stuck": 1}}') as wi \gset
insert into public.w2_messages (phone, direction, kind, content, created_at) values
  ('919812345678', 'out', 'reply', 'Hello Priya, your counsellor will call 9812345678', now()),
  ('910000123456', 'out', 'reply', 'harness text', now());
update one.ai_tasks set status = 'cancelled' where status in ('pending', 'deferred');
select one.enqueue_ai('explain', jsonb_build_object('incident_id', :wi), null, 'explain:w1', :wi) as tw \gset
set role service_role;
select one.ai_claim('worker-a') as c13 \gset
select one.ai_fail(:tw, 'worker-a', 'test', null, true);
reset role;
update one.ai_tasks set not_before = now() - interval '1 second' where id = :tw;
select pg_temp.ok(not ((:'c13'::jsonb -> 'context') ? 'messages'), 'no excerpts while ai.allow_message_excerpts is off');
select one.settings_put('ai', (select value from one.settings where key = 'ai') || '{"allow_message_excerpts": true}'::jsonb, 'test');
set role service_role;
select one.ai_claim('worker-a') as c14 \gset
select one.ai_fail(:tw, 'worker-a', 'test', null, false);
reset role;
select pg_temp.ok(jsonb_array_length(:'c14'::jsonb #> '{context,messages}') = 1 and not ((:'c14'::jsonb #> '{context,messages,0}') ? 'phone'),
                  'with them on: real traffic only, no phone (the app masks the text): ' || (:'c14'::jsonb #>> '{context,messages}'));
delete from public.w2_messages where content in ('Hello Priya, your counsellor will call 9812345678', 'harness text');

-- Leave the settings and tables as found.
select one.settings_put('ai', :'ai_before', 'test');
select one.settings_put('alerts', :'alerts_before', 'test');
truncate one.ai_calls, one.brief_pins, one.briefs, one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes
  restart identity cascade;
delete from one.saved_views;
