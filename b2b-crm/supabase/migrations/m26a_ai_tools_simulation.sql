-- M26a: Claude as the allocation optimiser (spec B7.8.2), part 1: the log, the inbox, settings, and the read-only tools.
--   ai_runs              every run: trigger, kind, model, prompt version, input hash, tool calls, output, tokens, cost, linked
--                        recommendations, the validator's verdict
--   ai_recommendations   the Advisory inbox: rationale, evidence, the change (bounded lever), simulated impact with a
--                        confidence interval, risk, expiry; approve, edit or reject; what was applied and its settings version
--   settings 'ai'        enabled (off until the API key is set), mode advisory (autopilot comes in Phase 4), models, daily
--                        budget, which schedules run, prices per million tokens (for the cost log), worker URL
--   ai_tool(name, input) the only data Claude sees: aggregated and pseudonymised (no names, phones or emails; leads appear
--                        as a short hash). segment_scorecards, partner_scorecards, conversion_cohorts, commission_rates,
--                        engine_settings, model_metrics, recent_decisions, alerts, uplift, run_simulation.
--   ai_simulate(change, days)  replays logged, matured partner decisions under a proposed change (inverse propensity):
--                        estimated net commission per lead now and with the change, the difference with a 95% interval,
--                        decisions used and effective sample size. It never touches a real lead.
--   ai_uplift(days)      realised net commission per matured lead, AI-steered against the holdout (B7.8.2: measured, not assumed).

insert into b2b.settings (key, value) values ('ai', jsonb_build_object(
  'enabled', false, 'mode', 'advisory',
  'models', jsonb_build_object('regular', 'claude-sonnet-5-5', 'deep', 'claude-opus-5-5', 'quick', 'claude-haiku-4-5-20251001'),
  'daily_budget_usd', 5, 'max_turns', 8, 'max_tokens', 4000,
  'schedules', jsonb_build_object('light', true, 'hourly', true, 'nightly', true, 'weekly', true),
  'prices_per_mtok', jsonb_build_object(
    'claude-sonnet-5-5', jsonb_build_object('in', 3, 'out', 15, 'cache_read', 0.3, 'cache_write', 3.75),
    'claude-opus-5-5', jsonb_build_object('in', 5, 'out', 25, 'cache_read', 0.5, 'cache_write', 6.25),
    'claude-haiku-4-5-20251001', jsonb_build_object('in', 1, 'out', 5, 'cache_read', 0.1, 'cache_write', 1.25)),
  'recommendation_days', 7, 'worker_url', null))
on conflict (key) do nothing;
insert into b2b.settings_versions (key, version, value, reason, actor_type)
select 'ai', 1, s.value, 'initial defaults (M26)', 'system' from b2b.settings s
 where s.key = 'ai' and not exists (select 1 from b2b.settings_versions v where v.key = 'ai');

alter table b2b.api_keys drop constraint if exists api_keys_scopes_check;
alter table b2b.api_keys add constraint api_keys_scopes_check
  check (cardinality(scopes) > 0 and scopes <@ array['intake', 'referrals', 'events', 'b2c', 'ai_worker']::text[]);

create table if not exists b2b.ai_runs (
  id              bigint generated always as identity primary key,
  trigger         text not null check (trigger in ('light', 'hourly', 'nightly', 'weekly', 'event', 'manual')),
  kind            text not null check (kind in ('light_check', 'optimise', 'deep_review', 'weekly_report')),
  model           text not null,
  prompt_version  text,
  status          text not null default 'queued' check (status in ('queued', 'running', 'done', 'failed', 'rejected', 'skipped')),
  context         jsonb not null default '{}',     -- why it was queued (event, anomalies)
  input_hash      text,
  tool_calls      jsonb not null default '[]',     -- [{id, name, input, output_hash, ms, at}]
  output          jsonb,
  narrative       text,
  validation      jsonb,
  tokens_in       int not null default 0,
  tokens_out      int not null default 0,
  cache_read      int not null default 0,
  cache_write     int not null default 0,
  cost_usd        numeric(10, 4) not null default 0,
  error           text,
  requested_by    text,
  created_at      timestamptz not null default now(),
  started_at      timestamptz,
  finished_at     timestamptz
);
create index if not exists ai_runs_created_idx on b2b.ai_runs (created_at desc);
create index if not exists ai_runs_queue_idx on b2b.ai_runs (status, created_at) where status in ('queued', 'running');

