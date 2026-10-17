-- Campaigns: staff building and opening, eligibility, marketplace visibility (no budget or notes for creators),
-- invites, applications, offers and acceptance, agency negotiation, isolation between creators.
begin;
\ir _helpers.psql
select plan(39);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('rev', array['content_reviewer']);
select tests.make_staff('fin', array['finance']);
select tests.make_creator('riya');
select tests.make_creator('arjun');
select tests.make_creator('tiny');
update inf.creators set approved_at = now(), niches = '{mba}', languages = '{English,Hindi}', state = 'Delhi' where handle in ('riya', 'arjun', 'tiny');
insert into inf.creator_platforms (creator_id, platform, url, handle, followers)
select creator_id, 'instagram', 'https://instagram.com/' || label, label, case label when 'tiny' then 500 else 50000 end
  from tests.people where label in ('riya', 'arjun', 'tiny');
insert into public.catalog_universities (id, name) values (9001, 'Test University');
insert into public.catalog_programs (id, university_id, program_name, mode, level, fee_total) values (7001, 9001, 'Online MBA', 'online', 'PG', 150000);

create temporary table ids (label text primary key, id uuid);
grant select, insert on ids to authenticated;
insert into ids select label, creator_id from tests.people where creator_id is not null;

-- Build and open.
select tests.as_person('mona');
insert into ids select 'camp', inf.campaign_save('{"name":"MBA Diwali push","objective":"leads","budget_paise":50000000,"slots":2,
  "internal_notes":"Target 300 leads","compensation_summary":"Fixed fee plus commission per enrolment",
  "eligibility":{"min_followers":10000,"platforms":["instagram"],"niches":["mba"]},"programme_ids":["7001"]}');
select is((select count(*)::int from inf.campaign_programmes where campaign_id = (select id from ids where label = 'camp')), 1, 'programme linked');
select throws_ok($$ select inf.campaign_save('{"name":"Bad prog","objective":"leads","programme_ids":["123456"]}') $$, '22023', null, 'unknown catalogue programme refused');
select throws_ok($$ select inf.campaign_set_status((select id from ids where label = 'camp'), 'open') $$, '22023', null, 'cannot open without deliverables and an end date');
select inf.campaign_save(jsonb_build_object('id', (select id from ids where label = 'camp'), 'name', 'MBA Diwali push', 'objective', 'leads',
  'budget_paise', 50000000, 'slots', 2, 'internal_notes', 'Target 300 leads', 'ends_on', (current_date + 30)::text,
  'compensation_summary', 'Fixed fee plus commission per enrolment',
  'deliverables', '[{"platform":"instagram","format":"reel","count":2}]'::jsonb,
  'eligibility', '{"min_followers":10000,"platforms":["instagram"],"niches":["mba"]}'::jsonb));
select lives_ok($$ select inf.campaign_set_status((select id from ids where label = 'camp'), 'open') $$, 'campaign opened');
select throws_ok($$ select inf.campaign_set_status((select id from ids where label = 'camp'), 'draft') $$, '22023', null, 'invalid status transition refused');
select tests.as_person('rev');
select throws_ok($$ select inf.campaign_save('{"name":"Rogue","objective":"leads"}') $$, '42501', null, 'content reviewer cannot create campaigns');
select tests.as_person('fin');
select throws_ok($$ select inf.campaign_save('{"name":"Rogue","objective":"leads"}') $$, '42501', null, 'finance cannot create campaigns');

-- Creators: marketplace with eligibility; no budget or internal notes.
select tests.as_person('riya');
select is(jsonb_array_length(inf.marketplace()), 1, 'eligible creator sees the campaign');
select ok(not (inf.marketplace() -> 0 ? 'budget_paise') and not (inf.marketplace() -> 0 ? 'internal_notes'), 'no budget or internal notes for creators');
select is(inf.marketplace() -> 0 ->> 'slots_left', '2', 'slots left shown');
select is((select count(*)::int from inf.campaigns), 0, 'campaigns table returns nothing to creators');
select is((select count(*)::int from inf.campaign_programmes_view((select id from ids where label = 'camp'))), 1, 'creator sees programme cards');
select tests.as_person('tiny');
select is(jsonb_array_length(inf.marketplace()), 0, 'ineligible creator does not see it');
select is((inf.marketplace(null, true) -> 0 -> 'gaps') ->> 0, 'followers', 'with p_all, the gap is explained');
select throws_ok($$ select inf.campaign_apply((select id from ids where label = 'camp'), (select id from ids where label = 'tiny'), 'pls', null, '{"deal_type":"fixed"}') $$, '22023', null, 'ineligible creator cannot apply');

-- Riya applies; Arjun cannot apply for her; Arjun can't see her application.
select tests.as_person('arjun');
select throws_ok($$ select inf.campaign_apply((select id from ids where label = 'camp'), (select id from ids where label = 'riya'), 'x', null, '{"deal_type":"fixed"}') $$, '42501', null, 'cannot apply on behalf of another creator');
select tests.as_person('riya');
insert into ids select 'app', inf.campaign_apply((select id from ids where label = 'camp'), (select id from ids where label = 'riya'),
  'I teach MBA prep to 50k students', array['https://instagram.com/p/abc'], '{"deal_type":"hybrid","fixed_fee_paise":1500000,"includes_commission":true,"deliverables":[{"platform":"instagram","format":"reel","count":2}]}');
