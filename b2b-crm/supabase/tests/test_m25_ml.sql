-- M25 per-lead model on STAGING, rolled back. Needs pending/m25d_ml_training_rows_prune.sql applied (the prune rows).
-- 30 fixture leads (half WhatsApp, half website), each sent 4 times (cycles) to two fixture partners 70 days ago: A enrols
-- about 3 of 4 of its WhatsApp leads and no website ones; B the reverse. Segment P̂ cannot see that; the model's partner x
-- source features can. Checks: the maths helpers, training (queued, cancelled by the Admin, trained by the tick, shadow,
-- holdout metrics beating segment P̂, a calibration that is not all 0/1), pruning old training rows, the gate refusing
-- promotion without logged-decision evidence, the registry keeping the models in use, serving through route_score (the
-- challenger decides, holdout leads never), shadow scores, the champion check, feature and prediction drift with its
-- alert, rollback (only to the champion the current one replaced), the calibration fallback with its alert, a failed
-- training run, a run that never finished, the settings, the cron timeout, and access. Every row must say ok = true.
begin;
-- hold the cron ticks' locks for this transaction so an overlapping staging cron run cannot make the calls below return busy; rollback releases them
select pg_advisory_xact_lock(hashtext('b2b.ml_tick'));
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
      -- A enrols WhatsApp leads (about 3 of 4 of its WhatsApp allocations), B website leads; the other mix never enrols
      v_y := ((v_p = pg_temp.v('A')::bigint) = v_wa) and (i + c) % 8 <> 1;
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
-- the fixture is not perfectly separable: 46 of the 60 matching allocations enrol
insert into r select 'fixture_has_noise', count(*) filter (where e.id is not null) = 46, count(*) filter (where e.id is not null)::text from b2b.allocations a left join public.enrollments e on e.allocation_id = a.id where a.segment = 'zzm25|PG|Online' and a.partner_id in (pg_temp.v('A')::bigint, pg_temp.v('B')::bigint) and a.engine_decision_id is null;

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
-- the Admin can cancel a queued run (it is retired) and then queue another (M1)
set local role authenticated;
select pg_temp.admin();
insert into t select 'Q', (b2b.ml_train_request('m25 test: queued, then cancelled') ->> 'id');
do $x$ declare e text; begin
  begin perform b2b.ml_set_status(pg_temp.v('Q')::bigint, 'retired', 'm25 test: cancel the queued run'); e := 'cancelled'; exception when others then e := sqlerrm; end;
  insert into t values ('Qcancel', e);
end $x$;
reset role;
insert into t select 'Qstatus', status from b2b.ml_models where id = pg_temp.v('Q')::bigint;
-- a run is named after the transaction's start second, so the cancelled one is renamed before the next request (and,
-- should the cancel have failed, taken out of the queue so that the rest of the file still runs)
update b2b.ml_models set version = 'm25-cancelled', status = case when status = 'training' then 'failed' else status end
 where id = pg_temp.v('Q')::bigint;
set local role authenticated;
select pg_temp.admin();
insert into t select 'M1', (b2b.ml_train_request('m25 test: first model') ->> 'id');
do $x$ declare e text; begin
  begin perform b2b.ml_train_request('again'); e := 'queued'; exception when others then e := sqlerrm; end;
  insert into r values ('one_training_at_a_time', e = 'a model is already waiting for training', e);
end $x$;
reset role;
insert into r select 'admin_cancels_queued_training', pg_temp.v('Qcancel') = 'cancelled' and pg_temp.v('Qstatus') = 'retired' and m.status = 'training',
                     pg_temp.v('Qcancel') || ' / ' || pg_temp.v('Qstatus') || ' / next request ' || m.status
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;
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
insert into r select 'calibration_not_degenerate', exists (select 1 from jsonb_array_elements(m.calibration) c where (c ->> 'p')::numeric > 0.05 and (c ->> 'p')::numeric < 0.95),
                     m.calibration::text
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;

-- ---------- pruning old training rows (pending/m25d) ----------
insert into b2b.ml_models (version, status, was_champion, status_at) values
  ('m25-prune-old', 'retired', false, now() - interval '31 days'),
  ('m25-prune-champ', 'retired', true, now() - interval '90 days'),
  ('m25-prune-recent', 'retired', false, now() - interval '5 days'),
  ('m25-prune-failed', 'failed', false, now() - interval '40 days');
