-- M27b: the metric layer (spec B13.1–B13.3). Every number on a dashboard, report, alert or in "Ask the CRM" comes from here.
--   metric_definitions   the catalogue: system metrics (an aggregate over one fact, its date column, unit, area, whether
--                        higher is better, and which rows a drill-down shows) and the Admin's calculated metrics (a formula
--                        over other metrics, e.g. commission_realised / allocations)
--   metric_dimensions()  which dimensions each fact can be cut by (B13.2), plus day / week / month on its date column
--   metric_run(p)        {metric, dims (up to 2), filters {dim: [values]}, from, to, compare: previous|none, limit,
--                        include_test} -> rows with value and previous-period value, the total, labels for partner ids.
--                        Identifiers come only from the catalogue; values are bound parameters.
--   metric_drill(p)      the rows behind a number (leads, allocations, enrolments, SLA checks …), up to 500
--   metric_query / metric_drill_admin / metric_catalogue / metric_save   Admin-checked wrappers for the app

create table if not exists b2b.metric_definitions (
  key          text primary key check (key ~ '^[a-z][a-z0-9_]{1,59}$'),
  label        text not null,
  area         text not null,
  description  text,
  unit         text not null check (unit in ('count', 'pct', 'inr', 'hours', 'days', 'minutes', 'usd', 'number')),
  fact         text check (fact in ('fact_leads', 'fact_allocations', 'fact_enrollments', 'fact_sla', 'fact_money', 'fact_invoices',
                                    'fact_notifications', 'fact_capi', 'fact_sync', 'fact_ai')),
  agg          text,                       -- system metrics only (written by migrations, never by the app)
  date_col     text not null default 'created_at',
  drill_where  text,                       -- system: the rows a drill-down shows (null: every row in scope)
  formula      jsonb,                      -- calculated: RPN tokens [{"m":"key"} | {"n":1.5} | {"op":"+"}]
  higher_is_better boolean not null default true,
  is_system    boolean not null default true,
  created_by   text,
  updated_at   timestamptz not null default now(),
  check ((is_system and fact is not null and agg is not null and formula is null) or (not is_system and formula is not null and agg is null))
);
alter table b2b.metric_definitions enable row level security;
revoke all on b2b.metric_definitions from public, anon, authenticated;
grant all on b2b.metric_definitions to service_role;

