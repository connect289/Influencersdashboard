-- M26 Claude optimiser (Advisory) on STAGING, rolled back. No call to Anthropic: the worker's side is played by SQL.
-- Fixture: 40 matured commission-first decisions in zzm26|PG|Online. A (₹12,000) won 32 with probability 0.8, 8 enrolled;
-- B (₹10,000) won 8 through the exploration lane with probability 0.2, 4 enrolled. Logged NCPL = (96,000 + 40,000) / 40
-- = ₹3,400. With exploration at 50% both get 0.5, so the inverse-propensity estimate is (0.625 x 96,000 + 2.5 x 40,000)
-- / 40 = ₹4,000, a difference of ₹600. Then: the worker API (keys, claim, tools, finish, fail), validation and bounds,
-- pricing and the daily budget, approve (with an edit) / reject / expiry / rollback, rule and pause drafts, the holdout
-- ignoring AI changes, the scheduler, the reads and access. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000f6","role":"authenticated","aal":"aal2","email":"m26-admin@test.local"}', true)
$f$;
create function pg_temp.kept() returns jsonb language sql as $f$
  select jsonb_build_array(
    jsonb_build_object('partner_id', pg_temp.v('A')::bigint, 'name', 'M26 Alpha', 'cpe', 12000, 'has_rate', true, 'segment_leads', 5, 'leads_week', 0),
    jsonb_build_object('partner_id', pg_temp.v('B')::bigint, 'name', 'M26 Beta', 'cpe', 10000, 'has_rate', true, 'segment_leads', 5, 'leads_week', 0));
$f$;

insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000f6', 'm26-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000f6', 'm26-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000f7', 'nobody26@test.local', 'authenticated', 'authenticated');
insert into b2b.api_keys (name, scopes, key_prefix, key_hash) values ('m26 worker', '{ai_worker}', 'eb2b_m26test', encode(extensions.digest('eb2b_m26test_key_0001', 'sha256'), 'hex'));
insert into b2b.api_keys (name, scopes, key_prefix, key_hash) values ('m26 other', '{intake}', 'eb2b_m26othr', encode(extensions.digest('eb2b_m26othr_key_0001', 'sha256'), 'hex'));
update b2b.settings set value = value || '{"maturity_days":60,"min_matured_leads":30,"exploration_share":0.2,"min_learning_leads":30,"kill_switch":false}' where key = 'engine';
update b2b.settings set value = value || '{"holdout_share":0,"segments":{},"partner_weights":{},"kill_segments":[],"ai":{}}' where key = 'engine_policy';
update b2b.settings set value = value || '{"enabled":false,"daily_budget_usd":1,"worker_url":null}' where key = 'ai';
update b2b.ai_runs set status = 'skipped' where status in ('queued', 'running');
update b2b.ai_recommendations set status = 'superseded' where status = 'open';

with x as (insert into b2b.partners (slug, name, status) values ('m26-alpha', 'M26 Alpha', 'active') returning id) insert into t select 'A', id::text from x;
with x as (insert into b2b.partners (slug, name, status) values ('m26-beta', 'M26 Beta', 'active') returning id) insert into t select 'B', id::text from x;
do $x$ begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', '919876505201', 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'AI Test', 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online', 'source', 'website')));
end $x$;
insert into t select 'L', id::text from public.student_leads where whatsapp_number = '919876505201';

do $x$
declare i int; v_d bigint; v_a bigint; v_win bigint; v_p numeric; v_cpe numeric; v_y boolean;
begin
  for i in 1 .. 40 loop
    if i <= 32 then v_win := pg_temp.v('A')::bigint; v_p := 0.8; v_cpe := 12000; v_y := i <= 8;
    else v_win := pg_temp.v('B')::bigint; v_p := 0.2; v_cpe := 10000; v_y := i <= 36; end if;
    insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, candidates, seed,
                                      selection_probability, scoring_mode, holdout, is_test, actor_type, created_at)
    values (pg_temp.v('L')::bigint, i, 'zzm26|PG|Online', '{}', case when i <= 32 then 'commission_first' else 'exploration' end, 'partner', v_win,
            (select jsonb_agg(c || '{"eligible":true}') from jsonb_array_elements(pg_temp.kept()) c), 0.5, v_p, 'commission_first', false, false, 'engine',
            now() - interval '80 days')
    returning id into v_d;
    insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, engine_decision_id, cpe_net_inr, accepted_at, created_at, is_test)
    values (pg_temp.v('L')::bigint, i, 'zzm26|PG|Online', 'partner', v_win, 'closed', case when i <= 32 then 'commission_first' else 'exploration' end,
            v_d, v_cpe, now() - interval '79 days', now() - interval '80 days', false)
    returning id into v_a;
    if v_y then
      insert into public.enrollments (lead_id, cycle_no, partner_id, allocation_id, status, source_product, enrolled_on)
      values (pg_temp.v('L')::bigint, i, v_win, v_a, 'verified', 'b2b', (now() - interval '50 days')::date);
    end if;
  end loop;
