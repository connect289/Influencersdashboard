-- M28a: dashboards (spec B13.3, B13.4, B14.3 "Dashboards: gallery of defaults and saved dashboards; builder").
--   dashboards      name, widgets (JSON: type, metric(s), breakdowns, filters, period, size), dashboard-wide period and
--                   filters, the nine defaults shipped (read-only; "duplicate to edit"), archive instead of delete
--   saved_views     a drill-down list saved by name (metric, filters, period)
--   settings 'analytics': which dashboard is the home screen (null: the Command Center)
--   dashboards_list / dashboard_get / dashboard_save / dashboard_copy / dashboard_archive / dashboard_set_home,
--   saved_view_save / saved_views_list, sla_timers (the live SLA list widget), alert_feed (the alerts widget)

create table if not exists b2b.dashboards (
  id          bigint generated always as identity primary key,
  slug        text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,59}$'),
  name        text not null,
  description text,
  widgets     jsonb not null default '[]',
  period      text not null default '30d' check (period in ('today', '7d', '30d', '90d', 'month', 'quarter', 'year')),
  filters     jsonb not null default '{}',
  is_default  boolean not null default false,
  archived_at timestamptz,
  created_by  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create table if not exists b2b.saved_views (
  id          bigint generated always as identity primary key,
  name        text not null,
  metric      text not null references b2b.metric_definitions (key),
  filters     jsonb not null default '{}',
  period      text not null default '30d',
  created_by  text,
  created_at  timestamptz not null default now()
);
do $rls$
declare t text;
begin
  foreach t in array array['dashboards', 'saved_views'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

insert into b2b.settings (key, value) values ('analytics', '{"home_dashboard_id": null}') on conflict (key) do nothing;

-- ---------- the nine default dashboards (B13.4) ----------
insert into b2b.dashboards (slug, name, description, period, is_default, widgets) values
('command-center', 'Command Center', 'Today''s leads, routing, acceptance, duplicates, SLAs and commission; flow from source to partner to stage; alerts; partner health.', 'today', true, '[
  {"id":"k1","type":"kpi","title":"Leads today","metric":"leads","w":2,"h":1},
  {"id":"k2","type":"kpi","title":"Routed to partners","metric":"allocations","w":2,"h":1},
  {"id":"k3","type":"kpi","title":"Accepted","metric":"accept_rate","w":2,"h":1},
  {"id":"k4","type":"kpi","title":"Duplicate rate","metric":"duplicate_rate","w":2,"h":1},
  {"id":"k5","type":"kpi","title":"SLA compliance","metric":"sla_compliance","w":2,"h":1},
  {"id":"k6","type":"kpi","title":"Commission expected (month)","metric":"commission_expected","period":"month","w":2,"h":1},
  {"id":"s1","type":"sankey","title":"Last 7 days: source → partner → stage","metric":"allocations","steps":["source","partner","stage"],"period":"7d","w":8,"h":3},
  {"id":"a1","type":"alerts","title":"Alerts","w":4,"h":3},
  {"id":"l1","type":"leaderboard","title":"Partner health: SLA compliance","metric":"sla_compliance","dims":["partner"],"period":"7d","w":6,"h":2},
  {"id":"l2","type":"leaderboard","title":"Leads today by partner","metric":"allocations","dims":["partner"],"w":6,"h":2}
]'),
('ai-optimiser', 'AI Optimiser', 'Net commission per lead, AI-steered against holdout; recommendations; AI cost; model use.', '90d', true, '[
  {"id":"k1","type":"kpi","title":"NCPL, AI-steered","metric":"ncpl_steered","period":"year","w":3,"h":1},
  {"id":"k2","type":"kpi","title":"NCPL, holdout","metric":"ncpl_holdout","period":"year","w":3,"h":1},
  {"id":"k3","type":"kpi","title":"Recommendations applied","metric":"ai_applied","w":3,"h":1},
  {"id":"k4","type":"kpi","title":"AI cost","metric":"ai_cost","w":3,"h":1},
  {"id":"c1","type":"bar","title":"NCPL by month: holdout or not","metric":"ncpl","dims":["month","holdout"],"period":"year","w":6,"h":2},
  {"id":"c2","type":"bar","title":"Recommendations by outcome","metric":"ai_recommendations","dims":["rec_status"],"w":6,"h":2},
  {"id":"c3","type":"bar","title":"Performance decisions by model","metric":"allocations","dims":["model_version"],"filters":{"scoring_mode":["performance"]},"w":12,"h":2}
]'),
('partner-league', 'Partner League Table', 'Every partner side by side, sorted by net commission per lead.', '90d', true, '[
  {"id":"t1","type":"table","title":"Partners","metrics":["allocations","accept_rate","contacted_rate","applied_rate","enrol_rate","ncpl","sla_compliance","duplicate_rate","cpe_avg"],"dims":["partner"],"sort":"ncpl","w":12,"h":3}
]'),
('partner-deep-dive', 'Partner Deep-Dive', 'One partner: funnel, effort, SLAs, cohorts, counsellors, commission and sync. Choose the partner in the filters.', '90d', true, '[
  {"id":"f1","type":"funnel","title":"Funnel","metrics":["accept_rate","contacted_rate","interested_rate","applied_rate","enrol_rate"],"w":6,"h":2},
  {"id":"k1","type":"kpi","title":"Time to first attempt","metric":"first_attempt_median","w":3,"h":1},
  {"id":"k2","type":"kpi","title":"Connect rate","metric":"connect_rate","w":3,"h":1},
  {"id":"k3","type":"kpi","title":"Attempts in 24 h","metric":"attempts_24h","w":3,"h":1},
  {"id":"k4","type":"kpi","title":"Stale leads","metric":"stale_share","w":3,"h":1},
  {"id":"h1","type":"heatmap","title":"SLA compliance by SLA and week","metric":"sla_compliance","dims":["sla","week"],"w":6,"h":2},
  {"id":"h2","type":"heatmap","title":"Cohorts: stage reached by allocation week","metric":"allocations","dims":["week","stage"],"w":6,"h":2},
  {"id":"t1","type":"table","title":"Counsellors","metrics":["allocations","first_attempt_median","connect_rate","contacted_rate"],"dims":["counsellor"],"w":6,"h":2},
  {"id":"c1","type":"line","title":"Commission realised by month","metric":"commission_realised","dims":["month"],"period":"year","w":6,"h":2},
  {"id":"k5","type":"kpi","title":"Sync errors","metric":"sync_error_rate","period":"7d","w":3,"h":1},
  {"id":"k6","type":"kpi","title":"Sync lag","metric":"sync_lag","period":"7d","w":3,"h":1}
]'),
('routing-flow', 'Routing & Flow', 'Where leads go: modes, partner shares over time, fallbacks to B2C.', '90d', true, '[
  {"id":"c1","type":"stacked","title":"Leads to partners by week and partner","metric":"allocations","dims":["week","partner"],"w":8,"h":2},
  {"id":"k1","type":"kpi","title":"Exploration lane","metric":"exploration_share","w":2,"h":1},
  {"id":"k2","type":"kpi","title":"Performance mode","metric":"performance_share","w":2,"h":1},
  {"id":"c2","type":"bar","title":"By routing mode","metric":"allocations","dims":["routing_mode"],"w":4,"h":2},
  {"id":"c3","type":"bar","title":"Leads by destination","metric":"leads","dims":["destination"],"w":6,"h":2},
  {"id":"c4","type":"bar","title":"Sent to B2C by lane","metric":"to_b2c","dims":["b2c_lane"],"w":6,"h":2},
  {"id":"x1","type":"text","title":"Segments","text":"Mode per segment, P̂ and NCPL per partner: Routing → Segments. Every decision: Routing → Overview → Decision log.","w":12,"h":1}
]'),
('sales-effort', 'Sales Effort & SLAs', 'How fast and how hard partners work their leads, and the SLA breaches due now.', '30d', true, '[
  {"id":"t1","type":"table","title":"Effort by partner","metrics":["first_attempt_median","first_attempt_p90","attempts_24h","attempts_72h","connect_rate","stale_share"],"dims":["partner"],"w":12,"h":2},
  {"id":"h1","type":"heatmap","title":"SLA compliance by partner and SLA","metric":"sla_compliance","dims":["partner","sla"],"w":6,"h":2},
  {"id":"c1","type":"bar","title":"Breaches by hour due","metric":"sla_breaches","dims":["due_hour"],"w":6,"h":2},
  {"id":"s1","type":"sla_timers","title":"Open SLAs due soonest","w":12,"h":2}
]'),
('commission', 'Commission & Receivables', 'Expected against realised, invoices, collection and ageing.', 'year', true, '[
  {"id":"k1","type":"kpi","title":"Expected","metric":"commission_expected","w":3,"h":1},
  {"id":"k2","type":"kpi","title":"Realised","metric":"commission_realised","w":3,"h":1},
  {"id":"k3","type":"kpi","title":"Outstanding","metric":"outstanding","w":3,"h":1},
  {"id":"k4","type":"kpi","title":"Collected","metric":"collection_rate","w":3,"h":1},
  {"id":"c1","type":"bar","title":"Realised by month","metric":"commission_realised","dims":["month"],"w":6,"h":2},
  {"id":"c2","type":"bar","title":"Outstanding by age","metric":"outstanding","dims":["ageing"],"w":6,"h":2},
  {"id":"t1","type":"table","title":"By partner","metrics":["commission_expected","commission_realised","invoiced","outstanding","collection_rate"],"dims":["partner"],"w":12,"h":2},
  {"id":"x1","type":"text","title":"Tier watch and statements","text":"Tier projections, statement variance and leakage: Commission & Finance.","w":12,"h":1}
]'),
('sources-ads', 'Sources & Ads', 'Leads and outcomes by source and campaign, with conversion-API health.', '90d', true, '[
  {"id":"c1","type":"bar","title":"Leads by source","metric":"leads","dims":["source"],"w":6,"h":2},
  {"id":"c2","type":"bar","title":"Lead to enrolment by source","metric":"lead_enrol_rate","dims":["source"],"w":6,"h":2},
  {"id":"t1","type":"table","title":"Campaigns","metrics":["leads","leads_routed_rate","lead_enrol_rate"],"dims":["campaign"],"w":8,"h":2},
  {"id":"m1","type":"map","title":"Leads by state","metric":"leads","dims":["state"],"w":4,"h":2},
  {"id":"c3","type":"bar","title":"Conversions sent by platform","metric":"capi_sent","dims":["platform"],"w":6,"h":2},
  {"id":"k1","type":"kpi","title":"Conversions failed","metric":"capi_failed","w":3,"h":1},
  {"id":"k2","type":"kpi","title":"Paid share","metric":"paid_share","w":3,"h":1}
]'),
('data-quality', 'Data Quality & Sync', 'Unmapped values, sync lag and errors, the pre-routing pool and what is held back.', '7d', true, '[
  {"id":"c1","type":"bar","title":"Unmapped values by partner","metric":"unmapped_events","dims":["partner"],"w":6,"h":2},
  {"id":"c2","type":"bar","title":"Sync lag by partner","metric":"sync_lag","dims":["partner"],"w":6,"h":2},
  {"id":"k1","type":"kpi","title":"Sync errors","metric":"sync_error_rate","w":3,"h":1},
  {"id":"k2","type":"kpi","title":"Pre-routing pool","metric":"pool_size","period":"30d","w":3,"h":1},
  {"id":"k3","type":"kpi","title":"Not passed","metric":"not_passed","w":3,"h":1},
  {"id":"k4","type":"kpi","title":"Messages failed","metric":"notifications_failed","w":3,"h":1},
  {"id":"c3","type":"bar","title":"Held back, by reason","metric":"not_passed","dims":["not_passed_reason"],"period":"30d","w":12,"h":2}
]')
on conflict (slug) do update set name = excluded.name, description = excluded.description, period = excluded.period, widgets = excluded.widgets, updated_at = now()
 where b2b.dashboards.is_default;

-- ---------- validation ----------
create or replace function b2b.dashboard_check_widgets(p jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare w jsonb; v_ids text[] := '{}'; k text; v_out jsonb := '[]';
begin
  if jsonb_typeof(p) <> 'array' then raise exception 'widgets must be a list' using errcode = '22023'; end if;
  if jsonb_array_length(p) > 40 then raise exception 'at most 40 widgets' using errcode = '22023'; end if;
  for w in select * from jsonb_array_elements(p) loop
    if coalesce(w ->> 'id', '') !~ '^[A-Za-z0-9_-]{1,20}$' or w ->> 'id' = any (v_ids) then raise exception 'each widget needs its own id' using errcode = '22023'; end if;
    v_ids := v_ids || (w ->> 'id');
    if w ->> 'type' not in ('kpi', 'line', 'bar', 'stacked', 'funnel', 'sankey', 'heatmap', 'table', 'leaderboard', 'map', 'gauge', 'sla_timers', 'alerts', 'text') then
      raise exception 'unknown widget type %', w ->> 'type' using errcode = '22023';
    end if;
    if not ((w ->> 'w')::int between 1 and 12) or not ((w ->> 'h')::int between 1 and 4) then raise exception 'widget sizes are 1–12 wide and 1–4 high' using errcode = '22023'; end if;
    if w ->> 'type' not in ('sla_timers', 'alerts', 'text') then
      for k in select coalesce(w ->> 'metric', x) from (select null::text x union all select jsonb_array_elements_text(coalesce(w -> 'metrics', '[]'))) z where coalesce(w ->> 'metric', x) is not null loop
        if not exists (select 1 from b2b.metric_definitions where key = k) then raise exception 'unknown metric % in "%"', k, w ->> 'title' using errcode = '22023'; end if;
      end loop;
      if w ->> 'metric' is null and jsonb_array_length(coalesce(w -> 'metrics', '[]')) = 0 then raise exception '"%" needs a metric', w ->> 'title' using errcode = '22023'; end if;
    end if;
    if jsonb_array_length(coalesce(w -> 'dims', '[]')) > 2 or jsonb_array_length(coalesce(w -> 'steps', '[]')) > 4 then raise exception 'too many breakdowns in "%"', w ->> 'title' using errcode = '22023'; end if;
    if w ? 'period' and w ->> 'period' not in ('today', '7d', '30d', '90d', 'month', 'quarter', 'year') then raise exception 'unknown period' using errcode = '22023'; end if;
    v_out := v_out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'id', w ->> 'id', 'type', w ->> 'type', 'title', left(coalesce(w ->> 'title', ''), 80), 'metric', w ->> 'metric', 'metrics', w -> 'metrics',
      'dims', w -> 'dims', 'steps', w -> 'steps', 'filters', w -> 'filters', 'period', w ->> 'period', 'sort', w ->> 'sort',
      'target', w -> 'target', 'text', left(w ->> 'text', 1000), 'w', (w ->> 'w')::int, 'h', (w ->> 'h')::int)));
  end loop;
  return v_out;
