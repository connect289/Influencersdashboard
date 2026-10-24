-- The phase 4 reviews (docs/reviews/phase-4-ui.md, docs/reviews/phase-4-security.md): each fix, proven. The PostgREST
-- JWT is simulated with request.jwt.claims. Local test cluster only.
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
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text) to authenticated, service_role;
create or replace function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000d1"}', false)
$$;
create or replace function pg_temp.as_engineer() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000d2"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer() to authenticated;

truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
delete from one.trusted_devices; delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-000000000002');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');
insert into one.session_checks (session_id, user_id, method) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-000000000001', 'trusted_device'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-000000000002', 'email_code');
insert into one.trusted_devices (token_hash, user_id, expires_at) values ('e2e-hash', '00000000-0000-0000-0000-000000000001', now() + interval '30 days');
\ir ../../migrations/0013_seed_builder_proposals.sql
create temp table t_pii as select array(select jsonb_array_elements_text(value -> 'pii_columns')) as k from one.settings where key = 'events';

-- S1 / M6: an engineer cannot change where a credential, an alert or a sign-in code is sent ----------------------------------
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('vendors', '{"resend_api": "https://evil.test"}', 'reroute')$q$) = '42501', 'vendors are the owner''s');
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('app', '{"base_url": "https://evil.test"}', 'reroute')$q$) = '42501', 'app.base_url is the owner''s');
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('hosts', '{"n8n": "https://evil.test"}', 'reroute')$q$) = '42501', 'hosts are the owner''s');
select pg_temp.ok(pg_temp.err($q$select one.ui_settings_put('ai', '{"daily_cap_inr": 100000}', 'spend more')$q$) = '42501', 'the AI spend cap is the owner''s');
select pg_temp.ok((select bool_and((s ->> 'owner_only')::boolean = (s ->> 'key' not in ('thresholds', 'checks', 'tests', 'witty', 'analytics')))
                     from jsonb_each(one.ui_settings()) e, lateral (select e.value || jsonb_build_object('key', e.key) as s) x),
                  'the Settings page marks every other key owner-only');
reset role;

-- S2: phones in any grouping, in free text, as long numbers; more name keys; timestamps and epoch seconds stay -----------
select pg_temp.ok(one.redact('{"a": "981-112-2334", "b": "98111.22334", "c": "already in our CRM as 098111 22334 (Asha)", "d": 971501234567,
                               "e": "+971 50 123 4567", "f": "(+91) 98111-22334", "student": "Asha", "mobile_no": "x", "customer_name": "R"}',
                             (select k from t_pii))
                  = '{"a": "[phone]", "b": "[phone]", "c": "[phone]", "d": "[phone]", "e": "[phone]", "f": "[phone]"}',
                  'every phone shape the review found is masked, and the name keys are dropped: '
                  || one.redact('{"a": "981-112-2334", "b": "98111.22334", "c": "already in our CRM as 098111 22334 (Asha)", "d": 971501234567}', '{}')::text);
select pg_temp.ok(one.redact('{"at": "2026-10-23 10:00:00+05:30", "day": "2026-10-23", "t": "2026-10-23T04:30:00.123+00:00", "n": 1729700000, "ms": 1234,
                               "count": 12345, "v": "1.2.3", "job": "b2c-capacity", "run": 987654}', '{}')
                  = '{"at": "2026-10-23 10:00:00+05:30", "day": "2026-10-23", "t": "2026-10-23T04:30:00.123+00:00", "n": 1729700000, "ms": 1234,
                      "count": 12345, "v": "1.2.3", "job": "b2c-capacity", "run": 987654}',
                  'dates, times, epoch seconds, counts and versions stay');

-- S4: forgetting trusted browsers ends the other sessions they checked; the caller's own session stays ---------------------
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok((select (r ->> 'revoked')::int = 1 and (r ->> 'sessions_ended')::int = 1
                     from (select one.ui_devices_revoke('00000000-0000-0000-0000-000000000001') as r) x), 'one device forgotten, one other session ended');
reset role;
select pg_temp.ok(not exists (select 1 from one.session_checks where session_id = '00000000-0000-0000-0000-0000000000d3'), 'the other session must pass the second step again');
select pg_temp.ok(exists (select 1 from one.session_checks where session_id = '00000000-0000-0000-0000-0000000000d1'), 'the caller stays signed in');
set role authenticated;
select pg_temp.as_owner();
select one.ui_devices_revoke('00000000-0000-0000-0000-000000000002');
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err('select one.ui_shell()') = '42501', 'the owner signs an engineer out everywhere');
reset role;
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-000000000002', 'email_code');