end $x$;

-- ---------- simulation ----------
insert into t select 'sim', b2b.ai_simulate('{"lever":"exploration_share","segment":"zzm26|PG|Online","value":0.5}', 120)::text;
insert into r select 'sim_hand_computed', (x ->> 'decisions')::int = 40 and (x ->> 'ncpl_now')::numeric = 3400 and (x ->> 'ncpl_new')::numeric = 4000
                     and (x ->> 'difference')::numeric = 600 and (x -> 'ci95' ->> 0)::numeric < 600 and (x -> 'ci95' ->> 1)::numeric > 600 and (x ->> 'enough')::boolean, x::text
  from (select pg_temp.v('sim')::jsonb x) z;
insert into r select 'sim_no_change_is_neutral', (x ->> 'difference')::numeric = 0, x ->> 'difference'
  from (select b2b.ai_simulate('{"lever":"exploration_share","segment":"zzm26|PG|Online","value":0.2}', 120) x) z;
insert into r select 'sim_other_segment_untouched', (x ->> 'difference')::numeric = 0, x ->> 'difference'
  from (select b2b.ai_simulate('{"lever":"exploration_share","segment":"other|PG|Online","value":0.5}', 120) x) z;
insert into r select 'sim_unreplayable_lever', not (x ->> 'simulated')::boolean, x ->> 'why'
  from (select b2b.ai_simulate('{"lever":"maturity_days","value":45}', 90) x) z;

-- ---------- bounds ----------
do $x$ declare e text; begin
  begin perform b2b.ai_validate_change('{"lever":"maturity_days","value":100}'); e := 'ok'; exception when others then e := sqlerrm; end;
  insert into r values ('bounds_maturity', e = 'maturity is 30 to 90 days for the AI', e);
  begin perform b2b.ai_validate_change(jsonb_build_object('lever', 'segment_pin', 'segment', 'zzm26|PG|Online', 'value', 'performance', 'until', now() + interval '40 days')); e := 'ok'; exception when others then e := sqlerrm; end;
  insert into r values ('bounds_pin_30_days', e = 'an AI pin expires within 30 days', e);
  begin perform b2b.ai_validate_change('{"lever":"commission_rate","value":20}'); e := 'ok'; exception when others then e := sqlerrm; end;
  insert into r values ('bounds_no_other_levers', e = 'outside the AI''s bounds: commission_rate', e);
  begin perform b2b.ai_validate_change(jsonb_build_object('lever', 'partner_weight', 'partner_id', pg_temp.v('A')::bigint, 'value', 1.3)); e := 'ok'; exception when others then e := sqlerrm; end;
  insert into r values ('bounds_weight', e = 'a partner weight is 0.90 to 1.10', e);
end $x$;
insert into r select 'pin_defaults_30_days', (x ->> 'until')::timestamptz between now() + interval '29 days' and now() + interval '31 days', x::text
  from (select b2b.ai_validate_change('{"lever":"segment_pin","segment":"zzm26|PG|Online","value":"performance"}') x) z;

