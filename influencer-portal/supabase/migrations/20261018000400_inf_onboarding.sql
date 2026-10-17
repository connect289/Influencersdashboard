-- Phase 2.4: invitations, creator self sign-up, the onboarding wizard (profile, platforms, KYC, terms, compliance
-- course and quiz), submission and admin approval with optional auto-approval (spec 7, 13).

-- ---------------------------------------------------------------------------------------------------------------
-- Invitations
-- ---------------------------------------------------------------------------------------------------------------
create table inf.creator_invitations (
  id           uuid primary key default gen_random_uuid(),
  creator_id   uuid not null references inf.creators (id) on delete cascade,
  email        text not null,
  sent_by      uuid not null default auth.uid(),
  sent_at      timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '30 days',
  status       text not null default 'sent' check (status in ('sent', 'accepted', 'revoked')),
  accepted_at  timestamptz
);
create index creator_invitations_creator_idx on inf.creator_invitations (creator_id, sent_at desc);
create trigger creator_invitations_audit after insert or update on inf.creator_invitations
  for each row execute function inf.audit_row('creator_invitation');

-- Mark a creator invited (single or bulk). The app then makes sure an auth account exists for the email (so the
-- email code works) and sends the invitation email. Returns the creators that were invited, with their emails.
create or replace function inf.creators_invite(p_ids uuid[]) returns table (creator_id uuid, email text, display_name text)
language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  if not inf.has_perm('creator.import') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(array_length(p_ids, 1), 0) > 500 then raise exception 'at most 500 at a time' using errcode = '22023'; end if;
  for r in
    select c.id, lower(c.email) as email, c.display_name
      from inf.creators c
     where c.id = any(p_ids) and c.email is not null and not c.is_blocked and c.status in ('prospect', 'invited')
       and not exists (select 1 from inf.creator_accounts a where a.creator_id = c.id)
     for update
  loop
    update inf.creators set status = 'invited' where id = r.id;
    insert into inf.creator_invitations (creator_id, email) values (r.id, r.email);
    creator_id := r.id; email := r.email; display_name := r.display_name;
    return next;
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Self sign-up (called by the app with the service role after rate limiting). Creates an onboarding creator.
-- Returns {ok, creator_id} or {ok:false, error: handle_taken | email_exists | invalid}.
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.creator_self_signup(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_email  text := lower(trim(p ->> 'email'));
  v_handle text := lower(trim(p ->> 'handle'));
  v_id     uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or v_handle !~ '^[a-z0-9._]{3,30}$'
     or char_length(trim(p ->> 'display_name')) not between 1 and 120 then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if exists (select 1 from inf.creators where lower(email) = v_email)
     or exists (select 1 from inf.staff_profiles where lower(email) = v_email)
     or exists (select 1 from inf.agency_members where email = v_email and status = 'active') then
    return jsonb_build_object('ok', false, 'error', 'email_exists');
  end if;
  if exists (select 1 from inf.creators where handle = v_handle) then
    return jsonb_build_object('ok', false, 'error', 'handle_taken');
  end if;
  insert into inf.creators (display_name, handle, email, status, pipeline_stage, source, onboarding_step)
  values (trim(p ->> 'display_name'), v_handle, v_email, 'invited', 'onboarding', 'self_signup', 'profile')
  returning id into v_id;
  if nullif(p ->> 'platform', '') is not null and nullif(p ->> 'platform_url', '') is not null then
    insert into inf.creator_platforms (creator_id, platform, url, handle, followers, stats_updated_at)
    values (v_id, p ->> 'platform', p ->> 'platform_url', coalesce(nullif(trim(p ->> 'platform_handle'), ''), v_handle),
            nullif(p ->> 'followers', '')::bigint, now());
  end if;
  perform inf.emit_event('creator.signed_up', 'creator', v_id::text, jsonb_build_object('handle', v_handle), 'creator_signed_up:' || v_id);
  return jsonb_build_object('ok', true, 'creator_id', v_id);
end $$;

-- Linking now also accepts the invitation and moves the creator into onboarding.
create or replace function inf.creator_account_link() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_email   text;
  v_ok      boolean;
  v_creator uuid;
  v_n       int;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select a.creator_id into v_creator from inf.creator_accounts a where a.user_id = v_uid;
  if v_creator is not null then return jsonb_build_object('ok', true, 'creator_id', v_creator, 'linked', false); end if;
  if exists (select 1 from inf.staff_profiles where user_id = v_uid) or exists (select 1 from inf.agency_members where user_id = v_uid) then
    return jsonb_build_object('ok', false, 'error', 'other_account_kind');
  end if;
  select lower(u.email), u.email_confirmed_at is not null into v_email, v_ok from auth.users u where u.id = v_uid;
  if v_email is null or not v_ok then return jsonb_build_object('ok', false, 'error', 'email_not_verified'); end if;
  select count(*), min(c.id::text)::uuid into v_n, v_creator
    from inf.creators c
   where lower(c.email) = v_email and c.status in ('invited', 'onboarding', 'active', 'paused') and not c.is_blocked
     and not exists (select 1 from inf.creator_accounts a where a.creator_id = c.id);
  if v_n <> 1 then return jsonb_build_object('ok', false, 'error', 'not_registered'); end if;
  insert into inf.creator_accounts (creator_id, user_id) values (v_creator, v_uid);
  update inf.creators set status = case when status = 'invited' then 'onboarding' else status end,
                          pipeline_stage = case when status = 'invited' then 'onboarding' else pipeline_stage end,
                          last_activity_at = now()
   where id = v_creator;
  update inf.creator_invitations set status = 'accepted', accepted_at = now() where creator_id = v_creator and status = 'sent';
  return jsonb_build_object('ok', true, 'creator_id', v_creator, 'linked', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Compliance mini-course: short lessons and a multiple-choice quiz. Correct answers never leave the database.
-- ---------------------------------------------------------------------------------------------------------------
create table inf.course_lessons (
  id        uuid primary key default gen_random_uuid(),
  position  int not null unique,
  title     text not null check (char_length(title) between 2 and 120),
  body      text not null check (char_length(body) between 10 and 4000),
  active    boolean not null default true
);

create table inf.course_questions (
  id             uuid primary key default gen_random_uuid(),
  position       int not null unique,
  prompt         text not null check (char_length(prompt) between 5 and 500),
  options        text[] not null check (array_length(options, 1) between 2 and 6),
  correct_index  int not null,
  explanation    text check (char_length(explanation) <= 600),
  active         boolean not null default true,
  check (correct_index >= 0 and correct_index < array_length(options, 1))
);

create table inf.course_attempts (
  id          uuid primary key default gen_random_uuid(),
  creator_id  uuid not null references inf.creators (id) on delete cascade,
  answers     jsonb not null,
  score_pct   int not null check (score_pct between 0 and 100),
  passed      boolean not null,
  created_at  timestamptz not null default now()
);
create index course_attempts_creator_idx on inf.course_attempts (creator_id, created_at desc);
create trigger course_attempts_append_only before update or delete on inf.course_attempts
  for each row execute function inf.forbid_mutation();
create trigger course_lessons_audit after insert or update or delete on inf.course_lessons for each row execute function inf.audit_row('course_lesson');
create trigger course_questions_audit after insert or update or delete on inf.course_questions for each row execute function inf.audit_row('course_question');

-- Version 1 of the course, written from the ASCI influencer guidelines and the portal's own rules. Review with legal
-- before go-live (docs/RUNBOOK.md); staff can edit lessons and questions later (Phase 9 compliance tools).
insert into inf.course_lessons (position, title, body) values
  (1, 'Always disclose the partnership',
   'Every post, reel, story or video you make for Eduwit must carry a clear disclosure such as #ad, #collab or "Paid partnership with Eduwit", placed where viewers see it before they see the message: at the start of a caption, on screen in the first seconds of a video, and spoken in audio-only content. Hiding it among many hashtags or in a collapsed caption doesn''t count (ASCI guidelines for influencer advertising).'),
  (2, 'Say only what is approved and true',
   'Use the programme facts and claims from your brief: fees, duration, accreditation and eligibility exactly as given. Never promise admission, jobs, salaries, placements or results, and never call a programme "the best" or "guaranteed". If you are unsure about a claim, ask in the brief''s Q&A before posting.'),
  (3, 'Students'' privacy',
   'You will see how your leads progress, but never a student''s phone number or email address. Don''t ask students to send you their contact details, and don''t contact them outside Eduwit''s process: Eduwit''s counsellors handle every conversation.'),
  (4, 'Fair play',
   'Leads from yourself, your family or your team, bought traffic, fake accounts and incentivised sign-ups are not commissionable and can lead to penalties or removal from the programme. Share your own tracking link or code only.');

insert into inf.course_questions (position, prompt, options, correct_index, explanation) values
  (1, 'Where should the partnership disclosure appear in a reel?',
   array['Only in the comments', 'On screen at the start and in the caption''s first line', 'At the end of the caption among other hashtags', 'It isn''t needed if you like the programme'],
   1, 'Viewers must see the disclosure before the message: on screen early and at the start of the caption.'),
  (2, 'A follower asks if the programme guarantees a job. What do you say?',
   array['Yes, everyone gets placed', 'Share only the placement support described in your brief, without promising a job', 'Tell them to DM you their phone number', 'Say the salary will double'],
   1, 'Never promise jobs, salaries or results; stick to approved facts.'),
  (3, 'Which of these is an acceptable disclosure?',
   array['#sp hidden in 20 hashtags', '"Paid partnership with Eduwit" at the start', '#blessed', 'No disclosure on stories'],
   1, 'A clear label placed where people see it first.'),
  (4, 'Can you ask interested students to send their phone numbers to you?',
   array['Yes, to pass them on faster', 'No: they should use your tracking link or code, and Eduwit''s counsellors contact them', 'Only by email', 'Only for close friends'],
   1, 'You never collect students'' contact details.'),
  (5, 'Your cousin signs up through your link. Is that lead commissionable?',
   array['Yes, any lead counts', 'No: leads from yourself, family or team are not commissionable', 'Only if they enrol', 'Only on weekends'],
   1, 'Self-referrals are excluded under the programme rules.'),
  (6, 'You aren''t sure whether a fee figure in your script is current. What should you do?',
   array['Guess', 'Ask in the brief''s Q&A before posting', 'Leave it out of the disclosure', 'Use an older figure you remember'],
   1, 'Only use approved, current facts; ask when unsure.'),
  (7, 'Is buying followers or paid traffic allowed to boost your leads?',
   array['Yes', 'No: bought or fake traffic isn''t commissionable and can lead to penalties', 'Only for new creators', 'Only on YouTube'],
   1, 'Only genuine audience engagement counts.'),
  (8, 'Who handles conversations with students who become leads?',
   array['You, on your personal WhatsApp', 'Eduwit''s counsellors', 'Your agency', 'Nobody'],
   1, 'Eduwit''s team runs every conversation with students.');

create or replace function inf.course_content() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'lessons', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'body', body) order by position) from inf.course_lessons where active), '[]'),
    'questions', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'prompt', prompt, 'options', to_jsonb(options)) order by position) from inf.course_questions where active), '[]'),
    'pass_pct', coalesce((inf.setting('creators.lifecycle') ->> 'course_pass_pct')::int, 80))
  where inf.current_creator_id() is not null or inf.has_perm('creator.read');