-- S6 / M5: fix and config proposals, and anything touching security, are the owner's to approve --------------------------
select max(id) filter (where source_key = 'builder:d017-b2b-key-scopes') as p_key, max(id) filter (where source_key = 'builder:s13-influencer-auth-passwords') as p_pw,
       max(id) filter (where source_key = 'builder:d007-spark-subtick-errors') as p_cfg, max(id) filter (where source_key = 'builder:gap-witty-blocks-security-log') as p_feat,
       max(id) filter (where source_key = 'builder:gap-influencer-login-attempts') as p_snooze
  from one.proposals \gset
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err(format('select one.ui_proposal_decide(%s, ''approve'', ''ok'')', :p_key)) = '42501',
                  'replacing an API key is the owner''s (touches api_keys)');
select pg_temp.ok(pg_temp.err(format('select one.ui_proposal_decide(%s, ''approve'', ''ok'')', :p_pw)) = '42501',
                  'so are passwords (touches auth)');
select pg_temp.ok(pg_temp.err(format('select one.ui_proposal_decide(%s, ''approve'', ''ok'')', :p_cfg)) = '42501',
                  'and every config proposal');
select one.ui_proposal_create('fix', 'b2b', 'Pause the acme partner', 'It rejects every lead since this morning.',
                              '{"rpc": "b2b.partner_set_status", "args": {"slug": "acme", "status": "paused"}, "touches": []}', 'medium') ->> 'id' as p_fix \gset
select pg_temp.ok(pg_temp.err(format('select one.ui_proposal_decide(%s, ''approve'', ''ok'')', :p_fix)) = '42501',
                  'a fix cannot declare itself harmless (M5)');
select pg_temp.ok((one.ui_proposal_decide(:p_feat, 'approve', 'asked Witty') ->> 'ok')::boolean,
                  'the engineer approves a feature request that touches nothing sensitive');
reset role;

-- S7: switching off or downgrading a P1, security, integrity, money or consent check is the owner's ----------------------
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_check_update('WEB-03', '{"enabled": false}', 'noisy')$q$) = '42501', 'a P1 stays on unless the owner says');
select pg_temp.ok(pg_temp.err($q$select one.ui_check_update('PLAT-07', '{"severity": "P3"}', 'quieter')$q$) = '42501', 'a security check keeps its severity');
select pg_temp.ok(pg_temp.err($q$select one.ui_check_update('PLAT-08', '{"enabled": false}', 'quiet')$q$) = '42501', 'so does an integrity check');
select pg_temp.ok((one.ui_check_update('PLAT-07', '{"cadence_s": 7200}', 'every two hours is enough') ->> 'ok')::boolean, 'its cadence is still the engineer''s');
-- m5: a reason in any script switches a check off.
select pg_temp.ok((one.ui_check_update('WEB-05', '{"enabled": false}', 'शोर बहुत है') ->> 'ok')::boolean, 'a Hindi reason works');
select pg_temp.as_owner();
select pg_temp.ok((one.ui_check_update('PLAT-07', '{"enabled": false}', 'replaced by the advisor check') ->> 'ok')::boolean, 'the owner can');
reset role;
select pg_temp.ok((select disabled_reason = 'owner:switched-off' from one.checks where id = 'WEB-05'), 'with a readable reason code');
update one.checks set enabled = true, disabled_reason = null where id in ('WEB-05', 'PLAT-07');
update one.checks set cadence_s = 86400 where id = 'PLAT-07';

-- M2: a snooze ends, and the proposal is back in the queue ----------------------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select one.ui_proposal_decide(:p_snooze, 'snooze', 'next sprint', null, 1);
reset role;
update one.proposals set expires_at = now() - interval '1 minute' where source_key = 'builder:gap-influencer-login-attempts';
delete from one.runs where kind = 'nightly';
set role postgres;
select one.nightly();
reset role;
select pg_temp.ok((select status = 'open' and expires_at is null from one.proposals where source_key = 'builder:gap-influencer-login-attempts'),
                  'the snoozed proposal is open again, and a builder proposal still never expires');

-- M3 and m6: only the app records a validation; validating n8n leaves the checks that were never built off --------------
select pg_temp.ok(not has_function_privilege('authenticated', 'one.setup_validated(text,boolean,text,text,text)', 'execute'),
                  'a signed-in person cannot record a validation directly');
