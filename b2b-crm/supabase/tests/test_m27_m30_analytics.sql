-- M27–M30 on STAGING, rolled back. Needs pending/m30b_fact_views.sql applied (the fixed fact_sla, fact_invoices, fact_sync).
-- Covers: facts (a breach met late stays a breach; drafts are not receivables; discarded sync events are not held and test
-- traffic follows the allocation), the metric layer (breakdowns, filters including '' for the '(none)' bucket, previous
-- period, realised commission and verified enrolments counted by the date they happened, calculated metrics: a formula
-- needs a metric, an empty count or sum base is 0, bases in formula order, only the dimensions every base shares;
-- drill-down including a week bucket; the row limit keeps the latest time buckets and says when rows were cut), the nine
-- default dashboards render, dashboard builder rules, the live SLA list and widget (open SLAs and breaches still owed),
-- metric alerts (a minimum volume, the cooldown) and the alert digest (queued, never sent: admin alerts stay off),
-- scheduled delivery with CSV attachments, reports (tabular, summary, matrix, CSV), Autopilot (applies only a confident,
-- simulated gain; at most N a day), the 7-day review with automatic rollback, the Ask-the-CRM log (cost at the configured
-- prices) and the change simulator. It takes the cron ticks' advisory locks first, so a staging cron run cannot overlap
-- the calls below. Every row must say ok = true.
begin;
-- hold the cron ticks' locks for this transaction so an overlapping staging cron run cannot make the calls below return busy; rollback releases them
select pg_advisory_xact_lock(hashtext('b2b.refresh_facts'));
select pg_advisory_xact_lock(hashtext('b2b.admin_alerts_tick'));
select pg_advisory_xact_lock(hashtext('b2b.ai_autopilot_tick'));
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

-- fixture: two partners; 12 leads (8 WhatsApp in Delhi, 4 website in Karnataka) and 12 allocations in zzm27|PG|Online,
-- all made 2 days ago (inside every 7d and 30d period, which end at now())
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
    update public.student_leads set lead_source = case when i <= 8 then 'whatsapp_direct' else 'website' end, created_at = now() - interval '2 days' where id = v_id;
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
-- a formula needs at least one metric; a metric and a number together still save
do $x$ declare e text; s text; begin
  begin perform b2b.metric_save('{"key":"nums_m27","label":"Numbers","unit":"number","formula":[{"n":1},{"n":2},{"op":"+"}]}'); e := 'saved';
  exception when others then e := sqlerrm; s := sqlstate; end;
  insert into r values ('formula_needs_metric', e = 'use at least one metric' and s = '22023', e || ' / ' || coalesce(s, ''));
  begin e := b2b.metric_save('{"key":"leads_x2_m27","label":"Leads doubled","unit":"count","formula":[{"m":"leads"},{"n":2},{"op":"*"}]}') ->> 'key';
  exception when others then e := sqlerrm; end;
  insert into r values ('formula_metric_and_number_saves', e = 'leads_x2_m27', e);
end $x$;
insert into r select 'drill_rows', (x ->> 'shown')::int = 2 and x ->> 'fact' = 'fact_allocations', x ->> 'shown'
  from (select b2b.metric_drill_admin('{"metric":"duplicates","filters":{"segment":["zzm27|PG|Online"]}}') x) z;
insert into r select 'catalogue', jsonb_array_length(x -> 'metrics') >= 50 and exists (select 1 from jsonb_array_elements(x -> 'metrics') m where m ->> 'key' = 'cpe_per_lead_m27' and (m ->> 'calculated')::boolean), null
  from (select b2b.metric_catalogue() x) z;
reset role;  -- the admin claims stay set; internal functions are called as the owner

-- ---------- fact views, date basis, calculated metrics, null bucket, row limit ----------
-- fixtures for partner A (fixture leads L2, L4, L6 are A's); each check below is its own statement after refresh_facts
-- C18: a breach met late and a check met on time
insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, met_at, status, breached_at)
select a.id, a.lead_id, a.partner_id, 'first_attempt', now() - interval '3 days', now() - interval '2 days', now() - interval '1 day', 'met_late', now() - interval '2 days'
  from b2b.allocations a where a.lead_id = pg_temp.v('L2')::bigint and a.cycle_no = 1;
insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, met_at, status)
select a.id, a.lead_id, a.partner_id, 'first_attempt', now() - interval '3 days', now() - interval '2 days', now() - interval '2 days 1 hour', 'met'
  from b2b.allocations a where a.lead_id = pg_temp.v('L4')::bigint and a.cycle_no = 1;
-- C19: a draft (never counted), an approved invoice 10 days overdue, a paid one with a 40-paise residue
insert into b2b.invoices (partner_id, through_period, status, gst_rate, total_inr)
values (pg_temp.v('A')::bigint, to_char(now(), 'YYYY-MM'), 'draft', 0.18, 118000);
insert into b2b.invoices (partner_id, through_period, status, number, issue_date, due_date, gst_rate, total_inr, approved_at)
values (pg_temp.v('A')::bigint, to_char(now(), 'YYYY-MM'), 'approved', 'M27T-APPROVED', current_date - 20, current_date - 10, 0.18, 50000, now());
insert into b2b.invoices (partner_id, through_period, status, number, issue_date, due_date, gst_rate, total_inr, received_inr, tds_inr, paid_at)
values (pg_temp.v('A')::bigint, to_char(now(), 'YYYY-MM'), 'paid', 'M27T-PAID', current_date - 5, current_date + 25, 0.18, 10000.40, 10000, 0, now());
-- C20 + C67: an enrolment and its commission line, created 45 days ago, verified and realised a minute ago (not now():
-- the period ends at now(), which is fixed for the whole transaction). Not linked to an allocation (cycle 90), so the
-- fixture allocations' outcomes do not change.
with x as (insert into public.enrollments (lead_id, cycle_no, partner_id, status, source_product, enrolled_on, verified_at, created_at)
           values (pg_temp.v('L2')::bigint, 90, pg_temp.v('A')::bigint, 'verified', 'b2b', current_date - 45, now() - interval '1 minute', now() - interval '45 days') returning id)
insert into t select 'E20', id::text from x;
insert into b2b.earnings (enrollment_id, partner_id, lead_id, period, kind, status, net_inr, gst_rate, gst_inr, gross_inr, realised_at, created_at)
values (pg_temp.v('E20')::bigint, pg_temp.v('A')::bigint, pg_temp.v('L2')::bigint, to_char(now() - interval '45 days', 'YYYY-MM'), 'commission', 'realised',
        3000, 0.18, 540, 3540, now() - interval '1 minute', now() - interval '45 days');
-- C65: (1) unmapped on a fixture allocation, (2) unmapped but discarded, (3) an error on a test allocation
with x as (insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, created_at, is_test)
           values (pg_temp.v('L4')::bigint, 91, 'zzm27x|PG|Online', 'partner', pg_temp.v('A')::bigint, 'closed', 'manual', now() - interval '1 day', true) returning id)
insert into t select 'AT', id::text from x;
insert into b2b.partner_events (partner_id, event_id, event_type, allocation_id, lead_id, raw, status, received_at)
select a.partner_id, 'm27-sync-1', 'status', a.id, a.lead_id, '{}', 'held_unmapped', now() - interval '1 hour'
  from b2b.allocations a where a.lead_id = pg_temp.v('L6')::bigint and a.cycle_no = 1;
insert into b2b.partner_events (partner_id, event_id, event_type, raw, status, received_at, discarded_at, discard_reason)
values (pg_temp.v('A')::bigint, 'm27-sync-2', 'status', '{}', 'held_unmapped', now() - interval '1 hour', now(), 'm27 test');
insert into b2b.partner_events (partner_id, event_id, event_type, allocation_id, raw, status, received_at)
values (pg_temp.v('A')::bigint, 'm27-sync-3', 'status', pg_temp.v('AT')::bigint, '{}', 'error', now() - interval '1 hour');
-- C67: one partner-B allocation in the previous 30-day period, so B has a previous-period value
insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, created_at, is_test)
values (pg_temp.v('L1')::bigint, 92, 'zzm27p|PG|Online', 'partner', pg_temp.v('B')::bigint, 'closed', 'manual', now() - interval '40 days', false);
-- C67 / C68: commission realised per allocation
select b2b.metric_save('{"key":"rev_per_alloc_m27","label":"Commission per allocation","unit":"inr","formula":[{"m":"commission_realised"},{"m":"allocations"},{"op":"/"}]}');
select b2b.refresh_facts();

