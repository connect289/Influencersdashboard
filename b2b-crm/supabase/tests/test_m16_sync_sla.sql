-- A3 fixture: the consent wording the test leads carry
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at) values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now()) on conflict (version) do nothing;
-- M16 status/activity sync, SLAs and reconciliation on STAGING, rolled back. Two leads accepted by partner e2e-down
-- (id 20, Mon–Fri 10–19, Sat 10–17); signed events go through b2b.partner_event_ingest; the SLA clock is driven by
-- calling b2b.sla_tick(). Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;

create function pg_temp.send(body jsonb) returns jsonb language plpgsql as $f$
declare ts text := floor(extract(epoch from now()))::bigint::text; sec text;
begin
  sec := b2b.partner_secret((select inbound_secret_id from b2b.partners where slug = 'e2e-down'));
  return b2b.partner_event_ingest('e2e-down', body::text, ts,
    'sha256=' || encode(extensions.hmac(convert_to(ts || '.' || body::text, 'UTF8'), convert_to(sec, 'UTF8'), 'sha256'), 'hex'));
end $f$;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;

-- ---------- working time ----------
update b2b.partners set holidays = '{2026-10-12}' where id = 20;
insert into r values
  ('deadline_skips_sunday_and_holiday', b2b.working_deadline(20, '2026-10-10 18:00+05:30', 120) = '2026-10-13 12:00+05:30',
   b2b.working_deadline(20, '2026-10-10 18:00+05:30', 120)::text),
  ('deadline_spans_days', b2b.working_deadline(20, '2026-10-09 18:00+05:30', 120) = '2026-10-10 11:00+05:30',
   b2b.working_deadline(20, '2026-10-09 18:00+05:30', 120)::text),
  ('working_day_is_next_close', b2b.working_days_deadline(20, '2026-10-09 15:00+05:30', 1) = '2026-10-10 17:00+05:30',
   b2b.working_days_deadline(20, '2026-10-09 15:00+05:30', 1)::text),
  ('working_minutes', b2b.working_minutes_between(20, '2026-10-09 18:00+05:30', '2026-10-10 11:00+05:30') = 120,
   b2b.working_minutes_between(20, '2026-10-09 18:00+05:30', '2026-10-10 11:00+05:30')::text);
update b2b.partners set holidays = '{}' where id = 20;

-- ---------- two leads with e2e-down: A pushed Mon 21 Sep 10:00, B pushed Sat 3 Oct 10:00 ----------
do $x$
declare v_id bigint; a b2b.allocations; i int; v_phone text; v_at timestamptz;
begin
  perform set_config('b2b.actor', 'engine', true);
  update b2b.settings set value = jsonb_set(value, '{exploration_share}', '0') where key = 'engine';
  for i in 1 .. 2 loop
    v_phone := '91987650310' || i;
    v_at := case i when 1 then '2026-09-21 10:00+05:30'::timestamptz else '2026-10-03 10:00+05:30'::timestamptz end;
    perform public.lead_intake(jsonb_build_object('phone', v_phone, 'source_system', 'crm', 'event_type', 'lead.created',
      'lead', jsonb_build_object('full_name', 'Sync ' || i, 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                                 'state', 'Delhi', 'source', 'whatsapp_direct', 'classification', 'WARM', 'consent_partner_share_at', now(), 'consent_text_version', 'test-partner-share:v1')));
    select id into v_id from public.student_leads where whatsapp_number = v_phone;
    perform b2b.route_decide(v_id, true, 'm16', 'auto');
    select * into a from b2b.allocations where lead_id = v_id and destination_type = 'partner' order by id desc limit 1;
    update b2b.allocations set status = 'pushing' where id = a.id;
    perform b2b.apply_created(a.id, 'REC-M16-' || i);
    perform b2b.accept_allocation(a.id);
    update b2b.allocations set pushed_at = v_at where id = a.id;
    insert into t values ('lead' || i, v_id::text), ('alloc' || i, a.id::text), ('ref' || i, a.reference), ('partner' || i, a.partner_id::text);
  end loop;
end $x$;
insert into r select 'leads_with_partner', pg_temp.v('partner1') = '20' and pg_temp.v('partner2') = '20', pg_temp.v('partner1') || ',' || pg_temp.v('partner2');

-- ---------- SLA clocks open, then breach with no activity ----------
select b2b.sla_tick();
insert into r select 'clocks_open', count(*) = 4
    and max(due_at) filter (where sla = 'first_attempt') = '2026-09-21 12:00+05:30'
    and max(due_at) filter (where sla = 'first_connect') = '2026-09-22 19:00+05:30'
    and max(due_at) filter (where sla = 'counselling_outcome') = '2026-09-26 17:00+05:30'
    and max(due_at) filter (where sla = 'status_update') = '2026-09-28 10:00+05:30',
  string_agg(sla || '=' || due_at, ', ')
  from b2b.sla_checks where allocation_id = pg_temp.v('alloc1')::bigint;
