-- Ledger, payouts, invoices and TDS: who may do what, immutability, the runner's apply (idempotent, confirmations
-- only grow, reversals record what was paid), penalties and fees, adjustments and holds, who sees which entries,
-- the payout flow (candidates, batch checks, two-person approval, audited bank export, paid and failed), GST
-- invoices, receipts and the event wiring.
begin;
\ir _helpers.psql
select plan(79);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('fin', array['finance']);
select tests.make_staff('fay', array['finance']);
select tests.make_staff('vic', array['viewer']);
select tests.make_creator('riya');
select tests.make_creator('arjun');
insert into inf.agencies (id, name) values ('00000000-0000-0000-0000-00000000a001', 'Acme Talent'), ('00000000-0000-0000-0000-00000000a002', 'Zen Mgmt');
do $$
declare v_uid uuid; v_sid uuid;
begin
  v_uid := tests.create_user('ola@acme.test'); v_sid := gen_random_uuid();
  insert into inf.agency_members (agency_id, email, full_name, role, user_id, linked_at) values ('00000000-0000-0000-0000-00000000a001', 'ola@acme.test', 'Ola', 'owner', v_uid, now());
  insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via) values (v_sid, v_uid, 'agency', now(), 'otp');
  insert into tests.people values ('ola', v_uid, v_sid, null);
  v_uid := tests.create_user('zed@zen.test'); v_sid := gen_random_uuid();
  insert into inf.agency_members (agency_id, email, full_name, role, user_id, linked_at) values ('00000000-0000-0000-0000-00000000a002', 'zed@zen.test', 'Zed', 'owner', v_uid, now());
  insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via) values (v_sid, v_uid, 'agency', now(), 'otp');
  insert into tests.people values ('zed', v_uid, v_sid, null);
end $$;
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_view_earnings)
select '00000000-0000-0000-0000-00000000a001', creator_id, 'active', true, true from tests.people where label = 'riya';
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_view_earnings)
select '00000000-0000-0000-0000-00000000a002', creator_id, 'active', true, false from tests.people where label = 'riya';

create temporary table ids (label text primary key, id uuid);
grant select, insert on ids to authenticated, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;
create temporary table eids (label text primary key, id bigint);
grant select, insert on eids to authenticated, service_role;

insert into ids values ('deal', gen_random_uuid());
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model, agreed_at)
select (select id from ids where label = 'deal'), (select id from ids where label = 'riya'), 'Riya deal', 'active', (now() at time zone 'Asia/Kolkata')::date - 30, 'hybrid', now();
insert into ids select 'version', gen_random_uuid();
insert into inf.deal_versions (id, deal_id, version, comp_config, config_hash, origin, effective_from, state)
select (select id from ids where label = 'version'), (select id from ids where label = 'deal'), 1, p.comp_config, inf.config_hash(p.comp_config),
       'builder', now() - interval '30 days', 'accepted'
  from inf.deal_presets p where p.key = 'fixed_plus_commission';
-- Verified KYC for Riya (PAN and bank), none for Arjun.
insert into inf.creator_kyc (creator_id, pan_enc, pan_last4, name_on_pan, bank_account_enc, bank_last4, ifsc, account_holder, status)
select (select id from ids where label = 'riya'), inf.pii_encrypt('ABCPS1234K'), '234K', 'Riya Sharma', inf.pii_encrypt('001234567890'), '7890',
       'HDFC0001234', 'Riya Sharma', 'verified';

-- ---------------------------------------------------------------------------------------------------------------
-- The runner's apply
-- ---------------------------------------------------------------------------------------------------------------
create temporary table plan (k text primary key, p jsonb);
grant select on plan to service_role, authenticated;
insert into plan values ('first', jsonb_build_object('as_of', now(), 'create', jsonb_build_array(
  jsonb_build_object('key', (select id from ids where label = 'version') || ':fee:signing:fire', 'type', 'milestone', 'direction', 'credit',
                     'amount_paise', 750000, 'confirmed_paise', 750000, 'rule_id', 'fee', 'version_id', (select id from ids where label = 'version'),
                     'subject', 'fee.signing', 'period', to_char((now() at time zone 'Asia/Kolkata')::date, 'YYYY-MM'), 'due_on', (now() at time zone 'Asia/Kolkata')::date - 1, 'note', 'Content fee: On signing',
                     'tds_component', 'milestone'),
  jsonb_build_object('key', (select id from ids where label = 'version') || ':commission:enrol:b2b:9:accrue', 'type', 'commission', 'direction', 'credit',
                     'amount_paise', 100000, 'confirmed_paise', 0, 'rule_id', 'commission', 'version_id', (select id from ids where label = 'version'),
                     'subject', 'commission:enrol:b2b:9', 'period', to_char((now() at time zone 'Asia/Kolkata')::date, 'YYYY-MM'), 'due_on', (now() at time zone 'Asia/Kolkata')::date, 'note', 'Commission per enrolment',
                     'tds_component', 'commission'))));

