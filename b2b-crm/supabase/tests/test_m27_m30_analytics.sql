-- M27–M30 on STAGING, rolled back: facts, the metric layer (breakdowns, filters, previous period, calculated metrics,
-- drill-down), the nine default dashboards render, dashboard builder rules, metric alerts and the alert digest (queued,
-- never sent: admin alerts stay off), scheduled delivery with CSV attachments, reports (tabular, summary, matrix, CSV),
-- Autopilot (applies only a confident, simulated gain; at most N a day), the 7-day review with automatic rollback,
-- the Ask-the-CRM log and the change simulator. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a7","role":"authenticated","aal":"aal2","email":"m27-admin@test.local"}', true)
$f$;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a7', 'm27-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000a7', 'm27-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a8', 'nobody27@test.local', 'authenticated', 'authenticated');
update b2b.settings set value = value || '{"enabled":false,"emails":["ops@example.com"],"whatsapp_numbers":[]}' where key = 'admin_alerts';
update b2b.settings set value = value || '{"holdout_share":0,"segments":{},"partner_weights":{},"kill_segments":[],"ai":{}}' where key = 'engine_policy';
update b2b.ai_recommendations set status = 'superseded' where status in ('open');

-- fixture: two partners, 12 leads (8 WhatsApp in Delhi, 4 website in Karnataka); 12 allocations in zzm27|PG|Online
with x as (insert into b2b.partners (slug, name, status) values ('m27-alpha', 'M27 Alpha', 'active') returning id) insert into t select 'A', id::text from x;
with x as (insert into b2b.partners (slug, name, status) values ('m27-beta', 'M27 Beta', 'active') returning id) insert into t select 'B', id::text from x;
do $x$
declare i int; v_id bigint; v_a bigint; v_d bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  for i in 1 .. 12 loop
    perform public.lead_intake(jsonb_build_object('phone', '91987650' || (6100 + i), 'source_system', 'crm', 'event_type', 'lead.created',
      'lead', jsonb_build_object('full_name', 'Analytics ' || i, 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                                 'state', case when i <= 8 then 'Delhi' else 'Karnataka' end, 'source', case when i <= 8 then 'whatsapp_direct' else 'website' end)));
    select id into v_id from public.student_leads where whatsapp_number = '91987650' || (6100 + i);
    update public.student_leads set lead_source = case when i <= 8 then 'whatsapp_direct' else 'website' end where id = v_id;
    insert into t values ('L' || i, v_id::text);
    insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, candidates, seed, selection_probability,
                                      scoring_mode, holdout, is_test, actor_type, created_at)
    values (v_id, 1, 'zzm27|PG|Online', '{}', 'commission_first', 'partner', case when i % 2 = 0 then pg_temp.v('A')::bigint else pg_temp.v('B')::bigint end,
            '[]', 0.5, 1, 'commission_first', i in (11, 12), false, 'engine', now() - interval '2 days')
    returning id into v_d;
    insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, engine_decision_id, cpe_net_inr, accepted_at, created_at, is_test)
    values (v_id, 1, 'zzm27|PG|Online', 'partner', case when i % 2 = 0 then pg_temp.v('A')::bigint else pg_temp.v('B')::bigint end,
            case when i in (3, 5) then 'duplicate' else 'closed' end, 'commission_first', v_d, case when i % 2 = 0 then 20000 else 10000 end,
            case when i not in (3, 5) then now() - interval '2 days' end, now() - interval '2 days', false)
    returning id into v_a;
    update public.student_leads set allocation_id = v_a, destination_type = 'partner', partner_id = case when i % 2 = 0 then pg_temp.v('A')::bigint else pg_temp.v('B')::bigint end,
           allocated_at = now() - interval '2 days' where id = v_id;
  end loop;
end $x$;
select b2b.refresh_facts();

-- ---------- metric layer ----------
insert into r select 'fact_leads_rows', count(*) = 12 and count(*) filter (where source = 'whatsapp_direct') = 8, count(*)::text
  from b2b.fact_leads where lead_id in (select v::bigint from t where k like 'L%');
insert into r select 'fact_allocations_rows', count(*) = 12 and count(*) filter (where duplicate) = 2, count(*)::text
  from b2b.fact_allocations where segment = 'zzm27|PG|Online';
