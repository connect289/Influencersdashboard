-- Migration 20261113113000_inf_hardening (D-197): payouts keep the bank details verified when the batch was made
-- (fingerprint, refused bank file, locked KYC bank fields, holder name counts as a change); a counter-offer decision
-- is one locked step and regeneration closes it; jobs that die while running stop and reach System status staff;
-- nightly contract reminders are sent once per day.
begin;
\ir _helpers.psql
select plan(49);

select tests.make_staff('fin', array['finance']);
select tests.make_staff('fay', array['finance']);
select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('adm', array['super_admin']);
select tests.make_staff('vic', array['viewer']);
select tests.make_creator('riya');
update inf.creators set approved_at = now() where handle = 'riya';

create temporary table ids (label text primary key, id uuid);
grant select, insert on ids to authenticated, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;
create temporary table jids (label text primary key, id bigint);
grant select, insert on jids to authenticated, service_role;

insert into inf.creator_kyc (creator_id, pan_enc, pan_last4, name_on_pan, bank_account_enc, bank_last4, ifsc, account_holder, status)
select (select id from ids where label = 'riya'), inf.pii_encrypt('ABCPS1234K'), '234K', 'Riya Sharma', inf.pii_encrypt('001234567890'), '7890',
       'HDFC0001234', 'Riya Sharma', 'verified';

-- ---------------------------------------------------------------------------------------------------------------
-- 1. Bank details fixed for the life of a payout
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('fin');
create temporary table eids (label text primary key, id bigint);
grant select, insert on eids to authenticated;
insert into eids select 'adj', inf.ledger_adjust(jsonb_build_object('creator_id', (select id from ids where label = 'riya'),
  'direction', 'credit', 'amount_paise', 50000, 'reason', 'Event appearance agreed by email'));
insert into ids select 'batch', inf.payout_batch_create(jsonb_build_object('payouts', jsonb_build_array(jsonb_build_object(
  'creator_id', (select id from ids where label = 'riya'), 'gross_paise', 50000, 'net_paise', 50000, 'sections', '[]'::jsonb,
  'items', jsonb_build_array(jsonb_build_object('entry_id', (select id from eids where label = 'adj'), 'amount_paise', 50000))))));
select tests.reset();
select is((select bank_fingerprint from inf.payouts where batch_id = (select id from ids where label = 'batch')),
          inf.kyc_bank_fingerprint((select id from ids where label = 'riya')), 'the payout keeps the beneficiary fingerprint');
select is((select bank_last4 from inf.payouts where batch_id = (select id from ids where label = 'batch')), '7890', 'and the last four digits');

select tests.as_person('riya');
select is(inf.kyc_save((select id from ids where label = 'riya'), null, 'Riya Sharma', 'unregistered', null, '009999999999', 'HDFC0001234', 'Riya Sharma') ->> 'error',
          'bank_locked', 'a new account number is refused while a payout is open');
select is(inf.kyc_save((select id from ids where label = 'riya'), null, 'Riya Sharma', 'unregistered', null, null, 'ICIC0001234', 'Riya Sharma') ->> 'error',
          'bank_locked', 'so is a new IFSC');
select is(inf.kyc_save((select id from ids where label = 'riya'), null, 'Riya Sharma', 'unregistered', null, null, 'HDFC0001234', 'Someone Else') ->> 'error',
          'bank_locked', 'and a new account holder name');
select is(inf.kyc_save((select id from ids where label = 'riya'), null, 'Riya Sharma', 'unregistered', null, '001234567890', 'HDFC0001234', 'Riya Sharma') ->> 'status',
          'verified', 're-entering the stored details is not a change: still verified');
select tests.as_person('mona');
select is(inf.kyc_save((select id from ids where label = 'riya'), null, 'Riya Sharma', 'unregistered', null, '009999999999', 'HDFC0001234', 'Riya Sharma') ->> 'error',
          'bank_locked', 'staff with creator.write are held to the same rule');

select tests.as_person('fin');
select inf.payout_batch_approve((select id from ids where label = 'batch'));
select tests.as_person('fay');
select is(inf.payout_batch_approve((select id from ids where label = 'batch')), 'approved', 'the batch is approved');
-- A swap that bypasses kyc_save (a direct write) still cannot reach the bank file.
select tests.reset();
update inf.creator_kyc set bank_account_enc = inf.pii_encrypt('005555555555'), bank_last4 = '5555' where creator_id = (select id from ids where label = 'riya');
select tests.as_person('fin');
select throws_like($$ select inf.payout_bank_rows((select id from ids where label = 'batch')) $$,
                   'bank file refused: PO-% (bank details changed after the batch was made)', 'changed bank details refuse the bank file');
