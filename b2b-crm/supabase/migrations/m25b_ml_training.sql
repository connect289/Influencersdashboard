-- M25b: the per-lead model, part 2: training, calibration, validation, the activation gate, serving and monitoring.
--   ml_train(model id)   builds the rows (the newest 50,000 matured outcomes; the newest valid_share of them is the holdout),
--                        keeps features seen in at least min_feature_rows training rows, fits the logistic regression by
--                        full-batch gradient descent (AdaGrad, L2), fits isotonic calibration on the training scores, then
--                        measures on the holdout: log loss, calibration error (ECE, 10 bins), deciles, and the same for
--                        segment-level P̂ (the baseline it must beat); and offline policy value by inverse propensity on the
--                        holdout's logged decisions (B7.8.1: "offline policy value shows higher net commission per lead").
--                        A trained model starts in shadow; the gate says whether it may decide.
--   ml_tick()            every 10 minutes (cron, statement_timeout 15 min): fails a run that never finished, trains a
--                        requested model, or the nightly one (train_hour_ist), and once a day monitors the deciding models:
--                        calibration on matured leads (above ece_fallback the model is retired automatically, fallback to
--                        segment P̂, with an alert) and feature and prediction drift (an alert only).
--   model_score(...)     the hook route_score calls: the champion decides (or the challenger on challenger_share of leads,
--                        by seeded draw); a shadow model only scores. Never for holdout leads.
--   ml_champion_check(id) realised net commission per lead of the challenger's leads against the rest, with a one-sided
--                        z-test (95%); a challenger becomes champion only when it is higher with confidence.

create or replace function b2b.ml_cfg()
returns jsonb language sql stable set search_path = '' as $fn$
  select '{"min_outcomes":500,"min_partners":2,"challenger_share":0.1,"ece_fallback":0.08,"l2":0.01,"iterations":200,"learning_rate":0.5,
           "min_feature_rows":10,"valid_share":0.2,"train_hour_ist":2,"auto_train":true}'::jsonb
         || coalesce((select value from b2b.settings where key = 'ml'), '{}');
$fn$;

/* Isotonic regression (pool adjacent violators) of y on score, as ascending bins [{upto, p}]. */
create or replace function b2b.ml_isotonic(p_scores float8[], p_y float8[])
returns jsonb language plpgsql immutable set search_path = '' as $fn$
declare
  n int := coalesce(array_length(p_scores, 1), 0);
  idx int[];
  bs float8[] := '{}';  -- block sums of y
  bn float8[] := '{}';  -- block counts
  bu float8[] := '{}';  -- block upper score
  k int := 0;
  i int;
  out jsonb := '[]';
begin
  if n = 0 then return '[]'; end if;
  select array_agg(o order by p_scores[o], o) into idx from generate_series(1, n) o;
  foreach i in array idx loop
    k := k + 1;
    bs[k] := p_y[i]; bn[k] := 1; bu[k] := p_scores[i];
    while k > 1 and bs[k - 1] / bn[k - 1] >= bs[k] / bn[k] loop
      bs[k - 1] := bs[k - 1] + bs[k]; bn[k - 1] := bn[k - 1] + bn[k]; bu[k - 1] := bu[k];
      k := k - 1;
    end loop;
  end loop;
  for i in 1 .. k loop
    -- a light pull toward the block's neighbours keeps a tiny all-zero block from predicting exactly 0
    out := out || jsonb_build_object('upto', round(bu[i]::numeric, 6), 'p', round(((bs[i] + 0.5 * (bs[i] / bn[i])) / (bn[i] + 0.5))::numeric, 6),
                                     'n', bn[i]::int);
  end loop;
  return out;
end $fn$;