-- C18: a breach met late stays a breach
insert into r select 'sla_breach_met_late', (x -> 'total' ->> 'value')::numeric = 1, (x -> 'total')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'sla_breaches', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))))) x) z;
insert into r select 'fact_sla_breached', count(*) = 2 and bool_and(breached = (status = 'met_late')), string_agg(status || ':' || breached, ', ')
  from b2b.fact_sla where partner_id = pg_temp.v('A')::bigint;
insert into r select 'sla_compliance_half', (x -> 'total' ->> 'value')::numeric = 0.5, (x -> 'total')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'sla_compliance', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))))) x) z;
-- C19: drafts are not receivables; a paid invoice's residue is not outstanding
insert into r select 'invoices_outstanding', (x -> 'total' ->> 'value')::numeric = 50000, (x -> 'total')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'outstanding', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))))) x) z;
insert into r select 'invoices_invoiced', (x -> 'total' ->> 'value')::numeric = 60000.40, (x -> 'total')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'invoiced', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))))) x) z;
-- (the paid invoice has no ageing bucket and outstanding 0: its '(none)' row is 0, so only '1-30' carries money)
insert into r select 'outstanding_by_ageing', (select count(*) = 1 and bool_and(rw -> 'd' ->> 0 = '1-30' and (rw ->> 'value')::numeric = 50000)
                                                 from jsonb_array_elements(x -> 'rows') rw where (rw ->> 'value')::numeric <> 0), (x -> 'rows')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'outstanding', 'dims', '["ageing"]'::jsonb,
                                                 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))))) x) z;
insert into r select 'draft_not_in_facts', count(*) = 2 and bool_and(i.status <> 'draft'), string_agg(i.status, ', ')
  from b2b.fact_invoices f join b2b.invoices i on i.id = f.invoice_id where f.partner_id = pg_temp.v('A')::bigint;
-- C20: realised commission and verified enrolments count in the month they were realised / verified
insert into r select 'realised_verified_date_cols', (select date_col from b2b.metric_definitions where key = 'commission_realised') = 'realised_at'
                     and (select date_col from b2b.metric_definitions where key = 'verified_enrolments') = 'verified_at', null;
insert into r select 'realised_in_realised_month', (x -> 'total' ->> 'value')::numeric = 3000, (x -> 'total')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'commission_realised', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))),
                                                 'from', date_trunc('month', now() - interval '1 minute'), 'to', now(), 'compare', 'none')) x) z;
insert into r select 'realised_not_in_created_month', (x -> 'total' ->> 'value')::numeric = 0, (x -> 'total')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'commission_realised', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))),
                                                 'from', date_trunc('month', now() - interval '45 days'), 'to', date_trunc('month', now() - interval '45 days') + interval '1 month',
                                                 'compare', 'none')) x) z;
insert into r select 'verified_in_verified_month', (x -> 'total' ->> 'value')::numeric = 1, (x -> 'total')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'verified_enrolments', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))),
                                                 'from', date_trunc('month', now() - interval '1 minute'), 'to', now(), 'compare', 'none')) x) z;
insert into r select 'verified_not_in_created_month', (x -> 'total' ->> 'value')::numeric = 0, (x -> 'total')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'verified_enrolments', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))),
                                                 'from', date_trunc('month', now() - interval '45 days'), 'to', date_trunc('month', now() - interval '45 days') + interval '1 month',
                                                 'compare', 'none')) x) z;
-- C65: discarded events are not held; test traffic follows the allocation's flag
insert into r select 'sync_unmapped_not_discarded', (x -> 'total' ->> 'value')::numeric = 1, (x -> 'total')::text
  from (select b2b.metric_run(jsonb_build_object('metric', 'unmapped_events', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))))) x) z;
insert into r select 'sync_events_test_flag', (x1 -> 'total' ->> 'value')::numeric = 2 and (x2 -> 'total' ->> 'value')::numeric = 3,
                     (x1 -> 'total' ->> 'value') || ' / ' || (x2 -> 'total' ->> 'value')
  from (select b2b.metric_run(jsonb_build_object('metric', 'sync_events', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))))) x1,
               b2b.metric_run(jsonb_build_object('metric', 'sync_events', 'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'))), 'include_test', true)) x2) z;
