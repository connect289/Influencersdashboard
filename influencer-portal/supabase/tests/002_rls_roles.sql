-- Row-level access per role on the identity and platform tables (spec 2.3, 20).
begin;
\ir _helpers.psql
select plan(40);

-- People
select tests.make_staff('admin', array['super_admin']);
select tests.make_staff('manager', array['influencer_manager']);
select tests.make_staff('reviewer', array['content_reviewer']);
select tests.make_staff('finance', array['finance']);
select tests.make_staff('viewer', array['viewer']);
select tests.make_staff('unverified', array['super_admin'], false);
select tests.make_staff('suspended', array['super_admin']);
update inf.staff_profiles set status = 'suspended' where user_id = (select user_id from tests.people where label = 'suspended');
select tests.make_creator('alice');
select tests.make_creator('bob');
select tests.make_creator('blocky');
update inf.creators set status = 'blocked' where id = (select creator_id from tests.people where label = 'blocky');
insert into inf.creators (display_name, handle, status) values ('Prospect Only', 'prospect_only', 'prospect');
-- A user of another product on the shared Auth (e.g. a B2C counsellor): no inf profile at all.
insert into tests.people select 'outsider', u, gen_random_uuid(), null from tests.create_user('outsider@b2c.test') u;

-- ---------- anon ----------
select tests.act_as_anon();
select throws_ok($$ select count(*) from inf.creators $$, '42501', null, 'anon: no access to creators');
select throws_ok($$ select inf.me() $$, '42501', null, 'anon: cannot call me()');
select tests.reset();

-- ---------- outsider (signed in to another product) ----------
select tests.as_person('outsider');
select is((select count(*)::int from inf.creators), 0, 'outsider: sees no creators');
select is((select count(*)::int from inf.staff_profiles), 0, 'outsider: sees no staff');
select is(inf.has_perm('creator.read'), false, 'outsider: has no permission');
select is(inf.me() ->> 'kind', 'none', 'outsider: me() kind is none');
select is((inf.session_register()) ->> 'error', 'no_portal_access', 'outsider: cannot register a portal session');
select is((select count(*)::int from inf.settings_list()), 0, 'outsider: sees no settings');

-- ---------- unverified staff session (code not entered yet) ----------
select tests.as_person('unverified');
select is(inf.has_perm('creator.read'), false, 'unverified staff: no permissions before the emailed code');
select is((select count(*)::int from inf.creators), 0, 'unverified staff: sees no creators');
select is((select count(*)::int from inf.audit_log), 0, 'unverified staff: no audit log');
select is((inf.me() -> 'session' ->> 'verified')::boolean, false, 'unverified staff: me() reports an unverified session');

-- ---------- suspended staff ----------
select tests.as_person('suspended');
select is(inf.has_perm('settings.read'), false, 'suspended staff: no permissions');
select is((select count(*)::int from inf.creators), 0, 'suspended staff: sees no creators');

-- ---------- super admin ----------
select tests.as_person('admin');
select is((select count(*)::int from inf.creators), 4, 'super admin: sees all creators');
select ok(inf.has_perm('staff.manage') and inf.has_perm('lead.contacts') and inf.has_perm('audit.read'), 'super admin: holds platform permissions');
select is(inf.has_perm('contract.countersign'), false, 'super admin without the signatory flag cannot countersign');
select ok((select count(*) from inf.staff_list()) >= 7, 'super admin: lists staff');
select ok((select count(*) from inf.audit_log) > 0, 'super admin: reads the audit log');

-- ---------- influencer manager ----------
select tests.as_person('manager');
select is((select count(*)::int from inf.creators), 4, 'manager: sees all creators');
select is(inf.has_perm('lead.contacts'), false, 'manager: cannot see student contacts');
select is(inf.has_perm('kyc.reveal'), false, 'manager: cannot reveal PAN or bank');
select is((select count(*)::int from inf.staff_list()), 0, 'manager: cannot list staff for administration');
select is((select count(*)::int from inf.audit_log), 0, 'manager: no audit log');
select throws_ok($$ select inf.staff_save((select user_id from tests.people where label='viewer'), 'X', 'x@staff.test', array['super_admin'], false, null) $$,
                 '42501', null, 'manager: cannot change roles');

-- ---------- content reviewer ----------
select tests.as_person('reviewer');
select is((select count(*)::int from inf.creators), 4, 'reviewer: can view creators');
select ok(not inf.has_perm('ledger.read') and not inf.has_perm('payout.read') and not inf.has_perm('deal.read'), 'reviewer: no finance or deal access');
select ok(inf.has_perm('deliverable.review') and inf.has_perm('compliance.override'), 'reviewer: content permissions');

-- ---------- finance ----------
select tests.as_person('finance');
select ok(inf.has_perm('kyc.reveal') and inf.has_perm('payout.approve') and inf.has_perm('tax.manage'), 'finance: money and KYC permissions');
select ok(not inf.has_perm('creator.write') and not inf.has_perm('campaign.write'), 'finance: read-only elsewhere');

-- ---------- viewer ----------
select tests.as_person('viewer');
select is((select count(*)::int from inf.creators), 0, 'viewer: no creator records (dashboards only)');
select ok(inf.has_perm('analytics.read'), 'viewer: analytics');

-- ---------- creators ----------
select tests.as_person('alice');
select is((select count(*)::int from inf.creators), 1, 'creator: sees exactly one creator row');
select is((select handle from inf.creators), 'alice', 'creator: and it is their own');
select is((select count(*)::int from inf.staff_profiles), 0, 'creator: sees no staff profiles');
select is((select count(*)::int from inf.audit_log), 0, 'creator: no audit log');
select is(inf.has_perm('creator.read'), false, 'creator: holds no staff permission');
select is((select count(*)::int from inf.creator_accounts), 1, 'creator: sees only their own account link');

select tests.as_person('blocky');
select is((select count(*)::int from inf.creators), 0, 'blocked creator: sees nothing');

-- Revoked session (remote logout)
select tests.reset();
update inf.user_sessions set revoked_at = now() where session_id = (select session_id from tests.people where label = 'bob');
select tests.as_person('bob');
select is((select count(*)::int from inf.creators), 0, 'creator with a revoked session: sees nothing');

select tests.reset();
select * from finish();
rollback;