select tests.as_person('fin');
select throws_ok($$ select inf.ledger_apply((select id from ids where label = 'deal'), (select p from plan where k = 'first')) $$, '42501', null,
  'only the runner applies plans');
select throws_ok($$ insert into inf.ledger_entries (creator_id, type, direction, amount_paise, status, source, event_key, period, due_on)
                    values ((select id from ids where label = 'riya'), 'adjustment', 'credit', 1, 'accrued', 'adjustment', 'x', '2026-11', (now() at time zone 'Asia/Kolkata')::date) $$,
  '42501', null, 'clients cannot write the ledger');

select tests.act_as_service();
select is(inf.ledger_apply((select id from ids where label = 'deal'), (select p from plan where k = 'first')) ->> 'created', '2', 'the plan posts two lines');
select is(inf.ledger_apply((select id from ids where label = 'deal'), (select p from plan where k = 'first')) ->> 'created', '0', 'applying again posts nothing');
insert into eids select 'fee', id from inf.ledger_entries where subject = 'fee.signing';
insert into eids select 'commission', id from inf.ledger_entries where subject = 'commission:enrol:b2b:9';
select is((select status from inf.ledger_entries where id = (select id from eids where label = 'fee')), 'payable', 'a confirmed, due line is payable');
select is((select status from inf.ledger_entries where id = (select id from eids where label = 'commission')), 'accrued', 'an unconfirmed line is accrued');
select is((select count(*)::int from inf.ledger_status_events where entry_id = (select id from eids where label = 'fee')), 1, 'posting logs the first status');
select is((select count(*)::int from inf.comp_runs where deal_id = (select id from ids where label = 'deal') and kind = 'live'), 2, 'each run is logged');

-- Immutability (even for the table owner).
select tests.reset();
select throws_ok($$ update inf.ledger_entries set amount_paise = 1 where id = (select id from eids where label = 'fee') $$, '42501', null,
  'amounts never change');
select throws_ok($$ update inf.ledger_entries set status = 'paid' where id = (select id from eids where label = 'fee') $$, '42501', null,
  'the status changes only through the ledger functions');
select throws_ok($$ delete from inf.ledger_entries where id = (select id from eids where label = 'fee') $$, '42501', null, 'entries are never deleted');
select throws_ok($$ update inf.ledger_status_events set reason = 'x' $$, '42501', null, 'status history is append-only');

select tests.act_as_service();
select is(inf.ledger_apply((select id from ids where label = 'deal'), jsonb_build_object('confirm', jsonb_build_array(
  jsonb_build_object('key', (select id from ids where label = 'version') || ':commission:enrol:b2b:9:accrue', 'confirmed_paise', 100000)))) ->> 'confirmed',
  '1', 'confirmations are applied');
select is((select status from inf.ledger_entries where id = (select id from eids where label = 'commission')), 'payable', 'and the commission becomes payable');
select is(inf.ledger_apply((select id from ids where label = 'deal'), jsonb_build_object('confirm', jsonb_build_array(
  jsonb_build_object('key', (select id from ids where label = 'version') || ':commission:enrol:b2b:9:accrue', 'confirmed_paise', 50000)))) ->> 'confirmed',
  '0', 'a lower confirmation is ignored');