select is((select status from inf.payout_batches where id = (select id from ids where label = 'batch')), 'approved', 'and the batch stays approved');
select tests.reset();
update inf.creator_kyc set bank_account_enc = inf.pii_encrypt('001234567890'), bank_last4 = '7890' where creator_id = (select id from ids where label = 'riya');
select tests.as_person('fin');
select is(inf.payout_bank_rows((select id from ids where label = 'batch')) -> 0 ->> 'account_number', '001234567890', 'the verified details export');
select tests.reset();
update inf.creator_kyc set status = 'submitted' where creator_id = (select id from ids where label = 'riya');
select tests.as_person('fin');
select throws_like($$ select inf.payout_bank_rows((select id from ids where label = 'batch')) $$, '%(KYC not verified)%',
                   'a KYC waiting for verification refuses a re-export');
select tests.reset();
update inf.creator_kyc set status = 'verified' where creator_id = (select id from ids where label = 'riya');
insert into ids select 'nobank', gen_random_uuid();
select tests.as_person('fin');
select is(inf.payouts_mark_paid(jsonb_build_array(jsonb_build_object('payout_ref', (select ref from inf.payouts where batch_id = (select id from ids where label = 'batch')),
          'utr', 'HDFCN52026111312345', 'paid_on', (now() at time zone 'Asia/Kolkata')::date))), 1, 'the payout is paid');
select tests.as_person('riya');
select is(inf.kyc_save((select id from ids where label = 'riya'), null, 'Riya Sharma', 'unregistered', null, '009999999999', 'HDFC0001234', 'Riya Sharma') ->> 'status',
          'submitted', 'once paid, the bank account can change and goes back for verification');
select tests.reset();
update inf.creator_kyc set status = 'verified' where creator_id = (select id from ids where label = 'riya');
select tests.as_person('riya');
select is(inf.kyc_save((select id from ids where label = 'riya'), null, 'Riya Sharma', 'unregistered', null, null, 'HDFC0001234', 'Riya S Sharma') ->> 'status',
          'submitted', 'a new account holder name alone sends the KYC back for verification');
select tests.reset();
select is((select account_holder from inf.creator_kyc where creator_id = (select id from ids where label = 'riya')), 'Riya S Sharma', 'and is saved');
select is(inf.kyc_bank_fingerprint((select id from ids where label = 'nobank')), null, 'no KYC, no fingerprint');
select tests.as_person('riya');
select throws_ok($$ select inf.kyc_bank_fingerprint((select id from ids where label = 'riya')) $$, '42501', null, 'creators cannot call the fingerprint');

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Counter-offers: one locked decision, closed by the next version
-- ---------------------------------------------------------------------------------------------------------------
select tests.reset();
insert into ids values ('deal', gen_random_uuid());
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model, agreed_at)
select (select id from ids where label = 'deal'), (select id from ids where label = 'riya'), 'Diwali deal', 'agreed', (now() at time zone 'Asia/Kolkata')::date, 'fixed_only', now();
insert into ids select 'dv1', gen_random_uuid();
insert into inf.deal_versions (id, deal_id, version, comp_config, config_hash, origin, effective_from, state, decided_at)
select (select id from ids where label = 'dv1'), (select id from ids where label = 'deal'), 1, p.comp_config, inf.config_hash(p.comp_config), 'builder', now(), 'accepted', now()
  from inf.deal_presets p where p.key = 'fixed_only';
update inf.deals set current_version_id = (select id from ids where label = 'dv1') where id = (select id from ids where label = 'deal');
update inf.clause_versions set reviewed_at = now();
create temporary table cfg (k text primary key, v jsonb);
grant select on cfg to authenticated;
insert into cfg select 'fee', jsonb_set(comp_config, '{fixed,0,amount_paise}', '2000000') from inf.deal_presets where key = 'fixed_only';
insert into cfg select 'fee2', jsonb_set(comp_config, '{fixed,0,amount_paise}', '1800000') from inf.deal_presets where key = 'fixed_only';
select tests.as_person('mona');
insert into ids select 'contract', inf.contract_create(jsonb_build_object('deal_id', (select id from ids where label = 'deal'),
  'template_id', (select id from inf.contract_templates where is_default)));
create temporary table content (v jsonb);
grant select on content to authenticated;
insert into content select jsonb_build_object('title', 'Creator Agreement', 'header', '[]'::jsonb, 'footer', '[]'::jsonb, 'sections', jsonb_build_array(
  jsonb_build_object('key', 'parties', 'number', 1, 'clause_id', (select id from inf.clauses where key = 'parties'), 'clause_version', 1, 'category', 'parties',
                     'title', 'Parties', 'negotiable', false, 'locked', true, 'amended', false, 'blocks', '[]'::jsonb)));