set role service_role;
select pg_temp.ok(pg_temp.err($q$select one.setup_validated('lightsail', null, null, 'eng@eduwit.in')$q$) = '22023', 'a validation needs a result');
select one.setup_validated('n8n_api', true, 'listed 18 workflows', 'eng@eduwit.in');
reset role;
select pg_temp.ok((select bool_and(not enabled and disabled_reason like 'blocked:%') from one.checks where id in ('HB-gemini', 'WITTY-09')),
                  'HB-gemini and WITTY-09 stay off (D-049)');

-- M1, M4, m1: the Witty panels plan and answer; names that are not personal data are kept ------------------------------
create table if not exists public.w2_learnings (id bigserial primary key, kind text, title text, confidence numeric, status text,
                                                created_at timestamptz default now());
create table if not exists public.w2_prompts (name text primary key, version int, updated_at timestamptz default now());
delete from public.w2_learnings; delete from public.w2_prompts; delete from public.w2_messages;
insert into public.w2_learnings (kind, title, confidence, status) values ('faq', 'Fees for MBA', 0.8, 'proposed'), ('faq', 'Old', 0.5, 'applied');
insert into public.w2_prompts (name, version) values ('reply', 7);
insert into public.w2_messages (phone, direction, reply_source, latency_ms) values ('+919811122334', 'out', 'model', 1200), ('+919811122334', 'out', 'faq', 300);
grant select on public.w2_learnings, public.w2_prompts to postgres;
set role authenticated;
select pg_temp.as_owner();
select pg_temp.ok((select (r ->> 'ok')::boolean and r #>> '{data,0,replies}' = '2' and r #>> '{data,0,by_source,faq}' = '1'
                     from (select one.ui_embed('witty.replies') as r) x), 'replies and latency answer (M1): ' || one.ui_embed('witty.replies')::text);
select pg_temp.ok((select jsonb_array_length(r -> 'data' -> 'waiting') = 1 from (select one.ui_embed('witty.learnings') as r) x),
                  'learnings waiting for a decision are listed (M4): ' || one.ui_embed('witty.learnings')::text);
select pg_temp.ok((select r #>> '{data,0,prompt}' = 'reply' from (select one.ui_embed('witty.prompts') as r) x), 'prompt names are kept (m1)');
select pg_temp.ok((select jsonb_typeof(m -> 'ms') = 'object' and m ? 'numbers' from (select one.ui_marketing(7) as m) x), 'Marketing times each section (m9)');
select pg_temp.ok((select (a #>> '{ms,funnel}') is not null from (select one.ui_analytics(7) as a) x), 'and Analytics');
select pg_temp.ok((one.me() ->> 'idle_hours')::numeric = 12, 'me() carries the idle limit (m7)');
reset role;
select pg_temp.ok((select bool_and(provolatile = 's') from pg_proc where oid in ('one.ui_embed(text)'::regprocedure, 'one.ui_marketing(integer)'::regprocedure,
                                                                                 'one.ui_analytics(integer)'::regprocedure)),
                  'the panel reads are STABLE, so PostgREST runs them read-only (m13)');

-- m8: saving the current value again is not a new version, and says so -----------------------------------------------------
select value::text as thr_now from one.settings where key = 'thresholds' \gset
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err(format('select one.ui_settings_put(%L, %L, %L)', 'thresholds', :'thr_now', 'same again')) = '22023', 'nothing changed, nothing saved');
reset role;

-- m12: settings the pages parse are checked on write ---------------------------------------------------------------------
select pg_temp.ok(pg_temp.err($q$select one.settings_check('analytics', '{"funnel": [{"key": "a", "match": [{"type": "x"}]}]}')$q$) = '22023', 'a funnel step needs a label');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('ai', '{"daily_cap_inr": "lots"}')$q$) = '22023', 'the AI cap is a number');
select pg_temp.ok(pg_temp.err($q$select one.settings_check('fixes', '{"observation_started_at": "next week"}')$q$) = '22023', 'the observation start is a time');
select pg_temp.ok(pg_temp.err(format('select one.settings_check(%L, %L)', 'analytics', (select value from one.settings where key = 'analytics'))) = 'ok', 'the seeded funnel passes');

truncate one.proposals restart identity cascade;
delete from one.trusted_devices; delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
delete from public.w2_learnings; delete from public.w2_prompts; delete from public.w2_messages;