-- An approved penalty and an approved extra revision fee are posted with the next run.
insert into inf.penalty_proposals (deal_id, key, rule_id, version_id, subject, amount_paise, reason, proposed_at, status, decided_at)
select (select id from ids where label = 'deal'), 'pen-1', 'late', (select id from ids where label = 'version'), 'reel1', 20000, 'Late', now(), 'approved', now();
select is(inf.ledger_apply((select id from ids where label = 'deal'), '{}') ->> 'other', '1', 'an approved penalty is posted');
select is((select direction || ':' || status || ':' || tds_component from inf.ledger_entries where event_key = 'penalty:pen-1'), 'debit:payable:fixed_fee',
  'as a payable debit against fees');
select is(inf.ledger_apply((select id from ids where label = 'deal'), '{}') ->> 'other', '0', 'only once');

-- ---------------------------------------------------------------------------------------------------------------
-- Adjustments and holds
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select throws_ok($$ select inf.ledger_adjust(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'direction', 'credit',
                    'amount_paise', 500, 'reason', 'Goodwill')) $$, '42501', null, 'managers do not post adjustments');
select tests.as_person('fin');
select throws_ok($$ select inf.ledger_adjust(jsonb_build_object('creator_id', (select id from ids where label = 'riya'), 'direction', 'credit',
                    'amount_paise', 500, 'reason', '')) $$, '22023', 'a reason is required', 'adjustments need a reason');
select lives_ok($$ insert into eids select 'adj', inf.ledger_adjust(jsonb_build_object('creator_id', (select id from ids where label = 'riya'),
                   'direction', 'credit', 'amount_paise', 5000, 'reason', 'Travel reimbursement agreed by email')) $$, 'finance posts an adjustment');
select is((select status from inf.ledger_entries where id = (select id from eids where label = 'adj')), 'payable', 'adjustments are confirmed and due');
select is(inf.ledger_hold((select id from eids where label = 'adj'), true, 'Checking the receipt'), 'on_hold', 'an entry can be held');
select is(inf.ledger_hold((select id from eids where label = 'adj'), false, 'Receipt checked'), 'payable', 'and released');

-- ---------------------------------------------------------------------------------------------------------------
-- Who sees what
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select is((select count(*)::int from inf.ledger_entries), 4, 'a creator sees her own entries');
select tests.as_person('arjun');
select is((select count(*)::int from inf.ledger_entries), 0, 'and no one else''s');
select is(inf.creator_earnings((select id from ids where label = 'riya')), null, 'nor their earnings');
select tests.as_person('ola');
select is((select count(*)::int from inf.ledger_entries), 4, 'an agency with the earnings grant sees them');
select tests.as_person('zed');
select is((select count(*)::int from inf.ledger_entries), 0, 'an agency without it does not');
select tests.as_person('vic');
select is((select count(*)::int from inf.ledger_entries), 0, 'viewers do not see the ledger');
select tests.as_person('mona');
select is((select count(*)::int from inf.ledger_entries), 4, 'managers read the ledger');
select is((inf.ledger_list('{}') ->> 'total')::int, 4, 'and list it');

-- ---------------------------------------------------------------------------------------------------------------
-- Payouts
-- ---------------------------------------------------------------------------------------------------------------
select throws_ok($$ select inf.payout_candidates('{}') $$, '42501', null, 'managers do not prepare payouts');
select tests.as_person('fin');
select is(jsonb_array_length(inf.payout_candidates('{}') -> 'creators'), 1, 'Riya has payable entries');
select is(jsonb_array_length(inf.payout_candidates('{}') -> 'creators' -> 0 -> 'entries'), 4, 'all four');
select ok((inf.payout_candidates('{}') -> 'creators' -> 0 ->> 'kyc_verified')::boolean, 'with verified KYC');

-- 7,500 + 1,000 + 50 − 200 rupees = 8,350 gross; 194J and 194H stay under their thresholds.
create temporary table batch (k text primary key, p jsonb);
grant select on batch to authenticated;
insert into batch values ('bad', jsonb_build_object('payouts', jsonb_build_array(jsonb_build_object(
  'creator_id', (select id from ids where label = 'riya'), 'gross_paise', 835000, 'net_paise', 835000, 'sections', '[]'::jsonb,
  'items', jsonb_build_array(jsonb_build_object('entry_id', (select id from eids where label = 'fee'), 'amount_paise', 700000))))));
