-- M31o: Addendum 3, metrics, dimensions, dashboards and Admin alerts (docs/B2B_CRM_ADDENDUM_3.md; design m31o_a3_metrics;
-- CONTRACT.md section 12; review findings C2, C22, C53, C69, C70, C71, C86, C87, C90). Applied after pending/m31n_facts, which
-- gives the fact views the columns read here.
--   metric_dimensions()      the Addendum 3 dimensions: fact_leads b2c_reason, hold_kind, partner_barred, consent_state, sub_source;
--                            fact_allocations score_stage (= f.stage, the A/B/C score stage; 'stage' keeps meaning stage_reached,
--                            C90), origin, paid, platform, from_b2c and the lead dimensions; fact_sla, fact_enrollments and
--                            fact_money gain segment, course and lead dimensions (C70)
--   date basis (C70)         metric_date_col(fact, basis, default): created | routed | accepted | enrolled per fact;
--                            metric_rows / metric_values_at take the basis (the old metric_base_rows / metric_values wrap them
--                            with no basis); metric_run and metric_drill accept 'date_basis'; dashboard widgets carry it
--   metric_definitions       paid_share and performance_share relabelled for Addendum 3; effort metrics over received leads
--                            (C69); conversion metrics leave upheld duplicate claims out (C53); new stage shares, paid outcomes,
--                            partner bar, re-decisions, consent, factors, manual routes, expected NCPL, activities per open lead,
--                            CAPI match keys, cohort enrolment at 7/30/60/90 days, cascade acceptance, dead letters (C71, C90)
--                            and the calculated AI cost per 1,000 leads
--   default dashboards       Command Center (realised commission, partner health table), AI Optimiser (open recommendations;
--                            performance decisions filtered by score stage), Routing & Flow (Stage B or C, B2C hand-offs by
--                            reason, scoring stage per segment, consent), Sources & Ads (paid share, paid leads), Commission
--                            (by campaign), Data Quality (dead letters)
--   admin_alerts.types       merged with every alert type that needs the Admin (C87); admin_alerts_settings_save accepts types[]
--   wa_template_text         WhatsApp template parameters cannot hold newlines or tabs (Meta error 132018): the sender flattens
--                            the text (C22); alert_digest_tick keeps one alert per line for e-mail and no longer loses events
--                            past the 50 shown or those committed after its snapshot (C86)
--   report_csv_admin         volatile, so its log_event works through PostgREST (C2)
-- Every function is create or replace with its existing signature; new functions get new names. Nothing here touches the fact
-- views themselves (pending/m31n_facts does), public.student_leads or any Witty object.

-- ---------- dimensions ----------
create or replace function b2b.metric_dimensions()
returns jsonb language sql immutable set search_path = '' as $fn$
  select '{
    "fact_leads": {"source":"f.source","sub_source":"f.sub_source","channel":"f.channel","campaign":"f.campaign","platform":"f.platform","paid":"f.paid","form":"f.form",
                   "utm_source":"f.utm_source","utm_medium":"f.utm_medium","city":"f.city","state":"f.state","course":"f.course","level":"f.level",
                   "mode":"f.mode","segment":"f.segment","specialization":"f.specialization","university":"f.university","lead_status":"f.lead_status",
                   "temperature":"f.temperature","stage":"f.stage","sub_stage":"f.sub_stage","lost_reason":"f.lost_reason","language":"f.language",
                   "destination":"f.destination","b2c_lane":"f.b2c_lane","b2c_reason":"f.b2c_reason","hold_kind":"f.hold_kind","partner_barred":"f.partner_barred",
                   "consent_state":"f.consent_state","not_passed_reason":"f.not_passed_reason","partner":"f.partner_id"},
    "fact_allocations": {"partner":"f.partner_id","segment":"f.segment","course":"f.course","level":"f.level","mode":"f.mode","routing_mode":"f.routing_mode",
                   "attempt_no":"f.attempt_no","status":"f.status","holdout":"f.holdout","scoring_mode":"f.scoring_mode","model_version":"f.model_version",
                   "counsellor":"f.counsellor","stage":"f.stage_reached","score_stage":"f.stage","origin":"f.origin","from_b2c":"f.from_b2c",
                   "paid":"f.paid","platform":"f.platform","programme":"f.programme",
                   "source":"f.source","sub_source":"f.sub_source","channel":"f.channel","form":"f.form","utm_source":"f.utm_source","utm_medium":"f.utm_medium",
                   "campaign":"f.campaign","city":"f.city","state":"f.state","university":"f.university","specialization":"f.specialization",
                   "lead_status":"f.lead_status","temperature":"f.temperature","sub_stage":"f.sub_stage","lost_reason":"f.lost_reason","language":"f.language"},
    "fact_enrollments": {"partner":"f.partner_id","course":"f.course","level":"f.level","mode":"f.mode","university":"f.university","status":"f.status","product":"f.product",
                   "programme":"f.programme","segment":"f.segment","source":"f.source","sub_source":"f.sub_source","campaign":"f.campaign","city":"f.city",
                   "state":"f.state","lead_status":"f.lead_status","language":"f.language","paid":"f.paid","platform":"f.platform"},
    "fact_sla": {"partner":"f.partner_id","sla":"f.sla","status":"f.status","due_hour":"f.due_hour","segment":"f.segment","course":"f.course","level":"f.level",
                   "mode":"f.mode","routing_mode":"f.routing_mode","attempt_no":"f.attempt_no","source":"f.source","campaign":"f.campaign","state":"f.state",
                   "lead_status":"f.lead_status","language":"f.language"},
    "fact_money": {"partner":"f.partner_id","kind":"f.kind","status":"f.status","period":"f.period","segment":"f.segment","course":"f.course",
                   "source":"f.source","campaign":"f.campaign","state":"f.state"},
    "fact_invoices": {"partner":"f.partner_id","status":"f.status","ageing":"f.ageing"},
    "fact_notifications": {"partner":"f.partner_id","channel":"f.channel","kind":"f.kind","language":"f.language","status":"f.status"},
    "fact_capi": {"platform":"f.platform","stage":"f.stage","status":"f.status"},
    "fact_sync": {"partner":"f.partner_id","status":"f.status"},
    "fact_ai": {"kind":"f.kind","run_kind":"f.run_kind","status":"f.status","rec_status":"f.rec_status"}
  }'::jsonb;
$fn$;

-- ---------- date basis (C70) ----------
/* The date column a basis names on a fact: null, '' or 'default' keeps the metric's own column; an unknown basis for the fact
   gives null (the caller raises). */
create or replace function b2b.metric_date_col(p_fact text, p_basis text, p_default text)
returns text language sql immutable set search_path = '' as $fn$
  select case when coalesce(p_basis, '') in ('', 'default') then p_default
              else '{"fact_leads":{"created":"created_at","routed":"routed_at","accepted":"accepted_at","enrolled":"enrolled_at"},
                     "fact_allocations":{"created":"created_at","routed":"created_at","accepted":"accepted_at"},
                     "fact_enrollments":{"created":"created_at","enrolled":"enrolled_at"}}'::jsonb -> p_fact ->> p_basis end;
$fn$;

/* One base metric over a period, dated by p_basis: rows of (dims as text[], value). */
create or replace function b2b.metric_rows(p_key text, p_dims text[], p_filters jsonb, p_from timestamptz, p_to timestamptz, p_test boolean, p_basis text)
returns table (d text[], value numeric) language plpgsql stable security definer set search_path = '' as $fn$
declare
  m b2b.metric_definitions;
  v_sel text := 'array[]::text[]';
  v_where text := '';
  v_expr text;
  k text;
  i int;
