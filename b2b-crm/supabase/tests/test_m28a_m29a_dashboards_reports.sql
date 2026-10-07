-- M28a and M29a review fixes on STAGING, rolled back: dashboard widget checks (every breakdown on every base metric, type
-- and size, sankey steps, the seeded dashboards), archiving a dashboard stops its schedules, the live SLA list (open
-- breaches with their status), CSV cells (formulas neutralised, quoted headers, matrix nulls), report validation, the
-- tabular export and e-mail limit, and the 2,000-value cut of summary and matrix reports. Every row must say ok = true.
begin;
-- hold the cron ticks' locks for this transaction so an overlapping staging cron run cannot make the calls below return busy; rollback releases them
select pg_advisory_xact_lock(hashtext('b2b.refresh_facts'));
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b6","role":"authenticated","aal":"aal2","email":"m28-admin@test.local"}', true)
$f$;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000b6', 'm28-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000b6', 'm28-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000b7', 'nobody28@test.local', 'authenticated', 'authenticated');
update b2b.settings set value = value || '{"enabled":false}' where key = 'admin_alerts';

-- fixture: partners G and H; one lead (not a test lead, no utm_source) with three allocations in zzm28|PG|Online (G accepted,
-- the lead's current one; H closed; G duplicate); SLA checks on G: (1) pending, due in 1 h; (2) first attempt breached
-- 1 h ago; (3) first attempt breached on the duplicate allocation (owed by nobody)
with x as (insert into b2b.partners (slug, name, status) values ('m28-gamma', 'M28 Gamma', 'active') returning id) insert into t select 'G', id::text from x;
with x as (insert into b2b.partners (slug, name, status) values ('m28-delta', 'M28 Delta', 'active') returning id) insert into t select 'H', id::text from x;
do $x$
declare v_l bigint; v_a bigint; i int;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', '919876507101', 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Reports M28', 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online', 'state', 'Delhi')));
  select id into v_l from public.student_leads where whatsapp_number = '919876507101';
  insert into t values ('L', v_l::text);
  for i in 1 .. 3 loop
    insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, reference, status, mode, cpe_net_inr, accepted_at, created_at, is_test)
    values (v_l, i, 'zzm28|PG|Online', 'partner', case when i = 2 then pg_temp.v('H')::bigint else pg_temp.v('G')::bigint end, 'M28-REF-' || i,
            case i when 1 then 'accepted' when 2 then 'closed' else 'duplicate' end, 'commission_first', 15000,
            case when i < 3 then now() - interval '1 day' end, now() - interval '1 day', false)
    returning id into v_a;
    insert into t values ('A' || i, v_a::text);
  end loop;
  update public.student_leads set allocation_id = pg_temp.v('A1')::bigint, destination_type = 'partner', partner_id = pg_temp.v('G')::bigint,
         allocated_at = now() - interval '1 day', created_at = now() - interval '2 days' where id = v_l;   -- inside the period (it ends at now())
  with x as (insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, status, breached_at)
             values (pg_temp.v('A1')::bigint, v_l, pg_temp.v('G')::bigint, 'first_connect', now() - interval '1 day', now() + interval '1 hour', 'pending', null) returning id)
  insert into t select 'C1', id::text from x;
  with x as (insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, status, breached_at)
             values (pg_temp.v('A1')::bigint, v_l, pg_temp.v('G')::bigint, 'first_attempt', now() - interval '1 day', now() - interval '1 hour', 'breached', now()) returning id)
  insert into t select 'C2', id::text from x;
  with x as (insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, status, breached_at)
             values (pg_temp.v('A3')::bigint, v_l, pg_temp.v('G')::bigint, 'first_attempt', now() - interval '1 day', now() - interval '2 hours', 'breached', now()) returning id)
  insert into t select 'C3', id::text from x;
end $x$;
select b2b.refresh_facts();

-- ---------- CSV (as the owner) ----------
insert into r select 'csv_matrix_nulls', x = E'"stage by partner","Acme","(none)"\n"contacted",3,2\n"(none)",1,', x
  from (select b2b.report_csv('{"kind":"matrix","row_dim":"stage","col_dim":"partner","rows":["contacted",null],"cols":["5",null],"cells":[{"d":["contacted","5"],"value":3},{"d":["contacted",null],"value":2},{"d":[null,"5"],"value":1}],"labels":{"partner":{"5":"Acme"}}}'::jsonb) x) z;
