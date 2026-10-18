-- Phase 8: dashboards and analytics (spec 12).
--
-- Staff dashboards read four summary materialised views refreshed every 15 minutes by pg_cron
-- (inf.analytics_refresh()); the creator home reads that creator's live rows. Every read goes through a SECURITY DEFINER
-- function that checks the caller, and only aggregates leave the database: no names of students, no phone numbers or
-- emails, and creators never see Eduwit's revenue. Definitions of every metric: docs/METRICS.md
-- (lib/analytics/metrics.ts). Nothing outside schema inf is created or changed; shared tables are only read.

-- ---------------------------------------------------------------------------------------------------------------
-- Committed spend per deal (written by the ledger runner from the engine's zero-performance simulation)
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.deals
  add column committed_paise bigint check (committed_paise >= 0),
  add column committed_at timestamptz;

create or replace function inf.deal_committed_set(p_deal uuid, p_paise bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_paise is null or p_paise < 0 then raise exception 'amount must not be negative' using errcode = '22023'; end if;
  update inf.deals set committed_paise = p_paise, committed_at = now()
   where id = p_deal and committed_paise is distinct from p_paise;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Lead facts: one row per attribution decision, with the furthest stage reached (stages are cumulative)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.an_stage_rank(p text) returns int
language sql immutable set search_path = '' as $$
  select case p when 'new' then 1 when 'qualifying' then 2 when 'qualified' then 3 when 'allocated' then 4
                when 'counselling' then 5 when 'applied' then 6 when 'enrolled' then 7 else 0 end
$$;

-- The live definition (the creator home filters it by creator; the planner pushes the filter into the lateral join).
create or replace view inf.an_leads_live as
select a.id as attribution_id,
       a.student_lead_id,
       a.creator_id,
       coalesce(a.campaign_id, d.campaign_id) as campaign_id,
       a.deal_id,
       a.deliverable_id,
       a.link_id,
       inf.ist_date(a.lead_created_at) as day,
       (a.status in ('credited', 'manually_credited') and a.touch in ('first', 'last')) as credited,
       a.status = 'duplicate' as duplicate,
       a.is_test,
       coalesce(x.platform, k.platform) as platform,
       k.programme_id,
       x.format as content_type,
       d.deal_model,
       greatest(coalesce(r.rank, 0), inf.an_stage_rank(a.creator_stage)) >= 3 as qualified,
       greatest(coalesce(r.rank, 0), inf.an_stage_rank(a.creator_stage)) >= 4 as allocated,
       greatest(coalesce(r.rank, 0), inf.an_stage_rank(a.creator_stage)) >= 6 as applied,
       greatest(coalesce(r.rank, 0), inf.an_stage_rank(a.creator_stage)) >= 7 and not ('cancelled' = any (a.stage_flags)) as enrolled,
       a.creator_stage = 'junk' as junk
  from inf.lead_attributions a
  left join lateral (select max(inf.an_stage_rank(e.creator_stage)) as rank
                       from inf.lead_stage_events e where e.attribution_id = a.id) r on true
  left join inf.tracking_links k on k.id = a.link_id
  left join inf.deliverables x on x.id = a.deliverable_id
  left join inf.deals d on d.id = a.deal_id;

create materialized view inf.an_leads as select * from inf.an_leads_live;
create unique index an_leads_pk on inf.an_leads (attribution_id);
create index an_leads_day_idx on inf.an_leads (day, creator_id);
create index an_leads_campaign_idx on inf.an_leads (campaign_id, day);

-- Clicks per link per IST day (crawlers counted separately and never in the dashboards).
create materialized view inf.an_clicks_daily as
select inf.ist_date(c.clicked_at) as day,
       c.link_id,
       k.creator_id,
       coalesce(k.campaign_id, d.campaign_id) as campaign_id,
       k.deal_id,
       k.deliverable_id,
       coalesce(x.platform, k.platform) as platform,
       k.programme_id,
       x.format as content_type,
       d.deal_model,
       count(*) filter (where not c.is_bot)::int as clicks,
       count(*) filter (where c.is_bot)::int as bot_clicks
  from inf.link_clicks c
  join inf.tracking_links k on k.id = c.link_id
  left join inf.deals d on d.id = k.deal_id
  left join inf.deliverables x on x.id = k.deliverable_id
 group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;
create unique index an_clicks_daily_pk on inf.an_clicks_daily (day, link_id);
create index an_clicks_daily_creator_idx on inf.an_clicks_daily (creator_id, day);

-- Earnings posted per IST day (credits minus debits, before tax; settlement lines excluded). Lines tied to a lead carry
-- that lead's post, platform and programme; deal-level lines (fees, milestones) do not.
create materialized view inf.an_spend_daily as
select md5(concat_ws('|', s.day, s.creator_id, s.deal_id, s.campaign_id, s.deal_model, s.link_id, s.deliverable_id, s.platform,
                     s.programme_id, s.content_type, s.type)) as k,
       s.*
  from (
    select inf.ist_date(e.posted_at) as day,
           e.creator_id,
           e.deal_id,
           coalesce(a.campaign_id, d.campaign_id) as campaign_id,
           d.deal_model,
           a.link_id,
           a.deliverable_id,
           coalesce(x.platform, l.platform) as platform,
           l.programme_id,
           x.format as content_type,
           e.type,
           sum(case when e.direction = 'credit' then e.amount_paise else -e.amount_paise end)::bigint as accrued_paise
      from inf.ledger_entries e
      left join inf.deals d on d.id = e.deal_id
      left join inf.lead_attributions a on a.id = e.attribution_id
      left join inf.tracking_links l on l.id = a.link_id
      left join inf.deliverables x on x.id = a.deliverable_id
     where e.type not in ('tds', 'gst', 'payout')
     group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
  ) s;
create unique index an_spend_daily_pk on inf.an_spend_daily (k);
create index an_spend_daily_day_idx on inf.an_spend_daily (day, creator_id);

-- Eduwit's commission per enrolment of a credited lead, excluding GST: received (pro rata for partly paid) by the day
-- it was received or recorded, and what is still expected. Manual receipts without a net figure use the GST setting.
create materialized view inf.an_revenue as
with att as (
  select distinct on (a.student_lead_id) a.*
    from inf.lead_attributions a
   where a.status in ('credited', 'manually_credited') and a.touch in ('first', 'last')
   order by a.student_lead_id, (a.touch = 'last') desc, a.created_at desc
),
rcpt as (
  select r.*,
         case when r.net_paise > 0 then r.net_paise
              else round(r.gross_paise * 10000.0
                         / (10000 + round(coalesce((inf.setting('compensation.defaults') ->> 'eduwit_commission_gst_pct')::numeric, 18) * 100)))::bigint
         end as net_eff
    from inf.receipts_effective() r
)
select r.enrollment_ref,
       a.id as attribution_id,
       a.creator_id,
       coalesce(a.campaign_id, d.campaign_id) as campaign_id,
       a.deal_id,
       a.deliverable_id,
       a.link_id,
       coalesce(x.platform, k.platform) as platform,
       k.programme_id,
       x.format as content_type,
       d.deal_model,
       a.is_test,
       coalesce(r.received_on, inf.ist_date(r.created_at)) as day,
       case when r.status in ('received', 'partly_received') and r.gross_paise > 0
            then round(r.net_eff::numeric * least(r.received_paise, r.gross_paise) / r.gross_paise)::bigint else 0 end as received_net_paise,
       case when r.status in ('expected', 'partly_received')
            then greatest(r.net_eff - case when r.gross_paise > 0
                                           then round(r.net_eff::numeric * least(r.received_paise, r.gross_paise) / r.gross_paise)::bigint
                                           else 0 end, 0)
            else 0 end as expected_net_paise
  from rcpt r
  join att a on a.student_lead_id = r.student_lead_id
  left join inf.deals d on d.id = a.deal_id
  left join inf.tracking_links k on k.id = a.link_id
  left join inf.deliverables x on x.id = a.deliverable_id;
create unique index an_revenue_pk on inf.an_revenue (enrollment_ref);
create index an_revenue_day_idx on inf.an_revenue (day, creator_id);

-- Refresh (pg_cron every 15 minutes; staff can ask for a refresh through the app's service role). Overlapping calls
-- return at once.
create or replace function inf.analytics_refresh() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v_at timestamptz := now();
begin
  if not pg_try_advisory_xact_lock(hashtext('inf.analytics_refresh')) then
    return (select s.watermark from inf.sync_state s where s.key = 'analytics');
  end if;
  refresh materialized view concurrently inf.an_leads;
  refresh materialized view concurrently inf.an_clicks_daily;
  refresh materialized view concurrently inf.an_spend_daily;
  refresh materialized view concurrently inf.an_revenue;
  insert into inf.sync_state (key, watermark, detail) values ('analytics', v_at, '{}')
  on conflict (key) do update set watermark = excluded.watermark, updated_at = now();
  return v_at;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Read functions (staff: analytics.read)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.analytics_meta() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('refreshed_at', (select s.watermark from inf.sync_state s where s.key = 'analytics'))
   where inf.has_perm('analytics.read')
$$;

-- Bucket start (YYYY-MM-DD) of an IST day: the day, its Monday, or the 1st of its month.
create or replace function inf.an_bucket(p_day date, p_bucket text) returns date
language sql immutable set search_path = '' as $$
  select case p_bucket when 'week' then p_day - (extract(isodow from p_day)::int - 1)
                       when 'month' then date_trunc('month', p_day)::date
                       else p_day end
$$;

-- Totals for a date range, grouped by a dimension (creator, campaign, deal, platform, content_type, programme,
-- deal_model, or all) or by time bucket (day, week, month), within an optional campaign, creator or deal. Rows whose
-- key is null are facts that do not belong to one value of the dimension (for example deal-level fees by platform).
create or replace function inf.analytics_totals(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_from date := (p ->> 'from')::date;
  v_to date := (p ->> 'to')::date;
  v_dim text := coalesce(nullif(p ->> 'dim', ''), 'all');
  v_bucket text := nullif(p ->> 'bucket', '');
  v_key text;
  v_out jsonb;
begin
  if not inf.has_perm('analytics.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_from is null or v_to is null or v_to < v_from or v_to - v_from > 1100 then
    raise exception 'invalid range' using errcode = '22023';
  end if;
  -- The grouping expression comes only from this whitelist, so the dynamic SQL below never contains caller text.
  v_key := case
    when v_bucket = 'day' then 'x.day::text'
    when v_bucket = 'week' then '(x.day - (extract(isodow from x.day)::int - 1))::text'
    when v_bucket = 'month' then 'date_trunc(''month'', x.day)::date::text'
    when v_bucket is not null then null
    when v_dim = 'all' then '''all'''
    when v_dim = 'creator' then 'x.creator_id::text'
    when v_dim = 'campaign' then 'x.campaign_id::text'
    when v_dim = 'deal' then 'x.deal_id::text'
    when v_dim = 'platform' then 'x.platform'
    when v_dim = 'content_type' then 'x.content_type'
    when v_dim = 'programme' then 'x.programme_id::text'
    when v_dim = 'deal_model' then 'x.deal_model'
  end;
  if v_key is null then raise exception 'invalid dimension' using errcode = '22023'; end if;
  -- Rows without a value for the dimension group under '~' and come back with a null key.
  execute format($q$
    with
    l as (
      select coalesce(%1$s, '~') as k,
             count(*) filter (where x.credited) as leads,
             count(*) filter (where x.credited and x.qualified) as qualified,
             count(*) filter (where x.credited and x.allocated) as allocated,
             count(*) filter (where x.credited and x.applied) as applied,
             count(*) filter (where x.credited and x.enrolled) as enrolled,
             count(*) filter (where x.credited and x.junk) as junk,
             count(*) as attributions,
             count(*) filter (where x.duplicate) as duplicates
        from inf.an_leads x
       where x.day between $1 and $2 and ($3 or not x.is_test)
         and ($4::uuid is null or x.campaign_id = $4) and ($5::uuid is null or x.creator_id = $5) and ($6::uuid is null or x.deal_id = $6)
       group by 1),
    c as (
      select coalesce(%1$s, '~') as k, sum(x.clicks) as clicks
        from inf.an_clicks_daily x
       where x.day between $1 and $2
         and ($4::uuid is null or x.campaign_id = $4) and ($5::uuid is null or x.creator_id = $5) and ($6::uuid is null or x.deal_id = $6)
       group by 1),
    s as (
      select coalesce(%1$s, '~') as k, sum(x.accrued_paise) as cost
        from inf.an_spend_daily x
       where x.day between $1 and $2
         and ($4::uuid is null or x.campaign_id = $4) and ($5::uuid is null or x.creator_id = $5) and ($6::uuid is null or x.deal_id = $6)
       group by 1),
    r as (
      select coalesce(%1$s, '~') as k, sum(x.received_net_paise) as revenue
        from inf.an_revenue x
       where x.day between $1 and $2 and ($3 or not x.is_test)
         and ($4::uuid is null or x.campaign_id = $4) and ($5::uuid is null or x.creator_id = $5) and ($6::uuid is null or x.deal_id = $6)
       group by 1),
    keys as (select k from l union select k from c union select k from s union select k from r),
    rows as (
      select nullif(keys.k, '~') as k, l.leads, l.qualified, l.allocated, l.applied, l.enrolled, l.junk, l.attributions,
             l.duplicates, c.clicks, s.cost, r.revenue
        from keys left join l on l.k = keys.k left join c on c.k = keys.k left join s on s.k = keys.k left join r on r.k = keys.k)
    select coalesce(jsonb_agg(jsonb_build_object(
             'key', rows.k,
             'label', case $7
                        when 'creator' then (select cr.display_name from inf.creators cr where cr.id::text = rows.k)
                        when 'campaign' then (select cp.name from inf.campaigns cp where cp.id::text = rows.k)
                        when 'deal' then (select dl.title from inf.deals dl where dl.id::text = rows.k)
                        when 'programme' then (select pg.program_name from public.catalog_programs pg where pg.id::text = rows.k)
                      end,
             'clicks', coalesce(rows.clicks, 0), 'leads', coalesce(rows.leads, 0), 'qualified', coalesce(rows.qualified, 0),
             'allocated', coalesce(rows.allocated, 0), 'applied', coalesce(rows.applied, 0), 'enrolled', coalesce(rows.enrolled, 0),
             'junk', coalesce(rows.junk, 0), 'attributions', coalesce(rows.attributions, 0), 'duplicates', coalesce(rows.duplicates, 0),
             'cost_paise', coalesce(rows.cost, 0), 'revenue_paise', coalesce(rows.revenue, 0)) order by rows.k nulls last), '[]')
      from rows
  $q$, v_key)
  into v_out
  using v_from, v_to, coalesce((p ->> 'include_test')::boolean, false), nullif(p ->> 'campaign_id', '')::uuid,
        nullif(p ->> 'creator_id', '')::uuid, nullif(p ->> 'deal_id', '')::uuid, case when v_bucket is null then v_dim end;
  return v_out;
end $$;

-- Spend: committed (agreed and active deals, now), accrued and paid in the range, by deal model, campaign or creator;
-- campaigns also get their budget and accrued spend to date.
create or replace function inf.analytics_spend(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_from date := (p ->> 'from')::date;
  v_to date := (p ->> 'to')::date;
  v_dim text := coalesce(nullif(p ->> 'dim', ''), 'all');
  v_campaign uuid := nullif(p ->> 'campaign_id', '')::uuid;
  v_out jsonb;
begin
  if not inf.has_perm('analytics.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_from is null or v_to is null or v_to < v_from then raise exception 'invalid range' using errcode = '22023'; end if;
  if v_dim not in ('all', 'deal_model', 'campaign', 'creator') then raise exception 'invalid dimension' using errcode = '22023'; end if;
  with
  dk as (
    select d.id, d.creator_id, d.campaign_id, d.deal_model,
           case v_dim when 'deal_model' then d.deal_model when 'campaign' then d.campaign_id::text
                      when 'creator' then d.creator_id::text else 'all' end as k
      from inf.deals d where v_campaign is null or d.campaign_id = v_campaign),
  committed as (
    select dk.k, sum(d.committed_paise) as v from dk join inf.deals d on d.id = dk.id
     where d.status in ('agreed', 'active') group by dk.k),
  accrued as (
    select case v_dim when 'deal_model' then x.deal_model when 'campaign' then x.campaign_id::text
                      when 'creator' then x.creator_id::text else 'all' end as k,
           sum(x.accrued_paise) filter (where x.day between v_from and v_to) as v,
           sum(x.accrued_paise) as to_date
      from inf.an_spend_daily x where v_campaign is null or x.campaign_id = v_campaign group by 1),
  paid as (
    select case v_dim when 'deal_model' then d.deal_model when 'campaign' then d.campaign_id::text
                      when 'creator' then po.creator_id::text else 'all' end as k,
           sum(case when e.direction = 'credit' then i.amount_paise else -abs(i.amount_paise) end) as v
      from inf.payouts po
      join inf.payout_items i on i.payout_id = po.id
      join inf.ledger_entries e on e.id = i.entry_id
      left join inf.deals d on d.id = e.deal_id
     where po.status = 'paid' and po.paid_on between v_from and v_to and (v_campaign is null or d.campaign_id = v_campaign)
     group by 1),
  keys as (select k from committed union select k from accrued union select k from paid)
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', keys.k,
           'label', case v_dim when 'campaign' then (select cp.name from inf.campaigns cp where cp.id::text = keys.k)
                               when 'creator' then (select cr.display_name from inf.creators cr where cr.id::text = keys.k) end,
           'committed_paise', coalesce(committed.v, 0), 'accrued_paise', coalesce(accrued.v, 0),
           'accrued_to_date_paise', coalesce(accrued.to_date, 0), 'paid_paise', coalesce(paid.v, 0),
           'budget_paise', case v_dim when 'campaign' then (select cp.budget_paise from inf.campaigns cp where cp.id::text = keys.k) end)
           order by keys.k nulls last), '[]')
    into v_out
    from keys left join committed on committed.k is not distinct from keys.k
    left join accrued on accrued.k is not distinct from keys.k left join paid on paid.k is not distinct from keys.k;
  return v_out;
end $$;

-- Programme health (now, plus creators approved in the range). Test creators only on request.
create or replace function inf.analytics_health(p jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'active', (select count(*) from inf.creators c where c.status = 'active' and (coalesce((p ->> 'include_test')::boolean, false) or not c.is_test)),
    'dormant', (select count(*) from inf.creators c where c.pipeline_stage = 'dormant' and (coalesce((p ->> 'include_test')::boolean, false) or not c.is_test)),
    'new', (select count(*) from inf.creators c where (coalesce((p ->> 'include_test')::boolean, false) or not c.is_test)
             and inf.ist_date(c.approved_at) between (p ->> 'from')::date and (p ->> 'to')::date),
    'new_previous', (select count(*) from inf.creators c where (coalesce((p ->> 'include_test')::boolean, false) or not c.is_test)
             and inf.ist_date(c.approved_at) between (p ->> 'prev_from')::date and (p ->> 'prev_to')::date),
    'pipeline', coalesce((select jsonb_object_agg(x.pipeline_stage, x.n) from (
                  select c.pipeline_stage, count(*) as n from inf.creators c where (coalesce((p ->> 'include_test')::boolean, false) or not c.is_test) group by 1) x), '{}'))
   where inf.has_perm('analytics.read')
$$;

-- Operations (now). Optional campaign scope.
create or replace function inf.analytics_operations(p_campaign uuid default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  with d as (select x.* from inf.deals x where p_campaign is null or x.campaign_id = p_campaign)
  select jsonb_build_object(
    'overdue_deliverables', (select count(*) from inf.deliverables v join d on d.id = v.deal_id
                              where v.status not in ('live', 'live_verified', 'metrics_submitted', 'completed', 'cancelled')
                                and (v.due_dates ->> 'live') is not null and (v.due_dates ->> 'live')::date < inf.ist_date(now())),
    'pending_reviews', (select count(*) from inf.deliverables v join d on d.id = v.deal_id
                         where v.status in ('concept_submitted', 'draft_submitted')),
    'pending_negotiations', (select count(*) from d where d.status in ('proposed', 'negotiating'))
                            + (select count(*) from inf.contracts k join d on d.id = k.deal_id where k.status in ('sent', 'in_negotiation')),
    'contracts_expiring', (select count(*) from inf.contracts k join d on d.id = k.deal_id
                            where k.status = 'active' and d.ends_on between inf.ist_date(now()) and inf.ist_date(now()) + 30),
    'payouts_due_paise', (select coalesce(sum(case when e.direction = 'credit' then e.confirmed_paise - e.paid_paise
                                                   else -(e.confirmed_paise - e.paid_paise) end), 0)
                            from inf.ledger_entries e where e.status = 'payable'
                             and (p_campaign is null or e.deal_id in (select d.id from d))),
    'kyc_pending', (select count(*) from inf.creator_kyc k where k.status = 'submitted'),
    'fraud_flags', (select count(*) from inf.fraud_flags f where f.status = 'open'
                     and (p_campaign is null or f.creator_id in (select d.creator_id from d))))
   where inf.has_perm('analytics.read')
$$;

-- Per-creator figures for the leaderboards (staff see everyone; opt-in only limits what creators see).
create or replace function inf.analytics_creators(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_from date := (p ->> 'from')::date;
  v_to date := (p ->> 'to')::date;
  v_campaign uuid := nullif(p ->> 'campaign_id', '')::uuid;
  v_test boolean := coalesce((p ->> 'include_test')::boolean, false);
begin
  if not inf.has_perm('analytics.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    with
    l as (select x.creator_id, count(*) filter (where x.credited) as leads, count(*) filter (where x.credited and x.enrolled) as enrolled,
                 count(*) filter (where x.credited and x.qualified) as qualified
            from inf.an_leads x where x.day between v_from and v_to and (v_test or not x.is_test)
             and (v_campaign is null or x.campaign_id = v_campaign) group by 1),
    s as (select x.creator_id, sum(x.accrued_paise) as cost from inf.an_spend_daily x
           where x.day between v_from and v_to and (v_campaign is null or x.campaign_id = v_campaign) group by 1),
    r as (select x.creator_id, sum(x.received_net_paise) as revenue from inf.an_revenue x
           where x.day between v_from and v_to and (v_test or not x.is_test) and (v_campaign is null or x.campaign_id = v_campaign) group by 1),
    o as (select dl.creator_id, count(*) as due,
                 count(*) filter (where v.live_at is not null and inf.ist_date(v.live_at) <= (v.due_dates ->> 'live')::date) as on_time
            from inf.deliverables v join inf.deals dl on dl.id = v.deal_id
           where v.status <> 'cancelled' and (v.due_dates ->> 'live') is not null
             and (v.due_dates ->> 'live')::date between v_from and least(v_to, inf.ist_date(now()))
             and (v_campaign is null or dl.campaign_id = v_campaign)
           group by 1),
    ids as (select creator_id from l union select creator_id from s union select creator_id from r union select creator_id from o)
    select jsonb_agg(jsonb_build_object(
             'creator_id', c.id, 'name', c.display_name, 'handle', c.handle, 'opt_in', c.leaderboard_opt_in,
             'leads', coalesce(l.leads, 0), 'qualified', coalesce(l.qualified, 0), 'enrolled', coalesce(l.enrolled, 0),
             'cost_paise', coalesce(s.cost, 0), 'revenue_paise', coalesce(r.revenue, 0),
             'due', coalesce(o.due, 0), 'on_time', coalesce(o.on_time, 0)) order by c.display_name)
      from ids join inf.creators c on c.id = ids.creator_id
      left join l on l.creator_id = c.id left join s on s.creator_id = c.id left join r on r.creator_id = c.id
      left join o on o.creator_id = c.id
     where v_test or not c.is_test), '[]');
end $$;

-- Finance dashboard: what Eduwit owes now, payouts and TDS by period bucket, TDS by quarter of the range's FYs.
create or replace function inf.analytics_finance(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_from date := (p ->> 'from')::date;
  v_to date := (p ->> 'to')::date;
  v_bucket text := coalesce(nullif(p ->> 'bucket', ''), 'month');
begin
  if not (inf.has_perm('analytics.read') and inf.has_perm('ledger.read')) then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_from is null or v_to is null or v_to < v_from then raise exception 'invalid range' using errcode = '22023'; end if;
  return jsonb_build_object(
    'liabilities_paise', (select coalesce(sum(case when e.direction = 'credit' then e.amount_paise - e.paid_paise
                                                   else -(e.amount_paise - e.paid_paise) end), 0)
                            from inf.ledger_entries e
                           where e.type not in ('tds', 'gst', 'payout') and e.status not in ('reversed', 'clawed_back')),
    'confirmed_unpaid_paise', (select coalesce(sum(case when e.direction = 'credit' then e.confirmed_paise - e.paid_paise
                                                        else -(e.confirmed_paise - e.paid_paise) end), 0)
                                 from inf.ledger_entries e
                                where e.type not in ('tds', 'gst', 'payout') and e.status not in ('reversed', 'clawed_back')),
    'payable_paise', (select coalesce(sum(case when e.direction = 'credit' then e.confirmed_paise - e.paid_paise
                                               else -(e.confirmed_paise - e.paid_paise) end), 0)
                        from inf.ledger_entries e where e.status = 'payable'),
    'payouts', coalesce((select jsonb_agg(jsonb_build_object('at', x.b, 'count', x.n, 'gross_paise', x.gross, 'tds_paise', x.tds,
                                                             'gst_paise', x.gst, 'net_paise', x.net) order by x.b)
                           from (select inf.an_bucket(po.paid_on, v_bucket) as b, count(*) as n, sum(po.gross_paise) as gross,
                                        sum(po.tds_paise) as tds, sum(po.gst_paise) as gst, sum(po.net_paise) as net
                                   from inf.payouts po where po.status = 'paid' and po.paid_on between v_from and v_to group by 1) x), '[]'),
    'tds', coalesce((select jsonb_agg(jsonb_build_object('fy', x.fy, 'quarter', x.quarter, 'section', x.section,
                                                         'amount_paise', x.amount, 'creators', x.creators) order by x.fy, x.quarter, x.section)
                       from (select t.fy, t.quarter, t.section, sum(t.amount_paise) as amount, count(distinct t.creator_id) as creators
                               from inf.tds_records t
                              where t.borne_by = 'creator' and t.fy between inf.fy_of(v_from) and inf.fy_of(v_to)
                              group by 1, 2, 3) x), '[]'));
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- The creator home (live): the creator, an agency with the view grant, or staff with creator.read
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.creator_dashboard(p_creator uuid, p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_from date := (p ->> 'from')::date;
  v_to date := (p ->> 'to')::date;
  v_pfrom date := (p ->> 'prev_from')::date;
  v_pto date := (p ->> 'prev_to')::date;
  v_bucket text := coalesce(nullif(p ->> 'bucket', ''), 'day');
  v_opt boolean;
begin
  if not (coalesce(p_creator = inf.current_creator_id(), false) or inf.agency_can(p_creator, 'view') or inf.has_perm('creator.read')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if v_from is null or v_to is null or v_to < v_from or v_to - v_from > 1100 or v_pfrom is null or v_pto is null then
    raise exception 'invalid range' using errcode = '22023';
  end if;
  select c.leaderboard_opt_in into v_opt from inf.creators c where c.id = p_creator;
  return (
    with
    lv as (select * from inf.an_leads_live x where x.creator_id = p_creator and x.credited and not x.is_test
              and (x.day between v_from and v_to or x.day between v_pfrom and v_pto)),
    cl as (select inf.ist_date(c.clicked_at) as day, k.id as link_id
             from inf.link_clicks c join inf.tracking_links k on k.id = c.link_id
            where k.creator_id = p_creator and not c.is_bot
              and (inf.ist_date(c.clicked_at) between v_from and v_to or inf.ist_date(c.clicked_at) between v_pfrom and v_pto)),
    totals as (
      select jsonb_build_object(
        'clicks', (select count(*) from cl where cl.day between v_from and v_to),
        'leads', count(*) filter (where lv.day between v_from and v_to),
        'qualified', count(*) filter (where lv.day between v_from and v_to and lv.qualified),
        'allocated', count(*) filter (where lv.day between v_from and v_to and lv.allocated),
        'applied', count(*) filter (where lv.day between v_from and v_to and lv.applied),
        'enrolled', count(*) filter (where lv.day between v_from and v_to and lv.enrolled)) as cur,
             jsonb_build_object(
        'clicks', (select count(*) from cl where cl.day between v_pfrom and v_pto),
        'leads', count(*) filter (where lv.day between v_pfrom and v_pto),
        'qualified', count(*) filter (where lv.day between v_pfrom and v_pto and lv.qualified),
        'allocated', count(*) filter (where lv.day between v_pfrom and v_pto and lv.allocated),
        'applied', count(*) filter (where lv.day between v_pfrom and v_pto and lv.applied),
        'enrolled', count(*) filter (where lv.day between v_pfrom and v_pto and lv.enrolled)) as prev
        from lv)
    select jsonb_build_object(
      'current', (select cur from totals),
      'previous', (select prev from totals),
      'series', coalesce((select jsonb_agg(jsonb_build_object('at', x.b, 'leads', x.leads, 'enrolled', x.enrolled) order by x.b)
                            from (select inf.an_bucket(lv.day, v_bucket) as b, count(*) as leads, count(*) filter (where lv.enrolled) as enrolled
                                    from lv where lv.day between v_from and v_to group by 1) x), '[]'),
      'content', coalesce((select jsonb_agg(jsonb_build_object('deliverable_id', x.deliverable_id, 'link_id', x.link_id,
                                                              'title', coalesce(dv.title, k.label, k.code), 'platform', x.platform,
                                                              'leads', x.leads, 'enrolled', x.enrolled) order by x.leads desc, x.enrolled desc)
                             from (select lv.deliverable_id, lv.link_id, max(lv.platform) as platform, count(*) as leads,
                                          count(*) filter (where lv.enrolled) as enrolled
                                     from lv where lv.day between v_from and v_to group by 1, 2
                                    order by count(*) desc limit 5) x
                             left join inf.deliverables dv on dv.id = x.deliverable_id
                             left join inf.tracking_links k on k.id = x.link_id), '[]'),
      'programmes', coalesce((select jsonb_agg(jsonb_build_object('key', x.programme_id, 'label', pg.program_name, 'leads', x.leads,
                                                                 'enrolled', x.enrolled) order by x.leads desc)
                                from (select lv.programme_id, count(*) as leads, count(*) filter (where lv.enrolled) as enrolled
                                        from lv where lv.day between v_from and v_to group by 1) x
                                left join public.catalog_programs pg on pg.id = x.programme_id), '[]'),
      'platforms', coalesce((select jsonb_agg(jsonb_build_object('key', x.platform, 'leads', x.leads, 'enrolled', x.enrolled)
                                              order by x.leads desc)
                               from (select lv.platform, count(*) as leads, count(*) filter (where lv.enrolled) as enrolled
                                       from lv where lv.day between v_from and v_to group by 1) x), '[]'),
      'deals', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title, 'status', d.status,
                                                            'campaign_id', d.campaign_id,
                                                            'campaign_name', (select cp.name from inf.campaigns cp where cp.id = d.campaign_id),
                                                            'ends_on', d.ends_on, 'committed_paise', d.committed_paise)
                                         order by d.starts_on desc)
                           from inf.deals d where d.creator_id = p_creator and d.status in ('agreed', 'active')), '[]'),
      'fixed', (select jsonb_build_object(
                  'committed_paise', coalesce(sum(d.committed_paise), 0),
                  'earned_paise', coalesce((select sum(case when e.direction = 'credit' then e.amount_paise else -e.amount_paise end)
                                              from inf.ledger_entries e join inf.deals d2 on d2.id = e.deal_id
                                             where e.creator_id = p_creator and d2.status in ('agreed', 'active')
                                               and e.type in ('fixed_fee', 'milestone')), 0))
                  from inf.deals d where d.creator_id = p_creator and d.status in ('agreed', 'active')),
      'actions', jsonb_build_object(
        'contracts', (select count(*) from inf.contracts k join inf.deals d on d.id = k.deal_id
                       where d.creator_id = p_creator and k.status in ('sent', 'in_negotiation', 'ready_to_sign')),
        'briefs', (select count(*) from inf.briefs b join inf.deals d on d.id = b.deal_id
                    where d.creator_id = p_creator and b.current_version_id is not null
                      and not exists (select 1 from inf.brief_acknowledgements a where a.version_id = b.current_version_id)),
        'due_soon', (select count(*) from inf.deliverables v join inf.deals d on d.id = v.deal_id
                      where d.creator_id = p_creator
                        and v.status not in ('live', 'live_verified', 'metrics_submitted', 'completed', 'cancelled')
                        and (v.due_dates ->> 'live')::date between inf.ist_date(now()) and inf.ist_date(now()) + 7),
        'overdue', (select count(*) from inf.deliverables v join inf.deals d on d.id = v.deal_id
                     where d.creator_id = p_creator
                       and v.status not in ('live', 'live_verified', 'metrics_submitted', 'completed', 'cancelled')
                       and (v.due_dates ->> 'live')::date < inf.ist_date(now())),
        'changes_requested', (select count(*) from inf.deliverables v join inf.deals d on d.id = v.deal_id
                               where d.creator_id = p_creator and v.status in ('concept_changes_requested', 'draft_changes_requested')),
        'metrics_due', (select count(*) from inf.deliverables v join inf.deals d on d.id = v.deal_id
                         where d.creator_id = p_creator and v.status in ('live', 'live_verified') and v.live_at < now() - interval '24 hours'
                           and not exists (select 1 from inf.post_metric_snapshots s where s.deliverable_id = v.id)),
        'invoices', (select count(*) from inf.payouts po join inf.payout_batches b on b.id = po.batch_id
                      where po.creator_id = p_creator and po.status = 'pending' and po.needs_invoice and b.status <> 'cancelled'
                        and not exists (select 1 from inf.invoices i where i.payout_id = po.id and i.status in ('submitted', 'accepted'))),
        'kyc', (select coalesce((select k.status not in ('submitted', 'verified') from inf.creator_kyc k where k.creator_id = p_creator), true))),
      'leaderboard', case when v_opt then (
        select jsonb_build_object('rank', x.rank, 'of', x.total, 'enrolled', x.enrolled)
          from (select y.creator_id, y.enrolled, rank() over (order by y.enrolled desc) as rank, count(*) over () as total
                  from (select c.id as creator_id, count(*) filter (where a.credited and a.enrolled and not a.is_test) as enrolled
                          from inf.creators c left join inf.an_leads a on a.creator_id = c.id and a.day between v_from and v_to
                         where c.leaderboard_opt_in and c.status = 'active' and not c.is_test
                         group by c.id) y) x
         where x.creator_id = p_creator) end,
      'opt_in', coalesce(v_opt, false))
  );
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Schedule, grants
-- ---------------------------------------------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('inf-analytics', '*/15 * * * *', $c$select inf.analytics_refresh()$c$);
  end if;
end $$;

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('function', 'inf.analytics_meta()', 'authenticated', 'execute'),
  ('function', 'inf.analytics_totals(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.analytics_spend(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.analytics_health(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.analytics_operations(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.analytics_creators(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.analytics_finance(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.creator_dashboard(uuid, jsonb)', 'authenticated', 'execute');
call inf.apply_client_grants();
