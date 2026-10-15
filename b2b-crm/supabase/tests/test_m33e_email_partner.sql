-- M33e leads by email for a partner without an API (staging fixtures: partner 22 becomes an email partner), rolled back:
-- the adapter settings, the checklist, the push through the email provider, the provider's answer, and outcomes recorded
-- by hand. Every row must say ok = true.
begin;
select pg_advisory_xact_lock(hashtext('b2b.push_tick'));
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.set(key text, val text) returns void language sql as $f$
  insert into t values (key, val) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e5","role":"authenticated","aal":"aal2","email":"m33e-admin@test.local"}', true) $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000e5', 'm33e-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000e5', 'm33e-admin@test.local');
-- the email provider (Notifications settings), as test_m9 sets it
do $x$ declare e uuid := vault.create_secret('test-key', 'b2b_test_mail_' || txid_current(), 'rolled back');
begin
  update b2b.settings set value = value || jsonb_build_object('email', coalesce(value -> 'email', '{}') || jsonb_build_object('provider', 'resend', 'from_email', 'leads@eduwit.in', 'from_name', 'Eduwit', 'api_key_secret_id', e, 'base_url', 'https://mock.invalid/mail'))
   where key = 'notifications';
end $x$;
update b2b.partners set adapter_type = 'email', dedupe_mode = 'none', hold_minutes = 0 where id = 22;

set local role authenticated;
select pg_temp.admin();
do $x$ declare x jsonb; e text; begin
  e := pg_temp.err($q$select b2b.partner_adapter_save(22, '{"env": "live", "settings": {"to_email": "not an email"}}')$q$);
  insert into r values ('email_setting_checked', e like '22023 to email must be one or more email addresses%', e);
  e := pg_temp.err($q$select b2b.partner_adapter_save(22, '{"env": "live", "settings": {"to_email": ""}}')$q$);
  insert into r values ('email_required', e like '22023 the to email is required%', e);
  x := b2b.partner_adapter_save(22, '{"env": "live", "settings": {"to_email": "Admissions@Partner.test, ops@partner.test", "subject_prefix": "[Eduwit]"}}');
  insert into r values ('email_saved', x ->> 'adapter' = 'email' and (x -> 'envs' -> 'live' ->> 'configured')::boolean and not (x -> 'envs' -> 'sandbox' ->> 'configured')::boolean
                        and x -> 'envs' -> 'live' -> 'settings' ->> 'to_email' = 'admissions@partner.test, ops@partner.test' and x -> 'spec' ->> 'label' = 'Email (no CRM API)', x::text);
  x := b2b.partner_adapter_save(22, '{"env": "sandbox", "settings": {"to_email": "sandbox@partner.test"}}');
end $x$;
reset role;
insert into r select 'checklist_email', (select bool_and((i ->> 'done')::boolean) from jsonb_array_elements(b2b.partner_checklist(p)) i where i ->> 'key' in ('credentials', 'mapping'))
                        and (select not (i ->> 'available')::boolean from jsonb_array_elements(b2b.partner_checklist(p)) i where i ->> 'key' = 'mapping'), b2b.partner_checklist(p)::text
    from b2b.partners p where p.id = 22;
update b2b.partners set hold_minutes = 0 where id = 22;  -- adapter_save resets the A3 hold (30 min async); accept at once here

-- a lead allocated to the email partner: the push is an email through the provider
select pg_temp.set('L', (b2b.intake_lead('{"full_name":"Email Lead","phone":"919876533301","email":"email.lead@example.com","course":"BBA","city":"Goa"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'consent', jsonb_build_object('sales_at', now(), 'partner_share_at', now(), 'text_version', 'test-partner-share:v1'))) ->> 'lead_id'));
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at) values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now()) on conflict (version) do nothing;
with a as (insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, programme_id, status, mode, segment, reference)
values (pg_temp.v('L')::bigint, 1, 'partner', 22, 34, 'queued', 'commission_first', 'bba|UG|Online', 'EDW-M33E') returning id)
insert into t select 'A', id::text from a;
update public.student_leads set destination_type = 'partner', partner_id = 22, allocation_id = pg_temp.v('A')::bigint, allocated_at = now() where id = pg_temp.v('L')::bigint;
insert into r select 'push_request_is_email', req ->> 'provider' = 'resend' and req ->> 'url' = 'https://mock.invalid/mail/emails'
  and req -> 'body' -> 'to' = '["admissions@partner.test", "ops@partner.test"]'::jsonb and req -> 'body' ->> 'subject' like '[Eduwit] EDW-M33E: Email Lead%'
  and req -> 'body' ->> 'html' like '%Email Lead%' and req -> 'headers' ->> 'Authorization' = 'Bearer test-key', left(req::text, 400)
  from (select b2b.push_request(a) req from b2b.allocations a where a.id = pg_temp.v('A')::bigint) y;
