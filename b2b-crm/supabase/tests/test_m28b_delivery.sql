-- M28b on STAGING, rolled back: messages to the Admin (one WhatsApp row per number, flattened body; stale messages skipped;
-- retries back off), the metric-alert and schedule checks (22023 messages), switching alerts and schedules off and on,
-- schedules of archived dashboards and failing reports stop, the home flag in dashboard_data, one failing widget does not
-- break its dashboard, and dashboard filters reach a calculated metric only where every base has the dimension.
-- Needs no fixture of its own beyond a test partner and the seeded 'partner-league' dashboard. Nothing is sent: admin
-- alerts are off except for one admin_send_tick, the recipients are example.com and test-range numbers, and pg_net only
-- sends committed requests. Every row must say ok = true.
begin;
select pg_advisory_xact_lock(hashtext('b2b.admin_alerts_tick'));   -- keeps the per-minute tick out while this runs
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b4","role":"authenticated","aal":"aal2","email":"m28b-admin@test.local"}', true)
$f$;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000b4', 'm28b-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000b4', 'm28b-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000b5', 'nobody28b@test.local', 'authenticated', 'authenticated');
update b2b.settings set value = value || '{"enabled":false,"emails":["ops@example.com"],"whatsapp_numbers":[]}' where key = 'admin_alerts';
with x as (insert into b2b.partners (slug, name, status) values ('m28b-alpha', 'M28b Alpha', 'active') returning id) insert into t select 'A', id::text from x;

-- ---------- admin messages (as the owner) ----------
-- C88: one WhatsApp row per distinct number, with a body that has no newline or tab
update b2b.settings set value = value || '{"whatsapp_numbers":["910000000801","910000000802","910000000801"]}' where key = 'admin_alerts';
insert into t select 'wq', b2b.admin_queue('test', 'M28b subject', E'line 1\nline 2\tx', null, '[]', '{"m28b":"wa"}', '{whatsapp}')::text;
insert into r select 'whatsapp_row_per_number', pg_temp.v('wq') = '2' and count(*) = 2 and bool_and(channel = 'whatsapp' and cardinality(recipients) = 1)
                     and count(distinct recipients[1]) = 2 and bool_and(body_text = 'line 1 · line 2 · x' and position(E'\n' in body_text) = 0),
                     pg_temp.v('wq') || ': ' || string_agg(recipients[1] || ' ' || body_text, '; ')
  from b2b.admin_messages where ref ->> 'm28b' = 'wa';
update b2b.settings set value = value || '{"whatsapp_numbers":[]}' where key = 'admin_alerts';

-- C117: messages queued for over 2 days are skipped (even while alerts are off); a retry waits 5 minutes per attempt made
with x as (insert into b2b.admin_messages (kind, channel, recipients, subject, body_text, created_at)
           values ('test', 'email', '{ops@example.com}', 'old', 'old', now() - interval '3 days') returning id) insert into t select 'stale', id::text from x;
with x as (insert into b2b.admin_messages (kind, channel, recipients, subject, body_text, attempts, sent_at, error)
           values ('test', 'email', '{ops@example.com}', 'retry', 'retry', 1, now(), 'HTTP 429') returning id) insert into t select 'retry', id::text from x;
with x as (insert into b2b.admin_messages (kind, channel, recipients, subject, body_text, attempts, sent_at, error)
           values ('test', 'email', '{ops@example.com}', 'waited', 'waited', 1, now() - interval '6 minutes', 'HTTP 429') returning id) insert into t select 'waited', id::text from x;
insert into t select 'send_off', b2b.admin_send_tick()::text;
insert into r select 'stale_skipped', m.status = 'skipped' and m.error like 'not sent within 2 days%', m.status || ' / ' || pg_temp.v('send_off')
  from b2b.admin_messages m where m.id = pg_temp.v('stale')::bigint;
update b2b.settings set value = value || '{"enabled":true}' where key = 'admin_alerts';
-- the e-mail provider may be unset on staging: the message then fails with the reason; a request made here is rolled back, never sent
insert into t select 'send_on', b2b.admin_send_tick()::text;
insert into r select 'retry_backoff', m.status = 'queued' and m.attempts = 1, m.status || ' / ' || m.attempts || ' / ' || pg_temp.v('send_on')
  from b2b.admin_messages m where m.id = pg_temp.v('retry')::bigint;
