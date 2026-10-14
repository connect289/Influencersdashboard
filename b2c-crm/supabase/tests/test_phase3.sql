-- Phase 3 (Money and analytics) checks, rolled back. Every row of the final select must say ok = true.
-- LOCAL COPY ONLY (supabase/tests/local_stubs.sql, then the migrations): the money checks need fixtures in the
-- catalogue (public.catalog_*) and the partner tables (b2b.*), which on staging belong to the B2B CRM and must not be
-- written, not even in a rolled-back transaction. Test phones 9190000000NN only.
begin;
do $g$ begin
  if current_database() <> 'b2c_fresh' then
    raise exception 'test_phase3 writes catalogue and partner fixtures: run it on a local copy (README → Checks), never on staging';
  end if;
end $g$;
create temp table r (n serial, name text, ok boolean, detail text);
grant all on r to authenticated, service_role;
grant usage, select on sequence r_n_seq to authenticated, service_role;

-- ---------- people ----------
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-00000000d001', 'admin.p3@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000d002', 'priya.p3@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000d003', 'rohan.p3@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000d004', 'head.p3@eduwit.in', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-00000000d005', 'sneha.p3@eduwit.in', 'authenticated', 'authenticated');
insert into b2c.users (user_id, email, full_name, role, is_active, is_test_user, languages, takes_leads, monthly_target) values
  ('aaaaaaaa-0000-0000-0000-00000000d001', 'admin.p3@eduwit.in', 'P3 Admin', 'admin', true, false, '{English}', false, '{}'),
  ('aaaaaaaa-0000-0000-0000-00000000d002', 'priya.p3@eduwit.in', 'Priya P3', 'counsellor', true, true, '{English}', true, '{"enrollments": 5, "commission": 60000, "calls": 100}'),
  ('aaaaaaaa-0000-0000-0000-00000000d003', 'rohan.p3@eduwit.in', 'Rohan P3', 'counsellor', true, true, '{English}', true, '{"enrollments": 4}'),
  ('aaaaaaaa-0000-0000-0000-00000000d004', 'head.p3@eduwit.in', 'Head P3', 'sales_head', true, true, '{English}', false, '{}'),
  ('aaaaaaaa-0000-0000-0000-00000000d005', 'sneha.p3@eduwit.in', 'Sneha P3', 'marketing', true, false, '{English}', false, '{}');
create function pg_temp.as_user(p uuid) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated', 'session_id', ('bbbbbbbb-0000-0000-0000-' || right(p::text, 12))::uuid)::text, true);
end $f$;
create function pg_temp.as_system() returns void language plpgsql as $f$ begin perform set_config('request.jwt.claims', '', true); end $f$;
insert into b2c.session_checks (session_id, user_id, method)
select ('bbbbbbbb-0000-0000-0000-' || right(user_id::text, 12))::uuid, user_id, 'email_code' from b2c.users where email like '%.p3@eduwit.in' on conflict do nothing;
create function pg_temp.env(p_id text, p_type text, p_lead bigint, p_data jsonb) returns jsonb language sql as $f$
  select jsonb_build_object('id', p_id, 'type', p_type, 'lead_id', p_lead, 'occurred_at', now(), 'test', true, 'contract_version', 3, 'data', p_data)
$f$;
create function pg_temp.lead(p_lead bigint, p_name text, p_course text, p_owner uuid, p_extra jsonb default '{}') returns void language plpgsql as $f$
begin
  perform b2c.handoff_receive(pg_temp.env('p3-rec-' || p_lead, 'b2c.lead_upserted', p_lead, jsonb_build_object('version', 1, 'record',
    jsonb_build_object('id', p_lead, 'is_test', true, 'held_by_b2c', true, 'contract_version', 3,
      'student', jsonb_build_object('name', p_name, 'phone', '91900000' || right(p_lead::text, 4), 'email', lower(replace(p_name, ' ', '.')) || '@example.in', 'city', 'Pune', 'state', 'Maharashtra'),
      'education', jsonb_build_object('highest_qualification', 'B.Com'), 'interest', jsonb_build_object('course', p_course, 'university', 'Jain Online'),
      'consent', jsonb_build_object('state', 'given', 'opted_out', false), 'source', jsonb_build_object('lead_source', 'meta_lead_ad')) || p_extra)));
  perform b2c.handoff_receive(pg_temp.env('p3-ho-' || p_lead, 'b2c.lead_handed_off', p_lead, '{"b2c_lane":"sales","reason":"fallback"}'));
  perform b2c.assign(p_lead, p_owner, null, 'manual', 'phase 3 test');
end $f$;
create function pg_temp.enrol(p_lead bigint, p_uni text, p_prog text, p_fee numeric, p_on date) returns bigint language plpgsql as $f$
declare v bigint;
begin
  perform pg_temp.as_user((select owner_id from b2c.leads_state where lead_id = p_lead));
  v := b2c.enrollment_record(jsonb_build_object('lead_id', p_lead, 'university', p_uni, 'programme', p_prog, 'fee', p_fee, 'fee_paid', p_fee, 'enrolled_on', p_on,
                                                'proof_path', 'leads/' || p_lead || '/receipt.pdf'));
  perform pg_temp.as_system();
  return v;
end $f$;
create function pg_temp.line(p_enrollment bigint) returns b2c.commission_lines language sql as $f$
  select * from b2c.commission_lines where enrollment_id = p_enrollment and kind = 'booking' and status <> 'void' order by id desc limit 1
$f$;
create temp table en (k text primary key, id bigint);
grant all on en to authenticated, service_role;