begin
  select * into m from b2b.metric_definitions where key = p_key and is_system;
  if m.key is null then raise exception 'unknown metric %', p_key using errcode = '22023'; end if;
  m.date_col := b2b.metric_date_col(m.fact, p_basis, m.date_col);
  if m.date_col is null then raise exception '% cannot be dated by %', m.label, p_basis using errcode = '22023'; end if;
  if coalesce(cardinality(p_dims), 0) > 0 then
    v_sel := 'array[';
    for i in 1 .. cardinality(p_dims) loop
      v_expr := b2b.metric_dim_expr(m.fact, m.date_col, p_dims[i]);
      if v_expr is null then raise exception '% cannot be broken down by %', m.label, p_dims[i] using errcode = '22023'; end if;
      v_sel := v_sel || case when i > 1 then ', ' else '' end || format('(%s)::text', v_expr);
    end loop;
    v_sel := v_sel || ']';
  end if;
  for k in select jsonb_object_keys(coalesce(p_filters, '{}')) loop
    v_expr := b2b.metric_dim_expr(m.fact, m.date_col, k);
    if v_expr is null then raise exception '% cannot be filtered by %', m.label, k using errcode = '22023'; end if;
    v_where := v_where || format(' and coalesce((%s)::text, '''') in (select jsonb_array_elements_text($1 -> %L))', v_expr, k);
  end loop;
  return query execute format(
    'select %s, (%s)::numeric from b2b.%I f where f.%I >= $2 and f.%I < $3 %s %s %s',
    v_sel, m.agg, m.fact, m.date_col, m.date_col, case when p_test then '' else 'and not f.is_test' end, v_where,
    case when coalesce(cardinality(p_dims), 0) > 0 then ' group by 1' else '' end)
    using p_filters, p_from, p_to;
end $fn$;

/* m27b's metric_base_rows: the metric's own date column. */
create or replace function b2b.metric_base_rows(p_key text, p_dims text[], p_filters jsonb, p_from timestamptz, p_to timestamptz, p_test boolean)
returns table (d text[], value numeric) language plpgsql stable security definer set search_path = '' as $fn$
begin
  return query select x.d, x.value from b2b.metric_rows(p_key, p_dims, p_filters, p_from, p_to, p_test, null) x;
end $fn$;

/* The values of a metric (system or calculated) by dims over one period, dated by p_basis: {dims-key: value}. */
create or replace function b2b.metric_values_at(m b2b.metric_definitions, p_dims text[], p_filters jsonb, p_from timestamptz, p_to timestamptz, p_test boolean, p_basis text)
returns table (d text[], value numeric) language plpgsql stable security definer set search_path = '' as $fn$
begin
  if m.is_system then
    return query select x.d, x.value from b2b.metric_rows(m.key, p_dims, p_filters, p_from, p_to, p_test, p_basis) x;
    return;
  end if;
  return query
    with parts as (
      select bb.key, x.d, x.value from unnest(b2b.metric_bases(m)) bb(key)
      cross join lateral b2b.metric_rows(bb.key, p_dims, p_filters, p_from, p_to, p_test, p_basis) x),
    keys as (select distinct parts.d from parts)
    -- a count or sum base with no rows in a group is 0 there (avg, percentile and ratio bases stay null)
    select k.d, b2b.metric_eval(m.formula,
             (select coalesce(jsonb_object_agg(bb.key, coalesce(p.value, case when md.agg ~* '^(count\(|coalesce\(sum\()' then 0 end)), '{}')
                from unnest(b2b.metric_bases(m)) bb(key)
                join b2b.metric_definitions md on md.key = bb.key
                left join parts p on p.key = bb.key and p.d is not distinct from k.d))
      from keys k;
end $fn$;

/* m27b's metric_values: the metric's own date column. */
create or replace function b2b.metric_values(m b2b.metric_definitions, p_dims text[], p_filters jsonb, p_from timestamptz, p_to timestamptz, p_test boolean)
returns table (d text[], value numeric) language plpgsql stable security definer set search_path = '' as $fn$
begin
  return query select x.d, x.value from b2b.metric_values_at(m, p_dims, p_filters, p_from, p_to, p_test, null) x;
end $fn$;

/* p adds date_basis: created | routed | accepted | enrolled (absent: the metric's own date column); the result echoes it. */
create or replace function b2b.metric_run(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  m b2b.metric_definitions;
  v_dims text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p -> 'dims', '[]')) x), '{}');
  v_to timestamptz := coalesce((p ->> 'to')::timestamptz, now());
  v_from timestamptz := coalesce((p ->> 'from')::timestamptz, v_to - interval '30 days');
  v_len interval;
  v_cmp boolean := coalesce(p ->> 'compare', 'previous') = 'previous';
  v_test boolean := coalesce((p ->> 'include_test')::boolean, false);
  v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 100), 1), 2000);
  v_basis text := nullif(nullif(p ->> 'date_basis', ''), 'default');
  v_tpos int;                -- position of the first day / week / month breakdown, null without one
  v_rows jsonb;
  v_more boolean;
  v_total jsonb;
begin
  select * into m from b2b.metric_definitions where key = p ->> 'metric';
  if m.key is null then raise exception 'unknown metric %', coalesce(p ->> 'metric', '(none)') using errcode = '22023'; end if;
  if cardinality(v_dims) > 2 then raise exception 'at most two breakdowns' using errcode = '22023'; end if;
  if v_basis is not null and v_basis not in ('created', 'routed', 'accepted', 'enrolled') then raise exception 'unknown date basis' using errcode = '22023'; end if;
  if v_from >= v_to then raise exception 'the period is empty' using errcode = '22023'; end if;
  if v_to - v_from > interval '3 years' then raise exception 'at most three years at a time' using errcode = '22023'; end if;
  v_len := v_to - v_from;
  v_tpos := (select min(i) from generate_subscripts(v_dims, 1) i where v_dims[i] in ('day', 'week', 'month'));

  -- over the limit, a time series keeps its newest buckets (returned oldest first); otherwise the largest values are kept
  with cur as (select * from b2b.metric_values_at(m, v_dims, p -> 'filters', v_from, v_to, v_test, v_basis)),
       prev as (select * from b2b.metric_values_at(m, v_dims, p -> 'filters', v_from - v_len, v_from, v_test, v_basis) where v_cmp and v_tpos is null),
       j as (select c.d, c.value, pr.value prev from cur c left join prev pr on pr.d is not distinct from c.d),
       k as (select j.*, row_number() over (order by case when v_tpos is not null then j.d[v_tpos] end desc nulls last, j.value desc nulls last, j.d) rn from j)
  select coalesce(jsonb_agg(jsonb_build_object('d', to_jsonb(k.d), 'value', round(k.value, 4), 'prev', round(k.prev, 4))
                            order by case when v_tpos is not null then k.d[v_tpos] end, k.value desc nulls last, k.d) filter (where k.rn <= v_limit), '[]'),
         count(*) > v_limit
    into v_rows, v_more from k;

  select jsonb_build_object('value', round((select value from b2b.metric_values_at(m, '{}', p -> 'filters', v_from, v_to, v_test, v_basis) limit 1), 4),
                            'prev', case when v_cmp then round((select value from b2b.metric_values_at(m, '{}', p -> 'filters', v_from - v_len, v_from, v_test, v_basis) limit 1), 4) end)
    into v_total;

  return jsonb_build_object(
    'metric', jsonb_build_object('key', m.key, 'label', m.label, 'unit', m.unit, 'area', m.area, 'higher_is_better', m.higher_is_better,
                                 'description', m.description, 'calculated', not m.is_system),
    'dims', to_jsonb(v_dims), 'from', v_from, 'to', v_to, 'date_basis', v_basis, 'rows', v_rows, 'limit', v_limit, 'truncated', coalesce(v_more, false), 'total', v_total,
    'labels', jsonb_build_object('partner', coalesce((select jsonb_object_agg(p2.id::text, coalesce(p2.display_name, p2.name)) from b2b.partners p2), '{}')));
end $fn$;

/* The rows behind a number. p: {metric, filters (including the clicked breakdown values), from, to, limit, date_basis}. */
create or replace function b2b.metric_drill(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  m b2b.metric_definitions;
  v_fact text;
  v_date text;
  v_where text := '';
  v_expr text;
  k text;
  v_to timestamptz := coalesce((p ->> 'to')::timestamptz, now());
  v_from timestamptz := coalesce((p ->> 'from')::timestamptz, v_to - interval '30 days');
  v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 200), 1), 500);
  v_rows jsonb;
  v_n bigint;
begin
  select * into m from b2b.metric_definitions where key = p ->> 'metric';
  if m.key is null then raise exception 'unknown metric' using errcode = '22023'; end if;
  if not m.is_system then
    -- a calculated metric drills into its first base metric
    select * into m from b2b.metric_definitions where key = (b2b.metric_bases(m))[1];
  end if;
  v_fact := m.fact;
  v_date := b2b.metric_date_col(v_fact, p ->> 'date_basis', m.date_col);
  if v_date is null then raise exception '% cannot be dated by %', m.label, p ->> 'date_basis' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(coalesce(p -> 'filters', '{}')) loop
    v_expr := b2b.metric_dim_expr(v_fact, v_date, k);
    if v_expr is null then raise exception 'cannot filter by %', k using errcode = '22023'; end if;
    v_where := v_where || format(' and coalesce((%s)::text, '''') in (select jsonb_array_elements_text($1 -> %L))', v_expr, k);
  end loop;
  if m.drill_where is not null then v_where := v_where || ' and (' || m.drill_where || ')'; end if;
  execute format('select count(*), coalesce(jsonb_agg(to_jsonb(x) order by x.%I desc), ''[]'') from (select f.* from b2b.%I f where f.%I >= $2 and f.%I < $3 and not f.is_test %s order by f.%I desc limit %s) x',
                 v_date, v_fact, v_date, v_date, v_where, v_date, v_limit)
    into v_n, v_rows using p -> 'filters', v_from, v_to;
  return jsonb_build_object('metric', m.key, 'fact', v_fact, 'rows', v_rows, 'shown', v_n, 'limit', v_limit,
                            'labels', jsonb_build_object('partner', coalesce((select jsonb_object_agg(p2.id::text, coalesce(p2.display_name, p2.name)) from b2b.partners p2), '{}')));
