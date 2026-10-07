-- M25 per-lead model on STAGING, rolled back. 30 fixture leads (half WhatsApp, half website), each sent 4 times (cycles)
-- to two fixture partners 70 days ago: A enrols most WhatsApp leads and no website ones; B the reverse. Segment P̂ cannot
-- see that; the model's partner x source features can. Checks: the maths helpers, training (queued, trained by the tick,
-- shadow, holdout metrics beating segment P̂), the gate refusing promotion without logged-decision evidence, serving through
-- route_score (the challenger decides, holdout leads never), shadow scores, the champion check, rollback, the calibration
-- fallback with its alert, a failed training run, and access. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated","aal":"aal2","email":"m25-admin@test.local"}', true)
$f$;
create function pg_temp.kept() returns jsonb language sql as $f$
  select jsonb_build_array(
    jsonb_build_object('partner_id', pg_temp.v('A')::bigint, 'name', 'M25 Alpha', 'cpe', 10000, 'has_rate', true, 'segment_leads', 60, 'leads_week', 0),
    jsonb_build_object('partner_id', pg_temp.v('B')::bigint, 'name', 'M25 Beta', 'cpe', 10000, 'has_rate', true, 'segment_leads', 60, 'leads_week', 0));
$f$;

insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000e1', 'm25-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000e1', 'm25-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000e2', 'nobody25@test.local', 'authenticated', 'authenticated');
update b2b.settings set value = value || '{"maturity_days":60,"half_life_days":30,"prior_weight":20,"default_p_enroll":0.05,"min_matured_leads":5,"kill_switch":false}' where key = 'engine';
update b2b.settings set value = value || '{"holdout_share":0,"segments":{},"partner_weights":{},"kill_segments":[],"ai":{}}' where key = 'engine_policy';
update b2b.settings set value = value || '{"min_outcomes":100,"min_feature_rows":3,"valid_share":0.25,"iterations":150,"auto_train":false,"challenger_share":0.1,"ece_fallback":0.08}' where key = 'ml';
-- no model of the shared staging registry interferes (rolled back)
update b2b.ml_models set status = 'retired' where status in ('shadow', 'challenger', 'champion', 'training');

with x as (insert into b2b.partners (slug, name, status) values ('m25-alpha', 'M25 Alpha', 'active') returning id) insert into t select 'A', id::text from x;
with x as (insert into b2b.partners (slug, name, status) values ('m25-beta', 'M25 Beta', 'active') returning id) insert into t select 'B', id::text from x;

do $x$
declare i int; v_id bigint; c int; v_p bigint; v_a bigint; v_wa boolean; v_y boolean;
begin
  perform set_config('b2b.actor', 'engine', true);
  for i in 1 .. 30 loop
    v_wa := i % 2 = 0;
    perform public.lead_intake(jsonb_build_object('phone', '91987650' || lpad((5000 + i)::text, 4, '0'), 'source_system', 'crm', 'event_type', 'lead.created',
      'lead', jsonb_build_object('full_name', 'ML Test ' || i, 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                                 'state', 'Delhi', 'source', case when v_wa then 'whatsapp_direct' else 'website' end, 'consent_partner_share_at', now())));
    select id into v_id from public.student_leads where whatsapp_number = '91987650' || lpad((5000 + i)::text, 4, '0');
    update public.student_leads set lead_source = case when v_wa then 'whatsapp_direct' else 'website' end, channel = case when v_wa then 'whatsapp' else 'web' end
     where id = v_id;
    insert into t values ('L' || i, v_id::text);
    for c in 1 .. 4 loop
      v_p := case when c % 2 = 1 then pg_temp.v('A')::bigint else pg_temp.v('B')::bigint end;
      -- A enrols WhatsApp leads (3 of 4 of its WhatsApp allocations), B website leads; the other mix never enrols
      v_y := ((v_p = pg_temp.v('A')::bigint) = v_wa) and (i + c) % 4 <> 0;
      insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, accepted_at, created_at, is_test)
      values (v_id, c, 'zzm25|PG|Online', 'partner', v_p, 'closed', 'commission_first', now() - interval '89 days' + (i * 4 + c) * interval '1 hour',
              now() - interval '90 days' + (i * 4 + c) * interval '1 hour', false)
      returning id into v_a;
      if v_y then
        insert into public.enrollments (lead_id, cycle_no, partner_id, allocation_id, status, source_product, enrolled_on)
        values (v_id, c, v_p, v_a, 'verified', 'b2b', (now() - interval '60 days')::date);
      end if;
    end loop;
  end loop;
