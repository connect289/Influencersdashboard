-- M32 Addendum 4 (the B2C CRM link, final shape) on STAGING with the e2e partners (20, 21, 22) and their offers, rolled
-- back. The ten tests of Addendum 4 §10, in order: real time only (1), the 15-minute batch without echoes (2),
-- occurred_at and contact roll-ups (3), the Eduwit stage fields (4), marketing consent and per-channel opt-out (5),
-- contacts in lookup and duplicate detection (6), the holder of a partner-held student (7), partner history (8), the
-- catalog schema and the b2c_app role (9), contract version 4 and the schema (10). Every row must say ok = true.
begin;
select pg_advisory_xact_lock(hashtext('b2b.b2c_sync_tick'));
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$
  insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000d4","role":"authenticated","aal":"aal2","email":"m32-admin@test.local"}', true)
$f$;
create function pg_temp.upserts(p_lead bigint) returns int language sql as $f$
  select count(*)::int from b2b.integration_outbox o where o.event_type = 'b2c.lead_upserted' and (o.payload ->> 'lead_id')::bigint = p_lead $f$;
-- a signed B2C CRM event
create function pg_temp.b2c(p_body jsonb) returns jsonb language plpgsql as $f$
declare ts text := extract(epoch from now())::bigint::text; sec text := 'whsec_m32_test_secret_000000000000000000000000000000';
begin
  return b2b.b2ccrm_event_ingest(p_body::text, ts, 'sha256=' || encode(extensions.hmac(convert_to(ts || '.' || p_body::text, 'UTF8'), convert_to(sec, 'UTF8'), 'sha256'), 'hex'));
end $f$;
-- a statement run as another role; the error text, or 'ok'
create function pg_temp.as_role(p_role text, p_sql text) returns text language plpgsql as $f$
declare e text := 'ok';
begin
  execute format('set local role %I', p_role);
  begin execute p_sql; exception when others then e := sqlerrm; end;
  execute 'reset role';
  return e;
