-- Migration 20261031000100_inf_campaign_threads: campaign conversations follow campaign visibility. The creator's side
-- (the creator, an agency they let negotiate) needs the creator to take part in a published campaign; staff keep their
-- access; an archived campaign's conversations are read-only.
begin;
\ir _helpers.psql
select plan(25);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_creator('riya');
select tests.make_creator('arjun');
select tests.make_creator('kiran');
select tests.make_creator('maya');
select tests.make_creator('neha');
do $$
declare v_uid uuid;
begin
  insert into inf.agencies (id, name) values ('00000000-0000-0000-0000-00000000a261', 'Acme Talent'), ('00000000-0000-0000-0000-00000000a262', 'Zen Mgmt');
  v_uid := tests.create_user('ola@acme.test');
  insert into inf.agency_members (agency_id, email, full_name, role, user_id, linked_at)
  values ('00000000-0000-0000-0000-00000000a261', 'ola@acme.test', 'Ola', 'owner', v_uid, now());
  insert into tests.people values ('ola', v_uid, gen_random_uuid(), null);
  v_uid := tests.create_user('zed@zen.test');
  insert into inf.agency_members (agency_id, email, full_name, role, user_id, linked_at)
  values ('00000000-0000-0000-0000-00000000a262', 'zed@zen.test', 'Zed', 'owner', v_uid, now());
  insert into tests.people values ('zed', v_uid, gen_random_uuid(), null);
  insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via)
  select session_id, user_id, 'agency', now(), 'otp' from tests.people where label in ('ola', 'zed');
end $$;
-- Acme may negotiate for Riya; Zen may only view.
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_negotiate_sign)
select '00000000-0000-0000-0000-00000000a261', creator_id, 'active', true, true from tests.people where label = 'riya';
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_negotiate_sign)
select '00000000-0000-0000-0000-00000000a262', creator_id, 'active', true, false from tests.people where label = 'riya';

create temporary table ids (label text primary key, id uuid);
grant select, insert on ids to authenticated;
insert into ids select label, creator_id from tests.people where creator_id is not null;
insert into ids values ('inv', gen_random_uuid()), ('open', gen_random_uuid()), ('draft', gen_random_uuid()),
                       ('paused', gen_random_uuid()), ('arch', gen_random_uuid());
insert into inf.campaigns (id, name, objective, status, visibility, created_by)
select (select id from ids where label = l), n, 'leads', s, v, (select user_id from tests.people where label = 'mona')
  from (values ('inv', 'Invite-only push', 'invite_only', 'invite_only'), ('open', 'Open push', 'open', 'open'),
               ('draft', 'Draft push', 'draft', 'open'), ('paused', 'Paused push', 'open', 'open'),
               ('arch', 'Archived push', 'active', 'open')) x(l, n, s, v);
-- Riya is invited to the invite-only, draft and archived campaigns; Arjun applied to the invite-only one; Maya has a
-- deal in the paused one.
insert into inf.campaign_invites (campaign_id, creator_id, sent_by)
select (select id from ids where label = c), (select id from ids where label = 'riya'), (select user_id from tests.people where label = 'mona')
  from unnest(array['inv', 'draft', 'arch']) c;
insert into inf.campaign_applications (campaign_id, creator_id, source, submitted_by)
select (select id from ids where label = 'inv'), (select id from ids where label = 'arjun'), 'marketplace',
       (select user_id from tests.people where label = 'arjun');
insert into inf.deals (creator_id, campaign_id, title, status, starts_on, deal_model)
select (select id from ids where label = 'maya'), (select id from ids where label = 'paused'), 'Maya paused deal', 'draft',
       (now() at time zone 'Asia/Kolkata')::date, 'fixed_only';

-- While the campaigns are live: Kiran asks on the open-marketplace one before it pauses; Riya writes on the one that
-- will be archived (with a file).
select tests.as_person('kiran');
select lives_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'paused'), 'Is this still open?', '[]', (select id from ids where label = 'kiran')) $$,
                'a creator asks about a campaign open in the marketplace');
select tests.as_person('riya');
insert into ids select 'arch_thread', inf.thread_open('campaign', (select id from ids where label = 'arch'), (select id from ids where label = 'riya'));
insert into ids values ('arch_file', gen_random_uuid());
select lives_ok(format($$ select inf.thread_post('campaign', %L, 'My draft', %L::jsonb, %L) $$, (select id from ids where label = 'arch'),
                       jsonb_build_array(jsonb_build_object('path', 'threads/' || (select id from ids where label = 'arch_thread') || '/'
                         || (select id from ids where label = 'arch_file') || '-plan.pdf', 'name', 'plan.pdf', 'mime', 'application/pdf', 'size_bytes', 10))::text,
                       (select id from ids where label = 'riya')),
                'an invited creator writes, with a file');