end $fn$;

-- ---------- dashboards: widgets carry a date basis ----------
create or replace function b2b.dashboard_check_widgets(p jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare w jsonb; v_ids text[] := '{}'; k text; d text; v_out jsonb := '[]';
begin
  if jsonb_typeof(p) <> 'array' then raise exception 'widgets must be a list' using errcode = '22023'; end if;
  if jsonb_array_length(p) > 40 then raise exception 'at most 40 widgets' using errcode = '22023'; end if;
  for w in select * from jsonb_array_elements(p) loop
    if coalesce(w ->> 'id', '') !~ '^[A-Za-z0-9_-]{1,20}$' or w ->> 'id' = any (v_ids) then raise exception 'each widget needs its own id' using errcode = '22023'; end if;
    v_ids := v_ids || (w ->> 'id');
    if w ->> 'type' not in ('kpi', 'line', 'bar', 'stacked', 'funnel', 'sankey', 'heatmap', 'table', 'leaderboard', 'map', 'gauge', 'sla_timers', 'alerts', 'text') then
      raise exception 'unknown widget type %', w ->> 'type' using errcode = '22023';
    end if;
    if w ->> 'type' = 'sankey' and jsonb_array_length(coalesce(w -> 'steps', '[]')) < 2 then
      raise exception '"%" needs at least two steps', w ->> 'title' using errcode = '22023';
    end if;
    if w ->> 'type' is null or w ->> 'w' is null or w ->> 'h' is null then raise exception 'each widget needs a type and a size' using errcode = '22023'; end if;
    if not ((w ->> 'w')::int between 1 and 12) or not ((w ->> 'h')::int between 1 and 4) then raise exception 'widget sizes are 1–12 wide and 1–4 high' using errcode = '22023'; end if;
    if (w ->> 'date_basis') is not null and w ->> 'date_basis' not in ('created', 'routed', 'accepted', 'enrolled') then raise exception 'unknown date basis' using errcode = '22023'; end if;
    if w ->> 'type' not in ('sla_timers', 'alerts', 'text') then
      for k in select coalesce(w ->> 'metric', x) from (select null::text x union all select jsonb_array_elements_text(coalesce(w -> 'metrics', '[]'))) z where coalesce(w ->> 'metric', x) is not null loop
        if not exists (select 1 from b2b.metric_definitions where key = k) then raise exception 'unknown metric % in "%"', k, w ->> 'title' using errcode = '22023'; end if;
        -- every breakdown and sankey step must exist on every base metric (system or calculated)
        for d in select jsonb_array_elements_text(coalesce(w -> 'dims', '[]') || coalesce(w -> 'steps', '[]')) loop
          if exists (select 1 from b2b.metric_definitions x cross join unnest(b2b.metric_bases(x)) bb(key)
                     join b2b.metric_definitions y on y.key = bb.key
                      where x.key = k and b2b.metric_dim_expr(y.fact, y.date_col, d) is null) then
            raise exception '% cannot be broken down by %', (select x2.label from b2b.metric_definitions x2 where x2.key = k), d using errcode = '22023';
          end if;
        end loop;
        -- and every base metric must be datable by the widget's date basis
        if (w ->> 'date_basis') is not null and exists (select 1 from b2b.metric_definitions x cross join unnest(b2b.metric_bases(x)) bb(key)
                                                          join b2b.metric_definitions y on y.key = bb.key
                                                         where x.key = k and b2b.metric_date_col(y.fact, w ->> 'date_basis', y.date_col) is null) then
          raise exception '% cannot be dated by %', (select x2.label from b2b.metric_definitions x2 where x2.key = k), w ->> 'date_basis' using errcode = '22023';
        end if;
      end loop;
      if w ->> 'metric' is null and jsonb_array_length(coalesce(w -> 'metrics', '[]')) = 0 then raise exception '"%" needs a metric', w ->> 'title' using errcode = '22023'; end if;
    end if;
    if jsonb_array_length(coalesce(w -> 'dims', '[]')) > 2 or jsonb_array_length(coalesce(w -> 'steps', '[]')) > 4 then raise exception 'too many breakdowns in "%"', w ->> 'title' using errcode = '22023'; end if;
    if w ? 'period' and w ->> 'period' not in ('today', '7d', '30d', '90d', 'month', 'quarter', 'year') then raise exception 'unknown period' using errcode = '22023'; end if;
    v_out := v_out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'id', w ->> 'id', 'type', w ->> 'type', 'title', left(coalesce(w ->> 'title', ''), 80), 'metric', w ->> 'metric', 'metrics', w -> 'metrics',
      'dims', w -> 'dims', 'steps', w -> 'steps', 'filters', w -> 'filters', 'period', w ->> 'period', 'date_basis', w ->> 'date_basis', 'sort', w ->> 'sort',
      'target', w -> 'target', 'text', left(w ->> 'text', 1000), 'w', (w ->> 'w')::int, 'h', (w ->> 'h')::int)));
  end loop;
  return v_out;
end $fn$;