end $f$;
-- a lead the B2C CRM holds (sales lane)
create function pg_temp.held(p_phone text, p_name text) returns bigint language plpgsql as $f$
declare v_id bigint; a_id bigint;
begin
  v_id := (b2b.intake_lead(jsonb_build_object('full_name', p_name, 'phone', p_phone, 'email', lower(replace(p_name, ' ', '.')) || '@example.com', 'course', 'MBA'),
           jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id')::bigint;
  insert into b2b.allocations (lead_id, cycle_no, destination_type, b2c_lane, status, mode, reason)
  values (v_id, 1, 'in_house', 'sales', 'handed_off', 'fallback', 'b2c_created') returning id into a_id;
  update public.student_leads set destination_type = 'in_house', allocation_id = a_id, allocated_at = now(), allocation_reason = 'b2c_created' where id = v_id;
  return v_id;
end $f$;

insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000d4', 'm32-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000d4', 'm32-admin@test.local');
insert into b2b.api_keys (name, scopes, key_prefix, key_hash)
values ('m32 b2c', '{b2c}', 'eb2b_m32test', encode(extensions.digest('eb2b_m32test_key_0001', 'sha256'), 'hex'));
do $x$
declare v_secret uuid := vault.create_secret('whsec_m32_test_secret_000000000000000000000000000000', 'b2b_m32_test_' || gen_random_uuid(), 'm32 test');
begin
  update b2b.webhook_endpoints set url = 'https://b2c.example.test/hooks/b2b', events = '{b2c.*,b2b.*}', active = true, secret_id = v_secret where consumer = 'b2c_crm';
  if not found then
    insert into b2b.webhook_endpoints (name, consumer, url, events, active, secret_id) values ('B2C CRM (m32 test)', 'b2c_crm', 'https://b2c.example.test/hooks/b2b', '{b2c.*,b2b.*}', true, v_secret);
  end if;
end $x$;

-- ======================================================================================================================
-- 1. Real time only: a Witty update to a B2C-held test lead is queued for the B2C endpoint at once; batched is refused
-- ======================================================================================================================
select pg_temp.set('W', pg_temp.held('910000320001', 'Witty Held')::text);
select b2b.b2c_sync_lead(pg_temp.v('W')::bigint);
update b2b.integration_outbox set status = 'delivered', delivered_at = now() where status = 'pending' and event_type = 'b2c.lead_upserted';
select public.lead_intake(jsonb_build_object('phone', '910000320001', 'source_system', 'witty', 'event_type', 'lead.updated', 'lead', jsonb_build_object('city', 'Indore')));
update b2b.b2c_link_state set value = jsonb_build_object('at', now() - interval '1 minute') where key = 'cursor';
select b2b.b2c_sync_tick();
-- queued and handed to the sender in the same moment (outbox_kick), not held for a batch
insert into r select 't1_witty_change_queued_now', count(*) = 1 and bool_and(o.payload -> 'data' ->> 'origin' is null and (o.payload ->> 'contract_version')::int = 4
                       and o.created_at = now() and o.status in ('pending', 'sending', 'delivered')),
                     string_agg(left(o.payload::text, 160), ' | ')
  from b2b.integration_outbox o
 where o.event_type = 'b2c.lead_upserted' and (o.payload ->> 'lead_id')::bigint = pg_temp.v('W')::bigint
   and o.payload -> 'data' -> 'record' -> 'student' ->> 'city' = 'Indore';
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; begin
  begin perform b2b.b2c_link_settings_save('{"delivery":"batched"}', 'm32 test: try batches'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('t1_batched_refused', e like 'the B2C CRM needs real-time delivery (Addendum 4)%', e);
end $x$;
reset role;
insert into r select 't1_cfg_realtime', b2b.b2c_link_cfg() ->> 'delivery' = 'realtime', null;

-- ======================================================================================================================
-- 2. A B2C batch of 150 updates and 300 activities: applied, no b2c.lead_upserted echo, all in the change feed
-- ======================================================================================================================
create temp table bl (n int primary key, lead_id bigint);
insert into bl select g, pg_temp.held('9100003' || lpad(g::text, 5, '0'), 'Batch Lead ' || g) from generate_series(1, 150) g;
select b2b.b2c_sync_lead(lead_id) from bl;
update b2b.integration_outbox set status = 'delivered', delivered_at = now() where status = 'pending' and event_type = 'b2c.lead_upserted';
select pg_temp.set('seq_before', (select max(seq) from b2b.b2c_sync)::text);
create temp table items (n int primary key, item jsonb);
insert into items
select row_number() over (order by k, n), it from (
  select 1 k, b.n, jsonb_build_object('op', 'update', 'lead_id', b.lead_id, 'request_id', 'm32-u-' || b.n, 'occurred_at', now() - interval '12 minutes',
                                      'set', jsonb_build_object('b2c_stage', 'Program Details Explained', 'sub_stage', 'batch ' || b.n)) it from bl b
  union all
  select 2, b.n * 10 + x, jsonb_build_object('op', 'activity', 'lead_id', b.lead_id, 'request_id', 'm32-a-' || b.n || '-' || x, 'kind', 'call',
                                             'at', now() - make_interval(mins => 14 - x), 'outcome', 'connected')
    from bl b, generate_series(1, 2) x) y;
select pg_temp.set('b1', b2b.api_b2c_batch('eb2b_m32test_key_0001', jsonb_build_object('items', (select jsonb_agg(item order by n) from items where n <= 200)))::text);
select pg_temp.set('b2', b2b.api_b2c_batch('eb2b_m32test_key_0001', jsonb_build_object('items', (select jsonb_agg(item order by n) from items where n between 201 and 400)))::text);
select pg_temp.set('b3', b2b.api_b2c_batch('eb2b_m32test_key_0001', jsonb_build_object('items', (select jsonb_agg(item order by n) from items where n > 400)))::text);
insert into r select 't2_batch_applied', (pg_temp.v('b1')::jsonb -> 'result' ->> 'applied')::int = 200 and (pg_temp.v('b2')::jsonb -> 'result' ->> 'applied')::int = 200
                       and (pg_temp.v('b3')::jsonb -> 'result' ->> 'applied')::int = 50, null;
insert into r select 't2_activity_answers_have_version', bool_and((i ->> 'version') is not null), null
  from jsonb_array_elements(pg_temp.v('b2')::jsonb -> 'result' -> 'items') i;
insert into r select 't2_no_echo', not exists (select 1 from b2b.integration_outbox o join bl b on (o.payload ->> 'lead_id')::bigint = b.lead_id
                                                where o.event_type = 'b2c.lead_upserted' and o.status = 'pending'), null;
insert into r select 't2_feed_lists_them', count(distinct s.lead_id) = 150 and bool_and(s.origin like 'b2c:%'), count(distinct s.lead_id)::text
  from b2b.b2c_sync s join bl b on b.lead_id = s.lead_id where s.seq > pg_temp.v('seq_before')::bigint;
insert into r select 't2_feed_api', jsonb_array_length(x -> 'result' -> 'leads') = 150, null
  from (select b2b.api_b2c_leads_feed('eb2b_m32test_key_0001', pg_temp.v('seq_before')::bigint, 500) x) y;
insert into r select 't2_rollups', bool_and(l.contact_attempts = 2 and l.custom_fields -> 'b2c' ->> 'stage' = 'Program Details Explained'), null
  from public.student_leads l join bl b on b.lead_id = l.id;
-- someone else's change after the batch still goes out at once
update public.student_leads set city = 'Bhopal' where id = (select lead_id from bl where n = 1);
select b2b.b2c_sync_lead((select lead_id from bl where n = 1));
insert into r select 't2_other_change_delivered', pg_temp.upserts((select lead_id from bl where n = 1)) = 2, null;

-- ======================================================================================================================
-- 3. occurred_at, contact roll-ups that never move backwards, and each activity counted once across retries
-- ======================================================================================================================
select pg_temp.set('C', pg_temp.held('910000320002', 'Clock Held')::text);
select pg_temp.set('c1', b2b.api_b2c_batch('eb2b_m32test_key_0001', jsonb_build_object('items', jsonb_build_array(
  jsonb_build_object('op', 'update', 'lead_id', pg_temp.v('C')::bigint, 'request_id', 'm32-c-u1', 'occurred_at', now() - interval '14 minutes', 'set', jsonb_build_object('stage', 'assigned')),
  jsonb_build_object('op', 'activity', 'lead_id', pg_temp.v('C')::bigint, 'request_id', 'm32-c-a1', 'kind', 'call', 'at', now() - interval '2 minutes'))))::text);
-- a late batch: an older activity, and the first activity retried
select pg_temp.set('c2', b2b.api_b2c_batch('eb2b_m32test_key_0001', jsonb_build_object('items', jsonb_build_array(
  jsonb_build_object('op', 'activity', 'lead_id', pg_temp.v('C')::bigint, 'request_id', 'm32-c-a0', 'kind', 'whatsapp', 'at', now() - interval '20 minutes'),
  jsonb_build_object('op', 'activity', 'lead_id', pg_temp.v('C')::bigint, 'request_id', 'm32-c-a1', 'kind', 'call', 'at', now() - interval '2 minutes'),
  jsonb_build_object('op', 'update', 'lead_id', pg_temp.v('C')::bigint, 'request_id', 'm32-c-u2', 'occurred_at', now() - interval '20 minutes',
                     'set', jsonb_build_object('last_contacted_at', now() - interval '30 minutes')))))::text);
insert into r select 't3_stage_changed_at_is_occurred_at', l.stage = 'assigned' and l.stage_changed_at = now() - interval '14 minutes', l.stage || ' ' || l.stage_changed_at
  from public.student_leads l where l.id = pg_temp.v('C')::bigint;
insert into r select 't3_last_contacted_not_backwards', l.last_contacted_at = now() - interval '2 minutes' and l.first_contacted_at = now() - interval '20 minutes',
                     l.first_contacted_at || ' / ' || l.last_contacted_at
  from public.student_leads l where l.id = pg_temp.v('C')::bigint;
insert into r select 't3_attempts_once_per_request', l.contact_attempts = 2, l.contact_attempts::text from public.student_leads l where l.id = pg_temp.v('C')::bigint;
insert into r select 't3_retry_replayed', (pg_temp.v('c2')::jsonb -> 'result' -> 'items' -> 1 ->> 'replayed')::boolean, pg_temp.v('c2');
insert into r select 't3_timeline_at_occurred_at', exists (select 1 from b2b.events e where e.lead_id = pg_temp.v('C')::bigint and e.type = 'b2c.lead_updated'
                                                           and e.occurred_at = now() - interval '14 minutes' and e.payload ->> 'request_id' = 'm32-c-u1'), null;
insert into r select 't3_future_refused', (b2b.api_b2c_lead_update('eb2b_m32test_key_0001', pg_temp.v('C')::bigint,
                       jsonb_build_object('request_id', 'm32-c-u3', 'occurred_at', now() + interval '1 hour', 'set', jsonb_build_object('sub_stage', 'x'))) ->> 'status')::int = 400, null;

-- ======================================================================================================================
-- 4. The Eduwit stage, sub-stage, comment and counsellor: written, on the Master Lead Table, safe from custom_fields
-- ======================================================================================================================
select pg_temp.set('S', pg_temp.held('910000320003', 'Stage Held')::text);
select pg_temp.set('s1', b2b.api_b2c_lead_update('eb2b_m32test_key_0001', pg_temp.v('S')::bigint, jsonb_build_object('request_id', 'm32-s-1',
  'set', jsonb_build_object('b2c_stage', 'Program Details Explained', 'b2c_sub_stage', 'Fees shared', 'b2c_stage_comment', 'Wants EMI options',
                            'owner_name', 'Priya Sharma', 'enrollment_verified_at', now(), 'active_journey_id', 7)))::text);
select pg_temp.set('s2', b2b.api_b2c_lead_update('eb2b_m32test_key_0001', pg_temp.v('S')::bigint, jsonb_build_object('request_id', 'm32-s-2',
  'set', jsonb_build_object('custom_fields', jsonb_build_object('source_note', 'fair'))))::text);
select pg_temp.set('s3', b2b.api_b2c_lead_update('eb2b_m32test_key_0001', pg_temp.v('S')::bigint, jsonb_build_object('request_id', 'm32-s-3',
  'set', jsonb_build_object('custom_fields', jsonb_build_object('b2c', jsonb_build_object('stage', 'hack')))))::text);
insert into r select 't4_written', (pg_temp.v('s1')::jsonb ->> 'ok')::boolean and l.custom_fields -> 'b2c' ->> 'stage' = 'Program Details Explained'
                       and l.custom_fields -> 'b2c' ->> 'owner_name' = 'Priya Sharma' and l.enrollment_verified_at is not null and l.active_journey_id = 7,
                     left(pg_temp.v('s1'), 300)
  from public.student_leads l where l.id = pg_temp.v('S')::bigint;
insert into r select 't4_survives_custom_fields', l.custom_fields ->> 'source_note' = 'fair' and l.custom_fields -> 'b2c' ->> 'sub_stage' = 'Fees shared'
                       and l.custom_fields -> 'b2c' ->> 'stage_comment' = 'Wants EMI options', l.custom_fields::text
  from public.student_leads l where l.id = pg_temp.v('S')::bigint;
insert into r select 't4_b2c_key_refused', (pg_temp.v('s3')::jsonb ->> 'status')::int = 422 and pg_temp.v('s3')::jsonb -> 'fields' ? 'custom_fields', pg_temp.v('s3');
insert into r select 't4_record_fields', x -> 'pipeline' ->> 'b2c_stage' = 'Program Details Explained' and x -> 'pipeline' ->> 'owner_name' = 'Priya Sharma'
                       and x -> 'pipeline' ->> 'b2c_stage_comment' = 'Wants EMI options' and not (x -> 'other' -> 'custom_fields' ? 'b2c')
                       and (x -> 'marketing' ->> 'active_journey_id')::int = 7, left(x::text, 300)
  from (select b2b.b2c_record(l) x from public.student_leads l where l.id = pg_temp.v('S')::bigint) y;
set local role authenticated;
select pg_temp.admin();
insert into r select 't4_master_lead_table', bool_or(z ->> 'b2c_stage' = 'Program Details Explained' and z ->> 'b2c_sub_stage' = 'Fees shared' and z ->> 'b2c_owner_name' = 'Priya Sharma'),
                     left((b2b.leads_list(jsonb_build_object('q', '910000320003', 'include_test', true)) -> 'rows')::text, 300)
  from jsonb_array_elements(b2b.leads_list(jsonb_build_object('q', '910000320003', 'include_test', true)) -> 'rows') z;
reset role;

-- ======================================================================================================================
-- 5. Marketing consent per channel; an email-only opt-out leaves the student opted in on WhatsApp
-- ======================================================================================================================
select pg_temp.set('m1', pg_temp.b2c(jsonb_build_object('event_id', 'm32-mc-1', 'type', 'b2ccrm.marketing_consent', 'data', jsonb_build_object(
  'lead_id', pg_temp.v('S')::bigint, 'channel', 'whatsapp', 'given', true, 'text', 'Yes, send me programme updates on WhatsApp', 'text_version', 'wa-mkt-v1',
  'source', 'wa_button', 'at', now() - interval '1 minute')))::text);
insert into r select 't5_marketing_consent_set', (pg_temp.v('m1')::jsonb ->> 'ok')::boolean and l.consent_marketing_at = now() - interval '1 minute'
                       and (l.custom_fields -> 'b2c' -> 'marketing_consent' -> 'whatsapp' ->> 'given')::boolean
                       and exists (select 1 from b2b.lead_consents c where c.lead_id = l.id and c.purpose = 'marketing' and c.state = 'given' and c.source = 'b2c_crm'),
                     pg_temp.v('m1')
  from public.student_leads l where l.id = pg_temp.v('S')::bigint;
select pg_temp.set('o1', pg_temp.b2c(jsonb_build_object('event_id', 'm32-oo-1', 'type', 'b2ccrm.opted_out', 'data', jsonb_build_object(
  'lead_id', pg_temp.v('S')::bigint, 'channels', jsonb_build_array('email'))))::text);
insert into r select 't5_email_only_opt_out', (pg_temp.v('o1')::jsonb ->> 'ok')::boolean and not coalesce(l.is_opted_out, false) and l.opted_out_channels = '{email}',
                     coalesce(l.opted_out_channels::text, '-') || ' ' || pg_temp.v('o1')
  from public.student_leads l where l.id = pg_temp.v('S')::bigint;
select pg_temp.set('m2', pg_temp.b2c(jsonb_build_object('event_id', 'm32-mc-2', 'type', 'b2ccrm.marketing_consent', 'data', jsonb_build_object(
  'lead_id', pg_temp.v('S')::bigint, 'channel', 'whatsapp', 'given', false, 'source', 'wa_button')))::text);
insert into r select 't5_marketing_consent_cleared', l.consent_marketing_at is null
                       and exists (select 1 from b2b.lead_consents c where c.lead_id = l.id and c.purpose = 'marketing' and c.state = 'withdrawn'), pg_temp.v('m2')
  from public.student_leads l where l.id = pg_temp.v('S')::bigint;
select pg_temp.set('o2', pg_temp.b2c(jsonb_build_object('event_id', 'm32-oo-2', 'type', 'b2ccrm.opted_out', 'data', jsonb_build_object(
  'lead_id', pg_temp.v('S')::bigint, 'channels', jsonb_build_array('whatsapp'))))::text);
insert into r select 't5_all_channels_opted_out', coalesce(l.is_opted_out, false) and l.opted_out_channels @> '{email,whatsapp}', pg_temp.v('o2')
  from public.student_leads l where l.id = pg_temp.v('S')::bigint;

-- ======================================================================================================================
-- 6. A second phone recorded by the B2C CRM: the lookup finds the lead, and a new intake with it is the same student
-- ======================================================================================================================
select pg_temp.set('k1', pg_temp.b2c(jsonb_build_object('event_id', 'm32-ca-1', 'type', 'b2ccrm.contact_added', 'data', jsonb_build_object(
  'lead_id', pg_temp.v('C')::bigint, 'kind', 'phone', 'value', '+91 99000 32004', 'label', 'parent', 'primary_for', '[]'::jsonb)))::text);
insert into r select 't6_contact_recorded', (pg_temp.v('k1')::jsonb ->> 'ok')::boolean
                       and exists (select 1 from b2b.lead_contacts c where c.lead_id = pg_temp.v('C')::bigint and c.kind = 'phone' and c.value = '919900032004' and c.label = 'parent')
                       and (select alternate_phone = '919900032004' and whatsapp_number = '910000320002' from public.student_leads where id = pg_temp.v('C')::bigint), pg_temp.v('k1');
insert into r select 't6_lookup_by_contact', exists (select 1 from jsonb_array_elements(x -> 'result' -> 'leads') z where (z ->> 'lead_id')::bigint = pg_temp.v('C')::bigint
                                                       and z ->> 'matched_on' = 'contact'), left(x::text, 300)
  from (select b2b.api_b2c_lead_lookup('eb2b_m32test_key_0001', '9900032004', null) x) y;
insert into r select 't6_intake_same_student', (x ->> 'lead_id')::bigint = pg_temp.v('C')::bigint
                       and (x -> 'warnings') ? 'matched a number recorded for an existing student', left(x::text, 300)
  from (select b2b.intake_lead('{"full_name":"Clock Held","phone":"9900032004","course":"MBA"}', jsonb_build_object('source_system', 'api', 'lead_source', 'website')) x) y;
insert into r select 't6_no_new_lead', not exists (select 1 from public.student_leads where whatsapp_number = '919900032004'), null;

-- ======================================================================================================================
-- 7. Lookup of a student a partner holds: who holds it and since when, no personal data
-- ======================================================================================================================
select pg_temp.set('P', (b2b.intake_lead('{"full_name":"Partner Held","phone":"910000320005","email":"partner.held@example.com","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website')) ->> 'lead_id'));
update public.student_leads set destination_type = 'partner', partner_id = 20, allocated_at = now() - interval '3 days' where id = pg_temp.v('P')::bigint;
insert into r select 't7_holder', z -> 'holder' ->> 'destination' = 'partner' and z -> 'holder' ->> 'partner_name' is not null
                       and (z -> 'holder' ->> 'since')::timestamptz = now() - interval '3 days' and z -> 'record' = 'null'::jsonb
                       and not (z::text like '%partner.held@example.com%') and not (z::text like '%Partner Held%'), z::text
  from jsonb_array_elements((b2b.api_b2c_lead_lookup('eb2b_m32test_key_0001', '910000320005', null)) -> 'result' -> 'leads') z;

-- ======================================================================================================================
-- 8. Partner history of a partner-lost lead the B2C CRM holds (fixture E7: lost at e2e-async, now B2C nurture)
-- ======================================================================================================================
insert into b2b.partner_activities (allocation_id, lead_id, partner_id, kind, direction, outcome, counsellor_name, occurred_at, mapped)
values (40, 338, 22, 'call', 'outbound', 'not_reachable', 'Ravi (partner counsellor)', now() - interval '2 days', '{"note":"called twice"}');
update b2b.allocations set lost_at = now() - interval '1 day', lost_detail = '{"status":"Lost","sub_status":"Not interested","lost_reason":"Not interested"}' where id = 40;
insert into r select 't8_partner_history', (x ->> 'ok')::boolean and jsonb_array_length(x -> 'result' -> 'history') >= 2
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'history') h where h ->> 'kind' = 'call' and h ->> 'outcome' = 'not_reachable' and h ->> 'note' = 'called twice')
                       and x -> 'result' ->> 'last_partner_status' = 'Lost' and x -> 'result' ->> 'last_partner_sub_status' = 'Not interested'
                       and not (x::text like '%Ravi%'), left(x::text, 400)
  from (select b2b.api_b2c_partner_history('eb2b_m32test_key_0001', 338) x) y;