end $fn$;

-- ---------- Admin ----------
create or replace function b2b.dashboards_list()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'home_dashboard_id', (select (value ->> 'home_dashboard_id')::bigint from b2b.settings where key = 'analytics'),
    'dashboards', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'slug', d.slug, 'name', d.name, 'description', d.description, 'is_default', d.is_default,
                                                                'widgets', jsonb_array_length(d.widgets), 'updated_at', d.updated_at)
                                            order by d.is_default desc, d.id) from b2b.dashboards d where d.archived_at is null), '[]'),
    'views', coalesce((select jsonb_agg(to_jsonb(v) order by v.id desc) from b2b.saved_views v), '[]'));
end $fn$;

create or replace function b2b.dashboard_get(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select to_jsonb(d) || jsonb_build_object('is_home', d.id = (select (value ->> 'home_dashboard_id')::bigint from b2b.settings where key = 'analytics'))
            from b2b.dashboards d where d.id = p_id and d.archived_at is null);
end $fn$;

/* p: {id?, name, description, period, filters, widgets}. Defaults cannot be edited (duplicate them first). */
create or replace function b2b.dashboard_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint := nullif(p ->> 'id', '')::bigint; v_w jsonb; v_slug text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' or length(trim(p ->> 'name')) > 80 then raise exception 'give the dashboard a name (up to 80 characters)' using errcode = '22023'; end if;
  if coalesce(p ->> 'period', '30d') not in ('today', '7d', '30d', '90d', 'month', 'quarter', 'year') then raise exception 'unknown period' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(p -> 'filters', '{}')) <> 'object' then raise exception 'filters must be an object' using errcode = '22023'; end if;
  v_w := b2b.dashboard_check_widgets(coalesce(p -> 'widgets', '[]'));
  if v_id is null then
    v_slug := left(regexp_replace(lower(trim(p ->> 'name')), '[^a-z0-9]+', '-', 'g'), 40);
    v_slug := trim(both '-' from v_slug);
    if length(v_slug) < 2 then v_slug := 'dashboard'; end if;
    v_slug := v_slug || '-' || substr(md5(random()::text), 1, 5);
    insert into b2b.dashboards (slug, name, description, period, filters, widgets, created_by)
    values (v_slug, trim(p ->> 'name'), left(p ->> 'description', 300), coalesce(p ->> 'period', '30d'), coalesce(p -> 'filters', '{}'), v_w, coalesce(auth.uid()::text, 'admin'))
    returning id into v_id;
  else
    if exists (select 1 from b2b.dashboards where id = v_id and is_default) then raise exception 'built-in dashboards are read-only: duplicate it to change it' using errcode = '22023'; end if;
    update b2b.dashboards set name = trim(p ->> 'name'), description = left(p ->> 'description', 300), period = coalesce(p ->> 'period', '30d'),
           filters = coalesce(p -> 'filters', '{}'), widgets = v_w, updated_at = now()
     where id = v_id and archived_at is null;
    if not found then raise exception 'dashboard not found' using errcode = 'P0002'; end if;
  end if;
  perform b2b.log_event('analytics.dashboard_saved', null, null, null, jsonb_build_object('id', v_id));
  return jsonb_build_object('id', v_id);
