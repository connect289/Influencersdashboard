-- M24c: performance routing, part 3: what the Admin sees and sets (spec B7.2 "the current mode per segment is shown in
-- the UI, and the Admin can pin a segment", B7.4 guardrails, B14.3 Routing screen).
--   routing_segments()                  every segment with its mode (auto or pinned), maturity progress, policy and recent flow
--   routing_segment(segment)            per partner: P̂ with a 90% interval, alpha/beta, refund rate, SLA, factors, weight,
--                                       CPE and NCPL; flow by mode in 30 days; holdout share; the last decisions
--   segment_policy_save(segment, p, reason)   pin (mode, until), exploration share, share cap, kill switch for one segment
--   partner_weight_save(partner, weight, until, reason)   temporary ±10% weight, at most 14 days
--   engine_policy_save(p, reason)       holdout share, Monte Carlo draws, leading-indicator weight
--   engine_settings_save(p, reason)     as in M6, plus (when given) maturity, half-life, prior strength, default P(enrol),
--                                       matured-lead threshold, speed and reliability factors, kill switch and fixed split
--   decision_replay(decision id)        re-runs a performance decision from its stored candidates and seed
--   stats_refresh_now()                 refresh the statistics now (they refresh hourly)
-- All writes go through set_setting (versioned with who, when and why). Entries carry source 'admin'.

/* A Beta(alpha, beta) interval by the normal approximation, clipped to [0, 1]. */
create or replace function b2b.beta_interval(p_alpha numeric, p_beta numeric, p_z numeric default 1.645)
returns jsonb language sql immutable set search_path = '' as $fn$
  select jsonb_build_object('low', round(greatest(m - p_z * sd, 0), 5), 'high', round(least(m + p_z * sd, 1), 5))
    from (select p_alpha / (p_alpha + p_beta) m,
                 sqrt(p_alpha * p_beta / ((p_alpha + p_beta) ^ 2 * (p_alpha + p_beta + 1))) sd) x;
$fn$;

/* The effective mode of a segment for non-holdout leads: an unexpired pin, else the automatic mode. */
create or replace function b2b.segment_mode(p_segment text)
returns jsonb language sql stable set search_path = '' as $fn$
  with pol as (select coalesce((select value from b2b.settings where key = 'engine_policy'), '{}') v),
       e as (select coalesce((select value from b2b.settings where key = 'engine'), '{}') v),
       pin as (select pol.v -> 'segments' -> p_segment -> 'pin' p from pol),
       auto as (select coalesce((select s.auto_mode from b2b.segment_stats s where s.variant = 'base' and s.segment = p_segment), 'commission_first') m)
  select jsonb_build_object(
    'auto', auto.m,
    'pin', case when pin.p is not null and ((pin.p ->> 'until') is null or (pin.p ->> 'until')::timestamptz > now()) then pin.p end,
    'killed', coalesce((e.v ->> 'kill_switch')::boolean, false) or coalesce(pol.v -> 'kill_segments', '[]') ? p_segment,
    'mode', case when coalesce((e.v ->> 'kill_switch')::boolean, false) or coalesce(pol.v -> 'kill_segments', '[]') ? p_segment then 'kill_switch'
                 when pin.p is not null and ((pin.p ->> 'until') is null or (pin.p ->> 'until')::timestamptz > now()) then pin.p ->> 'mode'
                 else auto.m end)
  from pol, e, pin, auto;
$fn$;

create or replace function b2b.routing_segments()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  pol jsonb := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
  prm jsonb := b2b.engine_params(true);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'params', prm,
    'policy', pol,
    'policy_version', (select version from b2b.settings where key = 'engine_policy'),
    'stats_at', (select max(refreshed_at) from b2b.segment_stats where variant = 'base'),
    'stage_rates', coalesce((select jsonb_agg(jsonb_build_object('stage', stage, 'n', n, 'enrolled', enrolled, 'rate', rate)
                                              order by array_position(array['applied', 'interested', 'contacted', 'accepted', 'none'], stage))
                               from b2b.stage_rates), '[]'),
    'segments', coalesce((
      select jsonb_agg(jsonb_build_object(
               'segment', k.segment, 'rollup', k.segment = b2b.segment_rollup(k.segment),
               'leads', coalesce(s.n_leads, 0), 'matured', coalesce(s.n_matured, 0), 'prior', coalesce(s.prior, (prm ->> 'default_p_enroll')::numeric),
               'partners', coalesce(s.partners, 0), 'partners_matured', coalesce(s.partners_matured, 0),
               'best_partner_matured', coalesce((select max(x.n_matured) from b2b.partner_segment_stats x where x.variant = 'base' and x.segment = k.segment), 0),
               'mode', b2b.segment_mode(k.segment),
               'exploration_share', pol -> 'segments' -> k.segment -> 'exploration_share',
               'share_cap', pol -> 'segments' -> k.segment -> 'share_cap',
               'leads_30d', (select count(*) from b2b.allocations a where a.segment = k.segment and a.destination_type = 'partner' and not a.is_test
                                and a.created_at > now() - interval '30 days'),
               'last_routed_at', (select max(a.created_at) from b2b.allocations a where a.segment = k.segment and a.destination_type = 'partner' and not a.is_test))
             order by coalesce(s.n_leads, 0) desc, k.segment)
        from (select segment from b2b.segment_stats where variant = 'base' and n_leads > 0
              union select a.segment from b2b.allocations a where a.segment is not null and a.destination_type = 'partner' and not a.is_test
                                                              and a.created_at > now() - interval '90 days'
              union select jsonb_object_keys(coalesce(pol -> 'segments', '{}'))
              union select jsonb_array_elements_text(coalesce(pol -> 'kill_segments', '[]'))) k
        left join b2b.segment_stats s on s.variant = 'base' and s.segment = k.segment), '[]'));
