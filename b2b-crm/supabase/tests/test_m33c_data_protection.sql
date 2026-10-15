-- M33c data protection and audit, rolled back: erasure (what is blanked, what stays, the B2C release, the partner
-- notices, the events), closing an erasure request, the retention rules (validation, preview, the nightly run), the
-- audit log and the overview. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$
  insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c3","role":"authenticated","aal":"aal2","email":"m33c-admin@test.local"}', true) $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000c3', 'm33c-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000c3', 'm33c-admin@test.local');
do $x$ declare v_secret uuid := vault.create_secret('whsec_m33c_test_secret_00000000000000000000000000000', 'b2b_m33c_' || gen_random_uuid(), 'm33c');
begin
  update b2b.webhook_endpoints set url = 'https://b2c.example.test/hooks/b2b', events = '{b2c.*,b2b.*}', active = true, secret_id = v_secret where consumer = 'b2c_crm';
  if not found then insert into b2b.webhook_endpoints (name, consumer, url, events, active, secret_id) values ('B2C CRM (m33c)', 'b2c_crm', 'https://b2c.example.test/hooks/b2b', '{b2c.*,b2b.*}', true, v_secret); end if;
end $x$;

-- a B2C-held lead with everything that holds personal data, once with a partner
select pg_temp.set('L', (b2b.intake_lead('{"full_name":"Priya Nair","phone":"919876533101","email":"priya.nair@example.com","city":"Kochi","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id'));
update public.student_leads set alternate_phone = '919876533102', guardian_name = 'Suresh Nair', custom_fields = '{"note": "x"}', ip_address = '1.2.3.4' where id = pg_temp.v('L')::bigint;
insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, status, mode, reason, outcome) values (pg_temp.v('L')::bigint, 1, 'partner', 20, 'closed', 'commission_first', null, 'lost');
with a as (insert into b2b.allocations (lead_id, cycle_no, destination_type, b2c_lane, status, mode, reason) values (pg_temp.v('L')::bigint, 1, 'in_house', 'nurture', 'handed_off', 'fallback', 'partner_lost') returning id)
update public.student_leads l set destination_type = 'in_house', allocation_id = a.id, allocated_at = now(), allocation_reason = 'partner_lost' from a where l.id = pg_temp.v('L')::bigint;
insert into b2b.lead_contacts (lead_id, kind, value, label, origin) values (pg_temp.v('L')::bigint, 'phone', '919876533103', 'parent', 'b2c');
insert into b2b.lead_edits (lead_id, field, old_value, new_value, reason, actor_id) values (pg_temp.v('L')::bigint, 'student_name', 'Priya', 'Priya Nair', 'typo', 'x');
select b2b.b2c_sync_lead(pg_temp.v('L')::bigint);
update b2b.integration_outbox set status = 'delivered', delivered_at = now() where status = 'pending' and (payload ->> 'lead_id')::bigint = pg_temp.v('L')::bigint;
set local role authenticated;
select pg_temp.admin();
select b2b.lead_note_add(pg_temp.v('L')::bigint, 'Wants a hostel; father pays');
-- ---------- erasure ----------
do $x$ declare x jsonb; e text; begin
  e := pg_temp.err(format($q$select b2b.lead_anonymise(%s, 'x')$q$, pg_temp.v('L')));
  insert into r values ('erase_needs_reason', e like '22023 a reason is required%', e);
  x := b2b.lead_anonymise(pg_temp.v('L')::bigint, 'student asked on the phone');
  perform pg_temp.set('EX', x::text);
  insert into r values ('erase_result', (x ->> 'lead_id')::bigint = pg_temp.v('L')::bigint and x -> 'partners_to_notify' = '[20]'::jsonb
                        and (x -> 'erased' ->> 'contacts')::int = 1 and (x -> 'erased' ->> 'notes')::int = 1 and (x -> 'erased' ->> 'edits')::int = 1, x::text);
  x := b2b.lead_anonymise(pg_temp.v('L')::bigint, 'again');
  insert into r values ('erase_once', (x ->> 'already')::boolean, x::text);
end $x$;
reset role;
insert into r select 'erase_lead_row', l.student_name = 'Erased' and l.whatsapp_number = 'ERASED-' || l.id and l.email_id is null and l.alternate_phone is null and l.guardian_name is null
                     and l.ip_address is null and l.custom_fields = '{}' and l.anonymised_at is not null and l.is_opted_out and l.deleted_at is not null
                     and l.city = 'Kochi' and l.interested_course = 'MBA' and l.destination_type = 'in_house', l::text
  from public.student_leads l where l.id = pg_temp.v('L')::bigint;
