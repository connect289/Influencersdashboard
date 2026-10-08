-- M24a: performance routing, part 1 (spec B7.2, B7.4, B7.8.1): the numbers the engine scores with, refreshed hourly.
--   partner_segment_stats  per partner and segment (exact course|level|mode and the course roll-up course|*|*):
--                          matured leads weighted by recency, young leads' expected outcome from stage-to-enrolment rates
--                          (leading indicators), the Beta posterior (alpha, beta, P̂) around the segment prior, the refund
--                          rate shrunk to the global rate, SLA compliance and the optional speed and reliability factors.
--                          variant 'base' uses the Admin's settings; variant 'ai' exists only while the AI optimiser has
--                          changed maturity, half-life or prior strength (the holdout keeps using 'base').
--   segment_stats          per segment: the prior (all partners' conversion), how many partners have matured data, auto mode.
--   stage_rates            historical P(enrol | reached at least this stage), from matured leads, shrunk to defaults.
--   stats_snapshots        one row per partner, segment and day, for the decline alert (P̂ or NCPL down by more than a third).
--   engine_policy          (setting) what changes routing per segment or partner: mode pins, exploration and share caps per
--                          segment, temporary partner weights, the segment kill switch, the holdout share and the AI
--                          optimiser's bounded parameters. Every entry carries its source (admin or ai); the holdout ignores 'ai'.
--   u01 / gamma / beta     a seeded, reproducible sampler (md5 streams; Marsaglia-Tsang gamma), so every draw in a decision
--                          can be replayed from engine_decisions.seed.
--   guard_tick             auto-pause (5 first-contact SLA breaches in a row; pushes failing for 30 minutes; duplicate rate
--                          above 25% over the last 20 leads) and the decline alert. Each writes an alert.* event.
-- Nothing here touches student_leads, Witty or the catalogue.

-- ---------- policy setting ----------
insert into b2b.settings (key, value) values ('engine_policy', jsonb_build_object(
  'holdout_share', 0.10, 'mc_draws', 200, 'leading_weight', 0.5, 'leading_min_days', 3,
  'segments', '{}'::jsonb, 'partner_weights', '{}'::jsonb, 'kill_segments', '[]'::jsonb, 'ai', '{}'::jsonb))
on conflict (key) do nothing;
insert into b2b.settings_versions (key, version, value, reason, actor_type)
select 'engine_policy', 1, s.value, 'initial defaults (M24)', 'system' from b2b.settings s
 where s.key = 'engine_policy' and not exists (select 1 from b2b.settings_versions v where v.key = 'engine_policy');

-- ---------- decision log: what scored the lead ----------
alter table b2b.engine_decisions add column if not exists scoring_mode text;
alter table b2b.engine_decisions add column if not exists holdout boolean not null default false;
alter table b2b.engine_decisions add column if not exists policy_version int;
alter table b2b.engine_decisions add column if not exists stats_at timestamptz;
alter table b2b.engine_decisions add column if not exists model_version text;
alter table b2b.engine_decisions add column if not exists shadow jsonb;
do $do$ begin
  if not exists (select 1 from pg_constraint where conname = 'engine_decisions_scoring_mode_check') then
    alter table b2b.engine_decisions add constraint engine_decisions_scoring_mode_check
      check (scoring_mode is null or scoring_mode in ('commission_first', 'performance', 'kill_switch'));
  end if;
end $do$;
create index if not exists engine_decisions_segment_idx on b2b.engine_decisions (segment, created_at desc) where destination_type = 'partner';

-- ---------- stats tables ----------
create table if not exists b2b.stage_rates (
  stage        text primary key check (stage in ('applied', 'interested', 'contacted', 'accepted', 'none')),
  n            int not null default 0,
  enrolled     int not null default 0,
  rate         numeric(6, 5) not null,
  refreshed_at timestamptz not null default now()
);

create table if not exists b2b.segment_stats (
  variant           text not null check (variant in ('base', 'ai')),
  segment           text not null,
  n_leads           int not null default 0,
  n_matured         int not null default 0,
  w_matured         numeric(12, 4) not null default 0,
  w_enrolled        numeric(12, 4) not null default 0,
  prior             numeric(6, 5) not null,
  partners          int not null default 0,
  partners_matured  int not null default 0,
  auto_mode         text not null check (auto_mode in ('commission_first', 'performance')),
  refreshed_at      timestamptz not null default now(),
  primary key (variant, segment)
);

create table if not exists b2b.partner_segment_stats (
  variant              text not null check (variant in ('base', 'ai')),
  partner_id           bigint not null references b2b.partners (id),
  segment              text not null,
  is_rollup            boolean not null default false,
  n_leads              int not null default 0,
  n_matured            int not null default 0,
  w_matured            numeric(12, 4) not null default 0,
  w_enrolled           numeric(12, 4) not null default 0,
  n_young              int not null default 0,
  w_young              numeric(12, 4) not null default 0,
  w_young_expected     numeric(12, 4) not null default 0,
  enrolled             int not null default 0,
  prior                numeric(6, 5) not null,
  alpha                numeric(12, 4) not null,
  beta                 numeric(12, 4) not null,
  p_hat                numeric(6, 5) not null,
  refund_rate          numeric(6, 5) not null default 0,
  sla_compliance       numeric(6, 5),
  first_contact_hours  numeric(8, 2),
  speed                numeric(5, 4) not null default 1,
  reliability          numeric(5, 4) not null default 1,
  refreshed_at         timestamptz not null default now(),
  primary key (variant, partner_id, segment)
);
create index if not exists partner_segment_stats_segment_idx on b2b.partner_segment_stats (variant, segment);

create table if not exists b2b.stats_snapshots (
  day         date not null,
  partner_id  bigint not null references b2b.partners (id),
  segment     text not null,
  p_hat       numeric(6, 5) not null,
  ncpl_inr    numeric(12, 2),
  n_matured   int not null,
  primary key (day, partner_id, segment)
);

do $rls$
declare t text;
begin
  foreach t in array array['stage_rates', 'segment_stats', 'partner_segment_stats', 'stats_snapshots'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- ---------- seeded sampler ----------
/* A uniform number in (0, 1) from a seed and a stream tag: the same inputs give the same number on every replay. */
create or replace function b2b.u01(p_seed text, p_tag text)
returns double precision language sql immutable parallel safe set search_path = '' as $fn$
  select ((('x' || substr(md5(p_seed || ':' || p_tag), 1, 13))::bit(52)::bigint)::double precision + 0.5) / 4503599627370496.0;
$fn$;

/* Gamma(shape, 1) by Marsaglia and Tsang, with the shape < 1 boost. Deterministic in (seed, tag). */
create or replace function b2b.gamma_sample(p_shape double precision, p_seed text, p_tag text)
returns double precision language plpgsql immutable parallel safe set search_path = '' as $fn$
declare
  a double precision := greatest(p_shape, 1e-6);
  d double precision;
  c double precision;
  x double precision;
  v double precision;
  u double precision;
  k int := 0;
  boost double precision := 1;
begin
  if a < 1 then
    -- u^(1/a) in log space: for a tiny shape it is below the smallest double, and Postgres raises on underflow
    boost := ln(b2b.u01(p_seed, p_tag || ':b')) / a;
    boost := case when boost < -700 then 0 else exp(boost) end;
    a := a + 1;
  end if;
  d := a - 1.0 / 3.0;
  c := 1.0 / sqrt(9.0 * d);
  loop
    k := k + 1;
    x := sqrt(-2.0 * ln(b2b.u01(p_seed, p_tag || ':' || k || 'a'))) * cos(2.0 * pi() * b2b.u01(p_seed, p_tag || ':' || k || 'b'));
    v := 1.0 + c * x;
    if v > 0 then
      v := v * v * v;
      u := b2b.u01(p_seed, p_tag || ':' || k || 'c');
      if ln(u) < 0.5 * x * x + d - d * v + d * ln(v) then return d * v * boost; end if;
    end if;
    if k >= 50 then return d * boost; end if;  -- practically never (acceptance is above 95% per round)
  end loop;
end $fn$;

create or replace function b2b.beta_sample(p_alpha double precision, p_beta double precision, p_seed text, p_tag text)
returns double precision language sql immutable parallel safe set search_path = '' as $fn$
  select case when g.x + g.y <= 0 then p_alpha / nullif(p_alpha + p_beta, 0) else g.x / (g.x + g.y) end
    from (select b2b.gamma_sample(p_alpha, p_seed, p_tag || ':x') x, b2b.gamma_sample(p_beta, p_seed, p_tag || ':y') y) g;
$fn$;

-- ---------- effective parameters ----------
/* The engine's statistical parameters: the Admin's engine settings, plus the AI optimiser's bounded changes unless
   p_base (holdout leads and the 'base' stats). */
create or replace function b2b.engine_params(p_base boolean)
returns jsonb language sql stable set search_path = '' as $fn$
  with e as (select coalesce((select value from b2b.settings where key = 'engine'), '{}') v),
       p as (select coalesce((select value from b2b.settings where key = 'engine_policy'), '{}') v),
       ai as (select case when p_base then '{}'::jsonb else coalesce(p.v -> 'ai', '{}') end v from p)
  select jsonb_build_object(
    'maturity_days', least(greatest(coalesce((ai.v ->> 'maturity_days')::int, (e.v ->> 'maturity_days')::int, 60), 7), 365),
    'half_life_days', least(greatest(coalesce((ai.v ->> 'half_life_days')::int, (e.v ->> 'half_life_days')::int, 30), 7), 365),
    'prior_weight', least(greatest(coalesce((ai.v ->> 'prior_weight')::numeric, (e.v ->> 'prior_weight')::numeric, 20), 1), 200),
    'default_p_enroll', least(greatest(coalesce((e.v ->> 'default_p_enroll')::numeric, 0.05), 0.001), 0.9),
    'min_matured_leads', greatest(coalesce((e.v ->> 'min_matured_leads')::int, 30), 1),
    'speed_on', coalesce((ai.v ->> 'speed_factor')::boolean, (e.v -> 'speed_factor' ->> 'enabled')::boolean, false),
    'reliability_on', coalesce((ai.v ->> 'reliability_factor')::boolean, (e.v -> 'reliability_factor' ->> 'enabled')::boolean, false),
    'leading_weight', least(greatest(coalesce((p.v ->> 'leading_weight')::numeric, 0.5), 0), 1),
    'leading_min_days', greatest(coalesce((p.v ->> 'leading_min_days')::int, 3), 0),
    'variant', case when not p_base and (ai.v ? 'maturity_days' or ai.v ? 'half_life_days' or ai.v ? 'prior_weight') then 'ai' else 'base' end)
  from e, p, ai;
$fn$;

/* The course roll-up of a segment: 'mba|PG|Online' -> 'mba|*|*'. */
create or replace function b2b.segment_rollup(p_segment text)
returns text language sql immutable set search_path = '' as $fn$
  select split_part(p_segment, '|', 1) || '|*|*';
$fn$;

-- ---------- outcomes per allocation ----------
/* One row per real partner allocation the partner actually received (not test, not duplicate/rejected/failed/recalled):
   its age, furthest stage before enrolment (applied, interested, contacted, accepted, none) and whether it enrolled
   (any enrolment reported, including later refunds and cancellations: the refund rate accounts for those). The basis of the stats and of the ML training set (M25). */
create or replace function b2b.allocation_outcomes()
returns table (allocation_id bigint, lead_id bigint, partner_id bigint, segment text, created_at timestamptz, age_days numeric,
               enrolled boolean, enrolment_status text, stage text, first_contact_hours numeric)
language sql stable security definer set search_path = '' as $fn$
  with st as (select e ->> 'key' k, (e ->> 'rank')::int r from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages'),
  a as (select x.* from b2b.allocations x
         where x.destination_type = 'partner' and not x.is_test and x.segment is not null
           and (x.status in ('pushed', 'accepted', 'closed') or x.accepted_at is not null))
  select a.id, a.lead_id, a.partner_id, a.segment, a.created_at,
         round(extract(epoch from now() - a.created_at)::numeric / 86400, 3),
         en.status is not null, en.status,
         -- the furthest stage before enrolment; an enrolled student has applied
         case when en.status is not null or l.applied_at >= a.created_at or pa.top >= 70 then 'applied'
              when pa.top >= 60 or (select r from st where k = l.stage) between 60 and 69 and l.allocation_id = a.id then 'interested'
              when l.first_contacted_at >= a.created_at or pa.top >= 50 or pa.calls > 0 then 'contacted'
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

/* Each outcome under a segment key (exact and course roll-up) with its weights for the given parameters:
   matured leads weigh 0.5^((age - maturity) / half-life); young leads (leading indicators) weigh leading_weight x age/maturity
   and count as rate(stage) enrolments, except an enrolment already reported, which counts in full. */
create or replace function b2b.keyed_outcomes(prm jsonb, p_rates jsonb)
returns table (partner_id bigint, segment text, w_m numeric, enr_m numeric, matured boolean, w_y numeric, exp_y numeric, enrolled boolean)
language sql stable security definer set search_path = '' as $fn$
  select o.partner_id, k.seg,
         case when o.age_days >= m.md then power(0.5, (o.age_days - m.md) / m.hl) else 0 end,
         case when o.age_days >= m.md and o.enrolled then power(0.5, (o.age_days - m.md) / m.hl) else 0 end,
         o.age_days >= m.md,
         case when o.age_days < m.md and o.enrolled then 1
              when o.age_days < m.md and o.age_days >= m.lmin then m.lw * least(o.age_days / m.md, 1) else 0 end,
         case when o.age_days < m.md and o.enrolled then 1
              when o.age_days < m.md and o.age_days >= m.lmin then m.lw * least(o.age_days / m.md, 1) * coalesce((p_rates ->> o.stage)::numeric, 0) else 0 end,
         o.enrolled
    from b2b.allocation_outcomes() o
   cross join (select (prm ->> 'maturity_days')::numeric md, (prm ->> 'half_life_days')::numeric hl,
                      (prm ->> 'leading_weight')::numeric lw, (prm ->> 'leading_min_days')::numeric lmin) m
   cross join lateral (select o.segment seg union select b2b.segment_rollup(o.segment)) k;
$fn$;

-- ---------- hourly refresh ----------
create or replace function b2b.stats_refresh()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_now timestamptz := now();
  v_variants text[] := array['base'];
  v_variant text;
  prm jsonb;
  v_def jsonb := '{"applied":0.35,"interested":0.12,"contacted":0.05,"accepted":0.03,"none":0.01}';
  v_rates jsonb;
  v_global_refund numeric;
  v_med_contact numeric;
  v_rows int := 0;
  v_alerts int := 0;
  r record;
begin
  perform set_config('b2b.actor', 'engine', true);

  -- P(enrol | reached at least this stage) from matured leads (base maturity), shrunk to the defaults with a strength of 10
  prm := b2b.engine_params(true);
  insert into b2b.stage_rates (stage, n, enrolled, rate, refreshed_at)
  select s.k, count(o.*), count(o.*) filter (where o.enrolled),
         round((count(o.*) filter (where o.enrolled) + (v_def ->> s.k)::numeric * 10) / (count(o.*) + 10), 5), v_now
    from (values ('none', 0), ('accepted', 1), ('contacted', 2), ('interested', 3), ('applied', 4)) s(k, rk)
    left join (select x.enrolled, array_position(array['none', 'accepted', 'contacted', 'interested', 'applied'], x.stage) - 1 rk
                 from b2b.allocation_outcomes() x where x.age_days >= (prm ->> 'maturity_days')::numeric) o on o.rk >= s.rk
   group by s.k
  on conflict (stage) do update set n = excluded.n, enrolled = excluded.enrolled, rate = excluded.rate, refreshed_at = excluded.refreshed_at;
  select jsonb_object_agg(stage, rate) into v_rates from b2b.stage_rates;

  -- refund rate: (refunded + cancelled) / decided enrolments, per partner, shrunk to the global rate with a strength of 20
  select coalesce(sum(case when e.status in ('refunded', 'cancelled') then 1 else 0 end)::numeric / nullif(count(*), 0), 0) into v_global_refund
    from public.enrollments e where e.source_product = 'b2b' and e.status in ('verified', 'refunded', 'cancelled');
  -- speed: median hours to the first attempt over 30 days, against all partners' median
  select percentile_cont(0.5) within group (order by o.first_contact_hours) into v_med_contact
    from b2b.allocation_outcomes() o where o.first_contact_hours is not null and o.created_at > v_now - interval '30 days';

  if (b2b.engine_params(false) ->> 'variant') = 'ai' then v_variants := array_append(v_variants, 'ai'); end if;

  foreach v_variant in array v_variants loop
    prm := b2b.engine_params(v_variant = 'base');
    -- segment priors: all partners' matured conversion, shrunk to default_p_enroll with prior_weight
    insert into b2b.segment_stats (variant, segment, n_leads, n_matured, w_matured, w_enrolled, prior, partners, partners_matured, auto_mode, refreshed_at)
    select v_variant, s.segment, s.n, s.nm, s.wm, s.we,
           round((s.we + (prm ->> 'default_p_enroll')::numeric * (prm ->> 'prior_weight')::numeric) / (s.wm + (prm ->> 'prior_weight')::numeric), 5),
           s.partners, s.pm, case when s.pm >= 2 then 'performance' else 'commission_first' end, v_now
      from (select k.segment, count(*) n, count(*) filter (where k.matured) nm, coalesce(sum(k.w_m), 0) wm, coalesce(sum(k.enr_m), 0) we,
                   count(distinct k.partner_id) partners,
                   count(distinct k.partner_id) filter (where k.pm) pm
              from (select k.*, count(*) filter (where k.matured) over (partition by k.segment, k.partner_id) >= (prm ->> 'min_matured_leads')::int pm
                      from b2b.keyed_outcomes(prm, v_rates) k) k
             group by k.segment) s
    on conflict (variant, segment) do update
      set n_leads = excluded.n_leads, n_matured = excluded.n_matured, w_matured = excluded.w_matured, w_enrolled = excluded.w_enrolled,
          prior = excluded.prior, partners = excluded.partners, partners_matured = excluded.partners_matured, auto_mode = excluded.auto_mode,
          refreshed_at = excluded.refreshed_at;

    insert into b2b.partner_segment_stats (variant, partner_id, segment, is_rollup, n_leads, n_matured, w_matured, w_enrolled, n_young, w_young,
                                           w_young_expected, enrolled, prior, alpha, beta, p_hat, refund_rate, sla_compliance, first_contact_hours,
                                           speed, reliability, refreshed_at)
    select v_variant, x.partner_id, x.segment, x.is_rollup, x.n, x.nm, x.wm, x.we, x.ny, x.wy, x.ey, x.enr, x.prior,
           x.a, x.b, round(x.a / (x.a + x.b), 5),
           coalesce(pr.refund, 0), pr.sla, pr.fch,
           case when pr.fch is null or v_med_contact is null or pr.fch <= 0 then 1 else least(greatest(v_med_contact / pr.fch, 0.85), 1.15) end,
           pr.rel, v_now
      from (select k.partner_id, k.segment, k.segment = b2b.segment_rollup(k.segment) is_rollup, count(*) n, count(*) filter (where k.matured) nm,
                   sum(k.w_m) wm, sum(k.enr_m) we, count(*) filter (where not k.matured) ny, sum(k.w_y) wy, sum(k.exp_y) ey,
                   count(*) filter (where k.enrolled) enr, ss.prior,
                   round(ss.prior * (prm ->> 'prior_weight')::numeric + sum(k.enr_m) + sum(k.exp_y), 4) a,
                   round((1 - ss.prior) * (prm ->> 'prior_weight')::numeric + (sum(k.w_m) - sum(k.enr_m)) + (sum(k.w_y) - sum(k.exp_y)), 4) b
              from b2b.keyed_outcomes(prm, v_rates) k join b2b.segment_stats ss on ss.variant = v_variant and ss.segment = k.segment
             group by k.partner_id, k.segment, ss.prior) x
      left join lateral (
        select round((coalesce(rf.bad, 0) + v_global_refund * 20) / (coalesce(rf.n, 0) + 20), 5) refund,
               sl.compliance sla, ct.fch,
               round(least(greatest(1 - 0.5 * coalesce(s7.breach_share, 0) - 0.5 * coalesce(ev.err_share, 0), 0.7), 1.0), 4) rel
          from (select count(*) n, count(*) filter (where e.status in ('refunded', 'cancelled')) bad from public.enrollments e
                 where e.partner_id = x.partner_id and e.source_product = 'b2b' and e.status in ('verified', 'refunded', 'cancelled')) rf,
               (select round(count(*) filter (where c.status = 'met')::numeric / nullif(count(*) filter (where c.status in ('met', 'met_late', 'breached')), 0), 5) compliance
                  from b2b.sla_checks c where c.partner_id = x.partner_id and not c.is_test and c.due_at > v_now - interval '30 days') sl,
               (select percentile_cont(0.5) within group (order by o.first_contact_hours)::numeric fch from b2b.allocation_outcomes() o
                 where o.partner_id = x.partner_id and o.first_contact_hours is not null and o.created_at > v_now - interval '30 days') ct,
               (select count(*) filter (where c.status = 'breached')::numeric / nullif(count(*) filter (where c.status in ('met', 'met_late', 'breached')), 0) breach_share
                  from b2b.sla_checks c where c.partner_id = x.partner_id and not c.is_test and c.due_at > v_now - interval '7 days') s7,
               (select count(*) filter (where e.status = 'error')::numeric / nullif(count(*), 0) err_share
                  from b2b.partner_events e where e.partner_id = x.partner_id and e.received_at > v_now - interval '7 days') ev
      ) pr on true
    on conflict (variant, partner_id, segment) do update
      set is_rollup = excluded.is_rollup, n_leads = excluded.n_leads, n_matured = excluded.n_matured, w_matured = excluded.w_matured,
          w_enrolled = excluded.w_enrolled, n_young = excluded.n_young, w_young = excluded.w_young, w_young_expected = excluded.w_young_expected,
          enrolled = excluded.enrolled, prior = excluded.prior, alpha = excluded.alpha, beta = excluded.beta, p_hat = excluded.p_hat,
          refund_rate = excluded.refund_rate, sla_compliance = excluded.sla_compliance, first_contact_hours = excluded.first_contact_hours,
          speed = excluded.speed, reliability = excluded.reliability, refreshed_at = excluded.refreshed_at;
    get diagnostics v_rows = row_count;

    -- keys with no allocations left (all of them became test, failed…) fall back to the prior
    update b2b.partner_segment_stats s set n_leads = 0, n_matured = 0, w_matured = 0, w_enrolled = 0, n_young = 0, w_young = 0, w_young_expected = 0,
           enrolled = 0, alpha = round(s.prior * (prm ->> 'prior_weight')::numeric, 4), beta = round((1 - s.prior) * (prm ->> 'prior_weight')::numeric, 4),
           p_hat = s.prior, refreshed_at = v_now
     where s.variant = v_variant and s.refreshed_at < v_now;
    update b2b.segment_stats s set n_leads = 0, n_matured = 0, w_matured = 0, w_enrolled = 0, partners = 0, partners_matured = 0,
           auto_mode = 'commission_first', prior = (prm ->> 'default_p_enroll')::numeric, refreshed_at = v_now
     where s.variant = v_variant and s.refreshed_at < v_now;
  end loop;
  -- 'ai' rows left from AI changes since withdrawn are never read: the engine reads 'ai' only while engine_params says so

  -- daily snapshot for the decline alert: NCPL uses the partner's current CPE for the segment's course (median of its offers)
  insert into b2b.stats_snapshots (day, partner_id, segment, p_hat, ncpl_inr, n_matured)
  select (v_now at time zone 'Asia/Kolkata')::date, s.partner_id, s.segment, s.p_hat,
         round(s.p_hat * (1 - s.refund_rate) * (select percentile_cont(0.5) within group (order by b2b.cpe_net(o.partner_id, o.programme_id, o.fees))
                                                  from b2b.partner_programmes o join public.catalog_programs c on c.id = o.programme_id
                                                 where o.partner_id = s.partner_id and o.valid_to is null and o.active
                                                   and c.course_key = split_part(s.segment, '|', 1))::numeric, 2),
         s.n_matured
    from b2b.partner_segment_stats s where s.variant = 'base' and s.n_leads > 0
  on conflict (day, partner_id, segment) do update set p_hat = excluded.p_hat, ncpl_inr = excluded.ncpl_inr, n_matured = excluded.n_matured;

  -- decline alert (B7.4): P̂ or NCPL down by more than a third against its value 30 days ago, with matured data, once a week
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
                            'alerts', v_alerts, 'at', v_now);
end $fn$;

-- ---------- guardrails (B7.4) ----------
/* Auto-pause a live partner on: 5 first-attempt SLA breaches in a row; pushes failing for 30 minutes (3 or more, none
   succeeded); more than 25% duplicates over its last 20 leads. Evidence older than the partner's last switch to active
   is ignored, so resuming a partner gives it a clean slate. Runs every 5 minutes. */
create or replace function b2b.guard_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  p record;
  v_since timestamptz;
  v_why text;
  v_kind text;
  v_paused int := 0;
  v_x record;
begin
  perform set_config('b2b.actor', 'engine', true);
  for p in select * from b2b.partners where status = 'active' and b2b.is_live('partner:' || id) loop
    v_since := coalesce((select max(e.occurred_at) from b2b.events e where e.type = 'partner.status_changed' and e.partner_id = p.id
                                                                     and e.payload ->> 'to' = 'active'), '-infinity');
    v_why := null;
    -- 1. five first-attempt breaches in a row
    select count(*) filter (where c.status = 'breached') bad, count(*) n into v_x
      from (select c.status from b2b.sla_checks c
             where c.partner_id = p.id and not c.is_test and c.sla = 'first_attempt' and c.status in ('met', 'met_late', 'breached')
               and c.due_at > v_since order by c.due_at desc limit 5) c;
    if v_x.n = 5 and v_x.bad = 5 then
      v_kind := 'sla_breaches'; v_why := 'missed the first-contact SLA on 5 leads in a row';
    end if;
    -- 2. pushes failing for 30 minutes
    if v_why is null then
      select count(*) filter (where r.outcome in ('error', 'timeout')) bad, count(*) filter (where r.outcome in ('created', 'duplicate', 'rejected')) ok,
             min(r.sent_at) filter (where r.outcome in ('error', 'timeout')) first_bad into v_x
        from b2b.push_requests r join b2b.allocations a on a.id = r.allocation_id
       where a.partner_id = p.id and not a.is_test and r.sent_at > greatest(v_since, now() - interval '45 minutes');
      if v_x.bad >= 3 and v_x.ok = 0 and v_x.first_bad <= now() - interval '30 minutes' then
        v_kind := 'push_failing'; v_why := 'pushes have failed for 30 minutes';
      end if;
    end if;
    -- 3. duplicate rate over the last 20 leads
    if v_why is null then
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
       where id = p.id;
      perform b2b.log_event('partner.status_changed', null, null, p.id, jsonb_build_object('from', 'active', 'to', 'paused', 'reason', 'auto-paused: ' || v_why, 'auto', true));
      perform b2b.log_event('alert.partner_auto_paused', null, null, p.id, jsonb_build_object('kind', v_kind, 'reason', v_why, 'partner', coalesce(p.display_name, p.name)));
      v_paused := v_paused + 1;
    end if;
  end loop;
  return jsonb_build_object('paused', v_paused);
end $fn$;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('b2b-stats-refresh', 'b2b-guard-tick');
  perform cron.schedule('b2b-stats-refresh', '7 * * * *', 'select b2b.stats_refresh()');
  perform cron.schedule('b2b-guard-tick', '*/5 * * * *', 'select b2b.guard_tick()');
end $cron$;

revoke execute on function b2b.u01(text, text), b2b.gamma_sample(double precision, text, text), b2b.beta_sample(double precision, double precision, text, text),
                           b2b.engine_params(boolean), b2b.segment_rollup(text), b2b.allocation_outcomes(), b2b.keyed_outcomes(jsonb, jsonb), b2b.stats_refresh(), b2b.guard_tick()
  from public, anon, authenticated;
grant execute on function b2b.u01(text, text), b2b.gamma_sample(double precision, text, text), b2b.beta_sample(double precision, double precision, text, text),
                          b2b.engine_params(boolean), b2b.segment_rollup(text), b2b.allocation_outcomes(), b2b.keyed_outcomes(jsonb, jsonb), b2b.stats_refresh(), b2b.guard_tick()
  to service_role;