end $fn$;

create or replace function b2b.routing_segment(p_segment text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  pol jsonb := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
  prm jsonb := b2b.engine_params(true);
  v_ck text := split_part(p_segment, '|', 1);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_segment), '') = '' then raise exception 'choose a segment' using errcode = '22023'; end if;
  return jsonb_build_object(
    'segment', p_segment, 'rollup', b2b.segment_rollup(p_segment),
    'mode', b2b.segment_mode(p_segment),
    'policy', coalesce(pol -> 'segments' -> p_segment, '{}'),
    'params', prm,
    'stats', (select to_jsonb(s) from b2b.segment_stats s where s.variant = 'base' and s.segment = p_segment),
    'partners', coalesce((
      select jsonb_agg(jsonb_build_object(
               'partner_id', p.id, 'name', coalesce(p.display_name, p.name), 'status', p.status,
               'exact', case when ex.partner_id is not null then jsonb_build_object('leads', ex.n_leads, 'matured', ex.n_matured, 'enrolled', ex.enrolled,
                               'w_matured', ex.w_matured, 'w_enrolled', ex.w_enrolled, 'young', ex.n_young, 'young_expected', ex.w_young_expected,
                               'p_hat', ex.p_hat, 'alpha', ex.alpha, 'beta', ex.beta, 'interval', b2b.beta_interval(ex.alpha, ex.beta)) end,
               'rollup', case when ru.partner_id is not null then jsonb_build_object('leads', ru.n_leads, 'matured', ru.n_matured, 'enrolled', ru.enrolled,
                               'p_hat', ru.p_hat, 'alpha', ru.alpha, 'beta', ru.beta, 'interval', b2b.beta_interval(ru.alpha, ru.beta)) end,
               'uses', case when coalesce(ex.n_leads, 0) >= 30 or ru.partner_id is null then 'segment' else 'course' end,
               'refund_rate', coalesce(ex.refund_rate, ru.refund_rate, 0), 'sla_compliance', coalesce(ex.sla_compliance, ru.sla_compliance),
               'first_contact_hours', coalesce(ex.first_contact_hours, ru.first_contact_hours),
               'speed', coalesce(ex.speed, ru.speed, 1), 'reliability', coalesce(ex.reliability, ru.reliability, 1),
               'weight', pol -> 'partner_weights' -> (p.id::text),
               'cpe', o.cpe, 'offers', o.n,
               'ncpl', round(coalesce(o.cpe, 0) * case when coalesce(ex.n_leads, 0) >= 30 or ru.partner_id is null then coalesce(ex.p_hat, s.prior) else ru.p_hat end
                             * (1 - coalesce(ex.refund_rate, ru.refund_rate, 0)), 2),
               'leads_30d', (select count(*) from b2b.allocations a where a.partner_id = p.id and a.segment = p_segment and not a.is_test
                               and a.created_at > now() - interval '30 days' and a.status <> 'failed'))
             order by o.cpe desc nulls last, p.id)
        from b2b.partners p
        left join b2b.partner_segment_stats ex on ex.variant = 'base' and ex.partner_id = p.id and ex.segment = p_segment
        left join b2b.partner_segment_stats ru on ru.variant = 'base' and ru.partner_id = p.id and ru.segment = b2b.segment_rollup(p_segment)
                                              and b2b.segment_rollup(p_segment) <> p_segment
        left join b2b.segment_stats s on s.variant = 'base' and s.segment = p_segment
        left join lateral (select count(*) n, round(percentile_cont(0.5) within group (order by b2b.cpe_net(x.partner_id, x.programme_id, x.fees))::numeric, 2) cpe
                             from b2b.partner_programmes x join public.catalog_programs c on c.id = x.programme_id and c.active
                            where x.partner_id = p.id and x.valid_to is null and x.active and c.course_key = v_ck
                              and (split_part(p_segment, '|', 2) in ('*', '') or c.level = split_part(p_segment, '|', 2))
                              and (split_part(p_segment, '|', 3) in ('*', '') or c.mode = split_part(p_segment, '|', 3))) o on true
       where p.status <> 'closed' and (ex.partner_id is not null or ru.partner_id is not null or o.n > 0)), '[]'),
    'flow_30d', coalesce((select jsonb_agg(jsonb_build_object('mode', x.mode, 'holdout', x.holdout, 'n', x.n) order by x.mode, x.holdout)
                            from (select d.mode, d.holdout, count(*) n from b2b.engine_decisions d
                                   where d.segment = p_segment and d.destination_type = 'partner' and not d.is_test and d.created_at > now() - interval '30 days'
                                   group by 1, 2) x), '[]'),
    'decisions', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'lead_id', d.lead_id, 'at', d.created_at, 'mode', d.mode, 'scoring_mode', d.scoring_mode,
                                                               'holdout', d.holdout, 'partner_id', d.winner_partner_id,
                                                               'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = d.winner_partner_id),
                                                               'selection_probability', d.selection_probability, 'is_test', d.is_test) order by d.id desc)
                             from (select * from b2b.engine_decisions d where d.segment = p_segment and d.destination_type = 'partner'
                                    order by d.id desc limit 15) d), '[]'));
