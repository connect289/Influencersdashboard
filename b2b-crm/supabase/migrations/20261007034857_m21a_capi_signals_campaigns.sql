-- M21a: conversion signals ranked by lead quality, and the ad campaign behind every lead (spec B11; Vikas, 7 Oct).
-- Paid leads only: CAPI reports a lead to Meta or Google only when that platform's paid ad brought it (a non-organic lead
-- form, or an ad click ID), so the platforms learn which campaigns bring students who enrol.
-- Signals, strongest first: enrolled (verified) → applicant → interested → qualified. Each carries a value in rupees:
-- the enrolment's expected (then realised) commission, and for earlier signals a share of the lead's expected commission
-- (settings capi.values; base: the allocation's commission per enrolment, else capi.base_value_inr).
--   lead_campaigns          one row per lead and enquiry cycle: platform, paid or not, campaign / ad set / ad, form, UTM
--   lead_campaign_detect    finds the first paid touch of the cycle (ad lead forms, touchpoints incl. Witty's click, the lead)
--   lead_campaign_sync      stores it
--   capi_milestones         now: qualified, interested, applied, enrolled, verified (+ lead, accepted, contacted, junk)

alter table b2b.conversion_events drop constraint if exists conversion_events_stage_check;
alter table b2b.conversion_events add constraint conversion_events_stage_check
  check (stage in ('lead', 'ready_to_route', 'qualified', 'partner_accepted', 'contacted', 'interested', 'applied', 'enrolled', 'verified', 'disqualified'));
alter table b2b.conversion_events add column if not exists campaign_id text;
alter table b2b.conversion_events add column if not exists campaign_name text;
create index if not exists conversion_events_campaign_idx on b2b.conversion_events (platform, campaign_id);

create table if not exists b2b.lead_campaigns (
  lead_id        bigint not null,
  cycle_no       int not null default 1,
  platform       text not null check (platform in ('meta', 'google', 'other', 'none')),
  paid           boolean not null,
  matchable      boolean not null,
  origin         text,
  campaign_id    text,
  campaign_name  text,
  adset_id       text,
  adset_name     text,
  ad_id          text,
  ad_name        text,
  form_id        text,
  utm_source     text,
  utm_medium     text,
  utm_campaign   text,
  utm_content    text,
  utm_term       text,
  click_key      text,
  touched_at     timestamptz,
  updated_at     timestamptz not null default now(),
  primary key (lead_id, cycle_no)
);
create index if not exists lead_campaigns_campaign_idx on b2b.lead_campaigns (platform, campaign_id, touched_at) where paid;
alter table b2b.lead_campaigns enable row level security;
do $do$ begin
  if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = 'lead_campaigns' and policyname = 'admin_read') then
    create policy admin_read on b2b.lead_campaigns for select to authenticated using ((select b2b.is_admin()));
  end if;
end $do$;
revoke all on b2b.lead_campaigns from anon, authenticated;
grant select on b2b.lead_campaigns to authenticated;
grant all on b2b.lead_campaigns to service_role;

-- settings: the new signals in the maps (strong signals on, weak ones off), values per signal
do $do$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'capi'), '{}');
begin
  if not (s -> 'meta' -> 'map') ? 'interested' then
    s := jsonb_set(s, '{meta,map}', coalesce(s -> 'meta' -> 'map', '{}') || jsonb_build_object(
           'qualified',        jsonb_build_object('event', coalesce(s -> 'meta' -> 'map' -> 'ready_to_route' ->> 'event', 'Qualified Lead'), 'enabled', true),
           'interested',       jsonb_build_object('event', 'Interested', 'enabled', true),
           'applied',          jsonb_build_object('event', 'Applicant', 'enabled', true),
           'ready_to_route',   jsonb_build_object('event', 'Ready to route', 'enabled', false),
           'partner_accepted', jsonb_build_object('event', 'Sales Accepted Lead', 'enabled', false),
           'contacted',        jsonb_build_object('event', 'Contacted', 'enabled', false)));
    s := jsonb_set(s, '{google,map}', coalesce(s -> 'google' -> 'map', '{}') || jsonb_build_object(
           'qualified',        jsonb_build_object('action', s -> 'google' -> 'map' -> 'ready_to_route' -> 'action', 'enabled', true),
           'interested',       jsonb_build_object('action', null, 'enabled', true),
           'ready_to_route',   jsonb_build_object('action', null, 'enabled', false),
           'partner_accepted', jsonb_build_object('action', null, 'enabled', false),
           'contacted',        jsonb_build_object('action', null, 'enabled', false)));
    s := s || jsonb_build_object('values', jsonb_build_object('qualified', 0.05, 'interested', 0.15, 'applied', 0.4), 'base_value_inr', 15000);
    perform b2b.set_setting('capi', s, 'm21a: signals ranked enrolled > applicant > interested > qualified, with values; weak signals off');
  end if;
