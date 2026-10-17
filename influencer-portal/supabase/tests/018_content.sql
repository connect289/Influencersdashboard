-- Content: briefs (versions, acknowledgement, Q&A), deliverables and the workflow, submissions (immutable, file
-- paths scoped to the deliverable), the compliance gate (server-recorded scans, overrides, ASCI checklist), revision
-- limits and extensions, comments, go-live and verification, metrics, penalty proposals, and who can see what.
begin;
\ir _helpers.psql
select plan(120);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('cara', array['content_reviewer']);
select tests.make_staff('fin', array['finance']);
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
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_act_deliverables)
select '00000000-0000-0000-0000-00000000a001', creator_id, 'active', true, true from tests.people where label = 'riya';
insert into inf.agency_creator_links (agency_id, creator_id, status, can_view, can_act_deliverables)
select '00000000-0000-0000-0000-00000000a002', creator_id, 'active', true, false from tests.people where label = 'riya';

create temporary table ids (label text primary key, id uuid);
grant select, insert, update on ids to authenticated, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;

-- An agreed deal and a draft deal for Riya.
insert into ids values ('deal', gen_random_uuid()), ('draft_deal', gen_random_uuid());
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model, agreed_at)
select (select id from ids where label = 'deal'), (select id from ids where label = 'riya'), 'Diwali deal', 'agreed', (now() at time zone 'Asia/Kolkata')::date, 'fixed_only', now();
insert into inf.deals (id, creator_id, title, status, starts_on, deal_model)
select (select id from ids where label = 'draft_deal'), (select id from ids where label = 'riya'), 'Holi deal', 'draft', (now() at time zone 'Asia/Kolkata')::date, 'fixed_only';
insert into inf.deal_versions (deal_id, version, comp_config, config_hash, origin, effective_from, state, decided_at)
select (select id from ids where label = 'deal'), 1, p.comp_config, inf.config_hash(p.comp_config), 'builder', now(), 'accepted', now()
  from inf.deal_presets p where p.key = 'fixed_only';
insert into ids select 'version', id from inf.deal_versions where deal_id = (select id from ids where label = 'deal');

-- ---------------------------------------------------------------------------------------------------------------
-- Seeds and the banned-claims list
-- ---------------------------------------------------------------------------------------------------------------
select is((select count(*)::int from inf.banned_claims where active), 11, 'eleven starting banned claims');
select is((select count(*)::int from inf.brief_templates where is_default), 1, 'one default brief template');

select tests.as_person('mona');
select throws_ok($$ select inf.banned_claim_save('{"pattern":"easy money","kind":"phrase","severity":"block"}') $$, '42501', null,
                 'a manager cannot edit the banned-claims list');
select tests.as_person('cara');
select lives_ok($$ select inf.banned_claim_save('{"pattern":"easy money","kind":"phrase","severity":"block"}') $$, 'a reviewer adds a claim');
select throws_ok($$ select inf.banned_claim_save('{"pattern":"Easy Money","kind":"phrase","severity":"warn"}') $$, '23505', null,
                 'duplicates are refused (case-insensitive)');
select is(jsonb_array_length(inf.banned_claims_active()), 12, 'the scan list has the new claim');
select tests.as_person('riya');
select is(inf.banned_claims_active(), '[]'::jsonb, 'creators do not read the list');
select is((select count(*)::int from inf.banned_claims), 0, 'creators cannot select banned claims');

-- ---------------------------------------------------------------------------------------------------------------
-- Brief and deliverables
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select throws_ok($$ select inf.brief_create(jsonb_build_object('deal_id', (select id from ids where label = 'deal'))) $$, '42501', null,
                 'a creator cannot create a brief');
select tests.as_person('mona');
select ok(inf.brief_source((select id from ids where label = 'deal')) -> 'template' ->> 'name' = 'Standard creator brief',
          'the brief source uses the default template');
select lives_ok($$ insert into ids select 'brief', inf.brief_create(jsonb_build_object('deal_id', (select id from ids where label = 'deal'),
  'content', '{"objective":"Explain the online MBA","key_messages":{"type":"doc","content":[]}}'::jsonb)) $$, 'a manager creates the brief');
select throws_ok($$ select inf.brief_create(jsonb_build_object('deal_id', (select id from ids where label = 'deal'))) $$, '23505', null,
                 'one brief per deal');