create table if not exists b2b.ai_tool_outputs (
  run_id      bigint not null references b2b.ai_runs (id),
  call_no     int not null,
  name        text not null,
  input       jsonb not null,
  output      jsonb not null,
  created_at  timestamptz not null default now(),
  primary key (run_id, call_no)
);

create table if not exists b2b.ai_recommendations (
  id              bigint generated always as identity primary key,
  run_id          bigint not null references b2b.ai_runs (id),
  kind            text not null check (kind in ('setting_change', 'rule_draft', 'pause_draft', 'insight')),
  status          text not null default 'open' check (status in ('open', 'applied', 'rejected', 'expired', 'rolled_back', 'superseded')),
  title           text not null,
  rationale       text not null,
  evidence        jsonb not null default '[]',
  change          jsonb,                        -- {lever, segment?, partner_id?, value, until?, from}
  simulation      jsonb,
  risk            text,
  expires_at      timestamptz not null,
  decided_by      text,
  decided_at      timestamptz,
  decision_note   text,
  applied         jsonb,                        -- {setting key, version, value applied, edited}
  check_due_at    timestamptz,
  check_result    jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists ai_recommendations_status_idx on b2b.ai_recommendations (status, created_at desc);

do $rls$
declare t text;
begin
  foreach t in array array['ai_runs', 'ai_tool_outputs', 'ai_recommendations'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

/* A lead as Claude may see it: a short, salted hash, never the ID, name or phone. */
create or replace function b2b.ai_pseudo(p_lead_id bigint)
returns text language sql stable set search_path = '' as $fn$
  select 'L-' || substr(md5('b2b-ai:' || coalesce((select value ->> 'salt' from b2b.settings where key = 'ai'), 'eduwit') || ':' || p_lead_id), 1, 8);
$fn$;

/* Net commission realised by a partner allocation: its CPE when an enrolment was reported and not refunded or cancelled. */
create or replace function b2b.allocation_reward(p_allocation_id bigint)
returns numeric language sql stable set search_path = '' as $fn$
  select case when e.status is not null and e.status not in ('refunded', 'cancelled') then coalesce(a.cpe_net_inr, 0) else 0 end
    from b2b.allocations a
    left join lateral (select x.status from public.enrollments x where x.allocation_id = a.id order by (x.status <> 'cancelled') desc, x.id desc limit 1) e on true
   where a.id = p_allocation_id;
$fn$;

-- ---------- simulation (inverse propensity on logged decisions) ----------
/* The probability that the policy changed by p_change picks each eligible candidate of a logged decision.
   change: {lever: exploration_share|segment_pin|partner_weight|share_cap|prior_weight|speed_factor|reliability_factor,
            segment?, partner_id?, value}. Levers that cannot be replayed from the log return null. */
create or replace function b2b.ai_policy_probs(d b2b.engine_decisions, p_change jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  pol jsonb := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
  v_seg_match boolean := p_change ->> 'segment' is null or p_change ->> 'segment' = d.segment;
  v_cands jsonb;
  v_mode text := d.scoring_mode;
  v_share numeric;
  v_min_learn int := coalesce((e ->> 'min_learning_leads')::int, 30);
  v_win jsonb; v_x jsonb; v_t jsonb;
  v_prior numeric;
  v_delta numeric;
  v_out jsonb := '{}';
begin
  select coalesce(jsonb_agg(c order by (c ->> 'partner_id')::bigint), '[]') into v_cands
    from jsonb_array_elements(d.candidates) c where coalesce((c ->> 'eligible')::boolean, true);
  if jsonb_array_length(v_cands) = 0 or d.scoring_mode is null or d.scoring_mode = 'kill_switch' then return null; end if;

  if v_seg_match then
    case p_change ->> 'lever'
      when 'segment_pin' then v_mode := p_change ->> 'value';
      when 'partner_weight' then
        v_cands := (select jsonb_agg(case when c ->> 'partner_id' = p_change ->> 'partner_id'
                                          then c || jsonb_build_object('weight', least(greatest((p_change ->> 'value')::numeric, 0.9), 1.1)) else c end)
                      from jsonb_array_elements(v_cands) c);
      when 'speed_factor' then
        if not (p_change ->> 'value')::boolean then v_cands := (select jsonb_agg(c || '{"speed":1}') from jsonb_array_elements(v_cands) c); end if;
      when 'reliability_factor' then
        if not (p_change ->> 'value')::boolean then v_cands := (select jsonb_agg(c || '{"reliability":1}') from jsonb_array_elements(v_cands) c); end if;
      when 'prior_weight' then
        -- alpha = prior x w + data: move the prior's share to the new strength
        v_prior := coalesce((select s.prior from b2b.segment_stats s where s.variant = 'base' and s.segment = d.segment), 0.05);
        v_delta := (p_change ->> 'value')::numeric - coalesce((b2b.engine_params(false) ->> 'prior_weight')::numeric, 20);
        v_cands := (select jsonb_agg(c || jsonb_build_object('alpha', greatest((c ->> 'alpha')::numeric + v_prior * v_delta, 0.01),
                                                             'beta', greatest((c ->> 'beta')::numeric + (1 - v_prior) * v_delta, 0.01)))
                      from jsonb_array_elements(v_cands) c where c ? 'alpha');
      when 'exploration_share', 'share_cap' then null;
      else return null;
    end case;
  end if;
  if v_cands is null then return null; end if;

  if v_mode = 'performance' and jsonb_array_length(v_cands) > 1 and (v_cands -> 0) ? 'alpha' then
    v_t := b2b.thompson_pick(v_cands, coalesce(d.seed, 0.5)::text, 99);
    return (select jsonb_object_agg(k, round(v::numeric / 100, 4)) from jsonb_each_text(v_t -> 'wins') x(k, v));
  end if;

  -- commission first, with the exploration lane (share as changed for this segment)
  v_share := case when p_change ->> 'lever' = 'exploration_share' and v_seg_match then (p_change ->> 'value')::numeric
                  else coalesce((pol -> 'segments' -> d.segment -> 'exploration_share' ->> 'value')::numeric, (e ->> 'exploration_share')::numeric, 0.2) end;
  select c into v_win from jsonb_array_elements(v_cands) c
   order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'sla_compliance')::numeric desc nulls last, (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint limit 1;
  select c into v_x from jsonb_array_elements(v_cands) c where coalesce((c ->> 'segment_leads')::int, 0) < v_min_learn and c <> v_win
   order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'sla_compliance')::numeric desc nulls last, (c ->> 'leads_week')::int, (c ->> 'partner_id')::bigint limit 1;
  if v_x is not null and v_share > 0 then
    v_out := jsonb_build_object(v_win ->> 'partner_id', round(1 - v_share, 4), v_x ->> 'partner_id', round(v_share, 4));
  else
    v_out := jsonb_build_object(v_win ->> 'partner_id', 1);
  end if;
  -- a share cap moves the winner's probability to the next candidate when the winner was over the cap that week
  if p_change ->> 'lever' = 'share_cap' and v_seg_match and jsonb_array_length(v_cands) > 1
     and exists (select 1 from jsonb_array_elements(d.excluded) x where x ->> 'why' like 'at the segment''s share cap%') is false
     and (select count(*) filter (where a.partner_id = (v_win ->> 'partner_id')::bigint)::numeric / nullif(count(*), 0)
            from b2b.allocations a where a.segment = d.segment and a.destination_type = 'partner' and not a.is_test
             and a.created_at between d.created_at - interval '7 days' and d.created_at) >= (p_change ->> 'value')::numeric then
    select c into v_x from jsonb_array_elements(v_cands) c where c <> v_win
     order by (c ->> 'cpe')::numeric desc nulls last, (c ->> 'partner_id')::bigint limit 1;
    v_out := jsonb_build_object(v_x ->> 'partner_id', 1);
  end if;
  return v_out;
end $fn$;

create or replace function b2b.ai_simulate(p_change jsonb, p_days int default 90)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  prm jsonb := b2b.engine_params(true);
  v jsonb;
begin
  if p_change ->> 'lever' not in ('exploration_share', 'segment_pin', 'partner_weight', 'share_cap', 'prior_weight', 'speed_factor', 'reliability_factor') then
    return jsonb_build_object('simulated', false, 'why', 'this change cannot be replayed from logged decisions; the holdout will measure it');
  end if;
  with dec as (
    select d.*, a.id alloc_id, b2b.allocation_reward(a.id) r, b2b.ai_policy_probs(d, p_change) pi
      from b2b.engine_decisions d
      join b2b.allocations a on a.engine_decision_id = d.id and a.destination_type = 'partner' and not a.is_test
     where d.destination_type = 'partner' and not d.is_test and d.selection_probability > 0 and d.scoring_mode is not null
       and d.created_at > now() - make_interval(days => least(greatest(p_days, 7), 365))
       and a.created_at <= now() - make_interval(days => (prm ->> 'maturity_days')::int)
       and a.status in ('pushed', 'accepted', 'closed')),
  terms as (select r, coalesce((pi ->> winner_partner_id::text)::numeric, 0) / selection_probability w from dec where pi is not null)
  select jsonb_build_object(
    'simulated', true, 'change', p_change, 'days', p_days, 'decisions', count(*),
    'ncpl_now', round(coalesce(avg(r), 0), 2),
    'ncpl_new', round(coalesce(avg(w * r), 0), 2),
    'difference', round(coalesce(avg(w * r - r), 0), 2),
    'ci95', jsonb_build_array(round(coalesce(avg(w * r - r) - 1.96 * stddev_samp(w * r - r) / sqrt(nullif(count(*), 0)), 0), 2),
                              round(coalesce(avg(w * r - r) + 1.96 * stddev_samp(w * r - r) / sqrt(nullif(count(*), 0)), 0), 2)),
    'gain_pct', case when avg(r) > 0 then round(100 * avg(w * r - r) / avg(r), 1) end,
    'ess', round(coalesce(power(sum(w), 2) / nullif(sum(w * w), 0), 0), 1),
    'enough', count(*) >= 30)
    into v from terms;
  return v;
end $fn$;

/* Realised net commission per matured partner lead, AI-steered against the holdout, overall and by month. */
create or replace function b2b.ai_uplift(p_days int default 180)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  with prm as (select (b2b.engine_params(true) ->> 'maturity_days')::int md),
  x as (select d.holdout, date_trunc('month', a.created_at at time zone 'Asia/Kolkata')::date mon, b2b.allocation_reward(a.id) r
          from b2b.engine_decisions d
          join b2b.allocations a on a.engine_decision_id = d.id and a.destination_type = 'partner' and not a.is_test, prm
         where d.destination_type = 'partner' and not d.is_test and d.scoring_mode is not null
           and a.created_at > now() - make_interval(days => p_days) and a.created_at <= now() - make_interval(days => prm.md)
           and a.status in ('pushed', 'accepted', 'closed')),
  s as (select holdout, count(*) n, avg(r) mu, coalesce(var_samp(r), 0) v from x group by holdout)
  select jsonb_build_object(
    'maturity_days', (select md from prm),
    'steered', jsonb_build_object('leads', coalesce((select n from s where not holdout), 0), 'ncpl', round(coalesce((select mu from s where not holdout), 0), 2)),
    'holdout', jsonb_build_object('leads', coalesce((select n from s where holdout), 0), 'ncpl', round(coalesce((select mu from s where holdout), 0), 2)),
    'uplift_pct', case when (select mu from s where holdout) > 0
                       then round(100 * ((select mu from s where not holdout) - (select mu from s where holdout)) / (select mu from s where holdout), 1) end,
    'z', round(coalesce(((select mu from s where not holdout) - (select mu from s where holdout))
                        / nullif(sqrt((select v / n from s where not holdout) + (select v / n from s where holdout)), 0), 0), 2),
    'by_month', coalesce((select jsonb_agg(jsonb_build_object('month', mon, 'steered', st, 'holdout', ho, 'steered_n', sn, 'holdout_n', hn) order by mon)
                            from (select mon, round(avg(r) filter (where not holdout), 2) st, round(avg(r) filter (where holdout), 2) ho,
                                         count(*) filter (where not holdout) sn, count(*) filter (where holdout) hn from x group by mon) m), '[]'));
$fn$;

-- ---------- the tools ----------
create or replace function b2b.ai_tool(p_name text, p_input jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_days int := least(greatest(coalesce((p_input ->> 'days')::int, 30), 1), 365);
  v_seg text := nullif(p_input ->> 'segment', '');
begin
  case p_name
  when 'segment_scorecards' then
    return jsonb_build_object('segments', coalesce((
      select jsonb_agg(jsonb_build_object('segment', s.segment, 'mode', b2b.segment_mode(s.segment) ->> 'mode', 'pinned', b2b.segment_mode(s.segment) -> 'pin' ->> 'source',
               'leads', s.n_leads, 'matured', s.n_matured, 'avg_enrolment_rate', s.prior, 'partners', s.partners, 'partners_matured', s.partners_matured,
               'routed_last_days', (select count(*) from b2b.allocations a where a.segment = s.segment and a.destination_type = 'partner' and not a.is_test
                                     and a.created_at > now() - make_interval(days => v_days)),
               'policy', coalesce((select value -> 'segments' -> s.segment from b2b.settings where key = 'engine_policy'), '{}'))
             order by s.n_leads desc)
        from b2b.segment_stats s where s.variant = 'base' and s.n_leads > 0 and (v_seg is null or s.segment = v_seg)), '[]'), 'days', v_days);
  when 'partner_scorecards' then
    return jsonb_build_object('partners', coalesce((
      select jsonb_agg(jsonb_build_object('partner_id', p.id, 'partner', coalesce(p.display_name, p.name), 'status', p.status,
               'leads', x.n, 'accepted', x.acc, 'duplicates', x.dup, 'rejected', x.rej,
               'duplicate_rate', round(x.dup::numeric / nullif(x.n, 0), 4),
               'sla_first_attempt_met', (select round(count(*) filter (where c.status = 'met')::numeric / nullif(count(*) filter (where c.status in ('met', 'met_late', 'breached')), 0), 4)
                                           from b2b.sla_checks c where c.partner_id = p.id and not c.is_test and c.sla = 'first_attempt' and c.due_at > now() - make_interval(days => v_days)),
               'enrolments_reported', (select count(*) from public.enrollments e where e.partner_id = p.id and e.source_product = 'b2b' and e.created_at > now() - make_interval(days => v_days)),
               'segments', coalesce((select jsonb_agg(jsonb_build_object('segment', s.segment, 'p_hat', s.p_hat, 'matured', s.n_matured, 'refund_rate', s.refund_rate,
                                                                         'speed', s.speed, 'reliability', s.reliability) order by s.n_leads desc)
                                       from b2b.partner_segment_stats s where s.variant = 'base' and s.partner_id = p.id and s.n_leads > 0
                                         and (v_seg is null or s.segment in (v_seg, b2b.segment_rollup(v_seg)))), '[]'),
               'weight', (select value -> 'partner_weights' -> (p.id::text) from b2b.settings where key = 'engine_policy'))
             order by x.n desc)
        from b2b.partners p
        cross join lateral (select count(*) n, count(*) filter (where a.status in ('accepted', 'closed') or a.accepted_at is not null) acc,
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
                     round(percentile_cont(0.5) within group (order by b2b.cpe_net(o.partner_id, o.programme_id, o.fees))::numeric, 0) cpe
                from b2b.partner_programmes o join public.catalog_programs c on c.id = o.programme_id and c.active
                join b2b.partners p on p.id = o.partner_id and p.status <> 'closed'
               where o.valid_to is null and o.active and (v_seg is null or c.course_key = split_part(v_seg, '|', 1))
               group by 1, 2, 3, 4) z), '[]'));
  when 'engine_settings' then
    return jsonb_build_object('engine', (select value - 'paid_rule' - 'blocked_phones' - 'b2c_sources' from b2b.settings where key = 'engine'),
                              'policy', (select value from b2b.settings where key = 'engine_policy'),
                              'effective', b2b.engine_params(false),
                              'history', coalesce((select jsonb_agg(jsonb_build_object('key', v.key, 'version', v.version, 'reason', v.reason, 'actor', v.actor_type, 'at', v.created_at) order by v.created_at desc)
                                                     from (select * from b2b.settings_versions where key in ('engine', 'engine_policy') order by created_at desc limit 15) v), '[]'),
                              'bounds', jsonb_build_object('exploration_share', '[0, 0.5]'::jsonb, 'maturity_days', '[30, 90]'::jsonb, 'half_life_days', '[14, 60]'::jsonb,
                                                           'prior_weight', '[5, 50]'::jsonb, 'segment_pin_days', 30, 'partner_weight', '[0.9, 1.1]'::jsonb,
                                                           'partner_weight_days', 14, 'share_cap', '[0.5, 1]'::jsonb));
  when 'model_metrics' then
    return jsonb_build_object('models', coalesce((select jsonb_agg(jsonb_build_object('version', m.version, 'status', m.status, 'trained_on', m.trained_on,
                                                    'holdout', m.metrics -> 'holdout' - 'deciles', 'baseline', m.metrics -> 'baseline' - 'deciles', 'policy', m.metrics -> 'policy',
                                                    'gate', m.gate, 'monitor', m.metrics -> 'monitor' - 'deciles') order by m.id desc)
                                                    from (select * from b2b.ml_models where status in ('shadow', 'challenger', 'champion') or id in (select id from b2b.ml_models order by id desc limit 3)) m), '[]'));
  when 'recent_decisions' then
    return jsonb_build_object('decisions', coalesce((
      select jsonb_agg(jsonb_build_object('lead', b2b.ai_pseudo(d.lead_id), 'at', d.created_at, 'segment', d.segment, 'destination', d.destination_type,
               'mode', d.mode, 'scoring', d.scoring_mode, 'holdout', d.holdout, 'reason', d.reason,
               'partner', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = d.winner_partner_id),
               'selection_probability', d.selection_probability, 'model', d.model_version,
               'candidates', (select jsonb_agg(jsonb_build_object('partner', c ->> 'name', 'cpe', c -> 'cpe', 'p_hat', c -> 'p_hat', 'ncpl', c -> 'ncpl', 'eligible', c -> 'eligible'))
                                from jsonb_array_elements(d.candidates) c)) order by d.id desc)
        from (select * from b2b.engine_decisions d where not d.is_test and (v_seg is null or d.segment = v_seg) order by d.id desc
               limit least(greatest(coalesce((p_input ->> 'limit')::int, 50), 1), 200)) d), '[]'));
  when 'alerts' then
    return jsonb_build_object('alerts', coalesce((
      select jsonb_agg(jsonb_build_object('type', e.type, 'at', e.occurred_at,
               'partner', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = e.partner_id),
               'detail', e.payload - 'lead_id' - 'phone' - 'email' - 'name') order by e.occurred_at desc)
        from (select * from b2b.events e where (e.type like 'alert.%' or e.type = 'routing.error') and e.occurred_at > now() - make_interval(days => least(v_days, 30))
               order by e.occurred_at desc limit 100) e), '[]'));
  when 'uplift' then
    return b2b.ai_uplift(greatest(v_days, 30));
  when 'run_simulation' then
    return b2b.ai_simulate(p_input -> 'change', coalesce((p_input ->> 'days')::int, 90));
  else
    raise exception 'unknown tool %', p_name using errcode = '22023';
  end case;
end $fn$;

revoke execute on function b2b.ai_pseudo(bigint), b2b.allocation_reward(bigint), b2b.ai_policy_probs(b2b.engine_decisions, jsonb), b2b.ai_simulate(jsonb, int),
                           b2b.ai_uplift(int), b2b.ai_tool(text, jsonb) from public, anon, authenticated;
grant execute on function b2b.ai_pseudo(bigint), b2b.allocation_reward(bigint), b2b.ai_policy_probs(b2b.engine_decisions, jsonb), b2b.ai_simulate(jsonb, int),
                          b2b.ai_uplift(int), b2b.ai_tool(text, jsonb) to service_role;