insert into b2b.ml_training_rows (model_id, allocation_id, split, y, x)
select m.id, g, 'train', 0, '{}' from b2b.ml_models m cross join generate_series(1, 2) g where m.version like 'm25-prune-%';
-- rows of older staging models the prune also removes (none on a fresh database)
insert into t select 'prune_others', count(*)::text from b2b.ml_training_rows r join b2b.ml_models m on m.id = r.model_id
 where m.status in ('retired', 'failed') and not m.was_champion and m.status_at < now() - interval '30 days' and m.version not like 'm25-prune-%';
insert into t select 'prune', b2b.ml_training_rows_prune()::text;
insert into r select 'prune_old_rows', pg_temp.v('prune')::int = 4 + pg_temp.v('prune_others')::int
                     and not exists (select 1 from b2b.ml_training_rows r join b2b.ml_models m on m.id = r.model_id where m.version in ('m25-prune-old', 'm25-prune-failed'))
                     and (select count(*) from b2b.ml_training_rows r join b2b.ml_models m on m.id = r.model_id where m.version = 'm25-prune-champ') = 2
                     and (select count(*) from b2b.ml_training_rows r join b2b.ml_models m on m.id = r.model_id where m.version = 'm25-prune-recent') = 2
                     and (select count(*) from b2b.ml_training_rows where model_id = pg_temp.v('M1')::bigint) = 120
                     and (select count(*) from b2b.events where type = 'ml.training_rows_pruned' and occurred_at >= now()
                                                            and (payload ->> 'rows')::int = pg_temp.v('prune')::int) = 1,
                     pg_temp.v('prune') || ' rows, ' || pg_temp.v('prune_others') || ' of them outside the test';
insert into r select 'prune_cron', exists (select 1 from cron.job where jobname = 'b2b-ml-prune'), null;

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
-- 25 newer runs (failed, as when data is short): the registry still lists the challenger, and stays bounded
insert into b2b.ml_models (version, status, error) select 'm25-fill-' || g, 'failed', 'filler' from generate_series(1, 25) g;
set local role authenticated;
select pg_temp.admin();
insert into r select 'overview_keeps_active', exists (select 1 from jsonb_array_elements(b2b.ml_overview() -> 'models') x
                                                       where (x ->> 'id')::bigint = pg_temp.v('M1')::bigint and x ->> 'status' = 'challenger'), null;
insert into r select 'overview_bounded', jsonb_array_length(b2b.ml_overview() -> 'models')
                                         <= 20 + (select count(*) from b2b.ml_models where status in ('training', 'shadow', 'challenger', 'champion')),
                     jsonb_array_length(b2b.ml_overview() -> 'models')::text;
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
insert into r select 'holdout_never_model', x ->> 'model_version' is null and not ((x -> 'winner') ? 'p_model') and x -> 'shadow' ? (select version from b2b.ml_models where id = pg_temp.v('M1')::bigint), x ->> 'model_version'
  from (select b2b.route_score(pg_temp.v('L2')::bigint, 'zzm25|PG|Online', pg_temp.kept(), 0.31, false) x) z;
update b2b.settings set value = value || '{"holdout_share":0}' where key = 'engine_policy';

-- ---------- drift monitoring ----------
update b2b.ml_models set status = 'champion' where id = pg_temp.v('M1')::bigint;
-- M1, trained on half WhatsApp and half website leads, now decides website leads only. The decisions are logged in the
-- Addendum 3 candidate format (p_source 'model' and p_used, no p_model). Its holdout rows point at one of them for now, so
-- the reference prediction has logged decisions to start from.
do $x$ declare i int; begin
  for i in 1 .. 50 loop
    insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, candidates, seed,
                                      selection_probability, scoring_mode, holdout, model_version, is_test, actor_type, created_at)
    values (pg_temp.v('L' || (2 * (i % 15) + 1))::bigint, 300 + i, 'zzm25|PG|Online', '{}', 'performance', 'partner', pg_temp.v('A')::bigint,
            jsonb_build_array(jsonb_build_object('partner_id', pg_temp.v('A')::bigint, 'p_source', 'model', 'p_used', 0.3, 'eligible', true)), 0.5, 0.9,
            'performance', false, (select version from b2b.ml_models where id = pg_temp.v('M1')::bigint), false, 'engine', now() - interval '2 days');
  end loop;
