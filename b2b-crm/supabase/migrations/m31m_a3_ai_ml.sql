-- M31m: Addendum 3, part 13: AI and ML (docs/B2B_CRM_ADDENDUM_3.md PART 4 Step 3 'Highest score wins' and 'Bounds and
-- weights are Admin settings, versioned. The Claude optimiser may tune them only inside these ranges'; design D23, D24,
-- D27, D29 and the m31m section; CONTRACT.md section 11; findings C1, C4, C5, C8, C9, C10, C11, C15, C16, C23, C26, C28,
-- C29, C30, C31, C32, C34, C41, C42, C45, C46, C47, C48, C49, C53, C56, C93, C95, C100, C102, C113, C121, C126).
--   ML  ml_isotonic (tied scores pooled, every block shrunk toward the training rate and pooled again, so P is never 0
--       or 1), ml_eval (deterministic bins), ml_predict (duplicate bins averaged, clipped to [0.005, 0.995]),
--       ml_lead_features / ml_features (the Addendum 3 features: temperature, qualification, job, course, university,
--       paid platform, decision-time partner values: backlog, working hours, speed to first contact, connect rate, fee
--       band and budget fit; SLA adherence and the log of the effort factor), ml_train (the decision's own feature
--       snapshot, the decision-day P̂, a doubly robust policy value over Stage C decisions with a strict gate, and a
--       passing shadow that a failing run does not displace), ml_champion_check (Stage C decisions since the challenger's
--       status_at, fixed 60-day maturity, upheld after-acceptance duplicates left out).
--   AI  ai_validate_change / ai_change_path (five levers only: effort_weights, effort_bounds, sla_floor, half_life_days
--       and prior_weight, inside the Admin's current bounds; written to engine_policy.ai.<lever>, never the Admin's
--       slots), ai_policy_probs (deterministic replay of the stored candidates under the changed levers, the lane only
--       where the decision could take it), ai_simulate (doubly robust against the current policy, decisions matured in
--       the window, a support share), ai_simulate_recent (young decisions, projected), ai_uplift (matured window and a
--       95% interval), ai_tool (per-type alert whitelist, reason codes only, the sales_effort and programme-CPE reads,
--       no address or number in settings history), the writers ai_apply_setting / ai_recommendation_decide /
--       ai_recommendation_rollback / ai_review_tick / ai_autopilot_tick (one writer, the settings row locked, the run
--       stamped on the version, no e-mail in reasons, an older change on the same lever superseded, a rollback refused
--       once the value moved on, Autopilot paused while routing is off, a support gate, created_at then id order, the
--       realised effect after maturity), simulate_change (the Admin's ranges).
--   Data ai.autopilot.min_support 0.5; engine_policy.ai keeps the five levers only; models still in use at this point
--       were trained on the old features and are retired once (a new shadow comes from the nightly run or the Admin's
--       'Train now'); nothing here touches student_leads, Witty (w2_*) or the catalogue.
-- Every function: schema b2b, set search_path = '', $fn$ quoting; same signatures as m25a/m25b/m26a/m26b/m30a (create or
-- replace keeps their grants, restated at the end). New: ai_alert_detail, ai_version_stamp, ai_simulate_recent
-- (service_role only). Idempotent: re-applying changes nothing.

-- ======================================================================================================== ML
/* Isotonic regression (pool adjacent violators) of y on score, as ascending bins [{upto, p, n}] (C9, C11):
   rows with the same 6-place score form one block first (ml_predict compares at that precision, so the fit does not
   depend on row order); every block is then shrunk toward the training positive rate with two pseudo-rows and the
   shrunk values are pooled again so the bins stay increasing; p is clipped to [0.005, 0.995]. */
create or replace function b2b.ml_isotonic(p_scores float8[], p_y float8[])
returns jsonb language plpgsql immutable set search_path = '' as $fn$
declare
  n int := coalesce(array_length(p_scores, 1), 0);
  gs float8[]; gy float8[]; gn float8[];
  bs float8[] := '{}'; bn float8[] := '{}'; bu float8[] := '{}';
  sp float8[] := '{}'; sw float8[] := '{}'; sn float8[] := '{}'; su float8[] := '{}';
  k int := 0; j int := 0; i int; v_base float8; out jsonb := '[]';
begin
  if n = 0 then return '[]'; end if;
  v_base := (select coalesce(sum(y), 0) from unnest(p_y) y) / n;
  -- ties pooled: rows with the same 6-place score form one group (F19)
  select array_agg(t.s order by t.s), array_agg(t.sy order by t.s), array_agg(t.c order by t.s) into gs, gy, gn
    from (select round(p_scores[o]::numeric, 6)::float8 s, sum(p_y[o]) sy, count(*)::float8 c from generate_series(1, n) o group by 1) t;
  for i in 1 .. array_length(gs, 1) loop
    k := k + 1; bs[k] := gy[i]; bn[k] := gn[i]; bu[k] := gs[i];
    while k > 1 and bs[k-1] / bn[k-1] >= bs[k] / bn[k] loop
      bs[k-1] := bs[k-1] + bs[k]; bn[k-1] := bn[k-1] + bn[k]; bu[k-1] := bu[k]; k := k - 1;
    end loop;
  end loop;
  -- shrink each block toward the training rate (2 pseudo-rows, F20/F32), then pool again so the bins stay increasing
  for i in 1 .. k loop
    j := j + 1; sp[j] := (bs[i] + 2 * v_base) / (bn[i] + 2); sw[j] := bn[i] + 2; sn[j] := bn[i]; su[j] := bu[i];
    while j > 1 and sp[j-1] >= sp[j] loop
      sp[j-1] := (sp[j-1] * sw[j-1] + sp[j] * sw[j]) / (sw[j-1] + sw[j]); sw[j-1] := sw[j-1] + sw[j]; sn[j-1] := sn[j-1] + sn[j]; su[j-1] := su[j]; j := j - 1;
    end loop;
  end loop;
  for i in 1 .. j loop
    out := out || jsonb_build_object('upto', round(su[i]::numeric, 6), 'p', round(least(greatest(sp[i], 0.005), 0.995)::numeric, 6), 'n', sn[i]::int);
  end loop;
  return out;
end $fn$;

/* Log loss, ECE (10 equal-count bins) and deciles of predictions p against outcomes y. The bins split ties by input
   position, so a baseline with many equal predictions (segment P̂ per partner) gets the same ECE on every run (C121). */
create or replace function b2b.ml_eval(p_p float8[], p_y float8[])
returns jsonb language sql immutable set search_path = '' as $fn$
  with d as (select u.p, u.y, ntile(10) over (order by u.p, u.i) b from unnest(p_p, p_y) with ordinality u(p, y, i)),
       bins as (select b, avg(p) mp, avg(y) my, count(*) n from d group by b)
  select jsonb_build_object(
    'n', (select count(*) from d),
    'log_loss', (select round(avg(-(y * ln(least(greatest(p, 1e-4), 1 - 1e-4)) + (1 - y) * ln(1 - least(greatest(p, 1e-4), 1 - 1e-4))))::numeric, 6) from d),
    'ece', (select round((sum(n * abs(mp - my)) / nullif(sum(n), 0))::numeric, 6) from bins),
    'mean_p', (select round(avg(p)::numeric, 6) from d), 'mean_y', (select round(avg(y)::numeric, 6) from d),
    'deciles', coalesce((select jsonb_agg(jsonb_build_object('bin', b, 'pred', round(mp::numeric, 4), 'actual', round(my::numeric, 4), 'n', n) order by b) from bins), '[]'));
$fn$;

/* Raw and calibrated P(enrol) of one feature vector under one model: the first bin with upto >= the 6-place score;
   duplicate upto values in a stored calibration are averaged, weighted by n; p is clipped to [0.005, 0.995] (C9, C11). */
create or replace function b2b.ml_predict(p_weights jsonb, p_calibration jsonb, p_x jsonb)
returns jsonb language sql immutable set search_path = '' as $fn$
  with s as (select coalesce((p_weights ->> '(bias)')::float8, 0)
                    + coalesce(sum(coalesce((p_weights ->> f.key)::float8, 0) * f.value::float8), 0) z
               from jsonb_each_text(p_x) f where f.value ~ '^-?[0-9.]+(e-?[0-9]+)?$'),
       r as (select 1 / (1 + exp(-least(greatest(s.z, -30), 30))) raw from s),
       cal as (select (c ->> 'upto')::numeric upto, sum((c ->> 'p')::numeric * coalesce((c ->> 'n')::numeric, 1)) / sum(coalesce((c ->> 'n')::numeric, 1)) p
                 from jsonb_array_elements(case when jsonb_typeof(p_calibration) = 'array' then p_calibration else '[]'::jsonb end) c group by 1)
  select jsonb_build_object('raw', round(r.raw::numeric, 6),
    'p', round(least(greatest(coalesce((select cal.p from cal where cal.upto >= round(r.raw::numeric, 6) order by cal.upto limit 1),
                                       (select cal.p from cal order by cal.upto desc limit 1),
                                       r.raw::numeric), 0.005), 0.995), 6))
  from r;
$fn$;

/* The lead's side of the features (privacy-safe buckets; never name, phone, e-mail, city, state or chat text; C45):
   source, Witty label, level, mode, experience, budget band, timeline, enquirer, Hindi, paid (b2b.lead_attribution) with
   the platform, weekend and hour of the current cycle's intake (reopened_at, else created_at; C46), lead score,
   temperature, qualification level (b2b.qualification_level, as the partner criteria use it), job category, course
   key and the university when exactly one resolves. '_src', '_lvl' and '_budget' are inputs for ml_features only. */
create or replace function b2b.ml_lead_features(l public.student_leads)
returns jsonb language sql stable set search_path = '' as $fn$
  with li as (select b2b.lead_interest(l) i),
       at as (select coalesce(b2b.lead_attribution(l), '{}'::jsonb) a),
       b as (
    select
      case when lower(coalesce(l.lead_source, '') || ' ' || coalesce(l.channel, '')) ~ '(whatsapp|witty)' then 'whatsapp'
           when lower(coalesce(l.lead_source, '') || ' ' || coalesce(l.utm_source, '')) ~ '(meta|facebook|instagram|fb)' then 'meta'
           when lower(coalesce(l.lead_source, '') || ' ' || coalesce(l.utm_source, '')) ~ 'google' then 'google'
           when lower(coalesce(l.lead_source, '')) ~ 'import' then 'import'
           when lower(coalesce(l.lead_source, '')) ~ '(referr|influenc|partner)' then 'referral'
           when lower(coalesce(l.lead_source, '')) ~ '(web|site|organic|seo|form)' then 'website'
           else 'other' end src,
      case when upper(coalesce(l.lead_status, '')) in ('HOT', 'WARM', 'COLD') then upper(l.lead_status) else 'NA' end st,
      coalesce(li.i ->> 'level', 'NA') lvl,
      coalesce(li.i ->> 'mode', 'NA') md,
      case when l.work_experience_years_num is null then 'NA' when l.work_experience_years_num < 1 then '0'
           when l.work_experience_years_num < 3 then '1-3' when l.work_experience_years_num < 7 then '3-7' else '7+' end exp,
      case when l.annual_budget_inr is null then 'NA' when l.annual_budget_inr < 100000 then 'lt1L' when l.annual_budget_inr < 200000 then '1-2L'
           when l.annual_budget_inr < 400000 then '2-4L' else '4L+' end bud,
      lower(coalesce(l.enrollment_timeline, '')) ~ '(immediate|asap|this month|next month|1 month|within a month|now)' soon,
      lower(coalesce(l.enquirer_relation, '')) ~ '(parent|father|mother|guardian)' parent,
      extract(hour from (coalesce(l.reopened_at, l.created_at) at time zone 'Asia/Kolkata'))::int hr,
      extract(isodow from (coalesce(l.reopened_at, l.created_at) at time zone 'Asia/Kolkata'))::int dow,
      lower(coalesce(l.preferred_language, '')) ~ '(hindi|hinglish)' hindi,
      coalesce((at.a ->> 'paid')::boolean, false) paid,
      at.a ->> 'platform' platform,
      coalesce(nullif(lower(trim(l.temperature)), ''), 'na') temp,
      coalesce(b2b.qualification_level(l.highest_qualification), 'na') qual,
      case when coalesce(trim(l.current_job_role), '') = '' then 'na'
           when lower(l.current_job_role) ~ '(student|fresher|unemploy|not working)' then 'none'
           when lower(l.current_job_role) ~ '(manager|head|director|founder|owner|\mvp\M)' then 'manager'
           else 'employed' end job,
      coalesce(li.i ->> 'course_key', 'na') course,
      li.i ->> 'university_id' uni
    from li, at)
  select jsonb_strip_nulls(jsonb_build_object(
           'src:' || b.src, 1, 'status:' || b.st, 1, 'level:' || b.lvl, 1, 'mode:' || b.md, 1, 'exp:' || b.exp, 1, 'budget:' || b.bud, 1,
           'soon', case when b.soon then 1 end, 'parent', case when b.parent then 1 end, 'hindi', case when b.hindi then 1 end,
           'paid', case when b.paid then 1 end, 'weekend', case when b.dow >= 6 then 1 end,
           'hour:' || case when b.hr between 6 and 11 then 'morning' when b.hr between 12 and 16 then 'afternoon' when b.hr between 17 and 21 then 'evening' else 'night' end, 1,
           'score', case when l.lead_score is not null then round(least(greatest(l.lead_score, 0), 100) / 100.0, 3) end,
           'temp:' || b.temp, 1, 'qual:' || b.qual, 1, 'job:' || b.job, 1, 'course:' || b.course, 1,
           '_budget', l.annual_budget_inr, '_src', b.src, '_lvl', b.lvl))
         || case when b.uni is not null then jsonb_build_object('uni:' || b.uni, 1) else '{}'::jsonb end
         || case when b.paid and b.platform in ('meta', 'google') then jsonb_build_object('platform:' || b.platform, 1) else '{}'::jsonb end
  from b;
$fn$;

/* Features of one lead for one candidate partner: the lead's buckets, the partner, partner x source and partner x level
   interactions, the partner's segment P̂ (log-odds), its SLA adherence (sla_missing when none was logged), the log of
   its applied effort factor (effort_missing when none), and the decision-time partner values stage_score logs with
   every candidate (C45): backlog, outside working hours (also per partner), speed to first contact over 7 and 30 days,
   connect rate, live_missing, the fee band and how the student's budget fits the fee. Immutable: jsonb in, jsonb out. */
create or replace function b2b.ml_features(p_lead jsonb, p_partner_id bigint, p_cand jsonb)
returns jsonb language sql immutable set search_path = '' as $fn$
  select (p_lead - '_src' - '_lvl' - '_budget')
      || jsonb_build_object(
           'p:' || p_partner_id, 1,
           'p:' || p_partner_id || '|src:' || coalesce(p_lead ->> '_src', 'other'), 1,
           'p:' || p_partner_id || '|level:' || coalesce(p_lead ->> '_lvl', 'NA'), 1,
           'p_logit', round(ln(v.ph / (1 - v.ph)), 4),
           'sla', round(coalesce(v.sla, 0.8), 4),
           'effort', round(ln(greatest(coalesce(v.ef, 1), 0.01)), 4))
      || case when v.sla is null then '{"sla_missing":1}'::jsonb else '{}'::jsonb end
      || case when v.ef is null then '{"effort_missing":1}'::jsonb else '{}'::jsonb end
      || jsonb_strip_nulls(jsonb_build_object(
           'backlog', round(ln(1 + least(coalesce(v.bl, 0), 1000)) / ln(1001::numeric), 4),
           'off_hours', case when v.ih is false then 1 end,
           'p:' || p_partner_id || '|off_hours', case when v.ih is false then 1 end,
           'fch7', round(least(coalesce(v.f7, v.f30, 24), 72) / 72, 4),
           'fch30', round(least(coalesce(v.f30, 24), 72) / 72, 4),
           'connect', round(v.cn, 4),
           'live_missing', case when v.bl is null then 1 end,
           'fee:' || case when v.fee is null then 'NA' when v.fee < 100000 then 'lt1L' when v.fee < 200000 then '1-2L' when v.fee < 400000 then '2-4L' else '4L+' end, 1,
           'budget_fit:' || case when v.bud is null or coalesce(v.fee, 0) <= 0 then 'NA' when v.bud < 0.8 * v.fee then 'under'
                                 when v.bud <= 1.2 * v.fee then 'fits' else 'over' end, 1))
    from (select least(greatest(coalesce((p_cand ->> 'p_hat')::numeric, 0.05), 0.001), 0.999) ph,
                 coalesce((p_cand ->> 'sla_adherence')::numeric, (p_cand ->> 'sla_compliance')::numeric) sla,
                 (p_cand ->> 'effort_factor')::numeric ef,
                 (p_cand ->> 'open_backlog')::numeric bl,
                 (p_cand ->> 'in_hours')::boolean ih,
                 (p_cand ->> 'fch_7d')::numeric f7,
                 (p_cand ->> 'fch_30d')::numeric f30,
                 (p_cand ->> 'connect_30d')::numeric cn,
                 (p_cand ->> 'fee_inr')::numeric fee,
                 (p_lead ->> '_budget')::numeric bud) v;
$fn$;

/* Training (C46, C47, C48, C49, C121): the newest 50,000 matured outcomes (matured = a3_fixed.matured_days, 60), each
   with the lead features its decision stored (features), else the row as it is now (pre-Addendum 3 staging rows only);
   the candidate as logged, its P̂ from the logged candidate, else the stats snapshot of the decision's IST day (never
   today's stats, which already hold the outcome); the newest valid_share held out. Fit as in m25b (AdaGrad, L2, isotonic
   calibration). Holdout metrics against segment P̂ with the arrays in one fixed order. The policy value is doubly robust
   over the Stage C partner decisions of the validation period that the model could have taken (mode performance or
   exploration, not holdout, not test, matured): r̂(c) = logged P x CPE x (1 - refund rate) per candidate; the logged
   policy's value is Σ π_log(c) r̂(c) + (r - r̂(a)); the model policy picks argmax of model P x CPE x (1 - refund) with the
   Addendum 3 ties and gets r̂(m) + [m = a] / π_log(a) x (r - r̂(a)); the realised r is the CPE when the allocation enrolled
   and was not refunded, cancelled or an upheld duplicate, else 0 (duplicates, rejections and lost leads stay in the set).
   The gate: min_outcomes, min_partners, strictly better log loss and no worse ECE than segment P̂, and at least 30 such
   decisions with DR(model) > DR(logged), strictly. A failing run never displaces a shadow that passed the gate within the
   last 30 days: the new model goes straight to retired, with its metrics (kept_shadow). */
create or replace function b2b.ml_train(p_model_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ml_cfg();
  prm jsonb := b2b.engine_params(true);
  v_md int := round(coalesce(b2b.stats_num(prm -> 'matured_days'), b2b.stats_num(prm -> 'maturity_days'), 60))::int;
  v_dpe numeric := coalesce(b2b.stats_num(prm -> 'default_p_enroll'), 0.05);
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
  v_dr jsonb;
  v_gate jsonb;
  v_valid_from timestamptz;
  v_keep boolean;
  i int;
begin
  select * into m from b2b.ml_models where id = p_model_id and status = 'training' for update;
  if m.id is null then raise exception 'no model waiting for training' using errcode = 'P0002'; end if;
  perform set_config('b2b.actor', 'engine', true);

  -- 1. rows: the newest 50,000 matured outcomes, features as the decision stored them, P̂ as it was on the decision's day
  insert into b2b.ml_training_rows (model_id, allocation_id, split, y, x, baseline_p, decision_id)
  select m.id, o.allocation_id,
         case when row_number() over (order by o.created_at, o.allocation_id) > ceil(count(*) over () * (1 - (cfg ->> 'valid_share')::numeric)) then 'valid' else 'train' end,
         case when o.enrolled then 1 else 0 end,
         b2b.ml_features(coalesce(dd.features, b2b.ml_lead_features(l)), o.partner_id,
                         coalesce(cand.c, '{}'::jsonb) || jsonb_build_object('p_hat', coalesce((cand.c ->> 'p_hat')::numeric, snap.p_hat, v_dpe))),
         coalesce((cand.c ->> 'p_hat')::numeric, snap.p_hat, v_dpe),
         a.engine_decision_id
    from (select * from b2b.allocation_outcomes() x
           where x.age_days >= v_md
           order by x.created_at desc, x.allocation_id desc limit 50000) o
    join b2b.allocations a on a.id = o.allocation_id
    join public.student_leads l on l.id = o.lead_id
    left join b2b.engine_decisions dd on dd.id = a.engine_decision_id
    left join lateral (select c from jsonb_array_elements(case when jsonb_typeof(dd.candidates) = 'array' then dd.candidates else '[]'::jsonb end) c
                        where (c ->> 'partner_id')::bigint = o.partner_id limit 1) cand on true
    left join lateral (select s.p_hat from b2b.stats_snapshots s
                        where s.partner_id = o.partner_id and s.segment in (o.segment, b2b.segment_rollup(o.segment))
                          and s.day <= (o.created_at at time zone 'Asia/Kolkata')::date
                        order by s.day desc, (s.segment = o.segment) desc limit 1) snap on true;

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

  -- 5. holdout metrics: the model against segment P̂, both arrays in one fixed order (C121)
  select b2b.ml_eval(array_agg((b2b.ml_predict(w, v_cal, r.x) ->> 'p')::float8 order by r.allocation_id), array_agg(r.y::float8 order by r.allocation_id)),
         b2b.ml_eval(array_agg(r.baseline_p::float8 order by r.allocation_id), array_agg(r.y::float8 order by r.allocation_id))
    into v_eval, v_base from b2b.ml_training_rows r where r.model_id = m.id and r.split = 'valid';

  -- 6. doubly robust policy value over the Stage C decisions of the validation period (C48)
  select min(a.created_at) into v_valid_from
    from b2b.ml_training_rows r join b2b.allocations a on a.id = r.allocation_id where r.model_id = m.id and r.split = 'valid';
  with dec as (
    select d.id, d.selection_probability::numeric sp, d.winner_partner_id win, d.candidates,
           coalesce(d.features, b2b.ml_lead_features(l)) lf,
           case when e.status is not null and e.status not in ('refunded', 'cancelled') and a.outcome is distinct from 'duplicate_upheld'
                 and not exists (select 1 from b2b.commission_disputes cd where cd.allocation_id = a.id and cd.status = 'upheld' and cd.kind = 'duplicate_after_acceptance')
                then coalesce(a.cpe_net_inr, 0) else 0 end reward
      from b2b.engine_decisions d
      join b2b.allocations a on a.engine_decision_id = d.id and a.destination_type = 'partner' and not a.is_test
      join public.student_leads l on l.id = d.lead_id
      left join lateral (select x.status from public.enrollments x where x.allocation_id = a.id order by (x.status <> 'cancelled') desc, x.id desc limit 1) e on true
     where d.stage = 'C' and not d.holdout and not d.is_test and d.destination_type = 'partner'
       and d.mode in ('performance', 'exploration') and d.selection_probability > 0
       and v_valid_from is not null and d.created_at >= v_valid_from
       and d.created_at <= now() - make_interval(days => v_md)),
  cands as (
    select dec.id, (c ->> 'partner_id')::bigint pid,
           case when (c ->> 'partner_id')::bigint = dec.win then dec.sp else coalesce((c ->> 'propensity')::numeric, 0) end pi_log,
           coalesce((c ->> 'p_used')::numeric, (c ->> 'p_hat')::numeric, 0) * coalesce((c ->> 'cpe')::numeric, 0) * (1 - coalesce((c ->> 'refund_rate')::numeric, 0)) rhat,
           (b2b.ml_predict(w, v_cal, b2b.ml_features(dec.lf, (c ->> 'partner_id')::bigint, c)) ->> 'p')::numeric
             * coalesce((c ->> 'cpe')::numeric, 0) * (1 - coalesce((c ->> 'refund_rate')::numeric, 0)) mscore,
           (c ->> 'cpe')::numeric cpe, (c ->> 'sla_adherence')::numeric sla, coalesce((c ->> 'leads_week')::int, 0) lw
      from dec, jsonb_array_elements(case when jsonb_typeof(dec.candidates) = 'array' then dec.candidates else '[]'::jsonb end) c
     where coalesce((c ->> 'eligible')::boolean, true) and (c ->> 'partner_id') is not null),
  pick as (
    select q.id, q.pid mpick, q.pi_log mpi, q.rhat mrhat
      from (select cands.*, row_number() over (partition by cands.id order by cands.mscore desc, cands.cpe desc nulls last, cands.sla desc nulls last, cands.lw, cands.pid) rn
              from cands) q
     where q.rn = 1),
  per as (
    select dec.id, dec.reward, dec.sp, dec.win, pick.mpick, pick.mpi, pick.mrhat,
           (select sum(cands.pi_log * cands.rhat) from cands where cands.id = dec.id) dm_log,
           (select cands.rhat from cands where cands.id = dec.id and cands.pid = dec.win limit 1) rhat_a
      from dec join pick on pick.id = dec.id)
  select jsonb_build_object(
    'decisions', count(*), 'agree', count(*) filter (where mpick = win),
    'logged_value', round(coalesce(avg(coalesce(dm_log, 0) + (reward - coalesce(rhat_a, 0))), 0), 2),
    'model_value', round(coalesce(avg(coalesce(mrhat, 0) + case when mpick = win then (reward - coalesce(rhat_a, 0)) / sp else 0 end), 0), 2),
    'support', round(coalesce(avg(case when mpi > 0 then 1 else 0 end), 0), 4),
    'ess', round(coalesce(power(sum(case when mpick = win then 1 / sp else 0 end), 2)
                          / nullif(sum(case when mpick = win then 1 / (sp * sp) else 0 end), 0), 0), 1),
    'estimator', 'doubly_robust', 'from', v_valid_from, 'matured_days', v_md)
    into v_dr from per;

  v_gate := jsonb_build_object(
    'outcomes', v_n, 'min_outcomes', (cfg ->> 'min_outcomes')::int, 'outcomes_ok', v_n >= (cfg ->> 'min_outcomes')::int,
    'partners', v_partners, 'partners_ok', v_partners >= (cfg ->> 'min_partners')::int,
    'beats_baseline', coalesce((v_eval ->> 'log_loss')::numeric < (v_base ->> 'log_loss')::numeric and (v_eval ->> 'ece')::numeric <= (v_base ->> 'ece')::numeric, false),
    'policy_value_ok', coalesce((v_dr ->> 'decisions')::int >= 30 and (v_dr ->> 'model_value')::numeric > (v_dr ->> 'logged_value')::numeric, false));
  v_gate := v_gate || jsonb_build_object('passed', (v_gate ->> 'outcomes_ok')::boolean and (v_gate ->> 'partners_ok')::boolean
                                                   and (v_gate ->> 'beats_baseline')::boolean and (v_gate ->> 'policy_value_ok')::boolean);

  -- a new model that failed the gate does not displace a recent shadow that passed it (C49)
  v_keep := not coalesce((v_gate ->> 'passed')::boolean, false)
            and exists (select 1 from b2b.ml_models s
                         where s.status = 'shadow' and s.id <> m.id
                           and coalesce((s.gate ->> 'passed')::boolean, false)
                           and s.trained_at > now() - interval '30 days');
  if not v_keep then
    update b2b.ml_models set status = 'retired', status_at = now(), status_by = 'engine', status_reason = 'replaced by ' || m.version
     where status = 'shadow' and id <> m.id;
  end if;
  update b2b.ml_models
     set status = case when v_keep then 'retired' else 'shadow' end, status_at = now(), status_by = 'engine',
         status_reason = case when v_keep then 'trained; gate not passed, so the shadow that passed it is kept' else 'trained' end,
         trained_at = now(),
         features = (select coalesce(jsonb_agg(k order by k), '[]') from jsonb_object_keys(v_vocab) k), weights = w, calibration = v_cal,
         metrics = jsonb_build_object('holdout', v_eval, 'baseline', v_base, 'policy', v_dr, 'iterations', v_iter, 'l2', v_l2,
                                      'top_weights', (select jsonb_agg(jsonb_build_object('feature', k, 'w', round(v::numeric, 4)) order by abs(v::numeric) desc)
                                                        from (select k, v from jsonb_each_text(w) x(k, v) where k <> '(bias)' order by abs(v::numeric) desc limit 15) t)),
         gate = v_gate,
         trained_on = jsonb_build_object('rows', v_n, 'enrolled', v_pos, 'train', v_ntrain, 'valid', v_nvalid, 'partners', v_partners,
                                         'maturity_days', v_md,
                                         'from', (select min(a.created_at) from b2b.ml_training_rows r join b2b.allocations a on a.id = r.allocation_id where r.model_id = m.id),
                                         'to', (select max(a.created_at) from b2b.ml_training_rows r join b2b.allocations a on a.id = r.allocation_id where r.model_id = m.id))
   where id = m.id;
  perform b2b.log_event('ml.model_trained', null, null, null, jsonb_build_object('version', m.version, 'gate', v_gate, 'holdout', v_eval - 'deciles', 'kept_shadow', v_keep));
  return jsonb_build_object('version', m.version, 'gate', v_gate, 'holdout', v_eval - 'deciles', 'baseline', v_base - 'deciles', 'policy', v_dr, 'kept_shadow', v_keep);
end $fn$;

/* The challenger against the rest: realised net commission per matured lead on the Stage C performance decisions since
   the model became challenger (status_at), not holdout, not test, with at least two eligible candidates (only then can a
   model decide), decided by this model, by the champion or by segment P̂ (a null model_version counts as 'other';
   retired versions and the exploration lane are left out), matured 60 days (a3_fixed), without the reward of an upheld
   after-acceptance duplicate (C10, C53). One-sided z-test at 95%. */
create or replace function b2b.ml_champion_check(p_model_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  with m as (select version, status_at since from b2b.ml_models where id = p_model_id),
       ch as (select version from b2b.ml_models where status = 'champion' and id <> p_model_id),
       md as (select round(coalesce(b2b.stats_num((select s.value -> 'a3_fixed' -> 'matured_days' from b2b.settings s where s.key = 'engine')), 60))::int d),
       r as (select coalesce(d.model_version = m.version, false) is_model,
                    case when e.status is not null and e.status not in ('refunded', 'cancelled') and a.outcome is distinct from 'duplicate_upheld'
                          and not exists (select 1 from b2b.commission_disputes cd where cd.allocation_id = a.id and cd.status = 'upheld' and cd.kind = 'duplicate_after_acceptance')
                         then coalesce(a.cpe_net_inr, 0) else 0 end reward
               from b2b.engine_decisions d
               join b2b.allocations a on a.engine_decision_id = d.id and a.destination_type = 'partner' and not a.is_test
               cross join m cross join md
               left join lateral (select x.status from public.enrollments x where x.allocation_id = a.id order by x.id desc limit 1) e on true
              where d.stage = 'C' and d.mode = 'performance' and not d.holdout and not d.is_test
                and d.created_at >= m.since
                and (d.model_version is null or d.model_version = m.version or d.model_version = (select version from ch))
                and (select count(*) from jsonb_array_elements(case when jsonb_typeof(d.candidates) = 'array' then d.candidates else '[]'::jsonb end) c
                      where coalesce((c ->> 'eligible')::boolean, true)) >= 2
                and a.created_at <= now() - make_interval(days => md.d)
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

/* ml_monitor, from m25b with two changes: the live side of the feature drift reads the decision's stored lead features
   (engine_decisions.features, C46) and the training-row regex leaves out every candidate-derived key ml_features now
   writes, so the PSI compares lead features with lead features. Calibration fallback and prediction drift unchanged.
   Once a day, for each deciding model (champion, challenger):
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

    -- feature drift: PSI of each lead feature's presence, this model's decisions in 30 days (their stored feature snapshot,
    -- C46) against its training rows. The training rows also hold ml_features' partner and candidate keys (p:*, p_logit,
    -- sla*, effort*, backlog, off_hours, fch7, fch30, connect, live_missing, fee:*, budget_fit:*): keep the regex in step
    -- with ml_features.
    with live as (select coalesce(d.features, b2b.ml_lead_features(l)) - '_src' - '_lvl' - '_budget' x
                    from b2b.engine_decisions d join public.student_leads l on l.id = d.lead_id
                   where d.model_version = m.version and not d.is_test and d.created_at > now() - interval '30 days'),
         tr as (select r.x from b2b.ml_training_rows r where r.model_id = m.id),
         n as (select (select count(*) from live)::float8 nl, (select count(*) from tr)::float8 nt),
         kl as (select f.key, count(*)::float8 k from live, jsonb_object_keys(live.x) f(key) where f.key <> 'score' group by 1),
         kt as (select f.key, count(*)::float8 k from tr, jsonb_object_keys(tr.x) f(key)
                 where f.key !~ '^(p:|p_logit$|sla|effort|score$|backlog$|off_hours$|fch7$|fch30$|connect$|live_missing$|fee:|budget_fit:)' group by 1),
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

-- ======================================================================================================== AI helpers
/* What Claude may see of an alert's payload (C8): a whitelist of short scalar keys per type, the engine-written reason
   of an auto-pause, the length of any other reason, the count of unmapped items, and the class of an error. Never proof,
   items, references, error text, a partner-written reason, a name or a title. */
create or replace function b2b.ai_alert_detail(p_type text, p jsonb)
returns jsonb language sql immutable set search_path = '' as $fn$
  select coalesce((select jsonb_object_agg(k, v) from jsonb_each(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) x(k, v)
                    where k = any (array['kind','segment','sla','due_at','is_test','channel','stage','code','where','version','was','ece','n',
                                         'p_hat_before','p_hat_now','ncpl_before','ncpl_now','changes','required','new','dead','rejected',
                                         'days_overdue','outstanding_inr','metric','value','threshold','op','z','platform','source','env',
                                         'spent_usd','budget_usd','event_type','contract_breach','id','alert_id','run_id','snapshot_id',
                                         'invoice_id','outbox_id','endpoint_id','schedule_id','request_id'])
                      and jsonb_typeof(v) in ('number', 'boolean', 'string')
                      and (k <> 'value' or jsonb_typeof(v) = 'number')
                      and (jsonb_typeof(v) <> 'string' or length(v #>> '{}') <= 60)), '{}'::jsonb)
      || case when p_type = 'alert.partner_auto_paused' and p ? 'reason' then jsonb_build_object('reason', left(p ->> 'reason', 120))
              when p ? 'reason' then jsonb_build_object('reason_chars', length(p ->> 'reason')) else '{}'::jsonb end
      || case when jsonb_typeof(p -> 'items') = 'array' then jsonb_build_object('unmapped_items', jsonb_array_length(p -> 'items')) else '{}'::jsonb end
      || case when p ? 'error' then jsonb_strip_nulls(jsonb_build_object('error_class', substring(p ->> 'error' from
           '^(HTTP [0-9]{3}|timeout|no response within 2 minutes|partner is switched off|partner has no [A-Za-z ]+|the CRM refused the credentials)')))
              else '{}'::jsonb end;
$fn$;

/* Stamps the AI run on an engine_policy settings version, and the actor 'autopilot' when Autopilot wrote it (C95). */
create or replace function b2b.ai_version_stamp(p_version int, p_run_id bigint, p_autopilot boolean)
returns void language sql volatile security definer set search_path = '' as $fn$
  update b2b.settings_versions set ai_run_id = p_run_id, actor_type = case when p_autopilot then 'autopilot' else actor_type end
   where key = 'engine_policy' and version = p_version;
  update b2b.settings set actor_type = 'autopilot' where key = 'engine_policy' and version = p_version and p_autopilot;
$fn$;

/* A proposed change, checked against the Addendum 3 levers and the Admin's bounds (PART 4 'The Claude optimiser may
   tune them only inside these ranges'); returns it normalised or raises 22023. Levers: effort_weights (an object over
   the six metrics, each inside a3_fixed.weight_range, positive sum), effort_bounds ([low, high] inside the Admin's
   effort bounds), sla_floor (the Admin's floor to its ceiling), half_life_days (14-60), prior_weight (5-50), rule_draft
   and pause_draft. Everything else, the retired Phase 3 levers included, is 'outside the AI's bounds' (C16, C29, C56).
   JSON types are checked first, with nested IFs (SQL does not short-circuit OR; C93). */
create or replace function b2b.ai_validate_change(p jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  v_lever text := p ->> 'lever';
  fx jsonb := coalesce((select s.value -> 'a3_fixed' from b2b.settings s where s.key = 'engine'), '{}'::jsonb);
  prm jsonb;
  w_lo numeric; w_hi numeric;
  a_lo numeric; a_hi numeric;
  s_floor numeric; s_ceil numeric;
  v_lo numeric; v_hi numeric; v_num numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'no change given' using errcode = '22023'; end if;
  if v_lever in ('sla_floor', 'half_life_days', 'prior_weight') and jsonb_typeof(p -> 'value') is distinct from 'number' then
    raise exception 'the change needs a numeric value' using errcode = '22023';
  end if;
  if v_lever = 'effort_weights' then
    if jsonb_typeof(p -> 'value') is distinct from 'object' then raise exception 'the change needs a weight per metric' using errcode = '22023'; end if;
    if (select count(*) from jsonb_each(p -> 'value')) = 0
       or exists (select 1 from jsonb_each(p -> 'value') w
                   where jsonb_typeof(w.value) <> 'number' or w.key not in ('first_call', 'attempts_72h', 'connect_rate', 'followup', 'acts_per_open', 'stale_share')) then
      raise exception 'the change needs a weight per metric' using errcode = '22023';
    end if;
  end if;
  if v_lever = 'effort_bounds' then
    if jsonb_typeof(p -> 'value') is distinct from 'array' or jsonb_array_length(p -> 'value') <> 2 then
      raise exception 'the change needs [low, high] bounds' using errcode = '22023';
    end if;
    if exists (select 1 from jsonb_array_elements(p -> 'value') x where jsonb_typeof(x) <> 'number') then
      raise exception 'the change needs [low, high] bounds' using errcode = '22023';
    end if;
  end if;
  if v_lever = 'pause_draft' and jsonb_typeof(p -> 'partner_id') is distinct from 'number' then
    raise exception 'the change needs a partner' using errcode = '22023';
  end if;
  -- a value of the wrong type inside a draft (a bad id, a bad date) is a refusal like any other, not a server error
  begin
    case v_lever
    when 'effort_weights' then
      w_lo := greatest(coalesce(b2b.stats_num(fx -> 'weight_range' -> 0), 0), 0);
      w_hi := greatest(coalesce(b2b.stats_num(fx -> 'weight_range' -> 1), 5), w_lo);
      if exists (select 1 from jsonb_each(p -> 'value') w where (w.value #>> '{}')::numeric < w_lo or (w.value #>> '{}')::numeric > w_hi)
         or (select sum((w.value #>> '{}')::numeric) from jsonb_each(p -> 'value') w) <= 0 then
        raise exception '%', format('effort weights are %s to %s each, and not all 0', w_lo, w_hi) using errcode = '22023';
      end if;
      return jsonb_build_object('lever', v_lever, 'value', (select jsonb_object_agg(w.key, round((w.value #>> '{}')::numeric, 3)) from jsonb_each(p -> 'value') w));
    when 'effort_bounds' then
      prm := b2b.engine_params(true);
      a_lo := coalesce(b2b.stats_num(prm -> 'effort' -> 'lo'), 0.85);
      a_hi := coalesce(b2b.stats_num(prm -> 'effort' -> 'hi'), 1.15);
      v_lo := (p -> 'value' ->> 0)::numeric;
      v_hi := (p -> 'value' ->> 1)::numeric;
      if v_lo < a_lo or v_lo > 1 or v_hi < 1 or v_hi > a_hi then
        raise exception '%', format('effort bounds are inside %s to %s for the AI', to_char(a_lo, 'FM0.00'), to_char(a_hi, 'FM0.00')) using errcode = '22023';
      end if;
      return jsonb_build_object('lever', v_lever, 'value', jsonb_build_array(round(v_lo, 3), round(v_hi, 3)));
    when 'sla_floor' then
      prm := b2b.engine_params(true);
      s_floor := coalesce(b2b.stats_num(prm -> 'sla' -> 'floor'), 0.80);
      s_ceil := coalesce(b2b.stats_num(prm -> 'sla' -> 'ceiling'), 1.0);
      v_num := (p ->> 'value')::numeric;
      if v_num < s_floor or v_num > s_ceil then
        raise exception '%', format('the SLA floor is %s to %s%% for the AI', round(s_floor * 100), round(s_ceil * 100)) using errcode = '22023';
      end if;
      return jsonb_build_object('lever', v_lever, 'value', round(v_num, 3));
    when 'half_life_days' then
      v_num := (p ->> 'value')::numeric;
      if v_num <> round(v_num) or not (v_num between 14 and 60) then raise exception 'the half-life is 14 to 60 days for the AI' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'value', v_num::int);
    when 'prior_weight' then
      v_num := (p ->> 'value')::numeric;
      if not (v_num between 5 and 50) then raise exception 'prior strength is 5 to 50 leads for the AI' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'value', round(v_num, 1));
    when 'rule_draft' then
      if jsonb_typeof(p -> 'rule') is distinct from 'object' then raise exception 'a drafted rule keeps, narrows to or excludes partners' using errcode = '22023'; end if;
      if p -> 'rule' ->> 'action' not in ('fix_partner', 'narrow', 'exclude') then raise exception 'a drafted rule keeps, narrows to or excludes partners' using errcode = '22023'; end if;
      if coalesce(trim(p -> 'rule' ->> 'name'), '') = '' then raise exception 'a drafted rule needs a name' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'rule', jsonb_build_object('name', left(trim(p -> 'rule' ->> 'name'), 120), 'action', p -> 'rule' ->> 'action',
                                'partner_ids', coalesce(p -> 'rule' -> 'partner_ids', '[]'), 'conditions', coalesce(p -> 'rule' -> 'conditions', '{}'),
                                'priority', coalesce((p -> 'rule' ->> 'priority')::int, 100)));
    when 'pause_draft' then
      if not exists (select 1 from b2b.partners where id = (p ->> 'partner_id')::bigint and status = 'active') then raise exception 'unknown or inactive partner' using errcode = '22023'; end if;
      return jsonb_build_object('lever', v_lever, 'partner_id', (p ->> 'partner_id')::bigint, 'reason', left(coalesce(p ->> 'reason', ''), 300));
    else
      raise exception 'outside the AI''s bounds: %', coalesce(v_lever, 'no lever') using errcode = '22023';
    end case;
  exception when data_exception then
    if sqlstate = '22023' then raise; end if;
    raise exception 'the change has a value of the wrong type (%)', sqlerrm using errcode = '22023';
  end;
end $fn$;

/* Where a change lives: engine_policy.ai.<lever> for the five levers, nothing else (the AI never writes the Admin's
   slots, segments or partner weights; C5, C29). Null for any other lever, which ai_validate_change refuses anyway. */
create or replace function b2b.ai_change_path(c jsonb, p_rec_id bigint)
returns jsonb language sql stable set search_path = '' as $fn$
  select case when c ->> 'lever' in ('effort_weights', 'effort_bounds', 'sla_floor', 'half_life_days', 'prior_weight')
              then jsonb_build_object('path', jsonb_build_array('ai', c ->> 'lever'), 'value', c -> 'value') end;
$fn$;

/* The probability that the policy changed by p_change picks each eligible candidate of a logged Addendum 3 decision
   (C15, C16, C30, C113). Null for pre-Addendum 3 decisions (no stage), for half_life_days (not recomputable from the
   stored aggregates: the holdout measures it) and for any lever outside effort_weights, effort_bounds, sla_floor,
   prior_weight and the internal neutral lever 'none' (the current policy).
   The current parameters are engine_params(false) (the AI's levers as they stand), or engine_params(true) with
   scope 'admin' (the Admin's what-if replaces the Admin's slot). The change is clipped as routing clips it: the AI
   inside the Admin's current bounds, the Admin inside the rulebook ranges. Per candidate, the effort factor is recomputed
   from its effort_detail and the SLA factor from its adherence (Stage B and C; 1 in Stage A), P(enrol) from its stored
   recency-weighted counts (w_enr + prior x pw) / (w_n + pw) unless the model decided it; score = CPE (A), CPE x f_e x f_s
   (B), CPE x P x (1 - refund) x f_e x f_s (C), rounded to 2 places; order score desc, CPE desc, SLA adherence desc,
   leads this week asc, partner_id. The exploration lane (0.8 / 0.2 at the fixed share) applies only where the decision
   could take it: mode commission_first, performance or exploration, a policy version and more than one candidate, with
   x the highest-CPE under-tested candidate when it is not the winner. The Stage C challenger mixture is not replayed:
   the deciding P source's values are used. */
create or replace function b2b.ai_policy_probs(d b2b.engine_decisions, p_change jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  v_lever text := coalesce(p_change ->> 'lever', 'none');
  v_admin boolean := coalesce(p_change ->> 'scope', '') = 'admin';
  fx jsonb := coalesce((select s.value -> 'a3_fixed' from b2b.settings s where s.key = 'engine'), '{}'::jsonb);
  base jsonb;
  prm jsonb;
  eff jsonb;
  sla jsonb;
  v_pw numeric;
  v_share numeric;
  v_learn int;
  w_lo numeric; w_hi numeric;
  x numeric; k text; v_tmp jsonb;
  v_cands jsonb;
  v_scored jsonb;
  v_win jsonb;
  v_x jsonb;
begin
  if d.stage is null or d.stage not in ('A', 'B', 'C') then return null; end if;
  if v_lever not in ('none', 'effort_weights', 'effort_bounds', 'sla_floor', 'prior_weight') then return null; end if;
  select coalesce(jsonb_agg(c order by (c ->> 'partner_id')::bigint), '[]'::jsonb) into v_cands
    from jsonb_array_elements(case when jsonb_typeof(d.candidates) = 'array' then d.candidates else '[]'::jsonb end) c
   where coalesce((c ->> 'eligible')::boolean, true) and (c ->> 'partner_id') is not null;
  if jsonb_array_length(v_cands) = 0 then return null; end if;

  base := b2b.engine_params(true);
  prm := case when v_admin then base else b2b.engine_params(false) end;
  eff := coalesce(prm -> 'effort', '{}'::jsonb);
  sla := coalesce(prm -> 'sla', '{}'::jsonb);
  v_pw := coalesce(b2b.stats_num(prm -> 'prior_weight'), 20);
  v_share := least(greatest(coalesce(b2b.stats_num(fx -> 'exploration_share'), 0.2), 0), 0.5);
  v_learn := round(coalesce(b2b.stats_num(fx -> 'learn_leads'), 30))::int;
  w_lo := greatest(coalesce(b2b.stats_num(fx -> 'weight_range' -> 0), 0), 0);
  w_hi := greatest(coalesce(b2b.stats_num(fx -> 'weight_range' -> 1), 5), w_lo);

  -- the change, clipped as routing clips it
  if v_lever = 'effort_weights' and jsonb_typeof(p_change -> 'value') = 'object' then
    v_tmp := coalesce(eff -> 'weights', '{}'::jsonb);
    foreach k in array array['first_call', 'attempts_72h', 'connect_rate', 'followup', 'acts_per_open', 'stale_share'] loop
      x := b2b.stats_num(p_change -> 'value' -> k);
      if x is not null then v_tmp := v_tmp || jsonb_build_object(k, least(greatest(x, w_lo), w_hi)); end if;
    end loop;
    eff := eff || jsonb_build_object('weights', v_tmp);
  elsif v_lever = 'effort_bounds' then
    x := b2b.stats_num(case jsonb_typeof(p_change -> 'value') when 'array' then p_change -> 'value' -> 0 when 'object' then p_change -> 'value' -> 'lo' end);
    if x is not null then
      eff := eff || jsonb_build_object('lo', case when v_admin then least(greatest(x, coalesce(b2b.stats_num(fx -> 'effort_range' -> 0), 0.85)), 1)
                                                  else least(greatest(x, coalesce(b2b.stats_num(base -> 'effort' -> 'lo'), 0.85)), 1) end);
    end if;
    x := b2b.stats_num(case jsonb_typeof(p_change -> 'value') when 'array' then p_change -> 'value' -> 1 when 'object' then p_change -> 'value' -> 'hi' end);
    if x is not null then
      eff := eff || jsonb_build_object('hi', case when v_admin then least(greatest(x, 1), coalesce(b2b.stats_num(fx -> 'effort_range' -> 1), 1.15))
                                                  else least(greatest(x, 1), coalesce(b2b.stats_num(base -> 'effort' -> 'hi'), 1.15)) end);
    end if;
  elsif v_lever = 'sla_floor' then
    x := b2b.stats_num(p_change -> 'value');
    if x is not null then
      sla := sla || jsonb_build_object('floor', case when v_admin then least(greatest(x, coalesce(b2b.stats_num(fx -> 'sla_range' -> 0), 0.80)), coalesce(b2b.stats_num(fx -> 'sla_range' -> 1), 1))
                                                    else least(greatest(x, coalesce(b2b.stats_num(base -> 'sla' -> 'floor'), 0.80)), coalesce(b2b.stats_num(base -> 'sla' -> 'ceiling'), 1)) end);
    end if;
  elsif v_lever = 'prior_weight' then
    x := b2b.stats_num(p_change -> 'value');
    if x is not null then v_pw := least(greatest(x, 1), 200); end if;
  end if;

  -- every candidate re-scored under these parameters, in the decision's stage
  select coalesce(jsonb_agg(jsonb_build_object('partner_id', c ->> 'partner_id', 'score', z.score, 'cpe', z.cpe_raw, 'sla', z.sla_adh, 'lw', z.lw, 'ut', z.ut)), '[]'::jsonb)
    into v_scored
    from jsonb_array_elements(v_cands) c
    cross join lateral (
      select q.cpe_raw, q.sla_adh, q.lw, q.ut,
             round(case d.stage when 'A' then q.cpe when 'B' then q.cpe * q.fe * q.fs else q.cpe * q.pu * (1 - q.rr) * q.fe * q.fs end, 2) score
        from (select (c ->> 'cpe')::numeric cpe_raw,
                     coalesce((c ->> 'cpe')::numeric, 0) cpe,
                     coalesce((c ->> 'refund_rate')::numeric, 0) rr,
                     (c ->> 'sla_adherence')::numeric sla_adh,
                     coalesce((c ->> 'leads_week')::int, 0) lw,
                     coalesce((c ->> 'under_tested')::boolean, coalesce((c ->> 'n_received')::int, (c ->> 'segment_leads')::int, 0) < v_learn) ut,
                     case when d.stage in ('B', 'C') then b2b.effort_from_detail(c -> 'effort_detail', eff) else 1 end fe,
                     case when d.stage in ('B', 'C') then b2b.sla_factor_of((c ->> 'sla_adherence')::numeric, (c ->> 'sla_total')::int, sla) else 1 end fs,
                     case when d.stage <> 'C' then 1
                          when coalesce(c ->> 'p_source', 'p_hat') = 'model' then coalesce((c ->> 'p_used')::numeric, (c ->> 'p_hat')::numeric, 0)
                          when (c ->> 'prior') is not null and (c ->> 'w_n') is not null
                               then least(greatest((coalesce((c ->> 'w_enr')::numeric, 0) + (c ->> 'prior')::numeric * v_pw) / nullif(coalesce((c ->> 'w_n')::numeric, 0) + v_pw, 0), 0.005), 0.995)
                          else coalesce((c ->> 'p_used')::numeric, (c ->> 'p_hat')::numeric, 0) end pu) q) z;

  select c into v_win from jsonb_array_elements(v_scored) c
   order by (c ->> 'score')::numeric desc, (c ->> 'cpe')::numeric desc nulls last, (c ->> 'sla')::numeric desc nulls last, (c ->> 'lw')::int, (c ->> 'partner_id')::bigint
   limit 1;
  -- the exploration lane, only where the logged decision could take it (C30)
  if d.mode in ('commission_first', 'performance', 'exploration') and d.policy_version is not null and jsonb_array_length(v_cands) > 1 and v_share > 0 then
    select c into v_x from jsonb_array_elements(v_scored) c where (c ->> 'ut')::boolean
     order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'sla')::numeric desc nulls last, (c ->> 'lw')::int, (c ->> 'partner_id')::bigint
     limit 1;
    if v_x is not null and v_x ->> 'partner_id' <> v_win ->> 'partner_id' then
      return jsonb_build_object(v_win ->> 'partner_id', round(1 - v_share, 4), v_x ->> 'partner_id', round(v_share, 4));
    end if;
  end if;
  return jsonb_build_object(v_win ->> 'partner_id', 1);
end $fn$;

-- ======================================================================================================== simulation
/* Replays logged, matured partner decisions under a proposed change, doubly robust against the CURRENT policy (C15,
   C23, C53): decisions with a stage created in the last p_days + matured_days days whose allocation is at least
   matured_days (60) old. For each decision i, π_cur = ai_policy_probs(d, none) and π_new = ai_policy_probs(d, change);
   r̂_i(c) = logged P x CPE x (1 - refund rate) per candidate; DR_k,i = Σ_c π_k(c) r̂_i(c) + π_k(a_i) / π_log(a_i) x (r_i -
   r̂_i(a_i)) with π_log the logged selection probability and r_i the realised net commission (the CPE when the lead
   enrolled and was not refunded, cancelled or an upheld duplicate); Δ_i = DR_new,i - DR_cur,i. ncpl_now and ncpl_new
   are the two means, difference and ci95 the paired mean and its 95% interval, gain_pct relative to the current
   policy, ess over w_new = π_new(a) / π_log(a), support the share of decisions whose new policy puts all its probability
   on partners the log could have chosen; enough = at least 30 decisions and support >= ai.autopilot.min_support. A
   change equal to the current setting gives Δ ≡ 0, so Autopilot can never apply a no-op. half_life_days cannot be
   replayed from the stored aggregates (simulated false: the holdout measures it). It never touches a real lead. */
create or replace function b2b.ai_simulate(p_change jsonb, p_days int default 90)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_lever text := p_change ->> 'lever';
  v_md int := round(coalesce(b2b.stats_num((select s.value -> 'a3_fixed' -> 'matured_days' from b2b.settings s where s.key = 'engine')), 60))::int;
  v_days int := least(greatest(coalesce(p_days, 90), 7), 365);
  v_min_support numeric := coalesce(b2b.stats_num((select s.value -> 'autopilot' -> 'min_support' from b2b.settings s where s.key = 'ai')), 0.5);
  v_none jsonb := jsonb_build_object('lever', 'none') || case when coalesce(p_change ->> 'scope', '') = 'admin' then '{"scope":"admin"}'::jsonb else '{}'::jsonb end;
  v jsonb;
begin
  if v_lever = 'half_life_days' then
    return jsonb_build_object('simulated', false, 'change', p_change, 'days', v_days,
                              'why', 'the recency half-life cannot be replayed from logged decisions; the holdout will measure it');
  end if;
  if v_lever not in ('effort_weights', 'effort_bounds', 'sla_floor', 'prior_weight') then
    return jsonb_build_object('simulated', false, 'change', p_change, 'days', v_days,
                              'why', 'this change cannot be replayed from logged decisions; the holdout will measure it');
  end if;
  with dec as (
    select d.id, d.winner_partner_id win, d.selection_probability::numeric sp, d.candidates,
           case when e.status is not null and e.status not in ('refunded', 'cancelled') and a.outcome is distinct from 'duplicate_upheld'
                 and not exists (select 1 from b2b.commission_disputes cd where cd.allocation_id = a.id and cd.status = 'upheld' and cd.kind = 'duplicate_after_acceptance')
                then coalesce(a.cpe_net_inr, 0) else 0 end r,
           b2b.ai_policy_probs(d, v_none) pc,
           b2b.ai_policy_probs(d, p_change) pn
      from b2b.engine_decisions d
      join b2b.allocations a on a.engine_decision_id = d.id and a.destination_type = 'partner' and not a.is_test
      left join lateral (select x.status from public.enrollments x where x.allocation_id = a.id order by (x.status <> 'cancelled') desc, x.id desc limit 1) e on true
     where d.destination_type = 'partner' and not d.is_test and d.selection_probability > 0 and d.stage is not null
       and d.created_at > now() - make_interval(days => v_days + v_md)
       and a.created_at <= now() - make_interval(days => v_md)
       and a.status in ('pushed', 'accepted', 'closed')),
  cand as (
    select dec.id, c ->> 'partner_id' pid,
           coalesce((c ->> 'p_used')::numeric, (c ->> 'p_hat')::numeric, 0) * coalesce((c ->> 'cpe')::numeric, 0) * (1 - coalesce((c ->> 'refund_rate')::numeric, 0)) rhat,
           case when (c ->> 'partner_id')::bigint = dec.win then dec.sp else coalesce((c ->> 'propensity')::numeric, 0) end pl
      from dec, jsonb_array_elements(case when jsonb_typeof(dec.candidates) = 'array' then dec.candidates else '[]'::jsonb end) c
     where dec.pc is not null and dec.pn is not null and coalesce((c ->> 'eligible')::boolean, true) and (c ->> 'partner_id') is not null),
  terms as (
    select dec.id, dec.r,
           sum(coalesce((dec.pc ->> cand.pid)::numeric, 0) * cand.rhat) dm_c,
           sum(coalesce((dec.pn ->> cand.pid)::numeric, 0) * cand.rhat) dm_n,
           coalesce((dec.pc ->> dec.win::text)::numeric, 0) / dec.sp wc,
           coalesce((dec.pn ->> dec.win::text)::numeric, 0) / dec.sp wn,
           max(case when cand.pid = dec.win::text then cand.rhat end) rhat_a,
           sum(coalesce((dec.pn ->> cand.pid)::numeric, 0) * case when cand.pl > 0 then 1 else 0 end) supp,
           bool_and(coalesce(dec.pn ->> cand.pid, '0') = coalesce(dec.pc ->> cand.pid, '0')) same
      from dec join cand on cand.id = dec.id
     group by dec.id, dec.r, dec.pc, dec.pn, dec.win, dec.sp),
  x as (select r, dm_c + wc * (r - coalesce(rhat_a, 0)) drc, dm_n + wn * (r - coalesce(rhat_a, 0)) drn, wn, supp >= 0.999 supported, same from terms)
  select jsonb_build_object(
    'simulated', true, 'change', p_change, 'days', v_days,
    'window', jsonb_build_object('from', now() - make_interval(days => v_days + v_md), 'to', now() - make_interval(days => v_md)),
    'decisions', count(*), 'affected', count(*) filter (where not same),
    'ncpl_now', round(coalesce(avg(drc), 0), 2),
    'ncpl_new', round(coalesce(avg(drn), 0), 2),
    'difference', round(coalesce(avg(drn - drc), 0), 2),
    'ci95', jsonb_build_array(round(coalesce(avg(drn - drc) - 1.96 * stddev_samp(drn - drc) / sqrt(nullif(count(*), 0)::numeric), 0), 2),
                              round(coalesce(avg(drn - drc) + 1.96 * stddev_samp(drn - drc) / sqrt(nullif(count(*), 0)::numeric), 0), 2)),
    'gain_pct', case when avg(drc) > 0 then round(100 * avg(drn - drc) / avg(drc), 1) end,
    'ess', round(coalesce(power(sum(wn), 2) / nullif(sum(wn * wn), 0), 0), 1),
    'support', round(coalesce(avg(supported::int), 0), 4),
    'min_support', v_min_support,
    'enough', count(*) >= 30 and coalesce(avg(supported::int), 0) >= v_min_support)
    into v from x;
  return v;
end $fn$;

/* The same pair of policies on the young decisions of the last p_days (at most matured_days) whose outcomes are not
   known yet: the direct-method term only, mean of Σ_c (π_new - π_cur)(c) r̂(c), labelled as a projection (C23). Never
   read by Autopilot or the ML gate. */
create or replace function b2b.ai_simulate_recent(p_change jsonb, p_days int)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_lever text := p_change ->> 'lever';
  v_md int := round(coalesce(b2b.stats_num((select s.value -> 'a3_fixed' -> 'matured_days' from b2b.settings s where s.key = 'engine')), 60))::int;
  v_days int;
  v_none jsonb := jsonb_build_object('lever', 'none') || case when coalesce(p_change ->> 'scope', '') = 'admin' then '{"scope":"admin"}'::jsonb else '{}'::jsonb end;
  v jsonb;
begin
  v_days := least(greatest(coalesce(p_days, 30), 1), v_md);
  if v_lever not in ('effort_weights', 'effort_bounds', 'sla_floor', 'prior_weight') then
    return jsonb_build_object('simulated', false, 'projected', true, 'days', v_days, 'decisions', 0, 'projected_difference', null,
                              'why', 'this change cannot be replayed from logged decisions');
  end if;
  with dec as (
    select d.id, d.candidates, b2b.ai_policy_probs(d, v_none) pc, b2b.ai_policy_probs(d, p_change) pn
      from b2b.engine_decisions d
     where d.destination_type = 'partner' and not d.is_test and d.selection_probability > 0 and d.stage is not null
       and d.created_at > now() - make_interval(days => v_days)
       and exists (select 1 from b2b.allocations a where a.engine_decision_id = d.id and a.destination_type = 'partner' and not a.is_test
                    and (a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null))),
  cand as (
    select dec.id, c ->> 'partner_id' pid,
           coalesce((c ->> 'p_used')::numeric, (c ->> 'p_hat')::numeric, 0) * coalesce((c ->> 'cpe')::numeric, 0) * (1 - coalesce((c ->> 'refund_rate')::numeric, 0)) rhat
      from dec, jsonb_array_elements(case when jsonb_typeof(dec.candidates) = 'array' then dec.candidates else '[]'::jsonb end) c
     where dec.pc is not null and dec.pn is not null and coalesce((c ->> 'eligible')::boolean, true) and (c ->> 'partner_id') is not null),
  terms as (
    select dec.id, sum(coalesce((dec.pc ->> cand.pid)::numeric, 0) * cand.rhat) dm_c, sum(coalesce((dec.pn ->> cand.pid)::numeric, 0) * cand.rhat) dm_n,
           bool_and(coalesce(dec.pn ->> cand.pid, '0') = coalesce(dec.pc ->> cand.pid, '0')) same
      from dec join cand on cand.id = dec.id group by dec.id, dec.pc, dec.pn)
  select jsonb_build_object('simulated', true, 'projected', true, 'label', 'projected: outcomes not known yet', 'days', v_days,
           'decisions', count(*), 'affected', count(*) filter (where not same),
           'projected_ncpl_now', round(coalesce(avg(dm_c), 0), 2), 'projected_ncpl_new', round(coalesce(avg(dm_n), 0), 2),
           'projected_difference', round(coalesce(avg(dm_n - dm_c), 0), 2))
    into v from terms;
  return v;
end $fn$;

/* Realised net commission per matured partner lead, AI-steered against the holdout, overall and by month: allocations
   between matured_days and matured_days + p_days old (C23), with the 95% interval of the difference (C42). */
create or replace function b2b.ai_uplift(p_days int default 180)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  with prm as (select round(coalesce(b2b.stats_num(b2b.engine_params(true) -> 'matured_days'), b2b.stats_num(b2b.engine_params(true) -> 'maturity_days'), 60))::int md),
  x as (select d.holdout, date_trunc('month', a.created_at at time zone 'Asia/Kolkata')::date mon, b2b.allocation_reward(a.id) r
          from b2b.engine_decisions d
          join b2b.allocations a on a.engine_decision_id = d.id and a.destination_type = 'partner' and not a.is_test, prm
         where d.destination_type = 'partner' and not d.is_test and d.scoring_mode is not null
           and a.created_at > now() - make_interval(days => p_days + prm.md) and a.created_at <= now() - make_interval(days => prm.md)
           and a.status in ('pushed', 'accepted', 'closed')),
  s as (select holdout, count(*) n, avg(r) mu, coalesce(var_samp(r), 0) v from x group by holdout)
  select jsonb_build_object(
    'maturity_days', (select md from prm), 'days', p_days,
    'steered', jsonb_build_object('leads', coalesce((select n from s where not holdout), 0), 'ncpl', round(coalesce((select mu from s where not holdout), 0), 2)),
    'holdout', jsonb_build_object('leads', coalesce((select n from s where holdout), 0), 'ncpl', round(coalesce((select mu from s where holdout), 0), 2)),
    'uplift_pct', case when (select mu from s where holdout) > 0
                       then round(100 * ((select mu from s where not holdout) - (select mu from s where holdout)) / (select mu from s where holdout), 1) end,
    'z', round(coalesce(((select mu from s where not holdout) - (select mu from s where holdout))
                        / nullif(sqrt((select v / n from s where not holdout) + (select v / n from s where holdout)), 0), 0), 2),
    'diff_ci95', (select jsonb_build_array(round(st.mu - ho.mu - 1.96 * sqrt(st.v / st.n + ho.v / ho.n), 2), round(st.mu - ho.mu + 1.96 * sqrt(st.v / st.n + ho.v / ho.n), 2))
                    from s st, s ho where not st.holdout and ho.holdout),
    'by_month', coalesce((select jsonb_agg(jsonb_build_object('month', mon, 'steered', st, 'holdout', ho, 'steered_n', sn, 'holdout_n', hn) order by mon)
                            from (select mon, round(avg(r) filter (where not holdout), 2) st, round(avg(r) filter (where holdout), 2) ho,
                                         count(*) filter (where not holdout) sn, count(*) filter (where holdout) hn from x group by mon) m), '[]'));
$fn$;

-- ======================================================================================================== the tools
/* The only data Claude sees: aggregated and pseudonymised (leads as a short salted hash; never a name, phone, e-mail,
   free-text note, proof or HTTP body). segment_scorecards, partner_scorecards, conversion_cohorts, commission_rates (+
   per-programme CPE for a segment), sales_effort (the six effort metrics and the SLA factor as routing uses them, plus
   raw activity over accepted leads), engine_settings (bounds, the fixed numbers, redacted history), model_metrics,
   recent_decisions (reason codes only), alerts (per-type whitelist), uplift, run_simulation (C8, C31, C32, C34, C102). */
create or replace function b2b.ai_tool(p_name text, p_input jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_days int := least(greatest(coalesce((p_input ->> 'days')::int, 30), 1), 365);
  v_seg text := nullif(p_input ->> 'segment', '');
  fx jsonb := coalesce((select s.value -> 'a3_fixed' from b2b.settings s where s.key = 'engine'), '{}'::jsonb);
  prm jsonb;
  v_b_leads numeric := coalesce(b2b.stats_num(fx -> 'stage_b_min_leads'), 20);
  v_c_mat numeric := coalesce(b2b.stats_num(fx -> 'stage_c_min_matured'), 30);
  v_c_part numeric := coalesce(b2b.stats_num(fx -> 'stage_c_min_partners'), 2);
begin
  case p_name
  when 'segment_scorecards' then
    return jsonb_build_object('segments', coalesce((
      select jsonb_agg(jsonb_build_object('segment', s.segment, 'stage', coalesce(s.auto_stage, 'A'), 'auto_mode', s.auto_mode,
               'leads', s.n_leads, 'matured', s.n_matured, 'avg_enrolment_rate', s.prior, 'partners', s.partners, 'partners_matured', s.partners_matured,
               'progress_b', (select round(least(1, coalesce(min(ps.n_received), 0)::numeric / nullif(v_b_leads, 0)), 2)
                                from b2b.partner_segment_stats ps where ps.variant = 'base' and ps.segment = s.segment and ps.n_received > 0),
               'progress_c', (select round(least(1, (count(*) filter (where ps.n_matured_c >= v_c_mat))::numeric / nullif(v_c_part, 0)), 2)
                                from b2b.partner_segment_stats ps where ps.variant = 'base' and ps.segment = s.segment and ps.n_received > 0),
               'routed_last_days', (select count(*) from b2b.allocations a where a.segment = s.segment and a.destination_type = 'partner' and not a.is_test
                                     and a.created_at > now() - make_interval(days => v_days)))
             order by s.n_leads desc)
        from b2b.segment_stats s
       where s.variant = 'base' and (s.n_leads > 0 or s.partners > 0)
         and case when v_seg is null then s.segment ~ '^[^|]+\|[^|]+\|[^|]+$' else s.segment in (v_seg, b2b.segment_rollup(v_seg)) end), '[]'), 'days', v_days);
  when 'partner_scorecards' then
    return jsonb_build_object('partners', coalesce((
      select jsonb_agg(jsonb_build_object('partner_id', p.id, 'partner', coalesce(p.display_name, p.name), 'status', p.status,
               'leads', x.n, 'accepted', x.acc, 'duplicates', x.dup, 'rejected', x.rej,
               'duplicate_rate', round(x.dup::numeric / nullif(x.n, 0), 4),
               'sla_first_attempt_met', (select round(count(*) filter (where c.status = 'met')::numeric / nullif(count(*) filter (where c.status in ('met', 'met_late', 'breached')), 0), 4)
                                           from b2b.sla_checks c where c.partner_id = p.id and not c.is_test and c.sla = 'first_attempt' and c.due_at > now() - make_interval(days => v_days)),
               'enrolments_reported', (select count(*) from public.enrollments e where e.partner_id = p.id and e.source_product = 'b2b' and e.created_at > now() - make_interval(days => v_days)),
               'segments', coalesce((select jsonb_agg(jsonb_build_object('segment', s.segment, 'p_hat', s.p_hat, 'matured', s.n_matured, 'received', s.n_received,
                                                                         'refund_rate', s.refund_rate, 'effort_factor', s.effort_factor, 'has_activity', s.has_activity,
                                                                         'sla_adherence', s.sla_adherence, 'sla_factor', s.sla_factor) order by s.n_received desc, s.n_leads desc)
                                       from b2b.partner_segment_stats s where s.variant = 'base' and s.partner_id = p.id and (s.n_leads > 0 or s.n_received > 0)
                                         and case when v_seg is null then s.segment ~ '^[^|]+\|[^|]+\|[^|]+$' else s.segment in (v_seg, b2b.segment_rollup(v_seg)) end), '[]'))
             order by x.n desc)
        from b2b.partners p
        cross join lateral (select count(*) n, count(*) filter (where a.status = 'accepted' or a.accepted_at is not null) acc,
                                   count(*) filter (where a.status = 'duplicate') dup, count(*) filter (where a.status = 'rejected') rej
                              from b2b.allocations a where a.partner_id = p.id and not a.is_test and a.created_at > now() - make_interval(days => v_days)
                               and (v_seg is null or a.segment = v_seg)) x
       where p.status <> 'closed'), '[]'), 'days', v_days);
  when 'conversion_cohorts' then
    return jsonb_build_object('cohorts', coalesce((
      select jsonb_agg(jsonb_build_object('month', mon, 'partner', pn, 'leads', n, 'contacted_or_further', c, 'interested_or_further', i, 'applied', ap, 'enrolled', en) order by mon, pn)
        from (select date_trunc('month', o.created_at at time zone 'Asia/Kolkata')::date mon, coalesce(p.display_name, p.name) pn, count(*) n,
                     count(*) filter (where o.stage in ('contacted', 'interested', 'applied')) c, count(*) filter (where o.stage in ('interested', 'applied')) i,
                     count(*) filter (where o.stage = 'applied') ap, count(*) filter (where o.enrolled) en
                from b2b.allocation_outcomes() o join b2b.partners p on p.id = o.partner_id
               where o.created_at > now() - make_interval(days => greatest(v_days, 90)) and (v_seg is null or o.segment = v_seg)
               group by 1, 2) z), '[]'));
  when 'commission_rates' then
    return jsonb_build_object('rates', coalesce((
      select jsonb_agg(jsonb_build_object('partner', pn, 'course', ck, 'level', lvl, 'mode', md, 'programmes', n, 'cpe_net_median', cpe) order by ck, cpe desc)
        from (select coalesce(p.display_name, p.name) pn, c.course_key ck, c.level lvl, c.mode md, count(*) n,
                     round(percentile_cont(0.5) within group (order by (b2b.cpe_detail(o.partner_id, o.programme_id, o.fees, 'middle', null) ->> 'cpe')::numeric)::numeric, 0) cpe
                from b2b.partner_programmes o join public.catalog_programs c on c.id = o.programme_id and c.active
                join b2b.partners p on p.id = o.partner_id and p.status <> 'closed'
               where o.valid_to is null and o.active and (v_seg is null or c.course_key = split_part(v_seg, '|', 1))
               group by 1, 2, 3, 4) z), '[]'))
      || case when v_seg is null then '{}'::jsonb else jsonb_build_object('programmes', coalesce((
           select jsonb_agg(jsonb_build_object('partner', z.pn, 'programme_id', z.pid, 'programme', z.pname, 'course', z.ck, 'level', z.lvl, 'mode', z.md,
                                               'specialization', z.spec, 'cpe', z.cpe, 'tier_basis', z.tb, 'fee_source', z.fs, 'gst_inclusive', z.gst) order by z.cpe desc nulls last, z.pid)
             from (select coalesce(p.display_name, p.name) pn, o.programme_id pid, c.program_name pname, c.course_key ck, c.level lvl, c.mode md, c.specialization spec,
                          (dd.d ->> 'cpe')::numeric cpe, dd.d ->> 'tier_basis' tb, dd.d ->> 'fee_source' fs, (dd.d ->> 'gst_inclusive')::boolean gst
                     from b2b.partner_programmes o join public.catalog_programs c on c.id = o.programme_id and c.active
                     join b2b.partners p on p.id = o.partner_id and p.status <> 'closed'
                     cross join lateral (select b2b.cpe_detail(o.partner_id, o.programme_id, o.fees, 'middle', null) d) dd
                    where o.valid_to is null and o.active and c.course_key = split_part(v_seg, '|', 1)
                    order by (dd.d ->> 'cpe')::numeric desc nulls last, o.programme_id limit 200) z), '[]')) end;
  when 'sales_effort' then
    return jsonb_build_object(
      'engine', coalesce((select jsonb_agg(jsonb_build_object('partner_id', s.partner_id, 'partner', coalesce(p.display_name, p.name), 'segment', s.segment,
                   'effort_factor', s.effort_factor, 'has_activity', s.has_activity, 'activity_coverage', s.activity_coverage, 'basis', s.effort_detail ->> 'basis',
                   'metrics', (select coalesce(jsonb_object_agg(k, jsonb_build_object('value', m -> 'v', 'median', m -> 'median', 'n', m -> 'n', 'r', m -> 'r')), '{}')
                                 from jsonb_each(case when jsonb_typeof(s.effort_detail -> 'metrics') = 'object' then s.effort_detail -> 'metrics' else '{}'::jsonb end) e(k, m)),
                   'sla_met', s.sla_met, 'sla_total', s.sla_total, 'sla_adherence', s.sla_adherence, 'sla_factor', s.sla_factor, 'stats_at', s.refreshed_at)
                 order by s.partner_id, s.segment)
          from b2b.partner_segment_stats s join b2b.partners p on p.id = s.partner_id and p.status <> 'closed'
         where s.variant = 'base' and s.n_received > 0
           and case when v_seg is null then s.segment ~ '^[^|]+\|[^|]+\|[^|]+$' else s.segment in (v_seg, b2b.segment_rollup(v_seg)) end), '[]'),
      'activity', coalesce((select jsonb_agg(jsonb_build_object('partner_id', z.partner_id, 'partner', z.pn, 'accepted_leads', z.n,
                   'first_attempt_hours_median', z.fa_med, 'first_attempt_hours_p90', z.fa_p90, 'first_attempt_sla_met', z.fa_met,
                   'attempts_24h_avg', z.a24, 'attempts_72h_avg', z.a72, 'connect_rate', z.conn, 'stale_share', z.stale, 'activities_last_7d', z.act7) order by z.n desc)
          from (select f.partner_id, coalesce(p.display_name, p.name) pn, count(*) n,
                       round((percentile_cont(0.5) within group (order by f.first_attempt_hours))::numeric, 1) fa_med,
                       round((percentile_cont(0.9) within group (order by f.first_attempt_hours))::numeric, 1) fa_p90,
                       round(avg(f.first_attempt_met::int)::numeric, 4) fa_met, round(avg(f.attempts_24h)::numeric, 2) a24, round(avg(f.attempts_72h)::numeric, 2) a72,
                       round(avg(coalesce(f.connected, false)::int)::numeric, 4) conn, round(avg(coalesce(f.stale, false)::int)::numeric, 4) stale, sum(f.activities_7d) act7
                  from b2b.fact_allocations f join b2b.partners p on p.id = f.partner_id and p.status <> 'closed'
                 where not f.is_test and f.accepted and f.created_at > now() - make_interval(days => v_days) and (v_seg is null or f.segment = v_seg)
                 group by 1, 2) z), '[]'),
      'days', v_days, 'facts_at', (select value ->> 'refreshed_at' from b2b.ai_state where key = 'facts'));
  when 'engine_settings' then
    prm := b2b.engine_params(true);
    return jsonb_build_object('engine', (select value - 'paid_rule' - 'blocked_phones' - 'b2c_sources' from b2b.settings where key = 'engine'),
                              'policy', (select value - 'segments' - 'partner_weights' from b2b.settings where key = 'engine_policy'),
                              'effective', b2b.engine_params(false),
                              'fixed', fx,
                              'history', coalesce((select jsonb_agg(jsonb_build_object('key', v.key, 'version', v.version,
                                                     'reason', regexp_replace(regexp_replace(coalesce(v.reason, ''), '[^\s@:]+@[^\s@:]+', '[admin]', 'g'), '\+?\d[\d -]{8,}\d', '[number]', 'g'),
                                                     'actor', v.actor_type, 'at', v.created_at) order by v.created_at desc)
                                                     from (select * from b2b.settings_versions where key in ('engine', 'engine_policy') order by created_at desc limit 15) v), '[]'),
                              'bounds', jsonb_build_object(
                                'effort_weights', jsonb_build_array(coalesce(b2b.stats_num(fx -> 'weight_range' -> 0), 0), coalesce(b2b.stats_num(fx -> 'weight_range' -> 1), 5)),
                                'effort_bounds', jsonb_build_object('lo', jsonb_build_array(prm -> 'effort' -> 'lo', 1), 'hi', jsonb_build_array(1, prm -> 'effort' -> 'hi')),
                                'sla_floor', jsonb_build_array(prm -> 'sla' -> 'floor', prm -> 'sla' -> 'ceiling'),
                                'half_life_days', '[14, 60]'::jsonb, 'prior_weight', '[5, 50]'::jsonb));
  when 'model_metrics' then
    return jsonb_build_object('models', coalesce((select jsonb_agg(jsonb_build_object('version', m.version, 'status', m.status, 'trained_on', m.trained_on,
                                                    'holdout', m.metrics -> 'holdout' - 'deciles', 'baseline', m.metrics -> 'baseline' - 'deciles', 'policy', m.metrics -> 'policy',
                                                    'gate', m.gate, 'monitor', m.metrics -> 'monitor' - 'deciles') order by m.id desc)
                                                    from (select * from b2b.ml_models where status in ('shadow', 'challenger', 'champion') or id in (select id from b2b.ml_models order by id desc limit 3)) m), '[]'));
  when 'recent_decisions' then
    return jsonb_build_object('decisions', coalesce((
      select jsonb_agg(jsonb_build_object('lead', b2b.ai_pseudo(d.lead_id), 'at', d.created_at, 'segment', d.segment, 'eval_segment', d.eval_segment,
               'destination', d.destination_type, 'mode', d.mode, 'scoring', d.scoring_mode, 'stage', d.stage, 'how', d.how, 'holdout', d.holdout,
               -- reason codes only (C31): a person's note shows as 'admin_note'
               'reason', case when d.reason = any (array['b2c_created','import_choice','rule','manual','manual_route_failed','no_partner_offers_programme','no_capacity',
                                                         'partners_unreachable','partner_attempts_exhausted','duplicate_cascade','no_partner_consent','partner_barred','b2c_held',
                                                         'paid_campaign','not_qualified','consent_no_answer','partner_lost','test_lead','test_handoff','no_sandbox_partner',
                                                         'junk','program_mismatch','invalid_phone','blocked_phone',
                                                         'duplicate at partner','rejected by partner','partner unreachable','partner paused'])
                                   or d.reason like 'kill switch:%' then d.reason
                              when d.reason is not null then 'admin_note' end,
               'partner', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = d.winner_partner_id),
               'selection_probability', d.selection_probability, 'score', d.score, 'model', d.model_version,
               'paid', case when coalesce((d.attribution ->> 'paid')::boolean, false) then d.attribution ->> 'label' end,
               'effort_factor', (select (c ->> 'effort_factor')::numeric from jsonb_array_elements(case when jsonb_typeof(d.candidates) = 'array' then d.candidates else '[]'::jsonb end) c
                                  where (c ->> 'partner_id')::bigint = d.winner_partner_id limit 1),
               'sla_factor', (select (c ->> 'sla_factor')::numeric from jsonb_array_elements(case when jsonb_typeof(d.candidates) = 'array' then d.candidates else '[]'::jsonb end) c
                               where (c ->> 'partner_id')::bigint = d.winner_partner_id limit 1),
               'candidates', (select jsonb_agg(jsonb_build_object('partner', c ->> 'name', 'cpe', c -> 'cpe', 'p_hat', c -> 'p_hat', 'p_used', c -> 'p_used', 'ncpl', c -> 'ncpl',
                                                                  'score', c -> 'score', 'effort_factor', c -> 'effort_factor', 'sla_factor', c -> 'sla_factor',
                                                                  'propensity', c -> 'propensity', 'eligible', c -> 'eligible'))
                                from jsonb_array_elements(case when jsonb_typeof(d.candidates) = 'array' then d.candidates else '[]'::jsonb end) c)) order by d.id desc)
        from (select * from b2b.engine_decisions d where not d.is_test and (v_seg is null or d.segment = v_seg) order by d.id desc
               limit least(greatest(coalesce((p_input ->> 'limit')::int, 50), 1), 200)) d), '[]'));
  when 'alerts' then
    return jsonb_build_object('alerts', coalesce((
      select jsonb_agg(jsonb_build_object('type', e.type, 'at', e.occurred_at,
               'partner', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = e.partner_id),
               'detail', b2b.ai_alert_detail(e.type, e.payload)) order by e.occurred_at desc)
        from (select * from b2b.events e where (e.type like 'alert.%' or e.type = 'routing.error') and e.occurred_at > now() - make_interval(days => least(v_days, 30))
               order by e.occurred_at desc limit 100) e), '[]'));
  when 'uplift' then
    return b2b.ai_uplift(least(greatest(coalesce((p_input ->> 'days')::int, 180), 30), 365));
  when 'run_simulation' then
    -- the change is checked first: a malformed value or a lever outside the AI's bounds is answered as an error, never simulated as a no-op
    return b2b.ai_simulate(b2b.ai_validate_change(p_input -> 'change'), coalesce((p_input ->> 'days')::int, 90));
  else
    raise exception 'unknown tool %', p_name using errcode = '22023';
  end case;
end $fn$;

-- ======================================================================================================== the writers
/* The one writer of an AI setting change (the Admin's approval and Autopilot both come here; C26, C95, C126): the
   lever must map to engine_policy.ai.<lever>; the settings row is locked (setting_for_update); the version carries the
   run and, for Autopilot, the actor 'autopilot'; an older applied change on the same lever is superseded, so a later
   rollback of it cannot overwrite this one; the reason names 'autopilot' or 'an Admin', never an address (C32). */
create or replace function b2b.ai_apply_setting(p_rec_id bigint, p_change jsonb, p_who text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  rec b2b.ai_recommendations;
  pol jsonb; v_put jsonb; v_from jsonb; v_res jsonb; v_set jsonb; v_path text[];
  v_auto boolean := p_who = 'autopilot';
begin
  select * into rec from b2b.ai_recommendations where id = p_rec_id for update;
  if rec.id is null then raise exception 'recommendation not found' using errcode = 'P0002'; end if;
  v_put := b2b.ai_change_path(p_change, rec.id);
  if v_put is null then
    raise exception 'retired by Addendum 3: % cannot be applied', coalesce(p_change ->> 'lever', 'this lever') using errcode = '22023';
  end if;
  v_path := (select array_agg(x) from jsonb_array_elements_text(v_put -> 'path') x);
  if cardinality(v_path) <> 2 or v_path[1] <> 'ai' or v_path[2] not in ('effort_weights', 'effort_bounds', 'sla_floor', 'half_life_days', 'prior_weight') then
    raise exception 'retired by Addendum 3: % cannot be applied', coalesce(p_change ->> 'lever', 'this lever') using errcode = '22023';
  end if;
  pol := b2b.setting_for_update('engine_policy');
  v_from := pol #> v_path;
  pol := b2b.jsonb_put(pol, v_path, v_put -> 'value');
  v_res := b2b.set_setting('engine_policy', pol, format('AI recommendation #%s (run #%s) applied by %s: %s', rec.id, rec.run_id,
                                                        case when v_auto then 'autopilot' else 'an Admin' end, rec.title));
  perform b2b.ai_version_stamp((v_res ->> 'version')::int, rec.run_id, v_auto);
  v_set := jsonb_build_object('key', 'engine_policy', 'version', v_res -> 'version', 'path', v_put -> 'path', 'from', v_from, 'to', v_put -> 'value',
                              'change', p_change, 'edited', p_change is distinct from rec.change);
  update b2b.ai_recommendations
     set status = 'applied', decided_by = p_who, decided_at = now(), decision_note = left(trim(p_note), 500), applied = v_set,
         check_due_at = now() + interval '7 days'
   where id = rec.id;
  -- an older applied change on the same lever is superseded: rolling it back would otherwise overwrite this one (C26)
  update b2b.ai_recommendations
     set status = 'superseded', check_result = coalesce(check_result, '{}'::jsonb) || jsonb_build_object('superseded_by', rec.id, 'superseded_at', now())
   where status = 'applied' and kind = 'setting_change' and id <> rec.id and applied -> 'path' = v_put -> 'path';
  perform b2b.log_event('ai.recommendation_applied', null, null, null, jsonb_build_object('id', rec.id, 'run_id', rec.run_id, 'change', p_change, 'by', p_who));
  return v_set;
end $fn$;

/* The Admin's decision on a recommendation: reject; apply an insight; approve a rule draft (an inactive rule), a pause
   draft (the partner paused) or a setting change (through ai_apply_setting, possibly edited within the bounds). */
create or replace function b2b.ai_recommendation_decide(p_id bigint, p_decision text, p_note text, p_change jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  rec b2b.ai_recommendations;
  v_change jsonb;
  v_set jsonb;
  v_who text := coalesce((select email from b2b.app_users where user_id = auth.uid()), auth.uid()::text, 'admin');
  v_res jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_decision not in ('approve', 'reject') then raise exception 'approve or reject' using errcode = '22023'; end if;
  select * into rec from b2b.ai_recommendations where id = p_id for update;
  if rec.id is null then raise exception 'recommendation not found' using errcode = 'P0002'; end if;
  if rec.status <> 'open' then raise exception 'this recommendation is %', rec.status using errcode = '22023'; end if;
  if rec.expires_at < now() then
    update b2b.ai_recommendations set status = 'expired' where id = rec.id;
    raise exception 'this recommendation has expired' using errcode = '22023';
  end if;
  if p_decision = 'reject' then
    update b2b.ai_recommendations set status = 'rejected', decided_by = v_who, decided_at = now(), decision_note = left(trim(p_note), 500) where id = rec.id;
    perform b2b.log_event('ai.recommendation_rejected', null, null, null, jsonb_build_object('id', rec.id, 'run_id', rec.run_id));
    return jsonb_build_object('status', 'rejected');
  end if;
  if rec.kind = 'insight' then
    update b2b.ai_recommendations set status = 'applied', decided_by = v_who, decided_at = now(), decision_note = left(trim(p_note), 500) where id = rec.id;
    return jsonb_build_object('status', 'applied');
  end if;
  -- the Admin may edit the change before approving; it is re-checked against the bounds
  v_change := b2b.ai_validate_change(coalesce(p_change, rec.change));
  if v_change ->> 'lever' is distinct from rec.change ->> 'lever' then raise exception 'an edit keeps the same lever' using errcode = '22023'; end if;

  if v_change ->> 'lever' = 'rule_draft' then
    v_res := b2b.routing_rule_save((v_change -> 'rule') || '{"active":false}');
    v_set := jsonb_build_object('rule_id', v_res ->> 'id', 'active', false);
  elsif v_change ->> 'lever' = 'pause_draft' then
    perform b2b.partner_set_status((v_change ->> 'partner_id')::bigint, 'paused',
                                   'AI recommendation #' || rec.id || ' approved by an Admin: ' || coalesce(nullif(v_change ->> 'reason', ''), rec.title));
    v_set := jsonb_build_object('partner_id', v_change ->> 'partner_id', 'paused', true);
  else
    -- one writer for every setting change: the row lock, the path check, the version stamp and the superseding live there
    v_set := b2b.ai_apply_setting(rec.id, v_change, v_who, p_note);
    return jsonb_build_object('status', 'applied', 'applied', v_set);
  end if;
  update b2b.ai_recommendations
     set status = 'applied', decided_by = v_who, decided_at = now(), decision_note = left(trim(p_note), 500),
         applied = v_set || jsonb_build_object('edited', p_change is not null and v_change is distinct from rec.change, 'change', v_change),
         check_due_at = now() + interval '7 days'
   where id = rec.id;
  perform b2b.log_event('ai.recommendation_applied', null, null, null, jsonb_build_object('id', rec.id, 'run_id', rec.run_id, 'change', v_change, 'by', v_who));
  return jsonb_build_object('status', 'applied', 'applied', v_set);
end $fn$;

/* Restores what an applied setting change replaced: only engine_policy.ai.<lever> paths (a retired Phase 3 path has
   nothing to roll back; C5), only while the slot still holds the value this change wrote (otherwise the later change is
   rolled back or the setting edited; C26), under the settings row lock, stamped with the run (C95). */
create or replace function b2b.ai_recommendation_rollback(p_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  rec b2b.ai_recommendations;
  pol jsonb;
  v_path text[];
  v_who text := coalesce((select email from b2b.app_users where user_id = auth.uid()), auth.uid()::text, 'admin');
  v_res jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into rec from b2b.ai_recommendations where id = p_id for update;
  if rec.id is null then raise exception 'recommendation not found' using errcode = 'P0002'; end if;
  if rec.status <> 'applied' or rec.kind <> 'setting_change' then raise exception 'only an applied setting change can be rolled back here' using errcode = '22023'; end if;
  v_path := (select array_agg(x) from jsonb_array_elements_text(case when jsonb_typeof(rec.applied -> 'path') = 'array' then rec.applied -> 'path' else '[]'::jsonb end) x);
  if v_path is null or cardinality(v_path) <> 2 or v_path[1] <> 'ai'
     or v_path[2] not in ('effort_weights', 'effort_bounds', 'sla_floor', 'half_life_days', 'prior_weight') then
    raise exception 'retired by Addendum 3: nothing to roll back' using errcode = '22023';
  end if;
  pol := b2b.setting_for_update('engine_policy');
  -- both coalesce(..., 'null') are needed: a removed value is stored as JSON null in 'to' but reads back as SQL NULL
  if coalesce(pol #> v_path, 'null'::jsonb) is distinct from coalesce(rec.applied -> 'to', 'null'::jsonb) then
    raise exception 'this setting has changed since this recommendation was applied; roll back the later change or edit the setting' using errcode = '22023';
  end if;
  pol := b2b.jsonb_put(pol, v_path, rec.applied -> 'from');
  v_res := b2b.set_setting('engine_policy', pol, format('rollback of AI recommendation #%s by an Admin: %s', rec.id, trim(p_reason)));
  perform b2b.ai_version_stamp((v_res ->> 'version')::int, rec.run_id, false);
  update b2b.ai_recommendations
     set status = 'rolled_back',
         check_result = coalesce(check_result, '{}'::jsonb) || jsonb_build_object('rolled_back_by', v_who, 'at', now(), 'reason', trim(p_reason), 'version', v_res -> 'version')
   where id = rec.id;
  perform b2b.log_event('ai.recommendation_rolled_back', null, null, null, jsonb_build_object('id', rec.id, 'by', v_who));
  return jsonb_build_object('status', 'rolled_back', 'version', v_res -> 'version');
end $fn$;

/* The 7-day review of every applied setting change (as m30a: steered against holdout on expected net commission per
   lead), in created_at, id order (C41). A 'worse' Autopilot change is rolled back only when its path is still an
   engine_policy.ai lever (C5) and the slot still holds the value it wrote (else it is superseded and the Admin alerted;
   C26), under the settings row lock, stamped 'autopilot' (C95). Then the realised effect (C42): once the leads routed
   around a change have matured (decided_at + matured_days + 14 days), net commission per matured lead in the 14 days
   before and after the change, steered and holdout, and the difference in differences (did), stored once in
   check_result.realised; 20 recommendations per call. Returns the number of reviews. */
create or replace function b2b.ai_review_tick()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  rec b2b.ai_recommendations;
  st record; ho record;
  v_scope jsonb;
  v_z numeric;
  v_verdict text;
  v_tries int;
  v_n int := 0;
  pol jsonb;
  v_res jsonb;
  v_path text[];
  v_md int := round(coalesce(b2b.stats_num((select s.value -> 'a3_fixed' -> 'matured_days' from b2b.settings s where s.key = 'engine')), 60))::int;
  v_end timestamptz;
  v_real jsonb;
begin
  for rec in select * from b2b.ai_recommendations where status = 'applied' and kind = 'setting_change' and check_due_at <= now()
                                                     and coalesce(check_result ->> 'final', 'false') <> 'true'
                                                     order by created_at, id for update skip locked loop
    v_scope := jsonb_strip_nulls(jsonb_build_object('segment', rec.applied -> 'change' ->> 'segment', 'partner_id', rec.applied -> 'change' ->> 'partner_id'));
    select * into st from b2b.expected_ncpl_rows(rec.decided_at, now(), v_scope) where not holdout;
    select * into ho from b2b.expected_ncpl_rows(rec.decided_at, now(), v_scope) where holdout;
    v_tries := coalesce((rec.check_result ->> 'tries')::int, 0) + 1;
    if coalesce(st.n, 0) < 20 or coalesce(ho.n, 0) < 10 then
      v_verdict := case when v_tries >= 3 then 'inconclusive' else 'waiting' end;
      v_z := null;
    else
      v_z := round((st.mean - ho.mean) / nullif(sqrt(st.var / st.n + ho.var / ho.n), 0), 2);
      v_verdict := case when st.mean < ho.mean and coalesce(v_z, -9) <= -1 then 'worse' else 'kept' end;
    end if;
    update b2b.ai_recommendations
       set check_result = coalesce(check_result, '{}'::jsonb) || jsonb_build_object('tries', v_tries, 'at', now(), 'verdict', v_verdict,
                            'steered', jsonb_build_object('leads', coalesce(st.n, 0), 'expected_ncpl', round(st.mean, 2)),
                            'holdout', jsonb_build_object('leads', coalesce(ho.n, 0), 'expected_ncpl', round(ho.mean, 2)), 'z', v_z,
                            'final', v_verdict <> 'waiting'),
           check_due_at = case when v_verdict = 'waiting' then now() + interval '7 days' else check_due_at end
     where id = rec.id;
    if v_verdict = 'worse' then
      if rec.decided_by = 'autopilot' then
        v_path := (select array_agg(x) from jsonb_array_elements_text(case when jsonb_typeof(rec.applied -> 'path') = 'array' then rec.applied -> 'path' else '[]'::jsonb end) x);
        if v_path is null or cardinality(v_path) <> 2 or v_path[1] <> 'ai'
           or v_path[2] not in ('effort_weights', 'effort_bounds', 'sla_floor', 'half_life_days', 'prior_weight') then
          -- a retired Phase 3 slot: nothing to write back (C5)
          update b2b.ai_recommendations set check_result = check_result || jsonb_build_object('not_rolled_back', 'retired by Addendum 3') where id = rec.id;
          perform b2b.log_event('alert.ai_review_worse', null, null, null, jsonb_build_object('id', rec.id, 'title', rec.title, 'z', v_z, 'retired', true));
        else
          pol := b2b.setting_for_update('engine_policy');
          if coalesce(pol #> v_path, 'null'::jsonb) is distinct from coalesce(rec.applied -> 'to', 'null'::jsonb) then
            update b2b.ai_recommendations
               set status = 'superseded',
                   check_result = check_result || jsonb_build_object('not_rolled_back', 'the setting was changed after this recommendation', 'superseded_at', now())
             where id = rec.id;
            perform b2b.log_event('alert.ai_review_worse', null, null, null, jsonb_build_object('id', rec.id, 'title', rec.title, 'z', v_z, 'superseded', true));
          else
            pol := b2b.jsonb_put(pol, v_path, rec.applied -> 'from');
            v_res := b2b.set_setting('engine_policy', pol, format('autopilot rollback of AI recommendation #%s after its 7-day review', rec.id));
            perform b2b.ai_version_stamp((v_res ->> 'version')::int, rec.run_id, true);
            update b2b.ai_recommendations
               set status = 'rolled_back', check_result = check_result || jsonb_build_object('auto_rolled_back', true, 'version', v_res -> 'version', 'at', now())
             where id = rec.id;
            perform b2b.log_event('alert.ai_rollback', null, null, null, jsonb_build_object('id', rec.id, 'title', rec.title, 'z', v_z));
          end if;
        end if;
      else
        perform b2b.log_event('alert.ai_review_worse', null, null, null, jsonb_build_object('id', rec.id, 'title', rec.title, 'z', v_z));
      end if;
    end if;
    v_n := v_n + 1;
  end loop;

  -- the realised effect, once the leads routed around the change have matured (C42)
  for rec in select * from b2b.ai_recommendations
              where kind = 'setting_change' and status in ('applied', 'rolled_back', 'superseded') and applied is not null
                and (check_result -> 'realised') is null
                and decided_at + make_interval(days => v_md + 14) <= now()
              order by decided_at, id limit 20 for update skip locked loop
    v_end := least(rec.decided_at + interval '14 days',
                   case rec.status
                     when 'rolled_back' then coalesce((rec.check_result ->> 'at')::timestamptz, rec.decided_at + interval '14 days')
                     when 'superseded' then coalesce((rec.check_result ->> 'superseded_at')::timestamptz, rec.decided_at + interval '14 days')
                     else rec.decided_at + interval '14 days' end);
    select jsonb_build_object(
             'before', jsonb_build_object('leads', count(*) filter (where not q.holdout and not q.aft), 'ncpl', round(avg(q.r) filter (where not q.holdout and not q.aft), 2)),
             'after', jsonb_build_object('leads', count(*) filter (where not q.holdout and q.aft), 'ncpl', round(avg(q.r) filter (where not q.holdout and q.aft), 2)),
             'holdout_before', jsonb_build_object('leads', count(*) filter (where q.holdout and not q.aft), 'ncpl', round(avg(q.r) filter (where q.holdout and not q.aft), 2)),
             'holdout_after', jsonb_build_object('leads', count(*) filter (where q.holdout and q.aft), 'ncpl', round(avg(q.r) filter (where q.holdout and q.aft), 2)),
             'did', round((avg(q.r) filter (where not q.holdout and q.aft) - avg(q.r) filter (where not q.holdout and not q.aft))
                          - (avg(q.r) filter (where q.holdout and q.aft) - avg(q.r) filter (where q.holdout and not q.aft)), 2),
             'window_days', 14, 'from', rec.decided_at - interval '14 days', 'to', v_end, 'at', now())
      into v_real
      from (select coalesce(d.holdout, false) holdout, a.created_at >= rec.decided_at aft, b2b.allocation_reward(a.id) r
              from b2b.allocations a join b2b.engine_decisions d on d.id = a.engine_decision_id
             where a.destination_type = 'partner' and not a.is_test and a.status in ('pushed', 'accepted', 'closed') and d.stage is not null
               and a.created_at >= rec.decided_at - interval '14 days' and a.created_at < v_end) q;
    update b2b.ai_recommendations set check_result = coalesce(check_result, '{}'::jsonb) || jsonb_build_object('realised', v_real) where id = rec.id;
  end loop;
  return v_n;
end $fn$;

/* Autopilot (settings ai.mode = 'autopilot'): applies an open setting change whose simulation rests on enough decisions,
   shows at least min_gain_pct with a 95% interval above zero and a support share of at least ai.autopilot.min_support
   (0.5); at most max_per_day a day; in created_at, id order (C41). Nothing is applied while routing is switched off or
   the engine is disabled, the same switches route_ready_leads uses (C28): a change applied then would take effect
   unreviewed when routing comes back. Reviews run either way. */
create or replace function b2b.ai_autopilot_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.ai_cfg();
  ap jsonb := coalesce(cfg -> 'autopilot', '{}'::jsonb);
  rec b2b.ai_recommendations;
  v_today int;
  v_applied int := 0;
  v_change jsonb;
  v_min_support numeric := coalesce(b2b.stats_num(ap -> 'min_support'), 0.5);
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.ai_autopilot_tick')) then return '{"busy":true}'; end if;
  perform set_config('b2b.actor', 'engine', true);
  if not b2b.is_live('routing') or not coalesce((select (s.value ->> 'enabled')::boolean from b2b.settings s where s.key = 'engine'), true) then
    return jsonb_build_object('applied', 0, 'paused', 'routing is off', 'reviewed', b2b.ai_review_tick());
  end if;
  if coalesce((cfg ->> 'enabled')::boolean, false) and cfg ->> 'mode' = 'autopilot' then
    select count(*) into v_today from b2b.ai_recommendations
     where decided_by = 'autopilot' and decided_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
    for rec in select * from b2b.ai_recommendations
                where status = 'open' and kind = 'setting_change' and expires_at > now()
                order by created_at, id for update skip locked loop
      exit when v_today + v_applied >= coalesce((ap ->> 'max_per_day')::int, 3);
      continue when not coalesce((rec.simulation ->> 'simulated')::boolean, false)
                 or coalesce((rec.simulation ->> 'decisions')::int, 0) < coalesce((ap ->> 'min_decisions')::int, 30)
                 or coalesce((rec.simulation ->> 'gain_pct')::numeric, -100) < coalesce((ap ->> 'min_gain_pct')::numeric, 3)
                 or coalesce((rec.simulation -> 'ci95' ->> 0)::numeric, -1) <= 0
                 or coalesce(b2b.stats_num(rec.simulation -> 'support'), 0) < v_min_support;
      begin
        v_change := b2b.ai_validate_change(rec.change);
        perform b2b.ai_apply_setting(rec.id, v_change, 'autopilot',
                                     format('simulated +%s%% (95%%: %s to %s) on %s decisions, support %s', rec.simulation ->> 'gain_pct', rec.simulation -> 'ci95' ->> 0,
                                            rec.simulation -> 'ci95' ->> 1, rec.simulation ->> 'decisions', rec.simulation ->> 'support'));
        v_applied := v_applied + 1;
      exception when sqlstate '22023' then
        update b2b.ai_recommendations set decision_note = 'autopilot skipped: ' || left(sqlerrm, 200) where id = rec.id;
      end;
    end loop;
  end if;
  return jsonb_build_object('applied', v_applied, 'reviewed', b2b.ai_review_tick());
end $fn$;

/* The Admin's replay of a what-if (Routing -> Simulate; C113): the Admin's own ranges, not the AI's (half-life 7-120,
   prior strength 1-100, effort weights 0-5 with a positive sum, effort bounds inside a3_fixed.effort_range, SLA floor
   inside a3_fixed.sla_range), simulated with scope 'admin' (the value replaces the Admin's slot), plus the projection on
   the young decisions of the last 60 days ('recent'). */
create or replace function b2b.simulate_change(p_change jsonb, p_days int default 90)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_lever text := p_change ->> 'lever';
  fx jsonb := coalesce((select s.value -> 'a3_fixed' from b2b.settings s where s.key = 'engine'), '{}'::jsonb);
  er_lo numeric := least(coalesce(b2b.stats_num(fx -> 'effort_range' -> 0), 0.85), 1);
  er_hi numeric := greatest(coalesce(b2b.stats_num(fx -> 'effort_range' -> 1), 1.15), 1);
  sr_hi numeric := least(coalesce(b2b.stats_num(fx -> 'sla_range' -> 1), 1.00), 1);
  sr_lo numeric := least(coalesce(b2b.stats_num(fx -> 'sla_range' -> 0), 0.80), 1);
  w_lo numeric := greatest(coalesce(b2b.stats_num(fx -> 'weight_range' -> 0), 0), 0);
  w_hi numeric := greatest(coalesce(b2b.stats_num(fx -> 'weight_range' -> 1), 5), 0);
  v_num numeric; v_lo numeric; v_hi numeric;
  v_val jsonb;
  v_days int := least(greatest(coalesce(p_days, 90), 7), 365);
  v_change jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_change is null or jsonb_typeof(p_change) <> 'object' then raise exception 'no change given' using errcode = '22023'; end if;
  case v_lever
  when 'half_life_days' then
    if jsonb_typeof(p_change -> 'value') is distinct from 'number' then raise exception 'the change needs a numeric value' using errcode = '22023'; end if;
    v_num := (p_change ->> 'value')::numeric;
    if v_num <> round(v_num) or not (v_num between 7 and 120) then raise exception 'the recency half-life is 7 to 120 days' using errcode = '22023'; end if;
    v_val := to_jsonb(v_num::int);
  when 'prior_weight' then
    if jsonb_typeof(p_change -> 'value') is distinct from 'number' then raise exception 'the change needs a numeric value' using errcode = '22023'; end if;
    v_num := (p_change ->> 'value')::numeric;
    if not (v_num between 1 and 100) then raise exception 'prior strength is 1 to 100 leads' using errcode = '22023'; end if;
    v_val := to_jsonb(round(v_num, 1));
  when 'effort_weights' then
    if jsonb_typeof(p_change -> 'value') is distinct from 'object' or (select count(*) from jsonb_each(p_change -> 'value')) = 0
       or exists (select 1 from jsonb_each(p_change -> 'value') w
                   where jsonb_typeof(w.value) <> 'number' or w.key not in ('first_call', 'attempts_72h', 'connect_rate', 'followup', 'acts_per_open', 'stale_share')
                      or (w.value #>> '{}')::numeric < w_lo or (w.value #>> '{}')::numeric > w_hi)
       or (select sum((w.value #>> '{}')::numeric) from jsonb_each(p_change -> 'value') w where jsonb_typeof(w.value) = 'number') <= 0 then
      raise exception '%', format('effort weights are %s to %s each, and not all 0', w_lo, w_hi) using errcode = '22023';
    end if;
    v_val := (select jsonb_object_agg(w.key, round((w.value #>> '{}')::numeric, 3)) from jsonb_each(p_change -> 'value') w);
  when 'effort_bounds' then
    if jsonb_typeof(p_change -> 'value') is distinct from 'array' or jsonb_array_length(p_change -> 'value') <> 2
       or exists (select 1 from jsonb_array_elements(p_change -> 'value') x where jsonb_typeof(x) <> 'number') then
      raise exception 'the change needs [low, high] bounds' using errcode = '22023';
    end if;
    v_lo := (p_change -> 'value' ->> 0)::numeric; v_hi := (p_change -> 'value' ->> 1)::numeric;
    if v_lo < er_lo or v_lo > 1 or v_hi < 1 or v_hi > er_hi then
      raise exception '%', format('effort bounds are %s–%s (low) and %s–%s (high)', to_char(er_lo, 'FM0.00'), '1.00', '1.00', to_char(er_hi, 'FM0.00')) using errcode = '22023';
    end if;
    v_val := jsonb_build_array(round(v_lo, 3), round(v_hi, 3));
  when 'sla_floor' then
    if jsonb_typeof(p_change -> 'value') is distinct from 'number' then raise exception 'the change needs a numeric value' using errcode = '22023'; end if;
    v_num := (p_change ->> 'value')::numeric;
    if v_num < sr_lo or v_num > sr_hi then
      raise exception '%', format('the SLA floor is %s to %s', to_char(sr_lo, 'FM0.00'), to_char(sr_hi, 'FM0.00')) using errcode = '22023';
    end if;
    v_val := to_jsonb(round(v_num, 3));
  else
    raise exception 'the simulator covers effort weights and bounds, the SLA floor, the half-life and prior strength' using errcode = '22023';
  end case;
  v_change := jsonb_build_object('lever', v_lever, 'value', v_val, 'scope', 'admin');
  return b2b.ai_simulate(v_change, v_days) || jsonb_build_object('recent', b2b.ai_simulate_recent(v_change, least(v_days, 60)));
end $fn$;

-- ======================================================================================================== data
/* ai.autopilot.min_support: the support share a simulation needs before Autopilot applies it (seeded once). */
do $ai$
declare v jsonb := (select value from b2b.settings where key = 'ai');
begin
  perform set_config('b2b.actor', 'system', true);
  if v is not null and not (case when jsonb_typeof(v -> 'autopilot') = 'object' then v -> 'autopilot' else '{}'::jsonb end ? 'min_support') then
    perform b2b.set_setting('ai', v || jsonb_build_object('autopilot', case when jsonb_typeof(v -> 'autopilot') = 'object' then v -> 'autopilot' else '{}'::jsonb end
                                                                       || '{"min_support":0.5}'::jsonb),
                            'Addendum 3: Autopilot applies a change only when its simulation is supported by the log (min_support 0.5)');
  end if;
end $ai$;

/* engine_policy.ai keeps the five Addendum 3 levers only (m31a stripped the retired ones; this guards any later write). */
do $pol$
declare
  p jsonb := (select value from b2b.settings where key = 'engine_policy');
  ai jsonb; n jsonb;
begin
  perform set_config('b2b.actor', 'system', true);
  if p is null then return; end if;
  ai := case when jsonb_typeof(p -> 'ai') = 'object' then p -> 'ai' else '{}'::jsonb end;
  n := coalesce((select jsonb_object_agg(x.k, x.v) from jsonb_each(ai) x(k, v)
                  where x.k in ('effort_weights', 'effort_bounds', 'sla_floor', 'half_life_days', 'prior_weight')), '{}'::jsonb);
  if n is distinct from ai then
    perform b2b.set_setting('engine_policy', p || jsonb_build_object('ai', n), 'Addendum 3: the AI optimiser keeps its five levers only (m31m)');
  end if;
end $pol$;

/* Cutover (once): a model still in use here was trained on the old features and the old scoring (m31a retired the ones
   it found; a nightly run between m31a and this file could have trained another). None may decide from now on; the
   nightly run or the Admin's 'Train now' produces the first Addendum 3 shadow. */
do $cut$
declare v_n int;
begin
  if exists (select 1 from b2b.ai_state where key = 'a3_ml_cutover') then return; end if;
  update b2b.ml_models
     set status = 'retired', status_at = now(), status_by = 'system',
         status_reason = 'Addendum 3: features and scoring changed at m31m; retrain'
   where status in ('shadow', 'challenger', 'champion');
  get diagnostics v_n = row_count;
  insert into b2b.ai_state (key, value, updated_at) values ('a3_ml_cutover', jsonb_build_object('at', now(), 'retired', v_n), now())
  on conflict (key) do nothing;
end $cut$;

-- ======================================================================================================== grants
revoke execute on function b2b.ml_isotonic(float8[], float8[]), b2b.ml_eval(float8[], float8[]), b2b.ml_predict(jsonb, jsonb, jsonb),
                           b2b.ml_lead_features(public.student_leads), b2b.ml_features(jsonb, bigint, jsonb), b2b.ml_train(bigint), b2b.ml_champion_check(bigint), b2b.ml_monitor(),
                           b2b.ai_alert_detail(text, jsonb), b2b.ai_version_stamp(int, bigint, boolean), b2b.ai_validate_change(jsonb), b2b.ai_change_path(jsonb, bigint),
                           b2b.ai_policy_probs(b2b.engine_decisions, jsonb), b2b.ai_simulate(jsonb, int), b2b.ai_simulate_recent(jsonb, int), b2b.ai_uplift(int),
                           b2b.ai_tool(text, jsonb), b2b.ai_apply_setting(bigint, jsonb, text, text), b2b.ai_review_tick(), b2b.ai_autopilot_tick()
  from public, anon, authenticated;
grant execute on function b2b.ml_isotonic(float8[], float8[]), b2b.ml_eval(float8[], float8[]), b2b.ml_predict(jsonb, jsonb, jsonb),
                          b2b.ml_lead_features(public.student_leads), b2b.ml_features(jsonb, bigint, jsonb), b2b.ml_train(bigint), b2b.ml_champion_check(bigint), b2b.ml_monitor(),
                          b2b.ai_alert_detail(text, jsonb), b2b.ai_version_stamp(int, bigint, boolean), b2b.ai_validate_change(jsonb), b2b.ai_change_path(jsonb, bigint),
                          b2b.ai_policy_probs(b2b.engine_decisions, jsonb), b2b.ai_simulate(jsonb, int), b2b.ai_simulate_recent(jsonb, int), b2b.ai_uplift(int),
                          b2b.ai_tool(text, jsonb), b2b.ai_apply_setting(bigint, jsonb, text, text), b2b.ai_review_tick(), b2b.ai_autopilot_tick()
  to service_role;
revoke execute on function b2b.ai_recommendation_decide(bigint, text, text, jsonb), b2b.ai_recommendation_rollback(bigint, text), b2b.simulate_change(jsonb, int)
  from public, anon;
grant execute on function b2b.ai_recommendation_decide(bigint, text, text, jsonb), b2b.ai_recommendation_rollback(bigint, text), b2b.simulate_change(jsonb, int)
  to authenticated, service_role;
