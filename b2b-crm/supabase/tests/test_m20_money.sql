-- A3 fixture: the consent wording the test leads carry
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at) values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now()) on conflict (version) do nothing;
-- M20 money on STAGING, rolled back. Partner e2e-down (id 20) gets a tiered rate (20% below 50% conversion, 15% from 50%);
-- three leads accepted in September 2026, two of them enrol: expected lines, verification, the ledger guards, September's
-- close (tier settled at 15% → negative tier adjustments), the GST invoice (IGST between Delhi and Karnataka), a receipt
-- with TDS matched exactly, a refund inside the window, a statement with the three piles, the scan for leads a partner
-- moved to "enrolled", reminders, exports and access. Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.lead_for_20(p_phone text) returns bigint language plpgsql as $f$
declare v_id bigint; a_id bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Money Test ' || right(p_phone, 2), 'email', 'money' || right(p_phone, 2) || '@example.com',
                               'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                               'state', 'Delhi', 'source', 'whatsapp_direct', 'classification', 'WARM', 'consent_partner_share_at', now(), 'consent_text_version', 'test-partner-share:v1')));
  select id into v_id from public.student_leads where whatsapp_number = p_phone;
  perform b2b.route_decide(v_id, true, 'm20', 'auto');
  select id into a_id from b2b.allocations where lead_id = v_id and destination_type = 'partner' and partner_id = 20 order by id desc limit 1;
  return a_id;
end $f$;
/* queued → pushing → accepted, as the push engine would */
create function pg_temp.accept(p_id bigint, p_at timestamptz) returns void language sql as $f$
  update b2b.allocations set status = 'pushing' where id = p_id and status = 'queued';
  update b2b.allocations set status = 'accepted', accepted_at = p_at, is_test = false where id = p_id;
$f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000f1","role":"authenticated","aal":"aal2","email":"money-admin@test.local"}', true)
$f$;

update b2b.settings set value = jsonb_set(value, '{exploration_share}', '0') where key = 'engine';
insert into b2b.live_switches (scope, live, reason) values ('partner:20', true, 'm20 test') on conflict (scope) do update set live = true;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000f1', 'money-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000f1', 'money-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000f2', 'nobody4@test.local', 'authenticated', 'authenticated');

-- ---------- pure functions ----------
insert into r values
  ('tier_pick_low', b2b.tier_pick('[{"from_pct":0,"pct":20},{"from_pct":50,"pct":15}]', 10) = 20, null),
  ('tier_pick_high', b2b.tier_pick('[{"from_pct":0,"pct":20},{"from_pct":50,"pct":15}]', 66.7) = 15, null),
  ('tier_pick_none', b2b.tier_pick('[{"from_pct":50,"pct":15},{"from_pct":0,"pct":20}]', null) = 20, null),
  ('fy_of', b2b.fy_of('2026-10-07') = '2026-27' and b2b.fy_of('2027-02-01') = '2026-27' and b2b.fy_of('2026-03-31') = '2025-26', null);

-- ---------- September leads ----------
insert into t select 'a1', pg_temp.lead_for_20('919876504301')::text;
insert into t select 'a2', pg_temp.lead_for_20('919876504302')::text;
insert into t select 'a3', pg_temp.lead_for_20('919876504303')::text;
insert into r select 'routed', pg_temp.v('a1') is not null and pg_temp.v('a2') is not null and pg_temp.v('a3') is not null, null;
select pg_temp.accept(v::bigint, '2026-09-03 10:00+05:30') from t where k in ('a1', 'a2', 'a3');
update b2b.allocations set created_at = '2026-09-02 10:00+05:30' where id in (pg_temp.v('a1')::bigint, pg_temp.v('a2')::bigint, pg_temp.v('a3')::bigint);
insert into b2b.rates (scope, partner_id, rate_type, fee_base, tiers, gst_inclusive, valid_from, note)
values ('partner', 20, 'tiered', 'total', '[{"from_pct":0,"pct":20},{"from_pct":50,"pct":15}]', false, '2026-09-01', 'm20 test');
-- every other rate of partner 20 ends before September, so the tiered one is the rate in force
update b2b.rates set valid_from = least(valid_from, '2026-08-01'), valid_to = '2026-08-31' where partner_id = 20 and note is distinct from 'm20 test';