insert into batch values ('good', jsonb_build_object('note', 'November run', 'payouts', jsonb_build_array(jsonb_build_object(
  'creator_id', (select id from ids where label = 'riya'), 'gross_paise', 835000, 'net_paise', 835000, 'sections', '[]'::jsonb,
  'items', jsonb_build_array(
    jsonb_build_object('entry_id', (select id from eids where label = 'fee'), 'amount_paise', 750000),
    jsonb_build_object('entry_id', (select id from eids where label = 'commission'), 'amount_paise', 100000),
    jsonb_build_object('entry_id', (select id from eids where label = 'adj'), 'amount_paise', 5000),
    jsonb_build_object('entry_id', (select id from inf.ledger_entries where event_key = 'penalty:pen-1'), 'amount_paise', -20000))))));
select throws_ok($$ select inf.payout_batch_create((select p from batch where k = 'bad')) $$, '40001', null,
  'an item must take exactly what is payable');
insert into ids select 'batch', inf.payout_batch_create((select p from batch where k = 'good'));
select ok((select ref ~ '^PB-\d{4}-\d{2}-\d{4}$' from inf.payout_batches where id = (select id from ids where label = 'batch')), 'the batch gets a reference');
insert into ids select 'payout', id from inf.payouts where batch_id = (select id from ids where label = 'batch');
select is((select status from inf.ledger_entries where id = (select id from eids where label = 'fee')), 'in_batch', 'its entries are in the batch');
select throws_ok($$ select inf.payout_batch_create((select p from batch where k = 'good')) $$, '40001', null, 'and cannot join another batch');
select throws_ok($$ select inf.payout_bank_rows((select id from ids where label = 'batch')) $$, '22023', null, 'no bank file before approval');

select tests.as_person('mona');
select throws_ok($$ select inf.payout_batch_approve((select id from ids where label = 'batch')) $$, '42501', null, 'managers do not approve payouts');
select tests.as_person('fin');
select is(inf.payout_batch_approve((select id from ids where label = 'batch')), 'draft', 'with two-person approval, one approval is not enough');
select throws_ok($$ select inf.payout_batch_approve((select id from ids where label = 'batch')) $$, '22023', 'a second approver is needed',
  'the same person cannot approve twice');
select tests.as_person('fay');
select is(inf.payout_batch_approve((select id from ids where label = 'batch')), 'approved', 'a second finance member approves');
select tests.as_person('fin');
select is((inf.payout_bank_rows((select id from ids where label = 'batch')) -> 0 ->> 'account_number'), '001234567890', 'the bank file has the account number');
select is((select status from inf.payout_batches where id = (select id from ids where label = 'batch')), 'processing', 'exporting starts processing');
select tests.reset();
select is((select count(*)::int from inf.audit_log where entity_type = 'payout_batch' and action = 'bank_export'), 1, 'and the export is audited');
select tests.as_person('fin');
select throws_ok($$ select inf.payout_batch_cancel((select id from ids where label = 'batch'), 'Oops') $$, '22023', null,
  'a batch sent to the bank cannot be cancelled');
select throws_ok($$ select inf.payouts_mark_paid(jsonb_build_array(jsonb_build_object('payout_ref', (select ref from inf.payouts where id = (select id from ids where label = 'payout')),
                    'utr', 'HDFCN52026113012345', 'paid_on', (now() at time zone 'Asia/Kolkata')::date + 3))) $$, '22023', null, 'a payment date cannot be in the future');
select is(inf.payouts_mark_paid(jsonb_build_array(jsonb_build_object('payout_ref', (select ref from inf.payouts where id = (select id from ids where label = 'payout')),
          'utr', 'HDFCN52026113012345', 'paid_on', (now() at time zone 'Asia/Kolkata')::date))), 1, 'finance marks the payout paid');
select is((select status from inf.ledger_entries where id = (select id from eids where label = 'fee')), 'paid', 'its entries are paid');
select is((select status from inf.ledger_entries where event_key = 'penalty:pen-1'), 'paid', 'including the recovered penalty');
select is((select sum(case direction when 'credit' then amount_paise else -amount_paise end)::bigint from inf.ledger_entries
            where creator_id = (select id from ids where label = 'riya') and status in ('paid')), 0::bigint,
  'after the payout, what was paid nets to zero against the payout entry');
select is((select status from inf.payout_batches where id = (select id from ids where label = 'batch')), 'paid', 'the batch is paid');
select is((select count(*)::int from inf.invoices where payout_id = (select id from ids where label = 'payout') and kind = 'payout_statement'), 1,
  'a creator without GST gets a payout statement');