select tests.reset();
update inf.campaigns set status = 'paused' where id = (select id from ids where label = 'paused');
update inf.campaigns set status = 'archived' where id = (select id from ids where label = 'arch');

-- ---------------------------------------------------------------------------------------------------------------
-- Not taking part: refused
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('kiran');
select throws_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'inv'), 'Hello', '[]', (select id from ids where label = 'kiran')) $$,
                 '42501', null, 'a creator who is not invited cannot write about an invite-only campaign');
select throws_ok($$ select inf.thread_get('campaign', (select id from ids where label = 'inv'), (select id from ids where label = 'kiran')) $$,
                 '42501', null, 'nor read its conversation');
select throws_ok($$ select inf.thread_open('campaign', (select id from ids where label = 'draft'), (select id from ids where label = 'kiran')) $$,
                 '42501', null, 'nor open one about a draft campaign');
select throws_ok($$ select inf.thread_get('campaign', (select id from ids where label = 'arch'), (select id from ids where label = 'kiran')) $$,
                 '42501', null, 'nor read about an archived campaign they never took part in');
select ok(not inf.thread_file_allowed('threads/' || (select id from ids where label = 'arch_thread') || '/' || (select id from ids where label = 'arch_file') || '-plan.pdf'),
          'nor open another creator''s campaign file');
select tests.as_person('neha');
select throws_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'paused'), 'Hi', '[]', (select id from ids where label = 'neha')) $$,
                 '42501', null, 'a paused campaign takes no new conversation from someone outside it');
select tests.as_person('riya');
select throws_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'draft'), 'Hi', '[]', (select id from ids where label = 'riya')) $$,
                 '42501', null, 'an invitation does not open a draft campaign');
select tests.as_person('zed');
select throws_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'inv'), 'For Riya', '[]', (select id from ids where label = 'riya')) $$,
                 '42501', null, 'an agency that may only view cannot write for its creator');
select tests.as_person('kiran');
select is((select count(*)::int from jsonb_array_elements(inf.my_threads()) x where x ->> 'entity_type' = 'campaign'), 1,
          'a creator''s inbox lists only their own campaign conversation');

-- ---------------------------------------------------------------------------------------------------------------
-- Taking part: allowed
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select lives_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'inv'), 'Thanks for the invite', '[]', (select id from ids where label = 'riya')) $$,
                'an invited creator writes about the campaign');
select tests.as_person('arjun');
select lives_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'inv'), 'About my application', '[]', (select id from ids where label = 'arjun')) $$,
                'a creator who applied writes about it');
select tests.as_person('ola');
select lives_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'inv'), 'For Riya', '[]', (select id from ids where label = 'riya')) $$,
                'an agency that may negotiate writes for its creator');
select tests.as_person('kiran');
select lives_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'open'), 'Question before I apply', '[]', (select id from ids where label = 'kiran')) $$,
                'any creator may ask about a campaign open in the marketplace');
select lives_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'paused'), 'Any news?', '[]', (select id from ids where label = 'kiran')) $$,
                'a conversation started while the campaign was open continues after it pauses');
select tests.as_person('maya');
select lives_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'paused'), 'About my deal', '[]', (select id from ids where label = 'maya')) $$,
                'a creator with a deal in the campaign writes about it');
select tests.as_person('mona');
select lives_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'inv'), 'Welcome', '[]', (select id from ids where label = 'kiran')) $$,
                'staff may start a conversation with any creator about a campaign');
select tests.as_person('kiran');
select is(inf.thread_get('campaign', (select id from ids where label = 'inv'), (select id from ids where label = 'kiran')) ->> 'can_post', 'true',
          'and that creator may then read and answer it');

-- ---------------------------------------------------------------------------------------------------------------
-- Archived: read-only for everyone
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select is(jsonb_array_length(inf.thread_get('campaign', (select id from ids where label = 'arch'), (select id from ids where label = 'riya')) -> 'messages'), 1,
          'the creator still reads an archived campaign''s conversation');
select is(inf.thread_get('campaign', (select id from ids where label = 'arch'), (select id from ids where label = 'riya')) ->> 'can_post', 'false',
          'read-only');
select throws_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'arch'), 'One more thing', '[]', (select id from ids where label = 'riya')) $$,
                 '42501', null, 'the creator cannot write in it');
select ok(inf.thread_file_allowed('threads/' || (select id from ids where label = 'arch_thread') || '/' || (select id from ids where label = 'arch_file') || '-plan.pdf'),
          'and still opens its files');
select tests.as_person('mona');
select is(inf.thread_get('campaign', (select id from ids where label = 'arch'), (select id from ids where label = 'riya')) ->> 'can_post', 'false',
          'staff read it, read-only');
select throws_ok($$ select inf.thread_post('campaign', (select id from ids where label = 'arch'), 'Closing note', '[]', (select id from ids where label = 'riya')) $$,
                 '42501', null, 'staff cannot write in it either');

select * from finish();
rollback;