/* Log loss, ECE (10 equal-count bins) and deciles of predictions p against outcomes y. */
create or replace function b2b.ml_eval(p_p float8[], p_y float8[])
returns jsonb language sql immutable set search_path = '' as $fn$
  with d as (select u.p, u.y, ntile(10) over (order by u.p) b from unnest(p_p, p_y) u(p, y)),
       bins as (select b, avg(p) mp, avg(y) my, count(*) n from d group by b)
  select jsonb_build_object(
    'n', (select count(*) from d),
    'log_loss', (select round(avg(-(y * ln(least(greatest(p, 1e-4), 1 - 1e-4)) + (1 - y) * ln(1 - least(greatest(p, 1e-4), 1 - 1e-4))))::numeric, 6) from d),
    'ece', (select round((sum(n * abs(mp - my)) / nullif(sum(n), 0))::numeric, 6) from bins),
    'mean_p', (select round(avg(p)::numeric, 6) from d), 'mean_y', (select round(avg(y)::numeric, 6) from d),
    'deciles', coalesce((select jsonb_agg(jsonb_build_object('bin', b, 'pred', round(mp::numeric, 4), 'actual', round(my::numeric, 4), 'n', n) order by b) from bins), '[]'));
$fn$;

create or replace function b2b.ml_train(p_model_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ml_cfg();
  prm jsonb := b2b.engine_params(true);
  m b2b.ml_models;
  v_n int; v_pos int; v_partners int; v_ntrain int; v_nvalid int;
  v_vocab jsonb;
  w jsonb := '{}';
  g jsonb := '{}';        -- AdaGrad accumulators
  v_lr float8 := coalesce((cfg ->> 'learning_rate')::float8, 0.5);
  v_l2 float8 := coalesce((cfg ->> 'l2')::float8, 0.01);
  v_iter int := least(greatest(coalesce((cfg ->> 'iterations')::int, 200), 10), 1000);
  v_cal jsonb;
  v_scores float8[]; v_ys float8[];
  v_eval jsonb; v_base jsonb;
  v_ips jsonb;
  v_gate jsonb;
  i int;
begin
  select * into m from b2b.ml_models where id = p_model_id and status = 'training' for update;
  if m.id is null then raise exception 'no model waiting for training' using errcode = 'P0002'; end if;
  perform set_config('b2b.actor', 'engine', true);

  -- 1. rows: the newest 50,000 matured outcomes (a run stays well under the tick's 15-minute timeout), features as they
  --    were at the decision (the logged candidate), newest valid_share held out
  insert into b2b.ml_training_rows (model_id, allocation_id, split, y, x, baseline_p, decision_id)
  select m.id, o.allocation_id,
         case when row_number() over (order by o.created_at, o.allocation_id) > ceil(count(*) over () * (1 - (cfg ->> 'valid_share')::numeric)) then 'valid' else 'train' end,
         case when o.enrolled then 1 else 0 end,
         b2b.ml_features(b2b.ml_lead_features(l), o.partner_id, coalesce(cand.c, jsonb_build_object('p_hat', st.p_hat, 'sla_compliance', st.sla_compliance))),
         coalesce((cand.c ->> 'p_hat')::numeric, st.p_hat, (prm ->> 'default_p_enroll')::numeric),
         a.engine_decision_id
    from (select * from b2b.allocation_outcomes() x
           where x.age_days >= (prm ->> 'maturity_days')::numeric
           order by x.created_at desc, x.allocation_id desc limit 50000) o
    join b2b.allocations a on a.id = o.allocation_id
    join public.student_leads l on l.id = o.lead_id
    left join lateral (select c from b2b.engine_decisions d, jsonb_array_elements(d.candidates) c
                        where d.id = a.engine_decision_id and (c ->> 'partner_id')::bigint = o.partner_id limit 1) cand on true
    left join lateral (select s.p_hat, s.sla_compliance from b2b.partner_segment_stats s
                        where s.variant = 'base' and s.partner_id = o.partner_id and s.segment in (o.segment, b2b.segment_rollup(o.segment))
                        order by (s.segment = o.segment and s.n_leads >= 30) desc, s.segment = b2b.segment_rollup(o.segment) desc limit 1) st on true;

  select count(*), count(*) filter (where y = 1), count(*) filter (where split = 'train'), count(*) filter (where split = 'valid')
    into v_n, v_pos, v_ntrain, v_nvalid from b2b.ml_training_rows where model_id = m.id;
  select count(distinct a.partner_id) into v_partners from b2b.ml_training_rows r join b2b.allocations a on a.id = r.allocation_id where r.model_id = m.id;
  if v_n < 40 or v_pos < 4 or v_nvalid < 10 or v_ntrain - (select count(*) from b2b.ml_training_rows where model_id = m.id and split = 'train' and y = 1) < 4 then
    raise exception 'not enough matured outcomes to train (% rows, % enrolled)', v_n, v_pos using errcode = '22023';
  end if;

  -- 2. vocabulary: features seen in at least min_feature_rows training rows
  select coalesce(jsonb_object_agg(f.key, true), '{}') into v_vocab
    from (select f.key from b2b.ml_training_rows r, jsonb_each(r.x) f where r.model_id = m.id and r.split = 'train'
           group by f.key having count(*) >= (cfg ->> 'min_feature_rows')::int) f;

  -- 3. gradient descent (AdaGrad) on the training rows; the bias starts at the training log-odds
  w := jsonb_build_object('(bias)', ln((v_pos + 0.5)::float8 / (v_n - v_pos + 0.5)));
  for i in 1 .. v_iter loop
    with z as (select r.allocation_id, r.y, (b2b.ml_predict(w, '[]', r.x) ->> 'raw')::float8 p, r.x
                 from b2b.ml_training_rows r where r.model_id = m.id and r.split = 'train'),
         gr as (select '(bias)' k, avg(z.p - z.y) gk from z
                union all
                select f.key, sum((z.p - z.y) * f.value::float8) / v_ntrain from z, jsonb_each_text(z.x) f where v_vocab ? f.key group by f.key),
         acc as (select gr.k, gr.gk + case when gr.k = '(bias)' then 0 else v_l2 * coalesce((w ->> gr.k)::float8, 0) end gk,
                        coalesce((g ->> gr.k)::float8, 0) + power(gr.gk + case when gr.k = '(bias)' then 0 else v_l2 * coalesce((w ->> gr.k)::float8, 0) end, 2) gs
                   from gr)
    select jsonb_object_agg(acc.k, round((coalesce((w ->> acc.k)::float8, 0) - v_lr * acc.gk / sqrt(acc.gs + 1e-8))::numeric, 8)),
           jsonb_object_agg(acc.k, acc.gs)
      into w, g from acc;
  end loop;

  -- 4. isotonic calibration on the training scores
  select array_agg((b2b.ml_predict(w, '[]', r.x) ->> 'raw')::float8 order by r.allocation_id), array_agg(r.y::float8 order by r.allocation_id)
    into v_scores, v_ys from b2b.ml_training_rows r where r.model_id = m.id and r.split = 'train';
  v_cal := b2b.ml_isotonic(v_scores, v_ys);

  -- 5. holdout metrics: the model against segment P̂
  select b2b.ml_eval(array_agg((b2b.ml_predict(w, v_cal, r.x) ->> 'p')::float8), array_agg(r.y::float8)),
         b2b.ml_eval(array_agg(r.baseline_p::float8), array_agg(r.y::float8))
    into v_eval, v_base from b2b.ml_training_rows r where r.model_id = m.id and r.split = 'valid';

  -- 6. offline policy value (inverse propensity) on the holdout's logged partner decisions
  with dec as (
    select r.allocation_id, d.id, d.selection_probability sp, d.winner_partner_id win, l lead_row, d.candidates,
           case when r.y = 1 and coalesce(en.status, '') not in ('refunded', 'cancelled')
                then coalesce((select (c ->> 'cpe')::numeric from jsonb_array_elements(d.candidates) c where (c ->> 'partner_id')::bigint = d.winner_partner_id), 0)
                else 0 end reward
      from b2b.ml_training_rows r
      join b2b.engine_decisions d on d.id = r.decision_id and d.destination_type = 'partner' and d.selection_probability > 0
      join public.student_leads l on l.id = d.lead_id
      left join lateral (select e.status from public.enrollments e where e.allocation_id = r.allocation_id order by e.id desc limit 1) en on true
     where r.model_id = m.id and r.split = 'valid'),
  pick as (
    select dec.*, (select (c ->> 'partner_id')::bigint from jsonb_array_elements(dec.candidates) c
                    where coalesce((c ->> 'eligible')::boolean, true)
                    order by (b2b.ml_predict(w, v_cal, b2b.ml_features(b2b.ml_lead_features(dec.lead_row), (c ->> 'partner_id')::bigint, c)) ->> 'p')::numeric
                             * coalesce((c ->> 'cpe')::numeric, 0) * (1 - coalesce((c ->> 'refund_rate')::numeric, 0)) desc,
                             (c ->> 'cpe')::numeric desc nulls last, (c ->> 'partner_id')::bigint limit 1) model_pick
      from dec)
  select jsonb_build_object('decisions', count(*), 'agree', count(*) filter (where model_pick = win),
                            'logged_value', round(coalesce(avg(reward), 0), 2),
                            'model_value', round(coalesce(avg(case when model_pick = win then reward / sp else 0 end), 0), 2),
                            'ess', round(coalesce(power(sum(case when model_pick = win then 1 / sp else 0 end), 2)
                                                  / nullif(sum(case when model_pick = win then 1 / (sp * sp) else 0 end), 0), 0), 1))
    into v_ips from pick;

  v_gate := jsonb_build_object(
    'outcomes', v_n, 'min_outcomes', (cfg ->> 'min_outcomes')::int, 'outcomes_ok', v_n >= (cfg ->> 'min_outcomes')::int,
    'partners', v_partners, 'partners_ok', v_partners >= (cfg ->> 'min_partners')::int,
    'beats_baseline', coalesce((v_eval ->> 'log_loss')::numeric < (v_base ->> 'log_loss')::numeric and (v_eval ->> 'ece')::numeric <= (v_base ->> 'ece')::numeric + 0.01, false),
    'policy_value_ok', coalesce((v_ips ->> 'decisions')::int >= 30 and (v_ips ->> 'model_value')::numeric >= (v_ips ->> 'logged_value')::numeric, false));
  v_gate := v_gate || jsonb_build_object('passed', (v_gate ->> 'outcomes_ok')::boolean and (v_gate ->> 'partners_ok')::boolean
                                                   and (v_gate ->> 'beats_baseline')::boolean and (v_gate ->> 'policy_value_ok')::boolean);

  update b2b.ml_models set status = 'retired', status_at = now(), status_by = 'engine', status_reason = 'replaced by ' || m.version
   where status = 'shadow' and id <> m.id;
  update b2b.ml_models
     set status = 'shadow', status_at = now(), status_by = 'engine', status_reason = 'trained', trained_at = now(),
         features = (select coalesce(jsonb_agg(k order by k), '[]') from jsonb_object_keys(v_vocab) k), weights = w, calibration = v_cal,
         metrics = jsonb_build_object('holdout', v_eval, 'baseline', v_base, 'policy', v_ips, 'iterations', v_iter, 'l2', v_l2,
                                      'top_weights', (select jsonb_agg(jsonb_build_object('feature', k, 'w', round(v::numeric, 4)) order by abs(v::numeric) desc)
                                                        from (select k, v from jsonb_each_text(w) x(k, v) where k <> '(bias)' order by abs(v::numeric) desc limit 15) t)),
         gate = v_gate,
         trained_on = jsonb_build_object('rows', v_n, 'enrolled', v_pos, 'train', v_ntrain, 'valid', v_nvalid, 'partners', v_partners,
                                         'maturity_days', (prm ->> 'maturity_days')::int,
                                         'from', (select min(a.created_at) from b2b.ml_training_rows r join b2b.allocations a on a.id = r.allocation_id where r.model_id = m.id),
                                         'to', (select max(a.created_at) from b2b.ml_training_rows r join b2b.allocations a on a.id = r.allocation_id where r.model_id = m.id))
   where id = m.id;
  perform b2b.log_event('ml.model_trained', null, null, null, jsonb_build_object('version', m.version, 'gate', v_gate, 'holdout', v_eval - 'deciles'));
  return jsonb_build_object('version', m.version, 'gate', v_gate, 'holdout', v_eval - 'deciles', 'baseline', v_base - 'deciles', 'policy', v_ips);
end $fn$;

/* The challenger against the rest of the performance-mode leads (not holdout): realised net commission per matured lead. */
create or replace function b2b.ml_champion_check(p_model_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  with m as (select version from b2b.ml_models where id = p_model_id),
       prm as (select (b2b.engine_params(true) ->> 'maturity_days')::int md),
       r as (select d.model_version = m.version is_model,
                    case when e.status is not null and e.status not in ('refunded', 'cancelled') then coalesce(a.cpe_net_inr, 0) else 0 end reward
               from b2b.engine_decisions d
               join b2b.allocations a on a.engine_decision_id = d.id and a.destination_type = 'partner' and not a.is_test
               cross join m cross join prm
               left join lateral (select x.status from public.enrollments x where x.allocation_id = a.id order by x.id desc limit 1) e on true
              where d.scoring_mode = 'performance' and d.mode = 'performance' and not d.holdout and not d.is_test
                and a.created_at <= now() - make_interval(days => prm.md)
                and a.status in ('pushed', 'accepted', 'closed')),
       s as (select is_model, count(*) n, avg(reward) mu, coalesce(var_samp(reward), 0) v from r group by is_model)
  select jsonb_build_object(
    'model_leads', coalesce((select n from s where is_model), 0), 'other_leads', coalesce((select n from s where not is_model), 0),
    'model_ncpl', round(coalesce((select mu from s where is_model), 0), 2), 'other_ncpl', round(coalesce((select mu from s where not is_model), 0), 2),
    'z', round(coalesce(((select mu from s where is_model) - (select mu from s where not is_model))
                        / nullif(sqrt((select v / n from s where is_model) + (select v / n from s where not is_model)), 0), 0), 3),
    'ready', coalesce((select n from s where is_model), 0) >= 100 and coalesce((select n from s where not is_model), 0) >= 100
             and coalesce(((select mu from s where is_model) - (select mu from s where not is_model))
                          / nullif(sqrt((select v / n from s where is_model) + (select v / n from s where not is_model)), 0), 0) >= 1.645);
$fn$;

/* The scoring hook (replaces the M24 stub). */
create or replace function b2b.model_score(p_lead_id bigint, p_cands jsonb, p_seed numeric, p_holdout boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ml_cfg();
  champ b2b.ml_models;
  chall b2b.ml_models;
  shad b2b.ml_models;
  dec b2b.ml_models;
  l public.student_leads;
  v_lead jsonb;
  v_out jsonb := '{}';
begin
  select * into champ from b2b.ml_models where status = 'champion';
  select * into chall from b2b.ml_models where status = 'challenger';
  select * into shad from b2b.ml_models where status = 'shadow';
  if champ.id is null and chall.id is null and shad.id is null then return '{}'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then return '{}'; end if;
  v_lead := b2b.ml_lead_features(l);
  if not p_holdout then
    if chall.id is not null and (champ.id is null or b2b.u01(p_seed::text, 'challenger') < coalesce((cfg ->> 'challenger_share')::numeric, 0.1)) then
      dec := chall;
    else
      dec := champ;
    end if;
  end if;
  if dec.id is not null then
    v_out := jsonb_build_object('deciding', dec.version,
      'p', (select jsonb_object_agg(c ->> 'partner_id', (b2b.ml_predict(dec.weights, dec.calibration, b2b.ml_features(v_lead, (c ->> 'partner_id')::bigint, c)) ->> 'p')::numeric)
              from jsonb_array_elements(p_cands) c));
  end if;
  -- shadow scores: the shadow model, and a challenger on leads it does not decide
  if shad.id is not null or (chall.id is not null and dec.id is distinct from chall.id) then
    v_out := v_out || jsonb_build_object('shadow', (
      select jsonb_object_agg(mm.version, (select jsonb_object_agg(c ->> 'partner_id', (b2b.ml_predict(mm.weights, mm.calibration, b2b.ml_features(v_lead, (c ->> 'partner_id')::bigint, c)) ->> 'p')::numeric)
                                             from jsonb_array_elements(p_cands) c))
        from b2b.ml_models mm where mm.id in (shad.id, case when dec.id is distinct from chall.id then chall.id end)));
  end if;
  return v_out;
end $fn$;

/* Once a day, for each deciding model (champion, challenger):
   - calibration on its matured leads: above ece_fallback the model is retired (the engine falls back to segment P̂) and
     the Admin is alerted (alert.model_fallback);
   - prediction drift, like for like: the model's mean P over the eligible candidates of its decisions in the last 30 days,
     against the same over its holdout's logged decisions (mean_p_reference: computed once, then kept in metrics.monitor);
   - feature drift: PSI of each lead feature's presence, its decisions in the last 30 days against its training rows.
   With at least drift_min_decisions (200) decisions in 30 days, a largest PSI above psi_alert (0.25) or a mean P that moved
   by more than pred_drift_rel (0.5) of the reference raises alert.model_drift for the Admin. Drift never retires a model.
   The model's P of a candidate is the logged p_model, or p_used when p_source = 'model' (the Addendum 3 format). */
create or replace function b2b.ml_monitor()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ml_cfg();
  prm jsonb := b2b.engine_params(true);
  m b2b.ml_models;
  v_md int := coalesce((prm ->> 'maturity_days')::int, (prm ->> 'matured_days')::int, 60);
  v_eval jsonb;
  v_recent numeric;
  v_ref numeric;
  v_psi jsonb;
  v_drift boolean;
  v_out jsonb := '[]';
begin
  perform set_config('b2b.actor', 'engine', true);
  for m in select * from b2b.ml_models where status in ('champion', 'challenger') loop
    -- calibration: the model's P for the partner that won, against enrolment, on matured allocations
    select b2b.ml_eval(array_agg(cc.p::float8), array_agg(case when e.status is not null then 1 else 0 end::float8))
      into v_eval
      from b2b.engine_decisions d
      join b2b.allocations a on a.engine_decision_id = d.id and not a.is_test and a.status in ('pushed', 'accepted', 'closed')
      cross join lateral (select coalesce(c ->> 'p_model', case when c ->> 'p_source' = 'model' then c ->> 'p_used' end)::numeric p
                            from jsonb_array_elements(d.candidates) c
                           where (c ->> 'partner_id')::bigint = d.winner_partner_id and (c ? 'p_model' or c ->> 'p_source' = 'model') limit 1) cc
      left join lateral (select x.status from public.enrollments x where x.allocation_id = a.id order by x.id desc limit 1) e on true
     where d.model_version = m.version and a.created_at <= now() - make_interval(days => v_md);

    -- prediction drift, like for like: the model's P over every eligible candidate in the last 30 days ...
    select avg(coalesce(c ->> 'p_model', case when c ->> 'p_source' = 'model' then c ->> 'p_used' end)::numeric) into v_recent
      from b2b.engine_decisions d, jsonb_array_elements(d.candidates) c
     where d.model_version = m.version and not d.is_test and d.created_at > now() - interval '30 days'
       and coalesce((c ->> 'eligible')::boolean, true) and (c ? 'p_model' or c ->> 'p_source' = 'model');
    -- ... against the same over the holdout's logged decisions, computed once, then cached
    v_ref := (m.metrics -> 'monitor' ->> 'mean_p_reference')::numeric;
    if v_ref is null then
      select avg((b2b.ml_predict(m.weights, m.calibration, b2b.ml_features(b2b.ml_lead_features(l), (c ->> 'partner_id')::bigint, c)) ->> 'p')::numeric)
        into v_ref
        from b2b.ml_training_rows r
        join b2b.engine_decisions d on d.id = r.decision_id
        join public.student_leads l on l.id = d.lead_id
        cross join lateral jsonb_array_elements(d.candidates) c
       where r.model_id = m.id and r.split = 'valid' and coalesce((c ->> 'eligible')::boolean, true);
    end if;

    -- feature drift: PSI of each lead feature's presence, this model's decisions in 30 days against its training rows.
    -- The training rows also hold ml_features' partner and candidate keys (p:*, p_logit, sla, sla_missing; effort under
    -- Addendum 3): keep the regex in step with ml_features.
    with live as (select b2b.ml_lead_features(l) - '_src' - '_lvl' x
                    from b2b.engine_decisions d join public.student_leads l on l.id = d.lead_id
                   where d.model_version = m.version and not d.is_test and d.created_at > now() - interval '30 days'),
         tr as (select r.x from b2b.ml_training_rows r where r.model_id = m.id),
         n as (select (select count(*) from live)::float8 nl, (select count(*) from tr)::float8 nt),
         kl as (select f.key, count(*)::float8 k from live, jsonb_object_keys(live.x) f(key) where f.key <> 'score' group by 1),
         kt as (select f.key, count(*)::float8 k from tr, jsonb_object_keys(tr.x) f(key)
                 where f.key !~ '^(p:|p_logit$|sla|effort|score$)' group by 1),
         sh as (select coalesce(kl.key, kt.key) key, (coalesce(kl.k, 0) + 0.5) / (n.nl + 1) a, (coalesce(kt.k, 0) + 0.5) / (n.nt + 1) e
                  from kl full join kt on kt.key = kl.key cross join n),
         psi as (select sh.key, sh.a, sh.e, (sh.a - sh.e) * ln(sh.a / sh.e) + (sh.e - sh.a) * ln((1 - sh.a) / (1 - sh.e)) v from sh)
    select case when n.nt >= 30 then jsonb_build_object('n_live', n.nl::int, 'n_training', n.nt::int,
             'max', round(coalesce((select max(v) from psi), 0)::numeric, 4),
             'top', coalesce((select jsonb_agg(jsonb_build_object('feature', t.key, 'training', round(t.e::numeric, 3), 'recent', round(t.a::numeric, 3),
                                                                  'psi', round(t.v::numeric, 4)) order by t.v desc)
                                from (select * from psi order by v desc limit 5) t), '[]'),
             'score_training', (select round(avg((tr.x ->> 'score')::numeric), 3) from tr),
             'score_30d', (select round(avg((live.x ->> 'score')::numeric), 3) from live)) end
      into v_psi from n;

    v_drift := coalesce(coalesce((v_psi ->> 'n_live')::int, 0) >= coalesce((cfg ->> 'drift_min_decisions')::int, 200)
                        and (coalesce((v_psi ->> 'max')::numeric, 0) > coalesce((cfg ->> 'psi_alert')::numeric, 0.25)
                             or (v_ref > 0 and v_recent is not null
                                 and abs(v_recent - v_ref) > coalesce((cfg ->> 'pred_drift_rel')::numeric, 0.5) * v_ref)), false);

    update b2b.ml_models set metrics = metrics || jsonb_build_object('monitor', jsonb_build_object('at', now(), 'matured', v_eval - 'deciles',
                                     'deciles', v_eval -> 'deciles', 'mean_p_30d', round(v_recent, 5),
                                     'mean_p_training', metrics -> 'holdout' -> 'mean_p',
                                     'mean_p_reference', round(v_ref, 5), 'feature_psi', v_psi, 'drift', v_drift))
     where id = m.id;
    -- for the Admin only: drift never retires a model
    if v_drift then
      perform b2b.log_event('alert.model_drift', null, null, null, jsonb_build_object('version', m.version, 'status', m.status,
        'max_psi', v_psi -> 'max', 'top', v_psi -> 'top', 'mean_p_30d', round(v_recent, 5), 'mean_p_reference', round(v_ref, 5)));
    end if;

    if coalesce((v_eval ->> 'n')::int, 0) >= 100 and (v_eval ->> 'ece')::numeric > (cfg ->> 'ece_fallback')::numeric then
      update b2b.ml_models set status = 'retired', status_at = now(), status_by = 'engine',
             status_reason = format('calibration error %s above %s on %s matured leads: fell back to segment P̂', v_eval ->> 'ece', cfg ->> 'ece_fallback', v_eval ->> 'n'),
             was_champion = was_champion or m.status = 'champion'
       where id = m.id;
      perform b2b.log_event('alert.model_fallback', null, null, null, jsonb_build_object('version', m.version, 'was', m.status, 'ece', v_eval ->> 'ece', 'n', v_eval ->> 'n'));
      v_out := v_out || jsonb_build_object('version', m.version, 'retired', true);
    else
      v_out := v_out || jsonb_build_object('version', m.version, 'ece', v_eval ->> 'ece', 'n', v_eval ->> 'n');
    end if;
  end loop;
  return v_out;
end $fn$;

/* The b2b-ml-tick cron job, every 10 minutes, under statement_timeout 15min (set in the job's command), one at a time
   (an advisory lock: a second tick returns {"busy":true}). In order:
   1. fails a training run queued more than an hour ago that is still 'training': its run never finished (cancelled or
      timed out, which WHEN OTHERS cannot catch), so the queue is freed (ml.model_failed);
   2. queues the nightly run at train_hour_ist (IST) when auto_train is on, nothing is queued and no model was created in
      the last 20 hours;
   3. trains the queued model (ml_train); an error marks it failed (ml.model_failed);
   4. once a day (23 hours after the last ml.monitored event), monitors the champion and the challenger (ml_monitor). */
create or replace function b2b.ml_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ml_cfg();
  m b2b.ml_models;
  v_hour int := extract(hour from now() at time zone 'Asia/Kolkata')::int;
  v_res jsonb := '{}';
  v_last timestamptz;
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.ml_tick')) then return '{"busy":true}'; end if;
  perform set_config('b2b.actor', 'engine', true);
  -- a run that never finished (cancelled or timed out: WHEN OTHERS cannot catch query_canceled) frees the queue
  for m in update b2b.ml_models
              set status = 'failed', error = 'training did not finish within an hour (cancelled or timed out)',
                  status_at = now(), status_by = 'engine'
            where status = 'training' and created_at < now() - interval '1 hour'
           returning * loop
    perform b2b.log_event('ml.model_failed', null, null, null, jsonb_build_object('version', m.version, 'error', 'did not finish within an hour'));
    v_res := v_res || jsonb_build_object('stuck_failed', m.version);
  end loop;
  -- nightly training when the auto switch is on and nothing was trained in the last 20 hours
  if coalesce((cfg ->> 'auto_train')::boolean, true) and v_hour = coalesce((cfg ->> 'train_hour_ist')::int, 2)
     and not exists (select 1 from b2b.ml_models where status = 'training')
     and not exists (select 1 from b2b.ml_models where created_at > now() - interval '20 hours') then
    insert into b2b.ml_models (version, requested_by) values ('v' || to_char(now() at time zone 'Asia/Kolkata', 'YYYYMMDD-HH24MISS'), 'nightly');
  end if;
  select * into m from b2b.ml_models where status = 'training' order by id limit 1;
  if m.id is not null then
    begin
      v_res := v_res || jsonb_build_object('trained', b2b.ml_train(m.id));
    exception when others then
      update b2b.ml_models set status = 'failed', error = left(sqlerrm, 500), status_at = now(), status_by = 'engine' where id = m.id;
      perform b2b.log_event('ml.model_failed', null, null, null, jsonb_build_object('version', m.version, 'error', left(sqlerrm, 300)));
      v_res := v_res || jsonb_build_object('failed', m.version, 'error', left(sqlerrm, 300));
    end;
  end if;
  select max(occurred_at) into v_last from b2b.events where type = 'ml.monitored';
  if v_last is null or v_last < now() - interval '23 hours' then
    if exists (select 1 from b2b.ml_models where status in ('champion', 'challenger')) then
      v_res := v_res || jsonb_build_object('monitor', b2b.ml_monitor());
    end if;
    perform b2b.log_event('ml.monitored', null, null, null, '{}');
  end if;
  return v_res;
end $fn$;

-- The timeout is part of the job's command: a SET clause on the function would not work, because the statement timer is
-- armed when the outer statement starts. An existing job only gets the new command and keeps its active flag, so a job
-- paused for the promotion window stays paused.
do $cron$
begin
  if exists (select 1 from cron.job where jobname = 'b2b-ml-tick') then
    perform cron.alter_job(jobid, command := 'set statement_timeout = ''15min''; select b2b.ml_tick()') from cron.job where jobname = 'b2b-ml-tick';
  else
    perform cron.schedule('b2b-ml-tick', '*/10 * * * *', 'set statement_timeout = ''15min''; select b2b.ml_tick()');
  end if;
end $cron$;

revoke execute on function b2b.ml_cfg(), b2b.ml_isotonic(float8[], float8[]), b2b.ml_eval(float8[], float8[]), b2b.ml_train(bigint),
                           b2b.ml_champion_check(bigint), b2b.model_score(bigint, jsonb, numeric, boolean), b2b.ml_monitor(), b2b.ml_tick()
  from public, anon, authenticated;
grant execute on function b2b.ml_cfg(), b2b.ml_isotonic(float8[], float8[]), b2b.ml_eval(float8[], float8[]), b2b.ml_train(bigint),
                          b2b.ml_champion_check(bigint), b2b.model_score(bigint, jsonb, numeric, boolean), b2b.ml_monitor(), b2b.ml_tick()
  to service_role;
