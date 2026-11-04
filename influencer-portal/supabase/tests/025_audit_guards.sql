-- Migration 20261030000100_inf_audit_guards: who may act on content and contracts, internal-only eligibility,
-- own-folder avatar, KYC proof and attachment paths, and tiers for staff and creators.
begin;
\ir _helpers.psql
select plan(32);

select tests.make_creator('riya');
select tests.make_creator('arjun');
do $$
declare v_uid uuid;
begin
  -- A signed-up account with a session and no portal role at all.
  v_uid := tests.create_user('stranger@example.test');
  insert into tests.people values ('stranger', v_uid, gen_random_uuid(), null);
  -- An agency linked to Riya that may view but not act on deliverables or negotiate.
  insert into inf.agencies (id, name) values ('00000000-0000-0000-0000-00000000a025', 'Viewers Only');
  v_uid := tests.create_user('vee@viewers.test');
  insert into inf.agency_members (agency_id, email, full_name, role, user_id, linked_at)
  values ('00000000-0000-0000-0000-00000000a025', 'vee@viewers.test', 'Vee', 'owner', v_uid, now());
  insert into tests.people values ('vee', v_uid, gen_random_uuid(), null);
  insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via)
  select session_id, user_id, 'agency', now(), 'otp' from tests.people where label = 'vee';
  insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_act_deliverables)
  select '00000000-0000-0000-0000-00000000a025', creator_id, 'active', true, false from tests.people where label = 'riya';
end $$;

create temporary table ids (label text primary key, id uuid);
grant select, insert on ids to authenticated;
insert into ids select label, creator_id from tests.people where creator_id is not null;
insert into ids values ('deal', gen_random_uuid()), ('reel', gen_random_uuid()), ('story', gen_random_uuid()), ('brief', gen_random_uuid()),
                       ('brief_v', gen_random_uuid()), ('contract', gen_random_uuid()), ('cv', gen_random_uuid()), ('cr', gen_random_uuid()),
                       ('campaign', gen_random_uuid());

-- Riya's agreed deal: a live reel with a pending post, a story not started, a brief, and a sent contract with a pending
-- change request.
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model, agreed_at)
select (select id from ids where label = 'deal'), (select id from ids where label = 'riya'), 'Audit deal', 'agreed',
       (now() at time zone 'Asia/Kolkata')::date, 'fixed_only', now();
insert into inf.deal_versions (deal_id, version, comp_config, config_hash, origin, effective_from, state, decided_at)
select (select id from ids where label = 'deal'), 1, p.comp_config, inf.config_hash(p.comp_config), 'builder', now(), 'accepted', now()
  from inf.deal_presets p where p.key = 'fixed_only';
insert into inf.deliverables (id, deal_id, title, platform, format, status)
values ((select id from ids where label = 'reel'), (select id from ids where label = 'deal'), 'Launch reel', 'instagram', 'reel', 'live'),
       ((select id from ids where label = 'story'), (select id from ids where label = 'deal'), 'Story', 'instagram', 'story', 'not_started');
insert into inf.published_posts (deliverable_id, live_url, posted_on)
select (select id from ids where label = 'reel'), 'https://www.instagram.com/reel/audit/', (now() at time zone 'Asia/Kolkata')::date;
insert into inf.briefs (id, deal_id) select (select id from ids where label = 'brief'), (select id from ids where label = 'deal');
insert into inf.brief_versions (id, brief_id, version, content)
select (select id from ids where label = 'brief_v'), (select id from ids where label = 'brief'), 1, '{"objective":"Explain the online MBA"}';
update inf.briefs set current_version_id = (select id from ids where label = 'brief_v') where id = (select id from ids where label = 'brief');
insert into inf.contracts (id, deal_id, template_id, status)
select (select id from ids where label = 'contract'), (select id from ids where label = 'deal'),
       (select t.id from inf.contract_templates t where t.is_default and t.archived_at is null limit 1), 'sent';
insert into inf.contract_versions (id, contract_id, version, deal_version_id, content, html, sha256)
select (select id from ids where label = 'cv'), (select id from ids where label = 'contract'), 1,
       (select v.id from inf.deal_versions v where v.deal_id = (select id from ids where label = 'deal')), '{"sections":[]}',
       '<p>The agreement text for this test.</p>', encode(sha256(convert_to('<p>The agreement text for this test.</p>', 'UTF8')), 'hex');