insert into r select 'breached_without_activity', count(*) filter (where status = 'breached') = 4, string_agg(sla || ':' || status, ', ')
  from b2b.sla_checks where allocation_id = pg_temp.v('alloc1')::bigint;
insert into r select 'breach_alert_and_stale',
    exists (select 1 from b2b.events where type = 'alert.sla_breach' and allocation_id = pg_temp.v('alloc1')::bigint)
    and exists (select 1 from b2b.events where type = 'lead.stale' and allocation_id = pg_temp.v('alloc1')::bigint)
    and (select partner_stale_at is not null from public.student_leads where id = pg_temp.v('lead1')::bigint), null;

-- ---------- a connected call (standard "contacted" event) ----------
insert into t select 'c1', pg_temp.send(jsonb_build_object('event_id', 'm16-1', 'type', 'contacted', 'reference', pg_temp.v('ref1'),
  'occurred_at', '2026-09-21T11:00:00+05:30',
  'data', jsonb_build_object('connected', true, 'duration_sec', 95, 'direction', 'outbound', 'counsellor_name', 'Priya')))::text;
insert into r select 'activity_row', x.kind = 'call' and x.outcome = 'connected' and x.direction = 'outbound' and x.duration_sec = 95
    and x.counsellor_name = 'Priya' and x.occurred_at = '2026-09-21 11:00+05:30' and x.lead_id = pg_temp.v('lead1')::bigint,
  row_to_json(x)::text
  from b2b.partner_activities x join b2b.partner_events e on e.id = x.partner_event_id where e.event_id = 'm16-1';
insert into r select 'rolled_up_and_unflagged', l.last_activity_at >= '2026-09-21 11:00+05:30' and l.partner_stale_at is null
    and l.first_contacted_at = '2026-09-21 11:00+05:30' and l.stage = 'contacted',
  l.last_activity_at || ' ' || l.stage from public.student_leads l where l.id = pg_temp.v('lead1')::bigint;
insert into t select 'c1b', pg_temp.send(jsonb_build_object('event_id', 'm16-1', 'type', 'contacted', 'reference', pg_temp.v('ref1'),
  'data', jsonb_build_object('connected', true)))::text;
insert into r select 'idempotent', pg_temp.v('c1b')::jsonb ->> 'result' = 'already received'
    and (select count(*) from b2b.partner_activities where allocation_id = pg_temp.v('alloc1')::bigint) = 1, pg_temp.v('c1b');

select b2b.sla_tick();
insert into r select 'met_after_late_report',
    max(status) filter (where sla = 'first_attempt') = 'met' and max(met_at) filter (where sla = 'first_attempt') = '2026-09-21 11:00+05:30'
    and max(status) filter (where sla = 'first_connect') = 'met'
    and max(status) filter (where sla = 'counselling_outcome') = 'breached'
    and count(*) filter (where sla = 'status_update' and status = 'met_late') = 1
    and count(*) filter (where sla = 'status_update' and status = 'pending') = 1,
  string_agg(sla || ':' || status, ', ' order by id)
  from b2b.sla_checks where allocation_id = pg_temp.v('alloc1')::bigint;

-- ---------- a mapping, then mapped activity, held activity, stage and fields ----------
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000b6', 'sync-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000b6', 'sync-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000b7', 'not-admin@test.local', 'authenticated', 'authenticated');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b6","role":"authenticated","aal":"aal2","email":"sync-admin@test.local"}', true);
do $x$
declare d bigint;
begin
  d := b2b.mapping_draft_start(20);
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Attempted', 'stage', 'contacted'));
  perform b2b.mapping_rule_save('status', jsonb_build_object('profile_id', d, 'partner_stage', 'Admission', 'stage', 'enrolled'));
  perform b2b.mapping_rule_save('activity', jsonb_build_object('profile_id', d, 'partner_type', 'Call Log', 'partner_outcome', 'Connected', 'kind', 'call', 'outcome', 'connected'));
  perform b2b.mapping_rule_save('field', jsonb_build_object('profile_id', d, 'partner_field', 'Enrollment No', 'canonical_key', 'enrollment_id', 'direction', 'in'));
  perform b2b.mapping_publish(d, 'm16 test');
end $x$;
reset role;

select pg_temp.send(jsonb_build_object('event_id', 'm16-2', 'type', 'activity', 'reference', pg_temp.v('ref1'), 'occurred_at', '2026-09-22T15:00:00+05:30',
  'data', jsonb_build_object('type', 'Call Log', 'outcome', 'Connected', 'duration', '300', 'direction', 'incoming', 'counsellor_name', 'Priya')));