$$;

-- Grade a quiz attempt. p_answers: {"<question id>": <option index>, ...}. Returns the score, pass/fail and, for
-- wrong answers, the explanation (not the right option). At most 10 attempts a day.
create or replace function inf.course_submit(p_answers jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_creator uuid := inf.current_creator_id();
  v_total int; v_right int; v_pct int; v_pass int; v_passed boolean;
begin
  if v_creator is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if (select count(*) from inf.course_attempts where creator_id = v_creator and created_at > now() - interval '1 day') >= 10 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;
  select count(*), count(*) filter (where (p_answers ->> q.id::text) ~ '^\d+$' and (p_answers ->> q.id::text)::int = q.correct_index)
    into v_total, v_right from inf.course_questions q where q.active;
  v_pct := case when v_total = 0 then 0 else round(100.0 * v_right / v_total) end;
  v_pass := coalesce((inf.setting('creators.lifecycle') ->> 'course_pass_pct')::int, 80);
  v_passed := v_pct >= v_pass;
  insert into inf.course_attempts (creator_id, answers, score_pct, passed) values (v_creator, p_answers, v_pct, v_passed);
  update inf.creators set last_activity_at = now() where id = v_creator;
  return jsonb_build_object('ok', true, 'score_pct', v_pct, 'passed', v_passed, 'pass_pct', v_pass,
    'wrong', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'explanation', q.explanation) order by q.position)
                         from inf.course_questions q
                        where q.active and coalesce((p_answers ->> q.id::text) ~ '^\d+$' and (p_answers ->> q.id::text)::int = q.correct_index, false) = false), '[]'));
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Onboarding state, submission and approval
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.onboarding_state(p_creator uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_id uuid := coalesce(p_creator, inf.current_creator_id());
  c inf.creators;
  v_profile boolean; v_platforms boolean; v_kyc text; v_terms boolean; v_course boolean;
  v_require_kyc boolean := coalesce((inf.setting('creators.lifecycle') ->> 'require_kyc_to_submit')::boolean, true);
begin
  if v_id is null or not (coalesce(v_id = inf.current_creator_id(), false) or inf.has_perm('creator.read')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into c from inf.creators where id = v_id;
  v_profile := c.legal_name is not null and c.phone_e164 is not null and c.city is not null and cardinality(c.niches) > 0;
  v_platforms := exists (select 1 from inf.creator_platforms where creator_id = v_id);
  select coalesce(status, 'pending') into v_kyc from inf.creator_kyc where creator_id = v_id;
  v_kyc := coalesce(v_kyc, 'pending');
  -- Terms: every current version accepted (by the creator's account).
  v_terms := exists (select 1 from inf.creator_accounts where creator_id = v_id) and not exists (
    select 1 from inf.terms_versions tv
     where tv.kind in ('platform_terms', 'privacy') and tv.effective_at <= now()
       and tv.version = (select max(t2.version) from inf.terms_versions t2 where t2.kind = tv.kind and t2.effective_at <= now())
       and not exists (select 1 from inf.terms_acceptances ta join inf.creator_accounts a on a.user_id = ta.user_id
                        where a.creator_id = v_id and ta.terms_version_id = tv.id));
  v_course := exists (select 1 from inf.course_attempts where creator_id = v_id and passed);
  return jsonb_build_object(
    'creator_id', v_id, 'status', c.status, 'approved', c.approved_at is not null,
    'submitted_at', c.onboarding_submitted_at, 'step', c.onboarding_step,
    'steps', jsonb_build_object('profile', v_profile, 'platforms', v_platforms,
                                'kyc', v_kyc in ('submitted', 'verified') or not v_require_kyc,
                                'terms', v_terms, 'course', v_course),
    'kyc_status', v_kyc, 'kyc_required', v_require_kyc,
    'complete', v_profile and v_platforms and (v_kyc in ('submitted', 'verified') or not v_require_kyc) and v_terms and v_course);
end $$;

-- Staff approve a creator: active, approved, notified.
create or replace function inf.creator_approve_internal(p_creator uuid, p_by uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid;
begin
  update inf.creators set status = 'active', pipeline_stage = 'active', approved_at = now(), approved_by = p_by,
         onboarding_step = 'done'
   where id = p_creator;
  select user_id into v_user from inf.creator_accounts where creator_id = p_creator;
  if v_user is not null then
    perform inf.notify(v_user, 'creator.approved', 'Welcome aboard: your profile is approved',
                       'You can now apply to campaigns.', '/creator', '{}'::jsonb, true, 'creator_approved:' || p_creator);
  end if;
  perform inf.emit_event('creator.approved', 'creator', p_creator::text, jsonb_build_object('by', p_by), 'creator_approved:' || p_creator);
end $$;

create or replace function inf.onboarding_submit() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := inf.current_creator_id();
  v_state jsonb;
  v_set jsonb := inf.setting('creators.lifecycle');
  v_followers bigint;
  v_auto boolean;
begin
  if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_state := inf.onboarding_state(v_id);
  if (v_state ->> 'approved')::boolean then return jsonb_build_object('ok', true, 'approved', true); end if;
  if not (v_state ->> 'complete')::boolean then return jsonb_build_object('ok', false, 'error', 'incomplete', 'steps', v_state -> 'steps'); end if;
  update inf.creators set onboarding_submitted_at = now(), onboarding_step = 'review', last_activity_at = now() where id = v_id;
  select coalesce(sum(followers), 0) into v_followers from inf.creator_platforms where creator_id = v_id;
  v_auto := coalesce((v_set ->> 'auto_approve_signups')::boolean, false)
            and v_followers >= coalesce((v_set ->> 'auto_approve_min_followers')::bigint, 0);
  if v_auto then
    perform inf.creator_approve_internal(v_id, null);
    perform inf.audit('creator', v_id::text, 'auto_approve', null, jsonb_build_object('followers', v_followers));
    return jsonb_build_object('ok', true, 'approved', true);
  end if;
  -- Tell the owner, or else every active staff member who can approve.
  perform inf.notify(sp.user_id, 'creator.onboarding_submitted', c.display_name || ' finished onboarding',
                     'Review and approve their profile.', '/admin/creators/approvals', jsonb_build_object('creator_id', v_id), false,
                     'onboarding_submitted:' || v_id || ':' || sp.user_id)
    from inf.creators c
    join inf.staff_profiles sp on sp.status = 'active'
     and (sp.user_id = c.owner_id or (c.owner_id is null and exists (
           select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
            where g.user_id = sp.user_id and rp.permission = 'creator.write')))
   where c.id = v_id;
  return jsonb_build_object('ok', true, 'approved', false);
end $$;

-- p_decision: approve | changes (back to the wizard with a reason) | decline (archived with a reason).
create or replace function inf.creator_review(p_creator uuid, p_decision text, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid; c inf.creators;
begin
  if not inf.has_perm('creator.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.creators where id = p_creator for update;
  if c.id is null then raise exception 'no such creator' using errcode = '22023'; end if;
  if c.approved_at is not null then raise exception 'already approved' using errcode = '22023'; end if;
  if p_decision <> 'approve' and coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  select user_id into v_user from inf.creator_accounts where creator_id = p_creator;
  if p_decision = 'approve' then
    if v_user is null then raise exception 'creator has not signed up yet' using errcode = '22023'; end if;
    perform inf.creator_approve_internal(p_creator, auth.uid());
  elsif p_decision = 'changes' then
    update inf.creators set onboarding_step = 'profile', onboarding_submitted_at = null where id = p_creator;
    if v_user is not null then
      perform inf.notify(v_user, 'creator.onboarding_changes', 'Please update your onboarding details',
                         'Reason: ' || left(p_reason, 300), '/creator/onboarding', '{}'::jsonb, true,
                         'onboarding_changes:' || p_creator || ':' || extract(epoch from now())::bigint);
    end if;
  elsif p_decision = 'decline' then
    update inf.creators set status = 'archived', pipeline_stage = 'archived', onboarding_submitted_at = null where id = p_creator;
    update inf.user_sessions s set revoked_at = now(), revoked_by = auth.uid(), revoke_reason = 'sign-up declined'
      from inf.creator_accounts a where a.creator_id = p_creator and s.user_id = a.user_id and s.revoked_at is null;
  else
    raise exception 'unknown decision' using errcode = '22023';
  end if;
  perform inf.audit('creator', p_creator::text, 'review:' || p_decision, null, jsonb_build_object('reason', p_reason));
end $$;

-- Staff queue: submitted, not yet approved.
create or replace function inf.approvals_queue() returns table (
  creator_id uuid, display_name text, handle text, source text, submitted_at timestamptz, followers bigint,
  kyc_status text, owner_name text)
language sql stable security definer set search_path = '' as $$
  select c.id, c.display_name, c.handle, c.source, c.onboarding_submitted_at,
         coalesce((select sum(p.followers) from inf.creator_platforms p where p.creator_id = c.id), 0)::bigint,
         coalesce((select k.status from inf.creator_kyc k where k.creator_id = c.id), 'pending'),
         (select sp.full_name from inf.staff_profiles sp where sp.user_id = c.owner_id)
    from inf.creators c
   where inf.has_perm('creator.read') and c.onboarding_submitted_at is not null and c.approved_at is null
     and c.status not in ('archived', 'blocked')
   order by c.onboarding_submitted_at;
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.creator_invitations enable row level security;
alter table inf.course_lessons enable row level security;
alter table inf.course_questions enable row level security;
alter table inf.course_attempts enable row level security;

create policy creator_invitations_staff_read on inf.creator_invitations for select to authenticated using ((select inf.has_perm('creator.read')));
create policy course_attempts_read on inf.course_attempts for select to authenticated
  using (creator_id = (select inf.current_creator_id()) or (select inf.has_perm('creator.read')));
-- course_lessons / course_questions: no direct access (the correct answers stay hidden); read via course_content().

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.creator_invitations', 'authenticated', 'select'),
  ('table', 'inf.course_attempts', 'authenticated', 'select'),
  ('function', 'inf.creators_invite(uuid[])', 'authenticated', 'execute'),
  ('function', 'inf.course_content()', 'authenticated', 'execute'),
  ('function', 'inf.course_submit(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.onboarding_state(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.onboarding_submit()', 'authenticated', 'execute'),
  ('function', 'inf.creator_review(uuid, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.approvals_queue()', 'authenticated', 'execute');
call inf.apply_client_grants();
