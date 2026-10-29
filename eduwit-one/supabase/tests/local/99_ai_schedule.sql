-- The AI cost controls (migration 0026, D-099): the schedule's switches default to what it did before, each one turns
-- a use down or off when the owner sets it, and a builder proposal for Eduwit One's own settings is applied by the
-- owner's approval through one.settings_put (versioned, audited), never by an engineer's. Local cluster only.
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
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000d1"}', false)
$$;
create or replace function pg_temp.as_engineer() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000d2"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer() to authenticated;

truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in'), ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-000000000002');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-000000000002', 'email_code');
create temp table t_ai as select value from one.settings where key = 'ai';
-- Explanations and proposals wait on the clock: the test uses the seeded minutes (15 and 60) and moves incidents back.
select one.settings_put('ai', (select value from t_ai) || jsonb_build_object('schedule', ((select value from t_ai) -> 'schedule') - 'classify_new_incidents' - 'explain_severities' - 'explain_unacknowledged' - 'propose_fix_only_with_catalogue_fix'), 'test@eduwit.in', 'no switches set');

-- 1. The defaults: the schedule does what 0018 did -------------------------------------------------------------------
-- CAT-01 has a catalogue fix (FIX-CACHE-B2C); INF-05 has none. One P1, one P2, one P3.
select one.open_or_touch_incident('CAT-01', 'P2', '{"value": {"cache_at": null}}') as i_cat \gset
select one.open_or_touch_incident('INF-05', 'P1', '{"value": {"n": 1}}') as i_inf \gset
select one.open_or_touch_incident('CAT-04', 'P3', '{"value": {"n": 1}}') as i_p3 \gset
update one.incidents set opened_at = now() - interval '2 hours';
select one.ai_schedule() as s1 \gset
select pg_temp.ok((:'s1'::jsonb ->> 'classify')::int = 3 and (:'s1'::jsonb ->> 'explain')::int = 2 and (:'s1'::jsonb ->> 'propose_fix')::int = 2,
                  'without the switches set: every incident classified, the P1 and the P2 explained and given a fix proposal, the P3 neither: ' || :'s1');

-- 2. Each switch, set by the owner, turns one use down or off -------------------------------------------------------------
truncate one.ai_tasks restart identity cascade;
select one.settings_put('ai', jsonb_set((select value from one.settings where key = 'ai'), '{schedule,classify_new_incidents}', 'false'), 'test@eduwit.in', 'classify off');
select pg_temp.ok((one.ai_schedule() ->> 'classify')::int = 0, 'classify_new_incidents false: no classification task');
select pg_temp.ok((select count(*) from one.ai_tasks where kind = 'explain') = 2, 'the other uses are untouched by that switch');

truncate one.ai_tasks restart identity cascade;
select one.settings_put('ai', jsonb_set((select value from one.settings where key = 'ai'), '{schedule,explain_severities}', '["P1"]'), 'test@eduwit.in', 'explain P1 only');
select one.ai_schedule() as s2 \gset
select pg_temp.ok((:'s2'::jsonb ->> 'explain')::int = 1 and exists (select 1 from one.ai_tasks where idempotency_key = 'explain:' || :i_inf)
                  and not exists (select 1 from one.ai_tasks where idempotency_key = 'explain:' || :i_cat), 'explain_severities ["P1"]: the P2 is not explained');

truncate one.ai_tasks restart identity cascade;
truncate one.ai_tasks restart identity cascade;
select one.settings_put('ai', jsonb_set(jsonb_set((select value from one.settings where key = 'ai'), '{schedule,explain_severities}', '["P1", "P2"]'), '{schedule,explain_unacknowledged}', 'false'), 'test@eduwit.in', 'explain acknowledged only');
select pg_temp.ok((one.ai_schedule() ->> 'explain')::int = 0, 'explain_unacknowledged false: nothing explained while nobody has acknowledged');
select one.acknowledge_incident(:i_inf, 'connect@eduwit.in');
select one.ai_schedule() as s2b \gset
select pg_temp.ok((:'s2b'::jsonb ->> 'explain')::int = 1 and exists (select 1 from one.ai_tasks where idempotency_key = 'explain:' || :i_inf),
                  'the acknowledged incident is explained: ' || :'s2b' || ' / acked=' || coalesce((select acknowledged_at::text from one.incidents where id = :i_inf), 'null')
                  || ' / schedule=' || (one.setting('ai') -> 'schedule')::text || ' / tasks=' || (select coalesce(string_agg(idempotency_key, ','), '-') from one.ai_tasks));
-- A storm is always explained, whatever the switches.
select one.open_or_touch_incident('ONE-STORM', 'P1', '{"value": {"n": 12}}') as i_storm \gset
select pg_temp.ok(exists (select 1 from one.ai_tasks where idempotency_key = 'explain:' || :i_storm) or (one.ai_schedule() ->> 'explain')::int >= 1, 'a storm is explained regardless');
update one.incidents set resolved_at = now(), resolved_by = 'test', resolution = 'manual' where id = :i_storm;

truncate one.ai_tasks restart identity cascade;
select one.settings_put('ai', jsonb_set((select value from one.settings where key = 'ai'), '{schedule,propose_fix_only_with_catalogue_fix}', 'true'), 'test@eduwit.in', 'fix proposals only with a catalogue fix');
select one.ai_schedule() as s3 \gset
select pg_temp.ok((:'s3'::jsonb ->> 'propose_fix')::int = 1 and exists (select 1 from one.ai_tasks where idempotency_key = 'propose_fix:' || :i_cat)
                  and not exists (select 1 from one.ai_tasks where idempotency_key = 'propose_fix:' || :i_inf),
                  'propose_fix_only_with_catalogue_fix: CAT-01 (FIX-CACHE-B2C) gets a proposal, INF-05 does not: ' || :'s3');