insert into r select 'mapped_activity_row', x.kind = 'call' and x.outcome = 'connected' and x.direction = 'inbound' and x.duration_sec = 300
    and x.mapped -> 'activity' ->> 'kind' = 'call' and coalesce(jsonb_array_length(x.mapped -> 'unmapped'), 0) = 0, row_to_json(x)::text
  from b2b.partner_activities x join b2b.partner_events e on e.id = x.partner_event_id where e.event_id = 'm16-2';

select pg_temp.send(jsonb_build_object('event_id', 'm16-3', 'type', 'activity', 'reference', pg_temp.v('ref1'), 'data', jsonb_build_object('type', 'WhatsApp Chat')));
select pg_temp.send(jsonb_build_object('event_id', 'm16-4', 'type', 'stage', 'reference', 'EDW-999999999', 'data', jsonb_build_object('stage', 'Attempted')));

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b6","role":"authenticated","aal":"aal2","email":"sync-admin@test.local"}', true);
do $x$
declare x jsonb; e text; v_held bigint := (select id from b2b.partner_events where event_id = 'm16-3' and partner_id = 20);
begin
  x := b2b.partner_sync(20);
  insert into r values ('dead_letters_listed', exists (select 1 from jsonb_array_elements(x -> 'dead_letters') d where (d ->> 'id')::bigint = v_held)
                          and exists (select 1 from jsonb_array_elements(x -> 'dead_letters') d where d ->> 'event_id' = 'm16-4' and d ->> 'status' = 'error'), null);
  x := b2b.partner_event_retry(v_held);
  insert into r values ('retry_still_held', x ->> 'status' = 'held_unmapped', x::text);
  begin perform b2b.partner_event_discard(v_held, 'x'); e := 'discarded'; exception when others then e := sqlerrm; end;
  insert into r values ('discard_needs_reason', e = 'a reason is required', e);
  perform b2b.partner_event_discard(v_held, 'not a sales activity');
  begin perform b2b.partner_event_retry(v_held); e := 'retried'; exception when others then e := sqlerrm; end;
  insert into r values ('discarded_not_retried', e like 'only a failed or held event%', e);
  x := b2b.partner_sync(20);
  insert into r values ('discarded_leaves_list', not exists (select 1 from jsonb_array_elements(x -> 'dead_letters') d where (d ->> 'id')::bigint = v_held)
                          and (x -> 'health' ->> 'events_7d')::int >= 4 and x -> 'scorecard' is not null and jsonb_array_length(x -> 'health' -> 'daily') = 7,
                        x -> 'health' ->> 'events_7d');
end $x$;
reset role;
insert into r select 'discard_kept_and_logged', e.discarded_at is not null and e.discard_reason = 'not a sales activity'
    and exists (select 1 from b2b.events v where v.type = 'partner.event_discarded' and (v.payload ->> 'partner_event_id')::bigint = e.id), e.status
  from b2b.partner_events e where e.event_id = 'm16-3' and e.partner_id = 20;
insert into r select 'reprocess_skips_discarded', (b2b.mapping_reprocess(20) ->> 'reprocessed')::int >= 0
    and (select discarded_at is not null and status = 'held_unmapped' from b2b.partner_events where event_id = 'm16-3' and partner_id = 20), null;

select pg_temp.send(jsonb_build_object('event_id', 'm16-5', 'type', 'stage', 'reference', pg_temp.v('ref1'), 'occurred_at', '2026-09-30T12:00:00+05:30',
  'data', jsonb_build_object('stage', 'Admission')));
insert into r select 'stage_change_row', l.stage = 'enrolled' and x.kind = 'stage_change' and x.outcome = 'enrolled', l.stage || ' ' || coalesce(x.outcome, '-')
  from public.student_leads l, b2b.partner_activities x join b2b.partner_events e on e.id = x.partner_event_id
 where l.id = pg_temp.v('lead1')::bigint and e.event_id = 'm16-5';
select b2b.sla_tick();
insert into r select 'outcome_late_and_proof_due',
    max(status) filter (where sla = 'counselling_outcome') = 'met_late'
    and max(status) filter (where sla = 'enrollment_proof') = 'pending'
    and max(due_at) filter (where sla = 'enrollment_proof') = '2026-10-07 12:00+05:30'
    and count(*) filter (where sla = 'status_update' and status = 'pending') = 0
    and count(*) filter (where sla = 'status_update' and status = 'void') = 1,
  string_agg(sla || ':' || status, ', ' order by id)
  from b2b.sla_checks where allocation_id = pg_temp.v('alloc1')::bigint;