insert into b2b.metric_definitions (key, label, area, unit, fact, agg, date_col, drill_where, higher_is_better, description) values
  -- intake
  ('leads', 'Leads', 'Intake', 'count', 'fact_leads', 'count(*)', 'created_at', null, true, 'New leads (not deleted or merged)'),
  ('leads_routed_rate', 'Routed', 'Intake', 'pct', 'fact_leads', 'avg((f.routed_at is not null)::int)', 'created_at', null, true, 'Share of leads that reached a CRM'),
  ('hours_to_route', 'Intake to routing (median)', 'Intake', 'hours', 'fact_leads', 'percentile_cont(0.5) within group (order by f.hours_to_route)', 'created_at', 'f.hours_to_route is not null', false, null),
  ('pool_size', 'In the pre-routing pool', 'Intake', 'count', 'fact_leads', 'count(*) filter (where f.destination = ''pool'')', 'created_at', 'f.destination = ''pool''', false, null),
  ('not_passed', 'Not passed (junk or mismatch)', 'Intake', 'count', 'fact_leads', 'count(*) filter (where f.destination = ''not_passed'')', 'created_at', 'f.destination = ''not_passed''', false, null),
  ('paid_share', 'From paid campaigns', 'Intake', 'pct', 'fact_leads', 'avg(f.paid::int)', 'created_at', 'f.paid', true, null),
  ('reopened', 'Reopened enquiries', 'Intake', 'count', 'fact_leads', 'count(*) filter (where f.reopened)', 'created_at', 'f.reopened', true, null),
  ('to_partners', 'Sent to partners', 'Intake', 'count', 'fact_leads', 'count(*) filter (where f.destination = ''partner'')', 'created_at', 'f.destination = ''partner''', true, null),
  ('to_b2c', 'Sent to B2C', 'Intake', 'count', 'fact_leads', 'count(*) filter (where f.destination = ''b2c'')', 'created_at', 'f.destination = ''b2c''', true, null),
  ('lead_enrol_rate', 'Lead to enrolment', 'Conversion', 'pct', 'fact_leads', 'avg(f.enrolled::int)', 'created_at', 'f.enrolled', true, 'Any destination'),
  -- routing
  ('allocations', 'Leads routed to partners', 'Routing', 'count', 'fact_allocations', 'count(*)', 'created_at', null, true, null),
  ('accept_rate', 'Accepted by partners', 'Routing', 'pct', 'fact_allocations', 'avg(f.accepted::int)', 'created_at', 'f.accepted', true, null),
  ('duplicate_rate', 'Duplicate rate', 'Duplicates', 'pct', 'fact_allocations', 'avg(f.duplicate::int)', 'created_at', 'f.duplicate', false, null),
  ('duplicates', 'Duplicates', 'Duplicates', 'count', 'fact_allocations', 'count(*) filter (where f.duplicate)', 'created_at', 'f.duplicate', false, null),
  ('rejections', 'Rejections', 'Duplicates', 'count', 'fact_allocations', 'count(*) filter (where f.rejected)', 'created_at', 'f.rejected', false, null),
  ('exploration_share', 'Exploration lane', 'Routing', 'pct', 'fact_allocations', 'avg((f.routing_mode = ''exploration'')::int)', 'created_at', 'f.routing_mode = ''exploration''', true, null),
  ('performance_share', 'Decided in performance mode', 'Routing', 'pct', 'fact_allocations', 'avg((f.scoring_mode = ''performance'')::int)', 'created_at', 'f.scoring_mode = ''performance''', true, null),
  ('cpe_avg', 'Commission per enrolment (avg)', 'Commission', 'inr', 'fact_allocations', 'avg(f.cpe)', 'created_at', null, true, 'Net of GST, of the partner the lead went to'),
  -- effort and SLAs
  ('first_attempt_median', 'Time to first attempt (median)', 'Sales effort', 'hours', 'fact_allocations', 'percentile_cont(0.5) within group (order by f.first_attempt_hours)', 'created_at', 'f.first_attempt_hours is not null', false, null),
  ('first_attempt_p90', 'Time to first attempt (p90)', 'Sales effort', 'hours', 'fact_allocations', 'percentile_cont(0.9) within group (order by f.first_attempt_hours)', 'created_at', 'f.first_attempt_hours is not null', false, null),
  ('attempts_24h', 'Attempts in the first 24 h', 'Sales effort', 'number', 'fact_allocations', 'avg(f.attempts_24h)', 'created_at', null, true, null),
  ('attempts_72h', 'Attempts in the first 72 h', 'Sales effort', 'number', 'fact_allocations', 'avg(f.attempts_72h)', 'created_at', null, true, null),
  ('connect_rate', 'Connected', 'Sales effort', 'pct', 'fact_allocations', 'avg(f.connected::int)', 'created_at', 'f.connected', true, null),
  ('stale_share', 'Stale (no update in 7 days)', 'Sales effort', 'pct', 'fact_allocations', 'avg(f.stale::int)', 'created_at', 'f.stale', false, null),
  ('contacted_rate', 'Contacted or further', 'Lead stages', 'pct', 'fact_allocations', 'avg((f.stage_reached in (''contacted'', ''interested'', ''applied'') or f.enrolled)::int)', 'created_at', 'f.stage_reached in (''contacted'', ''interested'', ''applied'') or f.enrolled', true, null),
  ('interested_rate', 'Counselled or further', 'Lead stages', 'pct', 'fact_allocations', 'avg((f.stage_reached in (''interested'', ''applied'') or f.enrolled)::int)', 'created_at', 'f.stage_reached in (''interested'', ''applied'') or f.enrolled', true, null),
  ('applied_rate', 'Applied', 'Lead stages', 'pct', 'fact_allocations', 'avg((f.stage_reached = ''applied'' or f.enrolled)::int)', 'created_at', 'f.stage_reached = ''applied'' or f.enrolled', true, null),
  ('sla_compliance', 'SLA compliance', 'SLAs', 'pct', 'fact_sla', 'avg(f.met::int) filter (where f.decided)', 'due_at', 'f.decided', true, null),
  ('sla_breaches', 'SLA breaches', 'SLAs', 'count', 'fact_sla', 'count(*) filter (where f.breached)', 'due_at', 'f.breached', false, null),
  -- conversion and money
  ('enrol_rate', 'Enrolment rate (matured leads)', 'Conversion', 'pct', 'fact_allocations', 'avg(f.enrolled::int) filter (where f.matured)', 'created_at', 'f.matured', true, 'Leads older than the maturity window'),
  ('ncpl', 'Net commission per lead (realised)', 'Commission', 'inr', 'fact_allocations', 'avg(f.reward) filter (where f.matured)', 'created_at', 'f.matured', true, 'Matured leads; commission of enrolments not refunded or cancelled'),
  ('ncpl_holdout', 'NCPL, holdout leads', 'AI and ML', 'inr', 'fact_allocations', 'avg(f.reward) filter (where f.matured and f.holdout)', 'created_at', 'f.matured and f.holdout', true, null),
  ('ncpl_steered', 'NCPL, AI-steered leads', 'AI and ML', 'inr', 'fact_allocations', 'avg(f.reward) filter (where f.matured and not f.holdout and f.scoring_mode is not null)', 'created_at', 'f.matured and not f.holdout and f.scoring_mode is not null', true, null),
  ('enrolments', 'Enrolments', 'Conversion', 'count', 'fact_enrollments', 'count(*) filter (where f.status <> ''cancelled'')', 'created_at', 'f.status <> ''cancelled''', true, null),
  ('verified_enrolments', 'Verified enrolments', 'Conversion', 'count', 'fact_enrollments', 'count(*) filter (where f.status = ''verified'')', 'created_at', 'f.status = ''verified''', true, null),
  ('refund_rate', 'Refunded or cancelled', 'Conversion', 'pct', 'fact_enrollments', 'avg((f.status in (''refunded'', ''cancelled''))::int) filter (where f.status in (''verified'', ''refunded'', ''cancelled''))', 'created_at', 'f.status in (''refunded'', ''cancelled'')', false, null),
  ('days_to_enrol', 'Days to enrol (median)', 'Conversion', 'days', 'fact_enrollments', 'percentile_cont(0.5) within group (order by f.days_to_enrol)', 'created_at', 'f.days_to_enrol is not null', false, null),
  ('commission_expected', 'Commission expected', 'Commission', 'inr', 'fact_money', 'coalesce(sum(f.net_inr) filter (where f.status = ''expected''), 0)', 'created_at', 'f.status = ''expected''', true, 'Net of GST'),
  ('commission_realised', 'Commission realised', 'Commission', 'inr', 'fact_money', 'coalesce(sum(f.net_inr) filter (where f.status = ''realised''), 0)', 'created_at', 'f.status = ''realised''', true, 'Net of GST'),
  ('invoiced', 'Invoiced', 'Receivables', 'inr', 'fact_invoices', 'coalesce(sum(f.total_inr), 0)', 'created_at', null, true, 'Gross, with GST'),
  ('outstanding', 'Outstanding', 'Receivables', 'inr', 'fact_invoices', 'coalesce(sum(f.outstanding_inr), 0)', 'created_at', 'f.outstanding_inr > 0', false, null),
  ('collection_rate', 'Collected', 'Receivables', 'pct', 'fact_invoices', 'sum(f.received_inr + f.tds_inr) / nullif(sum(f.total_inr), 0)', 'created_at', null, true, 'Received plus TDS, of invoiced'),
  -- notifications, CAPI, sync, AI
  ('notifications_sent', 'Student messages sent', 'Notifications', 'count', 'fact_notifications', 'count(*) filter (where f.status = ''sent'')', 'created_at', 'f.status = ''sent''', true, null),
  ('notifications_failed', 'Student messages failed', 'Notifications', 'count', 'fact_notifications', 'count(*) filter (where f.status = ''failed'')', 'created_at', 'f.status = ''failed''', false, null),
  ('notify_minutes', 'Acceptance to message (median)', 'Notifications', 'minutes', 'fact_notifications', 'percentile_cont(0.5) within group (order by f.minutes_to_send)', 'created_at', 'f.minutes_to_send is not null', false, null),
  ('capi_sent', 'Conversions sent to ad platforms', 'CAPI', 'count', 'fact_capi', 'count(*) filter (where f.status = ''sent'')', 'created_at', 'f.status = ''sent''', true, null),
  ('capi_failed', 'Conversions failed', 'CAPI', 'count', 'fact_capi', 'count(*) filter (where f.status in (''failed'', ''dead'', ''rejected''))', 'created_at', 'f.status in (''failed'', ''dead'', ''rejected'')', false, null),
  ('sync_events', 'Partner sync events', 'System and mapping', 'count', 'fact_sync', 'count(*)', 'created_at', null, true, null),
  ('sync_error_rate', 'Sync errors', 'System and mapping', 'pct', 'fact_sync', 'avg(f.error::int)', 'created_at', 'f.error', false, null),
  ('sync_lag', 'Sync lag (median)', 'System and mapping', 'minutes', 'fact_sync', 'percentile_cont(0.5) within group (order by f.lag_minutes)', 'created_at', 'f.lag_minutes is not null', false, null),
  ('unmapped_events', 'Unmapped values held', 'System and mapping', 'count', 'fact_sync', 'count(*) filter (where f.unmapped)', 'created_at', 'f.unmapped', false, null),
  ('ai_cost', 'AI cost', 'AI and ML', 'usd', 'fact_ai', 'coalesce(sum(f.cost_usd) filter (where f.kind = ''run''), 0)', 'created_at', 'f.kind = ''run''', false, null),
  ('ai_recommendations', 'AI recommendations', 'AI and ML', 'count', 'fact_ai', 'count(*) filter (where f.kind = ''recommendation'')', 'created_at', 'f.kind = ''recommendation''', true, null),
  ('ai_applied', 'AI recommendations applied', 'AI and ML', 'count', 'fact_ai', 'count(*) filter (where f.rec_status = ''applied'')', 'created_at', 'f.rec_status = ''applied''', true, null)