select b2b.push_dispatch(10);
insert into r select 'dispatched', a.status = 'pushing' and a.push_request_id is not null and q.url = 'https://mock.invalid/mail/emails', a.status
  from b2b.allocations a join net.http_request_queue q on q.id = a.push_request_id where a.id = pg_temp.v('A')::bigint;
insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select a.push_request_id, 200, 'application/json', '{"id": "re_abc123"}', false, null, now() from b2b.allocations a where a.id = pg_temp.v('A')::bigint;
select b2b.push_collect();
insert into r select 'created_then_accepted', a.status = 'accepted' and a.partner_record_id = 're_abc123' and a.pushed_at is not null, a.status || ' ' || coalesce(a.partner_record_id, '-')
  from b2b.allocations a where a.id = pg_temp.v('A')::bigint;  -- hold 0: the provider's id is the record id and the lead is accepted at once
-- the provider refuses the key: the Admin is told, the push is retried later as an error
select pg_temp.set('L2', (b2b.intake_lead('{"full_name":"Second Lead","phone":"919876533302","course":"BBA"}', jsonb_build_object('source_system', 'api', 'lead_source', 'website')) ->> 'lead_id'));
insert into b2b.allocations (lead_id, cycle_no, destination_type, partner_id, programme_id, status, mode, segment, reference)
values (pg_temp.v('L2')::bigint, 1, 'partner', 22, 34, 'queued', 'commission_first', 'bba|UG|Online', 'EDW-M33E2');
update public.student_leads set destination_type = 'partner', partner_id = 22, allocation_id = (select max(id) from b2b.allocations where lead_id = pg_temp.v('L2')::bigint) where id = pg_temp.v('L2')::bigint;
select b2b.push_dispatch(10);
insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select a.push_request_id, 401, 'application/json', '{"message": "invalid api key"}', false, null, now() from b2b.allocations a where a.lead_id = pg_temp.v('L2')::bigint;
select b2b.push_collect();
insert into r select 'provider_refusal_alerts', exists (select 1 from b2b.events e where e.type = 'alert.push_error' and e.partner_id = 22 and e.payload ->> 'error' like 'the email provider refused%'), null;

-- outcomes by hand
set local role authenticated;
select pg_temp.admin();
do $x$ declare x jsonb; e text; begin
  e := pg_temp.err(format($q$select b2b.allocation_outcome_manual(%s, 'flying')$q$, pg_temp.v('A')));
  insert into r values ('outcome_stage_checked', e like '22023 unknown stage flying%', e);
  e := pg_temp.err(format($q$select b2b.allocation_outcome_manual(%s, 'lost')$q$, pg_temp.v('A')));
  insert into r values ('outcome_lost_needs_reason', e like '22023 give the reason%', e);
  x := b2b.allocation_outcome_manual(pg_temp.v('A')::bigint, 'contacted', 'connected, interested', 'spoke to the counsellor on the phone');
  insert into r values ('outcome_contacted', x ->> 'result' like 'stage contacted%', x::text);
  x := b2b.allocation_outcome_manual(pg_temp.v('A')::bigint, 'applied', null, null);
  insert into r values ('outcome_applied', x ->> 'result' like 'stage applied%', x::text);
end $x$;
reset role;
insert into r select 'outcome_applied_to_lead', l.stage = 'applied' and exists (select 1 from b2b.partner_activities pa where pa.allocation_id = pg_temp.v('A')::bigint and pa.kind = 'stage_change' and pa.outcome = 'contacted' and pa.raw ->> 'source' = 'admin')
  and exists (select 1 from b2b.events where type = 'partner.outcome_manual' and allocation_id = pg_temp.v('A')::bigint), l.stage
  from public.student_leads l where l.id = pg_temp.v('L')::bigint;
set local role authenticated;
select pg_temp.admin();
insert into t select 'LOST', b2b.allocation_outcome_manual(pg_temp.v('A')::bigint, 'lost', null, 'they chose another university', 'joined elsewhere')::text;
reset role;
insert into r select 'outcome_lost_grace', (pg_temp.v('LOST')::jsonb ->> 'result') like 'lost:%' and (select lost_at is not null from b2b.allocations where id = pg_temp.v('A')::bigint), pg_temp.v('LOST');
insert into r select 'outcome_not_held', pg_temp.err(format($q$select b2b.allocation_outcome_manual(%s, 'contacted')$q$, (select max(id) from b2b.allocations where lead_id = pg_temp.v('L2')::bigint))) like '22023 the partner does not hold%', null;
select name, ok, detail from r order by ok, name;
rollback;