end $x$;
update b2b.ml_training_rows set decision_id = (select min(d.id) from b2b.engine_decisions d join b2b.ml_models m on m.version = d.model_version
                                                where m.id = pg_temp.v('M1')::bigint)
 where model_id = pg_temp.v('M1')::bigint and split = 'valid';
insert into t select 'mon1', b2b.ml_monitor()::text;
insert into t select 'ref1', metrics -> 'monitor' ->> 'mean_p_reference' from b2b.ml_models where id = pg_temp.v('M1')::bigint;
insert into r select 'drift_needs_volume', m.metrics -> 'monitor' -> 'drift' = 'false'::jsonb and (m.metrics -> 'monitor' -> 'feature_psi' ->> 'n_live')::int = 50
                     and not exists (select 1 from b2b.events where type = 'alert.model_drift' and payload ->> 'version' = m.version),
                     (m.metrics -> 'monitor' -> 'feature_psi')::text
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;
do $x$ declare i int; begin
  for i in 51 .. 200 loop
    insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, candidates, seed,
                                      selection_probability, scoring_mode, holdout, model_version, is_test, actor_type, created_at)
    values (pg_temp.v('L' || (2 * (i % 15) + 1))::bigint, 300 + i, 'zzm25|PG|Online', '{}', 'performance', 'partner', pg_temp.v('A')::bigint,
            jsonb_build_array(jsonb_build_object('partner_id', pg_temp.v('A')::bigint, 'p_source', 'model', 'p_used', 0.3, 'eligible', true)), 0.5, 0.9,
            'performance', false, (select version from b2b.ml_models where id = pg_temp.v('M1')::bigint), false, 'engine', now() - interval '2 days');
  end loop;
end $x$;
-- the reference is computed once: unlinked from its decisions now, a recomputation would give nothing
update b2b.ml_training_rows set decision_id = null where model_id = pg_temp.v('M1')::bigint;
insert into t select 'mon2', b2b.ml_monitor()::text;
insert into r select 'feature_drift_alert', (f ->> 'max')::numeric > 0.25 and f -> 'top' -> 0 ->> 'feature' in ('src:website', 'src:whatsapp')
                     and (f ->> 'n_live')::int = 200 and (m.metrics -> 'monitor' ->> 'drift')::boolean
                     and (select count(*) from b2b.events where type = 'alert.model_drift' and payload ->> 'version' = m.version) = 1,
                     f::text
  from b2b.ml_models m cross join lateral (select m.metrics -> 'monitor' -> 'feature_psi' f) z where m.id = pg_temp.v('M1')::bigint;
insert into r select 'mean_p_reference_cached', pg_temp.v('ref1') is not null and m.metrics -> 'monitor' ->> 'mean_p_reference' = pg_temp.v('ref1'),
                     coalesce(pg_temp.v('ref1'), 'null') || ' -> ' || coalesce(m.metrics -> 'monitor' ->> 'mean_p_reference', 'null')
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;
insert into r select 'monitor_reads_a3_candidates', (m.metrics -> 'monitor' ->> 'mean_p_30d')::numeric = 0.3, m.metrics -> 'monitor' ->> 'mean_p_30d'
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;