select tests.reset();
select is((select count(*)::int from inf.jobs where kind = 'payout.advice'), 1, 'and the payment advice is queued');

-- ---------------------------------------------------------------------------------------------------------------
-- GST invoices
-- ---------------------------------------------------------------------------------------------------------------
update inf.creator_kyc set gst_status = 'registered', gstin = '27ABCPS1234K1ZM', gstin_verified = true
 where creator_id = (select id from ids where label = 'riya');
select tests.as_person('fin');
select lives_ok($$ insert into eids select 'adj2', inf.ledger_adjust(jsonb_build_object('creator_id', (select id from ids where label = 'riya'),
                   'direction', 'credit', 'amount_paise', 100000, 'reason', 'Bonus agreed for the extra reel')) $$, 'another payable entry');
insert into ids select 'batch2', inf.payout_batch_create(jsonb_build_object('payouts', jsonb_build_array(jsonb_build_object(
  'creator_id', (select id from ids where label = 'riya'), 'gross_paise', 100000, 'gst_base_paise', 100000, 'gst_paise', 18000,
  'net_paise', 118000, 'needs_invoice', true, 'sections', '[]'::jsonb,
  'items', jsonb_build_array(jsonb_build_object('entry_id', (select id from eids where label = 'adj2'), 'amount_paise', 100000))))));
insert into ids select 'payout2', id from inf.payouts where batch_id = (select id from ids where label = 'batch2');
select throws_ok($$ select inf.payout_batch_approve((select id from ids where label = 'batch2')) $$, '22023', 'a payout is waiting for its GST invoice',
  'a payout with GST needs an accepted invoice first');
select tests.as_person('riya');
select ok(inf.invoice_upload_allowed((select id from ids where label = 'payout2')), 'the creator may upload the invoice');
select throws_ok($$ select inf.invoice_submit(jsonb_build_object('payout_id', (select id from ids where label = 'payout2'), 'number', 'RS-007',
                    'issued_on', (now() at time zone 'Asia/Kolkata')::date, 'gstin', '27ABCPS1234K1ZM',
                    'taxable_paise', 90000, 'gst_paise', 16200,
                    'file_path', (select id from ids where label = 'riya') || '/' || (select id from ids where label = 'payout2') || '/inv.pdf')) $$,
  '22023', 'the invoice amounts must match the payout', 'amounts must match');
select lives_ok($$ insert into ids select 'invoice', inf.invoice_submit(jsonb_build_object('payout_id', (select id from ids where label = 'payout2'),
                   'number', 'RS-007', 'issued_on', (now() at time zone 'Asia/Kolkata')::date, 'gstin', '27ABCPS1234K1ZM',
                   'taxable_paise', 100000, 'gst_paise', 18000,
                   'file_path', (select id from ids where label = 'riya') || '/' || (select id from ids where label = 'payout2') || '/inv.pdf')) $$,
  'a matching invoice is submitted');
select tests.as_person('fin');
select lives_ok($$ select inf.invoice_review((select id from ids where label = 'invoice'), true, null) $$, 'finance accepts it');
select is(inf.payout_batch_approve((select id from ids where label = 'batch2')), 'draft', 'then the batch can be approved');

-- A failed payment puts the entries back.
select tests.as_person('fay');
select is(inf.payout_batch_approve((select id from ids where label = 'batch2')), 'approved', 'second approval');
select tests.as_person('fin');
select lives_ok($$ select inf.payout_bank_rows((select id from ids where label = 'batch2')) $$, 'exported');
select lives_ok($$ select inf.payout_mark_failed((select id from ids where label = 'payout2'), 'Account closed') $$, 'the bank returns it');
select is((select status from inf.ledger_entries where id = (select id from eids where label = 'adj2')), 'payable', 'its entry is payable again');

-- ---------------------------------------------------------------------------------------------------------------
-- Receipts, manual events and the event wiring
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select throws_ok($$ select inf.receipt_record(jsonb_build_object('enrollment_ref', 'b2b:9', 'student_lead_id', 1, 'status', 'received',
                    'received_paise', 100, 'reason', 'Bank statement')) $$, '42501', null, 'managers do not record receipts');