end $do$;

-- ---------- milestones ----------
/* The lead's milestones in its current cycle, each with its time and value. Read from the shared tables, so stage changes
   written by the B2C CRM or a partner count as much as the B2B CRM's own.
   qualified   routed to a partner or to B2C sales (not the nurture lane, not junk)
   interested  counselled or further (stage rank 60+), as reported by the partner or the B2C CRM; an application implies it
   applied, enrolled (value: expected commission), verified (value: realised commission) */
create or replace function b2b.capi_milestones(l public.student_leads)
returns table (stage text, at timestamptz, value_inr numeric)
language sql stable security definer set search_path = '' as $fn$
  with c as (select coalesce(l.cycle_no, 1) cyc, coalesce(l.reopened_at, l.created_at) cycle_start),
  cfg as (select coalesce((select value from b2b.settings where key = 'capi'), '{}') v),
  st as (select e ->> 'key' k, (e ->> 'rank')::int r from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages'),
  a as (select min(x.created_at) filter (where x.destination_type = 'partner' or coalesce(x.b2c_lane, 'sales') = 'sales') qualified,
               min(coalesce(x.accepted_at, case when x.destination_type <> 'partner' and x.status = 'handed_off' then x.created_at end))
                 filter (where x.status in ('accepted', 'handed_off') or x.accepted_at is not null) accepted,
               (array_agg(x.cpe_net_inr order by x.created_at desc) filter (where x.cpe_net_inr is not null))[1] cpe
          from b2b.allocations x, c where x.lead_id = l.id and x.cycle_no = c.cyc),
  pa as (select min(p.occurred_at) at from b2b.partner_activities p join b2b.allocations x on x.id = p.allocation_id, c
          where x.lead_id = l.id and x.cycle_no = c.cyc and p.kind = 'stage_change'
            and p.outcome in (select k from st where r between 60 and 998)),
  e as (select min(x.created_at) filter (where x.status in ('reported', 'verified')) reported,
               (array_agg(x.expected_net_revenue_inr order by x.created_at) filter (where x.status in ('reported', 'verified')))[1] expected,
               min(x.verified_at) filter (where x.status = 'verified') verified,
               (array_agg(x.realised_net_revenue_inr order by x.verified_at) filter (where x.status = 'verified'))[1] realised
          from public.enrollments x, c where x.lead_id = l.id and coalesce(x.cycle_no, 1) = c.cyc),
  np as (select n.decided_at from b2b.not_passed n where n.lead_id = l.id and n.reason = 'junk' and n.passed_at is null),
  t as (select c.cycle_start,
               case when l.applied_at >= c.cycle_start then l.applied_at end applied,
               coalesce(e.reported, case when l.enrollment_status is not null and l.enrollment_status not in ('cancelled') and l.enrollment_date is not null
                                         then greatest(l.enrollment_date::timestamptz, c.cycle_start) end) enrolled,
               coalesce(a.cpe, nullif(cfg.v ->> 'base_value_inr', '')::numeric, 15000) base,
               coalesce(cfg.v -> 'values', '{}') w
          from c, cfg, a, e),
  m as (
    select 'lead' stage, t.cycle_start at, null::numeric value_inr from t
    union all select 'qualified', a.qualified, round(coalesce((t.w ->> 'qualified')::numeric, 0.05) * t.base, 2) from a, t
    union all select 'partner_accepted', a.accepted, null from a
    union all select 'contacted', case when l.first_contacted_at >= t.cycle_start then l.first_contacted_at end, null from t
    union all select 'interested', least(pa.at,
                                         case when (select r from st where k = l.stage) between 60 and 998 and l.stage_changed_at >= t.cycle_start then l.stage_changed_at end,
                                         t.applied, t.enrolled),
                                   round(coalesce((t.w ->> 'interested')::numeric, 0.15) * t.base, 2) from pa, t
    union all select 'applied', t.applied, round(coalesce((t.w ->> 'applied')::numeric, 0.4) * t.base, 2) from t
    union all select 'enrolled', t.enrolled, coalesce(e.expected, l.expected_net_revenue_inr, t.base) from t, e
    union all select 'verified', coalesce(e.verified, case when l.enrollment_verified_at >= t.cycle_start then l.enrollment_verified_at end),
                                 coalesce(e.realised, l.realised_net_revenue_inr) from e, t
    union all select 'disqualified', (select decided_at from np), null)
  select m.stage, m.at, m.value_inr from m where m.at is not null;
$fn$;

-- ---------- the ad campaign behind a lead ----------
/* Which paid ad brought the lead in its current cycle: the first paid touch (a non-organic Meta lead form, a Google lead
   form, or an ad click: fbclid / fbc / gclid / gbraid / wbraid), else the first touch with campaign or UTM information
   (paid = false). Sources: the ad platforms' lead forms (campaign, ad set and ad), touchpoints (the API, imports, the
   website, Witty's click), then the lead row. matchable: the platform can tie the lead to its ad. */
create or replace function b2b.lead_campaign_detect(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  -- a reopened lead's cycle starts at its new enquiry (an ad's own time can be a little earlier); a new lead has one cycle
  v_start timestamptz := coalesce(l.reopened_at - interval '1 hour', '-infinity'::timestamptz);
  c jsonb;
  ck jsonb;
  u jsonb;
  v_med text;
  v_src text;
  v_meta boolean;
  v_google boolean;
  v_platform text;
  v_paid boolean;
  first_info jsonb;
  v_organic text[] := '{}';
begin
  for c in
    select x from (
      -- ad platform lead forms
      select jsonb_build_object('at', coalesce(b2b.try_timestamptz(q.raw -> 'graph' ->> 'created_time') - interval '1 second', q.received_at), 'origin', case q.source when 'meta' then 'meta_lead_form' else 'google_lead_form' end,
               'ck', case q.source when 'meta' then jsonb_strip_nulls(jsonb_build_object('leadgen_id', q.idempotency_key,
                                                        'organic', coalesce(q.raw -> 'graph' ->> 'is_organic', q.raw ->> 'is_organic')))
                                 else jsonb_strip_nulls(jsonb_build_object('google_lead_id', q.idempotency_key, 'gclid', q.raw ->> 'gcl_id')) end,
               'campaign_id', coalesce(q.raw -> 'graph' ->> 'campaign_id', q.raw ->> 'campaign_id'),
               'campaign_name', coalesce(q.raw -> 'graph' ->> 'campaign_name', q.raw ->> 'campaign_name'),
               'adset_id', coalesce(q.raw -> 'graph' ->> 'adset_id', q.raw ->> 'adgroup_id'),
               'adset_name', q.raw -> 'graph' ->> 'adset_name',
               'ad_id', coalesce(q.raw -> 'graph' ->> 'ad_id', q.raw ->> 'creative_id', q.raw ->> 'ad_id'), 'ad_name', q.raw -> 'graph' ->> 'ad_name',
               'form_id', q.form_ref,
               'utm', jsonb_build_object('source', case q.source when 'meta' then case lower(coalesce(q.raw -> 'graph' ->> 'platform', '')) when 'ig' then 'instagram' else 'facebook' end
                                                   else 'google' end,
                                         'medium', case q.source when 'meta' then 'paid_social' else 'cpc' end)) x,
             coalesce(b2b.try_timestamptz(q.raw -> 'graph' ->> 'created_time') - interval '1 second', q.received_at) at
        from b2b.intake_requests q
       where q.lead_id = l.id and q.source in ('meta', 'google') and q.status = 'done' and q.received_at >= v_start
      union all
      -- every touch: API, imports, website, Witty (its click's UTM and click IDs)
      select jsonb_build_object('at', t.occurred_at, 'origin', coalesce(t.source_system, 'touchpoint'),
               'ck', coalesce(t.attribution -> 'click_ids', '{}') || coalesce(t.payload -> 'click_ids', '{}')
                     || jsonb_strip_nulls(jsonb_build_object('organic', t.attribution ->> 'organic')),
               'campaign_id', coalesce(t.attribution ->> 'campaign_id', t.payload -> 'click_ids' ->> 'campaign_id', t.payload ->> 'utm_id', t.attribution ->> 'utm_id'),
               'campaign_name', coalesce(nullif(t.campaign, ''), nullif(t.attribution ->> 'campaign', ''), t.payload ->> 'campaign'),
               'adset_id', coalesce(t.attribution ->> 'adset_id', t.payload -> 'click_ids' ->> 'adset_id', t.payload -> 'click_ids' ->> 'adgroup_id'),
               'ad_id', coalesce(t.attribution ->> 'ad_id', t.payload -> 'click_ids' ->> 'ad_id', t.payload -> 'click_ids' ->> 'creative_id'),
               'form_id', coalesce(t.attribution ->> 'form_id', t.payload -> 'click_ids' ->> 'form_id'),
               'utm', jsonb_build_object(
                 'source', coalesce(t.payload ->> 'utm_source', t.payload -> 'utm' ->> 'source', t.attribution ->> 'utm_source'),
                 'medium', coalesce(t.payload ->> 'utm_medium', t.payload -> 'utm' ->> 'medium', t.attribution ->> 'utm_medium'),
                 'campaign', coalesce(t.payload ->> 'utm_campaign', t.payload -> 'utm' ->> 'campaign', t.attribution ->> 'utm_campaign'),
                 'content', coalesce(t.payload ->> 'utm_content', t.payload -> 'utm' ->> 'content', t.attribution ->> 'utm_content'),
                 'term', coalesce(t.payload ->> 'utm_term', t.payload -> 'utm' ->> 'term', t.attribution ->> 'utm_term'))), t.occurred_at
        from public.touchpoints t
       where t.lead_id = l.id and t.occurred_at >= v_start
      union all
      -- the lead row (its first touch)
      select jsonb_build_object('at', l.created_at, 'origin', 'lead', 'ck', coalesce(l.click_ids, '{}'), 'campaign_name', nullif(l.campaign, ''),
               'campaign_id', l.click_ids ->> 'campaign_id', 'adset_id', l.click_ids ->> 'adset_id', 'ad_id', l.click_ids ->> 'ad_id', 'form_id', l.click_ids ->> 'form_id',
               'utm', jsonb_build_object('source', l.utm_source, 'medium', l.utm_medium, 'campaign', l.utm_campaign, 'content', l.utm_content, 'term', l.utm_term)),
             'infinity'::timestamptz) y(x, at)
     order by at
  loop
    ck := coalesce(c -> 'ck', '{}');
    -- a lead form Meta marks organic stays organic in every later copy of its leadgen ID (touchpoint, lead row)
    if ck ? 'leadgen_id' then
      if lower(coalesce(ck ->> 'organic', 'false')) in ('true', '1') then v_organic := v_organic || (ck ->> 'leadgen_id');
      elsif ck ->> 'leadgen_id' = any (v_organic) then ck := ck || '{"organic": "true"}'; end if;
    end if;
    u := jsonb_strip_nulls(coalesce(c -> 'utm', '{}'));
    v_med := lower(coalesce(u ->> 'medium', ''));
    v_src := lower(coalesce(u ->> 'source', ''));
    v_meta := (ck ? 'leadgen_id' and lower(coalesce(ck ->> 'organic', 'false')) not in ('true', '1')) or ck ? 'fbclid' or ck ? 'fbc';
    v_google := ck ?| array['gclid', 'gbraid', 'wbraid', 'google_lead_id'];
    v_platform := case when v_meta or ck ? 'leadgen_id' or v_src in ('facebook', 'fb', 'instagram', 'ig', 'meta', 'messenger', 'an', 'audience_network') then 'meta'
                       when v_google or v_src in ('google', 'youtube', 'gdn', 'adwords', 'google_ads', 'googleads') then 'google'
                       when v_src <> '' or c ->> 'campaign_name' is not null then 'other' end;
    v_paid := v_meta or v_google
              or (v_platform in ('meta', 'google', 'other') and not ck ? 'leadgen_id'
                  and v_med in ('cpc', 'ppc', 'paid', 'paid_social', 'paidsocial', 'paid-social', 'social_paid', 'cpm', 'display', 'paid_search', 'paidsearch', 'sem', 'ads'));
    if v_platform is not null and first_info is null then
      first_info := c || jsonb_build_object('platform', v_platform, 'paid', false, 'matchable', false);
    end if;
    if v_paid then
      return c || jsonb_build_object('platform', v_platform, 'paid', true, 'matchable', v_meta or v_google,
                                     'click_key', case when ck ? 'leadgen_id' then 'leadgen_id' when ck ? 'fbclid' then 'fbclid' when ck ? 'fbc' then 'fbc'
                                                       when ck ? 'google_lead_id' then 'google_lead_id' when ck ? 'gclid' then 'gclid'
                                                       when ck ? 'gbraid' then 'gbraid' when ck ? 'wbraid' then 'wbraid' end);
    end if;
  end loop;
  return coalesce(first_info, jsonb_build_object('platform', 'none', 'paid', false, 'matchable', false));
end $fn$;

create or replace function b2b.lead_campaign_sync(l public.student_leads)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  d jsonb := b2b.lead_campaign_detect(l);
  u jsonb := coalesce(d -> 'utm', '{}');
begin
  insert into b2b.lead_campaigns (lead_id, cycle_no, platform, paid, matchable, origin, campaign_id, campaign_name, adset_id, adset_name, ad_id, ad_name, form_id,
                                  utm_source, utm_medium, utm_campaign, utm_content, utm_term, click_key, touched_at, updated_at)
  values (l.id, coalesce(l.cycle_no, 1), d ->> 'platform', (d ->> 'paid')::boolean, (d ->> 'matchable')::boolean, d ->> 'origin',
          left(d ->> 'campaign_id', 60), left(coalesce(d ->> 'campaign_name', u ->> 'campaign'), 200), left(d ->> 'adset_id', 60), left(d ->> 'adset_name', 200),
          left(d ->> 'ad_id', 60), left(d ->> 'ad_name', 200), left(d ->> 'form_id', 60), left(u ->> 'source', 80), left(u ->> 'medium', 80),
          left(u ->> 'campaign', 200), left(u ->> 'content', 200), left(u ->> 'term', 200), d ->> 'click_key',
          case when d ->> 'at' is not null and d ->> 'at' <> 'infinity' then (d ->> 'at')::timestamptz else l.created_at end, now())
  on conflict (lead_id, cycle_no) do update
    set platform = excluded.platform, paid = excluded.paid, matchable = excluded.matchable, origin = excluded.origin, campaign_id = excluded.campaign_id,
        campaign_name = excluded.campaign_name, adset_id = excluded.adset_id, adset_name = excluded.adset_name, ad_id = excluded.ad_id, ad_name = excluded.ad_name,
        form_id = excluded.form_id, utm_source = excluded.utm_source, utm_medium = excluded.utm_medium, utm_campaign = excluded.utm_campaign,
        utm_content = excluded.utm_content, utm_term = excluded.utm_term, click_key = excluded.click_key, touched_at = excluded.touched_at, updated_at = now()
    where (b2b.lead_campaigns.platform, b2b.lead_campaigns.paid, b2b.lead_campaigns.campaign_id, b2b.lead_campaigns.campaign_name, b2b.lead_campaigns.ad_id)
          is distinct from (excluded.platform, excluded.paid, excluded.campaign_id, excluded.campaign_name, excluded.ad_id);
  return d;
end $fn$;

revoke execute on function b2b.lead_campaign_detect(public.student_leads), b2b.lead_campaign_sync(public.student_leads) from public, anon, authenticated;
grant execute on function b2b.lead_campaign_detect(public.student_leads), b2b.lead_campaign_sync(public.student_leads) to service_role;
