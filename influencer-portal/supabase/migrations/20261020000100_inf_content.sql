-- Phase 5: briefs, deliverables and content review (spec 10, 16; ERD §5).
--
-- Briefs are written from templates as a working copy and published as immutable versions; the creator acknowledges
-- each version and asks questions in a Q&A thread. Deliverables follow the workflow in lib/content/workflow.ts
-- (mirrored here by inf.deliverable_next; a generated pgTAP matrix keeps both in step), with per-deliverable stage
-- switches, due dates, a revision limit and full transition history. Submissions are versioned and immutable; review
-- comments carry a video timestamp or an image region; compliance checks are recorded by the server (service role)
-- and can be overridden with a reason; live posts are verified by a reviewer; metrics are captured at checkpoints.
-- Penalty proposals computed by the compensation engine wait for a person to approve them.
--
-- Creators and agencies (with the "act on deliverables" grant) only reach this data through the functions below.

-- ---------------------------------------------------------------------------------------------------------------
-- Banned claims (spec 16)
-- ---------------------------------------------------------------------------------------------------------------
create table inf.banned_claims (
  id          uuid primary key default gen_random_uuid(),
  pattern     text not null check (char_length(pattern) between 2 and 200),
  kind        text not null default 'phrase' check (kind in ('phrase', 'regex')),
  severity    text not null default 'block' check (severity in ('block', 'warn')),
  note        text check (char_length(note) <= 300),
  active      boolean not null default true,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index banned_claims_pattern_idx on inf.banned_claims (lower(pattern), kind);
create trigger banned_claims_touch before update on inf.banned_claims for each row execute function inf.touch_updated_at();
create trigger banned_claims_audit after insert or update or delete on inf.banned_claims for each row execute function inf.audit_row('banned_claim');

-- Starting list for edtech promotion (ASCI and UGC guidance); Eduwit edits it under Content → Banned claims.
insert into inf.banned_claims (pattern, kind, severity, note) values
  ('guaranteed placement', 'phrase', 'block', 'No promises of placement or jobs'),
  ('guaranteed job', 'phrase', 'block', 'No promises of placement or jobs'),
  ('job guarantee', 'phrase', 'block', 'No promises of placement or jobs'),
  ('assured placement', 'phrase', 'block', 'No promises of placement or jobs'),
  ('100\s*%\s*(job|placement)s?', 'regex', 'block', 'No promises of placement or jobs'),
  ('degree without (any )?exams?', 'regex', 'block', 'Misleading: exams are part of every UGC-approved programme'),
  ('no exams?', 'phrase', 'block', 'Misleading: exams are part of every UGC-approved programme'),
  ('fake degree', 'phrase', 'block', 'Never suggest a degree is not genuine'),
  ('best university', 'phrase', 'warn', 'Unverifiable superlative: use catalogue facts instead'),
  ('number one university', 'phrase', 'warn', 'Unverifiable superlative: use catalogue facts instead'),
  ('limited seats', 'phrase', 'warn', 'Only when the university has confirmed it');

-- ---------------------------------------------------------------------------------------------------------------
-- Brief templates and briefs
-- ---------------------------------------------------------------------------------------------------------------
create table inf.brief_templates (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 2 and 120),
  description  text check (char_length(description) <= 500),
  content      jsonb not null default '{}'::jsonb check (jsonb_typeof(content) = 'object'),
  is_default   boolean not null default false,
  archived_at  timestamptz,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index brief_templates_one_default_idx on inf.brief_templates (is_default) where is_default and archived_at is null;
create unique index brief_templates_name_idx on inf.brief_templates (lower(name)) where archived_at is null;
create trigger brief_templates_touch before update on inf.brief_templates for each row execute function inf.touch_updated_at();
create trigger brief_templates_audit after insert or update or delete on inf.brief_templates for each row execute function inf.audit_row('brief_template');

insert into inf.brief_templates (name, description, is_default, content) values
  ('Standard creator brief', 'Objective, ASCI disclosures, claims rules and a concept → draft → live → metrics workflow.', true,
   jsonb_build_object(
     'audience', 'Working professionals and graduates considering an online degree.',
     'disclosures', jsonb_build_array(
       'Label the post as a paid partnership at the start: use the platform''s paid-partnership label and #ad or #collab in the first line of the caption.',
       'For videos, say it out loud or show it on screen in the first few seconds.',
       'Use the same language as the content.'),
     'dos', jsonb_build_array(
       'Share your own honest experience and questions you had.',
       'Use only the approved claims below: fees, mode, recognitions and eligibility as the catalogue states them.',
       'Point viewers to your link or code for counselling.'),
     'donts', jsonb_build_array(
       'Don''t promise jobs, placements, salaries or results.',
       'Don''t compare universities or say one is "the best".',
       'Don''t ask viewers for their phone number or email in comments or messages.'),
     'tone', 'Friendly, honest and specific.',
     'languages', jsonb_build_array('English', 'Hindi'),
     'faqs', jsonb_build_array(
       jsonb_build_object('q', 'Can I write my own script?', 'a', 'Yes. Submit it as your concept first so Eduwit can check the claims before you film.'),
       jsonb_build_object('q', 'What if I miss a due date?', 'a', 'Tell Eduwit in the portal as soon as you know. Late delivery can carry a penalty under your deal.')),
     'due_offsets', jsonb_build_object('concept', 5, 'draft', 10, 'live', 15, 'metrics', 22),
     'stages', jsonb_build_object('brief', true, 'concept', true, 'draft', true, 'schedule', false, 'verify', true, 'metrics', true)));

-- The brief template a campaign's deals use (spec 14 campaign builder); null means the default template.
alter table inf.campaigns add column brief_template_id uuid references inf.brief_templates (id) on delete set null;

create table inf.briefs (
  id                  uuid primary key default gen_random_uuid(),
  deal_id             uuid not null unique references inf.deals (id) on delete restrict,
  template_id         uuid references inf.brief_templates (id) on delete set null,
  draft_content       jsonb not null default '{}'::jsonb check (jsonb_typeof(draft_content) = 'object'),
  current_version_id  uuid,
  created_by          uuid default auth.uid(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create trigger briefs_touch before update on inf.briefs for each row execute function inf.touch_updated_at();
create trigger briefs_audit after insert or update on inf.briefs for each row execute function inf.audit_row('brief', 'draft_content');

create table inf.brief_versions (
  id            uuid primary key default gen_random_uuid(),
  brief_id      uuid not null references inf.briefs (id) on delete restrict,
  version       int not null check (version >= 1),
  content       jsonb not null check (jsonb_typeof(content) = 'object'),
  note          text check (char_length(note) <= 500),
  published_by  uuid default auth.uid(),
  published_at  timestamptz not null default now(),
  unique (brief_id, version)
);
create trigger brief_versions_append_only before update or delete on inf.brief_versions for each row execute function inf.forbid_mutation();
create trigger brief_versions_audit after insert on inf.brief_versions for each row execute function inf.audit_row('brief_version', 'content');
alter table inf.briefs add constraint briefs_current_version_fk foreign key (current_version_id) references inf.brief_versions (id);

create table inf.brief_acknowledgements (
  id               bigint generated always as identity primary key,
  brief_id         uuid not null references inf.briefs (id) on delete restrict,
  version_id       uuid not null unique references inf.brief_versions (id),
  user_id          uuid not null default auth.uid(),
  side             text not null check (side in ('creator', 'agency')),
  acknowledged_at  timestamptz not null default now()
);
create trigger brief_acknowledgements_append_only before update or delete on inf.brief_acknowledgements for each row execute function inf.forbid_mutation();
create trigger brief_acknowledgements_audit after insert on inf.brief_acknowledgements for each row execute function inf.audit_row('brief_acknowledgement');

create table inf.brief_questions (
  id           uuid primary key default gen_random_uuid(),
  brief_id     uuid not null references inf.briefs (id) on delete cascade,
  parent_id    uuid references inf.brief_questions (id) on delete cascade,
  author_id    uuid not null default auth.uid(),
  author_side  text not null check (author_side in ('creator', 'agency', 'eduwit')),
  body         text not null check (char_length(body) between 1 and 4000),
  created_at   timestamptz not null default now()
);
create index brief_questions_brief_idx on inf.brief_questions (brief_id, created_at);
create trigger brief_questions_audit after insert on inf.brief_questions for each row execute function inf.audit_row('brief_question');

-- ---------------------------------------------------------------------------------------------------------------
-- Deliverables
-- ---------------------------------------------------------------------------------------------------------------
create sequence inf.deliverable_code_seq;

create table inf.deliverables (
  id                    uuid primary key default gen_random_uuid(),
  code                  text not null unique default 'DV-' || lpad(nextval('inf.deliverable_code_seq')::text, 5, '0'),
  deal_id               uuid not null references inf.deals (id) on delete restrict,
  brief_id              uuid references inf.briefs (id) on delete set null,
  title                 text not null check (char_length(title) between 2 and 120),
  platform              text not null check (platform in ('instagram', 'youtube', 'facebook', 'linkedin', 'x', 'telegram', 'moj_josh', 'other')),
  format                text not null check (format in ('reel', 'story', 'post', 'youtube_video', 'short', 'live', 'carousel', 'blog', 'other')),
  position              int not null default 0,
  specs                 jsonb not null default '{}'::jsonb check (jsonb_typeof(specs) = 'object'),
  stages                jsonb not null default '{"brief":true,"concept":true,"draft":true,"schedule":false,"verify":true,"metrics":true}'::jsonb
                          check (jsonb_typeof(stages) = 'object'),
  due_dates             jsonb not null default '{}'::jsonb check (jsonb_typeof(due_dates) = 'object'),
  revision_limit        int not null default 2 check (revision_limit between 0 and 20),
  revisions_used        int not null default 0 check (revisions_used >= 0),
  extra_revisions       int not null default 0 check (extra_revisions >= 0),
  status                text not null default 'not_started' check (status in ('not_started', 'brief_acknowledged', 'concept_submitted',
                          'concept_changes_requested', 'concept_approved', 'draft_submitted', 'draft_changes_requested', 'draft_approved',
                          'scheduled', 'live', 'live_verified', 'metrics_submitted', 'completed', 'cancelled')),
  -- The id the deal's compensation rules use for this deliverable (milestone triggers and penalties), when they name one.
  config_ref            text check (config_ref ~ '^[a-z0-9][a-z0-9_-]{0,39}$'),
  scheduled_for         timestamptz,
  concept_approved_at   timestamptz,
  draft_approved_at     timestamptz,
  live_at               timestamptz,
  verified_at           timestamptz,
  completed_at          timestamptz,
  cancelled_at          timestamptz,
  disclosure_failed_at  timestamptz,
  status_reason         text check (char_length(status_reason) <= 500),
  created_by            uuid default auth.uid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index deliverables_deal_idx on inf.deliverables (deal_id, position);
create index deliverables_status_idx on inf.deliverables (status) where status not in ('completed', 'cancelled');
create trigger deliverables_touch before update on inf.deliverables for each row execute function inf.touch_updated_at();
create trigger deliverables_audit after insert or update on inf.deliverables for each row execute function inf.audit_row('deliverable');

create table inf.deliverable_transitions (
  id              bigint generated always as identity primary key,
  deliverable_id  uuid not null references inf.deliverables (id) on delete restrict,
  from_status     text not null,
  to_status       text not null,
  action          text not null,
  actor_id        uuid default auth.uid(),
  actor_side      text not null check (actor_side in ('creator', 'agency', 'eduwit', 'system')),
  note            text check (char_length(note) <= 1000),
  at              timestamptz not null default now()
);
create index deliverable_transitions_idx on inf.deliverable_transitions (deliverable_id, at);
create trigger deliverable_transitions_append_only before update or delete on inf.deliverable_transitions for each row execute function inf.forbid_mutation();

create table inf.deliverable_submissions (
  id              uuid primary key default gen_random_uuid(),
  deliverable_id  uuid not null references inf.deliverables (id) on delete restrict,
  kind            text not null check (kind in ('concept', 'draft')),
  version         int not null check (version >= 1),
  body            text check (char_length(body) <= 20000),
  files           jsonb not null default '[]'::jsonb check (jsonb_typeof(files) = 'array' and jsonb_array_length(files) <= 10),
  link_url        text check (link_url ~ '^https://' and char_length(link_url) <= 1000),
  creator_note    text check (char_length(creator_note) <= 2000),
  status          text not null default 'submitted' check (status in ('submitted', 'approved', 'changes_requested')),
  author_side     text not null check (author_side in ('creator', 'agency')),
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  decided_by      uuid,
  decided_at      timestamptz,
  decision_note   text check (char_length(decision_note) <= 4000),
  unique (deliverable_id, kind, version)
);
-- A submission's content never changes; only the review decision is recorded on it.
create or replace function inf.submissions_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then raise exception 'inf.deliverable_submissions: append-only' using errcode = 'insufficient_privilege'; end if;
  if (new.deliverable_id, new.kind, new.version, new.body, new.files, new.link_url, new.creator_note, new.author_side, new.created_by, new.created_at)
     is distinct from (old.deliverable_id, old.kind, old.version, old.body, old.files, old.link_url, old.creator_note, old.author_side, old.created_by, old.created_at)
     or old.status <> 'submitted' then
    raise exception 'inf.deliverable_submissions: a submission is immutable once made and decided once' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;
create trigger deliverable_submissions_guard before update or delete on inf.deliverable_submissions for each row execute function inf.submissions_guard();
create trigger deliverable_submissions_audit after insert or update on inf.deliverable_submissions for each row execute function inf.audit_row('deliverable_submission', 'body');

create table inf.review_comments (
  id                  uuid primary key default gen_random_uuid(),
  submission_id       uuid not null references inf.deliverable_submissions (id) on delete restrict,
  deliverable_id      uuid not null references inf.deliverables (id) on delete restrict,
  parent_id           uuid references inf.review_comments (id) on delete cascade,
  author_id           uuid not null default auth.uid(),
  author_side         text not null check (author_side in ('creator', 'agency', 'eduwit')),
  body                text not null check (char_length(body) between 1 and 4000),
  video_timestamp_ms  int check (video_timestamp_ms between 0 and 86400000),
  -- {file: index in the submission's files, x, y, w, h} as fractions of the image (0–1).
  image_region        jsonb check (image_region is null or jsonb_typeof(image_region) = 'object'),
  resolved_at         timestamptz,
  resolved_by         uuid,
  created_at          timestamptz not null default now()
);
create index review_comments_submission_idx on inf.review_comments (submission_id, created_at);
create trigger review_comments_audit after insert or update on inf.review_comments for each row execute function inf.audit_row('review_comment');

create table inf.compliance_checks (
  id               uuid primary key default gen_random_uuid(),
  deliverable_id   uuid not null references inf.deliverables (id) on delete restrict,
  submission_id    uuid references inf.deliverable_submissions (id) on delete restrict,
  kind             text not null check (kind in ('banned_claims', 'disclosure', 'asci_checklist')),
  result           jsonb not null default '{}'::jsonb check (jsonb_typeof(result) = 'object'),
  passed           boolean not null,
  overridden       boolean not null default false,
  override_reason  text check (char_length(override_reason) <= 1000),
  overridden_by    uuid,
  overridden_at    timestamptz,
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  check (not overridden or (override_reason is not null and char_length(trim(override_reason)) >= 3))
);
create index compliance_checks_submission_idx on inf.compliance_checks (submission_id, kind);
create trigger compliance_checks_audit after insert or update on inf.compliance_checks for each row execute function inf.audit_row('compliance_check');

create table inf.published_posts (
  id                   uuid primary key default gen_random_uuid(),
  deliverable_id       uuid not null references inf.deliverables (id) on delete restrict,
  live_url             text not null check (live_url ~ '^https://' and char_length(live_url) <= 1000),
  posted_on            date not null,
  oembed               jsonb check (oembed is null or jsonb_typeof(oembed) = 'object'),
  disclosure_ok        boolean,
  verification_status  text not null default 'pending' check (verification_status in ('pending', 'verified', 'rejected', 'replaced')),
  verification         jsonb check (verification is null or jsonb_typeof(verification) = 'object'),
  verified_by          uuid,
  verified_at          timestamptz,
  review_note          text check (char_length(review_note) <= 1000),
  created_by           uuid default auth.uid(),
  created_at           timestamptz not null default now()
);
create index published_posts_deliverable_idx on inf.published_posts (deliverable_id, created_at);
create trigger published_posts_audit after insert or update on inf.published_posts for each row execute function inf.audit_row('published_post');

create table inf.post_metric_snapshots (
  id                 bigint generated always as identity primary key,
  deliverable_id     uuid not null references inf.deliverables (id) on delete restrict,
  published_post_id  uuid not null references inf.published_posts (id) on delete restrict,
  checkpoint         text not null check (checkpoint ~ '^([0-9]{1,4}h|adhoc)$'),
  views              bigint check (views >= 0),
  reach              bigint check (reach >= 0),
  likes              bigint check (likes >= 0),
  comments           bigint check (comments >= 0),
  shares             bigint check (shares >= 0),
  saves              bigint check (saves >= 0),
  clicks             bigint check (clicks >= 0),
  watch_time_s       bigint check (watch_time_s >= 0),
  -- Manual entry today; platform APIs fill the same columns later (spec 10.2) with source = 'api'.
  source             text not null default 'manual' check (source in ('manual', 'screenshot', 'api')),
  screenshot_paths   text[] not null default '{}' check (cardinality(screenshot_paths) <= 5),
  captured_at        timestamptz not null default now(),
  created_by         uuid default auth.uid()
);
create index post_metric_snapshots_idx on inf.post_metric_snapshots (deliverable_id, captured_at);
create trigger post_metric_snapshots_append_only before update or delete on inf.post_metric_snapshots for each row execute function inf.forbid_mutation();

-- Extra revision rounds beyond the contract's limit (spec 10.2): requested by a reviewer, approved by a manager,
-- optionally with a fee for the creator (posted with the ledger in Phase 7).
create table inf.revision_extensions (
  id              uuid primary key default gen_random_uuid(),
  deliverable_id  uuid not null references inf.deliverables (id) on delete restrict,
  reason          text not null check (char_length(reason) between 3 and 1000),
  fee_paise       bigint not null default 0 check (fee_paise between 0 and 100000000000),
  status          text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_by    uuid default auth.uid(),
  requested_at    timestamptz not null default now(),
  decided_by      uuid,
  decided_at      timestamptz,
  decision_note   text check (char_length(decision_note) <= 1000)
);
create unique index revision_extensions_one_pending_idx on inf.revision_extensions (deliverable_id) where status = 'pending';
create trigger revision_extensions_audit after insert or update on inf.revision_extensions for each row execute function inf.audit_row('revision_extension');

-- Penalties the engine proposes (late delivery, missed deliverable, missing disclosure); never applied without approval.
create table inf.penalty_proposals (
  id              uuid primary key default gen_random_uuid(),
  deal_id         uuid not null references inf.deals (id) on delete restrict,
  deliverable_id  uuid references inf.deliverables (id) on delete set null,
  key             text not null unique check (char_length(key) <= 300),
  rule_id         text not null,
  version_id      uuid not null references inf.deal_versions (id),
  subject         text not null,
  amount_paise    bigint not null check (amount_paise >= 0),
  forfeits        text[] not null default '{}',
  reason          text not null check (char_length(reason) <= 500),
  proposed_at     timestamptz not null,
  status          text not null default 'proposed' check (status in ('proposed', 'approved', 'rejected', 'withdrawn')),
  decided_by      uuid,
  decided_at      timestamptz,
  decision_note   text check (char_length(decision_note) <= 1000),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index penalty_proposals_status_idx on inf.penalty_proposals (status, deal_id);
create trigger penalty_proposals_touch before update on inf.penalty_proposals for each row execute function inf.touch_updated_at();
create trigger penalty_proposals_audit after insert or update on inf.penalty_proposals for each row execute function inf.audit_row('penalty_proposal');

-- ---------------------------------------------------------------------------------------------------------------
-- The workflow (mirror of lib/content/workflow.ts; supabase/tests/017_workflow_matrix.sql is generated from it)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.deliverable_next(p_from text, p_action text, s jsonb) returns text
language plpgsql immutable set search_path = '' as $$
declare
  b boolean := coalesce((s ->> 'brief')::boolean, true);
  c boolean := coalesce((s ->> 'concept')::boolean, true);
  d boolean := coalesce((s ->> 'draft')::boolean, true);
  sc boolean := coalesce((s ->> 'schedule')::boolean, false);
  v boolean := coalesce((s ->> 'verify')::boolean, true);
  m boolean := coalesce((s ->> 'metrics')::boolean, true);
  v_entry text := case when b then 'brief_acknowledged' else 'not_started' end;
  v_ready boolean := case when d then p_from = 'draft_approved' when c then p_from = 'concept_approved' else p_from = v_entry end;
  v_pub boolean := case when v then p_from = 'live_verified' else p_from = 'live' end;
begin
  if p_from in ('completed', 'cancelled') then return null; end if;
  return case p_action
    when 'acknowledge_brief' then case when b and p_from = 'not_started' then 'brief_acknowledged' end
    when 'submit_concept' then case when c and (p_from = v_entry or p_from = 'concept_changes_requested') then 'concept_submitted' end
    when 'approve_concept' then case when c and p_from = 'concept_submitted' then 'concept_approved' end
    when 'request_concept_changes' then case when c and p_from = 'concept_submitted' then 'concept_changes_requested' end
    when 'submit_draft' then case when d and ((case when c then p_from = 'concept_approved' else p_from = v_entry end)
                                            or p_from = 'draft_changes_requested') then 'draft_submitted' end
    when 'approve_draft' then case when d and p_from = 'draft_submitted' then 'draft_approved' end
    when 'request_draft_changes' then case when d and p_from = 'draft_submitted' then 'draft_changes_requested' end
    when 'schedule' then case when sc and (v_ready or p_from = 'scheduled') then 'scheduled' end
    when 'go_live' then case when p_from = 'live' then 'live'
                             when (case when sc then p_from = 'scheduled' else v_ready end) then 'live' end
    when 'verify_live' then case when v and p_from = 'live' then 'live_verified' end
    when 'submit_metrics' then case when m and (v_pub or p_from = 'metrics_submitted') then 'metrics_submitted' end
    when 'complete' then case when (case when m then p_from = 'metrics_submitted' else v_pub end) then 'completed' end
    when 'cancel' then 'cancelled'
  end;
end $$;

-- What the creator owes next (mirror of pendingStage): concept, draft, live, metrics or null.
create or replace function inf.deliverable_pending(p_status text, s jsonb) returns text
language plpgsql immutable set search_path = '' as $$
declare
  b boolean := coalesce((s ->> 'brief')::boolean, true);
  c boolean := coalesce((s ->> 'concept')::boolean, true);
  d boolean := coalesce((s ->> 'draft')::boolean, true);
  v boolean := coalesce((s ->> 'verify')::boolean, true);
  m boolean := coalesce((s ->> 'metrics')::boolean, true);
  v_entry text := case when b then 'brief_acknowledged' else 'not_started' end;
  v_ready boolean := case when d then p_status = 'draft_approved' when c then p_status = 'concept_approved' else p_status = v_entry end;
  v_pub boolean := case when v then p_status = 'live_verified' else p_status = 'live' end;
begin
  if p_status in ('completed', 'cancelled') or (p_status = 'not_started' and b) then return null; end if;
  if p_status in ('concept_submitted', 'draft_submitted') then return null; end if;
  if c and (p_status = v_entry or p_status = 'concept_changes_requested') then return 'concept'; end if;
  if d and (p_status = 'draft_changes_requested' or (case when c then p_status = 'concept_approved' else p_status = v_entry end)) then
    return 'draft';
  end if;
  if v_ready or p_status = 'scheduled' then return 'live'; end if;
  if p_status = 'live' and v then return null; end if;
  if m and v_pub then return 'metrics'; end if;
  return null;
end $$;

-- Days overdue (≥ 1) for the pending stage, or null (mirror of overdue()).
create or replace function inf.deliverable_overdue_days(p_status text, s jsonb, p_due jsonb, p_now timestamptz default now())
returns int language plpgsql stable set search_path = '' as $$
declare v_stage text := inf.deliverable_pending(p_status, s); v_due timestamptz;
begin
  if v_stage is null then return null; end if;
  v_due := nullif(p_due ->> v_stage, '')::timestamptz;
  if v_due is null or p_now <= v_due then return null; end if;
  return ceil(extract(epoch from (p_now - v_due)) / 86400)::int;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Access and notifications
-- ---------------------------------------------------------------------------------------------------------------
-- The caller's side for a deal's content: eduwit (brief.read or deliverable.read), creator, agency ("act on
-- deliverables"). Creators and agencies see content once the deal is agreed.
create or replace function inf.content_side(p_deal uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when inf.has_perm('deliverable.read') or inf.has_perm('brief.read') then 'eduwit'
    when d.status not in ('agreed', 'active', 'completed', 'terminated', 'expired') then null
    when coalesce(d.creator_id = inf.current_creator_id(), false) then 'creator'
    when inf.agency_can(d.creator_id, 'deliverables') then 'agency'
    end
    from inf.deals d where d.id = p_deal;
$$;

create or replace function inf.content_notify(p_deal uuid, p_to text, p_event text, p_title text, p_body text,
                                              p_creator_link text, p_admin_link text, p_key text) returns void
language plpgsql security definer set search_path = '' as $$
declare d inf.deals; v_user uuid;
begin
  select * into d from inf.deals where id = p_deal;
  if p_to = 'creator' then
    select user_id into v_user from inf.creator_accounts where creator_id = d.creator_id;
    if v_user is not null then
      perform inf.notify(v_user, p_event, p_title, p_body, p_creator_link, jsonb_build_object('deal_id', p_deal), false,
                         p_event || ':' || p_key || ':c');
    end if;
    perform inf.notify(m.user_id, p_event, p_title, p_body, replace(p_creator_link, '/creator/', '/agency/'),
                       jsonb_build_object('deal_id', p_deal), false, p_event || ':' || p_key || ':' || m.user_id)
      from inf.agency_creator_links l join inf.agency_members m on m.agency_id = l.agency_id and m.status = 'active' and m.user_id is not null
     where l.creator_id = d.creator_id and l.status = 'active' and l.can_act_deliverables;
  else
    perform inf.notify(sp.user_id, p_event, p_title, p_body, p_admin_link, jsonb_build_object('deal_id', p_deal), false,
                       p_event || ':' || p_key || ':' || sp.user_id)
      from inf.staff_profiles sp
     where sp.status = 'active' and (sp.user_id = d.owner_id or (d.owner_id is null and exists (
             select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
              where g.user_id = sp.user_id and rp.permission = 'deliverable.review')));
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Banned claims and templates (staff)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.banned_claim_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  if not inf.has_perm('compliance.manage') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.banned_claims (pattern, kind, severity, note, active)
    values (trim(p ->> 'pattern'), p ->> 'kind', p ->> 'severity', nullif(trim(p ->> 'note'), ''), coalesce((p ->> 'active')::boolean, true))
    returning id into v_id;
  else
    update inf.banned_claims set pattern = trim(p ->> 'pattern'), kind = p ->> 'kind', severity = p ->> 'severity',
           note = nullif(trim(p ->> 'note'), ''), active = coalesce((p ->> 'active')::boolean, true)
     where id = v_id;
    if not found then raise exception 'no such claim' using errcode = '22023'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'this pattern is already in the list' using errcode = '23505';
end $$;

-- Active claims for the scan (staff and the service role; the server scans every submission).
create or replace function inf.banned_claims_active() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'pattern', c.pattern, 'kind', c.kind, 'severity', c.severity, 'note', c.note)
                            order by c.created_at), '[]')
    from inf.banned_claims c
   where c.active and (inf.has_perm('deliverable.read') or inf.has_perm('brief.read') or coalesce(auth.role(), '') = 'service_role');
$$;

create or replace function inf.brief_template_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid;
begin
  if not inf.has_perm('brief.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.brief_templates (name, description, content) values (trim(p ->> 'name'), nullif(trim(p ->> 'description'), ''), p -> 'content')
    returning id into v_id;
  else
    update inf.brief_templates set name = trim(p ->> 'name'), description = nullif(trim(p ->> 'description'), ''), content = p -> 'content'
     where id = v_id and archived_at is null;
    if not found then raise exception 'no such template' using errcode = '22023'; end if;
  end if;
  if coalesce((p ->> 'is_default')::boolean, false) then
    update inf.brief_templates set is_default = false where is_default and id <> v_id;
    update inf.brief_templates set is_default = true where id = v_id;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'a template with this name exists' using errcode = '23505';
end $$;

create or replace function inf.brief_template_archive(p_template uuid, p_archived boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('brief.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.brief_templates set archived_at = case when p_archived then now() end,
         is_default = case when p_archived then false else is_default end
   where id = p_template;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Briefs
-- ---------------------------------------------------------------------------------------------------------------
-- What the app needs to build a brief for a deal: template, campaign, agreed deliverables, catalogue programmes,
-- active banned claims, disclosure terms and the deal's existing brief and deliverables. Staff or the service role.
create or replace function inf.brief_source(p_deal uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare d inf.deals; v_template uuid;
begin
  if not (inf.has_perm('brief.write') or coalesce(auth.role(), '') = 'service_role') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into d from inf.deals where id = p_deal;
  if d.id is null then return null; end if;
  select coalesce((select t.id from inf.campaigns cp join inf.brief_templates t on t.id = cp.brief_template_id
                    where cp.id = d.campaign_id and t.archived_at is null),
                  (select t.id from inf.brief_templates t where t.is_default and t.archived_at is null))
    into v_template;
  return jsonb_build_object(
    'deal', jsonb_build_object('id', d.id, 'code', d.code, 'title', d.title, 'status', d.status, 'starts_on', d.starts_on,
                               'ends_on', d.ends_on, 'creator_id', d.creator_id, 'agreed_terms', d.agreed_terms),
    'template', (select jsonb_build_object('id', t.id, 'name', t.name, 'content', t.content) from inf.brief_templates t where t.id = v_template),
    'campaign', (select jsonb_build_object('id', cp.id, 'name', cp.name, 'objective', cp.objective, 'description', cp.description,
                                           'deliverables', cp.deliverables)
                   from inf.campaigns cp where cp.id = d.campaign_id),
    'programmes', coalesce((select jsonb_agg(jsonb_build_object(
                     'id', p.id, 'program_name', p.program_name, 'specialization', p.specialization, 'level', p.level, 'mode', p.mode,
                     'university', u.name, 'recognitions', to_jsonb(u.recognitions), 'accreditation_text', u.accreditation_text,
                     'fee_total', p.fee_total, 'fee_yearly', p.fee_yearly, 'min_qualification', p.min_qualification,
                     'min_pct_general', p.min_pct_general, 'eligibility_text', p.eligibility_text) order by cp.position)
                              from inf.campaign_programmes cp
                              join public.catalog_programs p on p.id = cp.programme_id and p.active
                              join public.catalog_universities u on u.id = p.university_id
                             where cp.campaign_id = d.campaign_id), '[]'),
    'banned', coalesce((select jsonb_agg(c.pattern order by c.created_at) from inf.banned_claims c where c.active and c.kind = 'phrase'), '[]'),
    'disclosure_terms', inf.setting('content.review') -> 'disclosure_terms',
    'default_revision_limit', inf.setting('content.review') -> 'default_revision_limit',
    'brief_id', (select b.id from inf.briefs b where b.deal_id = d.id),
    'deliverables', (select count(*) from inf.deliverables x where x.deal_id = d.id));
end $$;

create or replace function inf.brief_create(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare d inf.deals; v_id uuid;
begin
  if not (inf.has_perm('brief.write') or coalesce(auth.role(), '') = 'service_role') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into d from inf.deals where id = (p ->> 'deal_id')::uuid;
  if d.id is null then raise exception 'no such deal' using errcode = '22023'; end if;
  if d.status in ('completed', 'terminated', 'expired') then raise exception 'deal is closed' using errcode = '22023'; end if;
  insert into inf.briefs (deal_id, template_id, draft_content)
  values (d.id, nullif(p ->> 'template_id', '')::uuid, coalesce(p -> 'content', '{}'::jsonb))
  returning id into v_id;
  update inf.deliverables set brief_id = v_id where deal_id = d.id and brief_id is null;
  return v_id;
exception when unique_violation then
  raise exception 'this deal already has a brief' using errcode = '23505';
end $$;

create or replace function inf.brief_save(p_brief uuid, p_content jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('brief.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if jsonb_typeof(p_content) <> 'object' then raise exception 'invalid brief' using errcode = '22023'; end if;
  update inf.briefs set draft_content = p_content where id = p_brief;
  if not found then raise exception 'no such brief' using errcode = '22023'; end if;
end $$;

-- Publishes the working copy as the next version; the creator acknowledges it (again, for a new version).
create or replace function inf.brief_publish(p_brief uuid, p_note text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare b inf.briefs; v_id uuid; v_version int;
begin
  if not inf.has_perm('brief.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into b from inf.briefs where id = p_brief for update;
  if b.id is null then raise exception 'no such brief' using errcode = '22023'; end if;
  if b.draft_content = '{}'::jsonb then raise exception 'the brief is empty' using errcode = '22023'; end if;
  if b.current_version_id is not null
     and (select content from inf.brief_versions where id = b.current_version_id) = b.draft_content then
    raise exception 'nothing changed since the last version' using errcode = '22023';
  end if;
  v_version := coalesce((select max(version) from inf.brief_versions where brief_id = b.id), 0) + 1;
  insert into inf.brief_versions (brief_id, version, content, note) values (b.id, v_version, b.draft_content, nullif(trim(p_note), ''))
  returning id into v_id;
  update inf.briefs set current_version_id = v_id where id = b.id;
  perform inf.content_notify(b.deal_id, 'creator', case when v_version = 1 then 'brief.published' else 'brief.updated' end,
                             case when v_version = 1 then 'New brief to read' else 'Your brief was updated' end,
                             'Read the brief and acknowledge it before you start.', '/creator/briefs/' || b.id, '/admin/briefs/' || b.id,
                             v_id::text);
  return v_id;
end $$;

-- The creator (or their agency with "act on deliverables") acknowledges the current version. The first
-- acknowledgement starts the deliverables (brief stage) and is a timestamped event that can trigger a milestone.
create or replace function inf.brief_acknowledge(p_brief uuid, p_version uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare b inf.briefs; v_side text; v_first boolean; r record;
begin
  select * into b from inf.briefs where id = p_brief for update;
  v_side := inf.content_side(b.deal_id);
  if b.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
  if b.current_version_id is distinct from p_version then raise exception 'a newer version of the brief exists' using errcode = '22023'; end if;
  v_first := not exists (select 1 from inf.brief_acknowledgements where brief_id = b.id);
  insert into inf.brief_acknowledgements (brief_id, version_id, side) values (b.id, p_version, v_side)
  on conflict (version_id) do nothing;
  if not found then return; end if;
  for r in select * from inf.deliverables where deal_id = b.deal_id and status = 'not_started'
             and coalesce((stages ->> 'brief')::boolean, true) loop
    perform inf.deliverable_apply(r.id, 'acknowledge_brief', 'system', null);
  end loop;
  if v_first then
    perform inf.emit_event('brief.acknowledged', 'brief', b.id::text, jsonb_build_object('deal_id', b.deal_id, 'version_id', p_version),
                           'brief_acknowledged:' || b.id);
  end if;
  perform inf.content_notify(b.deal_id, 'eduwit', 'brief.acknowledged', 'Brief acknowledged', 'The creator has read and acknowledged the brief.',
                             '/creator/briefs/' || b.id, '/admin/briefs/' || b.id, p_version::text);
end $$;

create or replace function inf.brief_question_add(p_brief uuid, p_body text, p_parent uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare b inf.briefs; v_side text; v_id uuid;
begin
  select * into b from inf.briefs where id = p_brief;
  v_side := inf.content_side(b.deal_id);
  if b.id is null or v_side is null or (v_side = 'eduwit' and not inf.has_perm('brief.write')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if v_side <> 'eduwit' and b.current_version_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into inf.brief_questions (brief_id, parent_id, author_side, body) values (b.id, p_parent, v_side, trim(p_body))
  returning id into v_id;
  perform inf.content_notify(b.deal_id, case when v_side = 'eduwit' then 'creator' else 'eduwit' end, 'brief.question',
                             case when v_side = 'eduwit' then 'Eduwit answered on your brief' else 'New question on a brief' end,
                             left(trim(p_body), 200), '/creator/briefs/' || b.id, '/admin/briefs/' || b.id, v_id::text);
  return v_id;
end $$;

create or replace function inf.brief_detail(p_brief uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare b inf.briefs; d inf.deals; v_side text; v inf.brief_versions;
begin
  select * into b from inf.briefs where id = p_brief;
  if b.id is null then return null; end if;
  v_side := inf.content_side(b.deal_id);
  if v_side is null or (v_side <> 'eduwit' and b.current_version_id is null) then return null; end if;
  select * into d from inf.deals where id = b.deal_id;
  select * into v from inf.brief_versions where id = b.current_version_id;
  return jsonb_build_object(
    'id', b.id, 'side', v_side, 'template_id', b.template_id,
    'deal', jsonb_build_object('id', d.id, 'code', d.code, 'title', d.title, 'status', d.status, 'campaign_id', d.campaign_id),
    'creator', (select jsonb_build_object('id', c.id, 'display_name', c.display_name, 'handle', c.handle) from inf.creators c where c.id = d.creator_id),
    'draft_content', case when v_side = 'eduwit' then b.draft_content end,
    'current', case when v.id is null then null else jsonb_build_object('id', v.id, 'version', v.version, 'content', v.content,
                    'note', v.note, 'published_at', v.published_at) end,
    'versions', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'version', x.version, 'note', x.note, 'published_at', x.published_at,
                                                              'acknowledged_at', (select a.acknowledged_at from inf.brief_acknowledgements a where a.version_id = x.id))
                                           order by x.version)
                            from inf.brief_versions x where x.brief_id = b.id), '[]'),
    'acknowledged_current', exists (select 1 from inf.brief_acknowledgements a where a.version_id = b.current_version_id),
    'questions', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'parent_id', q.parent_id, 'author_side', q.author_side, 'body', q.body,
                                                               'created_at', q.created_at, 'mine', q.author_id = auth.uid()) order by q.created_at)
                             from inf.brief_questions q where q.brief_id = b.id), '[]'),
    'deliverables', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'code', x.code, 'title', x.title, 'platform', x.platform,
                                                                  'format', x.format, 'specs', x.specs, 'due_dates', x.due_dates, 'status', x.status)
                                               order by x.position, x.created_at)
                                from inf.deliverables x where x.deal_id = b.deal_id and x.status <> 'cancelled'), '[]'),
    'can_write', v_side = 'eduwit' and inf.has_perm('brief.write'));
end $$;

create or replace function inf.briefs_list(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_q text := nullif(trim(p ->> 'q'), ''); v_state text := nullif(p ->> 'state', '');
begin
  if not inf.has_perm('brief.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(row order by (row ->> 'updated_at') desc) from (
    select jsonb_build_object('id', b.id, 'deal_id', d.id, 'deal_code', d.code, 'deal_title', d.title, 'creator_name', c.display_name,
                              'handle', c.handle, 'version', v.version, 'published_at', v.published_at,
                              'acknowledged', exists (select 1 from inf.brief_acknowledgements a where a.version_id = b.current_version_id),
                              'open_questions', (select count(*) from inf.brief_questions q where q.brief_id = b.id and q.parent_id is null
                                                    and q.author_side <> 'eduwit'
                                                    and not exists (select 1 from inf.brief_questions r where r.parent_id = q.id and r.author_side = 'eduwit')),
                              'updated_at', b.updated_at) as row
      from inf.briefs b join inf.deals d on d.id = b.deal_id join inf.creators c on c.id = d.creator_id
      left join inf.brief_versions v on v.id = b.current_version_id
     where (v_q is null or d.title ilike '%' || v_q || '%' or c.display_name ilike '%' || v_q || '%' or d.code ilike '%' || v_q || '%')
       and (v_state is null
            or (v_state = 'draft' and b.current_version_id is null)
            or (v_state = 'unacknowledged' and b.current_version_id is not null
                and not exists (select 1 from inf.brief_acknowledgements a where a.version_id = b.current_version_id))
            or (v_state = 'acknowledged' and exists (select 1 from inf.brief_acknowledgements a where a.version_id = b.current_version_id)))
     limit 200) s), '[]');
end $$;

create or replace function inf.my_briefs(p_creator uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'deal_id', d.id, 'deal_title', d.title, 'version', v.version,
                                               'published_at', v.published_at,
                                               'acknowledged', exists (select 1 from inf.brief_acknowledgements a where a.version_id = b.current_version_id))
                            order by v.published_at desc), '[]')
    from inf.briefs b join inf.deals d on d.id = b.deal_id join inf.brief_versions v on v.id = b.current_version_id
   where d.creator_id = p_creator and inf.content_side(d.id) in ('creator', 'agency');
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Deliverables: creation, editing and the move engine
-- ---------------------------------------------------------------------------------------------------------------
-- Applies one workflow move (internal; every public function checks who may act first).
create or replace function inf.deliverable_apply(p_id uuid, p_action text, p_side text, p_note text) returns text
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_to text;
begin
  select * into x from inf.deliverables where id = p_id for update;
  if x.id is null then raise exception 'no such deliverable' using errcode = '22023'; end if;
  v_to := inf.deliverable_next(x.status, p_action, x.stages);
  if v_to is null then raise exception 'cannot % a deliverable that is %', replace(p_action, '_', ' '), replace(x.status, '_', ' ') using errcode = '22023'; end if;
  update inf.deliverables set status = v_to,
         concept_approved_at = case when p_action = 'approve_concept' then coalesce(concept_approved_at, now()) else concept_approved_at end,
         draft_approved_at = case when p_action = 'approve_draft' then coalesce(draft_approved_at, now()) else draft_approved_at end,
         live_at = case when p_action = 'go_live' then coalesce(live_at, now()) else live_at end,
         verified_at = case when p_action = 'verify_live' then now() else verified_at end,
         completed_at = case when v_to = 'completed' then now() else completed_at end,
         cancelled_at = case when v_to = 'cancelled' then now() else cancelled_at end,
         status_reason = case when v_to in ('cancelled', 'completed') then nullif(trim(p_note), '') else status_reason end
   where id = x.id;
  insert into inf.deliverable_transitions (deliverable_id, from_status, to_status, action, actor_side, note)
  values (x.id, x.status, v_to, p_action, p_side, nullif(trim(p_note), ''));
  if x.status <> v_to then
    perform inf.emit_event('deliverable.' || v_to, 'deliverable', x.id::text,
                           jsonb_build_object('deal_id', x.deal_id, 'from', x.status, 'action', p_action),
                           'deliverable:' || x.id || ':' || v_to || ':' || extract(epoch from clock_timestamp())::text);
  end if;
  -- Live, cancelled and verification results can create or change penalty proposals.
  if p_action in ('go_live', 'cancel') and x.status <> v_to then
    perform inf.job_enqueue('penalties.refresh', jsonb_build_object('deal_id', x.deal_id), now(),
                            'penalties:' || x.deal_id || ':' || x.id || ':' || p_action);
  end if;
  return v_to;
end $$;

-- Deliverables for a deal, one row per piece (the app expands counts and computes due dates). Staff or service role.
create or replace function inf.deliverables_create(p_deal uuid, p_items jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare d inf.deals; v_item jsonb; v_n int := 0; v_pos int; v_limit int;
begin
  if not (inf.has_perm('brief.write') or coalesce(auth.role(), '') = 'service_role') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into d from inf.deals where id = p_deal;
  if d.id is null then raise exception 'no such deal' using errcode = '22023'; end if;
  if d.status in ('completed', 'terminated', 'expired') then raise exception 'deal is closed' using errcode = '22023'; end if;
  v_pos := coalesce((select max(position) from inf.deliverables where deal_id = d.id), 0);
  v_limit := coalesce((inf.setting('content.review') ->> 'default_revision_limit')::int, 2);
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_pos := v_pos + 1;
    insert into inf.deliverables (deal_id, brief_id, title, platform, format, position, specs, stages, due_dates, revision_limit, config_ref)
    values (d.id, (select b.id from inf.briefs b where b.deal_id = d.id), trim(v_item ->> 'title'), v_item ->> 'platform', v_item ->> 'format',
            v_pos, coalesce(v_item -> 'specs', '{}'), coalesce(v_item -> 'stages', '{"brief":true,"concept":true,"draft":true,"schedule":false,"verify":true,"metrics":true}'),
            coalesce(v_item -> 'due_dates', '{}'), coalesce((v_item ->> 'revision_limit')::int, v_limit), nullif(v_item ->> 'config_ref', ''));
    v_n := v_n + 1;
  end loop;
  -- A brief already acknowledged starts new deliverables at once.
  if exists (select 1 from inf.brief_acknowledgements a join inf.briefs b on b.id = a.brief_id where b.deal_id = d.id) then
    update inf.deliverables set status = 'brief_acknowledged' where deal_id = d.id and status = 'not_started'
       and coalesce((stages ->> 'brief')::boolean, true);
  end if;
  return v_n;
end $$;

create or replace function inf.deliverable_update(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables;
begin
  if not inf.has_perm('brief.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into x from inf.deliverables where id = p_id for update;
  if x.id is null then raise exception 'no such deliverable' using errcode = '22023'; end if;
  if x.status in ('completed', 'cancelled') then raise exception 'this deliverable is closed' using errcode = '22023'; end if;
  -- A stage can only be switched while the deliverable hasn't reached it (the workflow must stay consistent).
  if p ? 'stages' and p -> 'stages' is distinct from x.stages and x.status not in ('not_started', 'brief_acknowledged') then
    raise exception 'stages can only change before work starts' using errcode = '22023';
  end if;
  update inf.deliverables set
    title = coalesce(nullif(trim(p ->> 'title'), ''), title),
    specs = coalesce(p -> 'specs', specs),
    stages = coalesce(p -> 'stages', stages),
    due_dates = coalesce(p -> 'due_dates', due_dates),
    revision_limit = coalesce((p ->> 'revision_limit')::int, revision_limit),
    config_ref = case when p ? 'config_ref' then nullif(p ->> 'config_ref', '') else config_ref end
   where id = x.id;
end $$;

-- Staff: complete or cancel (with a reason).
create or replace function inf.deliverable_set_status(p_id uuid, p_action text, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables;
begin
  if not inf.has_perm('deliverable.review') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_action not in ('complete', 'cancel') then raise exception 'invalid action' using errcode = '22023'; end if;
  if p_action = 'cancel' and coalesce(char_length(trim(p_reason)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into x from inf.deliverables where id = p_id;
  perform inf.deliverable_apply(p_id, p_action, 'eduwit', p_reason);
  perform inf.content_notify(x.deal_id, 'creator', 'deliverable.' || p_action, case when p_action = 'cancel' then 'Deliverable cancelled'
                             else 'Deliverable completed' end, coalesce(trim(p_reason), x.title), '/creator/deliverables/' || x.id,
                             '/admin/content/' || x.id, x.id::text || p_action);
end $$;

create or replace function inf.deliverable_schedule(p_id uuid, p_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_side text;
begin
  select * into x from inf.deliverables where id = p_id;
  v_side := inf.content_side(x.deal_id);
  if x.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_at is null or p_at < now() - interval '1 day' then raise exception 'choose a future date' using errcode = '22023'; end if;
  perform inf.deliverable_apply(p_id, 'schedule', v_side, null);
  update inf.deliverables set scheduled_for = p_at where id = p_id;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Submissions, review and comments
-- ---------------------------------------------------------------------------------------------------------------
-- The storage path prefix a creator may upload to for a deliverable (the server then creates a signed upload URL).
create or replace function inf.deliverable_upload_allowed(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select inf.content_side(x.deal_id) in ('creator', 'agency') and x.status not in ('completed', 'cancelled')
                     from inf.deliverables x where x.id = p_id), false);
$$;

create or replace function inf.submission_add(p_deliverable uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_side text; v_kind text := p ->> 'kind'; v_id uuid; v_file jsonb;
begin
  select * into x from inf.deliverables where id = p_deliverable for update;
  v_side := inf.content_side(x.deal_id);
  if x.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_kind not in ('concept', 'draft') then raise exception 'invalid submission' using errcode = '22023'; end if;
  if coalesce(trim(p ->> 'body'), '') = '' and coalesce(jsonb_array_length(p -> 'files'), 0) = 0 and coalesce(p ->> 'link_url', '') = '' then
    raise exception 'add text, a file or a link' using errcode = '22023';
  end if;
  for v_file in select * from jsonb_array_elements(coalesce(p -> 'files', '[]'::jsonb)) loop
    if coalesce(v_file ->> 'path', '') !~ ('^' || x.id::text || '/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$') then
      raise exception 'invalid file' using errcode = '22023';
    end if;
  end loop;
  perform inf.deliverable_apply(x.id, 'submit_' || v_kind, v_side, null);
  insert into inf.deliverable_submissions (deliverable_id, kind, version, body, files, link_url, creator_note, author_side)
  values (x.id, v_kind, coalesce((select max(version) from inf.deliverable_submissions where deliverable_id = x.id and kind = v_kind), 0) + 1,
          nullif(trim(p ->> 'body'), ''), coalesce(p -> 'files', '[]'), nullif(trim(p ->> 'link_url'), ''), nullif(trim(p ->> 'note'), ''), v_side)
  returning id into v_id;
  perform inf.content_notify(x.deal_id, 'eduwit', 'deliverable.submitted', initcap(v_kind) || ' to review: ' || x.title,
                             'A new submission is waiting for review.', '/creator/deliverables/' || x.id, '/admin/content/' || x.id, v_id::text);
  return v_id;
end $$;

-- The server records the automatic scan of a submission (service role only, so a client can't report a clean scan).
create or replace function inf.compliance_record(p_submission uuid, p_checks jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare s inf.deliverable_submissions; v_item jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into s from inf.deliverable_submissions where id = p_submission;
  if s.id is null then raise exception 'no such submission' using errcode = '22023'; end if;
  for v_item in select * from jsonb_array_elements(p_checks) loop
    if v_item ->> 'kind' not in ('banned_claims', 'disclosure') then raise exception 'invalid check' using errcode = '22023'; end if;
    insert into inf.compliance_checks (deliverable_id, submission_id, kind, result, passed)
    values (s.deliverable_id, s.id, v_item ->> 'kind', coalesce(v_item -> 'result', '{}'), (v_item ->> 'passed')::boolean);
  end loop;
end $$;

create or replace function inf.compliance_override(p_check uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('compliance.override') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(char_length(trim(p_reason)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.compliance_checks set overridden = true, override_reason = trim(p_reason), overridden_by = auth.uid(), overridden_at = now()
   where id = p_check and not passed and not overridden;
  if not found then raise exception 'nothing to override' using errcode = '22023'; end if;
end $$;

-- The ASCI checklist items (mirror of ASCI_CHECKLIST in lib/content/compliance.ts).
create or replace function inf.asci_items() returns text[]
language sql immutable set search_path = '' as $$
  select array['disclosure_upfront', 'disclosure_clear', 'disclosure_language', 'disclosure_in_video', 'approved_claims_only',
               'genuine_experience', 'no_misleading_results'];
$$;

-- Approve a submission or ask for changes. Approval needs the automatic scan recorded and passed (or overridden) and,
-- at the last approval before publishing, the ASCI checklist complete. Changes count against the revision limit.
create or replace function inf.submission_review(p_submission uuid, p_decision text, p_note text, p_checklist jsonb default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare s inf.deliverable_submissions; x inf.deliverables; v_last boolean; v_item text;
begin
  if not inf.has_perm('deliverable.review') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into s from inf.deliverable_submissions where id = p_submission for update;
  if s.id is null or s.status <> 'submitted' then raise exception 'this submission has already been reviewed' using errcode = '22023'; end if;
  select * into x from inf.deliverables where id = s.deliverable_id for update;
  if x.status <> s.kind || '_submitted'
     or s.version <> (select max(version) from inf.deliverable_submissions where deliverable_id = x.id and kind = s.kind) then
    raise exception 'this submission has already been reviewed' using errcode = '22023';
  end if;
  if p_decision = 'approve' then
    if not exists (select 1 from inf.compliance_checks where submission_id = s.id and kind = 'banned_claims') then
      raise exception 'the compliance scan has not run on this submission' using errcode = '22023';
    end if;
    if exists (select 1 from inf.compliance_checks where submission_id = s.id and kind in ('banned_claims', 'disclosure')
                and not passed and not overridden) then
      raise exception 'compliance checks failed: fix or override them first' using errcode = '22023';
    end if;
    v_last := s.kind = 'draft' or not coalesce((x.stages ->> 'draft')::boolean, true);
    if v_last then
      foreach v_item in array inf.asci_items() loop
        if coalesce((p_checklist ->> v_item)::boolean, false) is not true then
          raise exception 'complete the ASCI checklist before approving' using errcode = '22023';
        end if;
      end loop;
      insert into inf.compliance_checks (deliverable_id, submission_id, kind, result, passed)
      values (x.id, s.id, 'asci_checklist', jsonb_build_object('items', p_checklist), true);
    end if;
    update inf.deliverable_submissions set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = nullif(trim(p_note), '')
     where id = s.id;
    perform inf.deliverable_apply(x.id, 'approve_' || s.kind, 'eduwit', p_note);
    perform inf.content_notify(x.deal_id, 'creator', 'deliverable.approved', initcap(s.kind) || ' approved: ' || x.title,
                               coalesce(nullif(trim(p_note), ''), 'You can move on to the next step.'), '/creator/deliverables/' || x.id,
                               '/admin/content/' || x.id, s.id::text);
  elsif p_decision = 'changes' then
    if coalesce(char_length(trim(p_note)), 0) < 3 then raise exception 'say what should change' using errcode = '22023'; end if;
    if x.revisions_used >= x.revision_limit + x.extra_revisions then
      raise exception 'the revision limit is reached: request an extra revision first' using errcode = '22023';
    end if;
    update inf.deliverable_submissions set status = 'changes_requested', decided_by = auth.uid(), decided_at = now(), decision_note = trim(p_note)
     where id = s.id;
    update inf.deliverables set revisions_used = revisions_used + 1 where id = x.id;
    perform inf.deliverable_apply(x.id, 'request_' || s.kind || '_changes', 'eduwit', p_note);
    perform inf.content_notify(x.deal_id, 'creator', 'deliverable.changes_requested', 'Changes requested: ' || x.title, left(trim(p_note), 200),
                               '/creator/deliverables/' || x.id, '/admin/content/' || x.id, s.id::text);
  else
    raise exception 'invalid decision' using errcode = '22023';
  end if;
end $$;

create or replace function inf.review_comment_add(p_submission uuid, p_body text, p_timestamp_ms int default null,
                                                  p_region jsonb default null, p_parent uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare s inf.deliverable_submissions; x inf.deliverables; v_side text; v_id uuid;
begin
  select * into s from inf.deliverable_submissions where id = p_submission;
  select * into x from inf.deliverables where id = s.deliverable_id;
  v_side := inf.content_side(x.deal_id);
  if s.id is null or v_side is null or (v_side = 'eduwit' and not inf.has_perm('deliverable.review')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_region is not null and not (
       (p_region ->> 'x')::numeric between 0 and 1 and (p_region ->> 'y')::numeric between 0 and 1
       and coalesce((p_region ->> 'w')::numeric, 0) between 0 and 1 and coalesce((p_region ->> 'h')::numeric, 0) between 0 and 1
       and coalesce((p_region ->> 'file')::int, 0) between 0 and 9) then
    raise exception 'invalid region' using errcode = '22023';
  end if;
  insert into inf.review_comments (submission_id, deliverable_id, parent_id, author_side, body, video_timestamp_ms, image_region)
  values (s.id, x.id, p_parent, v_side, trim(p_body), p_timestamp_ms,
          case when p_region is null then null else jsonb_build_object('file', coalesce((p_region ->> 'file')::int, 0), 'x', (p_region ->> 'x')::numeric,
               'y', (p_region ->> 'y')::numeric, 'w', coalesce((p_region ->> 'w')::numeric, 0), 'h', coalesce((p_region ->> 'h')::numeric, 0)) end)
  returning id into v_id;
  perform inf.content_notify(x.deal_id, case when v_side = 'eduwit' then 'creator' else 'eduwit' end, 'deliverable.comment',
                             'New comment on ' || x.title, left(trim(p_body), 200), '/creator/deliverables/' || x.id,
                             '/admin/content/' || x.id, v_id::text);
  return v_id;
end $$;

create or replace function inf.review_comment_set_resolved(p_comment uuid, p_resolved boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare cm inf.review_comments;
begin
  select * into cm from inf.review_comments where id = p_comment;
  if cm.id is null or inf.content_side((select deal_id from inf.deliverables where id = cm.deliverable_id)) is null then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update inf.review_comments set resolved_at = case when p_resolved then now() end, resolved_by = case when p_resolved then auth.uid() end
   where id = p_comment;
end $$;

-- Extra revision rounds (spec 10.2).
create or replace function inf.revision_extension_request(p_deliverable uuid, p_reason text, p_fee_paise bigint default 0) returns uuid
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_id uuid;
begin
  if not inf.has_perm('deliverable.review') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into x from inf.deliverables where id = p_deliverable;
  if x.id is null or x.status in ('completed', 'cancelled') then raise exception 'no such deliverable' using errcode = '22023'; end if;
  insert into inf.revision_extensions (deliverable_id, reason, fee_paise) values (x.id, trim(p_reason), coalesce(p_fee_paise, 0))
  returning id into v_id;
  perform inf.content_notify(x.deal_id, 'eduwit', 'deliverable.extension_requested', 'Extra revision requested: ' || x.title, trim(p_reason),
                             '/creator/deliverables/' || x.id, '/admin/content/' || x.id, v_id::text);
  return v_id;
exception when unique_violation then
  raise exception 'a request is already waiting for approval' using errcode = '23505';
end $$;

create or replace function inf.revision_extension_decide(p_id uuid, p_approve boolean, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare r inf.revision_extensions;
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.revision_extensions set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(),
         decided_at = now(), decision_note = nullif(trim(p_note), '')
   where id = p_id and status = 'pending'
  returning * into r;
  if r.id is null then raise exception 'this request has already been decided' using errcode = '22023'; end if;
  if p_approve then update inf.deliverables set extra_revisions = extra_revisions + 1 where id = r.deliverable_id; end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Go-live, verification and metrics
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.post_submit(p_deliverable uuid, p_url text, p_posted_on date, p_oembed jsonb default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_side text; v_id uuid;
begin
  select * into x from inf.deliverables where id = p_deliverable for update;
  v_side := inf.content_side(x.deal_id);
  if x.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_posted_on is null or p_posted_on > (now() at time zone 'Asia/Kolkata')::date then
    raise exception 'the posting date can''t be in the future' using errcode = '22023';
  end if;
  perform inf.deliverable_apply(x.id, 'go_live', v_side, null);
  update inf.published_posts set verification_status = 'replaced' where deliverable_id = x.id and verification_status = 'pending';
  insert into inf.published_posts (deliverable_id, live_url, posted_on, oembed) values (x.id, trim(p_url), p_posted_on, p_oembed)
  returning id into v_id;
  perform inf.content_notify(x.deal_id, 'eduwit', 'deliverable.live', 'Live post to verify: ' || x.title, trim(p_url),
                             '/creator/deliverables/' || x.id, '/admin/content/' || x.id, v_id::text);
  return v_id;
end $$;

-- A reviewer checks the post is live, carries the disclosure and matches the approved version.
create or replace function inf.post_verify(p_post uuid, p_live boolean, p_disclosure boolean, p_matches boolean, p_note text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare pp inf.published_posts; x inf.deliverables; v_ok boolean := p_live and p_disclosure and p_matches;
begin
  if not inf.has_perm('deliverable.verify_live') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into pp from inf.published_posts where id = p_post for update;
  if pp.id is null or pp.verification_status <> 'pending' then raise exception 'this post has already been checked' using errcode = '22023'; end if;
  if not v_ok and coalesce(char_length(trim(p_note)), 0) < 3 then raise exception 'say what is wrong' using errcode = '22023'; end if;
  select * into x from inf.deliverables where id = pp.deliverable_id;
  update inf.published_posts set verification_status = case when v_ok then 'verified' else 'rejected' end, disclosure_ok = p_disclosure,
         verification = jsonb_build_object('live', p_live, 'disclosure', p_disclosure, 'matches', p_matches),
         verified_by = auth.uid(), verified_at = now(), review_note = nullif(trim(p_note), '')
   where id = pp.id;
  if not p_disclosure and x.disclosure_failed_at is null then
    update inf.deliverables set disclosure_failed_at = now() where id = x.id;
    perform inf.job_enqueue('penalties.refresh', jsonb_build_object('deal_id', x.deal_id), now(), 'penalties:' || x.deal_id || ':' || x.id || ':disclosure');
  end if;
  if v_ok and coalesce((x.stages ->> 'verify')::boolean, true) then
    perform inf.deliverable_apply(x.id, 'verify_live', 'eduwit', p_note);
  end if;
  perform inf.content_notify(x.deal_id, 'creator', case when v_ok then 'deliverable.verified' else 'deliverable.live_rejected' end,
                             case when v_ok then 'Live post verified: ' else 'Fix your live post: ' end || x.title,
                             coalesce(nullif(trim(p_note), ''), 'Thanks, the post is verified.'), '/creator/deliverables/' || x.id,
                             '/admin/content/' || x.id, pp.id::text);
end $$;

create or replace function inf.metrics_submit(p_deliverable uuid, p jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare x inf.deliverables; v_side text; pp inf.published_posts; v_id bigint; v_path text;
begin
  select * into x from inf.deliverables where id = p_deliverable for update;
  v_side := inf.content_side(x.deal_id);
  if x.id is null or v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into pp from inf.published_posts where deliverable_id = x.id and verification_status <> 'replaced' order by created_at desc limit 1;
  if pp.id is null then raise exception 'submit the live link first' using errcode = '22023'; end if;
  foreach v_path in array coalesce(array(select jsonb_array_elements_text(p -> 'screenshots')), '{}') loop
    if v_path !~ ('^' || x.id::text || '/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$') then raise exception 'invalid file' using errcode = '22023'; end if;
  end loop;
  insert into inf.post_metric_snapshots (deliverable_id, published_post_id, checkpoint, views, reach, likes, comments, shares, saves, clicks,
                                         watch_time_s, source, screenshot_paths)
  values (x.id, pp.id, coalesce(nullif(p ->> 'checkpoint', ''), 'adhoc'), nullif(p ->> 'views', '')::bigint, nullif(p ->> 'reach', '')::bigint,
          nullif(p ->> 'likes', '')::bigint, nullif(p ->> 'comments', '')::bigint, nullif(p ->> 'shares', '')::bigint,
          nullif(p ->> 'saves', '')::bigint, nullif(p ->> 'clicks', '')::bigint, nullif(p ->> 'watch_time_s', '')::bigint,
          case when jsonb_array_length(coalesce(p -> 'screenshots', '[]')) > 0 then 'screenshot' else 'manual' end,
          coalesce(array(select jsonb_array_elements_text(p -> 'screenshots')), '{}'))
  returning id into v_id;
  if inf.deliverable_next(x.status, 'submit_metrics', x.stages) is not null then
    perform inf.deliverable_apply(x.id, 'submit_metrics', v_side, null);
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Penalty proposals
-- ---------------------------------------------------------------------------------------------------------------
-- Facts the penalty job needs (service role): deal, accepted versions, contract signature, brief acknowledgement,
-- deliverables with their events and metrics.
create or replace function inf.deal_content_facts(p_deal uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'deal', jsonb_build_object('id', d.id, 'starts_on', d.starts_on, 'ends_on', d.ends_on),
    'versions', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'effective_from', v.effective_from, 'config', v.comp_config)
                                          order by v.effective_from)
                            from inf.deal_versions v where v.deal_id = d.id and v.state = 'accepted'), '[]'),
    'contract_signed_at', (select min(c.countersigned_at) from inf.contracts c where c.deal_id = d.id and c.countersigned_at is not null),
    'brief_acknowledged_at', (select min(a.acknowledged_at) from inf.brief_acknowledgements a join inf.briefs b on b.id = a.brief_id where b.deal_id = d.id),
    'deliverables', coalesce((select jsonb_agg(jsonb_build_object(
        'id', x.id, 'config_ref', x.config_ref, 'due_live_at', x.due_dates ->> 'live', 'concept_approved_at', x.concept_approved_at,
        'draft_approved_at', x.draft_approved_at, 'live_at', x.live_at, 'cancelled_at', x.cancelled_at,
        'disclosure_failed_at', x.disclosure_failed_at,
        'metrics', coalesce((select jsonb_agg(jsonb_build_object('at', m.captured_at, 'views', m.views, 'reach', m.reach) order by m.captured_at)
                               from inf.post_metric_snapshots m where m.deliverable_id = x.id), '[]')))
                                from inf.deliverables x where x.deal_id = d.id), '[]'))
    from inf.deals d
   where d.id = p_deal and coalesce(auth.role(), '') = 'service_role';
$$;

-- Replaces the open proposals of a deal with the engine's current answer (service role): new ones are added,
-- changed amounts updated while still proposed, ones the engine no longer proposes withdrawn. Decided ones are kept.
create or replace function inf.penalty_proposals_sync(p_deal uuid, p_items jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare v_item jsonb; v_n int := 0; v_keys text[] := '{}';
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_keys := v_keys || (v_item ->> 'key');
    insert into inf.penalty_proposals (deal_id, deliverable_id, key, rule_id, version_id, subject, amount_paise, forfeits, reason, proposed_at)
    values (p_deal, (select x.id from inf.deliverables x where x.deal_id = p_deal and (x.config_ref = v_item ->> 'subject' or x.id::text = v_item ->> 'subject') limit 1),
            v_item ->> 'key', v_item ->> 'rule_id', (v_item ->> 'version_id')::uuid, v_item ->> 'subject', (v_item ->> 'amount_paise')::bigint,
            coalesce(array(select jsonb_array_elements_text(v_item -> 'forfeits')), '{}'), left(v_item ->> 'reason', 500),
            (v_item ->> 'at')::timestamptz)
    on conflict (key) do update set amount_paise = excluded.amount_paise, reason = excluded.reason, forfeits = excluded.forfeits,
                                    status = case when inf.penalty_proposals.status = 'withdrawn' then 'proposed' else inf.penalty_proposals.status end
      where inf.penalty_proposals.status in ('proposed', 'withdrawn');
    v_n := v_n + 1;
  end loop;
  update inf.penalty_proposals set status = 'withdrawn' where deal_id = p_deal and status = 'proposed' and not (key = any (v_keys));
  return v_n;
end $$;

create or replace function inf.penalty_decide(p_id uuid, p_approve boolean, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare r inf.penalty_proposals;
begin
  if not inf.has_perm('penalty.approve') then raise exception 'not allowed' using errcode = '42501'; end if;
  if not p_approve and coalesce(char_length(trim(p_note)), 0) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.penalty_proposals set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_at = now(),
         decision_note = nullif(trim(p_note), '')
   where id = p_id and status = 'proposed'
  returning * into r;
  if r.id is null then raise exception 'this proposal has already been decided' using errcode = '22023'; end if;
  if p_approve then
    perform inf.emit_event('penalty.approved', 'penalty_proposal', r.id::text, jsonb_build_object('deal_id', r.deal_id, 'amount_paise', r.amount_paise),
                           'penalty_approved:' || r.id);
    perform inf.content_notify(r.deal_id, 'creator', 'penalty.approved', 'A penalty was applied to your deal', r.reason,
                               '/creator/deals/' || r.deal_id, '/admin/deals/' || r.deal_id, r.id::text);
  end if;
end $$;

create or replace function inf.penalties_list(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_status text := nullif(p ->> 'status', '');
begin
  if not (inf.has_perm('penalty.approve') or inf.has_perm('ledger.read') or inf.has_perm('deal.read')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', pp.id, 'deal_id', d.id, 'deal_code', d.code, 'deal_title', d.title,
                                                       'creator_name', c.display_name, 'deliverable_id', pp.deliverable_id,
                                                       'deliverable_title', x.title, 'rule_id', pp.rule_id, 'amount_paise', pp.amount_paise,
                                                       'forfeits', to_jsonb(pp.forfeits), 'reason', pp.reason, 'proposed_at', pp.proposed_at,
                                                       'status', pp.status, 'decided_at', pp.decided_at, 'decision_note', pp.decision_note)
                                    order by pp.proposed_at desc)
                     from inf.penalty_proposals pp join inf.deals d on d.id = pp.deal_id join inf.creators c on c.id = d.creator_id
                     left join inf.deliverables x on x.id = pp.deliverable_id
                    where (v_status is null or pp.status = v_status)
                      and (nullif(p ->> 'deal_id', '') is null or pp.deal_id = (p ->> 'deal_id')::uuid)), '[]');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.deliverable_detail(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare x inf.deliverables; d inf.deals; v_side text; v_me uuid := auth.uid();
begin
  select * into x from inf.deliverables where id = p_id;
  if x.id is null then return null; end if;
  v_side := inf.content_side(x.deal_id);
  if v_side is null then return null; end if;
  select * into d from inf.deals where id = x.deal_id;
  return to_jsonb(x) - 'created_by' || jsonb_build_object(
    'side', v_side,
    'overdue_days', inf.deliverable_overdue_days(x.status, x.stages, x.due_dates),
    'pending_stage', inf.deliverable_pending(x.status, x.stages),
    'deal', jsonb_build_object('id', d.id, 'code', d.code, 'title', d.title, 'status', d.status),
    'creator', (select jsonb_build_object('id', c.id, 'display_name', c.display_name, 'handle', c.handle) from inf.creators c where c.id = d.creator_id),
    'brief', (select jsonb_build_object('id', b.id, 'published', b.current_version_id is not null,
                                        'acknowledged', exists (select 1 from inf.brief_acknowledgements a where a.brief_id = b.id))
                from inf.briefs b where b.deal_id = d.id),
    'submissions', coalesce((select jsonb_agg(to_jsonb(s) - 'created_by' - 'decided_by' order by s.created_at desc)
                               from inf.deliverable_submissions s where s.deliverable_id = x.id), '[]'),
    'comments', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'submission_id', m.submission_id, 'parent_id', m.parent_id,
                                                              'author_side', m.author_side, 'body', m.body, 'video_timestamp_ms', m.video_timestamp_ms,
                                                              'image_region', m.image_region, 'resolved', m.resolved_at is not null,
                                                              'created_at', m.created_at, 'mine', m.author_id = v_me) order by m.created_at)
                            from inf.review_comments m where m.deliverable_id = x.id), '[]'),
    'checks', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'submission_id', k.submission_id, 'kind', k.kind, 'result', k.result,
                                                            'passed', k.passed, 'overridden', k.overridden, 'override_reason', k.override_reason,
                                                            'created_at', k.created_at) order by k.created_at)
                          from inf.compliance_checks k where k.deliverable_id = x.id), '[]'),
    'posts', coalesce((select jsonb_agg(to_jsonb(pp) - 'created_by' - 'verified_by' order by pp.created_at desc)
                         from inf.published_posts pp where pp.deliverable_id = x.id), '[]'),
    'metrics', coalesce((select jsonb_agg(to_jsonb(m) - 'created_by' order by m.captured_at)
                           from inf.post_metric_snapshots m where m.deliverable_id = x.id), '[]'),
    'transitions', coalesce((select jsonb_agg(jsonb_build_object('from', t.from_status, 'to', t.to_status, 'action', t.action,
                                                                 'side', t.actor_side, 'note', t.note, 'at', t.at) order by t.at)
                               from inf.deliverable_transitions t where t.deliverable_id = x.id), '[]'),
    'extensions', case when v_side = 'eduwit' then coalesce((select jsonb_agg(to_jsonb(e) - 'requested_by' - 'decided_by' order by e.requested_at)
                                                               from inf.revision_extensions e where e.deliverable_id = x.id), '[]') end,
    'can_review', v_side = 'eduwit' and inf.has_perm('deliverable.review'),
    'can_verify', v_side = 'eduwit' and inf.has_perm('deliverable.verify_live'),
    'can_override', v_side = 'eduwit' and inf.has_perm('compliance.override'),
    'can_edit', v_side = 'eduwit' and inf.has_perm('brief.write'),
    'can_extend', v_side = 'eduwit' and inf.has_perm('deal.write'),
    'metric_checkpoints', inf.setting('content.review') -> 'metric_checkpoints_hours');
end $$;

-- Staff list with filters: status, deal, a "review queue" (submitted work and live posts awaiting verification),
-- overdue, and a search over title, creator and deal.
create or replace function inf.deliverables_list(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_status text[] := case when jsonb_typeof(p -> 'status') = 'array' and jsonb_array_length(p -> 'status') > 0
                          then array(select jsonb_array_elements_text(p -> 'status')) end;
  v_view text := coalesce(nullif(p ->> 'view', ''), 'open');
  v_q text := nullif(trim(p ->> 'q'), '');
begin
  if not inf.has_perm('deliverable.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(row order by (row ->> 'sort_due') nulls last, (row ->> 'code')) from (
    select jsonb_build_object('id', x.id, 'code', x.code, 'title', x.title, 'platform', x.platform, 'format', x.format, 'status', x.status,
                              'deal_id', d.id, 'deal_code', d.code, 'deal_title', d.title, 'creator_name', c.display_name, 'handle', c.handle,
                              'due_dates', x.due_dates, 'pending_stage', inf.deliverable_pending(x.status, x.stages),
                              'overdue_days', inf.deliverable_overdue_days(x.status, x.stages, x.due_dates),
                              'awaiting_verification', exists (select 1 from inf.published_posts pp where pp.deliverable_id = x.id and pp.verification_status = 'pending'),
                              'sort_due', x.due_dates ->> inf.deliverable_pending(x.status, x.stages),
                              'updated_at', x.updated_at) as row
      from inf.deliverables x join inf.deals d on d.id = x.deal_id join inf.creators c on c.id = d.creator_id
     where (v_status is null or x.status = any (v_status))
       and (nullif(p ->> 'deal_id', '') is null or x.deal_id = (p ->> 'deal_id')::uuid)
       and (v_q is null or x.title ilike '%' || v_q || '%' or c.display_name ilike '%' || v_q || '%' or d.title ilike '%' || v_q || '%'
            or x.code ilike '%' || v_q || '%')
       and case v_view
             when 'open' then x.status not in ('completed', 'cancelled')
             when 'review' then x.status in ('concept_submitted', 'draft_submitted')
                                or exists (select 1 from inf.published_posts pp where pp.deliverable_id = x.id and pp.verification_status = 'pending')
             when 'overdue' then inf.deliverable_overdue_days(x.status, x.stages, x.due_dates) is not null
             when 'live' then x.status in ('live', 'live_verified', 'metrics_submitted', 'completed') and x.live_at is not null
             else true end
     limit 500) s), '[]');
end $$;

create or replace function inf.my_deliverables(p_creator uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'code', x.code, 'title', x.title, 'platform', x.platform, 'format', x.format,
                                               'status', x.status, 'deal_id', d.id, 'deal_title', d.title, 'due_dates', x.due_dates,
                                               'pending_stage', inf.deliverable_pending(x.status, x.stages),
                                               'overdue_days', inf.deliverable_overdue_days(x.status, x.stages, x.due_dates),
                                               'updated_at', x.updated_at)
                            order by x.due_dates ->> inf.deliverable_pending(x.status, x.stages) nulls last, x.code), '[]')
    from inf.deliverables x join inf.deals d on d.id = x.deal_id
   where d.creator_id = p_creator and inf.content_side(d.id) in ('creator', 'agency');
$$;

-- A file of this deliverable (a submission file or a metrics screenshot) for someone who may see it; the server then
-- creates a short-lived signed URL.
create or replace function inf.deliverable_file_allowed(p_deliverable uuid, p_path text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select inf.content_side(x.deal_id) is not null from inf.deliverables x where x.id = p_deliverable), false)
     and (exists (select 1 from inf.deliverable_submissions s, jsonb_array_elements(s.files) f
                   where s.deliverable_id = p_deliverable and f ->> 'path' = p_path)
          or exists (select 1 from inf.post_metric_snapshots m where m.deliverable_id = p_deliverable and p_path = any (m.screenshot_paths)));
$$;

-- A brief asset for someone who may read the brief (published versions only for creators and agencies).
create or replace function inf.brief_asset_allowed(p_brief uuid, p_path text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select case inf.content_side(b.deal_id)
             when 'eduwit' then b.draft_content -> 'assets' @> jsonb_build_array(jsonb_build_object('path', p_path))
                                or exists (select 1 from inf.brief_versions v where v.brief_id = b.id
                                             and v.content -> 'assets' @> jsonb_build_array(jsonb_build_object('path', p_path)))
             when 'creator' then (select v.content -> 'assets' @> jsonb_build_array(jsonb_build_object('path', p_path))
                                    from inf.brief_versions v where v.id = b.current_version_id)
             when 'agency' then (select v.content -> 'assets' @> jsonb_build_array(jsonb_build_object('path', p_path))
                                   from inf.brief_versions v where v.id = b.current_version_id)
             else false end
      from inf.briefs b where b.id = p_brief), false);
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Reminders (nightly): due dates coming up, overdue (creator on day 1, the deal owner after N days), metrics due.
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.content_remind() returns int
language plpgsql security definer set search_path = '' as $$
declare
  r record; v_set jsonb := inf.setting('content.schedule'); v_review jsonb := inf.setting('content.review'); v_n int := 0;
  v_stage text; v_due timestamptz; v_days int; v_overdue int; v_hours int; v_today text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD');
begin
  for r in select x.* from inf.deliverables x join inf.deals d on d.id = x.deal_id
            where x.status not in ('completed', 'cancelled') and d.status in ('agreed', 'active') loop
    v_stage := inf.deliverable_pending(r.status, r.stages);
    if v_stage is not null and v_stage <> 'metrics' then
      v_due := nullif(r.due_dates ->> v_stage, '')::timestamptz;
      if v_due is not null then
        v_days := ((v_due at time zone 'Asia/Kolkata')::date - (now() at time zone 'Asia/Kolkata')::date);
        v_overdue := inf.deliverable_overdue_days(r.status, r.stages, r.due_dates);
        if v_days in (select (x)::int from jsonb_array_elements_text(v_set -> 'due_reminder_days') x) then
          perform inf.content_notify(r.deal_id, 'creator', 'deliverable.due', r.title || ': ' || v_stage || ' due in ' || v_days || ' day(s)',
                                     'Submit it in the portal before the due date.', '/creator/deliverables/' || r.id, '/admin/content/' || r.id,
                                     r.id || ':' || v_stage || ':' || v_today);
          v_n := v_n + 1;
        elsif v_overdue = 1 then
          perform inf.content_notify(r.deal_id, 'creator', 'deliverable.overdue', r.title || ' is overdue',
                                     'The ' || v_stage || ' was due yesterday. Submit it now or tell Eduwit what is holding it up.',
                                     '/creator/deliverables/' || r.id, '/admin/content/' || r.id, r.id || ':' || v_stage);
          v_n := v_n + 1;
        elsif v_overdue = coalesce((v_set ->> 'overdue_escalation_days')::int, 2) then
          perform inf.content_notify(r.deal_id, 'eduwit', 'deliverable.overdue', r.title || ' is ' || v_overdue || ' days overdue',
                                     'The creator has not submitted the ' || v_stage || '.', '/creator/deliverables/' || r.id,
                                     '/admin/content/' || r.id, r.id || ':' || v_stage);
          v_n := v_n + 1;
        end if;
      end if;
    elsif v_stage = 'metrics' and r.live_at is not null then
      for v_hours in select (x)::int from jsonb_array_elements_text(v_review -> 'metric_checkpoints_hours') x loop
        if now() >= r.live_at + make_interval(hours => v_hours)
           and now() < r.live_at + make_interval(hours => v_hours + 24)
           and not exists (select 1 from inf.post_metric_snapshots m where m.deliverable_id = r.id and m.checkpoint = v_hours || 'h') then
          perform inf.content_notify(r.deal_id, 'creator', 'deliverable.metrics_due', 'Metrics due: ' || r.title,
                                     'Add the ' || v_hours || '-hour numbers with a screenshot of your insights.', '/creator/deliverables/' || r.id,
                                     '/admin/content/' || r.id, r.id || ':' || v_hours || 'h');
          v_n := v_n + 1;
        elsif now() >= r.live_at + make_interval(hours => v_hours + coalesce((v_set ->> 'metrics_grace_hours')::int, 48))
           and now() < r.live_at + make_interval(hours => v_hours + coalesce((v_set ->> 'metrics_grace_hours')::int, 48) + 24)
           and not exists (select 1 from inf.post_metric_snapshots m where m.deliverable_id = r.id and m.checkpoint = v_hours || 'h') then
          perform inf.content_notify(r.deal_id, 'eduwit', 'deliverable.metrics_overdue', 'Metrics missing: ' || r.title,
                                     'The ' || v_hours || '-hour metrics are past the grace period.', '/creator/deliverables/' || r.id,
                                     '/admin/content/' || r.id, r.id || ':' || v_hours || 'h');
          v_n := v_n + 1;
        end if;
      end loop;
    end if;
  end loop;
  return v_n;
end $$;

create or replace function inf.nightly_prune() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from inf.rate_hits where window_start < now() - interval '1 day';
  delete from inf.email_codes where created_at < now() - interval '7 days';
  delete from inf.contract_sign_codes where created_at < now() - interval '30 days';
  delete from inf.trusted_devices where (revoked_at is not null or expires_at < now()) and created_at < now() - interval '90 days';
  update inf.user_sessions set revoked_at = now(), revoke_reason = 'expired'
   where revoked_at is null and last_seen_at < now() - interval '30 days';
  delete from inf.jobs where status in ('done', 'cancelled') and finished_at < now() - interval '30 days';
  perform inf.creators_flag_dormant();
  perform inf.deals_expire();
  perform inf.contracts_remind();
  perform inf.content_remind();
end $$;

-- campaign_save: unchanged, plus the campaign's brief template.
create or replace function inf.campaign_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid; v_prog bigint; v_pos int := 0;
begin
  if not inf.has_perm('campaign.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.campaigns (name, objective, description, visibility, starts_on, ends_on, apply_by, budget_paise, slots,
                               eligibility, deliverables, compensation_summary, internal_notes, owner_id, default_preset_id,
                               contract_template_id, brief_template_id)
    values (trim(p ->> 'name'), p ->> 'objective', nullif(trim(p ->> 'description'), ''), coalesce(nullif(p ->> 'visibility', ''), 'open'),
            nullif(p ->> 'starts_on', '')::date, nullif(p ->> 'ends_on', '')::date, nullif(p ->> 'apply_by', '')::date,
            nullif(p ->> 'budget_paise', '')::bigint, nullif(p ->> 'slots', '')::int, coalesce(p -> 'eligibility', '{}'),
            coalesce(p -> 'deliverables', '[]'), nullif(trim(p ->> 'compensation_summary'), ''), nullif(trim(p ->> 'internal_notes'), ''),
            coalesce(nullif(p ->> 'owner_id', '')::uuid, auth.uid()), nullif(p ->> 'default_preset_id', '')::uuid,
            nullif(p ->> 'contract_template_id', '')::uuid, nullif(p ->> 'brief_template_id', '')::uuid)
    returning id into v_id;
  else
    update inf.campaigns set name = trim(p ->> 'name'), objective = p ->> 'objective', description = nullif(trim(p ->> 'description'), ''),
           visibility = coalesce(nullif(p ->> 'visibility', ''), visibility), starts_on = nullif(p ->> 'starts_on', '')::date,
           ends_on = nullif(p ->> 'ends_on', '')::date, apply_by = nullif(p ->> 'apply_by', '')::date,
           budget_paise = nullif(p ->> 'budget_paise', '')::bigint, slots = nullif(p ->> 'slots', '')::int,
           eligibility = coalesce(p -> 'eligibility', '{}'), deliverables = coalesce(p -> 'deliverables', '[]'),
           compensation_summary = nullif(trim(p ->> 'compensation_summary'), ''), internal_notes = nullif(trim(p ->> 'internal_notes'), ''),
           owner_id = nullif(p ->> 'owner_id', '')::uuid,
           default_preset_id = case when p ? 'default_preset_id' then nullif(p ->> 'default_preset_id', '')::uuid else default_preset_id end,
           contract_template_id = case when p ? 'contract_template_id' then nullif(p ->> 'contract_template_id', '')::uuid else contract_template_id end,
           brief_template_id = case when p ? 'brief_template_id' then nullif(p ->> 'brief_template_id', '')::uuid else brief_template_id end
     where id = v_id;
    if not found then raise exception 'no such campaign' using errcode = '22023'; end if;
  end if;
  if p ? 'programme_ids' then
    delete from inf.campaign_programmes where campaign_id = v_id
      and programme_id not in (select (x)::bigint from jsonb_array_elements_text(p -> 'programme_ids') x);
    for v_prog in select (x)::bigint from jsonb_array_elements_text(p -> 'programme_ids') x loop
      if not exists (select 1 from public.catalog_programs where id = v_prog) then
        raise exception 'unknown programme %', v_prog using errcode = '22023';
      end if;
      insert into inf.campaign_programmes (campaign_id, programme_id, position) values (v_id, v_prog, v_pos)
      on conflict (campaign_id, programme_id) do update set position = excluded.position;
      v_pos := v_pos + 1;
    end loop;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS: staff read; creators and agencies only through the functions above.
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.banned_claims enable row level security;
alter table inf.brief_templates enable row level security;
alter table inf.briefs enable row level security;
alter table inf.brief_versions enable row level security;
alter table inf.brief_acknowledgements enable row level security;
alter table inf.brief_questions enable row level security;
alter table inf.deliverables enable row level security;
alter table inf.deliverable_transitions enable row level security;
alter table inf.deliverable_submissions enable row level security;
alter table inf.review_comments enable row level security;
alter table inf.compliance_checks enable row level security;
alter table inf.published_posts enable row level security;
alter table inf.post_metric_snapshots enable row level security;
alter table inf.revision_extensions enable row level security;
alter table inf.penalty_proposals enable row level security;

create policy banned_claims_staff_read on inf.banned_claims for select to authenticated
  using ((select inf.has_perm('deliverable.read')) or (select inf.has_perm('brief.read')) or (select inf.has_perm('compliance.manage')));
create policy brief_templates_staff_read on inf.brief_templates for select to authenticated using ((select inf.has_perm('brief.read')));
create policy briefs_staff_read on inf.briefs for select to authenticated using ((select inf.has_perm('brief.read')));
create policy brief_versions_staff_read on inf.brief_versions for select to authenticated using ((select inf.has_perm('brief.read')));
create policy brief_acknowledgements_staff_read on inf.brief_acknowledgements for select to authenticated using ((select inf.has_perm('brief.read')));
create policy deliverables_staff_read on inf.deliverables for select to authenticated using ((select inf.has_perm('deliverable.read')));
create policy deliverable_transitions_staff_read on inf.deliverable_transitions for select to authenticated using ((select inf.has_perm('deliverable.read')));
create policy deliverable_submissions_staff_read on inf.deliverable_submissions for select to authenticated using ((select inf.has_perm('deliverable.read')));
create policy compliance_checks_staff_read on inf.compliance_checks for select to authenticated using ((select inf.has_perm('deliverable.read')));
create policy published_posts_staff_read on inf.published_posts for select to authenticated using ((select inf.has_perm('deliverable.read')));
create policy penalty_proposals_staff_read on inf.penalty_proposals for select to authenticated
  using ((select inf.has_perm('penalty.approve')) or (select inf.has_perm('ledger.read')));

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.banned_claims', 'authenticated', 'select'),
  ('table', 'inf.brief_templates', 'authenticated', 'select'),
  ('table', 'inf.briefs', 'authenticated', 'select'),
  ('table', 'inf.brief_versions', 'authenticated', 'select'),
  ('table', 'inf.brief_acknowledgements', 'authenticated', 'select'),
  ('table', 'inf.deliverables', 'authenticated', 'select'),
  ('table', 'inf.deliverable_transitions', 'authenticated', 'select'),
  ('table', 'inf.deliverable_submissions', 'authenticated', 'select'),
  ('table', 'inf.compliance_checks', 'authenticated', 'select'),
  ('table', 'inf.published_posts', 'authenticated', 'select'),
  ('table', 'inf.penalty_proposals', 'authenticated', 'select'),
  ('function', 'inf.deliverable_next(text, text, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deliverable_pending(text, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deliverable_overdue_days(text, jsonb, jsonb, timestamptz)', 'authenticated', 'execute'),
  ('function', 'inf.content_side(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.banned_claim_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.banned_claims_active()', 'authenticated', 'execute'),
  ('function', 'inf.brief_template_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.brief_template_archive(uuid, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.brief_source(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.brief_create(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.brief_save(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.brief_publish(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.brief_acknowledge(uuid, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.brief_question_add(uuid, text, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.brief_detail(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.briefs_list(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.my_briefs(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.deliverables_create(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deliverable_update(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deliverable_set_status(uuid, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.deliverable_schedule(uuid, timestamptz)', 'authenticated', 'execute'),
  ('function', 'inf.deliverable_upload_allowed(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.submission_add(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.compliance_override(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.asci_items()', 'authenticated', 'execute'),
  ('function', 'inf.submission_review(uuid, text, text, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.review_comment_add(uuid, text, int, jsonb, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.review_comment_set_resolved(uuid, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.revision_extension_request(uuid, text, bigint)', 'authenticated', 'execute'),
  ('function', 'inf.revision_extension_decide(uuid, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.post_submit(uuid, text, date, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.post_verify(uuid, boolean, boolean, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.metrics_submit(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.penalty_decide(uuid, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.penalties_list(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.deliverable_detail(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.deliverables_list(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.my_deliverables(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.deliverable_file_allowed(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.brief_asset_allowed(uuid, text)', 'authenticated', 'execute');
call inf.apply_client_grants();