/* A widget's data: the metric layer for chart widgets (dated by the widget's date_basis), the special lists for the rest. */
create or replace function b2b.widget_data(w jsonb, p_period text, p_filters jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  r tstzrange := b2b.period_range(coalesce(w ->> 'period', p_period));
  f jsonb := coalesce(p_filters, '{}') || coalesce(w -> 'filters', '{}');
  v_ok jsonb;
  k text;
  m text;
  v_out jsonb := '[]';
  i int;
begin
  if w ->> 'type' = 'text' then return '{}'; end if;
  if w ->> 'type' = 'sla_timers' then
    -- open SLAs and breaches still owed (the rule of sla_timers; it mirrors sla_tick's void rule and 30-day re-check window)
    return jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'lead_id', c.lead_id, 'sla', c.sla, 'due_at', c.due_at, 'status', c.status,
                                                                                     'partner', coalesce(p.display_name, p.name)) order by c.due_at)
                                                  from (select c.* from b2b.sla_checks c join b2b.allocations y on y.id = c.allocation_id
                                                         where c.status in ('pending', 'breached') and not c.is_test
                                                           and (c.status = 'pending'
                                                                or (c.status = 'breached' and c.due_at > now() - interval '30 days'
                                                                    and case when c.sla = 'enrollment_proof' then y.status not in ('duplicate', 'rejected', 'recalled', 'failed')
                                                                             else y.status in ('pushed', 'accepted')
                                                                                  and not exists (select 1 from public.student_leads l where l.id = y.lead_id and l.allocation_id = y.id
                                                                                                     and l.stage in ('enrolled', 'verified', 'commission_booked', 'paid', 'lost')) end))
                                                           and (f -> 'partner' is null or c.partner_id::text in (select jsonb_array_elements_text(f -> 'partner')))
                                                         order by c.due_at limit 15) c join b2b.partners p on p.id = c.partner_id), '[]'));
  end if;
  if w ->> 'type' = 'alerts' then
    return jsonb_build_object('rows', coalesce((select jsonb_agg(jsonb_build_object('type', e.type, 'at', e.occurred_at, 'partner', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = e.partner_id),
                                                                                     'payload', e.payload - 'phone' - 'email' - 'name') order by e.occurred_at desc)
                                                  from (select * from b2b.events e where (e.type like 'alert.%' or e.type = 'routing.error') order by e.occurred_at desc limit 12) e), '[]'));
  end if;
  -- dashboard filters apply only where every base of the metric has that dimension
  for m in select coalesce(w ->> 'metric', x) from (select null::text x union all select jsonb_array_elements_text(coalesce(w -> 'metrics', '[]'))) z
            where coalesce(w ->> 'metric', x) is not null loop
    v_ok := (select coalesce(jsonb_object_agg(fk, fv), '{}') from jsonb_each(f) e(fk, fv)
              where not exists (select 1 from b2b.metric_definitions d
                                  cross join lateral unnest(b2b.metric_bases(d)) b(k)
                                  join b2b.metric_definitions d2 on d2.key = b.k
                                 where d.key = m and b2b.metric_dim_expr(d2.fact, d2.date_col, fk) is null));
    if w ->> 'type' = 'sankey' then
      for i in 1 .. jsonb_array_length(w -> 'steps') - 1 loop
        v_out := v_out || jsonb_build_array(b2b.metric_run(jsonb_build_object('metric', m, 'dims', jsonb_build_array(w -> 'steps' ->> (i - 1), w -> 'steps' ->> i),
                                                                              'filters', v_ok, 'from', lower(r), 'to', upper(r), 'compare', 'none', 'limit', 200,
                                                                              'date_basis', w ->> 'date_basis')));
      end loop;
    else
      v_out := v_out || jsonb_build_array(b2b.metric_run(jsonb_build_object('metric', m, 'dims', coalesce(w -> 'dims', '[]'), 'filters', v_ok,
                                                                            'from', lower(r), 'to', upper(r), 'compare', case when w ->> 'type' in ('kpi', 'gauge', 'table', 'leaderboard') then 'previous' else 'none' end,
                                                                            'limit', case when w ->> 'type' in ('kpi', 'gauge') then 1 else 500 end,
                                                                            'date_basis', w ->> 'date_basis')));
    end if;
  end loop;
  return jsonb_build_object('series', v_out, 'from', lower(r), 'to', upper(r));
end $fn$;