on conflict (key) do update
  set label = excluded.label, area = excluded.area, unit = excluded.unit, fact = excluded.fact, agg = excluded.agg, date_col = excluded.date_col,
      drill_where = excluded.drill_where, higher_is_better = excluded.higher_is_better, description = excluded.description, updated_at = now()
  where b2b.metric_definitions.is_system;

/* Dimensions per fact: key -> column expression (over alias f). Time grains are added for every fact. */
create or replace function b2b.metric_dimensions()
returns jsonb language sql immutable set search_path = '' as $fn$
  select '{
    "fact_leads": {"source":"f.source","channel":"f.channel","campaign":"f.campaign","platform":"f.platform","paid":"f.paid","form":"f.form",
                   "utm_source":"f.utm_source","utm_medium":"f.utm_medium","city":"f.city","state":"f.state","course":"f.course","level":"f.level",
                   "mode":"f.mode","segment":"f.segment","specialization":"f.specialization","university":"f.university","lead_status":"f.lead_status",
                   "temperature":"f.temperature","stage":"f.stage","sub_stage":"f.sub_stage","lost_reason":"f.lost_reason","language":"f.language",
                   "destination":"f.destination","b2c_lane":"f.b2c_lane","not_passed_reason":"f.not_passed_reason","partner":"f.partner_id"},
    "fact_allocations": {"partner":"f.partner_id","segment":"f.segment","course":"f.course","level":"f.level","mode":"f.mode","routing_mode":"f.routing_mode",
                   "attempt_no":"f.attempt_no","status":"f.status","holdout":"f.holdout","scoring_mode":"f.scoring_mode","model_version":"f.model_version",
                   "counsellor":"f.counsellor","stage":"f.stage_reached","source":"f.source","campaign":"f.campaign","state":"f.state",
                   "lead_status":"f.lead_status","language":"f.language"},
    "fact_enrollments": {"partner":"f.partner_id","course":"f.course","level":"f.level","mode":"f.mode","university":"f.university","status":"f.status","product":"f.product"},
    "fact_sla": {"partner":"f.partner_id","sla":"f.sla","status":"f.status","due_hour":"f.due_hour"},
    "fact_money": {"partner":"f.partner_id","kind":"f.kind","status":"f.status","period":"f.period"},
    "fact_invoices": {"partner":"f.partner_id","status":"f.status","ageing":"f.ageing"},
    "fact_notifications": {"partner":"f.partner_id","channel":"f.channel","kind":"f.kind","language":"f.language","status":"f.status"},
    "fact_capi": {"platform":"f.platform","stage":"f.stage","status":"f.status"},
    "fact_sync": {"partner":"f.partner_id","status":"f.status"},
    "fact_ai": {"kind":"f.kind","run_kind":"f.run_kind","status":"f.status","rec_status":"f.rec_status"}
  }'::jsonb;