insert into r select 'csv_formula_neutralised', split_part(x, E'\n', 2) = '"''=HYPERLINK(""https://x.example"")","-500.5","''-cmd","''@SUM(A1)"', x
  from (select b2b.report_csv('{"kind":"tabular","columns":["campaign","net_inr","city","university"],"rows":[{"campaign":"=HYPERLINK(\"https://x.example\")","net_inr":-500.5,"city":"-cmd","university":"@SUM(A1)"}],"labels":{"partner_id":{}}}'::jsonb) x) z;
insert into r select 'csv_cell_null_and_phone', b2b.csv_cell(null) = '""' and b2b.csv_cell('+91 98') = '"''+91 98"' and b2b.csv_cell('12.5') = '"12.5"',
                     b2b.csv_cell(null) || ' ' || b2b.csv_cell('+91 98');
insert into r select 'csv_header_quotes', x = 'partner,"Say ""hi"" rate","B"', x
  from (select b2b.report_csv('{"kind":"summary","dims":["partner"],"metrics":[{"key":"a","label":"Say \"hi\" rate"},{"key":"b","label":"B"}],"rows":[],"totals":[]}'::jsonb) x) z;
insert into r select 'csv_header_unlabelled_metric', x = 'partner,"a","B"', x
  from (select b2b.report_csv('{"kind":"summary","dims":["partner"],"metrics":[{"key":"a"},{"key":"b","label":"B"}],"rows":[],"totals":[]}'::jsonb) x) z;
insert into r select 'csv_summary_dim_value_neutralised', split_part(x, E'\n', 2) = '"''=cmd",4', x
  from (select b2b.report_csv('{"kind":"summary","dims":["campaign"],"metrics":[{"key":"leads","label":"Leads"}],"rows":[{"d":["=cmd"],"values":[4]}],"totals":[4]}'::jsonb) x) z;

-- ---------- seeds and widget checks ----------
insert into r select 'sales_effort_title', (select w ->> 'title' from b2b.dashboards d, jsonb_array_elements(d.widgets) w where d.slug = 'sales-effort' and w ->> 'id' = 's1') = 'Open SLAs and breaches', null;
insert into r select 'seeded_widgets_valid', bool_and(jsonb_array_length(b2b.dashboard_check_widgets(d.widgets)) = jsonb_array_length(d.widgets)) and count(*) = 9, count(*)::text
  from b2b.dashboards d where d.is_default and d.archived_at is null;
do $x$ declare e text; begin
  begin perform b2b.dashboard_check_widgets('[{"id":"s1","type":"sankey","title":"Flow","metric":"leads","w":6,"h":2,"steps":["source"]}]'); e := 'passed'; exception when others then e := sqlerrm; end;
  insert into r values ('sankey_needs_two_steps', e = '"Flow" needs at least two steps', e);
  begin perform b2b.dashboard_check_widgets('[{"id":"s1","type":"sankey","title":"Flow","metric":"leads","w":6,"h":2}]'); e := 'passed'; exception when others then e := sqlerrm; end;
  insert into r values ('sankey_needs_steps', e = '"Flow" needs at least two steps', e);
  begin perform b2b.dashboard_check_widgets('[{"id":"s1","type":"sankey","title":"Flow","metric":"allocations","w":6,"h":2,"steps":["source","partner"]}]'); e := 'passed'; exception when others then e := sqlerrm; end;
  insert into r values ('sankey_two_steps_pass', e = 'passed', e);
end $x$;

