-- Agencies: membership linking, creator-granted permissions, isolation between agencies, no KYC or contact access.
begin;
\ir _helpers.psql
select plan(32);

select tests.make_creator('riya');
select tests.make_creator('arjun');
select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('rev', array['content_reviewer']);

create temporary table ids as select label, creator_id from tests.people where creator_id is not null;
grant select, insert on ids to authenticated;

-- Staff create two agencies and invite an owner to each.
select tests.as_person('mona');
insert into ids select 'acme', inf.agency_save('{"name":"Acme Talent"}');
insert into ids select 'zen', inf.agency_save('{"name":"Zen Mgmt"}');
select lives_ok($$ select inf.agency_member_add((select creator_id from ids where label = 'acme'), 'Owner@Acme.test', 'Ola Owner', 'owner') $$, 'staff invites an agency owner');
select lives_ok($$ select inf.agency_member_add((select creator_id from ids where label = 'zen'), 'zed@zen.test', 'Zed', 'owner') $$, 'and one for the other agency');
select throws_ok($$ select inf.agency_member_add((select creator_id from ids where label = 'acme'), 'riya@creator.test', 'Riya', 'member') $$, '22023', null, 'a creator''s email cannot become an agency member');
insert into ids select 'zed_member', id from inf.agency_members where email = 'zed@zen.test';
select tests.as_person('rev');
select throws_ok($$ select inf.agency_save('{"name":"Rogue"}') $$, '42501', null, 'content reviewer cannot create agencies');
-- People outside the agency get null from current_agency_id(); the owner check must still refuse them.
select throws_ok($$ select inf.agency_member_add((select creator_id from ids where label = 'acme'), 'evil@else.test', 'Evil', 'owner') $$,
  '42501', null, 'staff without agency.manage cannot add agency members');
select throws_ok($$ select inf.agency_member_remove((select creator_id from ids where label = 'zed_member')) $$,
  '42501', null, 'or remove them');
select tests.as_person('riya');
select throws_ok($$ select inf.agency_member_add((select creator_id from ids where label = 'acme'), 'evil@else.test', 'Evil', 'owner') $$,
  '42501', null, 'a creator cannot add themselves as an agency owner');
select throws_ok($$ select inf.agency_link_request((select creator_id from ids where label = 'acme'), (select creator_id from ids where label = 'arjun')) $$,
  '42501', null, 'or send link requests in an agency''s name');
select throws_ok($$ select inf.agency_link_request_by_handle((select creator_id from ids where label = 'acme'), 'anyone') $$,
  '42501', null, 'by handle either');

-- The owner signs in: first sign-in links the membership by verified email.
select tests.reset();
insert into tests.people select 'ola', tests.create_user('owner@acme.test'), gen_random_uuid(), null;
insert into tests.people select 'zed', tests.create_user('zed@zen.test'), gen_random_uuid(), null;
insert into tests.people select 'stranger', tests.create_user('nobody@else.test'), gen_random_uuid(), null;
select tests.as_person('stranger');
select is(inf.agency_account_link() ->> 'error', 'not_registered', 'an uninvited account is refused');
select is(inf.session_register() ->> 'error', 'no_portal_access', 'and gets no session');
select tests.as_person('ola');
select is((inf.agency_account_link() ->> 'linked')::boolean, true, 'invited owner is linked on first sign-in');
select is(inf.session_register() ->> 'kind', 'agency', 'agency session registers (verified by the sign-in)');
select is(inf.me() ->> 'kind', 'agency', 'me() says agency');
select is(inf.me() -> 'agency' ->> 'name', 'Acme Talent', 'with the agency name');
select is(inf.current_agency_id(), (select creator_id from ids where label = 'acme'), 'current_agency_id() resolves');
select is(inf.is_staff(), false, 'agency users are not staff');
select is(inf.current_creator_id(), null, 'and not creators');
select tests.as_person('zed');
select inf.agency_account_link();
select inf.session_register();

-- Ola requests a link to Riya; it does nothing until Riya accepts.
select tests.as_person('ola');
insert into ids select 'link', inf.agency_link_request((select creator_id from ids where label = 'acme'), (select creator_id from ids where label = 'riya'));
select throws_ok($$ select inf.agency_link_request((select creator_id from ids where label = 'zen'), (select creator_id from ids where label = 'riya')) $$, '42501', null, 'an owner cannot request links for another agency');
select is(inf.agency_can((select creator_id from ids where label = 'riya'), 'view'), false, 'pending link grants nothing');
select is((select count(*)::int from inf.agency_creators()), 1, 'pending link is listed for the agency');

-- Riya accepts with "view" and "deliverables" only.
select tests.as_person('arjun');
select throws_ok($$ select inf.agency_link_respond((select creator_id from ids where label = 'link'), true, true, true, true, true) $$, '42501', null, 'another creator cannot accept the link');
select tests.as_person('riya');
select is((select count(*)::int from inf.my_agency_links()), 1, 'creator sees the request');
select lives_ok($$ select inf.agency_link_respond((select creator_id from ids where label = 'link'), true, true, true, false, false) $$, 'creator accepts with chosen grants');
select inf.platform_save((select creator_id from ids where label = 'riya'), '{"platform":"youtube","url":"https://youtube.com/@riya","handle":"riya"}');
select inf.kyc_save((select creator_id from ids where label = 'riya'), 'ABCPS1234K', 'Riya', 'unregistered', null, '001234567890', 'SBIN0001234', 'Riya');

select tests.as_person('ola');
select is(inf.agency_can((select creator_id from ids where label = 'riya'), 'deliverables'), true, 'granted permission applies');
select is(inf.agency_can((select creator_id from ids where label = 'riya'), 'negotiate'), false, 'ungranted permission does not');
select is((select count(*)::int from inf.creator_platforms), 1, 'agency reads the managed creator''s platforms');
select throws_ok($$ select inf.kyc_view((select creator_id from ids where label = 'riya')) $$, '42501', null, 'agency never sees KYC');
select throws_ok($$ select inf.platform_save((select creator_id from ids where label = 'riya'), '{"platform":"x","url":"https://x.com/r","handle":"r"}') $$, '42501', null, 'agency cannot edit the profile');
select is((select count(*)::int from inf.creators), 0, 'agency cannot read the creators table (contact details)');

-- Other agency sees nothing; revocation takes effect at once.
select tests.as_person('zed');
select is((select count(*)::int from inf.creator_platforms), 0, 'another agency sees nothing');
select tests.as_person('riya');
select inf.agency_link_respond((select creator_id from ids where label = 'link'), false, false, false, false, false);
select tests.as_person('ola');
select is(inf.agency_can((select creator_id from ids where label = 'riya'), 'view'), false, 'revoked by the creator: access ends');

select * from finish();
rollback;