update inf.contracts set current_version_id = (select id from ids where label = 'cv') where id = (select id from ids where label = 'contract');
insert into inf.contract_change_requests (id, contract_id, version_id, kind, proposed_terms, from_side, created_by)
select (select id from ids where label = 'cr'), (select id from ids where label = 'contract'), (select id from ids where label = 'cv'),
       'compensation', '{"fixed_fee_paise": 100}', 'creator', (select user_id from tests.people where label = 'riya');
insert into inf.campaigns (id, name, objective, status, eligibility, created_by)
select (select id from ids where label = 'campaign'), 'Draft campaign', 'awareness', 'draft', '{"min_followers": 100000}',
       (select user_id from tests.people where label = 'riya');
insert into inf.tiers (name, rank, active) values ('Audit tier', 1, true);

-- ---------------------------------------------------------------------------------------------------------------
-- A stranger (side NULL) is refused with 42501, and nothing changes
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('stranger');
select throws_ok($$ select inf.change_request_withdraw((select id from ids where label = 'cr')) $$, '42501', null,
                 'a stranger cannot withdraw a creator''s pending change request');
select throws_ok($$ select inf.change_request_create((select id from ids where label = 'contract'), '{"kind":"compensation","proposed_terms":{}}') $$,
                 '42501', null, 'a stranger cannot request a contract change');
select throws_ok($$ select inf.metrics_submit((select id from ids where label = 'reel'), '{"views":"999999999"}') $$, '42501', null,
                 'a stranger cannot submit metrics for a live deliverable');
select throws_ok($$ select inf.post_submit((select id from ids where label = 'reel'), 'https://www.instagram.com/reel/x/', (now() at time zone 'Asia/Kolkata')::date) $$,
                 '42501', null, 'a stranger cannot submit a live post');
select throws_ok($$ select inf.submission_add((select id from ids where label = 'story'), '{"kind":"concept","body":"idea"}') $$, '42501', null,
                 'a stranger cannot add a submission');
select throws_ok($$ select inf.deliverable_schedule((select id from ids where label = 'reel'), now() + interval '1 day') $$, '42501', null,
                 'a stranger cannot schedule a deliverable');
select throws_ok($$ select inf.brief_acknowledge((select id from ids where label = 'brief'), (select id from ids where label = 'brief_v')) $$,
                 '42501', null, 'a stranger cannot acknowledge a brief');
select tests.reset();
select is((select status from inf.contract_change_requests where id = (select id from ids where label = 'cr')), 'pending',
          'the change request is still pending');
select is((select count(*)::int from inf.post_metric_snapshots where deliverable_id = (select id from ids where label = 'reel')), 0,
          'no metrics were stored');

-- ---------------------------------------------------------------------------------------------------------------
-- An agency without the deliverables or negotiate grant is refused the same way
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('vee');
select throws_ok($$ select inf.metrics_submit((select id from ids where label = 'reel'), '{"views":"10"}') $$, '42501', null,
                 'an agency without the deliverables grant cannot submit metrics');
select throws_ok($$ select inf.change_request_withdraw((select id from ids where label = 'cr')) $$, '42501', null,
                 'an agency without the negotiate grant cannot withdraw a change request');

-- ---------------------------------------------------------------------------------------------------------------
-- The creator still can
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select lives_ok($$ select inf.metrics_submit((select id from ids where label = 'reel'), '{"views":"1200"}') $$, 'the creator submits metrics');
select tests.reset();
select is((select count(*)::int from inf.post_metric_snapshots where deliverable_id = (select id from ids where label = 'reel')), 1,
          'one snapshot is stored');

-- ---------------------------------------------------------------------------------------------------------------
-- eligibility_gaps is internal
-- ---------------------------------------------------------------------------------------------------------------
select tests.reset();
select ok(not has_function_privilege('authenticated', 'inf.eligibility_gaps(uuid,uuid)', 'execute'),
          'authenticated cannot execute eligibility_gaps');
select ok(not exists (select 1 from inf.client_grants where object_name = 'inf.eligibility_gaps(uuid, uuid)'),
          'eligibility_gaps is not in the declared client grants');
select tests.as_person('stranger');
select throws_ok($$ select inf.eligibility_gaps((select id from ids where label = 'campaign'), (select id from ids where label = 'riya')) $$,
                 '42501', null, 'a stranger cannot read a creator''s eligibility');

-- ---------------------------------------------------------------------------------------------------------------
-- Avatar and KYC proof paths stay in the creator's folder
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('arjun');
select throws_ok($$ select inf.creator_profile_update((select id from ids where label = 'arjun'),
                      jsonb_build_object('avatar_path', (select id from ids where label = 'riya')::text || '/1730000000000.jpg')) $$,
                 '22023', 'invalid avatar path', 'a creator cannot point their photo at another creator''s file');
