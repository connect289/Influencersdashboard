-- M31c: Addendum 3 statistics (docs/B2B_CRM_ADDENDUM_3.md PART 4 Stages B and C, PART 6.4). The numbers the staged
-- scorer uses, and the guardrails:
--   received and matured counts per partner and segment key (university key course|level|mode|u<id>, the 3-part
--     segment and the course roll-up course|*|*), with test allocations never counted;
--   the sales-effort factor from six synced-activity metrics, each compared with the median of the partners at the
--     same key over the last 30 days (partner-wide against all partners when the key is thin);
--   the stepped SLA-adherence factor (first attempt, status update, enrolment proof; 30 days, partner-wide);
--   P(enrol) from real matured conversion only (leading indicators off), with upheld after-acceptance duplicate
--     disputes left out (C53) and young stages credited only while the partner still holds the lead (C54);
--   auto-pause after 5 first-contact breaches in a row (met late counts) or 30 minutes of CRM sync failure, after which
--     the partner's queued pushes fail over at once (never counted as an attempt or a tried partner).
--
-- Owner's correction (7 Oct 2026; PART 4 'Bounds and weights are Admin settings, versioned'): the effort bounds and the
-- six effort weights (engine.effort_factor), and the SLA floor, ceiling, step and the three SLA weights
-- (engine.sla_factor) are Admin settings inside the rulebook ranges held in engine.a3_fixed (effort 0.85-1.15, SLA
-- 0.80-1.00, step 0.01-0.20, weights 0-5). engine_params clips them into those ranges again, and clips the AI optimiser's
-- overlay (engine_policy.ai.effort_weights, effort_bounds, sla_floor) inside the Admin's current bounds. Holdout leads
-- (engine_params(true)) never see the AI overlay. Every other rulebook number is read from engine.a3_fixed.
--
-- The effort and SLA levers act at decision time (C1 point 5): partner_segment_stats keeps the per-metric detail and
-- the adherence, and the scorer recomputes the factors with b2b.effort_from_detail / b2b.sla_factor_of and the
-- parameters of the lead (Admin or AI). The stored effort_factor and sla_factor columns are the Admin baseline (display).
-- Changes that alter the stored numbers (half-life or prior strength, Admin or AI; min_sample; SLA weights) are picked up
-- within a minute by b2b.stats_refresh_if_stale (cron b2b-stats-ai-catchup), through segment_stats.params.
--
-- Compatible with the m24b route_score until m31f replaces it: p_hat, alpha, beta, refund_rate, sla_compliance (now the
-- adherence), speed and reliability (both 1: retired) are still written.
--
-- Replaces: b2b.engine_params, b2b.segment_rollup, b2b.allocation_outcomes, b2b.keyed_outcomes, b2b.stats_refresh,
-- b2b.guard_tick (m24a_performance_stats.sql), b2b.partner_set_status (20261006125802_m4b_partners.sql),
-- b2b.partner_sync_tick (20261007043436_m23a_sync_cadence.sql).
-- New: b2b.stats_num, b2b.effort_from_detail, b2b.sla_factor_of, b2b.received_counts, b2b.followup_checks,
-- b2b.effort_detail_rows, b2b.sla_adherence_rows, b2b.stats_refresh_if_stale, b2b.partner_paused_failover;
-- cron b2b-stats-ai-catchup (every minute; created paused when b2b-stats-refresh is paused). The m24a cron jobs
-- (b2b-stats-refresh hourly, b2b-guard-tick every 5 minutes) are kept as they are.
-- Data: partner_adapter_state.last_poll_ok_at is filled from last_poll_at where the last poll succeeded.
-- Nothing here touches student_leads, Witty (w2_*) or the catalogue.

-- ---------- small pure helpers ----------
/* A number from a JSON value: a JSON number, or a string holding a plain decimal; anything else is null (never raises,
   so a malformed setting falls back to its default instead of stopping routing). */