-- A malformed switch falls back to the default instead of failing the tick.
select one.settings_put('ai', jsonb_set((select value from one.settings where key = 'ai'), '{schedule,explain_severities}', '"P1"'), 'test@eduwit.in', 'bad shape');
truncate one.ai_tasks restart identity cascade;
select one.acknowledge_incident(:i_cat, 'connect@eduwit.in');
select pg_temp.ok((one.ai_schedule() ->> 'explain')::int = 2, 'a switch of the wrong shape means the default');

-- 3. The seeded settings proposal: applied by the owner's approval, versioned, not by an engineer ------------------------
select one.settings_put('ai', (select value from t_ai), 'test@eduwit.in', 'restore');
insert into one.proposals (kind, app, title, rationale, evidence, change, risk, source, source_key)
values ('config', 'one', 'AI: explain incidents on the regular tier after 60 minutes; propose fixes after 180 minutes', 'test copy of the seeded proposal', '{}',
        '{"where": "Eduwit One: Settings → AI", "settings_patch": {"ai": {"routing": {"explain": "regular"}, "schedule": {"explain_after_min": 60, "propose_fix_after_min": 180}}}, "touches": ["versioned_settings"]}',
        'low', 'builder', 'builder:d099-ai-explain-tier-and-timings')
on conflict (source_key) do nothing;
select id as p_ai from one.proposals where source_key = 'builder:d099-ai-explain-tier-and-timings' \gset
select pg_temp.ok(one.proposal_sensitive('config', (select change from one.proposals where id = :p_ai)), 'a settings proposal is the owner''s to decide');
select (select version from one.settings where key = 'ai') as v_before \gset
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_proposal_decide($q$ || :p_ai || $q$, 'approve', 'looks fine')$q$) = '42501', 'an engineer cannot approve it');
select pg_temp.as_owner();
select one.ui_proposal_decide(:p_ai, 'approve', 'cheaper explanations', null, null, 'req-ai-1') as d1 \gset
select pg_temp.ok((:'d1'::jsonb #>> '{executed,executed}')::boolean and (:'d1'::jsonb #> '{executed,settings}') ? 'ai', 'the owner''s approval applies the patch: ' || :'d1');
reset role;
select pg_temp.ok((select status = 'applied' and decided_by = 'connect@eduwit.in' and applied_at is not null from one.proposals where id = :p_ai), 'the proposal is applied');
select pg_temp.ok((select value -> 'routing' ->> 'explain' = 'regular' and (value #>> '{schedule,explain_after_min}')::int = 60 and (value #>> '{schedule,propose_fix_after_min}')::int = 180
                     and value -> 'routing' ->> 'triage' = 'regular' and (value ->> 'daily_cap_inr')::numeric = ((select value from t_ai) ->> 'daily_cap_inr')::numeric
                     from one.settings where key = 'ai'), 'only the patched keys changed; the rest of the setting is as it was');
select pg_temp.ok((select version from one.settings where key = 'ai') = :v_before + 1
                  and exists (select 1 from one.settings_versions where key = 'ai' and version = :v_before + 1 and actor = 'connect@eduwit.in' and reason like 'proposal #' || :p_ai || ' approved%'),
                  'one new version under the approver''s name, naming the proposal');
select pg_temp.ok(exists (select 1 from one.audit where action = 'proposal.approve' and target = 'proposal:' || :p_ai and request_id = 'req-ai-1'), 'audited');
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_proposal_decide($q$ || :p_ai || $q$, 'approve')$q$) = 'P0002', 'applied once; not open any more');
reset role;
-- A patch naming a protected key or a missing key is refused, and nothing is applied.
insert into one.proposals (kind, app, title, rationale, change, risk, source, source_key)
values ('config', 'one', 'bad patch', 'test', '{"settings_patch": {"setup": {"items": {}}}}', 'low', 'builder', 'builder:test-bad-patch') returning id as p_bad \gset
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_proposal_decide($q$ || :p_bad || $q$, 'approve')$q$) = '22023', 'the setup settings cannot be patched by a proposal');
reset role;
select pg_temp.ok((select status = 'open' from one.proposals where id = :p_bad), 'and the proposal stays open');
-- A patch whose value the settings rules refuse is refused whole (settings_check inside settings_put).
update one.proposals set change = '{"settings_patch": {"ai": {"routing": {"explain": "opus"}}}}' where id = :p_bad;
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok(pg_temp.err($q$select one.ui_proposal_decide($q$ || :p_bad || $q$, 'approve')$q$) = '22023', 'a patch the settings rules refuse does not apply');
reset role;

-- 4. jsonb_deep_merge --------------------------------------------------------------------------------------------------
select pg_temp.ok(one.jsonb_deep_merge('{"a": {"x": 1, "y": [1, 2]}, "b": 2}', '{"a": {"y": [3], "z": true}, "c": null}') = '{"a": {"x": 1, "y": [3], "z": true}, "b": 2, "c": null}',
                  'objects merge key by key, arrays and scalars are replaced');
select pg_temp.ok(one.jsonb_deep_merge('{"a": 1}', '"s"') = '"s"' and one.jsonb_deep_merge('1', '{"a": 1}') = '{"a": 1}', 'a non-object on either side is replaced by the second');

select one.settings_put('ai', (select value from t_ai), 'test@eduwit.in', 'restore');
delete from one.proposals where source_key in ('builder:test-bad-patch');
select 'ai schedule tests passed' as result;