select pg_temp.send(jsonb_build_object('event_id', 'm16-6', 'type', 'update', 'reference', pg_temp.v('ref1'), 'data', jsonb_build_object('fields', jsonb_build_object('Enrollment No', 'ENR-9'))));
select b2b.sla_tick();
insert into r select 'proof_met', status = 'met', status from b2b.sla_checks where allocation_id = pg_temp.v('alloc1')::bigint and sla = 'enrollment_proof';
insert into r select 'b_breached_first_attempt', status = 'breached' and due_at = '2026-10-03 12:00+05:30', status || ' ' || due_at
  from b2b.sla_checks where allocation_id = pg_temp.v('alloc2')::bigint and sla = 'first_attempt';

-- ---------- reconciliation ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b6","role":"authenticated","aal":"aal2","email":"sync-admin@test.local"}', true);
do $x$
declare x jsonb; e text; v_ev bigint := (select id from b2b.partner_events where event_id = 'm16-4' and partner_id = 20); v_mm bigint;
begin
  x := b2b.reconcile_partner_run(20, null);
  insert into r values ('unknown_record_item', exists (select 1 from b2b.reconciliation_items where partner_id = 20 and kind = 'unknown_record'
                                                       and item_key = v_ev::text and status = 'open'), x::text);
  x := b2b.reconcile_partner_run(20, jsonb_build_array(jsonb_build_object('reference', pg_temp.v('ref1'), 'stage', 'Admission'),
                                                       jsonb_build_object('record_id', 'ZZZ-1', 'stage', 'Open')));
  insert into r values ('export_items',
    exists (select 1 from b2b.reconciliation_items where partner_id = 20 and kind = 'missing_at_eduwit' and item_key = 'ZZZ-1' and status = 'open')
    and exists (select 1 from b2b.reconciliation_items where partner_id = 20 and kind = 'missing_at_partner' and item_key = pg_temp.v('alloc2') and status = 'open')
    and not exists (select 1 from b2b.reconciliation_items where partner_id = 20 and kind = 'missing_at_partner' and item_key = pg_temp.v('alloc1'))
    and not exists (select 1 from b2b.reconciliation_items where partner_id = 20 and kind = 'status_mismatch' and item_key = pg_temp.v('alloc1'))
    and (x ->> 'export_rows')::int = 2, x::text);
  x := b2b.reconcile_partner_run(20, jsonb_build_array(jsonb_build_object('reference', pg_temp.v('ref1'), 'stage', 'Admission'),
                                                       jsonb_build_object('reference', pg_temp.v('ref2'), 'stage', 'Attempted')));
  select id into v_mm from b2b.reconciliation_items where partner_id = 20 and kind = 'status_mismatch' and item_key = pg_temp.v('alloc2') and status = 'open';
  insert into r values ('auto_resolve_and_mismatch',
    (select status from b2b.reconciliation_items where partner_id = 20 and kind = 'missing_at_eduwit' and item_key = 'ZZZ-1' order by id desc limit 1) = 'resolved'
    and (select status from b2b.reconciliation_items where partner_id = 20 and kind = 'missing_at_partner' and item_key = pg_temp.v('alloc2') order by id desc limit 1) = 'resolved'
    and v_mm is not null
    and (select detail ->> 'export_maps_to' from b2b.reconciliation_items where id = v_mm) = 'contacted', x::text);
  begin perform b2b.reconciliation_resolve(v_mm, 'dismissed', ''); e := 'closed'; exception when others then e := sqlerrm; end;
  insert into r values ('resolve_needs_note', e = 'a note is required', e);
  perform b2b.reconciliation_resolve(v_mm, 'dismissed', 'partner lags a day');
  insert into r values ('item_dismissed', (select status from b2b.reconciliation_items where id = v_mm) = 'dismissed', null);
  x := b2b.lead_partner_sync(pg_temp.v('lead1')::bigint);
  insert into r values ('lead_tab', jsonb_array_length(x -> 'activities') = 3 and jsonb_array_length(x -> 'slas') >= 5
                          and jsonb_array_length(x -> 'events') >= 5 and x -> 'activities' -> 0 ->> 'kind' = 'stage_change', left(x::text, 300));
end $x$;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b7","role":"authenticated","aal":"aal2","email":"not-admin@test.local"}', true);
do $x$
declare e text;
begin
  begin perform b2b.partner_sync(20); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r values ('non_admin_denied', e = 'not allowed', e);
end $x$;
reset role;
insert into r select 'reconcile_all_runs', (b2b.reconcile_all() ->> 'partners')::int >= 1, null;
insert into r select 'reconcile_alert', exists (select 1 from b2b.events where type = 'alert.reconciliation_items' and partner_id = 20), null;

select name, ok, detail from r order by ok, name;
rollback;