select inf.contract_version_add((select id from ids where label = 'contract'), (select v from content), '<article>v1</article>', '{}'::jsonb);
select inf.contract_send((select id from ids where label = 'contract'));
select tests.as_person('riya');
insert into ids select 'comp', inf.change_request_create((select id from ids where label = 'contract'),
  '{"kind":"compensation","proposed_terms":{"fixed_fee_paise":2000000},"note":"20k please"}');
select throws_ok($$ select inf.deal_version_from_counter((select id from ids where label = 'comp'), (select v from cfg where k = 'fee')) $$,
                 '42501', null, 'the creator cannot decide her own counter-offer');
select tests.as_person('mona');
select throws_ok($$ select inf.deal_version_from_counter((select id from ids where label = 'comp'), (select v from cfg where k = 'fee'), 'rejected') $$,
                 '22023', 'invalid decision', 'only accepted or countered here');
select throws_ok($$ select inf.deal_version_from_counter((select id from ids where label = 'comp'), (select v from cfg where k = 'fee'), 'accepted', null, gen_random_uuid()) $$,
                 '40001', null, 'terms that moved since the decision was prepared are refused');
insert into ids select 'dv2', inf.deal_version_from_counter((select id from ids where label = 'comp'), (select v from cfg where k = 'fee'), 'accepted', null,
                                                             (select id from ids where label = 'dv1'));
select tests.reset();
select is((select status || ':' || coalesce(resolved_in_version_id::text, 'none') from inf.contract_change_requests where id = (select id from ids where label = 'comp')),
          'accepted:none', 'the request is decided in the same step, its contract version still to come');
select is((select current_version_id from inf.deals where id = (select id from ids where label = 'deal')), (select id from ids where label = 'dv2'), 'the deal has the new terms');
select tests.as_person('mona');
select throws_ok($$ select inf.deal_version_from_counter((select id from ids where label = 'comp'), (select v from cfg where k = 'fee')) $$,
                 '22023', 'change request is not pending', 'deciding again is refused');
select tests.reset();
select is((select count(*)::int from inf.deal_versions where deal_id = (select id from ids where label = 'deal')), 2, 'and writes no other deal version');
select tests.as_person('mona');
select throws_like($$ select inf.contract_set_ready((select id from ids where label = 'contract')) $$, '%regenerate the contract first',
                   'the contract cannot be ready to sign before it carries the accepted terms');
insert into ids select 'cv2', inf.contract_version_add((select id from ids where label = 'contract'), (select v from content), '<article>v2</article>', '{}'::jsonb, 'Regenerated');
select tests.reset();
select is((select resolved_in_version_id from inf.contract_change_requests where id = (select id from ids where label = 'comp')), (select id from ids where label = 'cv2'),
          'any new version closes the decided counter-offer');
select is((select deal_version_id from inf.contract_versions where id = (select id from ids where label = 'cv2')), (select id from ids where label = 'dv2'),
          'built from the new terms');
select is((select count(*)::int from inf.deal_versions where deal_id = (select id from ids where label = 'deal')), 2, 'regenerating writes no deal version');
select tests.as_person('mona');
select lives_ok($$ select inf.contract_set_ready((select id from ids where label = 'contract')) $$, 'then it can be marked ready to sign');
-- A countered offer, closed through p_resolve the way the app before this change did it.
select tests.as_person('riya');
insert into ids select 'comp2', inf.change_request_create((select id from ids where label = 'contract'),
  '{"kind":"compensation","proposed_terms":{"fixed_fee_paise":2200000}}');
select tests.as_person('mona');
select inf.deal_version_from_counter((select id from ids where label = 'comp2'), (select v from cfg where k = 'fee2'), 'countered', 'We can do 18k');
select tests.reset();
select is((select status || ':' || decision_note from inf.contract_change_requests where id = (select id from ids where label = 'comp2')),
          'countered:We can do 18k', 'a counter is recorded with its note');
select tests.as_person('mona');
select lives_ok($$ select inf.contract_version_add((select id from ids where label = 'contract'), (select v from content), '<article>v3</article>', '{}'::jsonb, null,
                   jsonb_build_array(jsonb_build_object('id', (select id from ids where label = 'comp2'), 'status', 'countered'))) $$,
                'listing the decided request in p_resolve still works');