$fn$;

create or replace function b2b.metric_dim_expr(p_fact text, p_date_col text, p_dim text)
returns text language plpgsql immutable set search_path = '' as $fn$
begin
  if p_dim = 'day' then return format('(f.%I at time zone ''Asia/Kolkata'')::date', p_date_col); end if;
  if p_dim = 'week' then return format('date_trunc(''week'', f.%I at time zone ''Asia/Kolkata'')::date', p_date_col); end if;
  if p_dim = 'month' then return format('date_trunc(''month'', f.%I at time zone ''Asia/Kolkata'')::date', p_date_col); end if;
  return b2b.metric_dimensions() -> p_fact ->> p_dim;
end $fn$;

/* The base metrics a metric needs: itself, or the metrics in its formula. */
create or replace function b2b.metric_bases(m b2b.metric_definitions)
returns text[] language sql immutable set search_path = '' as $fn$
  select case when m.is_system then array[m.key]
              else (select array_agg(distinct t ->> 'm') from jsonb_array_elements(m.formula) t where t ? 'm') end;
$fn$;

/* One base metric over a period: rows of (dims as text[], value). */
create or replace function b2b.metric_base_rows(p_key text, p_dims text[], p_filters jsonb, p_from timestamptz, p_to timestamptz, p_test boolean)
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
    v_where := v_where || format(' and (%s)::text in (select jsonb_array_elements_text($1 -> %L))', v_expr, k);
  end loop;
  return query execute format(
    'select %s, (%s)::numeric from b2b.%I f where f.%I >= $2 and f.%I < $3 %s %s %s',
    v_sel, m.agg, m.fact, m.date_col, m.date_col, case when p_test then '' else 'and not f.is_test' end, v_where,
    case when coalesce(cardinality(p_dims), 0) > 0 then ' group by 1' else '' end)
    using p_filters, p_from, p_to;
