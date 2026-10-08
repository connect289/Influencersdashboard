-- M31g: Addendum 3 attribution (docs/B2B_CRM_ADDENDUM_3.md Definitions 'Paid leads', Changes table rows 'paid-campaign
-- leads' and 'paid detection by utm_medium'; design D38; review findings C64 and C126).
-- 'Paid' is a Meta/Google-only attribution label (b2b.lead_attribution, m31b), shared by routing labels, CAPI, the campaign
-- report and analytics. It has no routing effect any more.
--   is_enrolled_status        (new)            which enrollment_status values count as an enrolment (C64)
--   capi_milestones           (m21a, replaced) 'qualified' comes from the lead's class, a consent request or the first partner
--                                              allocation; nurture hand-offs no longer delay or block it; 'enrolled' uses
--                                              is_enrolled_status
--   lead_campaign_detect      (m21a, replaced) paid, platform, signal and label from lead_attribution; campaign ids and names
--                                              extracted from the same touches as before
--   paid_signal               (m7a, replaced)  the attribution label when paid, else null (engine.paid_rule is not read)
--   handoff_settings_save     (m7c, replaced)  b2c_sources, blocked_phones, junk_capi_signal and spam {…}; paid_rule refused
--   attribution_settings_save (new)            Admin save of the 'attribution' setting (markers, excluded campaigns, Meta ad
--                                              parameters), merged key by key under a row lock (C126)
--   attribution_list_clean    (new)            the list validator the save uses
-- Data: lead_campaigns re-synced for every non-deleted lead (batches of 500), conversion events still queued for leads that
-- are no longer paid become 'skipped' ('not paid under Addendum 3'), then refresh_facts().
-- Deploy note (design m31g (6)): apply with the live switches capi_meta and capi_google OFF, so nothing is sent while the
-- labels flip; the data step raises a NOTICE when either is on. Nothing here touches public.student_leads or Witty tables.

-- ---------- enrolment status (C64) ----------
/* B2B writes 'reported', 'verified', 'cancelled', 'refunded'; partner mappings may write 'pending' or 'enrolled'; the B2C
   link writes free text. Only these four mean the student enrolled ('pending' does not). Used by capi_milestones and by the
   fact_leads view (pending/m31n_facts). */
create or replace function b2b.is_enrolled_status(p text)
returns boolean language sql immutable set search_path = '' as $fn$
  select coalesce(lower(trim(p)) in ('reported', 'verified', 'enrolled', 'refunded'), false);
$fn$;

-- ---------- milestones (m21a, replaced) ----------
/* The lead's milestones in its current cycle, each with its time and value. Read from the shared tables, so stage changes
   written by the B2C CRM or a partner count as much as the B2B CRM's own.
   qualified   the earliest of: an engine decision with class 'qualified' that sent the lead to a partner or to B2C sales;
               a partner-sharing consent request (R8 asks only for qualified leads); the first partner allocation.
               Nurture hand-offs (not_qualified, consent_no_answer, partner_lost) neither delay nor block it.
   interested  counselled or further (stage rank 60+), as reported by the partner or the B2C CRM; an application implies it
   applied, enrolled (value: expected commission), verified (value: realised commission) */
create or replace function b2b.capi_milestones(l public.student_leads)
returns table (stage text, at timestamptz, value_inr numeric)
language sql stable security definer set search_path = '' as $fn$
  with c as (select coalesce(l.cycle_no, 1) cyc, coalesce(l.reopened_at, l.created_at) cycle_start),
  cfg as (select coalesce((select value from b2b.settings where key = 'capi'), '{}') v),
  st as (select e ->> 'key' k, (e ->> 'rank')::int r from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages'),
  a as (select min(coalesce(x.accepted_at, case when x.destination_type <> 'partner' and x.status = 'handed_off' then x.created_at end))
                 filter (where x.status in ('accepted', 'handed_off') or x.accepted_at is not null) accepted,
               min(x.created_at) filter (where x.destination_type = 'partner') first_partner,
               (array_agg(x.cpe_net_inr order by x.created_at desc) filter (where x.cpe_net_inr is not null))[1] cpe
          from b2b.allocations x, c where x.lead_id = l.id and x.cycle_no = c.cyc),
  q as (select least(
               (select min(d.created_at) from b2b.engine_decisions d, c
                 where d.lead_id = l.id and d.cycle_no = c.cyc and d.class = 'qualified'
                   and (d.destination_type = 'partner' or coalesce(d.b2c_lane, 'sales') = 'sales')),
               (select min(cr.created_at) from b2b.consent_requests cr, c where cr.lead_id = l.id and cr.cycle_no = c.cyc),
               a.first_partner) qualified
          from a),
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
               coalesce(e.reported, case when b2b.is_enrolled_status(l.enrollment_status) and l.enrollment_date is not null
                                         then greatest(l.enrollment_date::timestamptz, c.cycle_start) end) enrolled,
               coalesce(a.cpe, nullif(cfg.v ->> 'base_value_inr', '')::numeric, 15000) base,
               coalesce(cfg.v -> 'values', '{}') w
          from c, cfg, a, e),
  m as (
    select 'lead' stage, t.cycle_start at, null::numeric value_inr from t
    union all select 'qualified', q.qualified, round(coalesce((t.w ->> 'qualified')::numeric, 0.05) * t.base, 2) from q, t
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

-- ---------- the ad campaign behind a lead (m21a, replaced) ----------
/* Which ad brought the lead in its current cycle. paid, platform, signal and label come from b2b.lead_attribution (Meta and
   Google only; influencer/referral markers and excluded campaigns are never paid; UTM tags alone are not paid). The campaign,
   ad set, ad, form and UTM details are taken from the same touches as before (the ad platforms' lead forms, touchpoints incl.
   Witty's click, then the lead row): for a paid lead the first touch carrying the paid platform's click key (leadgen_id,
   fbclid, fbc, ctwa_clid; google_lead_id, gclid, gbraid, wbraid), else the first touch with any platform or campaign
   information, else the lead row. matchable: the touch carries an identifier CAPI can send (capi_ids) — ctwa_clid is not one.
   Keys: at / touched_at, origin, kind, ck / click_ids, campaign_id, campaign_name, adset_id, adset_name, ad_id, ad_name, form_id,
   utm {source, medium, campaign, content, term}, platform, paid, matchable, click_key, signal, label, is_organic, leadgen_id,
   google_lead_id. */
create or replace function b2b.lead_campaign_detect(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_attr jsonb := b2b.lead_attribution(l);
  v_paid boolean := coalesce((v_attr ->> 'paid')::boolean, false);
  v_platform text := coalesce(v_attr ->> 'platform', 'none');
  -- a reopened lead's cycle starts at its new enquiry (an ad's own time can be a little earlier); a new lead has one cycle
  v_start timestamptz := coalesce(l.reopened_at - interval '1 hour', '-infinity'::timestamptz);
  v_rows jsonb[] := '{}';
  v_organic text[] := '{}';
  c jsonb;
  ck jsonb;
  u jsonb;
  v_url text;
  v_key text;
  v_pick jsonb;
  v_pick_key text;
  v_first_info jsonb;
  v_lead_row jsonb;
  v_leadgen text;
  v_google_id text;
  v_match boolean;
begin
  for c in
    select x from (
      -- ad platform lead forms
      select jsonb_build_object('at', coalesce(b2b.try_timestamptz(q.raw -> 'graph' ->> 'created_time') - interval '1 second', q.received_at),
               'origin', case q.source when 'meta' then 'meta_lead_form' else 'google_lead_form' end, 'kind', q.source,
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
                                         'medium', case q.source when 'meta' then 'paid_social' else 'cpc' end),
               'url', null::text) x,
             coalesce(b2b.try_timestamptz(q.raw -> 'graph' ->> 'created_time') - interval '1 second', q.received_at) at, 1 ord
        from b2b.intake_requests q
       where q.lead_id = l.id and q.source in ('meta', 'google') and q.status = 'done' and q.received_at >= v_start
      union all
      -- every touch: API, imports, website, Witty (its click's UTM and click IDs)
      select jsonb_build_object('at', t.occurred_at, 'origin', coalesce(t.source_system, 'touchpoint'), 'kind', 'touchpoint',
               'ck', (case when jsonb_typeof(t.attribution -> 'click_ids') = 'object' then t.attribution -> 'click_ids' else '{}'::jsonb end)
                     || (case when jsonb_typeof(t.payload -> 'click_ids') = 'object' then t.payload -> 'click_ids' else '{}'::jsonb end)
                     || jsonb_strip_nulls(jsonb_build_object('organic', t.attribution ->> 'organic', 'ctwa_clid', t.attribution ->> 'ctwa_clid')),
               'campaign_id', coalesce(t.attribution ->> 'campaign_id', t.payload -> 'click_ids' ->> 'campaign_id', t.payload ->> 'utm_id', t.attribution ->> 'utm_id'),
               'campaign_name', coalesce(nullif(t.campaign, ''), nullif(t.attribution ->> 'campaign', ''), t.payload ->> 'campaign'),
               'adset_id', coalesce(t.attribution ->> 'adset_id', t.payload -> 'click_ids' ->> 'adset_id', t.payload -> 'click_ids' ->> 'adgroup_id'),
               'adset_name', null::text,
               'ad_id', coalesce(t.attribution ->> 'ad_id', t.payload -> 'click_ids' ->> 'ad_id', t.payload -> 'click_ids' ->> 'creative_id'),
               'ad_name', null::text,
               'form_id', coalesce(t.attribution ->> 'form_id', t.payload -> 'click_ids' ->> 'form_id'),
               'utm', jsonb_build_object(
                 'source', coalesce(t.payload ->> 'utm_source', t.payload -> 'utm' ->> 'source', t.attribution ->> 'utm_source'),
                 'medium', coalesce(t.payload ->> 'utm_medium', t.payload -> 'utm' ->> 'medium', t.attribution ->> 'utm_medium'),
                 'campaign', coalesce(t.payload ->> 'utm_campaign', t.payload -> 'utm' ->> 'campaign', t.attribution ->> 'utm_campaign'),
                 'content', coalesce(t.payload ->> 'utm_content', t.payload -> 'utm' ->> 'content', t.attribution ->> 'utm_content'),
                 'term', coalesce(t.payload ->> 'utm_term', t.payload -> 'utm' ->> 'term', t.attribution ->> 'utm_term')),
               'url', coalesce(t.payload ->> 'landing_url', t.attribution ->> 'landing_url')),
             t.occurred_at, 2
        from public.touchpoints t
       where t.lead_id = l.id and t.occurred_at >= v_start
      union all
      -- the lead row (always last)
      select jsonb_build_object('at', l.created_at, 'origin', 'lead', 'kind', 'lead',
               'ck', case when jsonb_typeof(l.click_ids) = 'object' then l.click_ids else '{}'::jsonb end,
               'campaign_name', nullif(l.campaign, ''),
               'campaign_id', case when jsonb_typeof(l.click_ids) = 'object' then l.click_ids ->> 'campaign_id' end,
               'adset_id', case when jsonb_typeof(l.click_ids) = 'object' then l.click_ids ->> 'adset_id' end, 'adset_name', null::text,
               'ad_id', case when jsonb_typeof(l.click_ids) = 'object' then l.click_ids ->> 'ad_id' end, 'ad_name', null::text,
               'form_id', case when jsonb_typeof(l.click_ids) = 'object' then l.click_ids ->> 'form_id' end,
               'utm', jsonb_build_object('source', l.utm_source, 'medium', l.utm_medium, 'campaign', l.utm_campaign, 'content', l.utm_content, 'term', l.utm_term),
               'url', l.landing_url),
             'infinity'::timestamptz, 3) y(x, at, ord)
     order by at, ord
  loop
    v_rows := array_append(v_rows, c);
    ck := coalesce(c -> 'ck', '{}'::jsonb);
    -- a lead form Meta marks organic stays organic in every copy of its leadgen ID (touchpoint, lead row)
    if ck ? 'leadgen_id' and lower(coalesce(ck ->> 'organic', 'false')) in ('true', '1') then
      v_organic := array_append(v_organic, ck ->> 'leadgen_id');
    end if;
  end loop;

  foreach c in array v_rows loop
    ck := coalesce(c -> 'ck', '{}'::jsonb);
    if ck ? 'leadgen_id' and coalesce((ck ->> 'leadgen_id') = any (v_organic), false) then
      ck := ck || '{"organic": "true"}'::jsonb;
      c := c || jsonb_build_object('ck', ck);
    end if;
    v_url := coalesce(c ->> 'url', '');
    v_leadgen := coalesce(v_leadgen, nullif(ck ->> 'leadgen_id', ''));
    v_google_id := coalesce(v_google_id, nullif(ck ->> 'google_lead_id', ''));
    if c ->> 'origin' = 'lead' then v_lead_row := c; end if;
    -- the paid platform's click key this touch carries
    v_key := case v_platform
      when 'meta' then case
        when ck ? 'leadgen_id' and lower(coalesce(ck ->> 'organic', 'false')) not in ('true', '1') then 'leadgen_id'
        when ck ? 'fbclid' or v_url ~* '[?&]fbclid=' then 'fbclid'
        when ck ? 'fbc' then 'fbc'
        when ck ? 'ctwa_clid' or v_url ~* '[?&]ctwa_clid=' then 'ctwa_clid' end
      when 'google' then case
        when ck ? 'google_lead_id' then 'google_lead_id'
        when ck ? 'gclid' or v_url ~* '[?&]gclid=' then 'gclid'
        when ck ? 'gbraid' or v_url ~* '[?&]gbraid=' then 'gbraid'
        when ck ? 'wbraid' or v_url ~* '[?&]wbraid=' then 'wbraid' end
      end;
    if v_paid and v_pick is null and v_key is not null then
      v_pick := c; v_pick_key := v_key;
    end if;
    -- the first touch with platform or campaign information (the row reported for leads that are not paid)
    if v_first_info is null
       and (c ->> 'kind' in ('meta', 'google')
            or ck ?| array['leadgen_id', 'fbclid', 'fbc', 'ctwa_clid', 'gclid', 'gbraid', 'wbraid', 'google_lead_id']
            or nullif(trim(coalesce(c -> 'utm' ->> 'source', '')), '') is not null
            or nullif(c ->> 'campaign_name', '') is not null or nullif(c ->> 'campaign_id', '') is not null) then
      v_first_info := c;
    end if;
  end loop;

  v_pick := coalesce(v_pick, v_first_info, v_lead_row, '{}'::jsonb);
  ck := coalesce(v_pick -> 'ck', '{}'::jsonb);
  u := coalesce(v_pick -> 'utm', '{}'::jsonb);
  v_match := v_paid and v_pick_key is not null and v_pick_key <> 'ctwa_clid' and ck ? v_pick_key;
  return jsonb_build_object(
    'at', v_pick -> 'at', 'touched_at', v_pick -> 'at',
    'origin', v_pick ->> 'origin', 'kind', v_pick ->> 'kind',
    'ck', ck, 'click_ids', ck,
    'campaign_id', coalesce(nullif(v_pick ->> 'campaign_id', ''), nullif(v_attr ->> 'campaign_id', '')),
    'campaign_name', nullif(v_pick ->> 'campaign_name', ''),
    'adset_id', nullif(v_pick ->> 'adset_id', ''), 'adset_name', nullif(v_pick ->> 'adset_name', ''),
    'ad_id', nullif(v_pick ->> 'ad_id', ''), 'ad_name', nullif(v_pick ->> 'ad_name', ''),
    'form_id', nullif(v_pick ->> 'form_id', ''),
    'utm', u,
    'platform', v_platform, 'paid', v_paid, 'matchable', v_match,
    'click_key', case when v_paid then v_pick_key end,
    'signal', v_attr ->> 'signal', 'label', case when v_paid then v_attr ->> 'label' end,
    'is_organic', (v_attr ->> 'signal') = 'organic_form' or lower(coalesce(ck ->> 'organic', 'false')) in ('true', '1'),
    'leadgen_id', v_leadgen, 'google_lead_id', v_google_id);
end $fn$;

-- ---------- the paid label (m7a, replaced) ----------
/* The paid label of the lead's current enquiry cycle ('Meta Lead Ads', 'Meta click-to-WhatsApp', 'Meta ad click', 'Google
   lead form', 'Google ad click'), null when not paid. Attribution only: it changes no routing decision. */
create or replace function b2b.paid_signal(l public.student_leads)
returns text language sql stable security definer set search_path = '' as $fn$
  select case when coalesce((a ->> 'paid')::boolean, false) then a ->> 'label' end from b2b.lead_attribution(l) a;
$fn$;

-- ---------- hand-off settings (m7c, replaced): B2C-created sources, blocked phones, the junk signal, spam rules ----------
/* Partial update of the engine keys the Hand-off card owns: only the keys given are validated and written. paid_rule is
   refused (paid is an attribution label under Addendum 3; see attribution_settings_save). The engine row is locked before
   the read (C126). */
create or replace function b2b.handoff_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v jsonb;
  k text;
  sp jsonb;
  lst jsonb;
  n int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'hand-off settings must be an object' using errcode = '22023'; end if;
  if p ? 'paid_rule' then raise exception 'paid is an attribution label under Addendum 3' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('b2c_sources', 'blocked_phones', 'junk_capi_signal', 'spam') then
      raise exception 'unknown hand-off setting: %', k using errcode = '22023';
    end if;
  end loop;
  v := b2b.setting_for_update('engine');
  if p ? 'b2c_sources' then
    if jsonb_typeof(p -> 'b2c_sources') <> 'array' then raise exception 'B2C sources must be a list' using errcode = '22023'; end if;
    v := v || jsonb_build_object('b2c_sources', (select coalesce(jsonb_agg(distinct lower(left(trim(x), 60))), '[]'::jsonb)
                                                   from jsonb_array_elements_text(p -> 'b2c_sources') x where trim(x) <> ''));
    n := n + 1;
  end if;
  if p ? 'blocked_phones' then
    if jsonb_typeof(p -> 'blocked_phones') <> 'array' then raise exception 'blocked phones must be a list' using errcode = '22023'; end if;
    if exists (select 1 from jsonb_array_elements_text(p -> 'blocked_phones') x where length(regexp_replace(x, '\D', '', 'g')) not between 10 and 15) then
      raise exception 'each blocked phone needs 10 to 15 digits' using errcode = '22023';
    end if;
    v := v || jsonb_build_object('blocked_phones', (select coalesce(jsonb_agg(distinct regexp_replace(x, '\D', '', 'g')), '[]'::jsonb)
                                                      from jsonb_array_elements_text(p -> 'blocked_phones') x));
    n := n + 1;
  end if;
  if p ? 'junk_capi_signal' then
    if jsonb_typeof(p -> 'junk_capi_signal') <> 'boolean' then raise exception 'the junk signal setting must be on or off' using errcode = '22023'; end if;
    v := v || jsonb_build_object('junk_capi_signal', (p ->> 'junk_capi_signal')::boolean);
    n := n + 1;
  end if;
  if p ? 'spam' then
    if jsonb_typeof(p -> 'spam') <> 'object' then raise exception 'spam settings must be an object' using errcode = '22023'; end if;
    sp := coalesce(case when jsonb_typeof(v -> 'spam') = 'object' then v -> 'spam' end, '{}'::jsonb);
    for k in select jsonb_object_keys(p -> 'spam') loop
      case k
        when 'use_witty_blocks' then
          if jsonb_typeof(p -> 'spam' -> k) <> 'boolean' then raise exception 'spam.use_witty_blocks must be on or off' using errcode = '22023'; end if;
          sp := sp || jsonb_build_object(k, (p -> 'spam' ->> k)::boolean);
        when 'disposable_email_domains' then
          if jsonb_typeof(p -> 'spam' -> k) <> 'array' then raise exception 'spam.disposable_email_domains must be a list' using errcode = '22023'; end if;
          if exists (select 1 from jsonb_array_elements_text(p -> 'spam' -> k) x where trim(x) <> '' and lower(trim(x)) !~ '^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$') then
            raise exception 'spam.disposable_email_domains: each entry is a domain like mailinator.com' using errcode = '22023';
          end if;
          select coalesce(jsonb_agg(distinct lower(trim(x))), '[]'::jsonb) into lst from jsonb_array_elements_text(p -> 'spam' -> k) x where trim(x) <> '';
          if jsonb_array_length(lst) > 500 then raise exception 'spam.disposable_email_domains: at most 500 domains' using errcode = '22023'; end if;
          sp := sp || jsonb_build_object(k, lst);
        when 'max_leads_per_ip_hour', 'max_leads_per_fingerprint_hour' then
          if jsonb_typeof(p -> 'spam' -> k) not in ('number', 'string') or (p -> 'spam' ->> k) !~ '^\d{1,3}$'
             or (p -> 'spam' ->> k)::int not between 1 and 100 then
            raise exception 'spam.% must be a whole number from 1 to 100', k using errcode = '22023';
          end if;
          sp := sp || jsonb_build_object(k, (p -> 'spam' ->> k)::int);
        else
          raise exception 'unknown hand-off setting: spam.%', k using errcode = '22023';
      end case;
    end loop;
    v := v || jsonb_build_object('spam', sp);
    n := n + 1;
  end if;
  if n = 0 then raise exception 'nothing to save' using errcode = '22023'; end if;
  v := v || jsonb_build_object('b2c_sends_own_notification', true);
  return b2b.set_setting('engine', v, trim(p_reason));
end $fn$;

-- ---------- attribution settings (new) ----------
/* A list of at most 50 distinct lowercase entries of at most 60 characters; empty entries are left out. */
create or replace function b2b.attribution_list_clean(p_list jsonb, p_name text)
returns jsonb language plpgsql immutable set search_path = '' as $fn$
declare
  v jsonb;
begin
  if p_list is null or jsonb_typeof(p_list) <> 'array' then raise exception '% must be a list', p_name using errcode = '22023'; end if;
  if exists (select 1 from jsonb_array_elements_text(p_list) x where length(trim(x)) > 60) then
    raise exception '%: each entry is at most 60 characters', p_name using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(distinct lower(trim(x))), '[]'::jsonb) into v from jsonb_array_elements_text(p_list) x where trim(x) <> '';
  if jsonb_array_length(v) > 50 then raise exception '%: at most 50 entries', p_name using errcode = '22023'; end if;
  return v;
end $fn$;

/* The Admin's 'attribution' setting (read by b2b.lead_attribution): influencer_markers {lead_sources[], utm_values[]} (never
   paid), exclude_campaigns[] (campaign names containing one of these are never paid), meta_ad_params[] (the ad parameter
   that must accompany fbclid/fbc for a Meta ad click). Keys given are merged one by one over the current value (sub-keys of
   influencer_markers too); the row is locked first (C126). Returns set_setting's {key, version}. */
create or replace function b2b.attribution_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v jsonb;
  k text;
  mk jsonb;
  lst jsonb;
  n int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'attribution settings must be an object' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('influencer_markers', 'exclude_campaigns', 'meta_ad_params') then
      raise exception 'unknown attribution setting: %', k using errcode = '22023';
    end if;
  end loop;
  v := b2b.setting_for_update('attribution');
  if p ? 'influencer_markers' then
    if jsonb_typeof(p -> 'influencer_markers') <> 'object' then raise exception 'influencer_markers must be an object' using errcode = '22023'; end if;
    mk := coalesce(case when jsonb_typeof(v -> 'influencer_markers') = 'object' then v -> 'influencer_markers' end, '{}'::jsonb);
    for k in select jsonb_object_keys(p -> 'influencer_markers') loop
      if k not in ('lead_sources', 'utm_values') then raise exception 'unknown attribution setting: influencer_markers.%', k using errcode = '22023'; end if;
      mk := mk || jsonb_build_object(k, b2b.attribution_list_clean(p -> 'influencer_markers' -> k, 'influencer_markers.' || k));
      n := n + 1;
    end loop;
    v := v || jsonb_build_object('influencer_markers', mk);
  end if;
  if p ? 'exclude_campaigns' then
    v := v || jsonb_build_object('exclude_campaigns', b2b.attribution_list_clean(p -> 'exclude_campaigns', 'exclude_campaigns'));
    n := n + 1;
  end if;
  if p ? 'meta_ad_params' then
    lst := b2b.attribution_list_clean(p -> 'meta_ad_params', 'meta_ad_params');
    if exists (select 1 from jsonb_array_elements_text(lst) x where x !~ '^[a-z0-9_]+$') then
      raise exception 'meta_ad_params: use parameter names like ad_id (letters, digits and underscores)' using errcode = '22023';
    end if;
    v := v || jsonb_build_object('meta_ad_params', lst);
    n := n + 1;
  end if;
  if n = 0 then raise exception 'nothing to save' using errcode = '22023'; end if;
  return b2b.set_setting('attribution', v, trim(p_reason));
end $fn$;

-- ---------- grants ----------
revoke execute on function b2b.is_enrolled_status(text), b2b.attribution_list_clean(jsonb, text), b2b.capi_milestones(public.student_leads),
                           b2b.lead_campaign_detect(public.student_leads), b2b.paid_signal(public.student_leads)
  from public, anon, authenticated;
grant execute on function b2b.is_enrolled_status(text), b2b.attribution_list_clean(jsonb, text), b2b.capi_milestones(public.student_leads),
                          b2b.lead_campaign_detect(public.student_leads), b2b.paid_signal(public.student_leads)
  to service_role;
revoke execute on function b2b.handoff_settings_save(jsonb, text), b2b.attribution_settings_save(jsonb, text) from public, anon;
grant execute on function b2b.handoff_settings_save(jsonb, text), b2b.attribution_settings_save(jsonb, text) to authenticated, service_role;

-- ---------- data: re-label every lead, stop queued conversions of leads that are no longer paid, refresh the facts ----------
/* Idempotent: lead_campaign_sync upserts only rows whose platform / paid / campaign changed; the conversion update matches
   nothing on a second run; refresh_facts() only rebuilds the materialized views (its failure is reported, never fatal). */
do $m31g_data$
declare
  l public.student_leads;
  v_last bigint := 0;
  v_n int := 0;
  v_batch int;
  v_skipped int;
  v_facts jsonb;
begin
  if exists (select 1 from b2b.live_switches s where s.scope in ('capi_meta', 'capi_google') and s.live) then
    raise notice 'm31g: a CAPI live switch (capi_meta / capi_google) is on; the design asks for both to be off while the paid labels are re-synced';
  end if;
  loop
    v_batch := 0;
    for l in select * from public.student_leads s where s.deleted_at is null and s.id > v_last order by s.id limit 500 loop
      perform b2b.lead_campaign_sync(l);
      v_last := l.id;
      v_batch := v_batch + 1;
    end loop;
    v_n := v_n + v_batch;
    exit when v_batch < 500;
  end loop;
  update b2b.conversion_events ce
     set status = 'skipped', reason = 'not paid under Addendum 3', next_attempt_at = null
   where ce.status in ('pending', 'failed', 'held')
     and exists (select 1 from b2b.lead_campaigns c
                  where c.lead_id = ce.lead_id and c.cycle_no = ce.cycle_no and (not c.paid or c.platform <> ce.platform));
  get diagnostics v_skipped = row_count;
  begin
    v_facts := b2b.refresh_facts();
  exception when others then
    v_facts := jsonb_build_object('error', left(sqlerrm, 200));
  end;
  raise notice 'm31g: attribution re-synced for % leads; % queued conversion events skipped (not paid under Addendum 3); facts %', v_n, v_skipped, v_facts;
end $m31g_data$;