-- ---------- fixtures: the catalogue and the partners (local copy only) ----------
update public.catalog_programs set fee_yearly = case id when 11 then 90000 when 12 then 80000 when 13 then 40000 end where id in (11, 12, 13);
insert into public.catalog_universities (id, name, short_name) values (3, 'Test Open University', 'TOU');
insert into public.catalog_programs (id, university_id, level, course, program_name, mode, fee_yearly, fee_total, active) values (14, 3, 'PG', 'MA', 'Online MA', 'Online', 50000, 100000, true);
insert into b2b.partners (id, slug, name, status) values (901, 'pa', 'Partner A', 'active'), (902, 'pb', 'Partner B', 'active'), (903, 'pc', 'Partner C', 'closed');
insert into b2b.partner_programmes (partner_id, programme_id) values (901, 11), (902, 11), (903, 11), (901, 12);
insert into b2b.rates (scope, partner_id, programme_id, rate_type, fee_base, value, valid_from) values
  ('partner', 901, null, 'percent', 'first_year', 20, '2026-01-01'),
  ('partner_programme', 902, 11, 'percent', 'first_year', 25, '2026-01-01'),
  ('partner', 902, null, 'percent', 'first_year', 15, '2026-01-01'),
  ('partner', 903, null, 'percent', 'first_year', 50, '2026-01-01');
update b2c.settings set value = value || '{"eduwit_gstin": "07AABCE1234F1Z5", "eduwit_state_code": "07", "eduwit_address": "New Delhi"}' where key = 'money';