select tests.as_person('fin');
select lives_ok($$ select inf.receipt_record(jsonb_build_object('enrollment_ref', 'b2b:9', 'student_lead_id', 1, 'status', 'received',
                   'received_paise', 1180000, 'gross_paise', 1180000, 'reason', 'Partner paid by bank transfer')) $$, 'finance records a receipt');
select tests.reset();
select is((select status from inf.receipts_effective() where enrollment_ref = 'b2b:9'), 'received', 'the manual receipt is in force');
delete from inf.jobs where kind = 'ledger.run';
select inf.emit_event('deal.active', 'deal', (select id::text from ids where label = 'deal'), '{}', 'test-deal-event');
select is((select count(*)::int from inf.jobs where kind = 'ledger.run' and payload ->> 'deal_id' = (select id::text from ids where label = 'deal')), 1,
  'a deal event enqueues one ledger run');

-- Reversing a line that was already paid claws it back: the reversal entry recovers the paid amount from future payouts.
select tests.act_as_service();
select is(inf.ledger_apply((select id from ids where label = 'deal'), jsonb_build_object('reverse', jsonb_build_array(jsonb_build_object(
  'key', (select id from ids where label = 'version') || ':fee:signing:fire', 'reason', 'changed')))) ->> 'reversed', '1', 'a paid line is reversed');
select is((select status from inf.ledger_entries where id = (select id from eids where label = 'fee')), 'clawed_back', 'it is clawed back');
select is((select direction || ':' || confirmed_paise || ':' || status from inf.ledger_entries where reverses_id = (select id from eids where label = 'fee')),
  'debit:750000:payable', 'and the reversal recovers what was paid');

-- ---------------------------------------------------------------------------------------------------------------
-- Eduwit's B2B commission from the CRM (b2b.earnings and b2b.invoices, read only)
-- ---------------------------------------------------------------------------------------------------------------
select tests.reset();
create temp table rx (label text primary key, id bigint);
with l as (insert into public.student_leads (whatsapp_number, student_name, stage) values ('910000009901', 'Receipt Student', 'new') returning id)
insert into rx select 'lead', id from l;
insert into inf.lead_attributions (student_lead_id, creator_id, code, touch, status, evidence_source, touch_at, lead_created_at)
select (select id from rx where label = 'lead'), (select creator_id from tests.people where label = 'riya'), 'RIYA-RCPT', 'first', 'credited',
       'referral_code', now(), now();
with e as (insert into public.enrollments (lead_id, source_product, status, enrolled_on)
           values ((select id from rx where label = 'lead'), 'b2b', 'verified', (now() at time zone 'Asia/Kolkata')::date) returning id)
insert into rx select 'enr', id from e;
with i as (insert into b2b.invoices (status, total_inr, received_inr) values ('partly_paid', 28320, 14160) returning id)
insert into rx select 'inv', id from i;
insert into b2b.earnings (enrollment_id, kind, status, gross_inr, invoice_id) values
  ((select id from rx where label = 'enr'), 'commission', 'realised', 11800, (select id from rx where label = 'inv')),
  ((select id from rx where label = 'enr'), 'tier_adjustment', 'realised', 2360, (select id from rx where label = 'inv')),
  ((select id from rx where label = 'enr'), 'commission', 'void', 99999, null);
select tests.act_as_service();
select lives_ok($$ select inf.commission_receipts_sync() $$, 'the receipts sync reads the B2B CRM');
select tests.reset();
select is((select row(r.status, r.gross_paise, r.received_paise)::text from inf.receipts_effective() r
            where r.enrollment_ref = 'b2b:' || (select id from rx where label = 'enr')),
          '(partly_received,1416000,708000)',
          'commission and tier settlement count, void lines do not, and a partly paid invoice counts pro rata');
update public.enrollments set status = 'refunded', refunded_at = now() where id = (select id from rx where label = 'enr');
select tests.act_as_service();
select lives_ok($$ select inf.commission_receipts_sync() $$, 'the sync runs again after a refund');
select tests.reset();
select is((select r.status from inf.receipts_effective() r where r.enrollment_ref = 'b2b:' || (select id from rx where label = 'enr')),
          'reversed', 'a refunded enrolment reverses the receipt even after Eduwit was paid');

select * from finish();
rollback;