select lives_ok($$ select inf.creator_profile_update((select id from ids where label = 'arjun'),
                      jsonb_build_object('avatar_path', (select id from ids where label = 'arjun')::text || '/1730000000000.jpg')) $$,
                'their own folder is fine');
select lives_ok($$ select inf.creator_profile_update((select id from ids where label = 'arjun'), '{"avatar_path": ""}') $$,
                'and clearing the photo is fine');
select lives_ok($$ select inf.creator_profile_update((select id from ids where label = 'arjun'), '{"bio": "Hello"}') $$,
                'a profile save without a photo is unaffected');
select is(inf.kyc_save((select id from ids where label = 'arjun'), 'ABCPE1234F', 'Arjun Test', 'unregistered', null, '123456789012',
                       'HDFC0001234', 'Arjun Test', (select id from ids where label = 'riya')::text || '/1730000000000-pan.pdf') ->> 'error',
          'invalid_proof', 'a KYC proof from another creator''s folder is refused');
select is(inf.kyc_save((select id from ids where label = 'arjun'), 'ABCPE1234F', 'Arjun Test', 'unregistered', null, '123456789012',
                       'HDFC0001234', 'Arjun Test', (select id from ids where label = 'arjun')::text || '/1730000000000-pan.pdf') ->> 'ok',
          'true', 'a proof in the creator''s own folder is saved');
select tests.reset();
select is((select proof_path from inf.creator_kyc where creator_id = (select id from ids where label = 'arjun')),
          (select id from ids where label = 'arjun')::text || '/1730000000000-pan.pdf', 'with the own-folder path');

-- ---------------------------------------------------------------------------------------------------------------
-- Attachments stay in their thread's folder
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
insert into ids select 'thread', inf.thread_open('deal', (select id from ids where label = 'deal'));
select throws_ok($$ select inf.thread_post('deal', (select id from ids where label = 'deal'), 'see file',
                      jsonb_build_array(jsonb_build_object('path', 'threads/' || (select id from ids where label = 'thread') || '/../../advice/'
                        || (select id from ids where label = 'arjun') || '/PO-2026-27-00001.pdf', 'name', 'x.pdf', 'mime', 'application/pdf', 'size_bytes', 10))) $$,
                 '22023', 'invalid file', 'an attachment path cannot climb out of its thread folder');
select throws_ok($$ select inf.thread_post('deal', (select id from ids where label = 'deal'), 'see file',
                      jsonb_build_array(jsonb_build_object('path', 'threads/' || (select id from ids where label = 'thread') || '/script.pdf',
                        'name', 'x.pdf', 'mime', 'application/pdf', 'size_bytes', 10))) $$,
                 '22023', 'invalid file', 'an attachment needs the uuid-name the upload URL gives it');
select lives_ok($$ select inf.thread_post('deal', (select id from ids where label = 'deal'), 'see file',
                      jsonb_build_array(jsonb_build_object('path', 'threads/' || (select id from ids where label = 'thread') || '/' || gen_random_uuid()
                        || '-script.pdf', 'name', 'script.pdf', 'mime', 'application/pdf', 'size_bytes', 10))) $$,
                'an attachment the app uploaded is accepted');

-- ---------------------------------------------------------------------------------------------------------------
-- Tiers for staff and creators only
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('stranger');
select is(inf.tiers_list(), '[]'::jsonb, 'a signed-up stranger reads no tiers');
select tests.as_person('vee');
select is(inf.tiers_list(), '[]'::jsonb, 'nor does an agency');
select tests.as_person('riya');
select is(jsonb_array_length(inf.tiers_list()), 1, 'a creator reads the active tiers');
select tests.reset();
select tests.act_as_service();
select is(jsonb_array_length(inf.tiers_list()), 1, 'the service role (scorecard runner) reads them');

-- ---------------------------------------------------------------------------------------------------------------
-- A blocked creator is refused like a stranger
-- ---------------------------------------------------------------------------------------------------------------
select tests.reset();
update inf.creators set is_blocked = true, blocked_reason = 'audit test' where id = (select id from ids where label = 'riya');
select tests.as_person('riya');
select throws_ok($$ select inf.change_request_withdraw((select id from ids where label = 'cr')) $$, '42501', null,
                 'a blocked creator cannot withdraw a change request');
select throws_ok($$ select inf.metrics_submit((select id from ids where label = 'reel'), '{"views":"1"}') $$, '42501', null,
                 'nor submit metrics');

select * from finish();
rollback;