insert into r select 't8_not_held_404', (b2b.api_b2c_partner_history('eb2b_m32test_key_0001', pg_temp.v('P')::bigint) ->> 'status')::int = 404, null;

-- ======================================================================================================================
-- 9. The catalog schema: the highest rate for a programme two partners offer; b2c_app reads it and not student_leads
-- ======================================================================================================================
insert into r select 't9_highest_for_programme', count(*) filter (where v.is_highest_for_programme) = 1
                       and bool_or(v.is_highest_for_programme and v.partner_id = 20 and v.value = 25)
                       and count(distinct v.partner_id) >= 2, string_agg(v.partner_id || ':' || v.value || ':' || v.is_highest_for_programme, ' ')
  from catalog.partner_rates_v v where v.programme_id = 33;
insert into r select 't9_programmes_v', p.offered_by_partner_count >= 2 and p.programme_name is not null, p.offered_by_partner_count::text
  from catalog.programmes_v p where p.id = 33;
insert into r select 't9_b2c_app_reads_catalog', pg_temp.as_role('b2c_app', 'select count(*) from catalog.partner_rates_v') = 'ok'
                       and pg_temp.as_role('b2c_app', 'select count(*) from catalog.programmes_v') = 'ok', null;
insert into r select 't9_b2c_app_no_student_leads', pg_temp.as_role('b2c_app', 'select count(*) from public.student_leads') like 'permission denied%',
                     pg_temp.as_role('b2c_app', 'select count(*) from public.student_leads');