end $x$;
select b2b.stats_refresh();

-- ---------- helpers ----------
insert into r select 'eval_log_loss', (b2b.ml_eval(array[0.5, 0.5]::float8[], array[1, 0]::float8[]) ->> 'log_loss')::numeric = round(ln(2)::numeric, 6), null;
insert into r select 'isotonic_monotone', bool_and(coalesce(p >= prev, true)) and count(*) between 2 and 5, max(x)
  from (select x::text x, (c ->> 'p')::numeric p, lag((c ->> 'p')::numeric) over (order by (c ->> 'upto')::numeric) prev
          from (select b2b.ml_isotonic(array[0.1, 0.2, 0.3, 0.4, 0.5, 0.6]::float8[], array[0, 1, 0, 0, 1, 1]::float8[]) x) z, jsonb_array_elements(x) c) q;
insert into r select 'predict_sigmoid', (b2b.ml_predict('{"(bias)":0,"a":1}', '[]', '{"a":1}') ->> 'raw')::numeric = 0.731059, null;
insert into r select 'predict_calibrated', (b2b.ml_predict('{"(bias)":0,"a":1}', '[{"upto":0.5,"p":0.1},{"upto":0.9,"p":0.6}]', '{"a":1}') ->> 'p')::numeric = 0.6, null;
insert into r select 'features_privacy_safe', x ? ('p:' || pg_temp.v('A')) and x ? ('p:' || pg_temp.v('A') || '|src:whatsapp') and x ? 'src:whatsapp'
                     and not exists (select 1 from jsonb_object_keys(x) k where k ~* '(name|phone|email|city)'), x::text
  from (select b2b.ml_features(b2b.ml_lead_features(l), pg_temp.v('A')::bigint, '{"p_hat":0.2}') x from public.student_leads l where l.id = pg_temp.v('L2')::bigint) z;

-- ---------- training ----------
set local role authenticated;
select pg_temp.admin();
insert into t select 'M1', (b2b.ml_train_request('m25 test: first model') ->> 'id');
do $x$ declare e text; begin
  begin perform b2b.ml_train_request('again'); e := 'queued'; exception when others then e := sqlerrm; end;
  insert into r values ('one_training_at_a_time', e = 'a model is already waiting for training', e);
end $x$;
reset role;
insert into t select 'tick', b2b.ml_tick()::text;
insert into r select 'trained_to_shadow', m.status = 'shadow' and m.trained_at is not null and jsonb_array_length(m.features) > 5
                     and (m.trained_on ->> 'rows')::int = 120 and (m.trained_on ->> 'valid')::int = 30, coalesce(m.error, m.status) || ' ' || pg_temp.v('tick')
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;
insert into r select 'beats_segment_phat', (m.metrics -> 'holdout' ->> 'log_loss')::numeric < (m.metrics -> 'baseline' ->> 'log_loss')::numeric,
                     (m.metrics -> 'holdout' ->> 'log_loss') || ' vs ' || (m.metrics -> 'baseline' ->> 'log_loss')
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;
insert into r select 'learned_interaction', (m.weights ->> ('p:' || pg_temp.v('A') || '|src:whatsapp'))::numeric > (m.weights ->> ('p:' || pg_temp.v('A') || '|src:website'))::numeric,
                     (m.weights ->> ('p:' || pg_temp.v('A') || '|src:whatsapp')) || ' / ' || (m.weights ->> ('p:' || pg_temp.v('A') || '|src:website'))
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;
insert into r select 'gate_needs_policy_evidence', (m.gate ->> 'outcomes_ok')::boolean and (m.gate ->> 'partners_ok')::boolean and (m.gate ->> 'beats_baseline')::boolean
                     and not (m.gate ->> 'policy_value_ok')::boolean and not (m.gate ->> 'passed')::boolean, m.gate::text
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;
insert into r select 'training_rows_kept', count(*) = 120 and count(*) filter (where split = 'valid') = 30, count(*)::text
  from b2b.ml_training_rows where model_id = pg_temp.v('M1')::bigint;

