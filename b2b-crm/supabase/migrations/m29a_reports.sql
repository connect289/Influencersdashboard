-- M29a: reports (spec B14.3 "Reports: tabular, summary and matrix reports; save, share, schedule, export").
--   reports          name, kind and definition:
--                      tabular  {fact, columns[], filters {dim: [values]}, period | from/to, sort, desc, limit}: rows of one fact
--                      summary  {metrics[], dims[1–2], filters, period}: one row per breakdown value, a column per metric
--                      matrix   {metric, row_dim, col_dim, filters, period}: the metric pivoted, rows by columns
--   report_run(def)  runs a definition (saved or not); report_email(id) renders it for scheduled delivery (first 50 rows
--                    in the e-mail, everything as CSV). Exports are CSV from the app. Columns are only those of the facts,
--                    which hold no names, phones or e-mails.

create table if not exists b2b.reports (
  id          bigint generated always as identity primary key,
  name        text not null,
  kind        text not null check (kind in ('tabular', 'summary', 'matrix')),
  definition  jsonb not null,
  created_by  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  archived_at timestamptz
);
alter table b2b.reports enable row level security;
do $p$ begin
  if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = 'reports' and policyname = 'admin_read') then
    create policy admin_read on b2b.reports for select to authenticated using ((select b2b.is_admin()));
  end if;
end $p$;
revoke all on b2b.reports from public, anon, authenticated;
grant select on b2b.reports to authenticated;
grant all on b2b.reports to service_role;
do $fk$ begin
  if not exists (select 1 from pg_constraint where conname = 'report_schedules_report_fk') then
    alter table b2b.report_schedules add constraint report_schedules_report_fk foreign key (report_id) references b2b.reports (id);
  end if;
end $fk$;

/* The columns of a fact (for tabular reports), with their types. */
create or replace function b2b.fact_columns(p_fact text)
returns jsonb language sql stable set search_path = '' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('name', a.attname, 'type', format_type(a.atttypid, a.atttypmod)) order by a.attnum), '[]')
    from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'b2b' and c.relname = p_fact and c.relname like 'fact\_%' and a.attnum > 0 and not a.attisdropped and a.attname <> 'is_test';
$fn$;