end $fn$;

create or replace function b2b.dashboard_copy(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare d b2b.dashboards;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from b2b.dashboards where id = p_id and archived_at is null;
  if d.id is null then raise exception 'dashboard not found' using errcode = 'P0002'; end if;
  return b2b.dashboard_save(jsonb_build_object('name', left(d.name || ' (copy)', 80), 'description', d.description, 'period', d.period, 'filters', d.filters, 'widgets', d.widgets));
end $fn$;

create or replace function b2b.dashboard_archive(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.dashboards set archived_at = now() where id = p_id and not is_default and archived_at is null;
  if not found then raise exception 'only your own dashboards can be archived' using errcode = '22023'; end if;
  if (select (value ->> 'home_dashboard_id')::bigint from b2b.settings where key = 'analytics') = p_id then
    perform b2b.set_setting('analytics', '{"home_dashboard_id": null}', 'home dashboard archived');
  end if;
  return jsonb_build_object('archived', p_id);
end $fn$;

create or replace function b2b.dashboard_set_home(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_id is not null and not exists (select 1 from b2b.dashboards where id = p_id and archived_at is null) then raise exception 'dashboard not found' using errcode = 'P0002'; end if;
  perform b2b.set_setting('analytics', coalesce((select value from b2b.settings where key = 'analytics'), '{}') || jsonb_build_object('home_dashboard_id', p_id),
                          case when p_id is null then 'home: Command Center' else 'home: dashboard ' || p_id end);
  return jsonb_build_object('home_dashboard_id', p_id);
end $fn$;

create or replace function b2b.saved_view_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'give the view a name' using errcode = '22023'; end if;
  if not exists (select 1 from b2b.metric_definitions where key = p ->> 'metric') then raise exception 'unknown metric' using errcode = '22023'; end if;
  insert into b2b.saved_views (name, metric, filters, period, created_by)
  values (left(trim(p ->> 'name'), 80), p ->> 'metric', coalesce(p -> 'filters', '{}'), coalesce(p ->> 'period', '30d'), coalesce(auth.uid()::text, 'admin'))
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $fn$;

/* Open SLA checks, soonest due first (the live SLA timer widget). */
create or replace function b2b.sla_timers(p_partner bigint default null, p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'allocation_id', c.allocation_id, 'lead_id', c.lead_id, 'sla', c.sla, 'due_at', c.due_at,
                                                       'partner', coalesce(p.display_name, p.name), 'reference', a.reference) order by c.due_at)
                     from (select * from b2b.sla_checks c where c.status = 'pending' and not c.is_test and (p_partner is null or c.partner_id = p_partner)
                            order by c.due_at limit least(greatest(p_limit, 1), 100)) c
                     join b2b.partners p on p.id = c.partner_id left join b2b.allocations a on a.id = c.allocation_id), '[]');