insert into r select 'retry_after_wait', m.status <> 'queued', m.status || ' / ' || coalesce(m.error, '')
  from b2b.admin_messages m where m.id = pg_temp.v('waited')::bigint;
update b2b.settings set value = value || '{"enabled":false}' where key = 'admin_alerts';

-- C108: 'Send a test' queues nothing without recipients
insert into t select 'tests_before', (select count(*) from b2b.admin_messages where kind = 'test')::text;
set local role authenticated;
select pg_temp.admin();
select b2b.admin_alerts_settings_save('{"emails":[],"whatsapp_numbers":[]}', 'm28b test: no recipients');
insert into t select 'test0', b2b.admin_alerts_test()::text;
reset role;
insert into r select 'test_without_recipients', (pg_temp.v('test0')::jsonb ->> 'queued') = '0'
                     and (select count(*) from b2b.admin_messages where kind = 'test')::text = pg_temp.v('tests_before'), pg_temp.v('test0');
set local role authenticated;
select b2b.admin_alerts_settings_save('{"emails":["ops@example.com"]}', 'm28b test: one recipient');
insert into t select 'test1', b2b.admin_alerts_test()::text;
reset role;
insert into r select 'test_with_one_email', (pg_temp.v('test1')::jsonb ->> 'queued') = '1'
                     and exists (select 1 from b2b.admin_messages where kind = 'test' and channel = 'email' and recipients = '{ops@example.com}' and subject like 'Test alert%'),
                     pg_temp.v('test1');