end $fn$;

/* Evaluates an RPN formula over named values; null on division by zero or a missing value. */
create or replace function b2b.metric_eval(p_formula jsonb, p_vals jsonb)
returns numeric language plpgsql immutable set search_path = '' as $fn$
declare st numeric[] := '{}'; t jsonb; a numeric; b numeric; n int;
begin
  for t in select * from jsonb_array_elements(p_formula) loop
    if t ? 'n' then st := st || (t ->> 'n')::numeric;
    elsif t ? 'm' then
      if p_vals ->> (t ->> 'm') is null then return null; end if;
      st := st || (p_vals ->> (t ->> 'm'))::numeric;
    else
      n := cardinality(st);
      if n < 2 then return null; end if;
      a := st[n - 1]; b := st[n]; st := st[1:n - 2];
      st := st || case t ->> 'op' when '+' then a + b when '-' then a - b when '*' then a * b
                                  when '/' then case when b = 0 then null else a / b end end;
      if st[cardinality(st)] is null then return null; end if;
    end if;
  end loop;
  return case when cardinality(st) = 1 then round(st[1], 6) end;
end $fn$;

/* The values of a metric (system or calculated) by dims over one period: {dims-key: value}. */
create or replace function b2b.metric_values(m b2b.metric_definitions, p_dims text[], p_filters jsonb, p_from timestamptz, p_to timestamptz, p_test boolean)
returns table (d text[], value numeric) language plpgsql stable security definer set search_path = '' as $fn$
declare b text;
begin
  if m.is_system then
    return query select x.d, x.value from b2b.metric_base_rows(m.key, p_dims, p_filters, p_from, p_to, p_test) x;
    return;
  end if;
  return query
    with parts as (
      select bb.key, x.d, x.value from unnest(b2b.metric_bases(m)) bb(key)
      cross join lateral b2b.metric_base_rows(bb.key, p_dims, p_filters, p_from, p_to, p_test) x),
    keys as (select distinct parts.d from parts)
    select k.d, b2b.metric_eval(m.formula, (select coalesce(jsonb_object_agg(p.key, p.value), '{}') from parts p where p.d is not distinct from k.d))
      from keys k;
end $fn$;

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
  v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 100), 1), 500);
  v_time boolean;
  v_rows jsonb;
  v_total jsonb;