insert into r select 'sync_dead_letter', count(*) filter (where not f.is_test) = 2 and bool_and(f.dead_letter = (e.event_id = 'm27-sync-1')) filter (where not f.is_test)
                     and bool_and(f.is_test = (e.event_id = 'm27-sync-3')), string_agg(e.event_id || ':' || f.dead_letter || ':' || f.is_test, ', ')
  from b2b.fact_sync f join b2b.partner_events e on e.id = f.event_id where f.partner_id = pg_temp.v('A')::bigint;
-- C67: an empty count or sum base is 0, not null (current and previous period)
insert into t select 'q67', b2b.metric_query(jsonb_build_object('metric', 'rev_per_alloc_m27', 'dims', '["partner"]'::jsonb, 'compare', 'previous',
                                                                'filters', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A'), pg_temp.v('B')))))::text;
insert into r select 'calc_empty_base_zero', (select (rw ->> 'value')::numeric from jsonb_array_elements(x -> 'rows') rw where rw -> 'd' ->> 0 = pg_temp.v('B')) = 0
                     and (select (rw ->> 'value')::numeric from jsonb_array_elements(x -> 'rows') rw where rw -> 'd' ->> 0 = pg_temp.v('A')) = 500, (x -> 'rows')::text
  from (select pg_temp.v('q67')::jsonb x) z;
insert into r select 'calc_prev_zero', (select (rw ->> 'prev')::numeric from jsonb_array_elements(x -> 'rows') rw where rw -> 'd' ->> 0 = pg_temp.v('B')) = 0, (x -> 'rows')::text
  from (select pg_temp.v('q67')::jsonb x) z;
-- C68: formula order, shared dimensions, drill into the formula's first base; system metrics unchanged
insert into r select 'calc_bases_formula_order', b2b.metric_bases(d) = '{commission_realised,allocations}'::text[], b2b.metric_bases(d)::text
  from b2b.metric_definitions d where d.key = 'rev_per_alloc_m27';
insert into r select 'calc_catalogue_shared_dims', m -> 'dims' = '["day", "month", "partner", "status", "week"]'::jsonb and not (m -> 'dims') ? 'routing_mode', (m -> 'dims')::text
  from (select b2b.metric_catalogue() x) z, jsonb_array_elements(z.x -> 'metrics') m where m ->> 'key' = 'rev_per_alloc_m27';
insert into r select 'system_catalogue_dims', m -> 'dims' = (select jsonb_agg(q.k order by q.k) from (select jsonb_object_keys(b2b.metric_dimensions() -> 'fact_allocations') k
                                                                                                         union select unnest(array['day', 'week', 'month'])) q)
                     and (m -> 'dims') ? 'routing_mode', (m -> 'dims')::text
  from (select b2b.metric_catalogue() x) z, jsonb_array_elements(z.x -> 'metrics') m where m ->> 'key' = 'allocations';
insert into r select 'calc_drill_first_base', x ->> 'fact' = 'fact_money' and (x ->> 'shown')::int = 1, x ->> 'fact'
  from (select b2b.metric_drill_admin('{"metric":"rev_per_alloc_m27"}') x) z;
-- C84: a '' filter value is the '(none)' bucket (needs C73's backdated leads; they have no utm_source)
insert into r select 'drill_null_bucket', (x ->> 'shown')::int = 12, x ->> 'shown'
  from (select b2b.metric_drill_admin('{"metric":"leads","filters":{"course":["zzm27"],"utm_source":[""]}}') x) z;
insert into r select 'metric_null_filter', (x -> 'total' ->> 'value')::numeric = 12, (x -> 'total')::text
  from (select b2b.metric_query('{"metric":"leads","filters":{"course":["zzm27"],"utm_source":[""]}}') x) z;
-- C85 (optional SQL row): a week bucket drills into the same rows it counts
insert into t select 'qw', b2b.metric_run('{"metric":"allocations","dims":["week"],"filters":{"segment":["zzm27|PG|Online"]},"compare":"none"}')::text;
insert into r select 'week_drill_matches', (b2b.metric_drill_admin(jsonb_build_object('metric', 'allocations', 'filters',
                       jsonb_build_object('segment', '["zzm27|PG|Online"]'::jsonb, 'week', jsonb_build_array(x -> 'rows' -> 0 -> 'd' ->> 0)))) ->> 'shown')::numeric
                     = (x -> 'rows' -> 0 ->> 'value')::numeric, (x -> 'rows' -> 0)::text
  from (select pg_temp.v('qw')::jsonb x) z;
-- C89: metric_run says when it cut rows
insert into r select 'metric_run_truncated', jsonb_array_length(x1 -> 'rows') = 1 and (x1 ->> 'truncated')::boolean and (x1 ->> 'limit')::int = 1
                     and jsonb_array_length(x2 -> 'rows') = 2 and not (x2 ->> 'truncated')::boolean
                     and (x2 -> 'rows' -> 0 ->> 'value')::numeric >= (x2 -> 'rows' -> 1 ->> 'value')::numeric, (x2 -> 'rows')::text
  from (select b2b.metric_run('{"metric":"allocations","dims":["partner"],"filters":{"segment":["zzm27|PG|Online"]},"compare":"none","limit":1}') x1,
               b2b.metric_run('{"metric":"allocations","dims":["partner"],"filters":{"segment":["zzm27|PG|Online"]},"compare":"none","limit":10}') x2) z;

-- C66: the row limit keeps the latest time buckets (10 partner-A allocations in zzm27t|PG|Online, one a day)
do $x$ begin
  for n in 1 .. 10 loop
    insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, created_at, is_test)
    values (pg_temp.v('L6')::bigint, 40 + n, 'zzm27t|PG|Online', 'partner', pg_temp.v('A')::bigint, 'closed', 'manual', now() - make_interval(days => n), false);
  end loop;
end $x$;
select b2b.refresh_facts();
insert into t select 'q66a', b2b.metric_run('{"metric":"allocations","dims":["day"],"filters":{"segment":["zzm27t|PG|Online"]},"limit":5}')::text;
insert into t select 'q66b', b2b.metric_run('{"metric":"allocations","dims":["partner","day"],"filters":{"segment":["zzm27t|PG|Online"]},"limit":5}')::text;
insert into t select 'q66c', b2b.metric_run('{"metric":"allocations","dims":["day"],"filters":{"segment":["zzm27t|PG|Online"]}}')::text;
insert into r select 'time_series_keeps_latest', jsonb_array_length(x -> 'rows') = 5 and (x ->> 'limit')::int = 5 and (x ->> 'truncated')::boolean
                     and (select array_agg(q.rw -> 'd' ->> 0 order by q.o) from jsonb_array_elements(x -> 'rows') with ordinality q(rw, o))
                         = (select array_agg(((now() - make_interval(days => n)) at time zone 'Asia/Kolkata')::date::text order by n desc) from generate_series(1, 5) n),
                     (x -> 'rows')::text
  from (select pg_temp.v('q66a')::jsonb x) z;
insert into r select 'time_series_second_dim', jsonb_array_length(x -> 'rows') = 5 and (x ->> 'truncated')::boolean
                     and (select array_agg(q.rw -> 'd' ->> 1 order by q.o) from jsonb_array_elements(x -> 'rows') with ordinality q(rw, o))
                         = (select array_agg(((now() - make_interval(days => n)) at time zone 'Asia/Kolkata')::date::text order by n desc) from generate_series(1, 5) n),
                     (x -> 'rows')::text
  from (select pg_temp.v('q66b')::jsonb x) z;
insert into r select 'time_series_default_limit', jsonb_array_length(x -> 'rows') = 10 and not (x ->> 'truncated')::boolean and (x ->> 'limit')::int = 100
                     and x -> 'rows' -> 9 -> 'd' ->> 0 = ((now() - interval '1 day') at time zone 'Asia/Kolkata')::date::text, (x -> 'rows' -> 9)::text
  from (select pg_temp.v('q66c')::jsonb x) z;

-- ---------- dashboards ----------
insert into r select 'defaults_valid', bool_and(jsonb_array_length(b2b.dashboard_check_widgets(d.widgets)) = jsonb_array_length(d.widgets)) and count(*) = 9, count(*)::text
  from b2b.dashboards d where d.is_default;
insert into r select 'defaults_render', not exists (select 1 from b2b.dashboards d, jsonb_each(b2b.dashboard_data(d.id) -> 'data') w where d.is_default and w.value ? 'error'),
                     (select string_agg(d.slug || ':' || w.key || ':' || (w.value ->> 'error'), '; ') from b2b.dashboards d, jsonb_each(b2b.dashboard_data(d.id) -> 'data') w where d.is_default and w.value ? 'error');
insert into r select 'command_center_kpi', (x -> 'data' -> 'k2' -> 'series' -> 0 -> 'total' ->> 'value') is not null and jsonb_array_length(x -> 'data' -> 's1' -> 'series') = 2, null
  from (select b2b.dashboard_data((select id from b2b.dashboards where slug = 'command-center'), '7d', '{}') x) z;
-- C72: SLA checks of partner A, one per allocation (segment zzm27s|PG|Online, so the zzm27|PG|Online counts are untouched),
-- on a lead of their own (phone 919876506190, not a test lead). Expected open list: (2), (6), (1) by due_at.
--   (1) first_attempt pending, due in 1 h             (2) first_attempt breached 1 h ago
--   (3) first_attempt breached, duplicate allocation   (4) status_update breached 40 days ago (past the 30-day re-check)
--   (5) status_update breached, the lead is 'lost' with this allocation (sla_tick's void rule before Addendum 3)
--   (6) enrollment_proof breached 30 min ago on a closed allocation
do $x$
declare v_l bigint; v_a bigint; v_c bigint; i int;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', '919876506190', 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Analytics SLA', 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online', 'state', 'Delhi')));
  select id into v_l from public.student_leads where whatsapp_number = '919876506190';
  insert into t values ('LS', v_l::text);
  for i in 1 .. 6 loop
    insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, cpe_net_inr, accepted_at, created_at, is_test)
    values (v_l, 40 + i, 'zzm27s|PG|Online', 'partner', pg_temp.v('A')::bigint, case i when 3 then 'duplicate' when 6 then 'closed' else 'accepted' end,
            'commission_first', 20000, now() - interval '3 days', now() - interval '3 days', false)
    returning id into v_a;
    insert into b2b.sla_checks (allocation_id, lead_id, partner_id, sla, started_at, due_at, status, breached_at, is_test)
    values (v_a, v_l, pg_temp.v('A')::bigint, case when i in (4, 5) then 'status_update' when i = 6 then 'enrollment_proof' else 'first_attempt' end,
            now() - interval '41 days',
            case i when 1 then now() + interval '1 hour' when 2 then now() - interval '1 hour' when 3 then now() - interval '2 hours'
                   when 4 then now() - interval '40 days' when 5 then now() - interval '3 hours' else now() - interval '30 minutes' end,
            case when i = 1 then 'pending' else 'breached' end, case when i > 1 then now() end, false)
    returning id into v_c;
    insert into t values ('SLA' || i, v_c::text);
    if i = 5 then
      update public.student_leads set allocation_id = v_a, destination_type = 'partner', partner_id = pg_temp.v('A')::bigint, stage = 'lost' where id = v_l;
    end if;
  end loop;
end $x$;
-- C72 (2): the SLA widget lists open SLAs and breaches still owed, with their status
insert into r select 'widget_sla_open_and_breached',
                     (select array_agg((rw ->> 'id')::bigint order by o) from jsonb_array_elements(x -> 'rows') with ordinality q(rw, o))
                       = array[pg_temp.v('SLA2')::bigint, pg_temp.v('SLA6')::bigint, pg_temp.v('SLA1')::bigint]
                     and (select array_agg(rw ->> 'status' order by o) from jsonb_array_elements(x -> 'rows') with ordinality q(rw, o)) = array['breached', 'breached', 'pending'],
                     (x -> 'rows')::text
  from (select b2b.widget_data('{"type":"sla_timers","w":12,"h":2}', '30d', jsonb_build_object('partner', jsonb_build_array(pg_temp.v('A')))) x) z;
-- C72 (1): the same list from sla_timers, with the partner's name and the allocation's reference
insert into r select 'sla_timers_open_and_breached',
                     (select array_agg((rw ->> 'id')::bigint order by o) from jsonb_array_elements(x) with ordinality q(rw, o))
                       = array[pg_temp.v('SLA2')::bigint, pg_temp.v('SLA6')::bigint, pg_temp.v('SLA1')::bigint]
                     and (select array_agg(rw ->> 'status' order by o) from jsonb_array_elements(x) with ordinality q(rw, o)) = array['breached', 'breached', 'pending']
                     and (select bool_and(rw ->> 'partner' = 'M27 Alpha' and rw ? 'reference') from jsonb_array_elements(x) rw),
                     x::text
  from (select b2b.sla_timers(pg_temp.v('A')::bigint, 20) x) z;
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
-- C77 (b): a rate alert with a minimum volume of routed leads (only 12 exist, so it is checked but does not fire)
insert into t select 'AL2', (b2b.metric_alert_save('{"name":"Duplicates high, enough volume","metric":"duplicate_rate","filters":{"segment":["zzm27|PG|Online"]},"window_hours":72,"op":">","threshold":0.1,"min_volume":100,"volume_metric":"allocations","channels":["email"]}') ->> 'id');
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
-- cooldown: only the test's alert is checked again (every other alert was checked at this transaction's now() by the tick);
-- it still breaches, so the tick returns 0 only because it fired within cooldown_hours
insert into r select 'cooldown', (select count(*) from b2b.admin_messages where kind = 'metric_alert' and ref ->> 'alert_id' = pg_temp.v('AL')) = 1, null;
update b2b.metric_alerts set last_checked_at = now() - interval '10 minutes' where id = pg_temp.v('AL')::bigint;
insert into r select 'cooldown_holds', b2b.metric_alerts_tick() = 0, (select last_fired_at::text from b2b.metric_alerts where id = pg_temp.v('AL')::bigint);
-- C77 (b): AL2 was checked by the admin_alerts_tick above and did not fire (12 routed leads < 100)
insert into r select 'alert_min_volume_respected', a.last_checked_at is not null and a.last_fired_at is null, coalesce(a.last_value::text, 'null')
  from b2b.metric_alerts a where a.id = pg_temp.v('AL2')::bigint;
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
-- C89: the set-based summary pivot gives the same rows (values in metric order) and says whether values were cut
insert into r select 'report_summary_same_shape', x -> 'truncated' = 'false'::jsonb and jsonb_array_length(x -> 'rows') = 2
                     and (select rw -> 'values' from jsonb_array_elements(x -> 'rows') rw where rw -> 'd' ->> 0 = pg_temp.v('A')) = '[6, 0]'::jsonb
                     and (select rw -> 'values' from jsonb_array_elements(x -> 'rows') rw where rw -> 'd' ->> 0 = pg_temp.v('B')) = '[6, 0.3333]'::jsonb, (x -> 'rows')::text
  from (select b2b.report_run('{"kind":"summary","definition":{"metrics":["allocations","duplicate_rate"],"dims":["partner"],"filters":{"segment":["zzm27|PG|Online"]},"period":"7d"}}') x) z;
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
-- (checked after the role is reset: a check in the same statement as the call would not see the new run)
insert into t select 'ask', b2b.ai_ask_log('{"question":"How many leads this week?","answer":"12 leads.","model":"claude-sonnet-5-5","usage":{"in":10000,"out":500},"validation":{"ok":true},"sources":[{"metric":"leads"}]}')::text;
do $x$ declare e text; begin
  begin perform b2b.simulate_change('{"lever":"exploration_share","segment":"zzm27|PG|Online","value":0.9}', 30); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r values ('simulate_change_bounds', e = 'exploration share is 0 to 50%', e);
end $x$;
insert into r select 'simulate_change_runs', (x ->> 'simulated')::boolean and x ? 'decisions', x::text
  from (select b2b.simulate_change('{"lever":"exploration_share","segment":"zzm27|PG|Online","value":0.3}', 30) x) z;
reset role;
-- the cost at the configured Sonnet 5.5 prices (0.0250 at $2 in / $10 out per million tokens)
insert into r select 'ask_logged', (select kind = 'ask' and status = 'done'
                                            and cost_usd = round((10000 * (pr ->> 'in')::numeric + 500 * (pr ->> 'out')::numeric) / 1000000.0, 4)
                                       from b2b.ai_runs where id = (x ->> 'id')::bigint)
                     and jsonb_array_length(b2b.ai_ask_history(5)) >= 1, x::text || ' at ' || coalesce(pr::text, 'no price')
  from (select pg_temp.v('ask')::jsonb x, (select value -> 'prices_per_mtok' -> 'claude-sonnet-5-5' from b2b.settings where key = 'ai') pr) z;
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