select throws_ok($$ select inf.campaign_apply((select id from ids where label = 'camp'), (select id from ids where label = 'riya'), 'again', null, '{"deal_type":"fixed"}') $$, '23505', null, 'one application per campaign');
select throws_ok($$ select inf.campaign_apply((select id from ids where label = 'camp'), (select id from ids where label = 'riya'), 'x', array['http://insecure.example'], '{}') $$, null, null, 'sample links must be https (or it is a duplicate)');
select is((select count(*)::int from inf.my_applications()), 1, 'creator sees their application');
select tests.as_person('arjun');
select throws_ok($$ select inf.application_detail((select id from ids where label = 'app')) $$, '42501', null, 'another creator cannot open it');
select is((select count(*)::int from inf.my_applications()), 0, 'and does not list it');

-- Staff counter; the creator accepts. The same side cannot accept its own offer.
select tests.reset();
select is((select count(*)::int from inf.notifications where event = 'application.submitted' and user_id = (select user_id from tests.people where label = 'mona')), 1, 'campaign owner notified of the application');
select tests.as_person('mona');
select lives_ok($$ select inf.application_shortlist((select id from ids where label = 'app')) $$, 'shortlisted');
insert into ids select 'offer', inf.offer_make((select id from ids where label = 'app'), '{"deal_type":"hybrid","fixed_fee_paise":1200000,"includes_commission":true,"deliverables":[{"platform":"instagram","format":"reel","count":2}]}', 'Can do 12k fixed');
select throws_ok($$ select inf.offer_accept((select id from ids where label = 'offer')) $$, '22023', null, 'Eduwit cannot accept its own offer');
select inf.application_message((select id from ids where label = 'app'), 'Happy to discuss the reel timing.');
select tests.as_person('riya');
select is(jsonb_array_length(inf.application_detail((select id from ids where label = 'app')) -> 'offers'), 2, 'creator sees both offers');
select is(inf.application_detail((select id from ids where label = 'app')) -> 'messages' -> 0 ->> 'author_side', 'eduwit', 'and the message');
select lives_ok($$ select inf.offer_accept((select id from ids where label = 'offer')) $$, 'creator accepts the counter-offer');
select tests.reset();
select is((select count(*)::int from inf.jobs where kind = 'deal.from_application' and payload ->> 'application_id' = (select id from ids where label = 'app')::text), 1, 'acceptance queues the deal job');
select tests.as_person('riya');
select is(inf.application_detail((select id from ids where label = 'app')) ->> 'status', 'accepted', 'application accepted');
select tests.reset();
select is((select count(*)::int from inf.domain_events where type = 'application.accepted'), 1, 'application.accepted emitted for Phase 3');
select is((select accepted_terms ->> 'fixed_fee_paise' from inf.campaign_applications where id = (select id from ids where label = 'app')), '1200000', 'agreed terms recorded');

-- Invites: invite-only campaign, agency negotiates for the creator.
select tests.as_person('mona');
insert into ids select 'vip', inf.campaign_save(jsonb_build_object('name', 'VIP invite', 'objective', 'awareness', 'visibility', 'invite_only',
  'ends_on', (current_date + 10)::text, 'deliverables', '[{"platform":"instagram","format":"story","count":3}]'::jsonb));
select inf.campaign_set_status((select id from ids where label = 'vip'), 'invite_only');
select is(inf.campaign_invite((select id from ids where label = 'vip'), array[(select id from ids where label = 'arjun'), (select id from ids where label = 'tiny')], 'You would be great'), 2, 'two invites sent');
select tests.as_person('riya');
select is((select count(*)::int from jsonb_array_elements(inf.marketplace()) x where x ->> 'id' = (select id from ids where label = 'vip')::text), 0, 'invite-only campaign hidden from the marketplace');
select is(inf.campaign_for_creator((select id from ids where label = 'vip')), null, 'and not openable by uninvited creators');
select tests.reset();
insert into inf.agencies (id, name) values ('00000000-0000-0000-0000-00000000a9e1', 'Acme');
insert into tests.people select 'ola', tests.create_user('ola@acme.test'), gen_random_uuid(), null;
insert into inf.agency_members (agency_id, email, full_name, role, user_id) select '00000000-0000-0000-0000-00000000a9e1', 'ola@acme.test', 'Ola', 'owner', user_id from tests.people where label = 'ola';
insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via) select session_id, user_id, 'agency', now(), 'otp' from tests.people where label = 'ola';
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_negotiate_sign) select '00000000-0000-0000-0000-00000000a9e1', id, 'active', true, true from ids where label = 'arjun';
select tests.as_person('ola');
select is((select count(*)::int from inf.my_invites((select id from ids where label = 'arjun'))), 1, 'agency with the negotiate grant sees the creator''s invite');
select lives_ok($$ select inf.campaign_apply((select id from ids where label = 'vip'), (select id from ids where label = 'arjun'), 'Arjun is in', null, '{"deal_type":"fixed","fixed_fee_paise":500000}') $$, 'agency accepts the invite for the creator');
select throws_ok($$ select inf.my_invites((select id from ids where label = 'tiny')) $$, '42501', null, 'but not for creators it does not manage');
select tests.reset();
select is((select status from inf.campaign_invites where creator_id = (select id from ids where label = 'arjun')), 'accepted', 'invite marked accepted');

-- Rejection needs a reason; slots are enforced.
select tests.as_person('mona');
select throws_ok($$ select inf.application_reject((select id from inf.campaign_applications where creator_id = (select id from ids where label = 'arjun')), ' ') $$, '22023', null, 'rejection needs a reason');

select * from finish();
rollback;