insert into r select 'erase_copies', (select bool_and(value like 'erased:%' and removed_at is not null) from b2b.lead_contacts where lead_id = pg_temp.v('L')::bigint)
  and (select bool_and(body = '[erased]' and deleted_at is not null) from b2b.lead_notes where lead_id = pg_temp.v('L')::bigint)
  and (select bool_and(old_value = '[erased]' and new_value = '[erased]') from b2b.lead_edits where lead_id = pg_temp.v('L')::bigint), null;
insert into r select 'erase_deliveries_stripped', bool_and(o.payload ? 'erased' and not (o.payload::text like '%Priya%')), count(*)::text
  from b2b.integration_outbox o where (o.payload ->> 'lead_id')::bigint = pg_temp.v('L')::bigint and o.payload ->> 'type' = 'b2c.lead_upserted';
insert into r select 'erase_released_from_b2c', exists (select 1 from b2b.integration_outbox o where (o.payload ->> 'lead_id')::bigint = pg_temp.v('L')::bigint and o.event_type = 'b2c.lead_released' and o.status = 'pending')
  and (select not in_scope from b2b.b2c_sync where lead_id = pg_temp.v('L')::bigint), null;
insert into r select 'erase_events', exists (select 1 from b2b.events e where e.type = 'lead.anonymised' and e.lead_id = pg_temp.v('L')::bigint and not (e.payload::text like '%Priya%'))
  and exists (select 1 from b2b.events e where e.type = 'alert.partner_erasure_notice' and e.lead_id = pg_temp.v('L')::bigint and e.partner_id = 20), null;
-- a new enquiry from the erased number is a new lead (no link to the old one)
insert into r select 'erased_number_is_new', (x ->> 'lead_id')::bigint <> pg_temp.v('L')::bigint and x ->> 'action' = 'created', x::text
  from (select b2b.intake_lead('{"full_name":"Priya N","phone":"919876533101","course":"MBA"}', jsonb_build_object('source_system', 'api', 'lead_source', 'website')) x) y;

-- ---------- closing an erasure request erases ----------
select pg_temp.set('L2', (b2b.intake_lead('{"full_name":"Rohan Das","phone":"919876533111","email":"rohan@example.com","course":"MCA"}', jsonb_build_object('source_system', 'api', 'lead_source', 'website')) ->> 'lead_id'));
insert into b2b.erasure_requests (lead_id, source, note) values (pg_temp.v('L2')::bigint, 'b2c_crm', 'asked in chat');
set local role authenticated;
select pg_temp.admin();
select b2b.erasure_request_close((select max(id) from b2b.erasure_requests where lead_id = pg_temp.v('L2')::bigint), 'done', 'verified by phone');
reset role;
insert into r select 'request_done_erases', l.anonymised_at is not null and l.student_name = 'Erased'
  and (select status = 'done' from b2b.erasure_requests where lead_id = l.id) and exists (select 1 from b2b.events where type = 'erasure.done' and lead_id = l.id), null
  from public.student_leads l where l.id = pg_temp.v('L2')::bigint;

-- ---------- retention ----------
select pg_temp.set('OLD', (b2b.intake_lead('{"full_name":"Old Lead","phone":"919876533121","email":"old@example.com","course":"BBA"}', jsonb_build_object('source_system', 'api', 'lead_source', 'website')) ->> 'lead_id'));
select pg_temp.set('BUSY', (b2b.intake_lead('{"full_name":"Busy Lead","phone":"919876533122","email":"busy@example.com","course":"BBA"}', jsonb_build_object('source_system', 'api', 'lead_source', 'website')) ->> 'lead_id'));
select pg_temp.set('TST', (b2b.intake_lead('{"full_name":"Test Lead","phone":"910000033123","course":"BBA"}', jsonb_build_object('source_system', 'api', 'lead_source', 'website')) ->> 'lead_id'));
-- the touch trigger bumps updated_at on every update (that is what "idle" measures); backdate without it, test only, rolled back
alter table public.student_leads disable trigger student_leads_touch_trg;
update public.student_leads set created_at = now() - interval '14 months', updated_at = now() - interval '13 months', last_activity_at = now() - interval '13 months', last_contacted_at = null
 where id in (pg_temp.v('OLD')::bigint, pg_temp.v('BUSY')::bigint);
