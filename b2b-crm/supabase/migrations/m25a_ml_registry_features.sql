-- M25a: the per-lead model (spec B7.8.1), part 1: settings, registry, features.
-- Model v1 is an L2-regularised logistic regression with partner x lead interaction features, calibrated with isotonic
-- regression (pool adjacent violators) on a time-based holdout. It is trained inside the database (nightly, pg_cron), so
-- no extra service, key or cost is needed; gradient-boosted trees (the spec's first choice) can replace it later behind
-- the same registry and scoring hook (b2b.model_score), because the engine only reads P(enrol) per candidate.
--   ml_models          registry: version, status (training, shadow, challenger, champion, retired, failed), features
--                      and weights, calibration bins, metrics, the activation gate's result, who promoted it and when
--   ml_training_rows   the rows each version was trained and validated on (reproducible; features only, no personal data)
--   ml_features(...)   the features of one lead for one candidate partner. Never used: name, phone, email, chat text,
--                      city or anything that could stand in for a protected attribute.
--   settings 'ml'      min_outcomes 500, min_partners 2, challenger_share 0.10, ece_fallback 0.08, l2 0.01,
--                      iterations 200, min_feature_rows 10, train_hour_ist 2

insert into b2b.settings (key, value) values ('ml', jsonb_build_object(
  'min_outcomes', 500, 'min_partners', 2, 'challenger_share', 0.10, 'ece_fallback', 0.08, 'l2', 0.01, 'iterations', 200,
  'learning_rate', 0.5, 'min_feature_rows', 10, 'valid_share', 0.2, 'train_hour_ist', 2, 'auto_train', true))
on conflict (key) do nothing;
insert into b2b.settings_versions (key, version, value, reason, actor_type)
select 'ml', 1, s.value, 'initial defaults (M25)', 'system' from b2b.settings s
 where s.key = 'ml' and not exists (select 1 from b2b.settings_versions v where v.key = 'ml');

create table if not exists b2b.ml_models (
  id            bigint generated always as identity primary key,
  version       text not null unique,
  kind          text not null default 'logistic_v1' check (kind in ('logistic_v1')),
  status        text not null default 'training' check (status in ('training', 'shadow', 'challenger', 'champion', 'retired', 'failed')),
  features      jsonb not null default '[]',     -- vocabulary
  weights       jsonb not null default '{}',     -- feature -> coefficient, plus "(bias)"
  calibration   jsonb not null default '[]',     -- [{upto: raw score, p: calibrated}] ascending
  metrics       jsonb not null default '{}',
  gate          jsonb not null default '{}',
  trained_on    jsonb not null default '{}',
  error         text,
  requested_by  text,
  created_at    timestamptz not null default now(),
  trained_at    timestamptz,
  status_at     timestamptz not null default now(),
  status_by     text,
  status_reason text,
  was_champion  boolean not null default false
);
create unique index if not exists ml_models_one_champion on b2b.ml_models ((true)) where status = 'champion';
create unique index if not exists ml_models_one_challenger on b2b.ml_models ((true)) where status = 'challenger';
create unique index if not exists ml_models_one_shadow on b2b.ml_models ((true)) where status = 'shadow';
create unique index if not exists ml_models_one_training on b2b.ml_models ((true)) where status = 'training';

create table if not exists b2b.ml_training_rows (
  model_id       bigint not null references b2b.ml_models (id),
  allocation_id  bigint not null,
  split          text not null check (split in ('train', 'valid')),
  y              smallint not null check (y in (0, 1)),
  x              jsonb not null,
  baseline_p     numeric(6, 5),
  decision_id    bigint,
  primary key (model_id, allocation_id)
);

do $rls$
declare t text;
begin
  foreach t in array array['ml_models', 'ml_training_rows'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

/* The lead's side of the features (privacy-safe buckets). */
create or replace function b2b.ml_lead_features(l public.student_leads)
returns jsonb language sql stable set search_path = '' as $fn$
  with b as (
    select
      case when lower(coalesce(l.lead_source, '') || ' ' || coalesce(l.channel, '')) ~ '(whatsapp|witty)' then 'whatsapp'
           when lower(coalesce(l.lead_source, '') || ' ' || coalesce(l.utm_source, '')) ~ '(meta|facebook|instagram|fb)' then 'meta'
           when lower(coalesce(l.lead_source, '') || ' ' || coalesce(l.utm_source, '')) ~ 'google' then 'google'
           when lower(coalesce(l.lead_source, '')) ~ 'import' then 'import'
           when lower(coalesce(l.lead_source, '')) ~ '(referr|influenc|partner)' then 'referral'
           when lower(coalesce(l.lead_source, '')) ~ '(web|site|organic|seo|form)' then 'website'
           else 'other' end src,
      case when upper(coalesce(l.lead_status, '')) in ('HOT', 'WARM', 'COLD') then upper(l.lead_status) else 'NA' end st,
      coalesce(b2b.lead_interest(l) ->> 'level', 'NA') lvl,
      coalesce(b2b.lead_interest(l) ->> 'mode', 'NA') md,
      case when l.work_experience_years_num is null then 'NA' when l.work_experience_years_num < 1 then '0'
           when l.work_experience_years_num < 3 then '1-3' when l.work_experience_years_num < 7 then '3-7' else '7+' end exp,
      case when l.annual_budget_inr is null then 'NA' when l.annual_budget_inr < 100000 then 'lt1L' when l.annual_budget_inr < 200000 then '1-2L'
           when l.annual_budget_inr < 400000 then '2-4L' else '4L+' end bud,
      lower(coalesce(l.enrollment_timeline, '')) ~ '(immediate|asap|this month|next month|1 month|within a month|now)' soon,
      lower(coalesce(l.enquirer_relation, '')) ~ '(parent|father|mother|guardian)' parent,
      extract(hour from l.created_at at time zone 'Asia/Kolkata')::int hr,
      extract(isodow from l.created_at at time zone 'Asia/Kolkata')::int dow,
      lower(coalesce(l.preferred_language, '')) ~ '(hindi|hinglish)' hindi,
      coalesce(jsonb_typeof(l.click_ids) = 'object' and l.click_ids <> '{}', false) or lower(coalesce(l.utm_medium, '')) ~ '(cpc|paid|ppc)' paid)
  select jsonb_strip_nulls(jsonb_build_object(
    'src:' || b.src, 1, 'status:' || b.st, 1, 'level:' || b.lvl, 1, 'mode:' || b.md, 1, 'exp:' || b.exp, 1, 'budget:' || b.bud, 1,
    'soon', case when b.soon then 1 end, 'parent', case when b.parent then 1 end, 'hindi', case when b.hindi then 1 end,
    'paid', case when b.paid then 1 end, 'weekend', case when b.dow >= 6 then 1 end,
    'hour:' || case when b.hr between 6 and 11 then 'morning' when b.hr between 12 and 16 then 'afternoon' when b.hr between 17 and 21 then 'evening' else 'night' end, 1,
    'score', case when l.lead_score is not null then round(least(greatest(l.lead_score, 0), 100) / 100.0, 3) end,
    '_src', b.src, '_lvl', b.lvl))
  from b;
$fn$;

/* Features of one lead for one candidate partner: the lead's buckets, the partner, partner x source and partner x level
   interactions, the partner's segment P̂ (log-odds) and SLA compliance as logged with the candidate. */
create or replace function b2b.ml_features(p_lead jsonb, p_partner_id bigint, p_cand jsonb)
returns jsonb language sql immutable set search_path = '' as $fn$
  select (p_lead - '_src' - '_lvl') || jsonb_build_object(
    'p:' || p_partner_id, 1,
    'p:' || p_partner_id || '|src:' || coalesce(p_lead ->> '_src', 'other'), 1,
    'p:' || p_partner_id || '|level:' || coalesce(p_lead ->> '_lvl', 'NA'), 1,
    'p_logit', round(ln(least(greatest(coalesce((p_cand ->> 'p_hat')::numeric, 0.05), 0.001), 0.999)
                         / (1 - least(greatest(coalesce((p_cand ->> 'p_hat')::numeric, 0.05), 0.001), 0.999))), 4),
    'sla', round(coalesce((p_cand ->> 'sla_compliance')::numeric, 0.8), 4))
  || case when p_cand ->> 'sla_compliance' is null then '{"sla_missing":1}'::jsonb else '{}'::jsonb end;
$fn$;

/* Raw and calibrated P(enrol) of one feature vector under one model. */
create or replace function b2b.ml_predict(p_weights jsonb, p_calibration jsonb, p_x jsonb)
returns jsonb language sql immutable set search_path = '' as $fn$
  with s as (select coalesce((p_weights ->> '(bias)')::float8, 0)
                    + coalesce(sum(coalesce((p_weights ->> f.key)::float8, 0) * f.value::float8), 0) z
               from jsonb_each_text(p_x) f where f.value ~ '^-?[0-9.]+(e-?[0-9]+)?$'),
       r as (select 1 / (1 + exp(-least(greatest(s.z, -30), 30))) raw from s)
  select jsonb_build_object('raw', round(r.raw::numeric, 6),
    -- calibration bins hold scores rounded to 6 places (as training stored them), so compare the rounded score
    'p', round(coalesce((select (c ->> 'p')::numeric from jsonb_array_elements(p_calibration) c where (c ->> 'upto')::numeric >= round(r.raw::numeric, 6)
                          order by (c ->> 'upto')::numeric limit 1),
                        (select (c ->> 'p')::numeric from jsonb_array_elements(p_calibration) c order by (c ->> 'upto')::float8 desc limit 1),
                        r.raw::numeric), 6))
  from r;
$fn$;

revoke execute on function b2b.ml_lead_features(public.student_leads), b2b.ml_features(jsonb, bigint, jsonb), b2b.ml_predict(jsonb, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function b2b.ml_lead_features(public.student_leads), b2b.ml_features(jsonb, bigint, jsonb), b2b.ml_predict(jsonb, jsonb, jsonb)
  to service_role;