end $fn$;

/* The latest alerts (the alerts widget). */
create or replace function b2b.alert_feed(p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'type', e.type, 'at', e.occurred_at, 'partner', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = e.partner_id),
                                                       'lead_id', e.lead_id, 'payload', e.payload) order by e.occurred_at desc)
                     from (select * from b2b.events e where (e.type like 'alert.%' or e.type = 'routing.error') order by e.occurred_at desc limit least(greatest(p_limit, 1), 100)) e), '[]');
end $fn$;

revoke execute on function b2b.dashboard_check_widgets(jsonb) from public, anon, authenticated;
grant execute on function b2b.dashboard_check_widgets(jsonb) to service_role;
revoke execute on function b2b.dashboards_list(), b2b.dashboard_get(bigint), b2b.dashboard_save(jsonb), b2b.dashboard_copy(bigint), b2b.dashboard_archive(bigint),
                           b2b.dashboard_set_home(bigint), b2b.saved_view_save(jsonb), b2b.sla_timers(bigint, int), b2b.alert_feed(int) from public, anon;
grant execute on function b2b.dashboards_list(), b2b.dashboard_get(bigint), b2b.dashboard_save(jsonb), b2b.dashboard_copy(bigint), b2b.dashboard_archive(bigint),
                          b2b.dashboard_set_home(bigint), b2b.saved_view_save(jsonb), b2b.sla_timers(bigint, int), b2b.alert_feed(int) to authenticated, service_role;