create or replace function b2b.report_run_def(p_kind text, d jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_fact text := d ->> 'fact';
  v_cols jsonb;
  v_sel text;
  v_where text := '';
  v_expr text;
  k text;
  c text;
  r tstzrange := case when d ? 'from' then tstzrange((d ->> 'from')::timestamptz, coalesce((d ->> 'to')::timestamptz, now())) else b2b.period_range(coalesce(d ->> 'period', '30d')) end;
  v_date text;
  v_rows jsonb;
  v_limit int := least(greatest(coalesce((d ->> 'limit')::int, 1000), 1), 5000);
  m text;
  v_series jsonb := '[]';
  v_x jsonb;
begin
  if p_kind = 'tabular' then
    if v_fact not in ('fact_leads', 'fact_allocations', 'fact_enrollments', 'fact_sla', 'fact_money', 'fact_invoices', 'fact_notifications', 'fact_capi', 'fact_sync', 'fact_ai') then
      raise exception 'choose what the report lists' using errcode = '22023';
    end if;
    v_cols := b2b.fact_columns(v_fact);
    if jsonb_typeof(d -> 'columns') <> 'array' or jsonb_array_length(d -> 'columns') = 0 or jsonb_array_length(d -> 'columns') > 30 then
      raise exception 'choose 1 to 30 columns' using errcode = '22023';
    end if;
    v_sel := '';
    for c in select jsonb_array_elements_text(d -> 'columns') loop
      if not exists (select 1 from jsonb_array_elements(v_cols) x where x ->> 'name' = c) then raise exception 'unknown column %', c using errcode = '22023'; end if;
      v_sel := v_sel || case when v_sel = '' then '' else ', ' end || format('f.%I', c);
    end loop;
    v_date := case v_fact when 'fact_sla' then 'due_at' else 'created_at' end;
    for k in select jsonb_object_keys(coalesce(d -> 'filters', '{}')) loop
      v_expr := b2b.metric_dim_expr(v_fact, v_date, k);
      if v_expr is null then raise exception 'cannot filter by %', k using errcode = '22023'; end if;
      v_where := v_where || format(' and (%s)::text in (select jsonb_array_elements_text($1 -> %L))', v_expr, k);
    end loop;
    if d ->> 'sort' is not null and not exists (select 1 from jsonb_array_elements(v_cols) x where x ->> 'name' = d ->> 'sort') then
      raise exception 'unknown sort column' using errcode = '22023';
    end if;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from (select %s from b2b.%I f where f.%I >= $2 and f.%I < $3 and not f.is_test %s order by %s %s nulls last limit %s) x',
                   v_sel, v_fact, v_date, v_date, v_where, format('f.%I', coalesce(d ->> 'sort', v_date)),
                   case when coalesce((d ->> 'desc')::boolean, true) then 'desc' else 'asc' end, v_limit)
      into v_rows using d -> 'filters', lower(r), upper(r);
    return jsonb_build_object('kind', 'tabular', 'columns', d -> 'columns', 'rows', v_rows, 'from', lower(r), 'to', upper(r), 'limit', v_limit,
                              'labels', jsonb_build_object('partner_id', coalesce((select jsonb_object_agg(p.id::text, coalesce(p.display_name, p.name)) from b2b.partners p), '{}')));
  elsif p_kind = 'summary' then
    if jsonb_typeof(d -> 'metrics') <> 'array' or jsonb_array_length(d -> 'metrics') = 0 or jsonb_array_length(d -> 'metrics') > 12 then
      raise exception 'choose 1 to 12 metrics' using errcode = '22023';
    end if;
    if jsonb_array_length(coalesce(d -> 'dims', '[]')) not between 1 and 2 then raise exception 'choose one or two breakdowns' using errcode = '22023'; end if;
    for m in select jsonb_array_elements_text(d -> 'metrics') loop
      v_series := v_series || jsonb_build_array(b2b.metric_run(jsonb_build_object('metric', m, 'dims', d -> 'dims', 'filters', coalesce(d -> 'filters', '{}'),
                                                                                  'from', lower(r), 'to', upper(r), 'compare', 'none', 'limit', 500)));
    end loop;
    -- one row per breakdown value, a column per metric
    select coalesce(jsonb_agg(jsonb_build_object('d', k2.d, 'values', (select jsonb_agg((select rw -> 'value' from jsonb_array_elements(s -> 'rows') rw where rw -> 'd' = k2.d limit 1) order by o)
                                                                       from jsonb_array_elements(v_series) with ordinality q(s, o)))
                              order by k2.d), '[]')
      into v_rows
      from (select distinct rw -> 'd' d from jsonb_array_elements(v_series) s, jsonb_array_elements(s -> 'rows') rw) k2;
    return jsonb_build_object('kind', 'summary', 'dims', d -> 'dims', 'metrics', (select jsonb_agg(s -> 'metric') from jsonb_array_elements(v_series) s),
                              'rows', v_rows, 'totals', (select jsonb_agg(s -> 'total' -> 'value') from jsonb_array_elements(v_series) s),
                              'from', lower(r), 'to', upper(r), 'labels', v_series -> 0 -> 'labels');
  elsif p_kind = 'matrix' then
    if d ->> 'row_dim' is null or d ->> 'col_dim' is null or d ->> 'row_dim' = d ->> 'col_dim' then raise exception 'choose two different breakdowns' using errcode = '22023'; end if;
    v_x := b2b.metric_run(jsonb_build_object('metric', d ->> 'metric', 'dims', jsonb_build_array(d ->> 'row_dim', d ->> 'col_dim'), 'filters', coalesce(d -> 'filters', '{}'),
                                             'from', lower(r), 'to', upper(r), 'compare', 'none', 'limit', 500));
    return jsonb_build_object('kind', 'matrix', 'metric', v_x -> 'metric', 'row_dim', d ->> 'row_dim', 'col_dim', d ->> 'col_dim',
                              'rows', (select coalesce(jsonb_agg(distinct rw -> 'd' -> 0), '[]') from jsonb_array_elements(v_x -> 'rows') rw),
                              'cols', (select coalesce(jsonb_agg(distinct rw -> 'd' -> 1), '[]') from jsonb_array_elements(v_x -> 'rows') rw),
                              'cells', v_x -> 'rows', 'total', v_x -> 'total', 'from', lower(r), 'to', upper(r), 'labels', v_x -> 'labels');
  end if;
  raise exception 'unknown kind of report' using errcode = '22023';