-- ---------- metric alerts and schedules: the checks (as the Admin) ----------
set local role authenticated;
select pg_temp.admin();
do $x$
declare e text; v_pl bigint := (select id from b2b.dashboards where slug = 'partner-league');
begin
  -- C116 (a) schedules
  begin perform b2b.schedule_save(jsonb_build_object('name', 'Bad', 'dashboard_id', v_pl, 'frequency', 'monthly', 'monthday', 31, 'recipients', '["md@example.com"]'::jsonb)); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('schedule_monthday_message', e = 'the day of the month is 1 to 28', e);
  begin perform b2b.schedule_save(jsonb_build_object('name', 'Bad', 'dashboard_id', v_pl, 'frequency', 'weekly', 'weekday', 0, 'recipients', '["md@example.com"]'::jsonb)); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('schedule_weekday_message', e = 'choose a day of the week', e);
  begin perform b2b.schedule_save(jsonb_build_object('name', 'Bad', 'dashboard_id', v_pl, 'frequency', 'daily', 'hour_ist', 24, 'recipients', '["md@example.com"]'::jsonb)); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('schedule_hour_message', e = 'the hour is 0 to 23', e);
  begin perform b2b.schedule_save('{"name":"Bad","report_id":-1,"frequency":"daily","recipients":["md@example.com"]}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('schedule_report_missing', e = 'report not found', e);
  -- C76 (d)
  begin perform b2b.schedule_save('{"name":"Bad","report_id":999999999,"frequency":"daily","recipients":["md@example.com"]}'); e := 'saved';
  exception when others then e := sqlstate || ' ' || sqlerrm; end;
  insert into r values ('schedule_report_checked', e = 'P0002 report not found', e);
  -- C116 (b) alerts
  begin perform b2b.metric_alert_save('{"name":"x","metric":"duplicate_rate","op":">","threshold":0.1,"window_hours":3000}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('alert_window_message', e = 'the window is 1 to 2160 hours', e);
  begin perform b2b.metric_alert_save('{"name":"x","metric":"duplicate_rate","op":">","threshold":0.1,"cooldown_hours":0}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('alert_wait_message', e = 'the wait is 1 to 720 hours', e);
  begin perform b2b.metric_alert_save('{"name":"x","metric":"duplicate_rate","op":">","threshold":0.1,"channels":["sms"]}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('alert_channel_message', e = 'send by email or whatsapp', e);
  begin perform b2b.metric_alert_save('{"name":"x","metric":"duplicate_rate","op":">","threshold":0.1,"min_volume":20,"volume_metric":"nope"}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('alert_volume_metric_message', e = 'unknown volume metric', e);
  -- C77 (a) the minimum volume
  begin perform b2b.metric_alert_save('{"name":"x","metric":"duplicate_rate","op":">","threshold":0.1,"min_volume":20}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('alert_minimum_needs_count', e = 'choose the count the minimum applies to', e);
  begin perform b2b.metric_alert_save('{"name":"x","metric":"duplicate_rate","op":">","threshold":0.1,"min_volume":20,"volume_metric":"duplicate_rate"}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('alert_minimum_count_metric', e = 'the minimum is counted with a count metric', e);
  begin perform b2b.metric_alert_save('{"name":"x","metric":"duplicate_rate","op":">","threshold":0.1,"min_volume":-1,"volume_metric":"allocations"}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('alert_minimum_range', e = 'the minimum is a whole number, 0 or more', e);
end $x$;
-- C77: without a minimum the alert fires as before (any number of leads is >= 0)
insert into t select 'AW', (b2b.metric_alert_save('{"name":"M28b any leads","metric":"leads","op":">=","threshold":0,"min_volume":0,"channels":["email"]}') ->> 'id');
-- C80: an alert and a schedule of the Admin's own, to switch off and on
insert into t select 'AON', (b2b.metric_alert_save('{"name":"M28b switch","metric":"leads","op":">","threshold":1000000000,"channels":["email"]}') ->> 'id');
insert into t select 'SON', (b2b.schedule_save(jsonb_build_object('name', 'M28b league', 'dashboard_id', (select id from b2b.dashboards where slug = 'partner-league'),
                                                                  'frequency', 'daily', 'recipients', '["md@example.com"]'::jsonb)) ->> 'id');
-- C76 (b): a copy of the league table, archived below without dashboard_archive
insert into t select 'D', (b2b.dashboard_copy((select id from b2b.dashboards where slug = 'partner-league')) ->> 'id');
reset role;

insert into t select 'mtick', b2b.metric_alerts_tick()::text;
insert into r select 'alert_without_minimum_fires', a.last_fired_at is not null
                     and exists (select 1 from b2b.admin_messages m where m.kind = 'metric_alert' and m.ref ->> 'alert_id' = pg_temp.v('AW') and m.recipients = '{ops@example.com}'),
                     coalesce(a.last_value::text, 'null') || ' / ' || pg_temp.v('mtick')
  from b2b.metric_alerts a where a.id = pg_temp.v('AW')::bigint;

-- ---------- switching off and on (C80) ----------
set local role authenticated;
select b2b.metric_alert_set_active(pg_temp.v('AON')::bigint, false);
select b2b.schedule_set_active(pg_temp.v('SON')::bigint, false);
reset role;
insert into r select 'alert_switched_off', not a.active, a.active::text from b2b.metric_alerts a where a.id = pg_temp.v('AON')::bigint;
insert into r select 'schedule_switched_off', not s.active and s.next_due_at is null, coalesce(s.next_due_at::text, 'null') from b2b.report_schedules s where s.id = pg_temp.v('SON')::bigint;
update b2b.metric_alerts set last_checked_at = now() where id = pg_temp.v('AON')::bigint;
update b2b.report_schedules set failures = 3 where id = pg_temp.v('SON')::bigint;
set local role authenticated;
select b2b.metric_alert_set_active(pg_temp.v('AON')::bigint, true);
select b2b.schedule_set_active(pg_temp.v('SON')::bigint, true);
reset role;
insert into r select 'alert_switched_on', a.active and a.last_checked_at is null, a.active::text || ' / ' || coalesce(a.last_checked_at::text, 'null')
  from b2b.metric_alerts a where a.id = pg_temp.v('AON')::bigint;
insert into r select 'schedule_switched_on', s.active and s.next_due_at > now() and s.failures = 0, coalesce(s.next_due_at::text, 'null') || ' / ' || s.failures
  from b2b.report_schedules s where s.id = pg_temp.v('SON')::bigint;
insert into r select 'switches_logged', count(*) filter (where type = 'analytics.metric_alert_switched') = 2 and count(*) filter (where type = 'analytics.schedule_switched') = 2, count(*)::text
  from b2b.events where (type = 'analytics.metric_alert_switched' and payload ->> 'id' = pg_temp.v('AON'))
                     or (type = 'analytics.schedule_switched' and payload ->> 'id' = pg_temp.v('SON'));

-- ---------- schedules that cannot be sent (C76) ----------
-- (b) the dashboard was archived: the schedule switches off at its next run
update b2b.dashboards set archived_at = now() where id = pg_temp.v('D')::bigint;
with x as (insert into b2b.report_schedules (name, dashboard_id, frequency, recipients, next_due_at)
           values ('M28b on archived', pg_temp.v('D')::bigint, 'daily', '{md@example.com}', now() - interval '1 minute') returning id) insert into t select 'SCX', id::text from x;
insert into t select 'stick', b2b.schedules_tick()::text;
insert into r select 'archived_schedule_stops', not s.active and s.failures = 1
                     and exists (select 1 from b2b.events e where e.type = 'alert.schedule_failed' and e.payload ->> 'schedule_id' = pg_temp.v('SCX')
                                    and (e.payload ->> 'deactivated')::boolean and e.payload ->> 'error' = 'dashboard not found'),
                     s.active::text || ' / ' || s.failures || ' / ' || pg_temp.v('stick')
  from b2b.report_schedules s where s.id = pg_temp.v('SCX')::bigint;
-- (c) a report that keeps failing: the fifth failure in a row switches the schedule off
with x as (insert into b2b.reports (name, kind, definition) values ('M28b broken', 'summary', '{"metrics":["nope"],"dims":["partner"]}') returning id) insert into t select 'RB', id::text from x;
with x as (insert into b2b.report_schedules (name, report_id, frequency, recipients, next_due_at)
           values ('M28b broken report', pg_temp.v('RB')::bigint, 'daily', '{md@example.com}', now() - interval '1 minute') returning id) insert into t select 'SCF', id::text from x;
do $x$
begin
  for i in 1 .. 5 loop
    update b2b.report_schedules set next_due_at = now() - interval '1 minute' where id = pg_temp.v('SCF')::bigint;
    if i = 5 then insert into t select 'SCF4', active::text || ' / ' || failures from b2b.report_schedules where id = pg_temp.v('SCF')::bigint; end if;
    perform b2b.schedules_tick();
  end loop;
end $x$;
insert into r select 'schedule_failure_cap', not s.active and s.failures = 5 and pg_temp.v('SCF4') = 'true / 4'
                     and (select count(*) from b2b.events e where e.type = 'alert.schedule_failed' and e.payload ->> 'schedule_id' = pg_temp.v('SCF')) = 5
                     and (select count(*) from b2b.events e where e.type = 'alert.schedule_failed' and e.payload ->> 'schedule_id' = pg_temp.v('SCF')
                             and (e.payload ->> 'deactivated')::boolean) = 1,
                     s.active::text || ' / ' || s.failures || ' (before the fifth: ' || pg_temp.v('SCF4') || ')'
  from b2b.report_schedules s where s.id = pg_temp.v('SCF')::bigint;
-- C80: an alert whose filters no longer suit its metric (inserted directly) cannot be switched on
with x as (insert into b2b.metric_alerts (name, metric, filters, op, threshold, active) values ('M28b SLA by source', 'sla_compliance', '{"source":["a"]}', '<', 0.5, false) returning id)
  insert into t select 'ASLA', id::text from x;
set local role authenticated;
do $x$ declare e text; begin
  begin perform b2b.schedule_set_active(pg_temp.v('SCX')::bigint, true); e := 'switched'; exception when others then e := sqlerrm; end;
  insert into r values ('schedule_archived_dashboard_stays_off', e = 'the dashboard is archived: schedule another one', e);
  begin perform b2b.metric_alert_set_active(pg_temp.v('ASLA')::bigint, true); e := 'switched'; exception when others then e := sqlerrm; end;
  insert into r values ('alert_switch_on_rechecks_filters', e like 'SLA compliance cannot be filtered by source%', e);
end $x$;
reset role;
insert into r select 'schedule_and_alert_still_off', not (select active from b2b.report_schedules where id = pg_temp.v('SCX')::bigint)
                     and not (select active from b2b.metric_alerts where id = pg_temp.v('ASLA')::bigint), null;

-- ---------- dashboards (C106, C115, C68) ----------
set local role authenticated;
insert into t select 'H', (b2b.dashboard_copy((select id from b2b.dashboards where slug = 'partner-league')) ->> 'id');
select b2b.dashboard_set_home(pg_temp.v('H')::bigint);
insert into r select 'home_flag_set', x -> 'dashboard' ->> 'is_home' = 'true', x -> 'dashboard' ->> 'is_home'
  from (select b2b.dashboard_data(pg_temp.v('H')::bigint) x) z;
insert into r select 'home_flag_other', x -> 'dashboard' ->> 'is_home' = 'false', x -> 'dashboard' ->> 'is_home'
  from (select b2b.dashboard_data((select id from b2b.dashboards where slug = 'partner-league')) x) z;
select b2b.dashboard_set_home(null);
insert into r select 'home_flag_cleared', x -> 'dashboard' ->> 'is_home' = 'false', x -> 'dashboard' ->> 'is_home'
  from (select b2b.dashboard_data(pg_temp.v('H')::bigint) x) z;
-- a calculated metric across two facts: commission (fact_money) per routed lead (fact_allocations)
select b2b.metric_save('{"key":"rev_per_alloc_m28","label":"Commission per routed lead (m28b test)","unit":"inr","formula":[{"m":"commission_realised"},{"m":"allocations"},{"op":"/"}]}');
-- the same bases the other way round: the first base (fact_allocations) has routing_mode, the second does not
select b2b.metric_save('{"key":"alloc_per_rev_m28","label":"Routed leads per rupee (m28b test)","unit":"number","formula":[{"m":"allocations"},{"m":"commission_realised"},{"op":"/"}]}');
reset role;
-- a sankey without steps fails in that widget only; a 22023 message is still shown as it is
with x as (insert into b2b.dashboards (slug, name, widgets) values ('zz-m28b-bad-sankey', 'Bad sankey',
             '[{"id":"s1","type":"sankey","title":"Flow","metric":"leads","w":6,"h":2},{"id":"k1","type":"kpi","title":"Leads","metric":"leads","w":3,"h":1},
               {"id":"b1","type":"bar","title":"SLA by source","metric":"sla_compliance","dims":["source"],"w":6,"h":2}]') returning id)
  insert into t select 'BS', id::text from x;
do $x$
declare x jsonb; e text;
  f jsonb := jsonb_build_object('routing_mode', '["commission_first"]'::jsonb, 'partner', jsonb_build_array(pg_temp.v('A')));
begin
  begin
    x := b2b.dashboard_render(pg_temp.v('BS')::bigint);
    insert into r values ('widget_error_isolated', x -> 'data' -> 's1' ->> 'error' = 'this widget failed (22004)' and x -> 'data' -> 'k1' ? 'series'
                          and x -> 'data' -> 'b1' ->> 'error' = 'SLA compliance cannot be broken down by source', (x -> 'data' -> 's1')::text || ' ' || (x -> 'data' -> 'b1')::text);
  exception when others then insert into r values ('widget_error_isolated', false, sqlstate || ' ' || sqlerrm);
  end;
  -- dashboard filters: routing_mode (only fact_allocations has it) is dropped, partner (both facts have it) is kept
  begin
    x := b2b.widget_data('{"type":"kpi","metric":"rev_per_alloc_m28","w":3,"h":1}', '30d', f);
    insert into r values ('widget_filters_per_base', jsonb_array_length(x -> 'series') = 1 and x -> 'series' -> 0 -> 'total' ? 'value'
                          and x -> 'series' -> 0 -> 'metric' ->> 'key' = 'rev_per_alloc_m28', (x -> 'series' -> 0 -> 'total')::text);
  exception when others then insert into r values ('widget_filters_per_base', false, sqlerrm);
  end;
  begin
    x := b2b.widget_data('{"type":"kpi","metric":"alloc_per_rev_m28","w":3,"h":1}', '30d', f);
    insert into r values ('widget_filters_every_base', jsonb_array_length(x -> 'series') = 1 and x -> 'series' -> 0 -> 'total' ? 'value', (x -> 'series' -> 0 -> 'total')::text);
  exception when others then insert into r values ('widget_filters_every_base', false, sqlerrm);
  end;
  -- a system metric still gets the filters its fact has
  begin perform b2b.widget_data('{"type":"kpi","metric":"allocations","w":3,"h":1}', '30d', f); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('widget_filters_system_metric', e = 'ran', e);
end $x$;

-- ---------- not for others ----------
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b5","role":"authenticated","aal":"aal2","email":"nobody28b@test.local"}', true);
set local role authenticated;
do $x$ declare e text; begin
  begin perform b2b.metric_alert_set_active(pg_temp.v('AON')::bigint, false); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('non_admin_alert_switch', e = '42501', e);
  begin perform b2b.schedule_set_active(pg_temp.v('SON')::bigint, false); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('non_admin_schedule_switch', e = '42501', e);
end $x$;
reset role;

select name, ok, detail from r order by ok, name;
rollback;