-- ---------- rates and rights ----------
do $x$
declare e text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d005');     -- Marketing reads money, changes nothing
  begin perform b2c.university_rate_save('{"university_id":1,"rate_type":"percent","value":20,"valid_from":"2026-01-01","note":"agreement"}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('marketing_cannot_set_rates', e = 'not allowed', e);
  insert into r (name, ok, detail) values ('marketing_reads_money', (b2c.money_admin() ->> 'from') is not null, null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  begin perform b2c.money_admin(); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('counsellor_cannot_read_company_money', e = 'not allowed', e);
  begin perform b2c.my_commission('{"user_id":"aaaaaaaa-0000-0000-0000-00000000d003"}'); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('counsellor_cannot_read_anothers_commission', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  perform b2c.university_rate_save('{"university_id":1,"rate_type":"percent","fee_base":"first_year","value":20,"gst_inclusive":true,"valid_from":"2026-01-01","note":"Amity agreement 2026"}');
  perform b2c.university_rate_save('{"university_id":2,"rate_type":"tiered","fee_base":"first_year","gst_inclusive":true,"valid_from":"2026-01-01","note":"Jain agreement 2026",
    "tiers":[{"from":0,"to":7,"value":22.42},{"from":7,"to":9,"value":20.42},{"from":9,"value":18.42}]}');
  perform b2c.university_rate_save('{"university_id":3,"rate_type":"fixed","value":10000,"gst_inclusive":false,"valid_from":"2026-01-01","note":"TOU letter"}');
  perform b2c.university_billing_save('{"university_id":1,"legal_name":"Amity Online Ltd","gstin":"07AAACA1234B1Z2","state_code":"07","address":"Noida","refund_days":30}');
  perform b2c.university_billing_save('{"university_id":2,"legal_name":"Jain Online","gstin":"29AAACJ1234B1Z2","state_code":"29","address":"Bengaluru"}');
  perform b2c.commission_override_save('{"counsellor_id":"aaaaaaaa-0000-0000-0000-00000000d002","programme_id":12,"rate_type":"percent","value":10,"valid_from":"2026-09-15","reason":"agreed for Jain MBA from 15 Sep"}');
  perform pg_temp.as_system();
end $x$;

-- ---------- September: seven enrollments ----------
do $x$
begin
  perform pg_temp.lead(900041, 'Asha Test', 'MBA', 'aaaaaaaa-0000-0000-0000-00000000d002');
  perform pg_temp.lead(900042, 'Bina Test', 'MBA', 'aaaaaaaa-0000-0000-0000-00000000d002');
  perform pg_temp.lead(900043, 'Chetan Test', 'BBA', 'aaaaaaaa-0000-0000-0000-00000000d003');
  perform pg_temp.lead(900044, 'Dev Test', 'MA', 'aaaaaaaa-0000-0000-0000-00000000d003');
  perform pg_temp.lead(900045, 'Esha Test', 'MBA', 'aaaaaaaa-0000-0000-0000-00000000d003');
  perform pg_temp.lead(900046, 'Farah Test', 'MBA', 'aaaaaaaa-0000-0000-0000-00000000d002');
  perform pg_temp.lead(900047, 'Gita Test', 'MBA', 'aaaaaaaa-0000-0000-0000-00000000d002');
  insert into en values ('e1', pg_temp.enrol(900041, 'Amity University Online', 'Online MBA', 179000, '2026-09-02'));
  insert into en values ('e2', pg_temp.enrol(900042, 'Jain Online', 'Online MBA', 160000, '2026-09-05'));
  insert into en values ('e3', pg_temp.enrol(900043, 'Jain', 'Online BBA', 120000, '2026-09-08'));
  insert into en values ('e4', pg_temp.enrol(900044, 'Test Open University', 'Online MA', 100000, '2026-09-10'));
  insert into en values ('e5', pg_temp.enrol(900045, 'Amity University Online', 'Online MBA', 179000, '2026-09-20'));
  insert into en values ('e6', pg_temp.enrol(900046, 'Jain Online', 'Online MBA', 160000, '2026-09-16'));
  -- Partner B raises its Amity MBA rate from 21 Sep: e1 keeps its booked rate, e7 uses the new one
  insert into b2b.rates (scope, partner_id, programme_id, rate_type, fee_base, value, valid_from) values ('partner_programme', 902, 11, 'percent', 'first_year', 30, '2026-09-21');
  insert into en values ('e7', pg_temp.enrol(900047, 'Amity University Online', 'Online MBA', 179000, '2026-09-25'));
end $x$;

do $x$
declare l b2c.commission_lines; j jsonb;
begin
  insert into r (name, ok, detail) values ('catalogue_ids_resolved', (select bool_and(university_id is not null and programme_id is not null) from b2c.enrollments where id in (select id from en)),
    (select string_agg(id || ':' || coalesce(university_id::text, '-') || '/' || coalesce(programme_id::text, '-'), ' ') from b2c.enrollments where id in (select id from en)));
  l := pg_temp.line((select id from en where k = 'e1'));
  insert into r (name, ok, detail) values ('several_partners_highest', l.amount = 22500 and l.rate_source = 'partner' and l.status = 'provisional'
    and jsonb_array_length(l.snapshot -> 'partners') = 2 and (l.snapshot -> 'used' ->> 'partner_id')::int = 902, l.amount || ' ' || (l.snapshot -> 'partners')::text);
  j := b2c.commission_line_json(l.id);
  insert into r (name, ok, detail) values ('line_shows_programme_partners_rate', j ->> 'programme' = 'Online MBA' and jsonb_array_length(j -> 'partners') = 2
    and (j -> 'rate' ->> 'pct')::numeric = 25 and (j -> 'rate' ->> 'base')::numeric = 90000 and j -> 'partners' -> 0 ? 'rate', j::text);
  l := pg_temp.line((select id from en where k = 'e2'));
  insert into r (name, ok, detail) values ('one_partner', l.amount = 16000 and l.rate_source = 'partner' and jsonb_array_length(l.snapshot -> 'partners') = 1, l.amount::text);
  l := pg_temp.line((select id from en where k = 'e3'));
  insert into r (name, ok, detail) values ('no_programme_partner_uses_university_highest', l.amount = 8000 and l.rate_source = 'university_highest' and l.flagged, l.amount || ' ' || l.rate_source);
  l := pg_temp.line((select id from en where k = 'e4'));
  insert into r (name, ok, detail) values ('no_partner_needs_rate', l.amount is null and l.status = 'needs_rate'
    and exists (select 1 from b2c.notifications where user_id = 'aaaaaaaa-0000-0000-0000-00000000d001' and title = 'Commission needs a rate'), l.status);
  l := pg_temp.line((select id from en where k = 'e6'));
  insert into r (name, ok, detail) values ('override_applies_and_shows', l.amount = 8000 and l.rate_source = 'override' and l.snapshot -> 'override' ->> 'reason' like 'agreed%'
    and jsonb_array_length(l.snapshot -> 'partners') = 1, l.amount || ' ' || l.rate_source);
  l := pg_temp.line((select id from en where k = 'e7'));
  insert into r (name, ok, detail) values ('later_rate_used_for_later_enrollment', l.amount = 27000, l.amount::text);
  insert into r (name, ok, detail) values ('rate_change_keeps_booked_line', (pg_temp.line((select id from en where k = 'e1'))).amount = 22500, null);
  -- university side: provisional tier at booking (nothing verified yet: the lowest bracket, 22.42%)
  insert into r (name, ok, detail) values ('university_booked_expected', (select count(*) from b2c.earnings where enrollment_id in (select id from en) and kind = 'booking' and realised_at is null) = 7
    and (select gross from b2c.earnings where enrollment_id = (select id from en where k = 'e1')) = 18000
    and (select net from b2c.earnings where enrollment_id = (select id from en where k = 'e1')) = 15254.24
    and (select gross from b2c.earnings where enrollment_id = (select id from en where k = 'e2')) = 17936
    and (select gross from b2c.earnings where enrollment_id = (select id from en where k = 'e4')) = 11800
    and (select net from b2c.earnings where enrollment_id = (select id from en where k = 'e4')) = 10000,
    (select string_agg(enrollment_id || ':' || gross || '/' || net, ' ' order by enrollment_id) from b2c.earnings where enrollment_id in (select id from en)));
  begin
    update b2c.earnings set gross = 1 where enrollment_id = (select id from en where k = 'e1');
    insert into r (name, ok, detail) values ('ledger_refuses_edits', false, 'edited');
  exception when others then
    insert into r (name, ok, detail) values ('ledger_refuses_edits', sqlerrm like '%ledger%', sqlerrm);
  end;
end $x$;

-- ---------- verification, fallback, adjustment ----------
do $x$
declare n int; e text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  perform b2c.enrollment_verify(id, true) from en where k in ('e1', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7');
  n := b2c.commission_fallback_save('{"university_id":3,"rate_type":"percent","fee_base":"first_year","value":10,"reason":"Admin rate until a partner offers TOU"}');
  insert into r (name, ok, detail) values ('fallback_books_waiting_line', n = 1 and (pg_temp.line((select id from en where k = 'e4'))).amount = 5000
    and (pg_temp.line((select id from en where k = 'e4'))).rate_source = 'fallback' and (pg_temp.line((select id from en where k = 'e4'))).status = 'due', n::text);
  perform b2c.commission_adjust((select id from en where k = 'e2'), -1000, 'agreed discount on a hard case');
  begin perform b2c.commission_adjust((select id from en where k = 'e2'), 500, ''); e := 'ok'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('adjustment_needs_reason', e like 'give the reason%', e);
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('verified_moves_status', (pg_temp.line((select id from en where k = 'e1'))).status = 'due'
    and (pg_temp.line((select id from en where k = 'e6'))).status = 'confirmed'
    and (select bool_and(realised_at is not null) from b2c.earnings where enrollment_id in (select id from en)),
    (pg_temp.line((select id from en where k = 'e1'))).status || '/' || (pg_temp.line((select id from en where k = 'e6'))).status);
end $x$;

-- ---------- refunds ----------
do $x$
declare j jsonb;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  j := b2c.enrollment_refund((select id from en where k = 'e5'), '2026-10-01', 'student withdrew in week two');
  insert into r (name, ok, detail) values ('refund_inside_window_before_settlement', (j ->> 'inside_window')::boolean
    and (select sum(gross) from b2c.earnings where enrollment_id = (select id from en where k = 'e5')) = 0
    and (select bool_and(status = 'void') from b2c.commission_lines where enrollment_id = (select id from en where k = 'e5'))
    and (select sum(amount) from b2c.commission_lines where enrollment_id = (select id from en where k = 'e5')) = 0, j::text);
  j := b2c.enrollment_refund((select id from en where k = 'e7'), '2026-11-30', 'refund after the window');
  insert into r (name, ok, detail) values ('refund_outside_window_keeps_commission', not (j ->> 'inside_window')::boolean
    and (select sum(gross) from b2c.earnings where enrollment_id = (select id from en where k = 'e7')) = 18000
    and (pg_temp.line((select id from en where k = 'e7'))).amount = 27000, j::text);
  perform pg_temp.as_system();
end $x$;

-- ---------- period close (tiers) ----------
do $x$
declare j jsonb; e text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  begin perform b2c.period_close(2, date_trunc('month', current_date)::date); e := 'closed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('current_month_cannot_close', e like 'a month can be closed%', e);
  j := b2c.period_close(2, '2026-09-01', 40);     -- 3 verified of 40 leads = 7.5%: the 20.42% tier
  insert into r (name, ok, detail) values ('tier_settled_at_close', (j ->> 'conversion')::numeric = 7.5 and (j ->> 'adjustments')::int = 3
    and (select sum(gross) from b2c.earnings where university_id = 2 and period = '2026-09-01') = 40840
    and (select gross from b2c.earnings where enrollment_id = (select id from en where k = 'e3') and kind = 'tier_adjust') = -800, j::text);
  begin perform b2c.period_close(2, '2026-09-01', 40); e := 'closed'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('close_once', e = 'this month is already closed', e);
  perform pg_temp.as_system();
end $x$;

-- ---------- the month matches a manual check ----------
insert into r (name, ok, detail)
select 'university_month_matches_manual', bool_and(ok), string_agg(detail, '; ') from (
  select (select sum(gross) from b2c.earnings where university_id = u and period = '2026-09-01') = expect as ok,
         u || ': ' || (select sum(gross) from b2c.earnings where university_id = u and period = '2026-09-01') || ' vs ' || expect as detail
    from (values (1, 36000.00), (2, 40840.00), (3, 11800.00)) v(u, expect)) s;   -- Amity: e1 + e7 (e5 refunded); Jain: 16336 + 8168 + 16336; TOU: 10000 + 18% GST
insert into r (name, ok, detail)
select 'counsellor_month_matches_manual',
       (select sum(amount) from b2c.commission_lines where counsellor_id = 'aaaaaaaa-0000-0000-0000-00000000d002' and status <> 'void') = 72500     -- 22500 + 16000 - 1000 + 8000 + 27000
   and (select sum(amount) from b2c.commission_lines where counsellor_id = 'aaaaaaaa-0000-0000-0000-00000000d003' and status <> 'void') = 13000,    -- 8000 + 5000
       (select string_agg(counsellor_id::text || '=' || s, ' ') from (select counsellor_id, sum(amount) s from b2c.commission_lines where status <> 'void' and lead_id between 900041 and 900047 group by 1) x);

-- ---------- the run, then a clawback ----------
do $x$
declare v bigint; j jsonb; e text;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  v := b2c.commission_run_prepare('2026-09-01', true);
  j := b2c.commission_run_view(v);
  insert into r (name, ok, detail) values ('run_takes_due_lines', (j -> 'totals' ->> 'amount')::numeric = 50500 and jsonb_array_length(j -> 'counsellors') = 2
    and (select (x ->> 'amount')::numeric from jsonb_array_elements(j -> 'counsellors') x where x ->> 'name' = 'Priya P3') = 37500, j -> 'totals' ->> 'amount');
  begin perform b2c.commission_run_prepare('2026-09-01', true); e := 'made'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('one_draft_run', e like 'finish or cancel%', e);
  j := b2c.commission_run_approve(v);
  insert into r (name, ok, detail) values ('run_settles', (select count(*) from b2c.commission_lines where run_id = v and status <> 'settled') = 0, j::text);
  j := b2c.enrollment_refund((select id from en where k = 'e1'), '2026-10-01', 'refund inside the window after settlement');
  insert into r (name, ok, detail) values ('clawback_after_settlement', exists (select 1 from b2c.commission_lines where enrollment_id = (select id from en where k = 'e1')
    and kind = 'clawback' and amount = -22500 and status = 'due' and run_id is null)
    and (select status from b2c.commission_lines where enrollment_id = (select id from en where k = 'e1') and kind = 'booking') = 'settled', j::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  j := b2c.commission_statement(v);
  insert into r (name, ok, detail) values ('counsellor_statement', (j ->> 'amount')::numeric = 37500 and jsonb_array_length(j -> 'lines') = 3, j ->> 'amount');
  j := b2c.my_commission();
  insert into r (name, ok, detail) values ('counsellor_dashboard', jsonb_array_length(j -> 'lines') >= 5 and (j -> 'target' ->> 'commission')::numeric = 60000
    and jsonb_array_length(j -> 'statements') = 0, (j -> 'tiles')::text);   -- the run was a test run: no real statement
  perform pg_temp.as_system();
end $x$;

-- ---------- invoice, receipt with TDS, statement ----------
do $x$
declare v bigint; v_num text; j jsonb;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  v := b2c.invoice_draft(2, null, true);
  insert into r (name, ok, detail) values ('invoice_draft_from_realised', (select gross from b2c.invoices where id = v) = 40840
    and (select count(*) from b2c.invoice_lines where invoice_id = v) = 6 and (select supply from b2c.invoices where id = v) = 'inter',
    (select gross || ' ' || supply from b2c.invoices where id = v));
  v_num := b2c.invoice_approve(v, '2026-10-05');
  insert into r (name, ok, detail) values ('invoice_number_gapless', v_num = 'TEST-EDW/2026-27/0001' and b2c.invoice_approve(b2c.invoice_draft(1, null, true), '2026-10-05') = 'TEST-EDW/2026-27/0002', v_num);
  j := b2c.receipt_record(jsonb_build_object('university_id', 2, 'amount', 36756, 'tds', 4084, 'reference', 'UTR-P3-1', 'received_on', '2026-10-12'));
  insert into r (name, ok, detail) values ('receipt_with_tds_settles_invoice', (select status from b2c.invoices where id = v) = 'paid' and (j ->> 'unallocated')::numeric = 0, j::text);
  j := b2c.statement_import(jsonb_build_object('university_id', 2, 'period_from', '2026-09-01', 'period_to', '2026-09-30', 'file_name', 'jain-sep.csv', 'rows', jsonb_build_array(
         jsonb_build_object('ref', (select id from en where k = 'e2')::text, 'student', 'Bina Test', 'amount', 16336),
         jsonb_build_object('ref', '', 'student', 'Chetan Test', 'programme', 'Online BBA', 'amount', 8000),
         jsonb_build_object('ref', '', 'student', 'Ghost Student', 'amount', 5000))));
  insert into r (name, ok, detail) values ('statement_four_piles', (j ->> 'matched')::int = 1 and (j ->> 'mismatch')::int = 1 and (j ->> 'university_only')::int = 1 and (j ->> 'eduwit_only')::int = 1,
    (j - 'rows' - 'eduwit_only_rows')::text);
  perform pg_temp.as_system();
end $x$;

-- ---------- daily job, partner-rate watch, published view ----------
do $x$
declare j jsonb;
begin
  j := b2c.money_tick();      -- first run notes the partner rates as they are
  insert into b2b.rates (scope, partner_id, rate_type, fee_base, value, valid_from) values ('partner', 901, 'percent', 'first_year', 22, '2026-10-20');
  j := b2c.money_tick();
  insert into r (name, ok, detail) values ('partner_rate_change_noticed', (j ->> 'rate_changes')::int = 1 and exists (select 1 from b2c.events where type = 'money.partner_rate_changed'), j::text);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d005');
  j := b2c.partner_rate_table(null);
  insert into r (name, ok, detail) values ('partner_rate_table', (select jsonb_array_length(x -> 'partners') from jsonb_array_elements(j -> 'rows') x where (x ->> 'programme_id')::int = 11) = 2, null);
  perform pg_temp.as_system();
end $x$;
insert into r (name, ok, detail) values ('published_view_for_b2b', has_table_privilege('service_role', 'public.b2c_enrollment_money_v', 'select')
  and not has_table_privilege('authenticated', 'public.b2c_enrollment_money_v', 'select') and not has_table_privilege('anon', 'public.b2c_enrollment_money_v', 'select')
  and (select count(*) from public.b2c_enrollment_money_v where lead_id between 900041 and 900047) = 0, 'test leads never reach B2B');

-- ---------- team performance ----------
do $x$
declare j jsonb; e text;
begin
  insert into b2c.calls (lead_id, user_id, number, tapped_at, logged_at, outcome) values
    (900042, 'aaaaaaaa-0000-0000-0000-00000000d002', '919000000042', now() - interval '2 hours', now() - interval '2 hours', 'no_answer'),
    (900042, 'aaaaaaaa-0000-0000-0000-00000000d002', '919000000042', now() - interval '1 hour', now() - interval '1 hour', 'connected'),
    (900043, 'aaaaaaaa-0000-0000-0000-00000000d003', '919000000043', now() - interval '3 hours', null, null);
  update b2c.calls set unlogged_flagged_at = now() where lead_id = 900043 and logged_at is null;
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  perform b2c.target_save('aaaaaaaa-0000-0000-0000-00000000d002', current_date, '{"calls": 120, "connected": 40, "enrollments": 6, "commission": 90000}');
  j := b2c.activity_monitor('{}');
  insert into r (name, ok, detail) values ('activity_monitor', (select (x ->> 'calls')::int = 2 and (x ->> 'connected')::int = 1 from jsonb_array_elements(j -> 'rows') x where x ->> 'name' = 'Priya P3')
    and (select (x ->> 'unlogged_calls')::int from jsonb_array_elements(j -> 'rows') x where x ->> 'name' = 'Rohan P3') = 1, null);
  j := b2c.capacity();
  insert into r (name, ok, detail) values ('capacity_panel', j ? 'hiring' and j ? 'rows', null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  j := b2c.my_progress();
  insert into r (name, ok, detail) values ('target_progress', (j -> 'target' ->> 'calls')::int = 120 and (j -> 'actual' ->> 'calls')::int = 2 and (j -> 'actual' ->> 'connected')::int = 1, j::text);
  j := b2c.leaderboard();
  insert into r (name, ok, detail) values ('leaderboard_hides_names_until_opt_in', (select bool_and(x ->> 'name' = 'A counsellor') from jsonb_array_elements(j -> 'rows') x where not (x ->> 'me')::boolean)
    and (select count(*) from jsonb_array_elements(j -> 'rows') x where (x ->> 'me')::boolean and x ->> 'name' = 'Priya P3') = 1, null);
  begin perform b2c.activity_monitor('{}'); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('counsellor_cannot_monitor', e = 'not allowed', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d003');
  perform b2c.leaderboard_opt(true);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  j := b2c.leaderboard();
  insert into r (name, ok, detail) values ('leaderboard_opt_in_shows_name', exists (select 1 from jsonb_array_elements(j -> 'rows') x where x ->> 'name' = 'Rohan P3'), null);
  perform pg_temp.as_system();
end $x$;

-- ---------- analytics: facts, scope, drill-down ----------
do $x$
declare j jsonb; e text; m record; v numeric; ids bigint[]; bad text := ''; xr jsonb; dr jsonb; spec jsonb;
begin
  perform b2c.facts_refresh();
  insert into r (name, ok, detail) values ('facts_built', (select count(*) from b2c.fact_leads where lead_id between 900041 and 900047 and is_test and enrolled_on is not null) = 7,
    (select count(*) from b2c.fact_leads where lead_id between 900041 and 900047)::text);
  spec := jsonb_build_object('metrics', jsonb_build_array('enrollments'), 'from', '2026-09-01', 'to', '2026-09-30', 'test', true);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  j := b2c.analytics_run(spec);
  insert into r (name, ok, detail) values ('analytics_counts', (j -> 'rows' -> 0 ->> 'enrollments')::int = 4 and jsonb_array_length(j -> 'sql') = 1, j::text);
  dr := b2c.analytics_drill(spec, 'enrollments', '{}');
  insert into r (name, ok, detail) values ('drill_matches_number', (dr ->> 'count')::int = 4
    and (b2c.lead_list(jsonb_build_object('drill', dr ->> 'drill_id', 'limit', 50)) ->> 'total')::int = 4, dr::text);
  j := b2c.analytics_run(spec || '{"dims": ["counsellor"]}');
  dr := b2c.analytics_drill(spec, 'enrollments', '{"counsellor": "Priya P3"}');
  insert into r (name, ok, detail) values ('drill_by_cell', (select (x ->> 'enrollments')::int from jsonb_array_elements(j -> 'rows') x where x -> 'k' ->> 0 = 'Priya P3') = 2
    and (dr ->> 'count')::int = 2, j::text);
  -- every lead-count metric the Admin can use, overall and by counsellor: the drill-down has exactly as many leads
  for m in select key from b2c.metric_defs where counts_leads and 'admin' = any (roles) loop
    spec := jsonb_build_object('metrics', jsonb_build_array(m.key), 'from', '2026-08-01', 'to', current_date, 'test', true);
    v := coalesce((b2c.analytics_run(spec) -> 'rows' -> 0 ->> m.key)::numeric, 0);
    ids := b2c.analytics_drill_ids('aaaaaaaa-0000-0000-0000-00000000d001', 'admin', spec, m.key, '{}');
    if coalesce(array_length(ids, 1), 0) <> v then bad := bad || m.key || ' ' || v || '/' || coalesce(array_length(ids, 1), 0) || '; '; end if;
    for xr in select * from jsonb_array_elements(b2c.analytics_run(spec || '{"dims": ["counsellor"]}') -> 'rows') loop
      ids := b2c.analytics_drill_ids('aaaaaaaa-0000-0000-0000-00000000d001', 'admin', spec, m.key, jsonb_build_object('counsellor', xr -> 'k' ->> 0));
      if coalesce(array_length(ids, 1), 0) <> coalesce((xr ->> m.key)::numeric, 0) then bad := bad || m.key || '@' || coalesce(xr -> 'k' ->> 0, 'none') || '; '; end if;
    end loop;
  end loop;
  insert into r (name, ok, detail) values ('every_lead_number_drills_to_its_leads', bad = '', bad);
  -- every standard widget runs for the roles it is published to
  bad := '';
  for m in select d.key, w as widget, unnest(d.roles) as g from b2c.dashboards d, jsonb_array_elements(d.widgets) w where d.owner_id is null loop
    continue when m.widget ->> 'viz' = 'text';
    begin
      perform b2c.analytics_exec(case m.g when 'admin' then 'aaaaaaaa-0000-0000-0000-00000000d001'::uuid when 'marketing' then 'aaaaaaaa-0000-0000-0000-00000000d005'::uuid
                                          else 'aaaaaaaa-0000-0000-0000-00000000d002'::uuid end,
                                 case m.g when 'admin' then 'admin' when 'marketing' then 'marketing' else 'counsellor' end, (m.widget -> 'spec') || '{"test": true}');
    exception when others then bad := bad || m.key || '/' || (m.widget ->> 'id') || ': ' || sqlerrm || '; ';
    end;
  end loop;
  insert into r (name, ok, detail) values ('standard_widgets_run', bad = '', bad);
  -- a counsellor gets only their own leads, whatever the spec says
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  spec := jsonb_build_object('metrics', jsonb_build_array('enrollments', 'assigned'), 'dims', jsonb_build_array('counsellor'), 'from', '2026-08-01', 'to', current_date, 'test', true);
  j := b2c.analytics_run(spec);
  insert into r (name, ok, detail) values ('sales_sees_only_own', (select bool_and(x -> 'k' ->> 0 = 'Priya P3') from jsonb_array_elements(j -> 'rows') x) and j ->> 'scope' = 'own leads', j::text);
  j := b2c.analytics_run(spec || '{"filters": [{"dim": "counsellor", "op": "eq", "value": "Rohan P3"}]}');
  insert into r (name, ok, detail) values ('sales_spec_naming_another_returns_nothing', jsonb_array_length(j -> 'rows') = 0, j::text);
  dr := b2c.analytics_drill(spec - 'dims', 'assigned', '{"counsellor": "Rohan P3"}');
  insert into r (name, ok, detail) values ('sales_drill_into_another_is_empty', (dr ->> 'count')::int = 0, dr::text);
  begin perform b2c.analytics_run('{"metrics": ["uni_expected"]}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('sales_cannot_use_company_money', e like 'metric uni_expected is not available%', e);
  begin perform b2c.analytics_run('{"metrics": ["enrollments"], "filters": [{"dim": "counsellor", "op": "eq", "value": "x'') or true or (''"}]}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('filter_values_are_quoted', e = 'ran', e);
  begin perform b2c.analytics_run('{"metrics": ["enrollments"], "dims": ["f.owner_id"]}'); e := 'ran'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('spec_names_keys_never_sql', e like 'unknown dimension%', e);
  j := b2c.analytics_catalog();
  insert into r (name, ok, detail) values ('sales_catalogue_has_no_company_money', not exists (select 1 from jsonb_array_elements(j -> 'metrics') x where x ->> 'key' like 'uni_%')
    and j ->> 'scope' = 'own leads', null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d004');      -- sales head: the team
  j := b2c.analytics_run(spec);
  insert into r (name, ok, detail) values ('sales_head_sees_team', (select count(distinct x -> 'k' ->> 0) from jsonb_array_elements(j -> 'rows') x) = 2 and j ->> 'scope' = 'team', j::text);
  perform pg_temp.as_system();
end $x$;

-- ---------- dashboards, schedules, alerts ----------
do $x$
declare j jsonb; e text; v bigint; v2 bigint;
begin
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  j := b2c.dashboards_list();
  insert into r (name, ok, detail) values ('sales_standard_dashboards', (select count(*) from jsonb_array_elements(j -> 'standard')) = 5
    and not exists (select 1 from jsonb_array_elements(j -> 'standard') x where x ->> 'key' = 'admin_overview'), (j -> 'standard')::text);
  begin perform b2c.dashboard_get((select id from b2c.dashboards where key = 'admin_overview')); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('sales_cannot_open_admin_dashboard', e = 'not allowed', e);
  v := b2c.dashboard_save(jsonb_build_object('id', (select id from b2c.dashboards where key = 'my_funnel'), 'name', 'My funnel, my way'));
  insert into r (name, ok, detail) values ('editing_standard_makes_own_copy', v <> (select id from b2c.dashboards where key = 'my_funnel')
    and (select owner_id from b2c.dashboards where id = v) = 'aaaaaaaa-0000-0000-0000-00000000d002'
    and (select name from b2c.dashboards where key = 'my_funnel') = 'My funnel', null);
  begin perform b2c.dashboard_save(jsonb_build_object('id', v, 'widgets', jsonb_build_array(b2c.w('x', 'Money', 'kpi', '{uni_expected}')))); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('widget_checked_against_role', e like 'metric uni_expected is not available%', e);
  perform b2c.dashboard_home(v);
  begin perform b2c.dashboard_publish(v, '{sales}'); e := 'published'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('only_admin_publishes', e = 'not allowed', e);
  v2 := b2c.schedule_save(jsonb_build_object('dashboard_id', v, 'freq', 'weekly', 'format', 'pdf', 'hour_ist', 8, 'weekday', 1));
  insert into r (name, ok, detail) values ('schedule_next_is_monday_8', (select extract(isodow from next_at at time zone 'Asia/Kolkata') = 1 and extract(hour from next_at at time zone 'Asia/Kolkata') = 8
    and next_at > now() from b2c.dashboard_schedules where id = v2), null);
  perform b2c.alert_save('{"name": "No enrolments today", "metric": "enrollments", "kind": "threshold", "op": "below", "threshold": 1, "channels": ["push", "email"]}');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  v2 := b2c.dashboard_publish(v, '{sales}');
  insert into r (name, ok, detail) values ('admin_publishes_copy', (select owner_id is null and roles = '{sales}' from b2c.dashboards where id = v2), null);
  perform pg_temp.as_system();
  update b2c.dashboard_schedules set next_at = now() - interval '1 minute' where dashboard_id = v;
  j := b2c.schedules_take(5);
  insert into r (name, ok, detail) values ('schedules_take', jsonb_array_length(j) = 1 and (select next_at > now() from b2c.dashboard_schedules where dashboard_id = v), null);
  j := b2c.alerts_tick();
  insert into r (name, ok, detail) values ('alert_fires_once', (j ->> 'fired')::int = 1 and exists (select 1 from b2c.notifications where user_id = 'aaaaaaaa-0000-0000-0000-00000000d002' and kind = 'alert')
    and (select count(*) from b2c.alert_events) = 1, j::text);
  j := b2c.alert_emails_take(10);
  insert into r (name, ok, detail) values ('alert_email_queued', jsonb_array_length(j) = 1 and jsonb_array_length(b2c.alert_emails_take(10)) = 0, null);
  update b2c.metric_alerts set last_checked_at = null;
  j := b2c.alerts_tick();
  insert into r (name, ok, detail) values ('alert_not_twice_a_day', (j ->> 'fired')::int = 0, j::text);
  j := b2c.anomalies_tick();
  insert into r (name, ok, detail) values ('anomalies_tick_runs', j ? 'anomalies', j::text);
end $x$;

-- ---------- AI: the cap, the log, insights ----------
do $x$
declare j jsonb;
begin
  perform b2c.ai_log('{"purpose": "ask", "model": "claude-sonnet-5-5", "input_tokens": 1000, "output_tokens": 1000, "question": "Which lost sub-stage grew most?"}');
  insert into r (name, ok, detail) values ('ai_cost_logged', (select cost_inr from b2c.ai_calls order by id desc limit 1) = 1.53, (select cost_inr::text from b2c.ai_calls order by id desc limit 1));
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  insert into r (name, ok, detail) values ('ai_budget_allows', (b2c.ai_budget('ask') ->> 'allowed')::boolean, null);
  perform pg_temp.as_system();
  update b2c.settings set value = value || '{"daily_cap_inr": 1}' where key = 'ai';
  insert into r (name, ok, detail) values ('ai_cap_stops', not (b2c.ai_budget('ask') ->> 'allowed')::boolean, null);
  update b2c.settings set value = value || '{"daily_cap_inr": 500}' where key = 'ai';
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  j := b2c.insights_candidates(null);
  insert into r (name, ok, detail) values ('insight_candidates_are_aggregates', j ->> 'role_group' = 'admin' and jsonb_array_length(j -> 'candidates') >= 8
    and j::text !~ '9190000000' and j::text !~ '@example', null);
  perform pg_temp.as_system();
  perform b2c.insights_save('{"role_group": "admin", "items": [{"title": "Enrolments up", "body": "4 this week", "metric": "enrollments"}], "model": "claude-sonnet-5-5"}');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d005');
  insert into r (name, ok, detail) values ('insights_by_role', jsonb_array_length(b2c.insights_latest()) = 0, null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d001');
  insert into r (name, ok, detail) values ('insights_latest', jsonb_array_length(b2c.insights_latest()) = 1, null);
  perform pg_temp.as_system();
end $x$;

-- ---------- Brief before you call ----------
do $x$
declare j jsonb; t text; e text;
begin
  insert into public.w2_messages (phone, direction, kind, content, created_at) values
    ('919000000042', 'in', 'text', 'Hi, I want an online MBA under 2 lakh. My other number is +91 98765 43210 and email bina.home@gmail.com', now() - interval '3 days'),
    ('919000000042', 'out', 'text', 'Thanks Bina! Noted your budget.', now() - interval '3 days'),
    ('919000000042', 'in', 'text', 'Call me on 9876543210 after 6 pm, or write to bina (at) yahoo dot com. My own number 919000000042.', now() - interval '2 days');
  insert into b2c.activities (lead_id, kind, body, actor_id) values (900042, 'note', 'Father asked to call 98765-43210 instead', 'aaaaaaaa-0000-0000-0000-00000000d002');
  j := b2c.brief_input(900042);
  t := j::text;
  insert into r (name, ok, detail) values ('brief_input_has_no_phone_or_email', t !~ '98765' and t !~ '9876543210' and t !~ '919000000042' and t !~ '9000000042' and t !~ '@'
    and t !~ 'yahoo dot com' and t ~ '\[phone\]' and t ~ '\[email\]' and jsonb_array_length(j -> 'witty') = 3 and j -> 'facts' ->> 'first_name' = 'Bina', t);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  j := b2c.brief_get(900042);
  insert into r (name, ok, detail) values ('brief_missing_is_stale', (j ->> 'stale')::boolean, null);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d003');
  begin perform b2c.brief_get(900042); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('brief_only_for_who_may_see', e = 'not allowed', e);
  perform pg_temp.as_system();
  perform b2c.brief_save(jsonb_build_object('lead_id', 900042, 'model', 'claude-sonnet-5-5', 'facts_hash', b2c.brief_facts_hash(900042), 'lines', jsonb_build_array(
    jsonb_build_object('text', 'Bina wants an online MBA under ₹2 lakh.', 'source', 'witty:' || (select max(id) from public.w2_messages where phone = '919000000042' and content like 'Hi,%')),
    jsonb_build_object('text', 'Enrolled at Jain Online; a parent is involved.', 'source', 'activity:' || (select max(id) from b2c.activities where lead_id = 900042 and kind = 'note')))));
  begin perform b2c.brief_save('{"lead_id": 900042, "lines": [{"text": "made up", "source": "web:abc"}]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r (name, ok, detail) values ('brief_lines_need_sources', e like 'unknown source%', e);
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  insert into r (name, ok, detail) values ('brief_fresh_after_save', not (b2c.brief_get(900042) ->> 'stale')::boolean, null);
  perform pg_temp.as_system();
  insert into b2c.activities (lead_id, kind, outcome, body, actor_id) values (900042, 'call', 'connected', 'Discussed fees', 'aaaaaaaa-0000-0000-0000-00000000d002');
  perform pg_temp.as_user('aaaaaaaa-0000-0000-0000-00000000d002');
  insert into r (name, ok, detail) values ('brief_stale_after_new_call', (b2c.brief_get(900042) ->> 'stale')::boolean, null);
  perform pg_temp.as_system();
  insert into r (name, ok, detail) values ('brief_job_skips_test_leads', array_length(b2c.brief_due_take(10), 1) is null, null);
end $x$;

-- ---------- grants ----------
insert into r (name, ok, detail)
select 'authenticated_can_call', bool_and(has_function_privilege('authenticated', f, 'execute')), string_agg(f, ', ') filter (where not has_function_privilege('authenticated', f, 'execute'))
  from unnest(array['b2c.university_rate_save(jsonb)', 'b2c.invoice_draft(bigint,date,boolean)', 'b2c.receipt_record(jsonb)', 'b2c.statement_import(jsonb)', 'b2c.money_admin(jsonb)',
    'b2c.my_commission(jsonb)', 'b2c.commission_run_prepare(date,boolean)', 'b2c.enrollment_refund(bigint,date,text)', 'b2c.target_save(uuid,date,jsonb)', 'b2c.leaderboard(date)',
    'b2c.analytics_run(jsonb)', 'b2c.analytics_drill(jsonb,text,jsonb)', 'b2c.dashboard_save(jsonb)', 'b2c.alert_save(jsonb)', 'b2c.brief_get(bigint)', 'b2c.lead_list(jsonb)']) f;
insert into r (name, ok, detail)
select 'authenticated_cannot_call_internals', not bool_or(has_function_privilege('authenticated', f, 'execute')), string_agg(f, ', ') filter (where has_function_privilege('authenticated', f, 'execute'))
  from unnest(array['b2c.earning_book(bigint,text)', 'b2c.commission_book(bigint,text)', 'b2c.partner_rates_for(bigint)', 'b2c.money_tick()', 'b2c.analytics_exec(uuid,text,jsonb)',
    'b2c.analytics_run_for(uuid,jsonb)', 'b2c.facts_refresh(integer)', 'b2c.brief_input(bigint)', 'b2c.brief_save(jsonb)', 'b2c.ai_log(jsonb)', 'b2c.schedules_take(integer)',
    'b2c.alerts_tick()', 'b2c.scrub_pii(text,text[])', 'b2c.insights_save(jsonb)']) f;
insert into r (name, ok, detail)
select 'nothing_for_anon', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'b2c' and has_function_privilege('anon', p.oid, 'execute')), null;

select n, name, ok, case when ok then null else detail end as detail from r order by n;
rollback;
