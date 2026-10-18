-- Onboarding: invitations, self sign-up (service role only), the course (answers hidden, graded in the database),
-- onboarding state and submission, staff review, auto-approval.
begin;
\ir _helpers.psql
select plan(29);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('rev', array['content_reviewer']);
create temporary table ids (label text primary key, id uuid);
grant select, insert on ids to authenticated, service_role;

-- Invitations.
select tests.as_person('mona');
insert into ids select 'pria', inf.creator_save('{"display_name":"Pria","handle":"pria.prep","email":"pria@creator.test"}');
insert into ids select 'noemail', inf.creator_save('{"display_name":"No Email","handle":"no.email"}');
select is((select count(*)::int from inf.creators_invite(array[(select id from ids where label = 'pria'), (select id from ids where label = 'noemail')])), 1, 'only creators with an email are invited');
select is((select status from inf.creators where id = (select id from ids where label = 'pria')), 'invited', 'status becomes invited');
select tests.as_person('rev');
select throws_ok($$ select * from inf.creators_invite(array[(select id from ids where label = 'pria')]) $$, '42501', null, 'content reviewer cannot invite');

-- Self sign-up: service role only; duplicates refused.
select tests.as_person('mona');
select throws_ok($$ select inf.creator_self_signup('{"display_name":"X","handle":"xyz","email":"x@y.in"}') $$, '42501', null, 'not callable by signed-in users');
select tests.act_as_service();
select is(inf.creator_self_signup('{"display_name":"Sam Self","handle":"sam.self","email":"Sam@Creator.test","platform":"instagram","platform_url":"https://instagram.com/sam","followers":"25000"}') ->> 'ok', 'true', 'self sign-up creates a creator');
select is(inf.creator_self_signup('{"display_name":"Dup","handle":"other","email":"sam@creator.test"}') ->> 'error', 'email_exists', 'existing email refused');
select is(inf.creator_self_signup('{"display_name":"Dup","handle":"sam.self","email":"new@creator.test"}') ->> 'error', 'handle_taken', 'taken handle refused');
select is(inf.creator_self_signup('{"display_name":"","handle":"ab","email":"bad"}') ->> 'error', 'invalid', 'invalid input refused');
select tests.reset();
select is((select source || '/' || status || '/' || pipeline_stage from inf.creators where handle = 'sam.self'), 'self_signup/invited/onboarding', 'self sign-ups start in onboarding');

-- Sam signs in: account linked, invitation-style status moves to onboarding.
insert into tests.people select 'sam', tests.create_user('sam@creator.test'), gen_random_uuid(), null;
select tests.as_person('sam');
select is((inf.creator_account_link() ->> 'linked')::boolean, true, 'sign-in links the self-signed-up creator');
select inf.session_register();
select is((select status from inf.creators where handle = 'sam.self'), 'onboarding', 'status is onboarding after first sign-in');
insert into ids select 'sam', inf.current_creator_id();

-- Course: answers hidden; grading in the database.
select ok(inf.course_content() -> 'questions' -> 0 ? 'options', 'questions are readable');
select ok(not (inf.course_content() -> 'questions' -> 0 ? 'correct_index'), 'correct answers are not sent');
select throws_ok($$ select * from inf.course_questions $$, '42501', null, 'question table is not readable');
select is((inf.course_submit('{}') ->> 'passed')::boolean, false, 'empty answers fail');
select tests.reset();
create temporary table right_answers as select jsonb_object_agg(id::text, correct_index) as a from inf.course_questions;
create temporary table one_wrong as
  select jsonb_object_agg(id::text, case when position = 1 then (correct_index + 1) % array_length(options, 1) else correct_index end) as a,
         (select id from inf.course_questions where position = 1) as wrong_id
    from inf.course_questions;
grant select on right_answers, one_wrong to authenticated;
select tests.as_person('sam');
select is((inf.course_submit((select a from one_wrong)) ->> 'score_pct')::int, 88, 'seven of eight right scores 88%');
select is((inf.course_submit((select a from one_wrong)) -> 'wrong' -> 0 ->> 'id')::uuid, (select wrong_id from one_wrong), 'the wrong question is explained');
select is((inf.course_submit((select a from right_answers)) ->> 'passed')::boolean, true, 'all right passes');

-- Onboarding state and submission.
select is((inf.onboarding_state() ->> 'complete')::boolean, false, 'not complete yet');
select is(inf.onboarding_submit() ->> 'error', 'incomplete', 'incomplete onboarding cannot be submitted');
select inf.creator_profile_update((select id from ids where label = 'sam'), '{"legal_name":"Sam Self","phone_e164":"+919811112222","city":"Delhi","niches":["mba"]}');
select inf.kyc_save((select id from ids where label = 'sam'), 'ABCPS1234K', 'Sam Self', 'unregistered', null, '001234567890', 'SBIN0001234', 'Sam Self');
select tests.reset();
insert into inf.terms_versions (kind, version, title, body) values ('platform_terms', 1, 'Terms', 'Body'), ('privacy', 1, 'Privacy', 'Body');
select tests.as_person('sam');
select inf.terms_accept(id) from inf.terms_pending();
select is(inf.onboarding_state() -> 'steps', '{"kyc": true, "terms": true, "course": true, "profile": true, "platforms": true}'::jsonb, 'every step done');
select is((inf.onboarding_submit() ->> 'approved')::boolean, false, 'submitted for review (auto-approval is off)');
select tests.reset();
select is((select count(*)::int from inf.notifications where user_id = (select user_id from tests.people where label = 'mona') and event = 'creator.onboarding_submitted'), 1, 'manager told about the submission');

-- Review.
select tests.as_person('rev');
select throws_ok($$ select inf.creator_review((select id from ids where label = 'sam'), 'approve', null) $$, '42501', null, 'content reviewer cannot approve');
select tests.as_person('mona');
select is((select count(*)::int from inf.approvals_queue()), 1, 'submission is in the approvals queue');
select throws_ok($$ select inf.creator_review((select id from ids where label = 'sam'), 'changes', ' ') $$, '22023', null, 'asking for changes needs a reason');
select lives_ok($$ select inf.creator_review((select id from ids where label = 'sam'), 'approve', null) $$, 'manager approves');
select is((select status || '/' || pipeline_stage from inf.creators where handle = 'sam.self'), 'active/active', 'approved creator is active');

-- Auto-approval when enabled and the follower threshold is met.
select tests.reset();
insert into inf.settings (key, value, version, updated_by)
values ('creators.lifecycle', '{"dormant_after_days":45,"auto_approve_signups":true,"auto_approve_min_followers":1000,"course_pass_pct":80,"require_kyc_to_submit":false}', 1, null)
on conflict (key) do update set value = excluded.value;
select tests.make_creator('ana', 'onboarding');
update inf.creators set legal_name = 'Ana', phone_e164 = '+919800000001', city = 'Pune', niches = '{mba}' where handle = 'ana';
insert into inf.creator_platforms (creator_id, platform, url, handle, followers) select creator_id, 'youtube', 'https://youtube.com/@ana', 'ana', 5000 from tests.people where label = 'ana';
insert into inf.course_attempts (creator_id, answers, score_pct, passed) select creator_id, '{}', 100, true from tests.people where label = 'ana';
insert into inf.terms_acceptances (user_id, terms_version_id) select p.user_id, tv.id from tests.people p, inf.terms_versions tv where p.label = 'ana';
select tests.as_person('ana');
select is((inf.onboarding_submit() ->> 'approved')::boolean, true, 'auto-approved (KYC not required by this setting)');

select * from finish();
rollback;