insert into t select 'q1', b2b.metric_run('{"metric":"allocations","dims":["partner"],"filters":{"segment":["zzm27|PG|Online"]},"compare":"previous"}')::text;
insert into r select 'breakdown_by_partner', (x -> 'total' ->> 'value')::numeric = 12 and jsonb_array_length(x -> 'rows') = 2
                     and (select (rw ->> 'value')::numeric from jsonb_array_elements(x -> 'rows') rw where rw -> 'd' ->> 0 = pg_temp.v('A')) = 6
                     and x -> 'labels' -> 'partner' ->> pg_temp.v('A') = 'M27 Alpha' and (x -> 'total' ->> 'prev')::numeric = 0, x -> 'total' ::text
  from (select pg_temp.v('q1')::jsonb x) z;
insert into r select 'rate_metric', (x -> 'total' ->> 'value')::numeric = round(2 / 12.0, 4), x -> 'total' ->> 'value'
  from (select b2b.metric_run('{"metric":"duplicate_rate","filters":{"segment":["zzm27|PG|Online"]}}') x) z;
insert into r select 'two_dims_and_filter', jsonb_array_length(x -> 'rows') = 2 and (x -> 'total' ->> 'value')::numeric = 12, (x -> 'rows')::text
  from (select b2b.metric_run('{"metric":"leads","dims":["source","state"],"filters":{"state":["Delhi","Karnataka"],"source":["whatsapp_direct","website"],"course":["zzm27"]}}') x) z;
insert into r select 'time_grain', exists (select 1 from jsonb_array_elements(x -> 'rows') rw where rw -> 'd' ->> 0 = ((now() - interval '2 days') at time zone 'Asia/Kolkata')::date::text), null
  from (select b2b.metric_run('{"metric":"allocations","dims":["day"],"filters":{"segment":["zzm27|PG|Online"]}}') x) z;