create or replace function b2b.stats_num(p jsonb)
returns numeric language sql immutable set search_path = '' as $fn$
  select case jsonb_typeof(p)
           when 'number' then (p #>> '{}')::numeric
           when 'string' then case when btrim(p #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' then btrim(p #>> '{}')::numeric end
         end;
$fn$;

/* The sales-effort factor (PART 4) from a partner_segment_stats.effort_detail and an effort parameter object
   (engine_params(..) -> 'effort': enabled, lo, hi, weights):
     r_bar = sum(w_i * r_i) / sum(w_i) over the metrics whose r is known (w_i from p_effort.weights, 1 when missing);
     factor = 1 + r_bar * (hi - 1) when r_bar > 0, else 1 + r_bar * (1 - lo);
   1.0 when the factor is disabled, there is no detail or no metric is known; at most 1.0 when the partner syncs no
   outbound activity (capped_no_activity). Rounded to 4 places. */
create or replace function b2b.effort_from_detail(p_detail jsonb, p_effort jsonb)
returns numeric language plpgsql immutable set search_path = '' as $fn$
declare
  v_lo numeric := least(greatest(coalesce(b2b.stats_num(p_effort -> 'lo'), 0.85), 0), 1);
  v_hi numeric := greatest(coalesce(b2b.stats_num(p_effort -> 'hi'), 1.15), 1);
  v_sw numeric := 0;
  v_swr numeric := 0;
  v_r numeric;
  v_w numeric;
  v_rbar numeric;
  v_f numeric := 1;
  m record;
begin
  if jsonb_typeof(p_effort -> 'enabled') = 'boolean' and not (p_effort ->> 'enabled')::boolean then return 1.0; end if;
  if p_detail is null or jsonb_typeof(p_detail -> 'metrics') is distinct from 'object' then return 1.0; end if;
  for m in select x.key, x.value from jsonb_each(p_detail -> 'metrics') x loop
    v_r := b2b.stats_num(m.value -> 'r');
    continue when v_r is null;
    v_w := greatest(coalesce(b2b.stats_num(p_effort -> 'weights' -> m.key), 1), 0);
    v_sw := v_sw + v_w;
    v_swr := v_swr + v_w * least(greatest(v_r, -1), 1);
  end loop;
  if v_sw > 0 then
    v_rbar := v_swr / v_sw;
    v_f := case when v_rbar > 0 then 1 + v_rbar * (v_hi - 1) else 1 + v_rbar * (1 - v_lo) end;
  end if;
  if jsonb_typeof(p_detail -> 'capped_no_activity') = 'boolean' and (p_detail ->> 'capped_no_activity')::boolean then
    v_f := least(v_f, 1);
  end if;
  return round(v_f, 4);
end $fn$;

/* The SLA-adherence factor (PART 4) from an adherence share, the number of decided checks behind it and an SLA
   parameter object (engine_params(..) -> 'sla': enabled, floor, ceiling, step): every full 10 points below 100%
   subtracts one step, never below the floor nor above the ceiling (95% -> 1.0, 90% -> 0.95, 85% -> 0.95, 55% -> 0.80 with
   the rulebook values). 1.0 when disabled; the ceiling when there are no decided checks. Rounded to 4 places. */
create or replace function b2b.sla_factor_of(p_adherence numeric, p_total int, p_sla jsonb)
returns numeric language plpgsql immutable set search_path = '' as $fn$
declare
  v_floor numeric := least(greatest(coalesce(b2b.stats_num(p_sla -> 'floor'), 0.80), 0), 1);
  v_ceil numeric;
  v_step numeric := greatest(coalesce(b2b.stats_num(p_sla -> 'step'), 0.05), 0);
begin
  if jsonb_typeof(p_sla -> 'enabled') = 'boolean' and not (p_sla ->> 'enabled')::boolean then return 1.0; end if;
  v_ceil := least(greatest(coalesce(b2b.stats_num(p_sla -> 'ceiling'), 1.0), v_floor), 1);
  if coalesce(p_total, 0) <= 0 or p_adherence is null then return round(v_ceil, 4); end if;
  return round(least(v_ceil, greatest(v_floor, 1 - v_step * floor((1 - least(greatest(p_adherence, 0), 1)) * 10 + 0.000000001))), 4);
end $fn$;

-- ---------- effective parameters ----------
/* The engine's statistical and factor parameters. The Admin's engine settings, clipped into the rulebook ranges of
   engine.a3_fixed; unless p_base (holdout leads, the 'base' stats and the Admin baseline), the AI optimiser's overlay
   from engine_policy.ai, clipped inside the Admin's bounds. Keys:
     matured_days = maturity_days (a3_fixed, 60), half_life_days, prior_weight, default_p_enroll, min_matured_leads
     (a3_fixed.stage_c_min_matured), leading_weight 0 (real matured conversion only), leading_min_days, speed_on and
     reliability_on (false: retired);
     effort {enabled, lo, hi, weights {first_call, attempts_72h, connect_rate, followup, acts_per_open, stale_share},
             min_sample, window_days, source 'admin'|'ai'};
     sla {enabled, floor, ceiling, step, weights {first_attempt, status_update, enrollment_proof}, window_days, source};
     stages (the a3_fixed gates);
     stats_params: what the stored stats depend on (half-life and prior strength with the overlay, default P, matured
       days, and the Admin's effort and SLA settings); stats_refresh stores it in segment_stats.params;
     ai_stats_wanted: the AI changed half_life_days or prior_weight (never for p_base);
     variant: 'ai' only when ai_stats_wanted and 'ai' stats rows built with exactly these stats_params exist; else
       'base' (so a fresh AI change uses the base stats until the catch-up job rebuilds, never missing ones). */
create or replace function b2b.engine_params(p_base boolean)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  e jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}');
  p jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine_policy'), '{}');
  fx jsonb;
  ai jsonb;
  ef jsonb;
  sf jsonb;
  k text;
  x numeric;
  v_md int;
  v_hl int;
  v_pw numeric;
  v_dpe numeric;
  v_lmin int;
  v_wd int;
  er_lo numeric;
  er_hi numeric;
  sr_lo numeric;
  sr_hi numeric;
  st_lo numeric;
  st_hi numeric;
  w_lo numeric;
  w_hi numeric;
  ef_on boolean;
  ef_lo numeric;
  ef_hi numeric;
  ef_ms int;
  ef_w jsonb := '{}';
  sf_on boolean;
  sf_floor numeric;
  sf_ceil numeric;
  sf_step numeric;
  sf_w jsonb := '{}';
  a_lo numeric;
  a_hi numeric;
  a_w jsonb;
  a_floor numeric;
  v_tmp jsonb;
  v_src_e text := 'admin';
  v_src_s text := 'admin';
  v_admin_e jsonb;
  v_admin_s jsonb;
  v_sp jsonb;
  v_want boolean;
  v_variant text := 'base';
begin
  fx := case when jsonb_typeof(e -> 'a3_fixed') = 'object' then e -> 'a3_fixed' else '{}'::jsonb end;
  ai := case when not coalesce(p_base, false) and jsonb_typeof(p -> 'ai') = 'object' then p -> 'ai' else '{}'::jsonb end;

  -- the rulebook ranges (a3_fixed); the Admin's and the AI's values must stay inside them
  er_lo := least(coalesce(b2b.stats_num(fx -> 'effort_range' -> 0), 0.85), 1);
  er_hi := greatest(coalesce(b2b.stats_num(fx -> 'effort_range' -> 1), 1.15), 1);
  sr_hi := least(coalesce(b2b.stats_num(fx -> 'sla_range' -> 1), 1.00), 1);
  sr_lo := least(greatest(coalesce(b2b.stats_num(fx -> 'sla_range' -> 0), 0.80), 0), sr_hi);
  st_lo := greatest(coalesce(b2b.stats_num(fx -> 'sla_step_range' -> 0), 0.01), 0);
  st_hi := greatest(coalesce(b2b.stats_num(fx -> 'sla_step_range' -> 1), 0.20), st_lo);
  w_lo := greatest(coalesce(b2b.stats_num(fx -> 'weight_range' -> 0), 0), 0);
  w_hi := greatest(coalesce(b2b.stats_num(fx -> 'weight_range' -> 1), 5), w_lo);
  v_wd := least(greatest(coalesce(b2b.stats_num(fx -> 'factor_window_days'), 30), 1), 365)::int;
  v_md := least(greatest(coalesce(b2b.stats_num(fx -> 'matured_days'), 60), 7), 365)::int;

  -- the Admin's sales-effort factor
  ef := case when jsonb_typeof(e -> 'effort_factor') = 'object' then e -> 'effort_factor' else '{}'::jsonb end;
  ef_on := case when jsonb_typeof(ef -> 'enabled') = 'boolean' then (ef ->> 'enabled')::boolean else true end;
  ef_lo := least(greatest(coalesce(b2b.stats_num(ef -> 'bounds' -> 0), er_lo), er_lo), 1);
  ef_hi := least(greatest(coalesce(b2b.stats_num(ef -> 'bounds' -> 1), er_hi), 1), er_hi);
  ef_ms := round(least(greatest(coalesce(b2b.stats_num(ef -> 'min_sample'), 10), 1), 1000))::int;
  foreach k in array array['first_call', 'attempts_72h', 'connect_rate', 'followup', 'acts_per_open', 'stale_share'] loop
    ef_w := ef_w || jsonb_build_object(k, least(greatest(coalesce(b2b.stats_num(ef -> 'weights' -> k), 1), w_lo), w_hi));
  end loop;
  if coalesce((select sum((w.value #>> '{}')::numeric) from jsonb_each(ef_w) w), 0) <= 0 then
    ef_w := '{"first_call":1,"attempts_72h":1,"connect_rate":1,"followup":1,"acts_per_open":1,"stale_share":1}';
  end if;

  -- the Admin's SLA-adherence factor
  sf := case when jsonb_typeof(e -> 'sla_factor') = 'object' then e -> 'sla_factor' else '{}'::jsonb end;
  sf_on := case when jsonb_typeof(sf -> 'enabled') = 'boolean' then (sf ->> 'enabled')::boolean else true end;
  sf_floor := least(greatest(coalesce(b2b.stats_num(sf -> 'floor'), sr_lo), sr_lo), sr_hi);
  sf_ceil := least(greatest(coalesce(b2b.stats_num(sf -> 'ceiling'), sr_hi), sf_floor), sr_hi);
  sf_step := least(greatest(coalesce(b2b.stats_num(sf -> 'step'), 0.05), st_lo), st_hi);
  foreach k in array array['first_attempt', 'status_update', 'enrollment_proof'] loop
    sf_w := sf_w || jsonb_build_object(k, least(greatest(coalesce(b2b.stats_num(sf -> 'weights' -> k), 1), w_lo), w_hi));
  end loop;
  if coalesce((select sum((w.value #>> '{}')::numeric) from jsonb_each(sf_w) w), 0) <= 0 then
    sf_w := '{"first_attempt":1,"status_update":1,"enrollment_proof":1}';
  end if;

  -- the AI optimiser's overlay, inside the Admin's bounds (none for p_base)
  a_lo := ef_lo;
  a_hi := ef_hi;
  a_w := ef_w;
  a_floor := sf_floor;
  if ai ? 'effort_bounds' then
    x := b2b.stats_num(case jsonb_typeof(ai -> 'effort_bounds') when 'array' then ai -> 'effort_bounds' -> 0
                                                                 when 'object' then ai -> 'effort_bounds' -> 'lo' end);
    if x is not null then a_lo := least(greatest(x, ef_lo), 1); v_src_e := 'ai'; end if;
    x := b2b.stats_num(case jsonb_typeof(ai -> 'effort_bounds') when 'array' then ai -> 'effort_bounds' -> 1
                                                                 when 'object' then ai -> 'effort_bounds' -> 'hi' end);
    if x is not null then a_hi := least(greatest(x, 1), ef_hi); v_src_e := 'ai'; end if;
  end if;
  if jsonb_typeof(ai -> 'effort_weights') = 'object' then
    v_tmp := ef_w;
    foreach k in array array['first_call', 'attempts_72h', 'connect_rate', 'followup', 'acts_per_open', 'stale_share'] loop
      x := b2b.stats_num(ai -> 'effort_weights' -> k);
      if x is not null then v_tmp := v_tmp || jsonb_build_object(k, least(greatest(x, w_lo), w_hi)); end if;
    end loop;
    if v_tmp is distinct from ef_w and coalesce((select sum((w.value #>> '{}')::numeric) from jsonb_each(v_tmp) w), 0) > 0 then
      a_w := v_tmp;
      v_src_e := 'ai';
    end if;
  end if;
  x := b2b.stats_num(ai -> 'sla_floor');
  if x is not null then a_floor := least(greatest(x, sf_floor), sf_ceil); v_src_s := 'ai'; end if;

  v_hl := round(least(greatest(coalesce(b2b.stats_num(ai -> 'half_life_days'), b2b.stats_num(e -> 'half_life_days'), 30), 7), 365))::int;
  v_pw := least(greatest(coalesce(b2b.stats_num(ai -> 'prior_weight'), b2b.stats_num(e -> 'prior_weight'), 20), 1), 200);
  v_dpe := least(greatest(coalesce(b2b.stats_num(e -> 'default_p_enroll'), 0.05), 0.001), 0.9);
  v_lmin := round(greatest(coalesce(b2b.stats_num(p -> 'leading_min_days'), 3), 0))::int;

  v_admin_e := jsonb_build_object('enabled', ef_on, 'lo', ef_lo, 'hi', ef_hi, 'weights', ef_w, 'min_sample', ef_ms, 'window_days', v_wd);
  v_admin_s := jsonb_build_object('enabled', sf_on, 'floor', sf_floor, 'ceiling', sf_ceil, 'step', sf_step, 'weights', sf_w, 'window_days', v_wd);
  v_sp := jsonb_build_object('half_life_days', v_hl, 'prior_weight', v_pw, 'default_p_enroll', v_dpe, 'matured_days', v_md,
                             'admin', jsonb_build_object('effort', v_admin_e, 'sla', v_admin_s));
  v_want := not coalesce(p_base, false) and (ai ? 'half_life_days' or ai ? 'prior_weight');
  if v_want and exists (select 1 from b2b.segment_stats s where s.variant = 'ai' and s.params = v_sp) then
    v_variant := 'ai';
  end if;

  return jsonb_build_object(
    'matured_days', v_md,
    'maturity_days', v_md,
    'half_life_days', v_hl,
    'prior_weight', v_pw,
    'default_p_enroll', v_dpe,
    'min_matured_leads', round(greatest(coalesce(b2b.stats_num(fx -> 'stage_c_min_matured'), 30), 1))::int,
    'leading_weight', 0,
    'leading_min_days', v_lmin,
    'speed_on', false,
    'reliability_on', false,
    'effort', v_admin_e || jsonb_build_object('lo', a_lo, 'hi', a_hi, 'weights', a_w, 'source', v_src_e),
    'sla', v_admin_s || jsonb_build_object('floor', a_floor, 'source', v_src_s),
    'stages', jsonb_build_object(
      'stage_b_min_leads', coalesce(b2b.stats_num(fx -> 'stage_b_min_leads'), 20),
      'stage_b_min_age_days', coalesce(b2b.stats_num(fx -> 'stage_b_min_age_days'), 7),
      'stage_c_min_matured', coalesce(b2b.stats_num(fx -> 'stage_c_min_matured'), 30),
      'stage_c_min_partners', coalesce(b2b.stats_num(fx -> 'stage_c_min_partners'), 2),
      'matured_days', v_md,
      'learn_leads', coalesce(b2b.stats_num(fx -> 'learn_leads'), 30),
      'exploration_share', coalesce(b2b.stats_num(fx -> 'exploration_share'), 0.2),
      'exact_segment_min_leads', coalesce(b2b.stats_num(fx -> 'exact_segment_min_leads'), 30),
      'tier_projected_min_matured', coalesce(b2b.stats_num(fx -> 'tier_projected_min_matured'), 30)),
    'stats_params', v_sp,
    'ai_stats_wanted', v_want,
    'variant', v_variant);
end $fn$;

/* One level up a segment key: a university key 'mba|PG|Online|u18' -> 'mba|PG|Online'; a 3-part key -> the course
   roll-up 'mba|*|*' (which is its own roll-up). */
create or replace function b2b.segment_rollup(p_segment text)
returns text language sql immutable set search_path = '' as $fn$
  select case when array_length(string_to_array(p_segment, '|'), 1) >= 4
              then split_part(p_segment, '|', 1) || '|' || split_part(p_segment, '|', 2) || '|' || split_part(p_segment, '|', 3)
              else split_part(p_segment, '|', 1) || '|*|*' end;
$fn$;

-- ---------- outcomes per allocation ----------
/* One row per real partner allocation the partner actually received (not test; pushed, accepted, closed, or accepted
   once), with its age, its furthest stage before enrolment and whether it enrolled (any enrolment reported, including
   later refunds and cancellations: the refund rate accounts for those). The basis of P(enrol) and of the ML training
   set. Left out: an allocation with an upheld after-acceptance duplicate dispute (no commission, not the partner's
   conversion; C53). An upheld late-activity-after-lost dispute stays counted. The lead's own stage, applied and
   contacted times credit the partner only while the lead is still with this allocation (C54); the 'lost' display stage
   of the 7-day grace never counts as applied. */
create or replace function b2b.allocation_outcomes()
returns table (allocation_id bigint, lead_id bigint, partner_id bigint, segment text, created_at timestamptz, age_days numeric,
               enrolled boolean, enrolment_status text, stage text, first_contact_hours numeric)
language sql stable security definer set search_path = '' as $fn$
  with st as (select e ->> 'key' k, (e ->> 'rank')::int r from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages'),
  a as (select x.* from b2b.allocations x
         where x.destination_type = 'partner' and not x.is_test and x.segment is not null
           and not exists (select 1 from b2b.commission_disputes d
                            where d.allocation_id = x.id and d.status = 'upheld' and d.kind = 'duplicate_after_acceptance')
           and (x.status in ('pushed', 'accepted', 'closed') or x.accepted_at is not null))
  select a.id, a.lead_id, a.partner_id, a.segment, a.created_at,
         round(extract(epoch from now() - a.created_at)::numeric / 86400, 3),
         en.status is not null, en.status,
         -- the furthest stage before enrolment; an enrolled student has applied
         case when en.status is not null or pa.top >= 70
                   or (l.allocation_id = a.id and (l.applied_at >= a.created_at or (select r from st where k = l.stage) between 70 and 998)) then 'applied'
              when pa.top >= 60 or (l.allocation_id = a.id and (select r from st where k = l.stage) between 60 and 69) then 'interested'
              when (l.allocation_id = a.id and l.first_contacted_at >= a.created_at) or pa.top >= 50 or pa.calls > 0 then 'contacted'
              when a.accepted_at is not null or a.status = 'accepted' then 'accepted'
              else 'none' end,
         round(extract(epoch from fc.at - a.created_at)::numeric / 3600, 2)
    from a
    join public.student_leads l on l.id = a.lead_id
    left join lateral (select e.status from public.enrollments e
                        where e.allocation_id = a.id
                           or (e.allocation_id is null and e.lead_id = a.lead_id and e.partner_id = a.partner_id and coalesce(e.cycle_no, 1) = a.cycle_no)
                        order by (e.status <> 'cancelled') desc, e.id desc limit 1) en on true
    left join lateral (select max((select r from st where k = p.outcome)) filter (where p.kind = 'stage_change' and (select r from st where k = p.outcome) < 999) top,
                              count(*) filter (where p.kind in ('call', 'whatsapp', 'meeting') and p.direction is distinct from 'inbound') calls
                         from b2b.partner_activities p where p.allocation_id = a.id) pa on true
    left join lateral (select min(c.met_at) at from b2b.sla_checks c where c.allocation_id = a.id and c.sla = 'first_attempt' and c.met_at is not null) fc on true;
$fn$;

/* Each outcome under its segment keys (the university key when the allocation has one, the 3-part segment and the
   course roll-up) with its weights for the given parameters: a matured lead (age >= matured_days) weighs
   0.5^((age - matured_days) / half-life). Young leads count only while leading_weight > 0 (Addendum 3 sets it to 0:
   P(enrol) is real matured conversion). */
create or replace function b2b.keyed_outcomes(prm jsonb, p_rates jsonb)
returns table (partner_id bigint, segment text, w_m numeric, enr_m numeric, matured boolean, w_y numeric, exp_y numeric, enrolled boolean)
language sql stable security definer set search_path = '' as $fn$
  select o.partner_id, k.seg,
         case when o.age_days >= m.md then power(0.5, (o.age_days - m.md) / m.hl) else 0 end,
         case when o.age_days >= m.md and o.enrolled then power(0.5, (o.age_days - m.md) / m.hl) else 0 end,
         o.age_days >= m.md,
         case when o.age_days >= m.md or m.lw <= 0 then 0
              when o.enrolled then 1
              when o.age_days >= m.lmin then m.lw * least(o.age_days / m.md, 1) else 0 end,
         case when o.age_days >= m.md or m.lw <= 0 then 0
              when o.enrolled then 1
              when o.age_days >= m.lmin then m.lw * least(o.age_days / m.md, 1) * coalesce((p_rates ->> o.stage)::numeric, 0) else 0 end,
         o.enrolled
    from b2b.allocation_outcomes() o
    join b2b.allocations x on x.id = o.allocation_id
   cross join (select coalesce((prm ->> 'matured_days')::numeric, (prm ->> 'maturity_days')::numeric, 60) md,
                      greatest(coalesce((prm ->> 'half_life_days')::numeric, 30), 1) hl,
                      coalesce((prm ->> 'leading_weight')::numeric, 0) lw,
                      coalesce((prm ->> 'leading_min_days')::numeric, 3) lmin) m
   cross join lateral (select x.segment_exact as seg where x.segment_exact is not null
                       union select o.segment
                       union select b2b.segment_rollup(o.segment)) k;
$fn$;

/* Received partner leads per partner and segment key (the same 'received' predicate as the scorer's stage gates and
   the facts: pushed, accepted or closed, or accepted once; never test): n_received, the first one's time, n_matured_c
   (created more than p_matured_days ago: 'sent more than 60 days ago') and leads_30d. */
create or replace function b2b.received_counts(p_now timestamptz, p_matured_days int)
returns table (partner_id bigint, segment text, n_received int, first_lead_at timestamptz, n_matured_c int, leads_30d int)
language sql stable security definer set search_path = '' as $fn$
  select a.partner_id, k.seg, count(*)::int, min(a.created_at),
         (count(*) filter (where a.created_at < p_now - make_interval(days => p_matured_days)))::int,
         (count(*) filter (where a.created_at > p_now - interval '30 days'))::int
    from b2b.allocations a
   cross join lateral (select a.segment_exact as seg where a.segment_exact is not null
                       union select a.segment
                       union select b2b.segment_rollup(a.segment)) k
   where a.destination_type = 'partner' and not a.is_test and a.segment is not null
     and (a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null)
   group by a.partner_id, k.seg;
$fn$;

-- ---------- sales-effort metrics ----------
/* Scheduled follow-up dates (effort metric 4): for each received allocation, the India-time dates that were the
   partner's next_follow_up_at (from the mapped fields of its events) at the start of that date, i.e. the latest value
   the partner set before the day began, from p_since's date up to yesterday (a day must be over to be judged), while
   the partner held the lead (not closed before the day, not lost in grace). done = an outbound call, WhatsApp, SMS,
   email or meeting on that date. */
create or replace function b2b.followup_checks(p_since timestamptz)
returns table (allocation_id bigint, partner_id bigint, scheduled_for date, done boolean)
language sql stable security definer set search_path = '' as $fn$
  with a as (
    select x.id, x.partner_id, coalesce(x.pushed_at, x.created_at) as pushed_at, x.status, x.outcome_at, x.lost_at, x.lost_revived_at
      from b2b.allocations x
     where x.destination_type = 'partner' and not x.is_test
       and (x.status in ('pushed', 'accepted', 'closed') or x.accepted_at is not null)
  ),
  sets as (
    select e.allocation_id, e.received_at, b2b.try_timestamptz(e.mapped -> 'fields' ->> 'next_follow_up_at') as due,
           lead(e.received_at) over (partition by e.allocation_id order by e.received_at, e.id) as next_at
      from b2b.partner_events e
      join a on a.id = e.allocation_id
     where e.mapped -> 'fields' ? 'next_follow_up_at' and e.status <> 'error' and e.discarded_at is null
  ),
  days as (
    select distinct s.allocation_id, (s.due at time zone 'Asia/Kolkata')::date as d
      from sets s
     cross join lateral (select (((s.due at time zone 'Asia/Kolkata')::date)::timestamp at time zone 'Asia/Kolkata') as d0) z
     where s.due is not null
       and s.received_at < z.d0 and (s.next_at is null or s.next_at >= z.d0)
       and (s.due at time zone 'Asia/Kolkata')::date >= (p_since at time zone 'Asia/Kolkata')::date
       and (s.due at time zone 'Asia/Kolkata')::date < (now() at time zone 'Asia/Kolkata')::date
  )
  select d.allocation_id, a.partner_id, d.d,
         exists (select 1 from b2b.partner_activities x
                  where x.allocation_id = d.allocation_id and x.kind in ('call', 'whatsapp', 'sms', 'email', 'meeting')
                    and x.direction is distinct from 'inbound'
                    and x.occurred_at >= z.d0 and x.occurred_at < z.d0 + interval '1 day')
    from days d
    join a on a.id = d.allocation_id
   cross join lateral (select (d.d::timestamp at time zone 'Asia/Kolkata') as d0) z
   where z.d0 >= a.pushed_at
     and (a.status in ('pushed', 'accepted') or coalesce(a.outcome_at, 'infinity'::timestamptz) > z.d0)
     and not (a.lost_at is not null and a.lost_revived_at is null and a.lost_at <= z.d0);
$fn$;

/* The six sales-effort metrics (PART 4) per partner and segment key, as the detail the factor is computed from. Window:
   activity since p_since (30 days, a3_fixed.factor_window_days); received, non-test allocations only.
     first_call     median working minutes from the push to the first outbound call, over allocations pushed in the
                    window; an allocation still uncalled after 72 hours open counts with the working minutes it has been
                    open (it is at least that slow); lower is better;
     attempts_72h   outbound calls in the first 72 hours, average over allocations pushed in the window at least 72 h ago;
     connect_rate   connected / outbound calls made in the window;
     followup       share of scheduled follow-up dates with an outbound activity that day (b2b.followup_checks);
     acts_per_open  outbound activities / open lead-weeks in the window;
     stale_share    share of the open allocations (not lost in grace) whose last report from the partner (or the push)
                    is more than 7 days old; lower is better.
   A partner with no outbound call, WhatsApp, SMS, email or meeting rows in the window (has_activity false) has metrics
   1-5 unknown (never zero), is left out of their medians, keeps stale_share and is capped at 1.0 (capped_no_activity).
   Comparison: at the key when the partner has at least p_min_sample observations there and at least 2 partners do
   (median over those partners; basis 'segment'); otherwise the partner-wide value against the median of the partners
   with at least p_min_sample partner-wide observations (basis 'partner'); otherwise the metric is not scored ('thin').
   r = clip(v / median - 1, -1, 1), or clip(1 - v / median, -1, 1) when lower is better (a zero median gives 0 for a zero
   value, else -1 or +1). detail = {metrics {k: {v, median, n, r, w (Admin weight, display), basis}}, basis 'segment'|
   'partner'|'mixed'|'none', has_activity, capped_no_activity, min_sample, since}. activity_coverage = share of the
   allocations pushed in the window at the key with any outbound activity (shown, not scored). */
create or replace function b2b.effort_detail_rows(p_since timestamptz, p_min_sample int, p_weights jsonb)
returns table (partner_id bigint, segment text, has_activity boolean, activity_coverage numeric, detail jsonb)
language sql stable security definer set search_path = '' as $fn$
  with rcv as (
    select a.id, a.partner_id, a.segment, a.segment_exact,
           coalesce(a.pushed_at, a.created_at) as pushed_at,
           a.status in ('pushed', 'accepted') and (a.lost_at is null or a.lost_revived_at is not null) as open_now,
           case when a.status in ('pushed', 'accepted') and (a.lost_at is null or a.lost_revived_at is not null) then now()
                when a.status in ('pushed', 'accepted') then least(a.lost_at, now())
                else least(coalesce(a.outcome_at, a.updated_at), now()) end as open_until
      from b2b.allocations a
     where a.destination_type = 'partner' and not a.is_test
       and (a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null)
  ),
  keys as (
    select r.id as allocation_id, k.seg
      from rcv r
     cross join lateral (select r.segment_exact as seg where r.segment_exact is not null
                         union select r.segment where r.segment is not null
                         union select b2b.segment_rollup(r.segment) where r.segment is not null) k
  ),
  act as (
    select x.allocation_id, r.partner_id, x.kind, x.outcome, x.occurred_at, r.pushed_at, r.open_until
      from b2b.partner_activities x
      join rcv r on r.id = x.allocation_id
     where x.occurred_at > p_since and x.occurred_at <= now()
       and x.kind in ('call', 'whatsapp', 'sms', 'email', 'meeting') and x.direction is distinct from 'inbound'
  ),
  ha as (select distinct act.partner_id from act),
  ac as (
    select act.allocation_id,
           min(act.occurred_at) filter (where act.kind = 'call' and act.occurred_at >= act.pushed_at) as first_call_at,
           count(*) filter (where act.kind = 'call' and act.occurred_at >= act.pushed_at
                              and act.occurred_at < act.pushed_at + interval '72 hours') as calls_72h,
           count(*) filter (where act.occurred_at >= greatest(act.pushed_at, p_since) and act.occurred_at <= act.open_until) as acts_open,
           count(*) as acts
      from act group by act.allocation_id
  ),
  obs as (
    select r.id as allocation_id, r.partner_id, 'first_call'::text as metric,
           b2b.working_minutes_between(r.partner_id, r.pushed_at, coalesce(ac.first_call_at, r.open_until))::numeric as num,
           1::numeric as den
      from rcv r left join ac on ac.allocation_id = r.id
     where r.pushed_at > p_since and (ac.first_call_at is not null or r.open_until >= r.pushed_at + interval '72 hours')
    union all
    select r.id, r.partner_id, 'attempts_72h', coalesce(ac.calls_72h, 0)::numeric, 1::numeric
      from rcv r left join ac on ac.allocation_id = r.id
     where r.pushed_at > p_since and r.pushed_at <= now() - interval '72 hours'
    union all
    select act.allocation_id, act.partner_id, 'connect_rate', case when act.outcome = 'connected' then 1 else 0 end::numeric, 1::numeric
      from act where act.kind = 'call'
    union all
    select f.allocation_id, f.partner_id, 'followup', case when f.done then 1 else 0 end::numeric, 1::numeric
      from b2b.followup_checks(p_since) f
    union all
    select r.id, r.partner_id, 'acts_per_open', coalesce(ac.acts_open, 0)::numeric,
           (extract(epoch from r.open_until - greatest(r.pushed_at, p_since)) / 86400 / 7)::numeric
      from rcv r left join ac on ac.allocation_id = r.id
     where r.open_until > greatest(r.pushed_at, p_since)
    union all
    select r.id, r.partner_id, 'stale_share',
           case when greatest(r.pushed_at, (select max(e.received_at) from b2b.partner_events e where e.allocation_id = r.id))
                     < now() - interval '7 days' then 1 else 0 end::numeric, 1::numeric
      from rcv r where r.open_now
    union all
    select r.id, r.partner_id, 'coverage', case when coalesce(ac.acts, 0) > 0 then 1 else 0 end::numeric, 1::numeric
      from rcv r left join ac on ac.allocation_id = r.id
     where r.pushed_at > p_since
  ),
  ob as (
    select o.* from obs o
     where o.metric in ('stale_share', 'coverage') or o.partner_id in (select ha.partner_id from ha)
  ),
  pk as (
    select o.partner_id, k.seg, o.metric, count(*) as n,
           case when o.metric = 'first_call' then (percentile_cont(0.5) within group (order by o.num))::numeric
                else sum(o.num) / nullif(sum(o.den), 0) end as v
      from ob o join keys k on k.allocation_id = o.allocation_id
     group by o.partner_id, k.seg, o.metric
  ),
  pp as (
    select o.partner_id, o.metric, count(*) as n,
           case when o.metric = 'first_call' then (percentile_cont(0.5) within group (order by o.num))::numeric
                else sum(o.num) / nullif(sum(o.den), 0) end as v
      from ob o
     group by o.partner_id, o.metric
  ),
  km as (
    select pk.seg, pk.metric, (percentile_cont(0.5) within group (order by pk.v))::numeric as med, count(*) as q
      from pk where pk.metric <> 'coverage' and pk.n >= p_min_sample and pk.v is not null
     group by pk.seg, pk.metric
  ),
  pm as (
    select pp.metric, (percentile_cont(0.5) within group (order by pp.v))::numeric as med, count(*) as q
      from pp where pp.metric <> 'coverage' and pp.n >= p_min_sample and pp.v is not null
     group by pp.metric
  ),
  tg as (select distinct r.partner_id, k.seg from rcv r join keys k on k.allocation_id = r.id),
  mt as (select * from (values ('first_call', true), ('attempts_72h', false), ('connect_rate', false), ('followup', false),
                               ('acts_per_open', false), ('stale_share', true)) v(metric, lower_better)),
  cell as (
    select tg.partner_id, tg.seg, mt.metric, mt.lower_better, ha.partner_id is not null as has_act,
           pk.n as kn, pk.v as kv, km.med as kmed, coalesce(km.q, 0) as kq,
           pp.n as pn, pp.v as pv, pm.med as pmed, coalesce(pm.q, 0) as pq
      from tg
     cross join mt
      left join ha on ha.partner_id = tg.partner_id
      left join pk on pk.partner_id = tg.partner_id and pk.seg = tg.seg and pk.metric = mt.metric
      left join km on km.seg = tg.seg and km.metric = mt.metric
      left join pp on pp.partner_id = tg.partner_id and pp.metric = mt.metric
      left join pm on pm.metric = mt.metric
  ),
  pick as (
    select c.*,
           case when c.metric <> 'stale_share' and not c.has_act then 'no_activity'
                when coalesce(c.kn, 0) >= p_min_sample and c.kv is not null and c.kq >= 2 then 'segment'
                when coalesce(c.pn, 0) >= p_min_sample and c.pv is not null and c.pq >= 1 then 'partner'
                else 'thin' end as basis
      from cell c
  ),
  sc as (
    select p.partner_id, p.seg, p.metric, p.lower_better, p.has_act, p.basis,
           case p.basis when 'segment' then p.kv when 'partner' then p.pv when 'thin' then coalesce(p.kv, p.pv) end as v,
           case p.basis when 'segment' then p.kmed when 'partner' then p.pmed end as med,
           case p.basis when 'segment' then p.kn when 'partner' then p.pn when 'thin' then coalesce(p.kn, p.pn, 0) else 0 end as n
      from pick p
  ),
  rr as (
    select s.*,
           case when s.basis not in ('segment', 'partner') or s.v is null or s.med is null then null
                when s.med = 0 then case when s.v = 0 then 0 when s.lower_better then -1 else 1 end
                when s.lower_better then least(greatest(1 - s.v / s.med, -1), 1)
                else least(greatest(s.v / s.med - 1, -1), 1) end as r
      from sc s
  ),
  cov as (select pk.partner_id, pk.seg, pk.v from pk where pk.metric = 'coverage')
  select rr.partner_id, rr.seg, bool_or(rr.has_act), round(max(cov.v), 4),
         jsonb_build_object(
           'metrics', jsonb_object_agg(rr.metric, jsonb_build_object(
                        'v', round(rr.v, 4), 'median', round(rr.med, 4), 'n', rr.n, 'r', round(rr.r, 4),
                        'w', coalesce(b2b.stats_num(p_weights -> rr.metric), 1), 'basis', rr.basis)),
           'basis', case when count(rr.r) = 0 then 'none'
                         when count(rr.r) = count(rr.r) filter (where rr.basis = 'segment') then 'segment'
                         when count(rr.r) = count(rr.r) filter (where rr.basis = 'partner') then 'partner'
                         else 'mixed' end,
           'has_activity', bool_or(rr.has_act),
           'capped_no_activity', not bool_or(rr.has_act),
           'min_sample', p_min_sample,
           'since', p_since)
    from rr
    left join cov on cov.partner_id = rr.partner_id and cov.seg = rr.seg
   group by rr.partner_id, rr.seg;
$fn$;

/* SLA adherence per partner (PART 4), over first_attempt, status_update and enrollment_proof checks due since p_since,
   decided (met, met late or breached) and not test: adherence = sum(w * met on time) / sum(w * decided), with the
   weights of p_sla.weights (the Admin's; 1 when missing). met and total count the decided checks of SLAs with a weight
   above 0. With the rulebook's equal weights this is the plain share of SLAs met. */
create or replace function b2b.sla_adherence_rows(p_since timestamptz, p_sla jsonb)
returns table (partner_id bigint, met int, total int, adherence numeric)
language sql stable security definer set search_path = '' as $fn$
  select c.partner_id,
         (count(*) filter (where c.status = 'met' and w.w > 0))::int,
         (count(*) filter (where w.w > 0))::int,
         round(coalesce(sum(w.w) filter (where c.status = 'met'), 0) / nullif(sum(w.w), 0), 5)
    from b2b.sla_checks c
   cross join lateral (select greatest(coalesce(b2b.stats_num(p_sla -> 'weights' -> c.sla), 1), 0) as w) w
   where not c.is_test and c.sla in ('first_attempt', 'status_update', 'enrollment_proof')
     and c.status in ('met', 'met_late', 'breached') and c.due_at > p_since
   group by c.partner_id;
$fn$;

-- ---------- hourly refresh ----------
/* Rebuilds the statistics (hourly cron, the Admin's 'refresh now', and the catch-up job). Per variant ('base' always;
   'ai' while the AI optimiser has changed half-life or prior strength): segment priors and auto stage, and per partner
   and key the recency-weighted matured outcomes, the Beta posterior and P̂, the refund rate, and the received/matured
   counts. Then, the same for both variants: the effort detail and the Admin-baseline effort factor, and the partner-wide
   SLA adherence and factor. Finally the daily snapshot and the fall alert (P̂ or NCPL down by more than a third). One
   refresh at a time (transaction advisory lock). */
create or replace function b2b.stats_refresh()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_now timestamptz := now();
  v_variants text[] := array['base'];
  v_variant text;
  prm jsonb;
  v_admin jsonb;
  v_def jsonb := '{"applied":0.35,"interested":0.12,"contacted":0.05,"accepted":0.03,"none":0.01}';
  v_rates jsonb;
  v_global_refund numeric;
  v_md int;
  v_since timestamptz;
  v_bmin int;
  v_bage int;
  v_cmin int;
  v_cpart int;
  v_pw numeric;
  v_dpe numeric;
  v_n int;
  v_rows int := 0;
  v_effort int := 0;
  v_sla int := 0;
  v_alerts int := 0;
  r record;
begin
  perform pg_advisory_xact_lock(hashtext('b2b.stats_refresh'));
  perform set_config('b2b.actor', 'engine', true);
  v_admin := b2b.engine_params(true);
  v_md := (v_admin ->> 'matured_days')::int;
  v_since := v_now - make_interval(days => coalesce((v_admin -> 'effort' ->> 'window_days')::int, 30));
  v_bmin := (v_admin -> 'stages' ->> 'stage_b_min_leads')::numeric::int;
  v_bage := (v_admin -> 'stages' ->> 'stage_b_min_age_days')::numeric::int;
  v_cmin := (v_admin -> 'stages' ->> 'stage_c_min_matured')::numeric::int;
  v_cpart := (v_admin -> 'stages' ->> 'stage_c_min_partners')::numeric::int;

  -- P(enrol | reached at least this stage) from matured leads, shrunk to the defaults with a strength of 10 (shown to
  -- the Admin; with leading_weight 0 it no longer feeds P̂)
  insert into b2b.stage_rates (stage, n, enrolled, rate, refreshed_at)
  select s.k, count(o.*), count(o.*) filter (where o.enrolled),
         round((count(o.*) filter (where o.enrolled) + (v_def ->> s.k)::numeric * 10) / (count(o.*) + 10), 5), v_now
    from (values ('none', 0), ('accepted', 1), ('contacted', 2), ('interested', 3), ('applied', 4)) s(k, rk)
    left join (select x.enrolled, array_position(array['none', 'accepted', 'contacted', 'interested', 'applied'], x.stage) - 1 rk
                 from b2b.allocation_outcomes() x where x.age_days >= v_md) o on o.rk >= s.rk
   group by s.k
  on conflict (stage) do update set n = excluded.n, enrolled = excluded.enrolled, rate = excluded.rate, refreshed_at = excluded.refreshed_at;
  select jsonb_object_agg(stage, rate) into v_rates from b2b.stage_rates;

  -- refund rate basis: (refunded + cancelled) / decided B2B enrolments, without enrolments on allocations whose
  -- after-acceptance duplicate dispute was upheld (C53)
  select coalesce(sum(case when e.status in ('refunded', 'cancelled') then 1 else 0 end)::numeric / nullif(count(*), 0), 0) into v_global_refund
    from public.enrollments e
   where e.source_product = 'b2b' and e.status in ('verified', 'refunded', 'cancelled')
     and not exists (select 1 from b2b.commission_disputes d
                      where d.allocation_id = e.allocation_id and d.status = 'upheld' and d.kind = 'duplicate_after_acceptance');

  if coalesce((b2b.engine_params(false) ->> 'ai_stats_wanted')::boolean, false) then v_variants := array_append(v_variants, 'ai'); end if;

  foreach v_variant in array v_variants loop
    prm := b2b.engine_params(v_variant = 'base');
    v_pw := (prm ->> 'prior_weight')::numeric;
    v_dpe := (prm ->> 'default_p_enroll')::numeric;

    -- segment priors (all partners' matured conversion, shrunk to default_p_enroll with prior_weight) and the stage
    -- the key's partners have reached (C: 2 or more with 30 matured; B: 2 or more, all with 20 received, the first
    -- at least 7 days old; else A)
    insert into b2b.segment_stats (variant, segment, n_leads, n_matured, w_matured, w_enrolled, prior, partners, partners_matured,
                                   auto_mode, auto_stage, params, refreshed_at)
    select v_variant, g.segment, coalesce(o.n, 0), coalesce(o.nm, 0), coalesce(o.wm, 0), coalesce(o.we, 0),
           round((coalesce(o.we, 0) + v_dpe * v_pw) / (coalesce(o.wm, 0) + v_pw), 5),
           g.partners, g.pm,
           case when g.stage in ('B', 'C') then 'performance' else 'commission_first' end, g.stage,
           prm -> 'stats_params', v_now
      from (select c.segment, count(*)::int partners, (count(*) filter (where c.n_matured_c >= v_cmin))::int pm,
                   case when count(*) filter (where c.n_matured_c >= v_cmin) >= v_cpart then 'C'
                        when count(*) >= 2 and bool_and(c.n_received >= v_bmin and c.first_lead_at <= v_now - make_interval(days => v_bage)) then 'B'
                        else 'A' end stage
              from b2b.received_counts(v_now, v_md) c
             group by c.segment) g
      left join (select k.segment, count(*) n, count(*) filter (where k.matured) nm, coalesce(sum(k.w_m), 0) wm, coalesce(sum(k.enr_m), 0) we
                   from b2b.keyed_outcomes(prm, v_rates) k
                  group by k.segment) o on o.segment = g.segment
    on conflict (variant, segment) do update
      set n_leads = excluded.n_leads, n_matured = excluded.n_matured, w_matured = excluded.w_matured, w_enrolled = excluded.w_enrolled,
          prior = excluded.prior, partners = excluded.partners, partners_matured = excluded.partners_matured, auto_mode = excluded.auto_mode,
          auto_stage = excluded.auto_stage, params = excluded.params, refreshed_at = excluded.refreshed_at;

    -- per partner and key: weighted outcomes, Beta posterior and P̂, refund rate (shrunk to the global rate with a
    -- strength of 20), median hours to the first attempt (30 days, shown), received and matured counts
    insert into b2b.partner_segment_stats (variant, partner_id, segment, is_rollup, n_leads, n_matured, w_matured, w_enrolled, n_young, w_young,
                                           w_young_expected, enrolled, prior, alpha, beta, p_hat, refund_rate, first_contact_hours,
                                           speed, reliability, n_received, first_lead_at, n_matured_c, leads_30d, refreshed_at)
    select v_variant, c.partner_id, c.segment, c.segment = b2b.segment_rollup(c.segment),
           coalesce(x.n, 0), coalesce(x.nm, 0), coalesce(x.wm, 0), coalesce(x.we, 0), coalesce(x.ny, 0), coalesce(x.wy, 0),
           coalesce(x.ey, 0), coalesce(x.enr, 0), ss.prior, z.a, z.b, round(z.a / (z.a + z.b), 5),
           round((coalesce(rf.bad, 0) + v_global_refund * 20) / (coalesce(rf.n, 0) + 20), 5),
           ct.fch, 1, 1, c.n_received, c.first_lead_at, c.n_matured_c, c.leads_30d, v_now
      from b2b.received_counts(v_now, v_md) c
      join b2b.segment_stats ss on ss.variant = v_variant and ss.segment = c.segment
      left join (select k.partner_id, k.segment, count(*) n, count(*) filter (where k.matured) nm,
                        sum(k.w_m) wm, sum(k.enr_m) we, count(*) filter (where not k.matured) ny, sum(k.w_y) wy, sum(k.exp_y) ey,
                        count(*) filter (where k.enrolled) enr
                   from b2b.keyed_outcomes(prm, v_rates) k
                  group by k.partner_id, k.segment) x on x.partner_id = c.partner_id and x.segment = c.segment
      cross join lateral (select round(ss.prior * v_pw + coalesce(x.we, 0) + coalesce(x.ey, 0), 4) a,
                                 round((1 - ss.prior) * v_pw + (coalesce(x.wm, 0) - coalesce(x.we, 0)) + (coalesce(x.wy, 0) - coalesce(x.ey, 0)), 4) b) z
      left join (select e.partner_id, count(*) n, count(*) filter (where e.status in ('refunded', 'cancelled')) bad
                   from public.enrollments e
                  where e.source_product = 'b2b' and e.status in ('verified', 'refunded', 'cancelled')
                    and not exists (select 1 from b2b.commission_disputes d
                                     where d.allocation_id = e.allocation_id and d.status = 'upheld' and d.kind = 'duplicate_after_acceptance')
                  group by e.partner_id) rf on rf.partner_id = c.partner_id
      left join (select o.partner_id, (percentile_cont(0.5) within group (order by o.first_contact_hours))::numeric fch
                   from b2b.allocation_outcomes() o
                  where o.first_contact_hours is not null and o.created_at > v_now - interval '30 days'
                  group by o.partner_id) ct on ct.partner_id = c.partner_id
    on conflict (variant, partner_id, segment) do update
      set is_rollup = excluded.is_rollup, n_leads = excluded.n_leads, n_matured = excluded.n_matured, w_matured = excluded.w_matured,
          w_enrolled = excluded.w_enrolled, n_young = excluded.n_young, w_young = excluded.w_young, w_young_expected = excluded.w_young_expected,
          enrolled = excluded.enrolled, prior = excluded.prior, alpha = excluded.alpha, beta = excluded.beta, p_hat = excluded.p_hat,
          refund_rate = excluded.refund_rate, first_contact_hours = excluded.first_contact_hours,
          speed = excluded.speed, reliability = excluded.reliability, n_received = excluded.n_received, first_lead_at = excluded.first_lead_at,
          n_matured_c = excluded.n_matured_c, leads_30d = excluded.leads_30d, refreshed_at = excluded.refreshed_at;
    get diagnostics v_n = row_count;
    v_rows := v_rows + v_n;

    -- keys with no received allocation left (all of them became test, failed...) fall back to the prior
    update b2b.partner_segment_stats s set n_leads = 0, n_matured = 0, w_matured = 0, w_enrolled = 0, n_young = 0, w_young = 0, w_young_expected = 0,
           enrolled = 0, alpha = round(s.prior * v_pw, 4), beta = round((1 - s.prior) * v_pw, 4), p_hat = s.prior,
           n_received = 0, first_lead_at = null, n_matured_c = 0, leads_30d = 0,
           effort_factor = 1, effort_detail = null, has_activity = false, activity_coverage = null, refreshed_at = v_now
     where s.variant = v_variant and s.refreshed_at < v_now;
    update b2b.segment_stats s set n_leads = 0, n_matured = 0, w_matured = 0, w_enrolled = 0, partners = 0, partners_matured = 0,
           auto_mode = 'commission_first', auto_stage = 'A', prior = v_dpe, params = prm -> 'stats_params', refreshed_at = v_now
     where s.variant = v_variant and s.refreshed_at < v_now;
  end loop;
  -- 'ai' rows built for AI parameters since changed or withdrawn are never read: engine_params reads 'ai' only while
  -- their params equal the current ones

  -- sales effort: the detail per partner and key (Admin min_sample), and the Admin-baseline factor (display; the scorer
  -- recomputes it with the lead's parameters through b2b.effort_from_detail)
  update b2b.partner_segment_stats s
     set effort_detail = x.detail,
         has_activity = coalesce(x.has_activity, false),
         activity_coverage = x.activity_coverage,
         effort_factor = b2b.effort_from_detail(x.detail, v_admin -> 'effort')
    from (select ps.variant, ps.partner_id, ps.segment, er.detail, er.has_activity, er.activity_coverage
            from b2b.partner_segment_stats ps
            join b2b.effort_detail_rows(v_since, (v_admin -> 'effort' ->> 'min_sample')::int, v_admin -> 'effort' -> 'weights') er
              on er.partner_id = ps.partner_id and er.segment = ps.segment
           where ps.n_received > 0) x
   where s.variant = x.variant and s.partner_id = x.partner_id and s.segment = x.segment;
  get diagnostics v_effort = row_count;

  -- SLA adherence, partner-wide, on all of the partner's rows; sla_compliance (read by the pre-A3 scorer) is the same
  -- share. No decided check: adherence null, factor = the ceiling (1.0 by default).
  update b2b.partner_segment_stats s
     set sla_met = coalesce(x.met, 0), sla_total = coalesce(x.total, 0), sla_adherence = x.adherence, sla_compliance = x.adherence,
         sla_factor = b2b.sla_factor_of(x.adherence, coalesce(x.total, 0), v_admin -> 'sla'),
         speed = 1, reliability = 1
    from (select ps.partner_id, sa.met, sa.total, sa.adherence
            from (select distinct q.partner_id from b2b.partner_segment_stats q) ps
            left join b2b.sla_adherence_rows(v_since, v_admin -> 'sla') sa on sa.partner_id = ps.partner_id) x
   where s.partner_id = x.partner_id;
  get diagnostics v_sla = row_count;

  -- daily snapshot for the fall alert: NCPL uses the partner's current CPE for the key's course (median of its offers)
  insert into b2b.stats_snapshots (day, partner_id, segment, p_hat, ncpl_inr, n_matured)
  select (v_now at time zone 'Asia/Kolkata')::date, s.partner_id, s.segment, s.p_hat,
         round(s.p_hat * (1 - s.refund_rate) * (select percentile_cont(0.5) within group (order by b2b.cpe_net(o.partner_id, o.programme_id, o.fees))
                                                  from b2b.partner_programmes o join public.catalog_programs c on c.id = o.programme_id
                                                 where o.partner_id = s.partner_id and o.valid_to is null and o.active
                                                   and c.course_key = split_part(s.segment, '|', 1))::numeric, 2),
         s.n_matured
    from b2b.partner_segment_stats s where s.variant = 'base' and s.n_leads > 0
  on conflict (day, partner_id, segment) do update set p_hat = excluded.p_hat, ncpl_inr = excluded.ncpl_inr, n_matured = excluded.n_matured;

  -- fall alert (B7.4): P̂ or NCPL down by more than a third against its value 30 days ago, with matured data, once a week
  for r in
    select n.partner_id, n.segment, o.p_hat old_p, n.p_hat new_p, o.ncpl_inr old_v, n.ncpl_inr new_v
      from b2b.stats_snapshots n
      join b2b.stats_snapshots o on o.partner_id = n.partner_id and o.segment = n.segment
                                and o.day = (select max(x.day) from b2b.stats_snapshots x where x.partner_id = n.partner_id and x.segment = n.segment
                                                                                          and x.day <= n.day - 30)
     where n.day = (v_now at time zone 'Asia/Kolkata')::date and n.n_matured >= 10
       and (n.p_hat < o.p_hat * 2 / 3 or n.ncpl_inr < o.ncpl_inr * 2 / 3)
       and not exists (select 1 from b2b.events e where e.type = 'alert.ncpl_drop' and e.partner_id = n.partner_id
                         and e.payload ->> 'segment' = n.segment and e.occurred_at > v_now - interval '7 days')
  loop
    perform b2b.log_event('alert.ncpl_drop', null, null, r.partner_id,
                          jsonb_build_object('segment', r.segment, 'p_hat_before', r.old_p, 'p_hat_now', r.new_p, 'ncpl_before', r.old_v, 'ncpl_now', r.new_v));
    v_alerts := v_alerts + 1;
  end loop;

  return jsonb_build_object('variants', to_jsonb(v_variants), 'allocations', (select count(*) from b2b.allocation_outcomes()), 'rows', v_rows,
                            'effort_rows', v_effort, 'sla_rows', v_sla, 'alerts', v_alerts, 'at', v_now);
end $fn$;

/* The catch-up job (every minute, C1): rebuilds the statistics when the stored ones no longer match the parameters, so
   an Admin or AI change of half-life or prior strength (or of min_sample or the SLA weights) reaches routing within a
   minute without an Admin request having to wait for a refresh. {busy:true} while another refresh runs; {fresh:true}
   when nothing changed. */
create or replace function b2b.stats_refresh_if_stale()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  prm jsonb;
  pb jsonb;
  v_why text;
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.stats_refresh')) then return '{"busy":true}'::jsonb; end if;
  pb := b2b.engine_params(true);
  prm := b2b.engine_params(false);
  if exists (select 1 from b2b.segment_stats s where s.variant = 'base' and s.params is distinct from pb -> 'stats_params') then
    v_why := 'base';
  elsif coalesce((prm ->> 'ai_stats_wanted')::boolean, false) and prm ->> 'variant' = 'base'
        and exists (select 1 from b2b.segment_stats s where s.variant = 'base') then
    v_why := 'ai';
  end if;
  if v_why is null then return '{"fresh":true}'::jsonb; end if;
  return b2b.stats_refresh() || jsonb_build_object('refreshed', v_why);
end $fn$;

-- ---------- guardrails (PART 6.4) ----------
/* A paused (or closed) partner receives no new leads: its non-test allocations waiting to be pushed (queued, or pushing
   with no request in flight) fail at once, with push_attempts unchanged, and are re-routed. They never count as an
   attempt or a tried partner (D3: a failed allocation counts only with push_attempts > 0, i.e. when a push was really
   sent). An allocation whose push request is in flight is left to its answer, so the partner never has a lead Eduwit
   has also sent elsewhere. Each allocation is handled on its own: an error re-routing one is logged (routing.error)
   and leaves it as it was. Returns the number failed over. */
create or replace function b2b.partner_paused_failover(p_partner_id bigint, p_why text)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  n int := 0;
  v_why text := left(coalesce(nullif(trim(p_why), ''), 'paused'), 300);
begin
  for r in select a.id, a.lead_id, a.push_attempts from b2b.allocations a
            where a.partner_id = p_partner_id and a.destination_type = 'partner' and not a.is_test
              and (a.status = 'queued' or (a.status = 'pushing' and a.push_request_id is null))
            order by a.id
  loop
    begin
      update b2b.allocations set status = 'failed', outcome = 'failed', outcome_at = now(), next_push_at = null,
             last_error = left('partner paused: ' || v_why, 500)
       where id = r.id and partner_id = p_partner_id
         and (status = 'queued' or (status = 'pushing' and push_request_id is null));
      if found then
        perform b2b.log_event('lead.push_failed', r.lead_id, r.id, p_partner_id,
                              jsonb_build_object('error', 'partner paused', 'why', v_why, 'partner_paused', true, 'attempts', r.push_attempts));
        perform b2b.reroute_after(r.id, 'partner paused');
        n := n + 1;
      end if;
    exception when others then
      perform b2b.log_event('routing.error', r.lead_id, r.id, p_partner_id,
                            jsonb_build_object('where', 'partner_paused_failover', 'error', left(sqlerrm, 300)));
    end;
  end loop;
  return n;
end $fn$;

/* Auto-pause a live, active partner (PART 6.4) on:
     1. its last 5 decided first-attempt checks all breached or met late (a3_fixed.auto_pause_breaches);
     2. pushes failing for 30 minutes (3 or more errors or timeouts, none answered);
     3. CRM sync failing for 30 minutes (a3_fixed.auto_pause_sync_minutes): a polled CRM whose latest poll in the last
        15 minutes failed, or whose sign-in has been failing in the last 15 minutes with no valid token, and with no
        successful poll for 30 minutes;
     4. more than 25% duplicates over its last 20 leads, only while engine.guard.duplicate_rate_pause is on (off by default).
   Evidence older than the partner's last switch to active is ignored, so resuming gives it a clean slate (a CRM that
   was already failing when Addendum 3 was installed is timed from the install). A pause then fails over the partner's
   queued pushes (b2b.partner_paused_failover). Runs every 5 minutes. */
create or replace function b2b.guard_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}');
  fx jsonb;
  v_breaches int;
  v_sync_min int;
  v_dup_on boolean;
  v_a3_since timestamptz;
  p record;
  st record;
  v_since timestamptz;
  v_base timestamptz;
  v_poll boolean;
  v_why text;
  v_kind text;
  v_paused int := 0;
  v_failed int := 0;
  v_x record;
begin
  perform set_config('b2b.actor', 'engine', true);
  fx := case when jsonb_typeof(e -> 'a3_fixed') = 'object' then e -> 'a3_fixed' else '{}'::jsonb end;
  v_breaches := round(least(greatest(coalesce(b2b.stats_num(fx -> 'auto_pause_breaches'), 5), 1), 50))::int;
  v_sync_min := round(least(greatest(coalesce(b2b.stats_num(fx -> 'auto_pause_sync_minutes'), 30), 5), 1440))::int;
  v_dup_on := case when jsonb_typeof(e -> 'guard' -> 'duplicate_rate_pause') = 'boolean' then (e -> 'guard' ->> 'duplicate_rate_pause')::boolean else false end;
  v_a3_since := coalesce((select min(v.created_at) from b2b.settings_versions v where v.key = 'engine' and v.value ? 'a3_fixed'), '-infinity'::timestamptz);

  for p in select * from b2b.partners where status = 'active' and b2b.is_live('partner:' || id) order by id loop
    v_since := coalesce((select max(ev.occurred_at) from b2b.events ev where ev.type = 'partner.status_changed' and ev.partner_id = p.id
                                                                       and ev.payload ->> 'to' = 'active'), '-infinity'::timestamptz);
    v_why := null;
    v_kind := null;

    -- 1. first-attempt breaches in a row (met late is a breach)
    select count(*) filter (where c.status in ('breached', 'met_late')) bad, count(*) n into v_x
      from (select c.status from b2b.sla_checks c
             where c.partner_id = p.id and not c.is_test and c.sla = 'first_attempt' and c.status in ('met', 'met_late', 'breached')
               and c.due_at > v_since order by c.due_at desc, c.id desc limit v_breaches) c;
    if v_x.n = v_breaches and v_x.bad = v_breaches then
      v_kind := 'sla_breaches'; v_why := format('missed the first-contact SLA on %s leads in a row', v_breaches);
    end if;

    -- 2. pushes failing
    if v_why is null then
      select count(*) filter (where q.outcome in ('error', 'timeout')) bad, count(*) filter (where q.outcome in ('created', 'duplicate', 'rejected')) ok,
             min(q.sent_at) filter (where q.outcome in ('error', 'timeout')) first_bad into v_x
        from b2b.push_requests q join b2b.allocations a on a.id = q.allocation_id
       where a.partner_id = p.id and not a.is_test and q.sent_at > greatest(v_since, now() - make_interval(mins => v_sync_min + 15));
      if v_x.bad >= 3 and v_x.ok = 0 and v_x.first_bad <= now() - make_interval(mins => v_sync_min) then
        v_kind := 'push_failing'; v_why := format('pushes have failed for %s minutes', v_sync_min);
      end if;
    end if;

    -- 3. CRM sync failing (polled CRMs: the poll, or the sign-in it needs)
    if v_why is null then
      select s.* into st from b2b.partner_adapter_state s where s.partner_id = p.id and s.env = 'live';
      v_poll := found
                and coalesce((b2b.adapter_spec(p.adapter_type) ->> 'poll')::boolean, false)
                and nullif(p.outbound_auth -> 'live' ->> 'secret_id', '') is not null
                and coalesce((p.outbound_auth -> 'live' ->> 'poll')::boolean, true);
      if v_poll then
        v_base := greatest(coalesce(st.last_poll_ok_at, v_a3_since), v_since);
        if v_base <= now() - make_interval(mins => v_sync_min)
           and ((st.last_poll_error is not null
                 and greatest(coalesce(st.last_poll_at, '-infinity'::timestamptz), coalesce(st.poll_requested_at, '-infinity'::timestamptz)) > now() - interval '15 minutes')
                or (st.token_error is not null and st.token_failed_at > now() - interval '15 minutes'
                    and (st.token_expires_at is null or st.token_expires_at <= now()))) then
          v_kind := 'sync_failing'; v_why := format('the CRM sync has been failing for %s minutes', v_sync_min);
        end if;
      end if;
    end if;

    -- 4. duplicate rate over the last 20 leads (only when the Admin turned it on)
    if v_why is null and v_dup_on then
      select count(*) filter (where a.status = 'duplicate') dup, count(*) n into v_x
        from (select a.status from b2b.allocations a
               where a.partner_id = p.id and not a.is_test and a.destination_type = 'partner' and a.created_at > v_since
                 and a.status not in ('queued', 'pushing', 'failed') order by a.created_at desc limit 20) a;
      if v_x.n = 20 and v_x.dup::numeric / v_x.n > 0.25 then
        v_kind := 'duplicate_rate'; v_why := format('duplicate rate is %s%% over the last 20 leads', round(v_x.dup * 100.0 / v_x.n));
      end if;
    end if;

    if v_why is not null then
      update b2b.partners set status = 'paused', paused_reason = 'auto-paused: ' || v_why, auto_paused_at = now(), updated_at = now(), updated_by = 'engine'
       where id = p.id and status = 'active';
      if found then
        perform b2b.log_event('partner.status_changed', null, null, p.id, jsonb_build_object('from', 'active', 'to', 'paused', 'reason', 'auto-paused: ' || v_why, 'auto', true));
        perform b2b.log_event('alert.partner_auto_paused', null, null, p.id, jsonb_build_object('kind', v_kind, 'reason', v_why, 'partner', coalesce(p.display_name, p.name)));
        v_paused := v_paused + 1;
        v_failed := v_failed + b2b.partner_paused_failover(p.id, 'auto-paused: ' || v_why);
      end if;
    end if;
  end loop;
  return jsonb_build_object('paused', v_paused, 'failed_over', v_failed);
end $fn$;

/* The Admin changes a partner's status (m4b, unchanged), and a paused or closed partner's queued pushes fail over at
   once (PART 6.4: paused partners receive no new leads). */
create or replace function b2b.partner_set_status(p_id bigint, p_status text, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_old text;
  v_failed int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status not in ('onboarding', 'active', 'paused', 'closed') then raise exception 'unknown status' using errcode = '22023'; end if;
  if p_status in ('paused', 'closed') and coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select status into v_old from b2b.partners where id = p_id for update;
  if v_old is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  if v_old = p_status then return jsonb_build_object('status', p_status); end if;
  if v_old = 'closed' then raise exception 'a closed partner cannot be reopened here' using errcode = '22023'; end if;

  update b2b.partners
     set status = p_status,
         paused_reason = case when p_status = 'paused' then trim(p_reason) else null end,
         auto_paused_at = null,
         updated_at = now(), updated_by = coalesce(auth.uid()::text, 'system')
   where id = p_id;
  if p_status = 'closed' and b2b.is_live('partner:' || p_id) then
    perform b2b.set_live_switch('partner:' || p_id, false, 'partner closed: ' || trim(p_reason));
  end if;
  perform b2b.log_event('partner.status_changed', null, null, p_id, jsonb_build_object('from', v_old, 'to', p_status, 'reason', nullif(trim(p_reason), '')));
  if p_status in ('paused', 'closed') then
    v_failed := b2b.partner_paused_failover(p_id, p_status || ': ' || trim(p_reason));
    return jsonb_build_object('status', p_status, 'failed_over', v_failed);
  end if;
  return jsonb_build_object('status', p_status);
end $fn$;

/* m23a, unchanged, plus partner_adapter_state.last_poll_ok_at on every successful poll (the sync-failure guard reads
   it). */
create or replace function b2b.partner_sync_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  h record;
  j jsonb;
  p b2b.partners;
  spec jsonb;
  e jsonb;
  recs jsonb;
  rec jsonb;
  res text;
  v_max timestamptz;
  v_counts jsonb;
  n_polls int := 0;
  n_issued int := 0;
begin
  perform set_config('b2b.actor', 'system', true);
  perform b2b.adapter_token_collect();

  -- answers to polls and schema fetches
  for r in select s.* from b2b.partner_adapter_state s where s.poll_request_id is not null or s.schema_request_id is not null loop
    select * into p from b2b.partners where id = r.partner_id;
    spec := b2b.adapter_spec(p.adapter_type);
    e := b2b.adapter_env(p, r.env);
    if r.poll_request_id is not null then
      select x.status_code, x.content, x.error_msg into h from net._http_response x where x.id = r.poll_request_id;
      if found then
        begin j := h.content::jsonb; exception when others then j := null; end;
        if h.status_code between 200 and 299 or h.status_code = 304 then
          recs := case when h.status_code = 304 or j is null then '[]' else b2b.adapter_poll_parse(p.adapter_type, j,
                    coalesce(nullif(e ->> 'status_field', ''), spec ->> 'status_field'), coalesce(nullif(e ->> 'reference_field', ''), spec ->> 'reference_field')) end;
          v_counts := '{}'; v_max := null;
          for rec in select x from jsonb_array_elements(recs) x loop
            begin res := b2b.adapter_poll_apply(p, r.env, rec); exception when others then res := 'error'; end;
            v_counts := v_counts || jsonb_build_object(res, coalesce((v_counts ->> res)::int, 0) + 1);
            v_max := greatest(v_max, b2b.try_timestamptz(rec ->> 'modified'));
          end loop;
          update b2b.partner_adapter_state
             set poll_request_id = null, last_poll_at = now(), last_poll_ok_at = now(), last_poll_error = null,
                 last_poll_result = v_counts || jsonb_build_object('records', jsonb_array_length(recs)),
                 poll_since = coalesce(v_max, r.poll_requested_at - interval '2 minutes', poll_since), updated_at = now()
           where partner_id = r.partner_id and env = r.env;
          n_polls := n_polls + 1;
        else
          if h.status_code = 401 then update b2b.partner_adapter_state set token_expires_at = null where partner_id = r.partner_id and env = r.env; end if;
          update b2b.partner_adapter_state set poll_request_id = null, last_poll_at = now(), updated_at = now(),
                 last_poll_error = left(coalesce(h.error_msg, 'HTTP ' || h.status_code || ': ' || left(h.content, 200)), 300)
           where partner_id = r.partner_id and env = r.env;
        end if;
      elsif r.poll_requested_at < now() - interval '5 minutes' then
        update b2b.partner_adapter_state set poll_request_id = null, last_poll_error = 'no answer from the CRM' where partner_id = r.partner_id and env = r.env;
      end if;
    end if;
    if r.schema_request_id is not null then
      select x.status_code, x.content, x.error_msg into h from net._http_response x where x.id = r.schema_request_id;
      if found then
        begin j := h.content::jsonb; exception when others then j := null; end;
        if h.status_code between 200 and 299 and j is not null then
          begin
            perform b2b.mapping_snapshot_store(p.id, 'api', b2b.adapter_schema_parse(p.adapter_type, j, coalesce(nullif(e ->> 'status_field', ''), spec ->> 'status_field')));
            update b2b.partner_adapter_state set schema_request_id = null, last_schema_at = now(), last_schema_error = null, updated_at = now()
             where partner_id = r.partner_id and env = r.env;
          exception when others then
            update b2b.partner_adapter_state set schema_request_id = null, last_schema_error = left(sqlerrm, 300), updated_at = now()
             where partner_id = r.partner_id and env = r.env;
          end;
        else
          if h.status_code = 401 then update b2b.partner_adapter_state set token_expires_at = null where partner_id = r.partner_id and env = r.env; end if;
          update b2b.partner_adapter_state set schema_request_id = null, updated_at = now(),
                 last_schema_error = left(coalesce(h.error_msg, 'HTTP ' || h.status_code || ': ' || left(h.content, 200)), 300)
           where partner_id = r.partner_id and env = r.env;
        end if;
      elsif r.schema_requested_at < now() - interval '5 minutes' then
        update b2b.partner_adapter_state set schema_request_id = null, last_schema_error = 'no answer from the CRM' where partner_id = r.partner_id and env = r.env;
      end if;
    end if;
  end loop;

  -- due polls: live partners that are switched on, and sandboxes with recent test leads; daily schema check of live partners
  for r in
    select pt.id, env.env, s.last_poll_at, s.poll_request_id, s.last_schema_at, s.schema_request_id, s.token_request_id
      from b2b.partners pt
      cross join (values ('live'), ('sandbox')) env(env)
      left join b2b.partner_adapter_state s on s.partner_id = pt.id and s.env = env.env
     where coalesce((b2b.adapter_spec(pt.adapter_type) ->> 'poll')::boolean, false)
       and nullif(pt.outbound_auth -> env.env ->> 'secret_id', '') is not null
       and coalesce((pt.outbound_auth -> env.env ->> 'poll')::boolean, true)
       and case when env.env = 'live' then b2b.is_live('partner:' || pt.id)
                else exists (select 1 from b2b.allocations a where a.partner_id = pt.id and a.is_test and a.created_at > now() - interval '7 days') end
  loop
    select * into p from b2b.partners where id = r.id;
    if r.poll_request_id is null and r.token_request_id is null
       and coalesce(r.last_poll_at, '-infinity') < now() - make_interval(mins => greatest(coalesce((p.outbound_auth -> r.env ->> 'poll_minutes')::int, case when r.env = 'live' then b2b.sync_minutes() else 2 end), 2)) then
      begin
        perform b2b.adapter_issue(p, r.env, 'poll');
        n_issued := n_issued + 1;
      exception when others then
        update b2b.partner_adapter_state set last_poll_at = now(), last_poll_error = left(sqlerrm, 300) where partner_id = p.id and env = r.env;
      end;
    end if;
    if r.env = 'live' and r.schema_request_id is null and coalesce((b2b.adapter_spec(p.adapter_type) ->> 'schema')::boolean, false)
       and coalesce(r.last_schema_at, '-infinity') < now() - interval '1 day' then
      begin
        perform b2b.adapter_issue(p, 'live', 'schema');
      exception when others then
        update b2b.partner_adapter_state set last_schema_at = now(), last_schema_error = left(sqlerrm, 300) where partner_id = p.id and env = 'live';
      end;
    end if;
  end loop;
  return jsonb_build_object('polls_read', n_polls, 'polls_sent', n_issued);
end $fn$;

-- ---------- data ----------
/* The last successful poll is known where the latest poll succeeded (a success clears last_poll_error and stamps
   last_poll_at); rows whose latest poll failed stay null, and the guard times them from the Addendum 3 install. */
update b2b.partner_adapter_state set last_poll_ok_at = last_poll_at
 where last_poll_ok_at is null and last_poll_error is null and last_poll_at is not null;

-- ---------- cron ----------
/* The catch-up job, created once. During the promotion window the b2b-* jobs are paused: when b2b-stats-refresh is
   paused the new job starts paused too, and is resumed with the others. */
do $cron$
declare
  v_active boolean;
begin
  if not exists (select 1 from cron.job where jobname = 'b2b-stats-ai-catchup') then
    perform cron.schedule('b2b-stats-ai-catchup', '* * * * *', 'select b2b.stats_refresh_if_stale()');
    select j.active into v_active from cron.job j where j.jobname = 'b2b-stats-refresh' order by j.jobid limit 1;
    if v_active is false then
      perform cron.alter_job(j.jobid, active := false) from cron.job j where j.jobname = 'b2b-stats-ai-catchup';
    end if;
  end if;
end $cron$;

-- ---------- grants ----------
revoke execute on function b2b.stats_num(jsonb), b2b.effort_from_detail(jsonb, jsonb), b2b.sla_factor_of(numeric, int, jsonb),
                           b2b.received_counts(timestamptz, int), b2b.followup_checks(timestamptz),
                           b2b.effort_detail_rows(timestamptz, int, jsonb), b2b.sla_adherence_rows(timestamptz, jsonb),
                           b2b.stats_refresh_if_stale(), b2b.partner_paused_failover(bigint, text),
                           b2b.engine_params(boolean), b2b.segment_rollup(text), b2b.allocation_outcomes(), b2b.keyed_outcomes(jsonb, jsonb),
                           b2b.stats_refresh(), b2b.guard_tick(), b2b.partner_sync_tick()
  from public, anon, authenticated;
grant execute on function b2b.stats_num(jsonb), b2b.effort_from_detail(jsonb, jsonb), b2b.sla_factor_of(numeric, int, jsonb),
                          b2b.received_counts(timestamptz, int), b2b.followup_checks(timestamptz),
                          b2b.effort_detail_rows(timestamptz, int, jsonb), b2b.sla_adherence_rows(timestamptz, jsonb),
                          b2b.stats_refresh_if_stale(), b2b.partner_paused_failover(bigint, text),
                          b2b.engine_params(boolean), b2b.segment_rollup(text), b2b.allocation_outcomes(), b2b.keyed_outcomes(jsonb, jsonb),
                          b2b.stats_refresh(), b2b.guard_tick(), b2b.partner_sync_tick()
  to service_role;
revoke execute on function b2b.partner_set_status(bigint, text, text) from public, anon;
grant execute on function b2b.partner_set_status(bigint, text, text) to authenticated, service_role;