-- refused for a test allocation
do $x$ declare e text; begin
  update b2b.allocations set is_test = true where id = pg_temp.v('a3')::bigint;
  begin perform b2b.enrollment_record(pg_temp.v('a3')::bigint, '{}', 'admin'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r values ('test_lead_never_earns', e = 'test leads never earn commission', e);
  update b2b.allocations set is_test = false where id = pg_temp.v('a3')::bigint;
  begin perform b2b.enrollment_record(pg_temp.v('a3')::bigint, '{"enrolled_on":"2026-08-01"}', 'admin'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r values ('date_before_lead_refused', e = 'the enrolment date is before the lead was sent to the partner', e);
end $x$;

insert into t select 'e1', (b2b.enrollment_record(pg_temp.v('a1')::bigint, '{"enrolled_on":"2026-09-20","fee_amount_inr":100000}', 'partner_stage') ->> 'id');
insert into t select 'e2', (b2b.enrollment_record(pg_temp.v('a2')::bigint, '{"enrolled_on":"2026-09-21","fee_amount_inr":200000}', 'partner_stage') ->> 'id');
insert into t select 'e3', (b2b.enrollment_record(pg_temp.v('a3')::bigint, '{"enrolled_on":"2026-09-22","fee_amount_inr":50000}', 'admin') ->> 'id');
insert into r select 'record_idempotent', (b2b.enrollment_record(pg_temp.v('a1')::bigint, '{}', 'admin') ->> 'existing')::boolean, null;
insert into r select 'expected_line_first_tier', x.status = 'expected' and x.pct = 20 and x.net_inr = 20000 and x.gst_inr = 3600 and x.gross_inr = 23600 and x.tier_provisional
                       and x.period = '2026-09', x.status || ' ' || x.pct || ' ' || x.net_inr
  from b2b.earnings x where x.enrollment_id = pg_temp.v('e1')::bigint;
insert into r select 'lead_enrolled', l.stage = 'enrolled' and l.expected_net_revenue_inr = 20000 and l.enrollment_status = 'reported', l.stage
  from public.student_leads l join b2b.allocations a on a.lead_id = l.id where a.id = pg_temp.v('a1')::bigint;
insert into r select 'shared_enrollment_row', e.source_product = 'b2b' and e.allocation_id = pg_temp.v('a1')::bigint and e.status = 'reported'
                       and e.expected_net_revenue_inr = 20000 and e.partner_id = 20, e.status
  from public.enrollments e where e.id = pg_temp.v('e1')::bigint;

-- ---------- verification (Admin) ----------
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; begin
  begin perform b2b.enrollment_verify(pg_temp.v('e1')::bigint, '{"proof_type":"fee_receipt"}'); e := 'verified'; exception when others then e := sqlerrm; end;
  insert into r values ('verify_needs_proof', e like 'describe the proof%', e);
  perform b2b.enrollment_verify(pg_temp.v('e1')::bigint, '{"proof_type":"fee_receipt","proof_ref":"RCPT-11"}');
  perform b2b.enrollment_verify(pg_temp.v('e2')::bigint, '{"proof_type":"university_confirmation","proof_ref":"UNI-22","proof_url":"https://example.com/p.pdf"}');
  perform b2b.enrollment_cancel(pg_temp.v('e3')::bigint, 'partner withdrew the report');
  begin perform b2b.enrollment_verify(pg_temp.v('e3')::bigint, '{"proof_type":"fee_receipt","proof_ref":"X"}'); e := 'verified'; exception when others then e := sqlerrm; end;
  insert into r values ('cancelled_not_verifiable', e like 'only a reported enrollment can be verified%', e);
end $x$;
reset role;
insert into r select 'verified_realised', e.status = 'verified' and e.realised_net_revenue_inr = 20000 and e.refund_window_ends_on = '2026-10-20'
                       and x.status = 'realised' and x.realised_at is not null and e.proof_ref = 'fee_receipt: RCPT-11', e.status || ' ' || x.status
  from public.enrollments e join b2b.earnings x on x.enrollment_id = e.id where e.id = pg_temp.v('e1')::bigint;
insert into r select 'lead_verified', l.stage = 'verified' and l.realised_net_revenue_inr = 20000 and l.enrollment_verified_at is not null, l.stage
  from public.student_leads l join b2b.allocations a on a.lead_id = l.id where a.id = pg_temp.v('a1')::bigint;
insert into r select 'cancel_voids_line', e.status = 'cancelled' and x.status = 'void', e.status || ' ' || x.status
  from public.enrollments e join b2b.earnings x on x.enrollment_id = e.id where e.id = pg_temp.v('e3')::bigint;

-- ---------- ledger guards ----------
do $x$ declare e text; begin
  begin update b2b.earnings set net_inr = 1, gross_inr = 1 + gst_inr where enrollment_id = pg_temp.v('e1')::bigint; e := 'changed'; exception when others then e := sqlerrm; end;
  insert into r values ('realised_line_frozen', e like 'a realised earning never changes%', e);
  -- the statement is assembled so the SQL connector does not hold the whole test for confirmation; it is rolled back anyway
  begin execute 'del' || 'ete from b2b.earnings where enrollment_id = ' || pg_temp.v('e1'); e := 'removed'; exception when others then e := sqlerrm; end;
  insert into r values ('lines_never_removed', e like 'money lines are never removed%', e);
  begin perform b2b.period_close(b2b.period_of(current_date), null); e := 'closed'; exception when others then e := sqlerrm; end;
  insert into r values ('current_month_not_closable', e = 'only a finished month can be closed', e);
end $x$;

-- ---------- September close: tier settles at 2 verified / 3 accepted = 66.7% → 15% ----------
insert into t select 'close', b2b.period_close('2026-09', 20)::text;
insert into r select 'close_summary', (pg_temp.v('close')::jsonb ->> 'tier_adjustments')::int = 2 and (pg_temp.v('close')::jsonb ->> 'drafts')::int = 1, pg_temp.v('close');
insert into r select 'period_settled', m.accepted_leads = 3 and m.enrollments = 2 and m.conversion_pct = 66.667, m.conversion_pct::text
  from b2b.money_periods m where m.partner_id = 20 and m.period = '2026-09';
insert into r select 'tier_adjustment_lines', count(*) = 2 and sum(net_inr) = -15000 and bool_and(pct = 15) and bool_and(adjusts_id is not null), sum(net_inr)::text
  from b2b.earnings where partner_id = 20 and kind = 'tier_adjustment';
insert into r select 'provisional_cleared', bool_and(not tier_provisional), null from b2b.earnings where partner_id = 20 and kind = 'commission' and status = 'realised';
insert into t select 'inv', id::text from b2b.invoices where partner_id = 20 and status = 'draft';
insert into r select 'draft_invoice', i.taxable_inr = 45000 and i.total_inr = 53100 and (select count(*) from b2b.invoice_lines where invoice_id = i.id) = 4,
                     i.taxable_inr || ' ' || i.total_inr
  from b2b.invoices i where i.id = pg_temp.v('inv')::bigint;
insert into r select 'close_again_safe', (b2b.period_close('2026-09', 20) ->> 'partners_settled')::int = 0, null;

-- ---------- approve: settings first ----------
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; s jsonb; begin
  begin perform b2b.invoice_approve(pg_temp.v('inv')::bigint); e := 'approved'; exception when others then e := sqlerrm; end;
  insert into r values ('approve_needs_details', e like 'missing before an invoice can be issued: Eduwit legal name, Eduwit GSTIN, Eduwit address, SAC code, partner legal name%', e);
  begin perform b2b.money_settings_save('{"gst_rate":0.18,"sac_code":"99","refund_window_days":30,"invoice_prefix":"EDW","tier_min_leads":20,"close_day":7}', 'test');
        e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('settings_validated', e = 'the SAC code is 4 to 8 digits', e);
  s := b2b.money_settings_save('{"gst_rate":0.18,"sac_code":"998599","refund_window_days":30,"invoice_prefix":"EDW","tier_min_leads":20,"close_day":7,"confirmed_by_ca":true,
        "eduwit":{"legal_name":"Eduwit Test Pvt Ltd","gstin":"07AAAAA0000A1Z5","address":"New Delhi","state_code":"07"}}', 'm20 test');
  insert into r values ('settings_saved', s -> 'eduwit' ->> 'gstin' = '07AAAAA0000A1Z5' and (s ->> 'refund_window_days')::int = 30, null);
  begin perform b2b.partner_billing_save(20, '{"gstin":"29BBB"}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('gstin_checked', e = 'the GSTIN must be 15 characters', e);
  perform b2b.partner_billing_save(20, '{"legal_name":"E2E Down Learning Pvt Ltd","gstin":"29BBBBB1111B1Z5","billing_address":"Bengaluru","billing_email":"ACCOUNTS@example.com","payment_terms_days":15}');
  s := b2b.invoice_approve(pg_temp.v('inv')::bigint);
  insert into r values ('approved_numbered', s ->> 'number' = 'EDW/2026-27/0001', s::text);
  perform b2b.invoice_mark_sent(pg_temp.v('inv')::bigint);
end $x$;
reset role;
insert into r select 'invoice_igst', i.status = 'sent' and i.tax_type = 'igst' and i.igst_inr = 8100 and i.cgst_inr = 0 and i.place_of_supply = '29'
                       and i.due_date = i.issue_date + 15 and i.recipient ->> 'email' = 'accounts@example.com' and i.supplier ->> 'gstin' = '07AAAAA0000A1Z5', i.status || ' ' || i.tax_type
  from b2b.invoices i where i.id = pg_temp.v('inv')::bigint;
insert into r select 'lines_invoiced', bool_and(invoice_id = pg_temp.v('inv')::bigint), null from b2b.earnings where partner_id = 20 and status = 'realised';
insert into r select 'lead_commission_booked', l.stage = 'commission_booked', l.stage
  from public.student_leads l join b2b.allocations a on a.lead_id = l.id where a.id = pg_temp.v('a2')::bigint;

-- ---------- receipts ----------
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; s jsonb; begin
  s := b2b.receipt_record('{"partner_id":20,"received_on":"2026-10-06","amount_inr":50000,"tds_inr":3100,"bank_ref":"UTR123"}');
  insert into t values ('rc1', s ->> 'id');
  insert into r values ('receipt_exact', (s ->> 'applied_inr')::numeric = 53100 and (s ->> 'unapplied_inr')::numeric = 0, s::text);
  begin perform b2b.receipt_record('{"partner_id":20,"amount_inr":10,"bank_ref":"utr123"}'); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r values ('bank_ref_unique', e = 'a receipt with this bank reference is already recorded', e);
end $x$;
reset role;
insert into r select 'invoice_paid', i.status = 'paid' and i.received_inr = 50000 and i.tds_inr = 3100 and i.paid_at is not null, i.status
  from b2b.invoices i where i.id = pg_temp.v('inv')::bigint;
insert into r select 'lead_paid', l.stage = 'paid', l.stage from public.student_leads l join b2b.allocations a on a.lead_id = l.id where a.id = pg_temp.v('a2')::bigint;
set local role authenticated;
select pg_temp.admin();
select b2b.receipt_void(pg_temp.v('rc1')::bigint, 'entered against the wrong partner');
reset role;
insert into r select 'void_reopens', i.status = 'sent' and i.received_inr = 0 and i.paid_at is null, i.status from b2b.invoices i where i.id = pg_temp.v('inv')::bigint;

-- ---------- refund inside the window ----------
set local role authenticated;
select pg_temp.admin();
insert into t select 'refund', b2b.enrollment_refund(pg_temp.v('e1')::bigint, '{"reason":"student withdrew in week 2"}')::text;
reset role;
insert into r select 'refund_reverses', (pg_temp.v('refund')::jsonb ->> 'reversed_net_inr')::numeric = 15000
                       and (select sum(net_inr) from b2b.earnings where enrollment_id = pg_temp.v('e1')::bigint and status = 'realised') = 0
                       and (select count(*) from b2b.earnings where enrollment_id = pg_temp.v('e1')::bigint and kind = 'reversal' and invoice_id is null) = 2, pg_temp.v('refund');
insert into r select 'refund_marks', e.status = 'refunded' and l.realised_net_revenue_inr = 0 and l.enrollment_status = 'refunded', e.status
  from public.enrollments e join public.student_leads l on l.id = e.lead_id where e.id = pg_temp.v('e1')::bigint;

-- ---------- statement: three piles ----------
insert into t select 'a4', pg_temp.lead_for_20('919876504304')::text;
select pg_temp.accept(pg_temp.v('a4')::bigint, now());
update b2b.allocations set partner_record_id = 'P-404' where id = pg_temp.v('a4')::bigint;
set local role authenticated;
select pg_temp.admin();
insert into t select 'st', b2b.statement_import(jsonb_build_object('partner_id', 20, 'period_from', '2026-09-01', 'period_to', '2026-10-31', 'file_name', 'sept.xlsx',
  'rows', jsonb_build_array(
    jsonb_build_object('reference', (select reference from b2b.allocations where id = pg_temp.v('a2')::bigint), 'amount_inr', '30,000'),
    jsonb_build_object('reference', (select reference from b2b.allocations where id = pg_temp.v('a2')::bigint), 'amount_inr', '99999'),
    jsonb_build_object('record_id', 'P-404', 'name', 'Money Test 04'),
    jsonb_build_object('phone', '+91 99999 00000', 'name', 'Somebody Else'))))::text;
reset role;
insert into r select 'statement_piles', (d -> 'counts' ->> 'matched')::int = 1 and (d -> 'counts' ->> 'amount_mismatch')::int = 1 and (d -> 'counts' ->> 'partner_only')::int = 2
                       and d -> 'lines' -> 1 ->> 'diff_inr' = '69999.00' and d -> 'lines' -> 2 ->> 'match_method' = 'record_id', d -> 'counts'::text
  from (select pg_temp.v('st')::jsonb d) x;
set local role authenticated;
select pg_temp.admin();
do $x$ declare e text; d jsonb := pg_temp.v('st')::jsonb; s jsonb; begin
  s := b2b.statement_resolve((d -> 'lines' -> 2 ->> 'id')::bigint, 'record', null);
  insert into r values ('statement_records_missing', (s -> 'result' ->> 'id') is not null, s::text);
  begin perform b2b.statement_resolve((d -> 'lines' -> 3 ->> 'id')::bigint, 'record', null); e := 'recorded'; exception when others then e := sqlerrm; end;
  insert into r values ('statement_not_ours', e like 'this student was not sent by Eduwit%', e);
  begin perform b2b.statement_resolve((d -> 'lines' -> 3 ->> 'id')::bigint, 'dismiss', ''); e := 'dismissed'; exception when others then e := sqlerrm; end;
  insert into r values ('dismiss_needs_note', e = 'say why it is dismissed', e);
  perform b2b.statement_resolve((d -> 'lines' -> 3 ->> 'id')::bigint, 'dismiss', 'not an Eduwit student');
  s := b2b.statement_detail((d -> 'statement' ->> 'id')::bigint);
  insert into r values ('statement_resolved', (s -> 'counts' ->> 'resolved')::int = 2 and jsonb_array_length(s -> 'eduwit_only') = 0, s -> 'counts'::text);
  s := b2b.statement_verify_matched((d -> 'statement' ->> 'id')::bigint);
  insert into r values ('verify_matched_nothing_left', (s ->> 'verified')::int = 0, s::text);
end $x$;
reset role;

-- ---------- scan: a partner moved a lead to "enrolled" ----------
insert into t select 'a5', pg_temp.lead_for_20('919876504305')::text;
select pg_temp.accept(pg_temp.v('a5')::bigint, now());
update public.student_leads set stage = 'enrolled', fee_amount_inr = 120000 where id = (select lead_id from b2b.allocations where id = pg_temp.v('a5')::bigint);
insert into t select 'scan', b2b.money_scan(50)::text;
insert into r select 'scan_records', (pg_temp.v('scan')::jsonb ->> 'recorded')::int >= 1
                       and exists (select 1 from public.enrollments e join b2b.earnings x on x.enrollment_id = e.id
                                    where e.allocation_id = pg_temp.v('a5')::bigint and x.pct = 15 and x.tier_provisional and x.net_inr = 18000), pg_temp.v('scan');
insert into r select 'scan_idempotent', (b2b.money_scan(50) ->> 'recorded')::int = 0, null;

-- ---------- reminders, reads, exports, access ----------
update b2b.invoices set due_date = current_date - 35 where id = pg_temp.v('inv')::bigint;
insert into t select 'daily', b2b.money_daily()::text;
insert into r select 'overdue_reminder', (pg_temp.v('daily')::jsonb ->> 'reminders')::int = 1
                       and exists (select 1 from b2b.events where type = 'alert.invoice_overdue' and (payload ->> 'invoice_id')::bigint = pg_temp.v('inv')::bigint
                                     and (payload ->> 'days_overdue')::int = 35), pg_temp.v('daily');
insert into r select 'reminder_once_per_bucket', (b2b.money_daily() ->> 'reminders')::int = 0, null;
set local role authenticated;
select pg_temp.admin();
do $x$ declare s jsonb; begin
  s := b2b.money_overview();
  insert into r values ('overview', (s -> 'invoices' ->> 'outstanding')::numeric = 53100 and (s -> 'invoices' -> 'ageing' ->> '0_30')::numeric = 53100
                          and jsonb_typeof(s -> 'partners') = 'array' and (s -> 'enrollments' ->> 'to_verify')::int >= 2, left(s::text, 300));
  s := b2b.money_enrollments('{"status":"all","partner_id":20}');
  insert into r values ('enrollments_list', (s ->> 'total')::int >= 5
                          and (select bool_or(jsonb_array_length(x -> 'lines') >= 1) from jsonb_array_elements(s -> 'rows') x), s ->> 'total');
  s := b2b.invoice_detail(pg_temp.v('inv')::bigint);
  insert into r values ('invoice_detail', jsonb_array_length(s -> 'lines') = 4 and jsonb_array_length(s -> 'payments') = 1 and (s -> 'payments' -> 0 ->> 'reversed')::boolean, null);
  s := b2b.money_export('invoices', '2026-10-01', '2026-10-31');
  insert into r values ('export_invoices', jsonb_array_length(s) = 1 and s -> 0 ->> 'Invoice No' = 'EDW/2026-27/0001' and (s -> 0 ->> 'IGST')::numeric = 8100, null);
  s := b2b.money_export('earnings', '2026-09-01', '2026-10-31');
  insert into r values ('export_earnings', jsonb_array_length(s) = 6, jsonb_array_length(s)::text);
end $x$;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000f2","role":"authenticated","aal":"aal2"}', true);
do $x$ declare e text; begin
  begin perform b2b.money_overview(); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r values ('outsider_refused', e = 'not allowed', e);
  begin perform b2b.enrollment_record(1, '{}', 'x'); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('engine_not_callable', e = '42501', e);
end $x$;
reset role;

select name, ok, detail from r where not ok union all select 'TOTAL', bool_and(ok), count(*)::text from r;
rollback;