-- ---------- rollback ----------
-- the champion M1 replaced
insert into b2b.ml_models (version, status, weights, calibration, was_champion, status_at, status_reason)
select 'm25-old-champion', 'retired', '{"(bias)":-2}', '[]', true, now() - interval '5 days', 'replaced by ' || version from b2b.ml_models where id = pg_temp.v('M1')::bigint;
set local role authenticated;
select pg_temp.admin();
-- (a check in the same statement as the call would not see the call's own changes, so the answer is kept first)
insert into t select 'rb', b2b.ml_rollback('m25 test: worse than expected')::text;
reset role;
insert into r select 'rollback_restores_previous', x ->> 'champion' = 'm25-old-champion'
                     and (select status from b2b.ml_models where id = pg_temp.v('M1')::bigint) = 'retired'
                     and (select status from b2b.ml_models where version = 'm25-old-champion') = 'champion', x::text
  from (select pg_temp.v('rb')::jsonb x) z;

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
insert into t select 'mon', b2b.ml_monitor()::text;
insert into r select 'fallback_retires', exists (select 1 from jsonb_array_elements(pg_temp.v('mon')::jsonb) x where x ->> 'version' = 'm25-old-champion' and (x ->> 'retired')::boolean)
                     and (select status from b2b.ml_models where version = 'm25-old-champion') = 'retired', pg_temp.v('mon');
insert into r select 'fallback_alert', count(*) = 1, count(*)::text from b2b.events where type = 'alert.model_fallback' and payload ->> 'version' = 'm25-old-champion';
insert into r select 'no_model_after_fallback', b2b.route_score(pg_temp.v('L2')::bigint, 'zzm25|PG|Online', pg_temp.kept(), 0.31, false) ->> 'model_version' is null, null;
-- m25-old-champion (retired for calibration) and M1 (rolled back) are past champions, but neither was replaced by the next
-- champion: rolling that one back restores nothing
insert into b2b.ml_models (version, status, weights, calibration) values ('m25-new-champion', 'champion', '{"(bias)":-2}', '[]');
set local role authenticated;
select pg_temp.admin();
insert into t select 'rb2', b2b.ml_rollback('m25 test: again')::text;
reset role;
insert into r select 'rollback_skips_bad_models', x ->> 'champion' is null
                     and (select status from b2b.ml_models where version = 'm25-old-champion') = 'retired'
                     and (select status from b2b.ml_models where id = pg_temp.v('M1')::bigint) = 'retired'
                     and (select status from b2b.ml_models where version = 'm25-new-champion') = 'retired', x::text
  from (select pg_temp.v('rb2')::jsonb x) z;

-- ---------- a run without enough data fails cleanly ----------
update b2b.settings set value = value || '{"maturity_days":180}' where key = 'engine';
with x as (insert into b2b.ml_models (version, requested_by) values ('m25-too-early', 'test') returning id) insert into t select 'M2', id::text from x;
select b2b.ml_tick();
insert into r select 'training_fails_cleanly', m.status = 'failed' and m.error like 'not enough matured outcomes%'
                     and not exists (select 1 from b2b.ml_training_rows where model_id = m.id), m.status || ' ' || coalesce(m.error, '')
  from b2b.ml_models m where m.id = pg_temp.v('M2')::bigint;
update b2b.settings set value = value || '{"maturity_days":60}' where key = 'engine';

-- ---------- a run that never finished is failed by the next tick ----------
-- (auto_train is off in this transaction, and no other model is 'training' now)
insert into b2b.ml_models (version, requested_by, created_at) values ('m25-stuck', 'test', now() - interval '2 hours');
insert into t select 'tick_stuck', b2b.ml_tick()::text;
insert into r select 'stuck_training_failed', m.status = 'failed' and m.error like 'training did not finish%'
                     and (select count(*) from b2b.events where type = 'ml.model_failed' and payload ->> 'version' = 'm25-stuck') = 1
                     and pg_temp.v('tick_stuck')::jsonb ->> 'stuck_failed' = 'm25-stuck', m.status || ' ' || pg_temp.v('tick_stuck')
  from b2b.ml_models m where m.version = 'm25-stuck';
insert into r select 'cron_has_timeout', exists (select 1 from cron.job where jobname = 'b2b-ml-tick' and command like 'set statement_timeout%'),
                     (select min(command) from cron.job where jobname = 'b2b-ml-tick');

-- ---------- reads, settings and access ----------
insert into t select 'ml_version', version::text from b2b.settings where key = 'ml';
set local role authenticated;
select pg_temp.admin();
insert into r select 'overview', jsonb_array_length(x -> 'models') >= 3 and (x -> 'data' ->> 'matured')::int >= 120, (x -> 'data')::text
  from (select b2b.ml_overview() x) z;
insert into t select 'saved', b2b.ml_settings_save('{"auto_train":false,"challenger_share":0.1}', 't')::text;
reset role;
insert into r select 'ml_settings_save', b2b.ml_cfg() ->> 'auto_train' = 'false'
                     and (select version from b2b.settings where key = 'ml') = pg_temp.v('ml_version')::int + 1, pg_temp.v('saved');
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