insert into r select 't9_b2c_app_no_b2b', pg_temp.as_role('b2c_app', 'select count(*) from b2b.rates') like 'permission denied%', null;
insert into b2b.rates (scope, partner_id, rate_type, value) values ('partner', 21, 'percent', 30);
insert into r select 't9_changes_logged', exists (select 1 from catalog.changes c where c.kind = 'rate' and c.at = now()), null;

-- ======================================================================================================================
-- 10. contract_version 4 on every envelope and record; the schema lists the new fields, groups and event types
-- ======================================================================================================================
insert into r select 't10_envelopes_v4', count(*) > 0 and bool_and((o.payload ->> 'contract_version')::int = 4 and (o.payload -> 'data' -> 'record' ->> 'contract_version')::int = 4), count(*)::text
  from b2b.integration_outbox o where o.event_type = 'b2c.lead_upserted' and o.created_at = now() and o.payload -> 'data' -> 'record' ? 'id' and (o.payload -> 'data' -> 'record' ->> 'held_by_b2c')::boolean;
insert into r select 't10_schema_v4', (x -> 'result' ->> 'contract_version')::int = 4 and x -> 'result' ->> 'delivery' = 'realtime'
                       and (x -> 'result' -> 'groups') ? 'marketing'
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'fields') f where f ->> 'field' = 'b2c_stage' and (f ->> 'writable')::boolean)
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'fields') f where f ->> 'field' = 'enrollment_verified_at')
                       and (x -> 'result' -> 'inbound') ? 'b2ccrm.marketing_consent' and (x -> 'result' -> 'inbound') ? 'b2ccrm.contact_added'
                       and not ((x -> 'result' -> 'events') ? 'b2c.leads_batch')
                       and jsonb_typeof(x -> 'result' -> 'consent_texts') = 'array' and (x -> 'result' -> 'batch' ->> 'max_items')::int = 200, left(x::text, 300)
  from (select b2b.api_b2c_schema('eb2b_m32test_key_0001') x) y;

-- ---------- hygiene: nothing outside the test phones ----------
insert into r select 'no_real_phone_used', not exists (select 1 from public.student_leads l where l.created_at = now() and l.whatsapp_number !~ '^(910000|919900032004)'), null;

select name, ok, detail from r order by ok, name;
rollback;