set local role authenticated;
select pg_temp.admin();
select b2b.metric_save('{"key":"cpe_sla_m28","label":"CPE times SLA m28","unit":"number","formula":[{"m":"cpe_avg"},{"m":"sla_compliance"},{"op":"*"}]}');
do $x$ declare e text; begin
  begin perform b2b.dashboard_save('{"name":"Bad","widgets":[{"id":"a","type":"table","title":"T","metrics":["leads","allocations"],"dims":["destination"],"w":12,"h":2}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('dims_on_every_metric', e = 'Leads routed to partners cannot be broken down by destination', e);
  begin perform b2b.dashboard_save('{"name":"Bad","widgets":[{"id":"a","type":"bar","title":"T","metric":"cpe_sla_m28","dims":["source"],"w":6,"h":2}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('dims_on_every_base', e = 'CPE times SLA m28 cannot be broken down by source', e);
  begin perform b2b.dashboard_save('{"name":"Bad","widgets":[{"id":"a","type":"sankey","title":"F","metric":"sla_compliance","steps":["partner","stage"],"w":6,"h":2}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('steps_checked', e = 'SLA compliance cannot be broken down by stage', e);
  begin perform b2b.dashboard_save('{"name":"Bad","widgets":[{"id":"a","type":"kpi","title":"T","metric":"leads","h":1}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('widget_needs_size', e = 'each widget needs a type and a size', e);
  begin perform b2b.dashboard_save('{"name":"Bad","widgets":[{"id":"a","title":"T","metric":"leads","w":3,"h":1}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('widget_needs_type', e = 'each widget needs a type and a size', e);
  begin e := b2b.dashboard_save('{"name":"Good m28","widgets":[{"id":"a","type":"bar","title":"T","metric":"cpe_sla_m28","dims":["partner"],"w":6,"h":2},{"id":"b","type":"table","title":"U","metrics":["leads","allocations"],"dims":["partner","source"],"w":12,"h":2}]}') ->> 'id';
  exception when others then e := 'refused: ' || sqlerrm; end;
  insert into r values ('shared_dims_save', e ~ '^[0-9]+$', e);
end $x$;
do $x$ declare d record; e text := ''; begin
  for d in select id, slug from b2b.dashboards where is_default and archived_at is null order by id loop
    begin perform b2b.dashboard_copy(d.id); exception when others then e := e || d.slug || ': ' || sqlerrm || '; '; end;
  end loop;
  insert into r values ('defaults_copy', e = '', e);
end $x$;

-- ---------- archiving a dashboard stops its schedules ----------
insert into t select 'D', (b2b.dashboard_copy((select id from b2b.dashboards where slug = 'partner-league')) ->> 'id');
insert into t select 'SD1', (b2b.schedule_save(jsonb_build_object('name', 'On D', 'dashboard_id', pg_temp.v('D')::bigint, 'frequency', 'daily', 'recipients', '["md@example.com"]'::jsonb)) ->> 'id');
insert into t select 'SD2', (b2b.schedule_save(jsonb_build_object('name', 'On D, off', 'dashboard_id', pg_temp.v('D')::bigint, 'frequency', 'weekly', 'weekday', 2, 'recipients', '["md@example.com"]'::jsonb)) ->> 'id');
select b2b.schedule_set_active(pg_temp.v('SD2')::bigint, false);
insert into t select 'arch', b2b.dashboard_archive(pg_temp.v('D')::bigint)::text;
reset role;
insert into r select 'archive_stops_schedules', (x ->> 'archived')::bigint = pg_temp.v('D')::bigint and (x ->> 'schedules_stopped')::int = 1
                     and not (select active from b2b.report_schedules where id = pg_temp.v('SD1')::bigint)
                     and not (select active from b2b.report_schedules where id = pg_temp.v('SD2')::bigint), x::text
  from (select pg_temp.v('arch')::jsonb x) z;

-- ---------- the live SLA list: open SLAs and breaches still owed, with status and reference ----------
set local role authenticated;
select pg_temp.admin();
insert into t select 'st', b2b.sla_timers(pg_temp.v('G')::bigint, 20)::text;
reset role;
insert into r select 'sla_timers_open_and_breached',
                     (select array_agg((rw ->> 'id')::bigint order by o) from jsonb_array_elements(x) with ordinality q(rw, o)) = array[pg_temp.v('C2')::bigint, pg_temp.v('C1')::bigint]
                     and (select array_agg(rw ->> 'status' order by o) from jsonb_array_elements(x) with ordinality q(rw, o)) = array['breached', 'pending']
                     and (select bool_and(rw ->> 'reference' = 'M28-REF-1' and rw ->> 'partner' = 'M28 Gamma') from jsonb_array_elements(x) rw), x::text
  from (select pg_temp.v('st')::jsonb x) z;

-- ---------- reports: validation, limits, the 2,000-value cut ----------
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; begin
  begin perform b2b.report_run('{"kind":"tabular","definition":{"fact":"fact_allocations","period":"7d"}}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('tabular_needs_columns', e = 'choose 1 to 30 columns', e);
  begin perform b2b.report_run('{"kind":"tabular","definition":{"fact":"fact_allocations","columns":"lead_id","period":"7d"}}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('tabular_columns_not_list', e = 'choose 1 to 30 columns', e);
  begin perform b2b.report_run('{"kind":"summary","definition":{"dims":["partner"],"period":"7d"}}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('summary_needs_metrics', e = 'choose 1 to 12 metrics', e);
  begin perform b2b.report_run('{"kind":"summary","definition":{"metrics":"leads","dims":["partner"],"period":"7d"}}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('summary_metrics_not_list', e = 'choose 1 to 12 metrics', e);
  begin perform b2b.report_save('{"name":"x","kind":"tabular","definition":{"fact":"fact_allocations","period":"7d"}}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('save_validates', e = 'choose 1 to 30 columns', e);
end $x$;
insert into t select 'RT', (b2b.report_save('{"name":"Allocations m28","kind":"tabular","definition":{"fact":"fact_allocations","columns":["allocation_id","partner_id","status"],"filters":{"segment":["zzm28|PG|Online"]},"period":"7d"}}') ->> 'id');
insert into t select 'RT1', (b2b.report_save('{"name":"Allocations m28 top 1","kind":"tabular","definition":{"fact":"fact_allocations","columns":["allocation_id","partner_id"],"filters":{"segment":["zzm28|PG|Online"]},"period":"7d","limit":1}}') ->> 'id');
insert into r select 'export_limit_5000', (b2b.report_run(jsonb_build_object('id', pg_temp.v('RT')::bigint, 'override', '{"limit":5000}'::jsonb)) ->> 'limit')::int = 5000
                     and (b2b.report_run(jsonb_build_object('id', pg_temp.v('RT')::bigint)) ->> 'limit')::int = 1000, null;
-- a '' filter value matches the null ('(none)') bucket: the fixture lead has no utm_source
insert into r select 'report_null_filter', jsonb_array_length(x -> 'rows') = 1 and x -> 'rows' -> 0 ->> 'lead_id' = pg_temp.v('L'), (x -> 'rows')::text
  from (select b2b.report_run('{"kind":"tabular","definition":{"fact":"fact_leads","columns":["lead_id"],"filters":{"course":["zzm28"],"utm_source":[""]},"period":"30d"}}') x) z;
insert into r select 'report_value_filter_unchanged', jsonb_array_length(x -> 'rows') = 0, (x -> 'rows')::text
  from (select b2b.report_run('{"kind":"tabular","definition":{"fact":"fact_leads","columns":["lead_id"],"filters":{"course":["zzm28"],"utm_source":["google"]},"period":"30d"}}') x) z;
-- two metrics from different facts (G has both, H has no SLA checks: null in that cell)
insert into t select 'sum', b2b.report_run(jsonb_build_object('kind', 'summary', 'definition', jsonb_build_object('metrics', '["allocations","sla_compliance"]'::jsonb, 'dims', '["partner"]'::jsonb,
                                           'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('G'), pg_temp.v('H'))), 'period', '7d')))::text;
insert into t select 'mx', b2b.report_run(jsonb_build_object('kind', 'matrix', 'definition', jsonb_build_object('metric', 'allocations', 'row_dim', 'partner', 'col_dim', 'status',
                                          'filters', jsonb_build_object('segment', '["zzm28|PG|Online"]'::jsonb), 'period', '7d')))::text;
reset role;
insert into r select 'report_truncated_flag', x -> 'truncated' = 'false'::jsonb and jsonb_array_length(x -> 'rows') = 2
                     and (select bool_and(jsonb_array_length(rw -> 'values') = 2) from jsonb_array_elements(x -> 'rows') rw)
                     and (select rw -> 'values' from jsonb_array_elements(x -> 'rows') rw where rw -> 'd' ->> 0 = pg_temp.v('G')) -> 0 = '2'::jsonb
                     and (select rw -> 'values' from jsonb_array_elements(x -> 'rows') rw where rw -> 'd' ->> 0 = pg_temp.v('H')) = '[1, null]'::jsonb
                     and y ? 'truncated' and y -> 'truncated' = 'false'::jsonb and jsonb_array_length(y -> 'rows') = 2 and jsonb_array_length(y -> 'cols') = 3,
                     (x -> 'rows')::text || ' / ' || (y - 'cells' - 'labels' - 'metric')::text
  from (select pg_temp.v('sum')::jsonb x, pg_temp.v('mx')::jsonb y) z;
insert into r select 'csv_matrix_partner_rows', split_part(c, E'\n', 1) = '"partner by status","accepted","closed","duplicate"'
                     and array_length(string_to_array(c, E'\n'), 1) = 3 and c like E'%\n"M28 Gamma",1.0000,,1.0000%' and c like E'%\n"M28 Delta",,1.0000,%', c
  from (select b2b.report_csv(pg_temp.v('mx')::jsonb) c) z;
insert into r select 'report_email_tabular', jsonb_array_length(x -> 'attachments') = 1
                     and array_length(string_to_array(convert_from(decode(x -> 'attachments' -> 0 ->> 'content_base64', 'base64'), 'UTF8'), E'\n'), 1) = 4
                     and convert_from(decode(x -> 'attachments' -> 0 ->> 'content_base64', 'base64'), 'UTF8') like '%"M28 Delta"%'
                     and x ->> 'text' not like '%Cut at 2,000%', left(x ->> 'text', 120)
  from (select b2b.report_email(pg_temp.v('RT')::bigint) x) z;
insert into r select 'email_saved_limit_wins', array_length(string_to_array(convert_from(decode(x -> 'attachments' -> 0 ->> 'content_base64', 'base64'), 'UTF8'), E'\n'), 1) = 2,
                     left(x ->> 'text', 120)
  from (select b2b.report_email(pg_temp.v('RT1')::bigint) x) z;

-- over 2,000 breakdown values: 2,100 allocations (G and H on alternate rows, one day apart per pair) by day and partner
insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, created_at, is_test)
select pg_temp.v('L')::bigint, 100 + i, 'zzm28t|PG|Online', 'partner', case when i % 2 = 0 then pg_temp.v('G')::bigint else pg_temp.v('H')::bigint end,
       'closed', 'manual', now() - make_interval(days => (i + 1) / 2) - interval '1 hour', false
  from generate_series(1, 2100) i;
select b2b.refresh_facts();
set local role authenticated;
select pg_temp.admin();
insert into t select 'RC', (b2b.report_save(jsonb_build_object('name', 'Daily m28', 'kind', 'summary',
                              'definition', jsonb_build_object('metrics', '["allocations"]'::jsonb, 'dims', '["day","partner"]'::jsonb, 'filters', '{"segment":["zzm28t|PG|Online"]}'::jsonb,
                                                               'from', now() - interval '1060 days', 'to', now()))) ->> 'id');
insert into t select 'cut', b2b.report_run(jsonb_build_object('id', pg_temp.v('RC')::bigint))::text;
insert into t select 'cutx', b2b.report_run(jsonb_build_object('kind', 'matrix', 'definition', jsonb_build_object('metric', 'allocations', 'row_dim', 'day', 'col_dim', 'partner',
                                            'filters', '{"segment":["zzm28t|PG|Online"]}'::jsonb, 'from', now() - interval '1060 days', 'to', now())))::text;
reset role;
insert into r select 'report_cut_at_2000', (x -> 'truncated')::boolean and jsonb_array_length(x -> 'rows') = 2000 and (y -> 'truncated')::boolean
                     and jsonb_array_length(y -> 'cells') = 2000, (x -> 'truncated')::text || ' ' || jsonb_array_length(x -> 'rows') || ' / ' || (y -> 'truncated')::text
  from (select pg_temp.v('cut')::jsonb x, pg_temp.v('cutx')::jsonb y) z;
insert into r select 'report_email_cut_note', x ->> 'text' like E'%\nCut at 2,000 breakdown values: narrow the filters or the period.'
                     and x ->> 'html' like '%all are attached as CSV. Cut at 2,000 breakdown values: narrow the filters or the period.</p>%', right(x ->> 'text', 80)
  from (select b2b.report_email(pg_temp.v('RC')::bigint) x) z;

-- ---------- access ----------
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b7","role":"authenticated","aal":"aal2","email":"nobody28@test.local"}', true);
set local role authenticated;
do $x$ declare e text; begin
  begin perform b2b.sla_timers(); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('non_admin_sla_timers', e = '42501', e);
  begin perform b2b.dashboard_archive(1); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('non_admin_archive', e = '42501', e);
  begin perform b2b.csv_cell('x'); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('csv_cell_internal', e = '42501', e);
  begin perform b2b.dashboard_check_widgets('[]'); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('check_widgets_internal', e = '42501', e);
end $x$;
reset role;

select name, ok, detail from r order by ok, name;
rollback;