do $x$ declare e text; begin
  begin perform b2b.metric_run('{"metric":"sla_compliance","dims":["source"]}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('dims_checked', e = 'SLA compliance cannot be broken down by source', e);
  begin perform b2b.metric_run('{"metric":"nope"}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('unknown_metric', e = 'unknown metric nope', e);
  begin perform b2b.metric_run('{"metric":"leads","filters":{"source; drop table x":["a"]}}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('no_injection', e like 'Leads cannot be filtered by%', e);
end $x$;
set local role authenticated;
select pg_temp.admin();
select b2b.metric_save('{"key":"cpe_per_lead_m27","label":"Commission per routed lead","unit":"inr","formula":[{"m":"cpe_avg"},{"m":"accept_rate"},{"op":"*"}]}');
insert into r select 'calculated_metric', abs((x -> 'total' ->> 'value')::numeric - round(15000 * (10 / 12.0), 2)) < 1, x -> 'total' ->> 'value'
  from (select b2b.metric_query('{"metric":"cpe_per_lead_m27","filters":{"segment":["zzm27|PG|Online"]}}') x) z;
do $x$ declare e text; begin
  begin perform b2b.metric_save('{"key":"bad_m27","label":"Bad","unit":"count","formula":[{"m":"leads"},{"op":"+"}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('formula_checked', e = 'the formula is not well formed', e);
  begin perform b2b.metric_save('{"key":"leads","label":"Mine","unit":"count","formula":[{"m":"leads"}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('builtin_protected', e = 'that key belongs to a built-in metric', e);
end $x$;
insert into r select 'drill_rows', (x ->> 'shown')::int = 2 and x ->> 'fact' = 'fact_allocations', x ->> 'shown'
  from (select b2b.metric_drill_admin('{"metric":"duplicates","filters":{"segment":["zzm27|PG|Online"]}}') x) z;
insert into r select 'catalogue', jsonb_array_length(x -> 'metrics') >= 50 and exists (select 1 from jsonb_array_elements(x -> 'metrics') m where m ->> 'key' = 'cpe_per_lead_m27' and (m ->> 'calculated')::boolean), null
  from (select b2b.metric_catalogue() x) z;
reset role;  -- the admin claims stay set; internal functions are called as the owner

-- ---------- dashboards ----------
insert into r select 'defaults_valid', bool_and(jsonb_array_length(b2b.dashboard_check_widgets(d.widgets)) = jsonb_array_length(d.widgets)) and count(*) = 9, count(*)::text
  from b2b.dashboards d where d.is_default;
insert into r select 'defaults_render', not exists (select 1 from b2b.dashboards d, jsonb_each(b2b.dashboard_data(d.id) -> 'data') w where d.is_default and w.value ? 'error'),
                     (select string_agg(d.slug || ':' || w.key || ':' || (w.value ->> 'error'), '; ') from b2b.dashboards d, jsonb_each(b2b.dashboard_data(d.id) -> 'data') w where d.is_default and w.value ? 'error');
insert into r select 'command_center_kpi', (x -> 'data' -> 'k2' -> 'series' -> 0 -> 'total' ->> 'value') is not null and jsonb_array_length(x -> 'data' -> 's1' -> 'series') = 2, null
  from (select b2b.dashboard_data((select id from b2b.dashboards where slug = 'command-center'), '7d', '{}') x) z;
do $x$ declare e text; begin
  begin perform b2b.dashboard_save(jsonb_build_object('id', (select id from b2b.dashboards where slug = 'partner-league'), 'name', 'x', 'widgets', '[]'::jsonb)); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('defaults_read_only', e = 'built-in dashboards are read-only: duplicate it to change it', e);
  begin perform b2b.dashboard_save('{"name":"Bad","widgets":[{"id":"a","type":"pie","metric":"leads","w":3,"h":1}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('widget_type_checked', e = 'unknown widget type pie', e);
  begin perform b2b.dashboard_save('{"name":"Bad","widgets":[{"id":"a","type":"kpi","metric":"nope","title":"T","w":3,"h":1}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('widget_metric_checked', e = 'unknown metric nope in "T"', e);
end $x$;
insert into t select 'D', (b2b.dashboard_copy((select id from b2b.dashboards where slug = 'partner-league')) ->> 'id');
select b2b.dashboard_save(jsonb_build_object('id', pg_temp.v('D')::bigint, 'name', 'My league', 'period', '7d', 'filters', '{"segment":["zzm27|PG|Online"]}'::jsonb,
  'widgets', '[{"id":"k","type":"kpi","title":"Routed","metric":"allocations","w":3,"h":1},{"id":"g","type":"gauge","title":"Accepted","metric":"accept_rate","target":0.9,"w":3,"h":1}]'::jsonb));
insert into r select 'copy_edit_filter', (x -> 'data' -> 'k' -> 'series' -> 0 -> 'total' ->> 'value')::numeric = 12, x -> 'data' -> 'k' ::text
  from (select b2b.dashboard_data(pg_temp.v('D')::bigint) x) z;
select b2b.dashboard_set_home(pg_temp.v('D')::bigint);
insert into r select 'home_set', (b2b.dashboards_list() ->> 'home_dashboard_id')::bigint = pg_temp.v('D')::bigint, null;
select b2b.dashboard_archive(pg_temp.v('D')::bigint);
insert into r select 'archive_clears_home', b2b.dashboards_list() -> 'home_dashboard_id' = 'null'::jsonb, null;
reset role;

-- ---------- alerts and schedules ----------
set local role authenticated;
select pg_temp.admin();
insert into t select 'AL', (b2b.metric_alert_save('{"name":"Duplicates high","metric":"duplicate_rate","filters":{"segment":["zzm27|PG|Online"]},"window_hours":72,"op":">","threshold":0.1,"channels":["email"]}') ->> 'id');
do $x$ declare e text; begin
  begin perform b2b.metric_alert_save('{"name":"x","metric":"sla_compliance","filters":{"source":["a"]},"op":">","threshold":1}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('alert_filters_checked', e like 'SLA compliance cannot be filtered by source', e);
end $x$;
insert into t select 'SC', (b2b.schedule_save(jsonb_build_object('name', 'Weekly league', 'dashboard_id', (select id from b2b.dashboards where slug = 'partner-league'),
                                                               'frequency', 'weekly', 'weekday', 1, 'hour_ist', 9, 'recipients', '["md@example.com"]'::jsonb)) ->> 'id');
reset role;
insert into r select 'next_due_monday_9', extract(isodow from s.next_due_at at time zone 'Asia/Kolkata') = 1 and extract(hour from s.next_due_at at time zone 'Asia/Kolkata') = 9
                     and s.next_due_at > now(), s.next_due_at::text from b2b.report_schedules s where s.id = pg_temp.v('SC')::bigint;
update b2b.report_schedules set next_due_at = now() - interval '1 minute' where id = pg_temp.v('SC')::bigint;
select b2b.log_event('alert.partner_auto_paused', null, null, pg_temp.v('A')::bigint, '{"reason":"m27 test"}');
update b2b.settings set value = value || '{"enabled":true}' where key = 'admin_alerts';
-- the e-mail provider may be unset on staging: messages are queued and then fail with the reason; nothing reaches a real address
insert into t select 'tick', b2b.admin_alerts_tick()::text;
insert into r select 'metric_alert_fired', (select last_fired_at is not null and round(last_value, 4) = round(2 / 12.0, 4) from b2b.metric_alerts where id = pg_temp.v('AL')::bigint)
                     and exists (select 1 from b2b.events where type = 'alert.metric' and payload ->> 'alert_id' = pg_temp.v('AL'))
                     and exists (select 1 from b2b.admin_messages where kind = 'metric_alert' and recipients = '{ops@example.com}'), pg_temp.v('tick');
insert into r select 'digest_queued', exists (select 1 from b2b.admin_messages where kind = 'alert_digest' and body_text like '%partner auto paused — M27 Alpha: m27 test%'), null;
insert into r select 'schedule_sent_with_csv', m.recipients = '{md@example.com}' and jsonb_array_length(m.attachments) >= 1 and m.body_html like '%Partner League Table%'
                     and convert_from(decode(m.attachments -> 0 ->> 'content_base64', 'base64'), 'UTF8') like 'partner,value%', m.subject
  from b2b.admin_messages m where m.kind = 'report' and m.ref ->> 'schedule_id' = pg_temp.v('SC');
insert into r select 'schedule_rolled_forward', s.next_due_at > now() and s.last_sent_at is not null, null from b2b.report_schedules s where s.id = pg_temp.v('SC')::bigint;
insert into r select 'cooldown', (select count(*) from b2b.admin_messages where kind = 'metric_alert') = 1
                     and (select (b2b.metric_alerts_tick()) = 0), null;
update b2b.settings set value = value || '{"enabled":false}' where key = 'admin_alerts';

-- ---------- reports ----------
set local role authenticated;
select pg_temp.admin();
insert into t select 'rt', b2b.report_run('{"kind":"tabular","definition":{"fact":"fact_allocations","columns":["allocation_id","partner_id","status","cpe"],"filters":{"segment":["zzm27|PG|Online"]},"period":"7d","sort":"cpe"}}')::text;
insert into r select 'report_tabular', jsonb_array_length(x -> 'rows') = 12 and (x -> 'rows' -> 0 ->> 'cpe')::numeric = 20000, jsonb_array_length(x -> 'rows')::text
  from (select pg_temp.v('rt')::jsonb x) z;
insert into r select 'report_summary', jsonb_array_length(x -> 'rows') = 2 and jsonb_array_length(x -> 'metrics') = 2, (x -> 'rows')::text
  from (select b2b.report_run('{"kind":"summary","definition":{"metrics":["allocations","duplicate_rate"],"dims":["partner"],"filters":{"segment":["zzm27|PG|Online"]},"period":"7d"}}') x) z;
insert into r select 'report_matrix', jsonb_array_length(x -> 'rows') = 2 and jsonb_array_length(x -> 'cols') = 2, (x -> 'cols')::text
  from (select b2b.report_run('{"kind":"matrix","definition":{"metric":"leads","row_dim":"state","col_dim":"source","filters":{"course":["zzm27"],"state":["Delhi","Karnataka"]},"period":"7d"}}') x) z;
insert into r select 'report_csv', split_part(x, E'\n', 1) = 'allocation_id,partner_id,status,cpe' and x like '%"M27 Alpha"%' and array_length(string_to_array(x, E'\n'), 1) = 13, split_part(x, E'\n', 1)
  from (select b2b.report_csv_admin('{"kind":"tabular","definition":{"fact":"fact_allocations","columns":["allocation_id","partner_id","status","cpe"],"filters":{"segment":["zzm27|PG|Online"]},"period":"7d"}}') x) z;
do $x$ declare e text; begin
  begin perform b2b.report_run('{"kind":"tabular","definition":{"fact":"fact_leads","columns":["lead_id","whatsapp_number"]}}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('no_personal_columns', e = 'unknown column whatsapp_number', e);
  begin perform b2b.report_run('{"kind":"tabular","definition":{"fact":"student_leads","columns":["id"]}}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('facts_only', e = 'choose what the report lists', e);
end $x$;
insert into t select 'RP', (b2b.report_save('{"name":"Duplicates by partner","kind":"summary","definition":{"metrics":["duplicates"],"dims":["partner"],"period":"30d"}}') ->> 'id');
reset role;
insert into r select 'report_email', (x ->> 'name') = 'Duplicates by partner' and jsonb_array_length(x -> 'attachments') = 1, left(x ->> 'text', 80)
  from (select b2b.report_email(pg_temp.v('RP')::bigint) x) z;

-- ---------- Autopilot and the 7-day review ----------
update b2b.settings set value = value || '{"enabled":true,"mode":"autopilot","autopilot":{"min_gain_pct":3,"max_per_day":1,"min_decisions":30}}' where key = 'ai';
with x as (insert into b2b.ai_runs (trigger, kind, model, status) values ('manual', 'optimise', 'claude-sonnet-5-5', 'done') returning id) insert into t select 'run', id::text from x;
insert into b2b.ai_recommendations (run_id, kind, title, rationale, change, simulation, expires_at) values
  (pg_temp.v('run')::bigint, 'setting_change', 'Weak gain', 'r', '{"lever":"exploration_share","segment":"zzm27|PG|Online","value":0.3}',
   '{"simulated":true,"decisions":80,"gain_pct":1.2,"ci95":[-10,40]}', now() + interval '7 days'),
  (pg_temp.v('run')::bigint, 'setting_change', 'Confident gain', 'r', '{"lever":"exploration_share","segment":"zzm27|PG|Online","value":0.4}',
   '{"simulated":true,"decisions":80,"gain_pct":6.5,"ci95":[12,90]}', now() + interval '7 days'),
  (pg_temp.v('run')::bigint, 'setting_change', 'Second confident gain', 'r', '{"lever":"prior_weight","value":10}',
   '{"simulated":true,"decisions":80,"gain_pct":5,"ci95":[5,60]}', now() + interval '7 days'),
  (pg_temp.v('run')::bigint, 'pause_draft', 'Pause B', 'r', jsonb_build_object('lever', 'pause_draft', 'partner_id', pg_temp.v('B')::bigint), null, now() + interval '7 days');
insert into t select 'ap', b2b.ai_autopilot_tick()::text;
insert into r select 'autopilot_applies_confident_only', (select status from b2b.ai_recommendations where title = 'Confident gain' and run_id = pg_temp.v('run')::bigint) = 'applied'
                     and (select decided_by from b2b.ai_recommendations where title = 'Confident gain' and run_id = pg_temp.v('run')::bigint) = 'autopilot'
                     and (select status from b2b.ai_recommendations where title = 'Weak gain' and run_id = pg_temp.v('run')::bigint) = 'open'
                     and (select status from b2b.ai_recommendations where title = 'Pause B' and run_id = pg_temp.v('run')::bigint) = 'open'
                     and (select (value -> 'segments' -> 'zzm27|PG|Online' -> 'exploration_share' ->> 'value')::numeric from b2b.settings where key = 'engine_policy') = 0.4,
                     pg_temp.v('ap');
insert into r select 'autopilot_daily_cap', (select status from b2b.ai_recommendations where title = 'Second confident gain' and run_id = pg_temp.v('run')::bigint) = 'open', null;
-- review: since the change, AI-steered leads (10, all stuck) against holdout (2 + 10 more, many applied) in the segment
update b2b.ai_recommendations set decided_at = now() - interval '8 days', check_due_at = now() - interval '1 minute'
 where title = 'Confident gain' and run_id = pg_temp.v('run')::bigint;
update b2b.engine_decisions set holdout = false where segment = 'zzm27|PG|Online';
do $x$
declare i int; v_d bigint; v_a bigint;
begin
  for i in 1 .. 12 loop
    insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, candidates, seed, selection_probability, scoring_mode, holdout, is_test, actor_type)
    values (pg_temp.v('L1')::bigint, 10 + i, 'zzm27|PG|Online', '{}', 'commission_first', 'partner', pg_temp.v('A')::bigint, '[]', 0.5, 1, 'commission_first', true, false, 'engine')
    returning id into v_d;
    insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, engine_decision_id, cpe_net_inr, accepted_at, created_at, is_test)
    values (pg_temp.v('L1')::bigint, 10 + i, 'zzm27|PG|Online', 'partner', pg_temp.v('A')::bigint, 'closed', 'commission_first', v_d, 20000, now() - interval '1 day', now() - interval '1 day', false)
    returning id into v_a;
    insert into public.enrollments (lead_id, cycle_no, partner_id, allocation_id, status, source_product, enrolled_on)
    select pg_temp.v('L1')::bigint, 10 + i, pg_temp.v('A')::bigint, v_a, 'reported', 'b2b', current_date where i % 2 = 0;
    -- and 12 more AI-steered leads that went nowhere
    insert into b2b.engine_decisions (lead_id, cycle_no, segment, interest, mode, destination_type, winner_partner_id, candidates, seed, selection_probability, scoring_mode, holdout, is_test, actor_type)
    values (pg_temp.v('L2')::bigint, 10 + i, 'zzm27|PG|Online', '{}', 'commission_first', 'partner', pg_temp.v('A')::bigint, '[]', 0.5, 1, 'commission_first', false, false, 'engine')
    returning id into v_d;
    insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, engine_decision_id, cpe_net_inr, accepted_at, created_at, is_test)
    values (pg_temp.v('L2')::bigint, 10 + i, 'zzm27|PG|Online', 'partner', pg_temp.v('A')::bigint, 'closed', 'commission_first', v_d, 20000, now() - interval '1 day', now() - interval '1 day', false);
  end loop;
end $x$;
select b2b.ai_review_tick();
insert into r select 'review_rolls_back_autopilot', x.status = 'rolled_back' and x.check_result ->> 'verdict' = 'worse' and (x.check_result ->> 'auto_rolled_back')::boolean
                     and not coalesce((select value -> 'segments' -> 'zzm27|PG|Online' from b2b.settings where key = 'engine_policy') ? 'exploration_share', false)
                     and exists (select 1 from b2b.events where type = 'alert.ai_rollback' and (payload ->> 'id')::bigint = x.id), x.check_result::text
  from b2b.ai_recommendations x where x.title = 'Confident gain' and x.run_id = pg_temp.v('run')::bigint;
update b2b.settings set value = value || '{"enabled":false,"mode":"advisory"}' where key = 'ai';

-- ---------- Ask the CRM log, simulator, access ----------
set local role authenticated;
select pg_temp.admin();
insert into r select 'ask_logged', (select kind = 'ask' and status = 'done' and cost_usd = round((10000 * 3 + 500 * 15) / 1000000.0, 4) from b2b.ai_runs where id = (x ->> 'id')::bigint)
                     and jsonb_array_length(b2b.ai_ask_history(5)) >= 1, x::text
  from (select b2b.ai_ask_log('{"question":"How many leads this week?","answer":"12 leads.","model":"claude-sonnet-5-5","usage":{"in":10000,"out":500},"validation":{"ok":true},"sources":[{"metric":"leads"}]}') x) z;
do $x$ declare e text; begin
  begin perform b2b.simulate_change('{"lever":"exploration_share","segment":"zzm27|PG|Online","value":0.9}', 30); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('simulate_change_bounds', e = 'exploration share is 0 to 50%', e);
end $x$;
insert into r select 'simulate_change_runs', (x ->> 'simulated')::boolean and x ? 'decisions', x::text
  from (select b2b.simulate_change('{"lever":"exploration_share","segment":"zzm27|PG|Online","value":0.3}', 30) x) z;
reset role;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a8","role":"authenticated","aal":"aal2","email":"nobody27@test.local"}', true);
set local role authenticated;
do $x$ declare e text; begin
  begin perform b2b.metric_query('{"metric":"leads"}'); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('non_admin_metrics', e = '42501', e);
  begin perform b2b.dashboard_render(1); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('render_internal', e = '42501', e);
  begin perform 1 from b2b.fact_leads limit 1; e := 'read'; exception when others then e := sqlstate; end;
  insert into r values ('facts_not_readable', e = '42501', e);
end $x$;
reset role;

select name, ok, detail from r order by ok, name;
rollback;