alter table public.student_leads enable trigger student_leads_touch_trg;
insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, status, mode) values (pg_temp.v('BUSY')::bigint, 1, 'partner', 20, 'accepted', 'commission_first');
update public.student_leads set created_at = now() - interval '40 days' where id = pg_temp.v('TST')::bigint;

insert into b2b.sign_in_log (at, email, method, outcome) values (now() - interval '400 days', 'x@test.local', 'session', 'success');
set local role authenticated;
select pg_temp.admin();
do $x$ declare x jsonb; e text; begin
  e := pg_temp.err($q$select b2b.retention_settings_save('{"inactive_months": 3}', 'test')$q$);
  insert into r values ('retention_months_checked', e like '22023 inactive_months is 6 to 120%', e);
  e := pg_temp.err($q$select b2b.retention_settings_save('{"test_lead_days": 0}', 'test')$q$);
  insert into r values ('retention_days_checked', e like '22023 test_lead_days is 1 to 365%', e);
  x := b2b.retention_settings_save('{"inactive_months": 12, "test_lead_days": 30}', 'm33c test');
  insert into r values ('retention_saved', (x ->> 'inactive_months')::int = 12 and (x ->> 'test_lead_days')::int = 30, x::text);
  x := b2b.retention_preview();
  insert into r values ('retention_preview', (x ->> 'inactive_to_erase')::int = 1 and (x ->> 'test_leads_to_delete')::int = 1 and (x ->> 'anonymised_total')::int >= 2, x::text);
end $x$;
reset role;
insert into t select 'RT', b2b.retention_tick()::text;
insert into r select 'retention_tick', (x ->> 'erased')::int = 1 and (x ->> 'test_deleted')::int = 1 and (x ->> 'errors')::int = 0 and (x ->> 'sign_in_pruned')::int >= 1, x::text
  from (select pg_temp.v('RT')::jsonb x) y;
insert into r select 'retention_applied', (select anonymised_at is not null from public.student_leads where id = pg_temp.v('OLD')::bigint)
  and (select anonymised_at is null from public.student_leads where id = pg_temp.v('BUSY')::bigint)
  and (select deleted_at is not null and anonymised_at is null from public.student_leads where id = pg_temp.v('TST')::bigint)
  and exists (select 1 from b2b.events where type = 'lead.deleted' and lead_id = pg_temp.v('TST')::bigint and (payload ->> 'retention')::boolean)
  and (select value ->> 'erased' = '1' from b2b.job_state where key = 'retention'), null;
insert into r select 'retention_cron', exists (select 1 from cron.job where jobname = 'b2b-retention'), null;

-- ---------- the audit log and the overview ----------
set local role authenticated;
select pg_temp.admin();
do $x$ declare x jsonb; begin
  x := b2b.audit_log('{"q": "anonymised"}');
  insert into r values ('audit_filter_type', jsonb_array_length(x -> 'rows') >= 2 and (select bool_and(z ->> 'type' = 'lead.anonymised') from jsonb_array_elements(x -> 'rows') z), left(x::text, 300));
  x := b2b.audit_log('{"actor_type": "admin", "limit": 1}');
  insert into r values ('audit_admin_rows', jsonb_array_length(x -> 'rows') = 1 and x -> 'rows' -> 0 ->> 'actor_email' = 'm33c-admin@test.local' and (x ->> 'next_after') is not null, left(x::text, 300));
  insert into r values ('audit_keyset', (select max((z ->> 'id')::bigint) from jsonb_array_elements(b2b.audit_log(jsonb_build_object('actor_type', 'admin', 'after', x ->> 'next_after')) -> 'rows') z) < (x ->> 'next_after')::bigint, null);
  x := b2b.audit_log(jsonb_build_object('actor_type', 'all', 'lead_id', pg_temp.v('L')::bigint));
  insert into r values ('audit_by_lead', jsonb_array_length(x -> 'rows') >= 3 and (select bool_and((z ->> 'lead_id')::bigint = pg_temp.v('L')::bigint) from jsonb_array_elements(x -> 'rows') z), null);
  x := b2b.data_protection_overview();
  insert into r values ('dp_overview', (x -> 'erasures' ->> 'done_30d')::int = 1 and (x ->> 'anonymised_total')::int >= 3 and (x ->> 'partner_notices_open')::int >= 1 and x ? 'settings', x::text);
end $x$;
reset role;
select name, ok, detail from r order by ok, name;
rollback;