select tests.reset();
select ok((select resolved_in_version_id is not null from inf.contract_change_requests where id = (select id from ids where label = 'comp2')), 'and closes it');

-- ---------------------------------------------------------------------------------------------------------------
-- 4. Nightly reminders once per day (the contract is open, its deadline passed within the day)
-- ---------------------------------------------------------------------------------------------------------------
update inf.contracts set negotiation_deadline = now() - interval '1 hour' where id = (select id from ids where label = 'contract');
select ok(inf.contracts_remind() >= 1, 'the reminder goes out');
create temporary table counts (k text primary key, n int);
insert into counts select 'reminders', count(*) from inf.notifications where event = 'contract.reminder';
select ok((select n from counts) > 0, 'as a notification');
select inf.contracts_remind();
select is((select count(*)::int from inf.notifications where event = 'contract.reminder'), (select n from counts), 'a second run the same day sends nothing new');

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Jobs that die while running
-- ---------------------------------------------------------------------------------------------------------------
insert into jids select 'last', inf.job_enqueue('test.stale', '{}', now(), 'stale-last', 1);
insert into jids select 'more', inf.job_enqueue('test.more', '{}', now(), 'stale-more', 3);
select count(*) from inf.job_claim('w1', 10, array['test.stale', 'test.more']);
update inf.jobs set locked_at = now() - interval '11 minutes' where id in (select id from jids);
select is((select count(*)::int from inf.job_claim('w2', 10, array['test.stale'])), 0, 'a job that stopped on its last attempt is not claimed again');
select is((select status from inf.jobs where id = (select id from jids where label = 'last')), 'dead', 'it is dead');
select ok((select last_error like 'stopped while running on attempt 1 of 1%' from inf.jobs where id = (select id from jids where label = 'last')), 'with the reason');
select is((select count(*)::int from inf.domain_events where type = 'system.job_dead' and subject_id = (select id::text from jids where label = 'last')), 1,
          'and emits system.job_dead');
select is((select count(*)::int from inf.notifications where event = 'system.job_dead' and user_id = (select user_id from tests.people where label = 'adm')), 1,
          'staff with system.read are told in the app');
select is((select count(*)::int from inf.notification_deliveries d join inf.notifications n on n.id = d.notification_id where n.event = 'system.job_dead'), 0,
          'without email or WhatsApp');
select is((select count(*)::int from inf.notifications where event = 'system.job_dead' and user_id = (select user_id from tests.people where label = 'vic')), 0,
          'staff without system.read are not');
select is((select attempts from inf.job_claim('w2', 10, array['test.more'])), 2, 'a stopped job with attempts left is claimed again');
select is((select count(*)::int from inf.jobs where id = (select id from jids where label = 'more') and status = 'running'), 1, 'and runs');

-- A dead delivery job fails its queued deliveries.
select inf.notify((select user_id from tests.people where label = 'riya'), 'payout.paid', 'Paid', 'Paid', '/creator/earnings', '{}', true, 'hard-n1');
insert into jids select 'deliver', id from inf.jobs where idem_key = 'notify:' || (select id from inf.notifications where idem_key = 'hard-n1');
update inf.jobs set max_attempts = 1 where id = (select id from jids where label = 'deliver');
select count(*) from inf.job_claim('w3', 10, array['notify.deliver']);
select is(inf.job_finish((select id from jids where label = 'deliver'), false, 'provider down'), 'dead', 'the delivery job dies');
select is((select string_agg(distinct d.status, ',') from inf.notification_deliveries d join inf.notifications n on n.id = d.notification_id where n.idem_key = 'hard-n1'),
          'failed', 'its queued deliveries are failed, not left queued');
-- A dead-job notice whose own delivery dies tells no one again.
select inf.notify((select user_id from tests.people where label = 'adm'), 'system.job_dead', 'Stopped', 'Stopped', '/admin/system', '{}', true, 'hard-n2', array['email']);
insert into jids select 'notice', id from inf.jobs where idem_key = 'notify:' || (select id from inf.notifications where idem_key = 'hard-n2');
update inf.jobs set max_attempts = 1 where id = (select id from jids where label = 'notice');
insert into counts select 'notices', count(*) from inf.notifications where event = 'system.job_dead';
select count(*) from inf.job_claim('w4', 10, array['notify.deliver']);
select is(inf.job_finish((select id from jids where label = 'notice'), false, 'provider down'), 'dead', 'the notice''s delivery job dies');
select is((select count(*)::int from inf.notifications where event = 'system.job_dead'), (select n from counts where k = 'notices'), 'without a new notice');

select tests.reset();
select * from finish();
rollback;