-- shadow scores are logged, nothing decides
insert into r select 'shadow_scores_only', x ->> 'model_version' is null and x -> 'shadow' ? (select version from b2b.ml_models where id = pg_temp.v('M1')::bigint),
                     x -> 'shadow' ->> 0
  from (select b2b.route_score(pg_temp.v('L2')::bigint, 'zzm25|PG|Online', pg_temp.kept(), 0.31, false) x) z;

-- ---------- promotion ----------
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; begin
  begin perform b2b.ml_set_status(pg_temp.v('M1')::bigint, 'challenger', 'try'); e := 'promoted'; exception when others then e := sqlerrm; end;
  insert into r values ('gate_blocks_challenger', e like 'the model has not passed the activation gate%', e);
  begin perform b2b.ml_set_status(pg_temp.v('M1')::bigint, 'champion', 'try'); e := 'promoted'; exception when others then e := sqlerrm; end;
  insert into r values ('no_skipping_to_champion', e = 'only the challenger can become the champion', e);
end $x$;
reset role;
update b2b.ml_models set gate = gate || '{"passed":true}' where id = pg_temp.v('M1')::bigint;  -- as if logged decisions had shown the value
set local role authenticated;
select pg_temp.admin();
select b2b.ml_set_status(pg_temp.v('M1')::bigint, 'challenger', 'm25 test: gate passed');
do $x$ declare e text; begin
  begin perform b2b.ml_set_status(pg_temp.v('M1')::bigint, 'champion', 'too early'); e := 'promoted'; exception when others then e := sqlerrm; end;
  insert into r values ('champion_needs_confidence', e like 'the challenger is not yet better with confidence%', e);
end $x$;
reset role;

-- the challenger decides (no champion yet): per lead, the partner that converts its source
insert into t select 'sw', b2b.route_score(pg_temp.v('L2')::bigint, 'zzm25|PG|Online', pg_temp.kept(), 0.31, false)::text;   -- WhatsApp lead
insert into t select 'sx', b2b.route_score(pg_temp.v('L1')::bigint, 'zzm25|PG|Online', pg_temp.kept(), 0.31, false)::text;   -- website lead
insert into r select 'challenger_decides', x ->> 'scoring_mode' = 'performance' and x ->> 'model_version' = (select version from b2b.ml_models where id = pg_temp.v('M1')::bigint)
                     and (x -> 'winner') ? 'p_model', x ->> 'scoring_mode' || ' ' || coalesce(x ->> 'model_version', '-')
  from (select pg_temp.v('sw')::jsonb x) z;
