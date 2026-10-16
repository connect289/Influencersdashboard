-- B2C CRM b26 (Phase 4): ad spend and return on ad spend (spec B13.2 inflow and money, B19.2 row 4). Staging first.
--   ad_spend_daily     one row per platform, day, campaign and ad set, loaded from the Meta Ads Manager and Google Ads
--                      CSV exports; a re-import replaces the same rows instead of adding them again
--   ad_campaign_map    ties a platform campaign to the leads' source and campaign values (the Admin or Marketing sets it;
--                      a lead whose campaign equals a platform campaign's id or name matches without a map)
--   source 'ads'       spend rows and the matched leads (with their qualified, enrolled and university commission net),
--                      so cost per lead, cost per enrolment and ROAS are one query; the leads are the cohort that
--                      arrived in the period
--   analytics_exec      rows without a lead (spend) also count when the test-leads switch is on
--   the "Ad spend" standard dashboard for the Admin and Marketing

create table if not exists b2c.ad_imports (
  id bigint generated always as identity primary key,
  platform text not null check (platform in ('meta', 'google')),
  file_name text,
  rows int not null default 0,
  from_day date,
  to_day date,
  spend numeric(14, 2) not null default 0,
  created_by uuid,
  created_at timestamptz not null default now()
);
create table if not exists b2c.ad_spend_daily (
  id bigint generated always as identity primary key,
  platform text not null check (platform in ('meta', 'google')),
  day date not null,
  account text not null default '',
  campaign_id text not null,
  campaign text,
  adset text not null default '',
  spend numeric(12, 2) not null default 0 check (spend >= 0),
  impressions bigint not null default 0,
  clicks bigint not null default 0,
  platform_leads int not null default 0,
  currency text not null default 'INR',
  import_id bigint references b2c.ad_imports (id),
  updated_at timestamptz not null default now(),
  unique (platform, day, campaign_id, adset)
);
create index if not exists ad_spend_campaign on b2c.ad_spend_daily (platform, campaign_id);
create table if not exists b2c.ad_campaign_map (
  id bigint generated always as identity primary key,
  platform text not null check (platform in ('meta', 'google')),
  campaign_id text not null,
  lead_source text,
  lead_campaign text,
  set_by uuid,
  set_at timestamptz not null default now(),
  unique (platform, campaign_id),
  check (lead_source is not null or lead_campaign is not null)
);
alter table b2c.ad_imports enable row level security;
alter table b2c.ad_spend_daily enable row level security;
alter table b2c.ad_campaign_map enable row level security;

/* Each lead's ad campaign: a map first (campaign value, then source), else a platform campaign whose id or name equals
   the lead's campaign. */
create or replace view b2c.ad_lead_campaign_v with (security_invoker = true) as
  select f.lead_id, k.platform, k.campaign_id
    from b2c.fact_leads f
   cross join lateral (
     select x.platform, x.campaign_id from (
       select m.platform, m.campaign_id, 1 pri from b2c.ad_campaign_map m
        where m.lead_campaign is not null and lower(m.lead_campaign) = lower(f.campaign)
       union all
       select m.platform, m.campaign_id, 2 from b2c.ad_campaign_map m
        where m.lead_campaign is null and lower(m.lead_source) = lower(f.source)
       union all
       select s.platform, s.campaign_id, 3 from b2c.ad_spend_daily s
        where f.campaign is not null and (lower(s.campaign_id) = lower(f.campaign) or lower(s.campaign) = lower(f.campaign))) x
     order by x.pri limit 1) k;

/* Admin and Marketing: one CSV's rows, already read by the app. p: platform, file_name, rows [{day, account, campaign_id,
   campaign, adset, spend, impressions, clicks, leads, currency}]. Same platform, day, campaign and ad set: replaced. */
