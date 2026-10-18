-- Creator profile and KYC: own-record isolation, masked KYC, Finance-only reveal (audited), verification workflow.
begin;
\ir _helpers.psql
select plan(32);

select tests.make_creator('riya');
select tests.make_creator('arjun');
select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('fin', array['finance']);
select tests.make_staff('rev', array['content_reviewer']);
select tests.make_staff('view', array['viewer']);

create temporary table ids as select label, creator_id from tests.people where creator_id is not null;
grant select on ids to authenticated;

-- Profile: a creator edits only their own profile.
select tests.as_person('riya');
select lives_ok($$ select inf.creator_profile_update((select creator_id from ids where label = 'riya'), '{"bio":"Teaches MBA prep","niches":["MBA","mba ","Finance"]}') $$, 'creator updates own profile');
select throws_ok($$ select inf.creator_profile_update((select creator_id from ids where label = 'arjun'), '{"bio":"x"}') $$, '42501', null, 'cannot update another creator');
select throws_ok($$ select inf.creator_profile_update((select creator_id from ids where label = 'riya'), '{"phone_e164":"98765"}') $$, '22023', null, 'phone must be E.164');
select lives_ok($$ select inf.platform_save((select creator_id from ids where label = 'riya'), '{"platform":"instagram","url":"https://instagram.com/riya","handle":"riya","followers":120000}') $$, 'add platform');
select throws_ok($$ select inf.platform_save((select creator_id from ids where label = 'riya'), '{"platform":"instagram","url":"http://insecure.example","handle":"riya2"}') $$, '23514', null, 'platform URLs must be https');
select lives_ok($$ select inf.rate_card_save((select creator_id from ids where label = 'riya'), '{"platform":"instagram","format":"reel","suggested_paise":1500000}') $$, 'add rate card');
select lives_ok($$ select inf.rate_card_save((select creator_id from ids where label = 'riya'), '{"platform":"instagram","format":"reel","suggested_paise":1800000}') $$, 'rate card upserts by platform and format');
select is((select count(*)::int from inf.creator_rate_cards), 1, 'creator sees one rate card (own)');
select lives_ok($$ select inf.creator_contact_add((select creator_id from ids where label = 'riya'), 'family', 'Brother', '98765 43210', null) $$, 'add a family number');
select is((select phone_last2 from inf.creator_contacts), '10', 'only the last two digits are kept in clear');

select tests.as_person('arjun');
select is((select count(*)::int from inf.creator_platforms), 0, 'other creator sees no platforms of riya');
select is((select count(*)::int from inf.creator_contacts), 0, 'other creator sees no contacts of riya');

-- KYC: validation.
select tests.as_person('riya');
select is(inf.kyc_save((select creator_id from ids where label = 'riya'), 'ABCDE1234', 'Riya Sharma', 'unregistered', null, null, null, null) ->> 'error', 'invalid_pan', 'malformed PAN refused');
select is(inf.kyc_save((select creator_id from ids where label = 'riya'), null, 'Riya Sharma', 'unregistered', null, '12345', null, null) ->> 'error', 'invalid_account', 'short account number refused');
select is(inf.kyc_save((select creator_id from ids where label = 'riya'), null, 'Riya Sharma', 'unregistered', null, null, 'SBIN1234567', null) ->> 'error', 'invalid_ifsc', 'IFSC fifth character must be 0');
select is(inf.kyc_save((select creator_id from ids where label = 'riya'), 'ABCPS1234K', 'Riya Sharma', 'registered', '27ABCPX1234K1Z5', null, null, null) ->> 'error', 'gstin_pan_mismatch', 'GSTIN must embed the PAN');

-- Partial then complete.
select is(inf.kyc_save((select creator_id from ids where label = 'riya'), 'abcps1234k', 'Riya Sharma', 'unregistered', null, null, null, null) ->> 'status', 'pending', 'partial KYC stays pending');
select is(inf.kyc_save((select creator_id from ids where label = 'riya'), null, 'Riya Sharma', 'registered', '27ABCPS1234K1Z5', '001234567890', 'SBIN0001234', 'Riya Sharma') ->> 'status', 'submitted', 'complete KYC is submitted without re-entering the PAN');
select is(inf.kyc_view((select creator_id from ids where label = 'riya')) ->> 'pan_masked', 'XXXXXX234K', 'creator sees masked PAN');
select is(inf.kyc_view((select creator_id from ids where label = 'riya')) ->> 'bank_masked', 'XXXXXXXX7890', 'creator sees masked account');
select throws_ok($$ select inf.kyc_reveal((select creator_id from ids where label = 'riya'), 'curious') $$, '42501', null, 'creator cannot call reveal');
select throws_ok($$ select * from inf.creator_kyc $$, '42501', null, 'KYC table is not readable directly');

select tests.as_person('arjun');
select throws_ok($$ select inf.kyc_view((select creator_id from ids where label = 'riya')) $$, '42501', null, 'another creator cannot view masked KYC');

-- Staff: manager sees masked, cannot reveal; reviewer and viewer see nothing.
select tests.as_person('mona');
select is(inf.kyc_view((select creator_id from ids where label = 'riya')) ->> 'pan_masked', 'XXXXXX234K', 'manager sees masked KYC');
select throws_ok($$ select inf.kyc_reveal((select creator_id from ids where label = 'riya'), 'payout check') $$, '42501', null, 'manager cannot reveal');
select tests.as_person('rev');
select throws_ok($$ select inf.kyc_view((select creator_id from ids where label = 'riya')) $$, '42501', null, 'content reviewer cannot view KYC');

-- Finance: reveal (needs a reason, audited), verify.
select tests.as_person('fin');
select throws_ok($$ select inf.kyc_reveal((select creator_id from ids where label = 'riya'), '  ') $$, '22023', null, 'reveal needs a reason');
select is(inf.kyc_reveal((select creator_id from ids where label = 'riya'), 'Payout batch 12') ->> 'pan', 'ABCPS1234K', 'finance reveals the full PAN');
select tests.reset();
select is((select count(*)::int from inf.audit_log where entity_type = 'creator_kyc' and action = 'reveal'), 1, 'reveal is audited');
-- (The GSTIN embeds the PAN by law and is printed on invoices, so only the account number and the encrypted columns are checked.)
select ok((select count(*) = 0 from inf.audit_log where entity_type = 'creator_kyc' and (coalesce(after::text, '') ~ '001234567890|\\x' or coalesce(before::text, '') ~ '001234567890|\\x')), 'no account number or ciphertext in the audit log');
select tests.as_person('fin');
select lives_ok($$ select inf.kyc_verify((select creator_id from ids where label = 'riya'), true, null, true) $$, 'finance verifies KYC');

-- A bank change after verification sends KYC back for review.
select tests.as_person('riya');
select is(inf.kyc_save((select creator_id from ids where label = 'riya'), null, null, 'registered', '27ABCPS1234K1Z5', '009999888877', 'HDFC0000123', null) ->> 'status', 'submitted', 'bank change re-opens verification');

select * from finish();
rollback;