end $fn$;

/* One segment's policy. p: {pin: {mode: 'commission_first'|'performance', until?: date}|null, exploration_share: 0..0.5|null,
   share_cap: 0.5..1|null, killed: boolean}. Keys left out are kept. */
create or replace function b2b.segment_policy_save(p_segment text, p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pol jsonb := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
  seg jsonb;
  v_by text := coalesce(auth.uid()::text, 'admin');
  v_until timestamptz;
  v_kill jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_segment), '') = '' or p_segment !~ '^[^|]+\|[^|]+\|[^|]+$' or length(p_segment) > 120 then
    raise exception 'unknown segment' using errcode = '22023';
  end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  seg := coalesce(pol -> 'segments' -> p_segment, '{}');
  if p ? 'pin' then
    if jsonb_typeof(p -> 'pin') = 'null' then
      seg := seg - 'pin';
    else
      if p -> 'pin' ->> 'mode' not in ('commission_first', 'performance') then raise exception 'pin the segment to commission first or performance' using errcode = '22023'; end if;
      v_until := nullif(p -> 'pin' ->> 'until', '')::timestamptz;
      if v_until is not null and (v_until <= now() or v_until > now() + interval '366 days') then
        raise exception 'a pin ends within a year from now' using errcode = '22023';
      end if;
      seg := seg || jsonb_build_object('pin', jsonb_strip_nulls(jsonb_build_object('mode', p -> 'pin' ->> 'mode', 'until', v_until, 'source', 'admin',
                                                                                    'by', v_by, 'at', now(), 'reason', left(trim(p_reason), 300))));
    end if;
  end if;
  if p ? 'exploration_share' then
    if jsonb_typeof(p -> 'exploration_share') = 'null' then seg := seg - 'exploration_share';
    elsif not ((p ->> 'exploration_share')::numeric between 0 and 0.5) then raise exception 'exploration share must be between 0 and 50%%' using errcode = '22023';
    else seg := seg || jsonb_build_object('exploration_share', jsonb_build_object('value', round((p ->> 'exploration_share')::numeric, 3), 'source', 'admin', 'by', v_by, 'at', now()));
    end if;
  end if;
  if p ? 'share_cap' then
    if jsonb_typeof(p -> 'share_cap') = 'null' then seg := seg - 'share_cap';
    elsif not ((p ->> 'share_cap')::numeric between 0.5 and 1) then raise exception 'a share cap is between 50%% and 100%%' using errcode = '22023';
    else seg := seg || jsonb_build_object('share_cap', jsonb_build_object('value', round((p ->> 'share_cap')::numeric, 3), 'source', 'admin', 'by', v_by, 'at', now()));
    end if;
  end if;
  v_kill := coalesce(pol -> 'kill_segments', '[]');
  if p ? 'killed' then
    if jsonb_typeof(p -> 'killed') <> 'boolean' then raise exception 'kill switch must be on or off' using errcode = '22023'; end if;
    v_kill := (select coalesce(jsonb_agg(distinct x), '[]') from (select jsonb_array_elements_text(v_kill) x
                                                                  union select p_segment where (p ->> 'killed')::boolean) z
                where x <> p_segment or (p ->> 'killed')::boolean);
  end if;
  pol := jsonb_set(pol, '{segments}', case when seg = '{}' then coalesce(pol -> 'segments', '{}') - p_segment
                                           else coalesce(pol -> 'segments', '{}') || jsonb_build_object(p_segment, seg) end)
         || jsonb_build_object('kill_segments', v_kill);
  perform b2b.set_setting('engine_policy', pol, 'segment ' || p_segment || ': ' || trim(p_reason));
  return b2b.segment_mode(p_segment) || jsonb_build_object('policy', seg);