begin
  select * into m from b2b.metric_definitions where key = p ->> 'metric';
  if m.key is null then raise exception 'unknown metric %', coalesce(p ->> 'metric', '(none)') using errcode = '22023'; end if;
  if cardinality(v_dims) > 2 then raise exception 'at most two breakdowns' using errcode = '22023'; end if;
  if v_from >= v_to then raise exception 'the period is empty' using errcode = '22023'; end if;
  if v_to - v_from > interval '3 years' then raise exception 'at most three years at a time' using errcode = '22023'; end if;
  v_len := v_to - v_from;
  v_time := v_dims && array['day', 'week', 'month'];

  with cur as (select * from b2b.metric_values(m, v_dims, p -> 'filters', v_from, v_to, v_test)),
       prev as (select * from b2b.metric_values(m, v_dims, p -> 'filters', v_from - v_len, v_from, v_test) where v_cmp and not v_time),
       j as (select c.d, c.value, pr.value prev from cur c left join prev pr on pr.d is not distinct from c.d)
  select coalesce(jsonb_agg(jsonb_build_object('d', to_jsonb(j.d), 'value', round(j.value, 4), 'prev', round(j.prev, 4))
                            order by case when v_time then j.d[1] end, j.value desc nulls last, j.d), '[]')
    into v_rows from (select * from j order by case when v_time then j.d[1] end, j.value desc nulls last limit v_limit) j;

  select jsonb_build_object('value', round((select value from b2b.metric_values(m, '{}', p -> 'filters', v_from, v_to, v_test) limit 1), 4),
                            'prev', case when v_cmp then round((select value from b2b.metric_values(m, '{}', p -> 'filters', v_from - v_len, v_from, v_test) limit 1), 4) end)
    into v_total;

  return jsonb_build_object(
    'metric', jsonb_build_object('key', m.key, 'label', m.label, 'unit', m.unit, 'area', m.area, 'higher_is_better', m.higher_is_better,
                                 'description', m.description, 'calculated', not m.is_system),
    'dims', to_jsonb(v_dims), 'from', v_from, 'to', v_to, 'rows', v_rows, 'total', v_total,
    'labels', jsonb_build_object('partner', coalesce((select jsonb_object_agg(p2.id::text, coalesce(p2.display_name, p2.name)) from b2b.partners p2), '{}')));
end $fn$;

/* The rows behind a number. p: {metric, filters (including the clicked breakdown values), from, to, limit}. */
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
  v_fact := m.fact; v_date := m.date_col;
  for k in select jsonb_object_keys(coalesce(p -> 'filters', '{}')) loop
    v_expr := b2b.metric_dim_expr(v_fact, v_date, k);
    if v_expr is null then raise exception 'cannot filter by %', k using errcode = '22023'; end if;
    v_where := v_where || format(' and (%s)::text in (select jsonb_array_elements_text($1 -> %L))', v_expr, k);
  end loop;
  if m.drill_where is not null then v_where := v_where || ' and (' || m.drill_where || ')'; end if;
  execute format('select count(*), coalesce(jsonb_agg(to_jsonb(x) order by x.%I desc), ''[]'') from (select f.* from b2b.%I f where f.%I >= $2 and f.%I < $3 and not f.is_test %s order by f.%I desc limit %s) x',
                 v_date, v_fact, v_date, v_date, v_where, v_date, v_limit)
    into v_n, v_rows using p -> 'filters', v_from, v_to;
  return jsonb_build_object('metric', m.key, 'fact', v_fact, 'rows', v_rows, 'shown', v_n, 'limit', v_limit,
                            'labels', jsonb_build_object('partner', coalesce((select jsonb_object_agg(p2.id::text, coalesce(p2.display_name, p2.name)) from b2b.partners p2), '{}')));
end $fn$;

-- ---------- Admin wrappers ----------
create or replace function b2b.metric_catalogue()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('key', m.key, 'label', m.label, 'area', m.area, 'unit', m.unit, 'description', m.description,
                                 'higher_is_better', m.higher_is_better, 'calculated', not m.is_system, 'formula', m.formula, 'fact', m.fact,
                                 'dims', (select coalesce(jsonb_agg(d order by d), '[]') from (
                                            select jsonb_object_keys(b2b.metric_dimensions() -> coalesce(m.fact, (select f2.fact from b2b.metric_definitions f2 where f2.key = (b2b.metric_bases(m))[1]))) d
                                            union select unnest(array['day', 'week', 'month'])) z))
                               order by m.area, m.label) from b2b.metric_definitions m), '[]'),
    'facts_at', (select value ->> 'refreshed_at' from b2b.ai_state where key = 'facts'));
end $fn$;