create or replace function b2c.ad_spend_import(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing'); v_platform text := p ->> 'platform'; v_imp bigint; v_n int; v_bad int;
begin
  if v_platform not in ('meta', 'google') then raise exception 'the platform is meta or google'; end if;
  if jsonb_typeof(p -> 'rows') <> 'array' or jsonb_array_length(p -> 'rows') = 0 then raise exception 'the file has no rows'; end if;
  if jsonb_array_length(p -> 'rows') > 20000 then raise exception 'at most 20,000 rows per file'; end if;
  select count(*) into v_bad from jsonb_array_elements(p -> 'rows') r
   where nullif(r ->> 'day', '') is null or coalesce(nullif(r ->> 'campaign_id', ''), nullif(r ->> 'campaign', '')) is null
      or (r ->> 'day') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(nullif(r ->> 'spend', ''), '0') !~ '^\d+(\.\d+)?$';
  if v_bad > 0 then raise exception '% rows have no date, no campaign or an unreadable amount', v_bad; end if;
  if exists (select 1 from jsonb_array_elements(p -> 'rows') r where coalesce(nullif(r ->> 'currency', ''), 'INR') <> 'INR') then
    raise exception 'spend must be in INR (set the ad account currency, or convert before importing)';
  end if;
  insert into b2c.ad_imports (platform, file_name, created_by) values (v_platform, left(p ->> 'file_name', 200), me) returning id into v_imp;
  insert into b2c.ad_spend_daily as t (platform, day, account, campaign_id, campaign, adset, spend, impressions, clicks, platform_leads, import_id)
  select v_platform, (r ->> 'day')::date, coalesce(r ->> 'account', ''), coalesce(nullif(r ->> 'campaign_id', ''), r ->> 'campaign'), nullif(r ->> 'campaign', ''),
         coalesce(r ->> 'adset', ''), sum(coalesce(nullif(r ->> 'spend', ''), '0')::numeric), sum(coalesce(nullif(r ->> 'impressions', ''), '0')::bigint),
         sum(coalesce(nullif(r ->> 'clicks', ''), '0')::bigint), sum(coalesce(nullif(r ->> 'leads', ''), '0')::int), v_imp
    from jsonb_array_elements(p -> 'rows') r
   group by 2, 3, 4, 5, 6
  on conflict (platform, day, campaign_id, adset) do update set account = excluded.account, campaign = coalesce(excluded.campaign, t.campaign), spend = excluded.spend,
     impressions = excluded.impressions, clicks = excluded.clicks, platform_leads = excluded.platform_leads, import_id = excluded.import_id, updated_at = now();
  get diagnostics v_n = row_count;
  update b2c.ad_imports i set rows = v_n, from_day = q.f, to_day = q.t, spend = q.s
    from (select min(day) f, max(day) t, coalesce(sum(spend), 0) s from b2c.ad_spend_daily where import_id = v_imp) q where i.id = v_imp;
  perform b2c.log('marketing.ad_spend_imported', null, jsonb_build_object('import_id', v_imp, 'platform', v_platform, 'rows', v_n));
  return (select to_jsonb(i) from b2c.ad_imports i where id = v_imp);
end $f$;

create or replace function b2c.ad_campaign_map_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('marketing'); v bigint;
begin
  if p ->> 'platform' not in ('meta', 'google') or coalesce(p ->> 'campaign_id', '') = '' then raise exception 'unknown campaign'; end if;
  if coalesce(nullif(trim(p ->> 'lead_source'), ''), nullif(trim(p ->> 'lead_campaign'), '')) is null then
    raise exception 'give the leads'' source or campaign value this campaign brings';
  end if;
  insert into b2c.ad_campaign_map as m (platform, campaign_id, lead_source, lead_campaign, set_by)
  values (p ->> 'platform', p ->> 'campaign_id', nullif(trim(p ->> 'lead_source'), ''), nullif(trim(p ->> 'lead_campaign'), ''), me)
  on conflict (platform, campaign_id) do update set lead_source = excluded.lead_source, lead_campaign = excluded.lead_campaign, set_by = me, set_at = now()
  returning id into v;
  perform b2c.log('marketing.ad_campaign_mapped', null, p);
  return v;
end $f$;

/* The Ad spend tab: imports, each campaign with its spend and matched leads, and suggestions for unmatched campaigns. */
create or replace function b2c.ad_spend_overview(p_from date default null, p_to date default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_from date := coalesce(p_from, (now() at time zone 'Asia/Kolkata')::date - 89); v_to date := coalesce(p_to, (now() at time zone 'Asia/Kolkata')::date);
begin
  if not b2c.can('marketing') then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('from', v_from, 'to', v_to,
    'imports', (select coalesce(jsonb_agg(to_jsonb(i) || jsonb_build_object('by', (select full_name from b2c.users where user_id = i.created_by)) order by i.id desc), '[]')
                  from (select * from b2c.ad_imports order by id desc limit 20) i),
    'campaigns', (select coalesce(jsonb_agg(c order by (c ->> 'spend')::numeric desc), '[]') from (
       select jsonb_build_object('platform', s.platform, 'campaign_id', s.campaign_id, 'campaign', max(s.campaign), 'spend', sum(s.spend), 'clicks', sum(s.clicks),
                'platform_leads', sum(s.platform_leads),
                'map', (select jsonb_build_object('lead_source', m.lead_source, 'lead_campaign', m.lead_campaign) from b2c.ad_campaign_map m where m.platform = s.platform and m.campaign_id = s.campaign_id),
                'leads', (select count(*) from b2c.ad_lead_campaign_v a join b2c.fact_leads f on f.lead_id = a.lead_id
                           where a.platform = s.platform and a.campaign_id = s.campaign_id and not f.is_test
                             and f.handed_off_at >= (v_from::timestamp at time zone 'Asia/Kolkata') and f.handed_off_at < ((v_to + 1)::timestamp at time zone 'Asia/Kolkata')),
                'enrolled', (select count(*) from b2c.ad_lead_campaign_v a join b2c.fact_leads f on f.lead_id = a.lead_id
                           where a.platform = s.platform and a.campaign_id = s.campaign_id and not f.is_test and f.enrolled_on is not null and not f.refunded
                             and f.handed_off_at >= (v_from::timestamp at time zone 'Asia/Kolkata') and f.handed_off_at < ((v_to + 1)::timestamp at time zone 'Asia/Kolkata')),
                'commission_net', (select coalesce(sum(f.university_net), 0) from b2c.ad_lead_campaign_v a join b2c.fact_leads f on f.lead_id = a.lead_id
                           where a.platform = s.platform and a.campaign_id = s.campaign_id and not f.is_test
                             and f.handed_off_at >= (v_from::timestamp at time zone 'Asia/Kolkata') and f.handed_off_at < ((v_to + 1)::timestamp at time zone 'Asia/Kolkata'))) c
         from b2c.ad_spend_daily s where s.day between v_from and v_to group by s.platform, s.campaign_id) q),
    'lead_values', (select coalesce(jsonb_agg(jsonb_build_object('source', source, 'campaign', campaign, 'leads', n) order by n desc), '[]') from (
                      select source, campaign, count(*) n from b2c.fact_leads where not is_test and handed_off_at >= now() - interval '180 days'
                       group by 1, 2 order by 3 desc limit 200) v));
end $f$;

-- ---------- analytics: the 'ads' source, its metrics and dimensions ----------
insert into b2c.an_sources (key, from_sql, actor_sql, lead_based) values
  ('ads', '(select s.day, (s.day::timestamp at time zone ''Asia/Kolkata'') as at, s.platform, s.campaign_id, coalesce(s.campaign, s.campaign_id) as campaign_name,
                   s.spend, s.clicks, s.impressions, null::bigint as lead_id, 0 as lead, 0 as qualified, 0 as enrolled, 0::numeric as commission_net
              from b2c.ad_spend_daily s
            union all
            select (f.handed_off_at at time zone ''Asia/Kolkata'')::date, f.handed_off_at, a.platform, a.campaign_id,
                   coalesce((select max(coalesce(d.campaign, d.campaign_id)) from b2c.ad_spend_daily d where d.platform = a.platform and d.campaign_id = a.campaign_id), a.campaign_id),
                   0, 0, 0, f.lead_id, 1, (f.counselled_at is not null)::int, (f.enrolled_on is not null and not f.refunded)::int, coalesce(f.university_net, 0)
              from b2c.ad_lead_campaign_v a join b2c.fact_leads f on f.lead_id = a.lead_id) x', 'null::uuid', false)
on conflict (key) do update set from_sql = excluded.from_sql, actor_sql = excluded.actor_sql, lead_based = excluded.lead_based;

insert into b2c.metric_defs (key, label, area, source, agg, date_sql, where_sql, fmt, roles, counts_leads, higher_is_better, description, sort) values
  ('ad_spend', 'Ad spend', 'Ad spend', 'ads', 'sum(x.spend)', 'x.at', null, 'money', '{admin,marketing}', false, false, 'Spend imported from Meta and Google', 300),
  ('ad_clicks', 'Ad clicks', 'Ad spend', 'ads', 'sum(x.clicks)', 'x.at', null, 'count', '{admin,marketing}', false, true, null, 301),
  ('ad_leads', 'Leads from ads', 'Ad spend', 'ads', 'sum(x.lead)', 'x.at', 'x.lead_id is not null', 'count', '{admin,marketing}', true, true,
     'Leads that arrived in the period from a campaign with spend (by the campaign map or a matching campaign value)', 302),
  ('ad_enrolled', 'Enrolled from ads', 'Ad spend', 'ads', 'sum(x.enrolled)', 'x.at', 'x.lead_id is not null', 'count', '{admin,marketing}', true, true,
     'Leads from ads that arrived in the period and have enrolled (refunds excluded)', 303),
  ('ad_cpl', 'Cost per lead', 'Ad spend', 'ads', 'round(sum(x.spend) / nullif(sum(x.lead), 0), 2)', 'x.at', null, 'money', '{admin,marketing}', false, false, null, 304),
  ('ad_cpql', 'Cost per qualified lead', 'Ad spend', 'ads', 'round(sum(x.spend) / nullif(sum(x.qualified), 0), 2)', 'x.at', null, 'money', '{admin,marketing}', false, false,
     'Spend divided by the leads from ads that reached Qualified or later', 305),
  ('ad_cpe', 'Cost per enrolment', 'Ad spend', 'ads', 'round(sum(x.spend) / nullif(sum(x.enrolled), 0), 2)', 'x.at', null, 'money', '{admin,marketing}', false, false, null, 306),
  ('ad_commission', 'University commission from ads (net)', 'Ad spend', 'ads', 'sum(x.commission_net)', 'x.at', null, 'money', '{admin,marketing}', false, true,
     'Net university commission booked for the leads from ads that arrived in the period', 307),
  ('ad_roas', 'Return on ad spend', 'Ad spend', 'ads', 'round(sum(x.commission_net) / nullif(sum(x.spend), 0), 2)', 'x.at', null, 'number', '{admin,marketing}', false, true,
     'Net university commission of the period''s leads from ads, for each rupee spent (2.5 means ₹2.50 back per ₹1)', 308)
on conflict (key) do update set label = excluded.label, area = excluded.area, source = excluded.source, agg = excluded.agg, date_sql = excluded.date_sql, where_sql = excluded.where_sql,
  fmt = excluded.fmt, roles = excluded.roles, counts_leads = excluded.counts_leads, higher_is_better = excluded.higher_is_better, description = excluded.description, sort = excluded.sort;

insert into b2c.dim_defs (key, label, expr, sources, money, sort) values
  ('ad_platform', 'Ad platform', 'x.platform', '{ads}', false, 60),
  ('ad_campaign', 'Ad campaign', 'x.campaign_name', '{ads}', false, 61)
on conflict (key) do update set label = excluded.label, expr = excluded.expr, sources = excluded.sources, money = excluded.money, sort = excluded.sort;

insert into b2c.dashboards (key, name, description, roles, sort, widgets, filters) values
('ad_spend', 'Ad spend', 'What the ads cost and what they brought back', '{admin,marketing}', 27, jsonb_build_array(
   b2c.w('s1', 'Ad spend', 'kpi', '{ad_spend}'), b2c.w('s2', 'Cost per lead', 'kpi', '{ad_cpl}'), b2c.w('s3', 'Cost per enrolment', 'kpi', '{ad_cpe}'),
   b2c.w('s4', 'Return on ad spend', 'kpi', '{ad_roas}'),
   b2c.w('s5', 'Spend by day', 'line', '{ad_spend}', '{day}', 2), b2c.w('s6', 'Leads from ads by day', 'line', '{ad_leads}', '{day}', 2),
   b2c.w('s7', 'By campaign', 'table', '{ad_spend,ad_leads,ad_cpl,ad_enrolled,ad_cpe,ad_roas}', '{ad_campaign}', 4),
   b2c.w('s8', 'By platform', 'table', '{ad_spend,ad_leads,ad_cpl,ad_roas}', '{ad_platform}', 2),
   b2c.w('s9', 'Cost per qualified lead by platform', 'bar', '{ad_cpql}', '{ad_platform}', 2)), '{"range": "30d", "compare": "previous"}')
on conflict (key) do nothing;

/* analytics_exec() as in b22, except that rows without a lead (ad spend) count in test mode too: spend is never a test lead. */
create or replace function b2c.analytics_exec(p_user uuid, p_role text, spec jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  g text := b2c.an_group(p_role); m b2c.metric_defs; s b2c.an_sources; d b2c.dim_defs; v_metrics text[]; v_dims text[]; k text; i int;
  v_from date := coalesce(nullif(spec ->> 'from', '')::date, (now() at time zone 'Asia/Kolkata')::date - 29);
  v_to date := coalesce(nullif(spec ->> 'to', '')::date, (now() at time zone 'Asia/Kolkata')::date);
  v_test boolean := coalesce((spec ->> 'test')::boolean, false); v_limit int := least(greatest(coalesce((spec ->> 'limit')::int, 500), 1), 5000);
  v_where text; v_scope text; v_sel text; v_grp text; v_sql text; v_rows jsonb; v_out jsonb := '{}'; v_sqls jsonb := '[]'; c jsonb; v_expr text; v_op text; v_cmp jsonb;
  v_team text; v_date text; v_cmp_from date; v_cmp_to date; v_all_rows jsonb;
begin
  if g is null then raise exception 'not allowed' using errcode = '42501'; end if;
  select array_agg(x) into v_metrics from jsonb_array_elements_text(coalesce(spec -> 'metrics', '[]')) x;
  select array_agg(x) into v_dims from jsonb_array_elements_text(coalesce(spec -> 'dims', '[]')) x;
  if coalesce(array_length(v_metrics, 1), 0) = 0 then raise exception 'pick at least one metric'; end if;
  if array_length(v_metrics, 1) > 6 then raise exception 'at most 6 metrics'; end if;
  if coalesce(array_length(v_dims, 1), 0) > 2 then raise exception 'at most 2 dimensions'; end if;
  if v_to < v_from or v_to - v_from > 1100 then raise exception 'the date range must run forwards and cover at most 3 years'; end if;
  select team into v_team from b2c.users where user_id = p_user;
  foreach k in array v_metrics loop
    select * into m from b2c.metric_defs where key = k;
    if m.key is null then raise exception 'unknown metric: %', k; end if;
    if not g = any (m.roles) then raise exception 'metric % is not available to your role', k; end if;
  end loop;
  foreach k in array coalesce(v_dims, '{}') loop
    select * into d from b2c.dim_defs where key = k;
    if d.key is null then raise exception 'unknown dimension: %', k; end if;
  end loop;
  -- comparison period
  if spec ->> 'compare' = 'previous' then v_cmp_to := v_from - 1; v_cmp_from := v_cmp_to - (v_to - v_from);
  elsif spec ->> 'compare' = 'year' then v_cmp_from := (v_from - interval '1 year')::date; v_cmp_to := (v_to - interval '1 year')::date; end if;

  foreach k in array v_metrics loop
    select * into m from b2c.metric_defs where key = k;
    select * into s from b2c.an_sources where key = m.source;
    v_date := coalesce(m.date_sql, 'now()');
    -- the role's scope: never optional
    v_scope := case g
      when 'sales' then case when p_role = 'sales_head'
                             then format('(%1$s in (select w.user_id from b2c.users w where w.role in (''counsellor'', ''sales_head'') and (%2$L is null or w.team = %2$L or w.user_id = %3$L)))', s.actor_sql, v_team, p_user)
                             else format('(%s = %L%s)', s.actor_sql, p_user, case when m.source in ('leads', 'replies', 'journeys', 'commission') then '' else format(' and f.owner_id = %L', p_user) end) end
      else 'true' end;
    v_where := format('%s and (x.lead_id is null or (coalesce(f.is_test, false) = %L and not coalesce(f.deleted, false)))', v_scope, v_test);
    if m.where_sql is not null then v_where := v_where || ' and (' || m.where_sql || ')'; end if;
    -- user filters, by dimension key only
    for c in select * from jsonb_array_elements(coalesce(spec -> 'filters', '[]')) loop
      select * into d from b2c.dim_defs where key = c ->> 'dim';
      if d.key is null then raise exception 'unknown dimension in a filter: %', c ->> 'dim'; end if;
      if d.sources is not null and not m.source = any (d.sources) then continue; end if;
      if d.money and g = 'sales' and m.source <> 'commission' then raise exception 'that filter is not available to your role'; end if;
      v_expr := '(' || replace(d.expr, ':date', v_date) || ')';
      v_op := coalesce(c ->> 'op', 'eq');
      v_where := v_where || ' and ' || case v_op
        when 'eq' then format('%s::text = %L', v_expr, c ->> 'value')
        when 'neq' then format('%s::text is distinct from %L', v_expr, c ->> 'value')
        when 'in' then format('%s::text = any (%L::text[])', v_expr, (select array_agg(x) from jsonb_array_elements_text(c -> 'value') x))
        when 'not_in' then format('not coalesce(%s::text = any (%L::text[]), false)', v_expr, (select array_agg(x) from jsonb_array_elements_text(c -> 'value') x))
        when 'contains' then format('%s::text ilike %L', v_expr, '%' || (c ->> 'value') || '%')
        when 'is_null' then format('%s is null', v_expr)
        when 'not_null' then format('%s is not null', v_expr)
        else null end;
      if v_where is null then raise exception 'unknown filter operator: %', v_op; end if;
    end loop;
    -- dimensions valid for this metric's source
    v_sel := ''; v_grp := '';
    for i in 1 .. coalesce(array_length(v_dims, 1), 0) loop
      select * into d from b2c.dim_defs where key = v_dims[i];
      if d.sources is not null and not m.source = any (d.sources) then
        v_expr := 'null::text';
      elsif d.money and g = 'sales' and m.source <> 'commission' then
        raise exception 'that dimension is not available to your role';
      elsif d.key in ('day', 'week', 'month') and m.date_sql is null then
        v_expr := 'null::text';
      else
        v_expr := '(' || replace(d.expr, ':date', v_date) || ')::text';
      end if;
      v_sel := v_sel || format('%s as d%s, ', v_expr, i);
      v_grp := v_grp || case when v_grp = '' then '' else ', ' end || i;
    end loop;
    v_sql := format('select %s(%s)::numeric as v from %s left join b2c.fact_leads f on f.lead_id = x.lead_id left join b2c.users u on u.user_id = %s where %s%s%s',
                    v_sel, m.agg, s.from_sql, s.actor_sql,
                    v_where,
                    case when m.date_sql is not null then format(' and %1$s >= (%2$L::date::timestamp at time zone ''Asia/Kolkata'') and %1$s < ((%3$L::date + 1)::timestamp at time zone ''Asia/Kolkata'')', m.date_sql, '%FROM%', '%TO%') else '' end,
                    case when v_grp <> '' then ' group by ' || v_grp else '' end);
    v_sqls := v_sqls || jsonb_build_object('metric', k, 'sql', replace(replace(v_sql, '%FROM%', v_from::text), '%TO%', v_to::text));
    execute format('select coalesce(jsonb_agg(jsonb_build_object(''k'', jsonb_build_array(%s), ''v'', q.v)), ''[]'') from (%s) q',
                   coalesce((select string_agg('q.d' || gi, ', ') from generate_series(1, coalesce(array_length(v_dims, 1), 0)) gi), ''),
                   replace(replace(v_sql, '%FROM%', v_from::text), '%TO%', v_to::text)) into v_rows;
    for c in select * from jsonb_array_elements(v_rows) loop
      v_out := jsonb_set(v_out, array[(c -> 'k')::text], coalesce(v_out -> ((c -> 'k')::text), jsonb_build_object('k', c -> 'k')) || jsonb_build_object(k, c -> 'v'));
    end loop;
    if v_cmp_from is not null then
      execute format('select coalesce(jsonb_agg(jsonb_build_object(''k'', jsonb_build_array(%s), ''v'', q.v)), ''[]'') from (%s) q',
                     coalesce((select string_agg('q.d' || gi, ', ') from generate_series(1, coalesce(array_length(v_dims, 1), 0)) gi), ''),
                     replace(replace(v_sql, '%FROM%', v_cmp_from::text), '%TO%', v_cmp_to::text)) into v_rows;
      for c in select * from jsonb_array_elements(v_rows) loop
        v_out := jsonb_set(v_out, array[(c -> 'k')::text], coalesce(v_out -> ((c -> 'k')::text), jsonb_build_object('k', c -> 'k')) || jsonb_build_object(k || '__cmp', c -> 'v'));
      end loop;
    end if;
  end loop;
  select coalesce(jsonb_agg(x order by x -> 'k'), '[]') into v_all_rows from (select value as x from jsonb_each(v_out) limit v_limit) q;
  return jsonb_build_object('rows', v_all_rows, 'metrics', v_metrics, 'dims', coalesce(to_jsonb(v_dims), '[]'), 'from', v_from, 'to', v_to,
                            'compare', case when v_cmp_from is not null then jsonb_build_object('from', v_cmp_from, 'to', v_cmp_to) end,
                            'test', v_test, 'sql', v_sqls, 'scope', case g when 'sales' then case when p_role = 'sales_head' then 'team' else 'own leads' end else 'all' end,
                            'defs', (select jsonb_agg(jsonb_build_object('key', md.key, 'label', md.label, 'fmt', md.fmt, 'higher_is_better', md.higher_is_better, 'counts_leads', md.counts_leads))
                                       from b2c.metric_defs md where md.key = any (v_metrics)));
end $f$;

grant select on b2c.ad_imports, b2c.ad_spend_daily, b2c.ad_campaign_map to authenticated;
do $d$ declare t text; begin
  foreach t in array array['ad_imports', 'ad_spend_daily', 'ad_campaign_map'] loop
    if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = t and policyname = 'marketing read') then
      execute format('create policy "marketing read" on b2c.%I for select to authenticated using ((select b2c.can(''marketing'')))', t);
    end if;
  end loop;
end $d$;
grant execute on function b2c.ad_spend_import(jsonb), b2c.ad_campaign_map_save(jsonb), b2c.ad_spend_overview(date, date) to authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