end $fn$;

/* A temporary partner weight (0.9 to 1.1, at most 14 days) on its NCPL in performance mode; null removes it. */
create or replace function b2b.partner_weight_save(p_partner_id bigint, p_weight numeric, p_until timestamptz, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pol jsonb := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = p_partner_id) then raise exception 'partner not found' using errcode = 'P0002'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  if p_weight is null then
    pol := jsonb_set(pol, '{partner_weights}', coalesce(pol -> 'partner_weights', '{}') - p_partner_id::text);
  else
    if not (p_weight between 0.9 and 1.1) then raise exception 'a partner weight is between 0.90 and 1.10' using errcode = '22023'; end if;
    if p_until is null or p_until <= now() or p_until > now() + interval '14 days 1 hour' then
      raise exception 'a partner weight ends within 14 days' using errcode = '22023';
    end if;
    pol := jsonb_set(pol, '{partner_weights}', coalesce(pol -> 'partner_weights', '{}')
                       || jsonb_build_object(p_partner_id::text, jsonb_build_object('weight', round(p_weight, 3), 'until', p_until, 'source', 'admin',
                                                                                     'by', coalesce(auth.uid()::text, 'admin'), 'reason', left(trim(p_reason), 300))));
  end if;
  perform b2b.set_setting('engine_policy', pol, 'partner ' || p_partner_id || ' weight: ' || trim(p_reason));
  return coalesce(pol -> 'partner_weights' -> p_partner_id::text, 'null'::jsonb);
end $fn$;

create or replace function b2b.engine_policy_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pol jsonb := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'holdout_share' and not ((p ->> 'holdout_share')::numeric between 0 and 0.5) then raise exception 'the holdout is 0 to 50%% of leads' using errcode = '22023'; end if;
  if p ? 'mc_draws' and not ((p ->> 'mc_draws')::int between 50 and 1000) then raise exception 'draws are 50 to 1000' using errcode = '22023'; end if;
  if p ? 'leading_weight' and not ((p ->> 'leading_weight')::numeric between 0 and 1) then raise exception 'the leading-indicator weight is 0 to 1' using errcode = '22023'; end if;
  if p ? 'leading_min_days' and not ((p ->> 'leading_min_days')::int between 0 and 30) then raise exception 'young leads count after 0 to 30 days' using errcode = '22023'; end if;
  pol := pol || jsonb_strip_nulls(jsonb_build_object(
           'holdout_share', round((p ->> 'holdout_share')::numeric, 3), 'mc_draws', (p ->> 'mc_draws')::int,
           'leading_weight', round((p ->> 'leading_weight')::numeric, 3), 'leading_min_days', (p ->> 'leading_min_days')::int));
  return b2b.set_setting('engine_policy', pol, p_reason);
end $fn$;