insert into r select 'per_lead_preference',
                     (select (c ->> 'p_model')::numeric from jsonb_array_elements(pg_temp.v('sw')::jsonb -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('A'))
                     > (select (c ->> 'p_model')::numeric from jsonb_array_elements(pg_temp.v('sw')::jsonb -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('B'))
                     and (select (c ->> 'p_model')::numeric from jsonb_array_elements(pg_temp.v('sx')::jsonb -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('B'))
                     > (select (c ->> 'p_model')::numeric from jsonb_array_elements(pg_temp.v('sx')::jsonb -> 'candidates') c where c ->> 'partner_id' = pg_temp.v('A')),
                     null;
insert into r select 'model_winner_mostly_right', (x -> 'winner' ->> 'partner_id') = pg_temp.v('A') and (x ->> 'selection_probability')::numeric > 0.5, x ->> 'selection_probability'
  from (select pg_temp.v('sw')::jsonb x) z;
update b2b.settings set value = value || '{"holdout_share":1}' where key = 'engine_policy';
insert into r select 'holdout_never_model', x ->> 'model_version' is null and not ((x -> 'winner') ? 'p_model') and (x -> 'shadow') is not null, x ->> 'model_version'
  from (select b2b.route_score(pg_temp.v('L2')::bigint, 'zzm25|PG|Online', pg_temp.kept(), 0.31, false) x) z;
update b2b.settings set value = value || '{"holdout_share":0}' where key = 'engine_policy';

-- ---------- rollback ----------
insert into b2b.ml_models (version, status, weights, calibration, was_champion, status_at) values ('m25-old-champion', 'retired', '{"(bias)":-2}', '[]', true, now() - interval '5 days');
update b2b.ml_models set status = 'champion' where id = pg_temp.v('M1')::bigint;
set local role authenticated;
select pg_temp.admin();
insert into r select 'rollback_restores_previous', x ->> 'champion' = 'm25-old-champion'
                     and (select status from b2b.ml_models where id = pg_temp.v('M1')::bigint) = 'retired'
                     and (select status from b2b.ml_models where version = 'm25-old-champion') = 'champion', x::text
  from (select b2b.ml_rollback('m25 test: worse than expected') x) z;
reset role;

-- ---------- calibration fallback ----------
-- 100 matured decisions by the (restored) champion that predicted 0.9 for leads that did not enrol
do $x$ declare i int; v_d bigint; begin
  for i in 1 .. 100 loop
    insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, candidates, seed,
                                      selection_probability, scoring_mode, holdout, model_version, is_test, actor_type, created_at)
    values (pg_temp.v('L1')::bigint, 100 + i, 'zzm25|PG|Online', '{}', 'performance', 'partner', pg_temp.v('A')::bigint,
            jsonb_build_array(jsonb_build_object('partner_id', pg_temp.v('A')::bigint, 'p_model', 0.9, 'eligible', true)), 0.5, 0.9, 'performance', false,
            'm25-old-champion', false, 'engine', now() - interval '70 days')
    returning id into v_d;
    insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, engine_decision_id, accepted_at, created_at, is_test)
    values (pg_temp.v('L1')::bigint, 100 + i, 'zzm25|PG|Online', 'partner', pg_temp.v('A')::bigint, 'closed', 'performance', v_d,
            now() - interval '69 days', now() - interval '70 days', false);
  end loop;
end $x$;
insert into r select 'fallback_retires', exists (select 1 from jsonb_array_elements(b2b.ml_monitor()) x where x ->> 'version' = 'm25-old-champion' and (x ->> 'retired')::boolean)
                     and (select status from b2b.ml_models where version = 'm25-old-champion') = 'retired', null;
insert into r select 'fallback_alert', count(*) = 1, count(*)::text from b2b.events where type = 'alert.model_fallback' and payload ->> 'version' = 'm25-old-champion';
insert into r select 'no_model_after_fallback', b2b.route_score(pg_temp.v('L2')::bigint, 'zzm25|PG|Online', pg_temp.kept(), 0.31, false) ->> 'model_version' is null, null;

-- ---------- a run without enough data fails cleanly ----------
update b2b.settings set value = value || '{"maturity_days":180}' where key = 'engine';
with x as (insert into b2b.ml_models (version, requested_by) values ('m25-too-early', 'test') returning id) insert into t select 'M2', id::text from x;
select b2b.ml_tick();
insert into r select 'training_fails_cleanly', m.status = 'failed' and m.error like 'not enough matured outcomes%'
                     and not exists (select 1 from b2b.ml_training_rows where model_id = m.id), m.status || ' ' || coalesce(m.error, '')
  from b2b.ml_models m where m.id = pg_temp.v('M2')::bigint;
update b2b.settings set value = value || '{"maturity_days":60}' where key = 'engine';

-- ---------- reads and access ----------
set local role authenticated;
select pg_temp.admin();
insert into r select 'overview', jsonb_array_length(x -> 'models') >= 3 and (x -> 'data' ->> 'matured')::int >= 120, (x -> 'data')::text
  from (select b2b.ml_overview() x) z;
reset role;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e2","role":"authenticated","aal":"aal2","email":"nobody25@test.local"}', true);
set local role authenticated;
do $x$ declare e text; begin
  begin perform b2b.ml_overview(); e := 'read'; exception when others then e := sqlstate; end;
  insert into r values ('non_admin_refused', e = '42501', e);
  begin perform b2b.ml_train(1); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('training_not_callable', e = '42501', e);
end $x$;
reset role;

select name, ok, detail from r order by ok, name;
rollback;