end $fn$;

/* CSV of a report result (all rows), with partner names instead of ids. */
create or replace function b2b.report_csv(p_res jsonb)
returns text language sql immutable set search_path = '' as $fn$
  select case p_res ->> 'kind'
    when 'tabular' then (
      select string_agg(line, E'\n' order by o) from (
        select 0 o, (select string_agg(c, ',') from jsonb_array_elements_text(p_res -> 'columns') c) line
        union all
        select row_number() over (), (select string_agg('"' || replace(coalesce(case when c = 'partner_id' then coalesce(p_res -> 'labels' -> 'partner_id' ->> (rw ->> c), rw ->> c) else rw ->> c end, ''), '"', '""') || '"', ',' order by co)
                                        from jsonb_array_elements_text(p_res -> 'columns') with ordinality cc(c, co))
          from jsonb_array_elements(p_res -> 'rows') rw) z)
    when 'summary' then (
      select string_agg(line, E'\n' order by o) from (
        select 0 o, (select string_agg(dd, ',') from jsonb_array_elements_text(p_res -> 'dims') dd) || ',' || (select string_agg('"' || (m ->> 'label') || '"', ',') from jsonb_array_elements(p_res -> 'metrics') m) line
        union all
        select row_number() over (), (select string_agg('"' || replace(coalesce(case when p_res -> 'dims' ->> (o2 - 1) = 'partner' then coalesce(p_res -> 'labels' -> 'partner' ->> v, v) else v end, ''), '"', '""') || '"', ',' order by o2)
                                        from jsonb_array_elements_text(rw -> 'd') with ordinality q2(v, o2))
                                     || ',' || (select string_agg(case when jsonb_typeof(x) in ('number', 'string', 'boolean') then x #>> '{}' else '' end, ',' order by o3) from jsonb_array_elements(rw -> 'values') with ordinality q3(x, o3))
          from jsonb_array_elements(p_res -> 'rows') rw) z)
    else (
      select string_agg(line, E'\n' order by o) from (
        select 0 o, '"' || (p_res ->> 'row_dim') || ' by ' || (p_res ->> 'col_dim') || '",' || (select string_agg('"' || replace(c #>> '{}', '"', '""') || '"', ',' order by c #>> '{}') from jsonb_array_elements(p_res -> 'cols') c) line
        union all
        select row_number() over (), '"' || replace(rv #>> '{}', '"', '""') || '",' ||
               (select string_agg(coalesce((select cell ->> 'value' from jsonb_array_elements(p_res -> 'cells') cell where cell -> 'd' -> 0 = rv and cell -> 'd' -> 1 = c limit 1), ''), ',' order by c #>> '{}')
                  from jsonb_array_elements(p_res -> 'cols') c)
          from jsonb_array_elements(p_res -> 'rows') rv) z)
  end;
$fn$;

create or replace function b2b.report_email(p_report_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare rp b2b.reports; res jsonb; v_csv text; v_lines text[];
begin
  select * into rp from b2b.reports where id = p_report_id and archived_at is null;
  if rp.id is null then raise exception 'report not found' using errcode = 'P0002'; end if;
  res := b2b.report_run_def(rp.kind, rp.definition);
  v_csv := coalesce(b2b.report_csv(res), '');
  v_lines := string_to_array(v_csv, E'\n');
  return jsonb_build_object('name', rp.name,
    'text', rp.name || E'\n' || array_to_string(v_lines[1:51], E'\n'),
    'html', format('<div style="font-family:Arial,sans-serif;font-size:13px"><h2 style="font-size:18px">%s</h2><p style="color:#666">%s rows; the first 50 are below, all are attached as CSV.</p><pre style="font-size:12px">%s</pre></div>',
                   b2b.html_escape(rp.name), greatest(coalesce(array_length(v_lines, 1), 1) - 1, 0), b2b.html_escape(array_to_string(v_lines[1:51], E'\n'))),
    'attachments', jsonb_build_array(jsonb_build_object('filename', regexp_replace(lower(rp.name), '[^a-z0-9]+', '-', 'g') || '.csv',
                                                        'content_base64', translate(encode(convert_to(v_csv, 'UTF8'), 'base64'), E'\n', ''))));
end $fn$;

-- ---------- Admin ----------
create or replace function b2b.reports_list()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'reports', coalesce((select jsonb_agg(to_jsonb(r) order by r.id desc) from b2b.reports r where r.archived_at is null), '[]'),
    'facts', (select jsonb_object_agg(f, b2b.fact_columns(f)) from unnest(array['fact_leads', 'fact_allocations', 'fact_enrollments', 'fact_sla', 'fact_money',
                                                                                    'fact_invoices', 'fact_notifications', 'fact_capi', 'fact_sync', 'fact_ai']) f));
end $fn$;

create or replace function b2b.report_run(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare rp b2b.reports;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p ? 'id' then
    select * into rp from b2b.reports where id = (p ->> 'id')::bigint and archived_at is null;
    if rp.id is null then raise exception 'report not found' using errcode = 'P0002'; end if;
    return b2b.report_run_def(rp.kind, rp.definition || coalesce(p -> 'override', '{}')) || jsonb_build_object('report', to_jsonb(rp));
  end if;
  return b2b.report_run_def(p ->> 'kind', p -> 'definition');
end $fn$;

create or replace function b2b.report_csv_admin(p jsonb)
returns text language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  perform b2b.log_event('analytics.report_exported', null, null, null, jsonb_build_object('id', p ->> 'id', 'kind', coalesce(p ->> 'kind', 'saved')));
  return b2b.report_csv(b2b.report_run(p));
end $fn$;

create or replace function b2b.report_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint := nullif(p ->> 'id', '')::bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p ->> 'name'), '') = '' or length(trim(p ->> 'name')) > 80 then raise exception 'give the report a name (up to 80 characters)' using errcode = '22023'; end if;
  perform b2b.report_run_def(p ->> 'kind', p -> 'definition');   -- validates
  if v_id is null then
    insert into b2b.reports (name, kind, definition, created_by) values (trim(p ->> 'name'), p ->> 'kind', p -> 'definition', coalesce(auth.uid()::text, 'admin')) returning id into v_id;
  else
    update b2b.reports set name = trim(p ->> 'name'), kind = p ->> 'kind', definition = p -> 'definition', updated_at = now() where id = v_id and archived_at is null;
    if not found then raise exception 'report not found' using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('id', v_id);
end $fn$;

create or replace function b2b.report_archive(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.reports set archived_at = now() where id = p_id and archived_at is null;
  if not found then raise exception 'report not found' using errcode = 'P0002'; end if;
  update b2b.report_schedules set active = false where report_id = p_id;
  return jsonb_build_object('archived', p_id);
end $fn$;

revoke execute on function b2b.fact_columns(text), b2b.report_run_def(text, jsonb), b2b.report_csv(jsonb), b2b.report_email(bigint) from public, anon, authenticated;
grant execute on function b2b.fact_columns(text), b2b.report_run_def(text, jsonb), b2b.report_csv(jsonb), b2b.report_email(bigint) to service_role;
revoke execute on function b2b.reports_list(), b2b.report_run(jsonb), b2b.report_csv_admin(jsonb), b2b.report_save(jsonb), b2b.report_archive(bigint) from public, anon;
grant execute on function b2b.reports_list(), b2b.report_run(jsonb), b2b.report_csv_admin(jsonb), b2b.report_save(jsonb), b2b.report_archive(bigint) to authenticated, service_role;