/* As in M6c, plus the performance settings when given (older callers keep working). */
create or replace function b2b.engine_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_split jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not ((p ->> 'exploration_share')::numeric between 0 and 0.5) then raise exception 'exploration share must be between 0 and 50%%' using errcode = '22023'; end if;
  if p ->> 'cpe_aggregate' not in ('median', 'mean', 'max') then raise exception 'unknown commission aggregate' using errcode = '22023'; end if;
  if not ((p ->> 'min_learning_leads')::int between 1 and 1000) then raise exception 'learning leads must be 1 to 1000' using errcode = '22023'; end if;
  if not ((p ->> 'attempt_limit')::int between 1 and 5) or not ((p ->> 'partner_limit')::int between 1 and 5) then
    raise exception 'attempt and partner limits must be 1 to 5' using errcode = '22023';
  end if;
  if not ((p ->> 'witty_idle_minutes')::int between 5 and 1440) then raise exception 'Witty idle time must be 5 to 1440 minutes' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'require_partner_consent') <> 'boolean' then raise exception 'consent setting must be on or off' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'trusted_sources') <> 'array' then raise exception 'trusted sources must be a list' using errcode = '22023'; end if;
  v := v || jsonb_build_object(
         'exploration_share', round((p ->> 'exploration_share')::numeric, 3), 'cpe_aggregate', p ->> 'cpe_aggregate',
         'min_learning_leads', (p ->> 'min_learning_leads')::int, 'attempt_limit', (p ->> 'attempt_limit')::int,
         'partner_limit', (p ->> 'partner_limit')::int, 'witty_idle_minutes', (p ->> 'witty_idle_minutes')::int,
         'require_partner_consent', (p ->> 'require_partner_consent')::boolean,
         'trusted_sources', (select coalesce(jsonb_agg(distinct left(trim(x), 60)), '[]') from jsonb_array_elements_text(p -> 'trusted_sources') x where trim(x) <> ''));

  -- performance settings (B7.2, B21)
  if p ? 'maturity_days' then
    if not ((p ->> 'maturity_days')::int between 14 and 180) then raise exception 'maturity is 14 to 180 days' using errcode = '22023'; end if;
    v := v || jsonb_build_object('maturity_days', (p ->> 'maturity_days')::int);
  end if;
  if p ? 'half_life_days' then
    if not ((p ->> 'half_life_days')::int between 7 and 120) then raise exception 'the recency half-life is 7 to 120 days' using errcode = '22023'; end if;
    v := v || jsonb_build_object('half_life_days', (p ->> 'half_life_days')::int);
  end if;
  if p ? 'prior_weight' then
    if not ((p ->> 'prior_weight')::numeric between 1 and 100) then raise exception 'prior strength is 1 to 100 leads' using errcode = '22023'; end if;
    v := v || jsonb_build_object('prior_weight', round((p ->> 'prior_weight')::numeric, 1));
  end if;
  if p ? 'default_p_enroll' then
    if not ((p ->> 'default_p_enroll')::numeric between 0.001 and 0.5) then raise exception 'the default enrolment rate is 0.1%% to 50%%' using errcode = '22023'; end if;
    v := v || jsonb_build_object('default_p_enroll', round((p ->> 'default_p_enroll')::numeric, 4));
  end if;
  if p ? 'min_matured_leads' then
    if not ((p ->> 'min_matured_leads')::int between 5 and 500) then raise exception 'matured leads for performance mode are 5 to 500' using errcode = '22023'; end if;
    v := v || jsonb_build_object('min_matured_leads', (p ->> 'min_matured_leads')::int);
  end if;
  if p ? 'speed_factor' then
    if jsonb_typeof(p -> 'speed_factor') <> 'boolean' then raise exception 'the speed factor is on or off' using errcode = '22023'; end if;
    v := jsonb_set(v, '{speed_factor}', coalesce(v -> 'speed_factor', '{"bounds":[0.85,1.15]}') || jsonb_build_object('enabled', (p ->> 'speed_factor')::boolean));
  end if;
  if p ? 'reliability_factor' then
    if jsonb_typeof(p -> 'reliability_factor') <> 'boolean' then raise exception 'the reliability factor is on or off' using errcode = '22023'; end if;
    v := jsonb_set(v, '{reliability_factor}', coalesce(v -> 'reliability_factor', '{"bounds":[0.7,1.0]}') || jsonb_build_object('enabled', (p ->> 'reliability_factor')::boolean));
  end if;
  if p ? 'fixed_split' then
    if jsonb_typeof(p -> 'fixed_split') <> 'object' then raise exception 'the fixed split lists partners and their shares' using errcode = '22023'; end if;
    select coalesce(jsonb_object_agg(k, round(x::numeric, 2)), '{}') into v_split
      from jsonb_each_text(p -> 'fixed_split') s(k, x)
     where k ~ '^[0-9]+$' and x ~ '^[0-9]+(\.[0-9]+)?$' and x::numeric > 0 and exists (select 1 from b2b.partners where id = k::bigint and status <> 'closed');
    if (select count(*) from jsonb_object_keys(p -> 'fixed_split')) <> (select count(*) from jsonb_object_keys(v_split)) then
      raise exception 'the fixed split names an unknown or closed partner, or a share that is not a positive number' using errcode = '22023';
    end if;
    v := v || jsonb_build_object('fixed_split', v_split);
  end if;
  if p ? 'kill_switch' then
    if jsonb_typeof(p -> 'kill_switch') <> 'boolean' then raise exception 'the kill switch is on or off' using errcode = '22023'; end if;
    if (p ->> 'kill_switch')::boolean and coalesce(v -> 'fixed_split', '{}') = '{}' then
      raise exception 'set the fixed split between partners before turning the kill switch on' using errcode = '22023';
    end if;
    v := v || jsonb_build_object('kill_switch', (p ->> 'kill_switch')::boolean);
  end if;
  return b2b.set_setting('engine', v, p_reason);