-- ---------- worker API ----------
insert into r select 'claim_needs_worker_key', (b2b.api_ai_claim('eb2b_m26othr_key_0001') ->> 'status')::int = 401 and (b2b.api_ai_claim('nope') ->> 'status')::int = 401, null;
insert into r select 'claim_when_off', b2b.api_ai_claim('eb2b_m26test_key_0001', '{"has_anthropic_key":true}') -> 'result' ->> 'why' = 'the optimiser is off', null;
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; begin
  begin perform b2b.ai_run_now('optimise', 'm26 test'); e := 'queued'; exception when others then e := sqlerrm; end;
  insert into r values ('run_now_needs_on', e = 'turn the optimiser on first (AI settings)', e);
  perform b2b.ai_settings_save('{"enabled":true,"daily_budget_usd":1}', 'm26 test: on');
  begin perform b2b.ai_settings_save('{"mode":"autopilot"}', 'm26 test'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('autopilot_not_yet', e = 'only Advisory mode is available until Autopilot is built', e);
  begin perform b2b.ai_settings_save('{"worker_url":"http://x.test"}', 'm26 test'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('worker_url_https', e = 'the worker address starts with https://', e);
end $x$;
insert into t select 'R1', (b2b.ai_run_now('optimise', 'm26 test: first run') ->> 'id');
reset role;
insert into t select 'c1', b2b.api_ai_claim('eb2b_m26test_key_0001', '{"has_anthropic_key":true}')::text;
insert into r select 'claim_running', x -> 'result' -> 'run' ->> 'id' = pg_temp.v('R1') and x -> 'result' -> 'price_per_mtok' ? 'in'
                     and (select status from b2b.ai_runs where id = pg_temp.v('R1')::bigint) = 'running'
                     and (select value ->> 'has_anthropic_key' from b2b.ai_state where key = 'worker') = 'true', x::text
  from (select pg_temp.v('c1')::jsonb x) z;
insert into r select 'claim_nothing_more', b2b.api_ai_claim('eb2b_m26test_key_0001') -> 'result' -> 'run' = 'null'::jsonb, null;
insert into r select 'tool_scorecards', x -> 'result' ->> 'call_no' = '1' and x -> 'result' -> 'output' ? 'segments', left(x::text, 200)
  from (select b2b.api_ai_tool('eb2b_m26test_key_0001', pg_temp.v('R1')::bigint, 'segment_scorecards', '{}') x) z;
insert into r select 'tool_simulation', (x -> 'result' -> 'output' ->> 'difference')::numeric = 600, x -> 'result' -> 'output' ->> 'difference'
  from (select b2b.api_ai_tool('eb2b_m26test_key_0001', pg_temp.v('R1')::bigint, 'run_simulation',
               '{"change":{"lever":"exploration_share","segment":"zzm26|PG|Online","value":0.5},"days":120}') x) z;
insert into r select 'decisions_pseudonymous', not (x::text ~ '"lead_id"') and x::text ~ '"lead": "L-[0-9a-f]{8}"', left(x::text, 200)
  from (select b2b.api_ai_tool('eb2b_m26test_key_0001', pg_temp.v('R1')::bigint, 'recent_decisions', '{"segment":"zzm26|PG|Online","limit":3}') x) z;
insert into r select 'unknown_tool_answered', x -> 'result' -> 'output' ->> 'error' = 'unknown tool drop_everything', null
  from (select b2b.api_ai_tool('eb2b_m26test_key_0001', pg_temp.v('R1')::bigint, 'drop_everything', '{}') x) z;
insert into r select 'tool_log', jsonb_array_length(tool_calls) = 4 and (select count(*) from b2b.ai_tool_outputs where run_id = pg_temp.v('R1')::bigint) = 4, null
  from b2b.ai_runs where id = pg_temp.v('R1')::bigint;

insert into t select 'f1', b2b.api_ai_finish('eb2b_m26test_key_0001', pg_temp.v('R1')::bigint, jsonb_build_object(
  'narrative', 'B converts better.', 'prompt_version', 'test', 'input_hash', 'abc',
  'usage', '{"in":200000,"out":10000}'::jsonb, 'validation', '{"ok":true,"checked":3,"unverified":[]}'::jsonb,
  'output', jsonb_build_object('summary', 'B converts better.', 'findings', '[]'::jsonb, 'recommendations', jsonb_build_array(
    jsonb_build_object('title', 'Explore more in MBA PG Online', 'rationale', 'B enrols half its leads.', 'risk', 'Small sample.',
                       'evidence', '[{"tool":"run_simulation","metric":"difference","value":600}]'::jsonb,
                       'change', '{"lever":"exploration_share","segment":"zzm26|PG|Online","value":0.5}'::jsonb),
    jsonb_build_object('title', 'Raise the rate', 'rationale', 'More money.', 'change', '{"lever":"commission_rate","value":25}'::jsonb),
    jsonb_build_object('title', 'Watch B', 'rationale', 'Observation only.'),
    jsonb_build_object('title', 'Draft: keep B for MBA', 'rationale', 'B converts.', 'change',
                       jsonb_build_object('lever', 'rule_draft', 'rule', jsonb_build_object('name', 'MBA to B (AI draft)', 'action', 'narrow', 'partner_ids', jsonb_build_array(pg_temp.v('B')::bigint),
                                                                                        'conditions', '{"course_keys":["zzm26"]}'::jsonb))),
    jsonb_build_object('title', 'Pause A', 'rationale', 'A converts poorly.', 'change', jsonb_build_object('lever', 'pause_draft', 'partner_id', pg_temp.v('A')::bigint, 'reason', 'low conversion'))))))::text;
insert into r select 'finish_files_inbox', jsonb_array_length(x -> 'result' -> 'recommendations') = 4 and jsonb_array_length(x -> 'result' -> 'rejected') = 1
                     and x -> 'result' -> 'rejected' -> 0 ->> 'why' = 'outside the AI''s bounds: commission_rate', x::text
  from (select pg_temp.v('f1')::jsonb x) z;
insert into r select 'priced', r2.cost_usd = round((200000 * 3 + 10000 * 15) / 1000000.0, 4) and r2.status = 'done', r2.cost_usd::text
  from b2b.ai_runs r2 where r2.id = pg_temp.v('R1')::bigint;
insert into r select 'simulation_attached', (x.simulation ->> 'difference')::numeric = 600 and x.kind = 'setting_change' and x.expires_at > now() + interval '6 days', x.simulation::text
  from b2b.ai_recommendations x where x.run_id = pg_temp.v('R1')::bigint and x.title = 'Explore more in MBA PG Online';
insert into r select 'kinds', string_agg(kind, ',' order by id) = 'setting_change,insight,rule_draft,pause_draft', string_agg(kind, ',' order by id)
  from b2b.ai_recommendations where run_id = pg_temp.v('R1')::bigint;
insert into t select 'rec_x', id::text from b2b.ai_recommendations where run_id = pg_temp.v('R1')::bigint and kind = 'setting_change';
insert into t select 'rec_rule', id::text from b2b.ai_recommendations where run_id = pg_temp.v('R1')::bigint and kind = 'rule_draft';
insert into t select 'rec_pause', id::text from b2b.ai_recommendations where run_id = pg_temp.v('R1')::bigint and kind = 'pause_draft';
insert into t select 'rec_ins', id::text from b2b.ai_recommendations where run_id = pg_temp.v('R1')::bigint and kind = 'insight';

-- a report whose numbers did not validate is filed as rejected, with nothing in the inbox
update b2b.settings set value = value || '{"daily_budget_usd":100}' where key = 'ai';
insert into t select 'R2', b2b.ai_queue('manual', 'deep_review', '{}')::text;
select b2b.api_ai_claim('eb2b_m26test_key_0001');
-- (a check in the same statement as the call would not see the call's own changes, so the answer is kept first)
insert into t select 'f2', b2b.api_ai_finish('eb2b_m26test_key_0001', pg_temp.v('R2')::bigint, jsonb_build_object('narrative', 'Uplift is 12%.',
          'output', '{"summary":"Uplift is 12%.","findings":[],"recommendations":[{"title":"x","rationale":"y","change":{"lever":"prior_weight","value":10}}]}'::jsonb,
          'usage', '{"in":1000,"out":100}'::jsonb, 'validation', '{"ok":false,"unverified":["12%"]}'::jsonb))::text;
insert into r select 'unvalidated_rejected', x -> 'result' ->> 'status' = 'rejected' and jsonb_array_length(x -> 'result' -> 'recommendations') = 0
                     and (select error from b2b.ai_runs where id = pg_temp.v('R2')::bigint) like 'the validator found numbers%', x::text
  from (select pg_temp.v('f2')::jsonb x) z;
-- a failed run is logged and alerts
insert into t select 'R3', b2b.ai_queue('manual', 'weekly_report', '{}')::text;
select b2b.api_ai_claim('eb2b_m26test_key_0001');
select b2b.api_ai_fail('eb2b_m26test_key_0001', pg_temp.v('R3')::bigint, 'Anthropic API: overloaded', '{"in":100,"out":0}');
insert into r select 'fail_logged', (select status from b2b.ai_runs where id = pg_temp.v('R3')::bigint) = 'failed'
                     and exists (select 1 from b2b.events where type = 'alert.ai_run_failed' and payload ->> 'run_id' = pg_temp.v('R3')), null;
-- the daily budget: the first run cost $0.75, so with a $0.50 budget the next queued run is skipped
update b2b.settings set value = value || '{"daily_budget_usd":0.5}' where key = 'ai';
insert into t select 'R4', b2b.ai_queue('manual', 'light_check', '{}')::text;
insert into t select 'c4', b2b.api_ai_claim('eb2b_m26test_key_0001')::text;
insert into r select 'budget_stops_runs', pg_temp.v('c4')::jsonb -> 'result' ->> 'why' = 'daily budget reached'
                     and (select status from b2b.ai_runs where id = pg_temp.v('R4')::bigint) = 'skipped'
                     and exists (select 1 from b2b.events where type = 'alert.ai_budget'), null;
update b2b.settings set value = value || '{"daily_budget_usd":100}' where key = 'ai';

-- ---------- the inbox ----------
set local role authenticated;
select pg_temp.admin();
-- approve with an edit (0.5 -> 0.3)
select b2b.ai_recommendation_decide(pg_temp.v('rec_x')::bigint, 'approve', 'try a smaller step',
                                    '{"lever":"exploration_share","segment":"zzm26|PG|Online","value":0.3}');
reset role;
insert into r select 'applied_as_ai', (value -> 'segments' -> 'zzm26|PG|Online' -> 'exploration_share' ->> 'value')::numeric = 0.3
                     and value -> 'segments' -> 'zzm26|PG|Online' -> 'exploration_share' ->> 'source' = 'ai', value -> 'segments' ->> 'zzm26|PG|Online'
  from b2b.settings where key = 'engine_policy';
insert into r select 'applied_logged', x.status = 'applied' and (x.applied ->> 'edited')::boolean and x.applied ->> 'from' is null and x.check_due_at > now()
                     and exists (select 1 from b2b.settings_versions v where v.key = 'engine_policy' and v.reason like 'AI recommendation #' || x.id || ' (run #%) approved by m26-admin@test.local%'),
                     x.applied::text
  from b2b.ai_recommendations x where x.id = pg_temp.v('rec_x')::bigint;
-- AI-steered leads use it, holdout leads do not
insert into r select 'steered_uses_ai_change', (b2b.route_score(pg_temp.v('L')::bigint, 'zzm26|PG|Online', pg_temp.kept(), 0.4, false) ->> 'exploration_share')::numeric = 0.3, null;
-- the holdout share is capped at 50%; seed 0.31 draws 0.276 for the holdout, so it is held out
update b2b.settings set value = value || '{"holdout_share":0.5}' where key = 'engine_policy';
insert into r select 'holdout_ignores_ai_change', (x ->> 'holdout')::boolean and (x ->> 'exploration_share')::numeric = 0.2, x::text
  from (select b2b.route_score(pg_temp.v('L')::bigint, 'zzm26|PG|Online', pg_temp.kept(), 0.31, false) x) z;
update b2b.settings set value = value || '{"holdout_share":0}' where key = 'engine_policy';

set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; begin
  begin perform b2b.ai_recommendation_decide(pg_temp.v('rec_x')::bigint, 'approve', 'again'); e := 'ok'; exception when others then e := sqlerrm; end;
  insert into r values ('decided_once', e = 'this recommendation is applied', e);
  begin perform b2b.ai_recommendation_decide(pg_temp.v('rec_pause')::bigint, 'approve', 'x', '{"lever":"exploration_share","segment":"zzm26|PG|Online","value":0.1}'); e := 'ok'; exception when others then e := sqlerrm; end;
  insert into r values ('edit_keeps_lever', e = 'an edit keeps the same lever', e);
end $x$;
select b2b.ai_recommendation_rollback(pg_temp.v('rec_x')::bigint, 'm26 test: undo');
select b2b.ai_recommendation_decide(pg_temp.v('rec_rule')::bigint, 'approve', 'review it in Rules');
select b2b.ai_recommendation_decide(pg_temp.v('rec_pause')::bigint, 'approve', 'agreed');
select b2b.ai_recommendation_decide(pg_temp.v('rec_ins')::bigint, 'reject', 'not useful');
reset role;
insert into r select 'rolled_back', not coalesce((select value -> 'segments' -> 'zzm26|PG|Online' from b2b.settings where key = 'engine_policy') ? 'exploration_share', false)
                     and (select status from b2b.ai_recommendations where id = pg_temp.v('rec_x')::bigint) = 'rolled_back',
                     (select value -> 'segments' from b2b.settings where key = 'engine_policy')::text;
insert into r select 'rule_draft_inactive', not g.active and g.action = 'narrow' and g.partner_ids = array[pg_temp.v('B')::bigint], g.name
  from b2b.routing_rules g where g.name = 'MBA to B (AI draft)';
insert into r select 'pause_draft_paused', p.status = 'paused' and p.paused_reason like 'AI recommendation #%approved by m26-admin@test.local%', p.paused_reason
  from b2b.partners p where p.id = pg_temp.v('A')::bigint;
insert into r select 'rejected_kept', x.status = 'rejected' and x.decision_note = 'not useful', x.status from b2b.ai_recommendations x where x.id = pg_temp.v('rec_ins')::bigint;
-- expiry
insert into t select 'R5', b2b.ai_queue('manual', 'optimise', '{}')::text;
select b2b.api_ai_claim('eb2b_m26test_key_0001');
select b2b.api_ai_finish('eb2b_m26test_key_0001', pg_temp.v('R5')::bigint, '{"narrative":"x","output":{"summary":"x","findings":[],"recommendations":[{"title":"Prior","rationale":"r","change":{"lever":"prior_weight","value":10}}]},"usage":{},"validation":{"ok":true}}');
update b2b.ai_recommendations set expires_at = now() - interval '1 minute' where run_id = pg_temp.v('R5')::bigint;
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; begin
  begin perform b2b.ai_recommendation_decide((select id from b2b.ai_recommendations where run_id = pg_temp.v('R5')::bigint), 'approve', 'late'); e := 'ok'; exception when others then e := sqlerrm; end;
  insert into r values ('expired_refused', e = 'this recommendation has expired', e);
end $x$;
insert into r select 'overview', (x -> 'spend' ->> 'today_usd')::numeric >= 0.75 and jsonb_array_length(x -> 'runs') >= 4 and (x ->> 'worker_key')::boolean
                     and x -> 'uplift' -> 'steered' ? 'ncpl', (x -> 'spend')::text
  from (select b2b.ai_overview() x) z;
insert into r select 'run_detail', jsonb_array_length(x -> 'tool_outputs') = 4 and jsonb_array_length(x -> 'recommendations_rows') = 4, null
  from (select b2b.ai_run_detail(pg_temp.v('R1')::bigint) x) z;
reset role;

-- ---------- scheduler ----------
update b2b.ai_runs set status = 'done' where status in ('queued', 'running');
update b2b.ai_runs set created_at = now() - interval '1 hour' where kind = 'light_check' and created_at >= now() - interval '1 minute';
select b2b.log_event('alert.sla_breach', null, null, pg_temp.v('B')::bigint, '{"test":true}');
insert into t select 'tick', b2b.ai_schedule_tick()::text;
insert into r select 'schedule_light_on_alerts', exists (select 1 from b2b.ai_runs where kind = 'light_check' and status = 'queued' and trigger = 'light'), pg_temp.v('tick');
insert into r select 'schedule_one_per_kind', (select count(*) from b2b.ai_runs where status = 'queued' group by kind order by 1 desc limit 1) = 1
                     and (b2b.ai_schedule_tick() ->> 'queued')::int = 0, null;
insert into r select 'light_uses_quick_model', model = (select value -> 'models' ->> 'quick' from b2b.settings where key = 'ai'), model
  from b2b.ai_runs where kind = 'light_check' and status = 'queued';
update b2b.settings set value = value || '{"enabled":false}' where key = 'ai';
insert into r select 'schedule_off', b2b.ai_schedule_tick() = '{"enabled":false}'::jsonb, null;

-- ---------- access ----------
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000f7","role":"authenticated","aal":"aal2","email":"nobody26@test.local"}', true);
set local role authenticated;
do $x$ declare e text; begin
  begin perform b2b.ai_overview(); e := 'read'; exception when others then e := sqlstate; end;
  insert into r values ('non_admin_refused', e = '42501', e);
  begin perform b2b.ai_tool('alerts', '{}'); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('tools_not_callable', e = '42501', e);
end $x$;
reset role;
set local role anon;
insert into r select 'anon_worker_needs_key', (b2b.api_ai_claim('bad') ->> 'status')::int = 401, null;
reset role;

select name, ok, detail from r order by ok, name;
rollback;