select is(inf.deliverables_create((select id from ids where label = 'deal'), '[
  {"title":"Launch reel","platform":"instagram","format":"reel","config_ref":"reel1",
   "due_dates":{"concept":"2020-01-01T18:29:59Z","draft":"2099-01-01T18:29:59Z","live":"2099-02-01T18:29:59Z"}},
  {"title":"Story set","platform":"instagram","format":"story","stages":{"brief":true,"concept":false,"draft":false,"schedule":false,"verify":true,"metrics":false}}
]'::jsonb), 2, 'two deliverables');
insert into ids select 'reel', id from inf.deliverables where title = 'Launch reel';
insert into ids select 'story', id from inf.deliverables where title = 'Story set';
select ok((select bool_and(code ~ '^DV-\d{5}$' and brief_id = (select id from ids where label = 'brief')) from inf.deliverables),
          'deliverables get a code and the brief');
select is((select revision_limit from inf.deliverables where id = (select id from ids where label = 'reel')), 2, 'the default revision limit applies');
select is((select count(*)::int from inf.tracking_links where deliverable_id in (select id from ids where label in ('reel', 'story'))), 2,
          'each deliverable gets its own tracking link');
select ok((select bool_and(code ~ '^[A-Z0-9]{2,12}(-[A-Z0-9]{1,8}){1,3}$' and destination = 'whatsapp_witty'
                           and creator_id = (select id from ids where label = 'riya') and deal_id = (select id from ids where label = 'deal'))
             from inf.tracking_links where deliverable_id in (select id from ids where label in ('reel', 'story'))),
          'with a valid code, for the creator and deal, sent to Witty');

select tests.as_person('riya');
select is(inf.brief_detail((select id from ids where label = 'brief')), null, 'creators do not see an unpublished brief');
select is(inf.my_briefs((select id from ids where label = 'riya')), '[]'::jsonb, 'nothing in My briefs yet');

select tests.as_person('mona');
select lives_ok($$ select inf.brief_publish((select id from ids where label = 'brief')) $$, 'publish version 1');
select throws_ok($$ select inf.brief_publish((select id from ids where label = 'brief')) $$, '22023', 'nothing changed since the last version',
                 'publishing an unchanged brief is refused');
select tests.reset();
select is((select count(*)::int from inf.notifications n join tests.people p on p.user_id = n.user_id
            where p.label in ('riya', 'ola') and n.event = 'brief.published'), 2, 'the creator and the acting agency are told');
select is((select count(*)::int from inf.notifications n join tests.people p on p.user_id = n.user_id
            where p.label = 'zed' and n.event = 'brief.published'), 0, 'an agency without the deliverables grant is not');

select tests.as_person('riya');
select ok(inf.brief_detail((select id from ids where label = 'brief')) ->> 'side' = 'creator', 'the creator reads the published brief');
select is(inf.brief_detail((select id from ids where label = 'brief')) -> 'draft_content', 'null'::jsonb, 'but not the working copy');
select is((select count(*)::int from inf.briefs), 0, 'creators cannot select briefs directly');
select tests.as_person('arjun');
select is(inf.brief_detail((select id from ids where label = 'brief')), null, 'another creator sees nothing');
select tests.as_person('zed');
select is(inf.brief_detail((select id from ids where label = 'brief')), null, 'an agency without the deliverables grant sees nothing');
select tests.as_person('ola');
select ok(inf.brief_detail((select id from ids where label = 'brief')) ->> 'side' = 'agency', 'the acting agency reads the brief');

select tests.as_person('riya');
select throws_ok($$ select inf.submission_add((select id from ids where label = 'reel'), '{"kind":"concept","body":"My idea"}') $$, '22023', null,
                 'nothing is submitted before the brief is acknowledged');
select throws_ok($$ select inf.brief_acknowledge((select id from ids where label = 'brief'), gen_random_uuid()) $$, '22023', null,
                 'acknowledging a version that is not current is refused');
select lives_ok($$ select inf.brief_acknowledge((select id from ids where label = 'brief'),
                     (select (inf.brief_detail((select id from ids where label = 'brief')) -> 'current' ->> 'id')::uuid)) $$, 'the creator acknowledges');
select lives_ok($$ select inf.brief_acknowledge((select id from ids where label = 'brief'),
                     (select (inf.brief_detail((select id from ids where label = 'brief')) -> 'current' ->> 'id')::uuid)) $$, 'acknowledging twice is harmless');
select tests.reset();
select is((select array_agg(status order by position) from inf.deliverables), array['brief_acknowledged', 'brief_acknowledged'],
          'acknowledging starts the deliverables');
select is((select count(*)::int from inf.domain_events where type = 'brief.acknowledged'), 1, 'one brief.acknowledged event');
select is((select count(*)::int from inf.deliverable_transitions where actor_side = 'system' and action = 'acknowledge_brief'), 2,
          'the transitions are recorded');

-- Q&A
select tests.as_person('riya');
select lives_ok($$ insert into ids select 'q1', inf.brief_question_add((select id from ids where label = 'brief'), 'Can I film in Hindi?') $$,
                'the creator asks a question');
select tests.as_person('fin');
select throws_ok($$ select inf.brief_question_add((select id from ids where label = 'brief'), 'Yes', (select id from ids where label = 'q1')) $$,
                 '42501', null, 'finance cannot answer on a brief');
select tests.as_person('mona');
select lives_ok($$ select inf.brief_question_add((select id from ids where label = 'brief'), 'Yes, Hindi is fine.', (select id from ids where label = 'q1')) $$,
                'the manager answers');
select is((inf.briefs_list('{}') -> 0 ->> 'open_questions')::int, 0, 'no open questions after the answer');

-- ---------------------------------------------------------------------------------------------------------------
-- Submissions and the compliance gate
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select throws_ok($$ select inf.submission_add((select id from ids where label = 'reel'),
                     jsonb_build_object('kind', 'concept', 'files', jsonb_build_array(jsonb_build_object('path', 'other/0b6f7c1e-1111-4a2b-9c3d-123456789abc-a.mp4')))) $$,
                 '22023', 'invalid file', 'files must live under the deliverable');
select lives_ok($$ insert into ids select 'c1', inf.submission_add((select id from ids where label = 'reel'),
                     jsonb_build_object('kind', 'concept', 'body', 'Guaranteed placement after this MBA!',
                       'files', jsonb_build_array(jsonb_build_object('path', (select id from ids where label = 'reel')::text || '/0b6f7c1e-1111-4a2b-9c3d-123456789abc-script.pdf', 'name', 'script.pdf')))) $$,
                'the creator submits a concept');
select ok(inf.deliverable_file_allowed((select id from ids where label = 'reel'), (select id from ids where label = 'reel')::text || '/0b6f7c1e-1111-4a2b-9c3d-123456789abc-script.pdf'),
          'the creator may open their file');
select throws_ok($$ select inf.submission_review((select id from ids where label = 'c1'), 'approve', null) $$, '42501', null, 'a creator cannot review');
select throws_ok($$ select inf.compliance_record((select id from ids where label = 'c1'), '[{"kind":"banned_claims","passed":true}]') $$, '42501', null,
                 'a creator cannot record a clean scan');
select tests.as_person('arjun');
select ok(not inf.deliverable_file_allowed((select id from ids where label = 'reel'), (select id from ids where label = 'reel')::text || '/0b6f7c1e-1111-4a2b-9c3d-123456789abc-script.pdf'),
          'another creator may not open it');

select tests.as_person('cara');
select throws_ok($$ select inf.submission_review((select id from ids where label = 'c1'), 'approve', null) $$, '22023', 'the compliance scan has not run on this submission',
                 'approval waits for the scan');
select tests.act_as_service();
select lives_ok($$ select inf.compliance_record((select id from ids where label = 'c1'), '[{"kind":"banned_claims","passed":false,"result":{"claims":[{"text":"Guaranteed placement"}]}}]') $$,
                'the server records the scan');
select tests.as_person('cara');
select throws_ok($$ select inf.submission_review((select id from ids where label = 'c1'), 'approve', null) $$, '22023', 'compliance checks failed: fix or override them first',
                 'a failed scan blocks approval');
select tests.as_person('mona');
select throws_ok($$ select inf.compliance_override((select id from inf.compliance_checks limit 1), 'Context makes it fine') $$, '42501', null,
                 'a manager without the override permission cannot override');
select tests.as_person('cara');
select throws_ok($$ select inf.compliance_override((select id from inf.compliance_checks limit 1), '') $$, '22023', null, 'an override needs a reason');
select lives_ok($$ select inf.compliance_override((select id from inf.compliance_checks limit 1), 'Quoted to explain what not to believe') $$,
                'a reviewer overrides with a reason');
select lives_ok($$ select inf.submission_review((select id from ids where label = 'c1'), 'approve', 'Good concept') $$,
                'the concept is approved (no checklist before the draft)');
select tests.reset();
select is((select status from inf.deliverables where id = (select id from ids where label = 'reel')), 'concept_approved', 'concept approved');
select throws_ok($$ update inf.deliverable_submissions set body = 'changed' where id = (select id from ids where label = 'c1') $$, '42501', null,
                 'a submission is immutable');

-- Draft, revision limit and extensions
select tests.as_person('riya');
select lives_ok($$ insert into ids select 'd1', inf.submission_add((select id from ids where label = 'reel'), '{"kind":"draft","body":"#ad My honest MBA review"}') $$,
                'the creator submits a draft');
select tests.act_as_service();
select lives_ok($$ select inf.compliance_record((select id from ids where label = 'd1'), '[{"kind":"banned_claims","passed":true},{"kind":"disclosure","passed":true}]') $$,
                'clean scans recorded');
select tests.as_person('mona');
select lives_ok($$ select inf.deliverable_update((select id from ids where label = 'reel'), '{"revision_limit":1}') $$, 'the manager sets a limit of one round');
select throws_ok($$ select inf.deliverable_update((select id from ids where label = 'reel'), '{"stages":{"brief":true,"concept":false,"draft":true,"schedule":false,"verify":true,"metrics":true}}') $$,
                 '22023', 'stages can only change before work starts', 'stages are locked once work starts');
select tests.as_person('cara');
select throws_ok($$ select inf.submission_review((select id from ids where label = 'd1'), 'changes', '') $$, '22023', 'say what should change',
                 'changes need a note');
select lives_ok($$ select inf.submission_review((select id from ids where label = 'd1'), 'changes', 'Trim the intro') $$, 'one round of changes');
select tests.as_person('riya');
select lives_ok($$ insert into ids select 'd2', inf.submission_add((select id from ids where label = 'reel'), '{"kind":"draft","body":"#ad Shorter intro"}') $$,
                'version 2 of the draft');
select tests.act_as_service();
select lives_ok($$ select inf.compliance_record((select id from ids where label = 'd2'), '[{"kind":"banned_claims","passed":true},{"kind":"disclosure","passed":true}]') $$,
                'scans recorded');
select tests.as_person('cara');
select throws_ok($$ select inf.submission_review((select id from ids where label = 'd2'), 'changes', 'Again') $$, '22023',
                 'the revision limit is reached: request an extra revision first', 'the limit stops a second round');
select lives_ok($$ insert into ids select 'ext', inf.revision_extension_request((select id from ids where label = 'reel'), 'Music licence issue', 50000) $$,
                'the reviewer asks for an extra round');
select throws_ok($$ select inf.revision_extension_decide((select id from ids where label = 'ext'), true) $$, '42501', null,
                 'a reviewer cannot approve the extra round');
select tests.as_person('mona');
select lives_ok($$ select inf.revision_extension_decide((select id from ids where label = 'ext'), true, 'OK') $$, 'the manager approves it');
select tests.as_person('cara');
select throws_ok($$ select inf.submission_review((select id from ids where label = 'd2'), 'approve', 'Lovely') $$, '22023',
                 'complete the ASCI checklist before approving', 'the last approval needs the checklist');
select lives_ok($$ select inf.submission_review((select id from ids where label = 'd2'), 'approve', 'Lovely',
                     (select jsonb_object_agg(i, true) from unnest(inf.asci_items()) i)) $$, 'approved with the checklist');
select throws_ok($$ select inf.submission_review((select id from ids where label = 'd1'), 'approve', null) $$, '22023', null,
                 'an older version cannot be reviewed again');

-- Comments
select lives_ok($$ insert into ids select 'cm', inf.review_comment_add((select id from ids where label = 'd2'), 'Logo too small here', 12500) $$,
                'a timestamped comment');
select throws_ok($$ select inf.review_comment_add((select id from ids where label = 'd2'), 'Here', null, '{"x":2,"y":0.5}') $$, '22023', 'invalid region',
                 'regions are fractions of the image');
select tests.as_person('riya');
select lives_ok($$ select inf.review_comment_add((select id from ids where label = 'd2'), 'Fixed in the final', null, null, (select id from ids where label = 'cm')) $$,
                'the creator replies');
select lives_ok($$ select inf.review_comment_set_resolved((select id from ids where label = 'cm'), true) $$, 'and resolves the thread');
select tests.as_person('arjun');
select throws_ok($$ select inf.review_comment_set_resolved((select id from ids where label = 'cm'), false) $$, '42501', null, 'another creator cannot touch it');

-- ---------------------------------------------------------------------------------------------------------------
-- Go-live, verification and metrics
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select throws_ok($$ select inf.post_submit((select id from ids where label = 'reel'), 'https://www.instagram.com/reel/abc/', (now() at time zone 'Asia/Kolkata')::date + 5) $$, '22023', null,
                 'the posting date cannot be in the future');
select lives_ok($$ select inf.post_submit((select id from ids where label = 'reel'), 'https://www.instagram.com/reel/abc/', (now() at time zone 'Asia/Kolkata')::date) $$, 'the creator goes live');
select tests.reset();
select ok((select live_at is not null and status = 'live' from inf.deliverables where id = (select id from ids where label = 'reel')), 'live with a timestamp');
select is((select count(*)::int from inf.jobs where kind = 'penalties.refresh'), 1, 'going live queues a penalty refresh');

select tests.as_person('vic');
select throws_ok($$ select inf.post_verify((select id from inf.published_posts limit 1), true, true, true) $$, '42501', null, 'a viewer cannot verify');
select tests.as_person('cara');
select throws_ok($$ select inf.post_verify((select id from inf.published_posts limit 1), true, false, true) $$, '22023', 'say what is wrong',
                 'a rejection needs a note');
select lives_ok($$ select inf.post_verify((select id from inf.published_posts limit 1), true, false, true, 'No #ad in the caption') $$, 'missing disclosure rejected');
select tests.reset();
select ok((select disclosure_failed_at is not null and status = 'live' from inf.deliverables where id = (select id from ids where label = 'reel')),
          'the disclosure failure is recorded and the post stays live');
select tests.as_person('riya');
select lives_ok($$ select inf.post_submit((select id from ids where label = 'reel'), 'https://www.instagram.com/reel/abc2/', (now() at time zone 'Asia/Kolkata')::date) $$, 'the corrected link');
select tests.as_person('cara');
select lives_ok($$ select inf.post_verify((select id from inf.published_posts where verification_status = 'pending'), true, true, true) $$, 'verified');
select tests.reset();
select is((select array_agg(verification_status order by created_at) from inf.published_posts), array['rejected', 'verified'],
          'the history keeps the rejected post');
select is((select status from inf.deliverables where id = (select id from ids where label = 'reel')), 'live_verified', 'live verified');

select tests.as_person('riya');
select throws_ok($$ select inf.metrics_submit((select id from ids where label = 'reel'), '{"checkpoint":"24h","views":1200,"screenshots":["elsewhere/x.png"]}') $$,
                 '22023', 'invalid file', 'screenshots must live under the deliverable');
select lives_ok($$ select inf.metrics_submit((select id from ids where label = 'reel'), '{"checkpoint":"24h","views":1200,"reach":900}') $$, '24-hour metrics');
select tests.as_person('cara');
select lives_ok($$ select inf.deliverable_set_status((select id from ids where label = 'reel'), 'complete') $$, 'completed');
select throws_ok($$ select inf.deliverable_set_status((select id from ids where label = 'story'), 'cancel', '') $$, '22023', 'a reason is required',
                 'cancelling needs a reason');
select lives_ok($$ select inf.deliverable_set_status((select id from ids where label = 'story'), 'cancel', 'Campaign scope reduced') $$, 'cancelled');
select tests.as_person('riya');
select throws_ok($$ select inf.submission_add((select id from ids where label = 'reel'), '{"kind":"draft","body":"more"}') $$, '22023', null,
                 'nothing moves after completion');

-- ---------------------------------------------------------------------------------------------------------------
-- Reads and RLS
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select is((select count(*)::int from inf.deliverables), 0, 'creators cannot select deliverables directly');
select is((select count(*)::int from inf.deliverable_submissions), 0, 'nor submissions');
select is(jsonb_array_length(inf.my_deliverables((select id from ids where label = 'riya'))), 2, 'My deliverables lists both');
select is(inf.deliverable_detail((select id from ids where label = 'reel')) -> 'extensions', 'null'::jsonb, 'creators do not see extension requests');
select throws_ok($$ select inf.deliverables_list('{}') $$, '42501', null, 'creators cannot use the staff list');
select tests.as_person('ola');
select is((select count(*)::int from inf.deliverables), 0, 'agencies cannot select deliverables directly');
select ok(inf.deliverable_detail((select id from ids where label = 'reel')) ->> 'side' = 'agency', 'the acting agency reads the deliverable');
select tests.as_person('fin');
select is(jsonb_array_length(inf.deliverables_list('{"view":"all"}')), 2, 'finance reads the staff list');
select is((select count(*)::int from inf.deliverables), 2, 'staff with deliverable.read select deliverables');
select tests.as_person('vic');
select is((select count(*)::int from inf.deliverables), 0, 'a viewer does not');

-- Content stays hidden on a deal that is not agreed.
select tests.act_as_service();
select is((select inf.deliverables_create((select id from ids where label = 'draft_deal'), '[{"title":"Teaser","platform":"youtube","format":"short"}]')), 1,
          'deliverables on a draft deal');
select tests.as_person('riya');
select is(jsonb_array_length(inf.my_deliverables((select id from ids where label = 'riya'))), 2, 'the draft deal''s deliverable is hidden from the creator');

-- ---------------------------------------------------------------------------------------------------------------
-- Penalty proposals
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('riya');
select throws_ok($$ select inf.deal_content_facts((select id from ids where label = 'deal')) $$, '42501', null, 'content facts are for the server only');
select throws_ok($$ select inf.penalty_proposals_sync((select id from ids where label = 'deal'), '[]') $$, '42501', null, 'creators cannot write proposals');
select tests.act_as_service();
select ok(jsonb_array_length(inf.deal_content_facts((select id from ids where label = 'deal')) -> 'deliverables') = 2, 'the server reads content facts');
select is(inf.penalty_proposals_sync((select id from ids where label = 'deal'), jsonb_build_array(jsonb_build_object(
  'key', (select id from ids where label = 'version')::text || ':late:reel1:penalty', 'rule_id', 'late', 'version_id', (select id from ids where label = 'version'),
  'subject', 'reel1', 'amount_paise', 100000, 'forfeits', '[]'::jsonb, 'reason', 'Live 3 days late', 'at', now()))), 1, 'one proposal');
select is((select deliverable_id from inf.penalty_proposals), (select id from ids where label = 'reel'), 'matched to the deliverable by its rule id');
select is(inf.penalty_proposals_sync((select id from ids where label = 'deal'), '[]'), 0, 'the engine no longer proposes it');
select is((select status from inf.penalty_proposals), 'withdrawn', 'withdrawn');
select is(inf.penalty_proposals_sync((select id from ids where label = 'deal'), jsonb_build_array(jsonb_build_object(
  'key', (select id from ids where label = 'version')::text || ':late:reel1:penalty', 'rule_id', 'late', 'version_id', (select id from ids where label = 'version'),
  'subject', 'reel1', 'amount_paise', 150000, 'forfeits', '[]'::jsonb, 'reason', 'Live 4 days late', 'at', now()))), 1, 'proposed again');
select is((select status || ':' || amount_paise from inf.penalty_proposals), 'proposed:150000', 'back to proposed with the new amount');
select tests.as_person('cara');
select throws_ok($$ select inf.penalty_decide((select id from inf.penalty_proposals limit 1), true) $$, '42501', null, 'a reviewer cannot approve penalties');
select tests.as_person('mona');
select throws_ok($$ select inf.penalty_decide((select id from inf.penalty_proposals limit 1), false, '') $$, '22023', 'a reason is required',
                 'rejecting needs a reason');
select lives_ok($$ select inf.penalty_decide((select id from inf.penalty_proposals limit 1), true, 'Agreed with the creator') $$, 'the manager approves');
select tests.act_as_service();
select is(inf.penalty_proposals_sync((select id from ids where label = 'deal'), '[]'), 0, 'a later sync');
select is((select status from inf.penalty_proposals), 'approved', 'never touches a decided proposal');

-- Reminders run.
select tests.reset();
select lives_ok($$ select inf.content_remind() $$, 'the reminder job runs');

select * from finish();
rollback;