end $fn$;

/* Re-runs a decision's choice from what was logged: performance decisions through thompson_pick with the stored seed
   and candidates; commission-first decisions through the seeded exploration draw. Shows whether it reproduces. */
create or replace function b2b.decision_replay(p_decision_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  d b2b.engine_decisions;
  v_k int;
  v_x jsonb;
  v_cands jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from b2b.engine_decisions where id = p_decision_id;
  if d.id is null then raise exception 'decision not found' using errcode = 'P0002'; end if;
  if d.seed is null or d.scoring_mode is null then
    return jsonb_build_object('replayable', false, 'why', 'decided before seeded scoring (M24) or not a scored decision');
  end if;
  select coalesce(jsonb_agg(c), '[]') into v_cands from jsonb_array_elements(d.candidates) c where (c ->> 'eligible')::boolean;
  if d.scoring_mode = 'performance' and d.mode = 'performance' then
    v_k := coalesce((select (value ->> 'mc_draws')::int from b2b.settings_versions where key = 'engine_policy' and version = d.policy_version), 200);
    v_x := b2b.thompson_pick(v_cands, d.seed::text, v_k);
    return jsonb_build_object('replayable', true, 'scoring_mode', d.scoring_mode, 'winner', (v_x ->> 'winner')::bigint,
                              'logged_winner', d.winner_partner_id, 'reproduced', (v_x ->> 'winner')::bigint = d.winner_partner_id,
                              'selection_probability', (v_x ->> 'selection_probability')::numeric, 'logged_probability', d.selection_probability,
                              'wins', v_x -> 'wins', 'draws', v_x -> 'draws');
  end if;
  return jsonb_build_object('replayable', true, 'scoring_mode', d.scoring_mode, 'logged_winner', d.winner_partner_id,
                            'holdout_draw', round(b2b.u01(d.seed::text, 'holdout')::numeric, 6), 'holdout', d.holdout,
                            'exploration_draw', round(b2b.u01(d.seed::text, 'explore')::numeric, 6), 'mode', d.mode,
                            'selection_probability', d.selection_probability);
end $fn$;

create or replace function b2b.stats_refresh_now()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.stats_refresh();
end $fn$;

revoke execute on function b2b.beta_interval(numeric, numeric, numeric), b2b.segment_mode(text) from public, anon, authenticated;
grant execute on function b2b.beta_interval(numeric, numeric, numeric), b2b.segment_mode(text) to service_role;
revoke execute on function b2b.routing_segments(), b2b.routing_segment(text), b2b.segment_policy_save(text, jsonb, text),
                           b2b.partner_weight_save(bigint, numeric, timestamptz, text), b2b.engine_policy_save(jsonb, text),
                           b2b.decision_replay(bigint), b2b.stats_refresh_now() from public, anon;
grant execute on function b2b.routing_segments(), b2b.routing_segment(text), b2b.segment_policy_save(text, jsonb, text),
                          b2b.partner_weight_save(bigint, numeric, timestamptz, text), b2b.engine_policy_save(jsonb, text),
                          b2b.decision_replay(bigint), b2b.stats_refresh_now() to authenticated, service_role;