create or replace function b2b.metric_query(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.metric_run(p);
end $fn$;

create or replace function b2b.metric_drill_admin(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.metric_drill(p);
end $fn$;

/* A calculated metric: p {key, label, area?, unit, description?, higher_is_better, formula: RPN tokens}. Only system
   metrics may be referenced, and they must share a fact family for breakdowns (checked when queried). */
create or replace function b2b.metric_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare t jsonb; v_depth int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(p ->> 'key', '') !~ '^[a-z][a-z0-9_]{1,59}$' then raise exception 'the key is lower-case letters, digits and _' using errcode = '22023'; end if;
  if exists (select 1 from b2b.metric_definitions where key = p ->> 'key' and is_system) then raise exception 'that key belongs to a built-in metric' using errcode = '22023'; end if;
  if coalesce(trim(p ->> 'label'), '') = '' then raise exception 'give the metric a name' using errcode = '22023'; end if;
  if p ->> 'unit' not in ('count', 'pct', 'inr', 'hours', 'days', 'minutes', 'usd', 'number') then raise exception 'unknown unit' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'formula') <> 'array' or jsonb_array_length(p -> 'formula') = 0 or jsonb_array_length(p -> 'formula') > 40 then
    raise exception 'the formula is empty or too long' using errcode = '22023';
  end if;
  for t in select * from jsonb_array_elements(p -> 'formula') loop
    if t ? 'm' then
      if not exists (select 1 from b2b.metric_definitions where key = t ->> 'm' and is_system) then raise exception 'unknown metric % in the formula', t ->> 'm' using errcode = '22023'; end if;
      v_depth := v_depth + 1;
    elsif t ? 'n' then
      if jsonb_typeof(t -> 'n') <> 'number' then raise exception 'numbers only' using errcode = '22023'; end if;
      v_depth := v_depth + 1;
    elsif t ->> 'op' in ('+', '-', '*', '/') then
      v_depth := v_depth - 1;
      if v_depth < 1 then raise exception 'the formula is not well formed' using errcode = '22023'; end if;
    else raise exception 'the formula is not well formed' using errcode = '22023';
    end if;
  end loop;
  if v_depth <> 1 then raise exception 'the formula is not well formed' using errcode = '22023'; end if;
  insert into b2b.metric_definitions (key, label, area, description, unit, formula, higher_is_better, is_system, created_by)
  values (p ->> 'key', left(trim(p ->> 'label'), 80), coalesce(nullif(trim(p ->> 'area'), ''), 'Custom'), left(p ->> 'description', 300), p ->> 'unit',
          p -> 'formula', coalesce((p ->> 'higher_is_better')::boolean, true), false, coalesce(auth.uid()::text, 'admin'))
  on conflict (key) do update set label = excluded.label, area = excluded.area, description = excluded.description, unit = excluded.unit,
                                  formula = excluded.formula, higher_is_better = excluded.higher_is_better, updated_at = now()
  where not b2b.metric_definitions.is_system;
  perform b2b.log_event('analytics.metric_saved', null, null, null, jsonb_build_object('key', p ->> 'key'));
  return jsonb_build_object('key', p ->> 'key');
end $fn$;

revoke execute on function b2b.metric_dimensions(), b2b.metric_dim_expr(text, text, text), b2b.metric_bases(b2b.metric_definitions),
                           b2b.metric_base_rows(text, text[], jsonb, timestamptz, timestamptz, boolean), b2b.metric_eval(jsonb, jsonb),
                           b2b.metric_values(b2b.metric_definitions, text[], jsonb, timestamptz, timestamptz, boolean), b2b.metric_run(jsonb), b2b.metric_drill(jsonb)
  from public, anon, authenticated;
grant execute on function b2b.metric_dimensions(), b2b.metric_dim_expr(text, text, text), b2b.metric_bases(b2b.metric_definitions),
                          b2b.metric_base_rows(text, text[], jsonb, timestamptz, timestamptz, boolean), b2b.metric_eval(jsonb, jsonb),
                          b2b.metric_values(b2b.metric_definitions, text[], jsonb, timestamptz, timestamptz, boolean), b2b.metric_run(jsonb), b2b.metric_drill(jsonb)
  to service_role;
revoke execute on function b2b.metric_catalogue(), b2b.metric_query(jsonb), b2b.metric_drill_admin(jsonb), b2b.metric_save(jsonb) from public, anon;
grant execute on function b2b.metric_catalogue(), b2b.metric_query(jsonb), b2b.metric_drill_admin(jsonb), b2b.metric_save(jsonb) to authenticated, service_role;