-- ---------- the metric catalogue (system metrics; the Admin's calculated ones are untouched) ----------
insert into b2b.metric_definitions (key, label, area, unit, fact, agg, date_col, drill_where, higher_is_better, description) values
  -- relabelled or redefined by Addendum 3
  ('paid_share', 'From paid Meta / Google ads', 'Intake', 'pct', 'fact_leads', 'avg(f.paid::int)', 'created_at', 'f.paid', true, 'Meta Lead Ads, Google lead forms and Meta / Google ad clicks: an attribution label, not a routing rule'),
  ('performance_share', 'Decided on effort and SLA (Stage B or C)', 'Routing', 'pct', 'fact_allocations', 'avg((f.stage in (''B'', ''C''))::int)', 'created_at', 'f.stage in (''B'', ''C'')', true, 'Share of partner allocations scored at Stage B or C'),
  ('commission_realised', 'Commission realised', 'Commission', 'inr', 'fact_money', 'coalesce(sum(f.net_inr) filter (where f.status = ''realised''), 0)', 'realised_at', 'f.status = ''realised''', true, 'Net of GST, by the date it was realised'),
  -- effort over the leads the partner received (C69)
  ('attempts_24h', 'Attempts in the first 24 h', 'Sales effort', 'number', 'fact_allocations', 'avg(f.attempts_24h)', 'created_at', 'f.received', true, 'Leads the partner received'),
  ('attempts_72h', 'Attempts in the first 72 h', 'Sales effort', 'number', 'fact_allocations', 'avg(f.attempts_72h)', 'created_at', 'f.received', true, 'Leads the partner received'),
  ('stale_share', 'Stale (no update in 7 days)', 'Sales effort', 'pct', 'fact_allocations', 'avg(f.stale::int)', 'created_at', 'f.stale', false, 'Open allocations'),
  ('contacted_rate', 'Contacted or further', 'Lead stages', 'pct', 'fact_allocations', 'avg((f.stage_reached in (''contacted'', ''interested'', ''applied'') or f.enrolled)::int) filter (where f.received and not f.duplicate_upheld)', 'created_at', 'f.stage_reached in (''contacted'', ''interested'', ''applied'') or f.enrolled', true, 'Leads the partner received; upheld duplicate claims left out'),
  ('interested_rate', 'Counselled or further', 'Lead stages', 'pct', 'fact_allocations', 'avg((f.stage_reached in (''interested'', ''applied'') or f.enrolled)::int) filter (where f.received and not f.duplicate_upheld)', 'created_at', 'f.stage_reached in (''interested'', ''applied'') or f.enrolled', true, 'Leads the partner received; upheld duplicate claims left out'),
  ('applied_rate', 'Applied', 'Lead stages', 'pct', 'fact_allocations', 'avg((f.stage_reached = ''applied'' or f.enrolled)::int) filter (where f.received and not f.duplicate_upheld)', 'created_at', 'f.stage_reached = ''applied'' or f.enrolled', true, 'Leads the partner received; upheld duplicate claims left out'),
  -- conversion without upheld duplicate claims (C53)
  ('enrol_rate', 'Enrolment rate (matured leads)', 'Conversion', 'pct', 'fact_allocations', 'avg(f.enrolled::int) filter (where f.matured and not f.duplicate_upheld)', 'created_at', 'f.matured and not f.duplicate_upheld', true, 'Leads older than the maturity window; upheld duplicate claims left out'),
  ('ncpl', 'Net commission per lead (realised)', 'Commission', 'inr', 'fact_allocations', 'avg(f.reward) filter (where f.matured and not f.duplicate_upheld)', 'created_at', 'f.matured and not f.duplicate_upheld', true, 'Matured leads; commission of enrolments not refunded or cancelled; upheld duplicate claims left out'),
  ('ncpl_holdout', 'NCPL, holdout leads', 'AI and ML', 'inr', 'fact_allocations', 'avg(f.reward) filter (where f.matured and f.holdout and not f.duplicate_upheld)', 'created_at', 'f.matured and f.holdout and not f.duplicate_upheld', true, null),
  ('ncpl_steered', 'NCPL, AI-steered leads', 'AI and ML', 'inr', 'fact_allocations', 'avg(f.reward) filter (where f.matured and not f.holdout and f.scoring_mode is not null and not f.duplicate_upheld)', 'created_at', 'f.matured and not f.holdout and f.scoring_mode is not null and not f.duplicate_upheld', true, null),
  -- staged scoring
  ('stage_a_share', 'Stage A: programme match, highest commission', 'Routing', 'pct', 'fact_allocations', 'avg((f.stage = ''A'')::int) filter (where f.stage is not null)', 'created_at', 'f.stage = ''A''', true, 'Of scored partner allocations'),
  ('stage_b_share', 'Stage B: commission × effort × SLA', 'Routing', 'pct', 'fact_allocations', 'avg((f.stage = ''B'')::int) filter (where f.stage is not null)', 'created_at', 'f.stage = ''B''', true, 'Of scored partner allocations'),
  ('stage_c_share', 'Stage C: commission per lead × effort × SLA', 'Routing', 'pct', 'fact_allocations', 'avg((f.stage = ''C'')::int) filter (where f.stage is not null)', 'created_at', 'f.stage = ''C''', true, 'Of scored partner allocations'),
  ('effort_factor_avg', 'Sales-effort factor (avg)', 'Sales effort', 'number', 'fact_allocations', 'avg(f.effort_factor)', 'created_at', 'f.effort_factor is not null', true, '1.0 = the segment median; applied at Stage B and C'),
  ('sla_factor_avg', 'SLA-adherence factor (avg)', 'SLAs', 'number', 'fact_allocations', 'avg(f.sla_factor)', 'created_at', 'f.sla_factor is not null', true, '1.0 = every SLA met; applied at Stage B and C'),
  ('ncpl_expected', 'Expected commission per lead (Stage C)', 'Commission', 'inr', 'fact_allocations', 'avg(f.ncpl_expected)', 'created_at', 'f.ncpl_expected is not null', true, 'Expected at routing, net of GST; set only for Stage C decisions'),
  ('manual_route_share', 'Manual routes', 'Routing', 'pct', 'fact_allocations', 'avg((f.routing_mode = ''manual'')::int)', 'created_at', 'f.routing_mode = ''manual''', false, 'Admin or B2C route-to-partners and re-routes'),
  -- paid leads, the partner bar, re-decisions, consent
  ('paid_to_partner_share', 'Paid leads sent to partners', 'Routing', 'pct', 'fact_leads', 'avg((f.destination = ''partner'')::int) filter (where f.paid)', 'created_at', 'f.paid and f.destination = ''partner''', true, 'Of paid Meta / Google leads'),
  ('paid_enrol_rate', 'Paid lead to enrolment', 'Conversion', 'pct', 'fact_leads', 'avg(f.enrolled::int) filter (where f.paid)', 'created_at', 'f.paid and f.enrolled', true, 'Paid Meta / Google leads, any destination'),
  ('barred_leads', 'Partner-barred leads', 'Routing', 'count', 'fact_leads', 'count(*) filter (where f.partner_barred)', 'created_at', 'f.partner_barred', false, 'Duplicate cascade or lost by a partner: B2C only, for ever'),
  ('requalified_to_partners', 'Requalified, then routed to partners', 'Routing', 'count', 'fact_allocations', 'count(*) filter (where f.origin = ''requalify'')', 'created_at', 'f.origin = ''requalify''', true, 'Leads that qualified in B2C nurture and went on to a partner'),
  ('reenquiries', 'Re-enquiries', 'Routing', 'count', 'fact_leads', 'coalesce(sum(f.reenquiries), 0)', 'created_at', 'f.reenquiries > 0', true, 'New enquiries from students already held by a partner or by B2C'),
  ('consent_yes_rate', 'Partner-sharing consent: YES', 'Consent', 'pct', 'fact_leads', 'avg((f.consent_state = ''given'')::int) filter (where f.consent_state in (''given'', ''refused'', ''withdrawn''))', 'created_at', 'f.consent_state = ''given''', true, 'Of leads with an answer (given, refused or withdrawn)'),
  -- B13.1 metrics one column away (C71)
  ('activities_per_open_lead', 'Activities per open lead (last 7 days)', 'Sales effort', 'number', 'fact_allocations', 'avg(f.activities_7d) filter (where f.status in (''pushed'', ''accepted'') and not coalesce(f.lost_grace, false))', 'created_at', 'f.status in (''pushed'', ''accepted'')', true, 'Outbound calls, WhatsApp, SMS, e-mail and meetings'),
  ('capi_match_keys', 'Match keys per conversion', 'CAPI', 'number', 'fact_capi', 'avg(f.match_keys) filter (where f.status = ''sent'')', 'created_at', 'f.status = ''sent''', true, 'Proxy for match quality'),
  ('enrol_rate_7d', 'Enrolled within 7 days', 'Conversion', 'pct', 'fact_allocations', 'avg((coalesce(f.days_to_enrol, 100000) <= 7)::int) filter (where f.received and f.age_days >= 7)', 'created_at', 'f.received and f.age_days >= 7 and f.days_to_enrol <= 7', true, 'Allocations at least 7 days old'),
  ('enrol_rate_30d', 'Enrolled within 30 days', 'Conversion', 'pct', 'fact_allocations', 'avg((coalesce(f.days_to_enrol, 100000) <= 30)::int) filter (where f.received and f.age_days >= 30)', 'created_at', 'f.received and f.age_days >= 30 and f.days_to_enrol <= 30', true, 'Allocations at least 30 days old'),
  ('enrol_rate_60d', 'Enrolled within 60 days', 'Conversion', 'pct', 'fact_allocations', 'avg((coalesce(f.days_to_enrol, 100000) <= 60)::int) filter (where f.received and f.age_days >= 60)', 'created_at', 'f.received and f.age_days >= 60 and f.days_to_enrol <= 60', true, 'Allocations at least 60 days old'),
  ('enrol_rate_90d', 'Enrolled within 90 days', 'Conversion', 'pct', 'fact_allocations', 'avg((coalesce(f.days_to_enrol, 100000) <= 90)::int) filter (where f.received and f.age_days >= 90)', 'created_at', 'f.received and f.age_days >= 90 and f.days_to_enrol <= 90', true, 'Allocations at least 90 days old'),
  ('cascade_accept_rate', 'Accepted after an earlier partner failed', 'Duplicates', 'pct', 'fact_allocations', 'avg(f.accepted::int) filter (where f.attempt_no > 1)', 'created_at', 'f.attempt_no > 1', true, 'Second and later partners in a cascade'),
  -- B13.4 (C90)
  ('dead_letters', 'Dead letters', 'System and mapping', 'count', 'fact_sync', 'count(*) filter (where f.dead_letter)', 'created_at', 'f.dead_letter', false, 'Partner events that failed or are held unmapped and were not discarded')
on conflict (key) do update
  set label = excluded.label, area = excluded.area, unit = excluded.unit, fact = excluded.fact, agg = excluded.agg, date_col = excluded.date_col,
      drill_where = excluded.drill_where, higher_is_better = excluded.higher_is_better, description = excluded.description, updated_at = now()
  where b2b.metric_definitions.is_system;

-- the calculated metric (C71); the Admin may change or keep it, so it is seeded once
insert into b2b.metric_definitions (key, label, area, unit, formula, higher_is_better, is_system, created_by)
values ('ai_cost_per_1000_leads', 'AI cost per 1,000 leads', 'AI and ML', 'usd', '[{"m":"ai_cost"},{"m":"leads"},{"op":"/"},{"n":1000},{"op":"*"}]', false, false, 'system')
on conflict (key) do nothing;

-- ---------- the default dashboards that change (B13.4; C90). Only the shipped defaults are updated; copies are the Admin's. ----------
insert into b2b.dashboards (slug, name, description, period, is_default, widgets) values
('command-center', 'Command Center', 'Today''s leads, routing, acceptance, duplicates, SLAs and commission; flow from source to partner to stage; alerts; partner health.', 'today', true, '[
  {"id":"k1","type":"kpi","title":"Leads today","metric":"leads","w":2,"h":1},
  {"id":"k2","type":"kpi","title":"Routed to partners","metric":"allocations","w":2,"h":1},
  {"id":"k3","type":"kpi","title":"Accepted","metric":"accept_rate","w":2,"h":1},
  {"id":"k4","type":"kpi","title":"Duplicate rate","metric":"duplicate_rate","w":2,"h":1},
  {"id":"k5","type":"kpi","title":"SLA compliance","metric":"sla_compliance","w":2,"h":1},
  {"id":"k6","type":"kpi","title":"Commission expected (month)","metric":"commission_expected","period":"month","w":2,"h":1},
  {"id":"k7","type":"kpi","title":"Commission realised (month)","metric":"commission_realised","period":"month","w":2,"h":1},
  {"id":"s1","type":"sankey","title":"Last 7 days: source → partner → stage","metric":"allocations","steps":["source","partner","stage"],"period":"7d","w":8,"h":3},
  {"id":"a1","type":"alerts","title":"Alerts","w":4,"h":3},
  {"id":"l1","type":"table","title":"Partner health","metrics":["sla_compliance","sync_lag","sync_error_rate"],"dims":["partner"],"period":"7d","w":6,"h":2},
  {"id":"l2","type":"leaderboard","title":"Leads today by partner","metric":"allocations","dims":["partner"],"w":6,"h":2}
]'),
('ai-optimiser', 'AI Optimiser', 'Net commission per lead, AI-steered against holdout; recommendations; AI cost; model use.', '90d', true, '[
  {"id":"k1","type":"kpi","title":"NCPL, AI-steered","metric":"ncpl_steered","period":"year","w":3,"h":1},
  {"id":"k2","type":"kpi","title":"NCPL, holdout","metric":"ncpl_holdout","period":"year","w":3,"h":1},
  {"id":"k3","type":"kpi","title":"Recommendations applied","metric":"ai_applied","w":3,"h":1},
  {"id":"k4","type":"kpi","title":"AI cost","metric":"ai_cost","w":3,"h":1},
  {"id":"k5","type":"kpi","title":"Open recommendations","metric":"ai_recommendations","filters":{"rec_status":["open"]},"period":"90d","w":3,"h":1},
  {"id":"c1","type":"bar","title":"NCPL by month: holdout or not","metric":"ncpl","dims":["month","holdout"],"period":"year","w":6,"h":2},
  {"id":"c2","type":"bar","title":"Recommendations by outcome","metric":"ai_recommendations","dims":["rec_status"],"w":6,"h":2},
  {"id":"c3","type":"bar","title":"Stage B and C decisions by model","metric":"allocations","dims":["model_version"],"filters":{"score_stage":["B","C"]},"w":12,"h":2}
]'),
('routing-flow', 'Routing & Flow', 'Where leads go: scoring stages, partner shares over time, hand-offs to B2C by reason, consent.', '90d', true, '[
  {"id":"c1","type":"stacked","title":"Leads to partners by week and partner","metric":"allocations","dims":["week","partner"],"w":8,"h":2},
  {"id":"k1","type":"kpi","title":"Exploration lane","metric":"exploration_share","w":2,"h":1},
  {"id":"k2","type":"kpi","title":"Stage B or C","metric":"performance_share","w":2,"h":1},
  {"id":"c2","type":"bar","title":"By routing mode","metric":"allocations","dims":["routing_mode"],"w":4,"h":2},
  {"id":"c3","type":"bar","title":"Leads by destination","metric":"leads","dims":["destination"],"w":6,"h":2},
  {"id":"c4","type":"bar","title":"B2C hand-offs by reason","metric":"to_b2c","dims":["b2c_reason"],"w":6,"h":2},
  {"id":"h1","type":"heatmap","title":"Scoring stage per segment","metric":"allocations","dims":["segment","score_stage"],"w":12,"h":2},
  {"id":"c5","type":"bar","title":"Consent funnel: partner-sharing consent by state","metric":"leads","dims":["consent_state"],"w":6,"h":2},
  {"id":"k3","type":"kpi","title":"Consent: YES","metric":"consent_yes_rate","w":2,"h":1},
  {"id":"k4","type":"kpi","title":"Partner-barred","metric":"barred_leads","w":2,"h":1},
  {"id":"k5","type":"kpi","title":"Requalified to partners","metric":"requalified_to_partners","w":2,"h":1},
  {"id":"x1","type":"text","title":"Segments","text":"CPE, effort, SLA and score per partner: Routing → Segments. Every decision: Routing → Decision log.","w":12,"h":1}
]'),
('commission', 'Commission & Receivables', 'Expected against realised, invoices, collection and ageing.', 'year', true, '[
  {"id":"k1","type":"kpi","title":"Expected","metric":"commission_expected","w":3,"h":1},
  {"id":"k2","type":"kpi","title":"Realised","metric":"commission_realised","w":3,"h":1},
  {"id":"k3","type":"kpi","title":"Outstanding","metric":"outstanding","w":3,"h":1},
  {"id":"k4","type":"kpi","title":"Collected","metric":"collection_rate","w":3,"h":1},
  {"id":"c1","type":"bar","title":"Realised by month","metric":"commission_realised","dims":["month"],"w":6,"h":2},
  {"id":"c2","type":"bar","title":"Outstanding by age","metric":"outstanding","dims":["ageing"],"w":6,"h":2},
  {"id":"c3","type":"bar","title":"Commission realised by campaign","metric":"commission_realised","dims":["campaign"],"w":12,"h":2},
  {"id":"t1","type":"table","title":"By partner","metrics":["commission_expected","commission_realised","invoiced","outstanding","collection_rate"],"dims":["partner"],"w":12,"h":2},
  {"id":"x1","type":"text","title":"Tier watch and statements","text":"Tier projections, statement variance and leakage: Commission & Finance.","w":12,"h":1}
]'),
('sources-ads', 'Sources & Ads', 'Leads and outcomes by source and campaign, paid Meta / Google leads, with conversion-API health.', '90d', true, '[
  {"id":"c1","type":"bar","title":"Leads by source","metric":"leads","dims":["source"],"w":6,"h":2},
  {"id":"c2","type":"bar","title":"Lead to enrolment by source","metric":"lead_enrol_rate","dims":["source"],"w":6,"h":2},
  {"id":"t1","type":"table","title":"Campaigns","metrics":["leads","leads_routed_rate","lead_enrol_rate"],"dims":["campaign"],"w":8,"h":2},
  {"id":"m1","type":"map","title":"Leads by state","metric":"leads","dims":["state"],"w":4,"h":2},
  {"id":"c3","type":"bar","title":"Conversions sent by platform","metric":"capi_sent","dims":["platform"],"w":6,"h":2},
  {"id":"k1","type":"kpi","title":"Conversions failed","metric":"capi_failed","w":3,"h":1},
  {"id":"k2","type":"kpi","title":"Paid Meta / Google share","metric":"paid_share","w":3,"h":1},
  {"id":"c4","type":"bar","title":"Paid leads by destination","metric":"leads","dims":["destination"],"filters":{"paid":["true"]},"w":6,"h":2},
  {"id":"k3","type":"kpi","title":"Paid leads sent to partners","metric":"paid_to_partner_share","w":3,"h":1},
  {"id":"k4","type":"kpi","title":"Paid lead to enrolment","metric":"paid_enrol_rate","w":3,"h":1}
]'),
('data-quality', 'Data Quality & Sync', 'Unmapped values, sync lag, errors and dead letters, the pre-routing pool and what is held back.', '7d', true, '[
  {"id":"c1","type":"bar","title":"Unmapped values by partner","metric":"unmapped_events","dims":["partner"],"w":6,"h":2},
  {"id":"c2","type":"bar","title":"Sync lag by partner","metric":"sync_lag","dims":["partner"],"w":6,"h":2},
  {"id":"k1","type":"kpi","title":"Sync errors","metric":"sync_error_rate","w":3,"h":1},
  {"id":"k2","type":"kpi","title":"Pre-routing pool","metric":"pool_size","period":"30d","w":3,"h":1},
  {"id":"k3","type":"kpi","title":"Not passed","metric":"not_passed","w":3,"h":1},
  {"id":"k4","type":"kpi","title":"Messages failed","metric":"notifications_failed","w":3,"h":1},
  {"id":"k5","type":"kpi","title":"Dead letters","metric":"dead_letters","period":"90d","w":3,"h":1},
  {"id":"c3","type":"bar","title":"Held back, by reason","metric":"not_passed","dims":["not_passed_reason"],"period":"30d","w":12,"h":2}
]')
on conflict (slug) do update set name = excluded.name, description = excluded.description, period = excluded.period, widgets = excluded.widgets, updated_at = now()
 where b2b.dashboards.is_default;

-- ---------- Admin alerts: the digest covers every alert type that needs the Admin (C87) ----------
do $types$
declare
  s jsonb;
  v_have jsonb;
  v_want jsonb;
begin
  select value into s from b2b.settings where key = 'admin_alerts';
  if s is null then return; end if;   -- m28b seeds the setting; nothing to merge into
  v_have := (select jsonb_agg(distinct x order by x) from jsonb_array_elements_text(coalesce(s -> 'types', '[]')) x);
  v_want := (select jsonb_agg(distinct x order by x) from jsonb_array_elements_text(coalesce(s -> 'types', '[]') ||
              '["alert.partner_rejected","alert.commission_dispute","alert.consent_unsendable","alert.consent_withdrawn","alert.partner_recall_notice",
                "alert.partner_optout_notice","alert.push_collect_error","alert.erasure_requested","alert.ai_rollback","alert.ai_review_worse",
                "alert.schedule_failed","alert.metric_invalid","alert.push_failed","alert.mapping_drift","alert.programme_sheet_failed",
                "alert.webhook_dead","alert.intake_failed","alert.partner_auth","alert.capi_auth"]'::jsonb) x);
  if v_have is distinct from v_want then
    perform b2b.set_setting('admin_alerts', jsonb_set(s, '{types}', v_want), 'Addendum 3 and review F82: every alert type that needs the Admin goes into the digest');
  end if;
end $types$;

/* The Admin's digest settings; 'types' (the alert types the digest carries) is editable: alert.* names or routing.error, up to
   60. alert.metric is not a digest type (metric alerts send their own message). */
create or replace function b2b.admin_alerts_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v jsonb := coalesce((select value from b2b.settings where key = 'admin_alerts'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'emails' and (jsonb_typeof(p -> 'emails') <> 'array' or jsonb_array_length(p -> 'emails') > 10
                       or exists (select 1 from jsonb_array_elements_text(p -> 'emails') x where x !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$')) then
    raise exception 'up to 10 e-mail addresses' using errcode = '22023';
  end if;
  if p ? 'whatsapp_numbers' and (jsonb_typeof(p -> 'whatsapp_numbers') <> 'array' or jsonb_array_length(p -> 'whatsapp_numbers') > 5
                                 or exists (select 1 from jsonb_array_elements_text(p -> 'whatsapp_numbers') x where x !~ '^[0-9]{10,15}$')) then
    raise exception 'up to 5 WhatsApp numbers, digits with the country code' using errcode = '22023';
  end if;
  if p ? 'digest_minutes' and not ((p ->> 'digest_minutes')::int between 5 and 1440) then raise exception 'the digest interval is 5 to 1440 minutes' using errcode = '22023'; end if;
  if p ? 'enabled' and jsonb_typeof(p -> 'enabled') <> 'boolean' then raise exception 'on or off' using errcode = '22023'; end if;
  if p ? 'types' and (jsonb_typeof(p -> 'types') <> 'array' or jsonb_array_length(p -> 'types') > 60
       or exists (select 1 from jsonb_array_elements_text(p -> 'types') x where x !~ '^(alert\.[a-z_]+|routing\.error)$' or x = 'alert.metric')) then
    raise exception 'unknown alert type' using errcode = '22023';
  end if;
  v := v || jsonb_strip_nulls(jsonb_build_object('enabled', p -> 'enabled', 'emails', p -> 'emails', 'whatsapp_numbers', p -> 'whatsapp_numbers',
                                                 'digest_minutes', (p ->> 'digest_minutes')::int, 'whatsapp_language', p ->> 'whatsapp_language',
                                                 'types', p -> 'types'))
       || case when p ? 'whatsapp_template' then jsonb_build_object('whatsapp_template', nullif(trim(p ->> 'whatsapp_template'), '')) else '{}' end;
  return b2b.set_setting('admin_alerts', v, p_reason);
end $fn$;

-- ---------- WhatsApp template text (C22): no newlines or tabs in a template parameter, at most 900 characters ----------
create or replace function b2b.wa_template_text(p text)
returns text language sql immutable set search_path = '' as $fn$
  select left(btrim(regexp_replace(regexp_replace(coalesce(p, ''), '\s*[\r\n\t]+\s*', ' | ', 'g'), ' {4,}', ' ', 'g'), ' |'), 900);
$fn$;

/* The provider request for one admin message (e-mail through the student-notification provider settings; WhatsApp through the
   Meta Cloud API with the Admin's approved template, its one parameter flattened by wa_template_text). */
create or replace function b2b.admin_message_request(m b2b.admin_messages)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  al jsonb := coalesce((select value from b2b.settings where key = 'admin_alerts'), '{}');
  e jsonb := coalesce(s -> 'email', '{}');
  w jsonb := coalesce(s -> 'whatsapp', '{}');
  v_key text;
begin
  if m.channel = 'whatsapp' then
    v_key := case when w ->> 'token_secret_id' is not null then b2b.partner_secret((w ->> 'token_secret_id')::uuid) end;
    if v_key is null or w ->> 'phone_number_id' is null or al ->> 'whatsapp_template' is null then return jsonb_build_object('error', 'WhatsApp for alerts is not configured (provider and an approved template)'); end if;
    return jsonb_build_object('provider', 'meta_cloud', 'many', true,
      'url', coalesce(w ->> 'base_url', 'https://graph.facebook.com') || '/' || coalesce(w ->> 'api_version', 'v21.0') || '/' || (w ->> 'phone_number_id') || '/messages',
      'headers', jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
      'bodies', (select jsonb_agg(jsonb_build_object('messaging_product', 'whatsapp', 'to', r, 'type', 'template',
                   'template', jsonb_build_object('name', al ->> 'whatsapp_template', 'language', jsonb_build_object('code', coalesce(al ->> 'whatsapp_language', 'en')),
                     'components', jsonb_build_array(jsonb_build_object('type', 'body', 'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', b2b.wa_template_text(m.subject || ': ' || m.body_text))))))))
                 from unnest(m.recipients) r));
  end if;
  v_key := case when e ->> 'api_key_secret_id' is not null then b2b.partner_secret((e ->> 'api_key_secret_id')::uuid) end;
  if v_key is null or e ->> 'from_email' is null then return jsonb_build_object('error', 'the e-mail provider is not configured (Notifications → Providers)'); end if;
  if coalesce(e ->> 'provider', 'resend') = 'brevo' then
    return jsonb_build_object('provider', 'brevo', 'url', coalesce(e ->> 'base_url', 'https://api.brevo.com') || '/v3/smtp/email',
      'headers', jsonb_build_object('Content-Type', 'application/json', 'api-key', v_key),
      'body', jsonb_strip_nulls(jsonb_build_object('sender', jsonb_build_object('name', 'Eduwit B2B CRM', 'email', e ->> 'from_email'),
        'to', (select jsonb_agg(jsonb_build_object('email', r)) from unnest(m.recipients) r), 'subject', m.subject, 'textContent', m.body_text,
        'htmlContent', m.body_html,
        'attachment', case when jsonb_array_length(m.attachments) > 0 then (select jsonb_agg(jsonb_build_object('name', a ->> 'filename', 'content', a ->> 'content_base64')) from jsonb_array_elements(m.attachments) a) end)));
  end if;
  return jsonb_build_object('provider', 'resend', 'url', coalesce(e ->> 'base_url', 'https://api.resend.com') || '/emails',
    'headers', jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'Idempotency-Key', 'admin-' || m.id),
    'body', jsonb_strip_nulls(jsonb_build_object('from', 'Eduwit B2B CRM <' || (e ->> 'from_email') || '>', 'to', to_jsonb(m.recipients), 'subject', m.subject,
      'text', m.body_text, 'html', m.body_html,
      'attachments', case when jsonb_array_length(m.attachments) > 0 then (select jsonb_agg(jsonb_build_object('filename', a ->> 'filename', 'content', a ->> 'content_base64')) from jsonb_array_elements(m.attachments) a) end)));
end $fn$;

-- ---------- the alert digest (C86): a window that ends 2 minutes ago, moved only to where it was read; the count covers every event ----------
/* New alert events since the last digest, as one message (B7.4: auto-pause, NCPL fall alerts, SLA breaches …). The window runs from
   the previous digest's 'until' (its created_at for older digests) to two minutes ago, so events whose transaction committed
   after the previous snapshot are still picked up; the subject counts every event in the window and the text shows the first
   50. E-mail keeps one alert per line; the WhatsApp copy is flattened by the sender (wa_template_text). */
create or replace function b2b.alert_digest_tick()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  al jsonb := coalesce((select value from b2b.settings where key = 'admin_alerts'), '{}');
  v_prev timestamptz := (select max(created_at) from b2b.admin_messages where kind = 'alert_digest');
  v_last timestamptz := coalesce((select max(coalesce((ref ->> 'until')::timestamptz, created_at)) from b2b.admin_messages where kind = 'alert_digest'),
                                 now() - interval '1 hour');
  v_until timestamptz := now() - interval '2 minutes';   -- events carry their transaction's start time: let in-flight ones commit first
  v_types text[] := array(select jsonb_array_elements_text(coalesce(al -> 'types', '[]')));
  v_n int; v_text text; v_html text;
begin
  if v_prev > now() - make_interval(mins => coalesce((al ->> 'digest_minutes')::int, 15)) then return 0; end if;
  if v_last >= v_until then return 0; end if;
  select count(*) into v_n from b2b.events e where e.occurred_at > v_last and e.occurred_at <= v_until and e.type = any (v_types);
  if v_n = 0 then return 0; end if;
  select string_agg(format('• %s%s%s', replace(replace(e.type, 'alert.', ''), '_', ' '),
                           coalesce(' — ' || (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = e.partner_id), ''),
                           coalesce(': ' || left(coalesce(e.payload ->> 'reason', e.payload ->> 'error', e.payload ->> 'segment', ''), 160), '')),
                    E'\n' order by e.occurred_at, e.id)
    into v_text
    from (select * from b2b.events e where e.occurred_at > v_last and e.occurred_at <= v_until and e.type = any (v_types)
           order by e.occurred_at, e.id limit 50) e;
  if v_n > 50 then v_text := v_text || E'\n… and ' || (v_n - 50) || ' more (Dashboards → Alerts)'; end if;
  v_html := '<div style="font-family:Arial,sans-serif;font-size:14px"><p><b>' || v_n || ' new alert' || case when v_n > 1 then 's' else '' end
            || '</b> in the Eduwit B2B CRM:</p><pre style="font-family:Arial,sans-serif;white-space:pre-wrap">' || b2b.html_escape(v_text) || '</pre></div>';
  return b2b.admin_queue('alert_digest', v_n || ' new alert' || case when v_n > 1 then 's' else '' end || ' in the B2B CRM', v_text, v_html, '[]',
                         jsonb_build_object('since', v_last, 'until', v_until, 'count', v_n), '{email,whatsapp}');
end $fn$;

-- ---------- reports (C2): the CSV export logs an event, so it cannot run read-only ----------
create or replace function b2b.report_csv_admin(p jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  perform b2b.log_event('analytics.report_exported', null, null, null, jsonb_build_object('id', p ->> 'id', 'kind', coalesce(p ->> 'kind', 'saved')));
  return b2b.report_csv(b2b.report_run(p));
end $fn$;

-- ---------- grants (create or replace keeps the existing ones; the new functions are internal) ----------
revoke execute on function b2b.metric_date_col(text, text, text), b2b.metric_rows(text, text[], jsonb, timestamptz, timestamptz, boolean, text),
                           b2b.metric_values_at(b2b.metric_definitions, text[], jsonb, timestamptz, timestamptz, boolean, text), b2b.wa_template_text(text)
  from public, anon, authenticated;
grant execute on function b2b.metric_date_col(text, text, text), b2b.metric_rows(text, text[], jsonb, timestamptz, timestamptz, boolean, text),
                          b2b.metric_values_at(b2b.metric_definitions, text[], jsonb, timestamptz, timestamptz, boolean, text), b2b.wa_template_text(text)
  to service_role;
revoke execute on function b2b.metric_dimensions(), b2b.metric_base_rows(text, text[], jsonb, timestamptz, timestamptz, boolean),
                           b2b.metric_values(b2b.metric_definitions, text[], jsonb, timestamptz, timestamptz, boolean), b2b.metric_run(jsonb), b2b.metric_drill(jsonb),
                           b2b.dashboard_check_widgets(jsonb), b2b.widget_data(jsonb, text, jsonb), b2b.admin_message_request(b2b.admin_messages), b2b.alert_digest_tick()
  from public, anon, authenticated;
grant execute on function b2b.metric_dimensions(), b2b.metric_base_rows(text, text[], jsonb, timestamptz, timestamptz, boolean),
                          b2b.metric_values(b2b.metric_definitions, text[], jsonb, timestamptz, timestamptz, boolean), b2b.metric_run(jsonb), b2b.metric_drill(jsonb),
                          b2b.dashboard_check_widgets(jsonb), b2b.widget_data(jsonb, text, jsonb), b2b.admin_message_request(b2b.admin_messages), b2b.alert_digest_tick()
  to service_role;
revoke execute on function b2b.admin_alerts_settings_save(jsonb, text), b2b.report_csv_admin(jsonb) from public, anon;
grant execute on function b2b.admin_alerts_settings_save(jsonb, text), b2b.report_csv_admin(jsonb) to authenticated, service_role;

-- ---------- the seeded dashboards pass the checks a saved dashboard passes (a bad seeded widget fails this migration) ----------
do $seeds$ begin perform b2b.dashboard_check_widgets(d.widgets) from b2b.dashboards d where d.is_default and d.archived_at is null; end $seeds$;
