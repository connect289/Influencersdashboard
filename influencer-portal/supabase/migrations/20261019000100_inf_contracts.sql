-- Phase 4: contracts (spec 5 "Contracts", 8). Clause library with versions and legal-review marks, templates,
-- contracts with immutable versions, clause-anchored comments, change requests, versioned consent text, signing codes
-- and append-only signatures.
--
--   * Content is assembled by the app (lib/contracts, pure and tested) from the template, the clause versions and the
--     deal; the database stores each version's content and HTML and computes the SHA-256 of the HTML itself.
--   * Signing is service-role only: the app authenticates the person, then calls inf.contract_sign_* with their user
--     id, the IP and user agent it observed. A signature records the version, the document hash, typed name, consent
--     text and code reference, and can never change.
--   * Countersigning activates the deal and queues the final PDF (with its signature certificate).

-- ---------------------------------------------------------------------------------------------------------------
-- Deal versions replaced during contract negotiation (a structured compensation counter-offer)
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.deal_versions drop constraint deal_versions_origin_check;
alter table inf.deal_versions add constraint deal_versions_origin_check
  check (origin in ('builder', 'application', 'amendment', 'renewal', 'counter_offer'));
alter table inf.deal_versions drop constraint deal_versions_state_check;
alter table inf.deal_versions add constraint deal_versions_state_check
  check (state in ('proposed', 'accepted', 'declined', 'withdrawn', 'superseded'));

-- Immutable, except: a proposal is decided once; an accepted version can be superseded (replaced before signing).
create or replace function inf.deal_versions_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'inf.deal_versions: rows are append-only (delete refused)' using errcode = 'insufficient_privilege';
  end if;
  if (new.deal_id, new.version, new.comp_config, new.config_hash, new.origin, new.effective_from, new.proposed_by, new.proposed_at)
     is distinct from (old.deal_id, old.version, old.comp_config, old.config_hash, old.origin, old.effective_from, old.proposed_by, old.proposed_at)
     or (new.state is distinct from old.state
         and not (old.state = 'proposed') and not (old.state = 'accepted' and new.state = 'superseded')) then
    raise exception 'inf.deal_versions: a version is immutable' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Clause library
-- ---------------------------------------------------------------------------------------------------------------
create table inf.clauses (
  id               uuid primary key default gen_random_uuid(),
  key              text not null unique check (key ~ '^[a-z][a-z0-9_]{1,59}$'),
  category         text not null check (category in ('parties', 'scope', 'timelines', 'compensation', 'taxes', 'content_approval',
                     'disclosure', 'claims', 'usage_rights', 'exclusivity', 'confidentiality', 'data_protection', 'conduct',
                     'penalties', 'termination', 'force_majeure', 'indemnity', 'disputes', 'notices', 'entire_agreement', 'other')),
  current_version  int not null default 1,
  deal_types       text[] not null default '{}' check (deal_types <@ array['commission_only', 'fixed_only', 'hybrid', 'barter', 'custom']),
  archived_at      timestamptz,
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table inf.clause_versions (
  clause_id    uuid not null references inf.clauses (id) on delete cascade,
  version      int not null check (version >= 1),
  title        text not null check (char_length(title) between 2 and 160),
  body         jsonb not null check (jsonb_typeof(body) = 'object' and body ->> 'type' = 'doc'),
  required     boolean not null default false,
  negotiable   boolean not null default false,
  locked       boolean not null default false,
  reviewed_at  timestamptz,
  reviewed_by  uuid,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  primary key (clause_id, version),
  check (not (negotiable and locked))
);

-- A version's text never changes; only its legal-review mark can be set.
create or replace function inf.clause_versions_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then raise exception 'inf.clause_versions: append-only' using errcode = 'insufficient_privilege'; end if;
  if (new.clause_id, new.version, new.title, new.body, new.required, new.negotiable, new.locked, new.created_by, new.created_at)
     is distinct from (old.clause_id, old.version, old.title, old.body, old.required, old.negotiable, old.locked, old.created_by, old.created_at) then
    raise exception 'inf.clause_versions: a clause version is immutable; save a new version' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;
create trigger clause_versions_guard before update or delete on inf.clause_versions for each row execute function inf.clause_versions_guard();
create trigger clauses_touch before update on inf.clauses for each row execute function inf.touch_updated_at();
create trigger clauses_audit after insert or update or delete on inf.clauses for each row execute function inf.audit_row('clause');
create trigger clause_versions_audit after insert or update on inf.clause_versions for each row execute function inf.audit_row('clause_version');

create table inf.contract_templates (
  id           uuid primary key default gen_random_uuid(),
  key          text unique check (key ~ '^[a-z][a-z0-9_]{2,59}$'),
  name         text not null check (char_length(name) between 2 and 120),
  description  text check (char_length(description) <= 500),
  title        text not null check (char_length(title) between 2 and 200),
  header       jsonb not null default '{"type":"doc","content":[]}'::jsonb check (header ->> 'type' = 'doc'),
  footer       jsonb not null default '{"type":"doc","content":[]}'::jsonb check (footer ->> 'type' = 'doc'),
  is_default   boolean not null default false,
  archived_at  timestamptz,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index contract_templates_one_default_idx on inf.contract_templates (is_default) where is_default and archived_at is null;
create unique index contract_templates_name_idx on inf.contract_templates (lower(name)) where archived_at is null;

create table inf.template_clauses (
  template_id  uuid not null references inf.contract_templates (id) on delete cascade,
  clause_id    uuid not null references inf.clauses (id) on delete restrict,
  position     int not null,
  condition    text check (condition is null or condition ~ '^!?\s*[a-z][a-z0-9_.]*(\s*(==|!=)\s*"[^"]*")?$'),
  primary key (template_id, clause_id)
);
create trigger contract_templates_touch before update on inf.contract_templates for each row execute function inf.touch_updated_at();
create trigger contract_templates_audit after insert or update or delete on inf.contract_templates for each row execute function inf.audit_row('contract_template');
create trigger template_clauses_audit after insert or update or delete on inf.template_clauses for each row execute function inf.audit_row('template_clause');

-- Consent text shown before signing; versioned so each signature records exactly what was agreed to.
create table inf.consent_texts (
  version     int primary key,
  body        text not null check (char_length(body) between 20 and 2000),
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now()
);
create trigger consent_texts_append_only before update or delete on inf.consent_texts for each row execute function inf.forbid_mutation();
insert into inf.consent_texts (version, body) values (1,
  'I have read this agreement in full. I agree to sign it electronically, and I agree that my typed name and the one-time code sent to me are my signature and have the same effect as a handwritten signature.');

-- ---------------------------------------------------------------------------------------------------------------
-- Contracts
-- ---------------------------------------------------------------------------------------------------------------
create sequence inf.contract_number_seq;

create table inf.contracts (
  id                    uuid primary key default gen_random_uuid(),
  number                text not null unique default 'CT-' || lpad(nextval('inf.contract_number_seq')::text, 5, '0'),
  deal_id               uuid not null references inf.deals (id) on delete restrict,
  template_id           uuid not null references inf.contract_templates (id) on delete restrict,
  parent_contract_id    uuid references inf.contracts (id) on delete restrict,
  kind                  text not null default 'original' check (kind in ('original', 'amendment', 'renewal')),
  status                text not null default 'draft' check (status in ('draft', 'sent', 'in_negotiation', 'ready_to_sign',
                          'signed_by_creator', 'active', 'completed', 'terminated', 'expired', 'void', 'superseded')),
  current_version_id    uuid,
  payee_agency_id       uuid references inf.agencies (id) on delete restrict,
  effective_on          date,
  expires_on            date check (expires_on is null or effective_on is null or expires_on >= effective_on),
  stamp_duty_reference  text check (char_length(stamp_duty_reference) <= 200),
  negotiation_deadline  timestamptz,
  sent_at               timestamptz,
  creator_signed_at     timestamptz,
  countersigned_at      timestamptz,
  closed_at             timestamptz,
  status_reason         text check (char_length(status_reason) <= 1000),
  integrity_failed_at   timestamptz,
  created_by            uuid default auth.uid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index contracts_deal_idx on inf.contracts (deal_id, created_at desc);
create index contracts_status_idx on inf.contracts (status, updated_at desc);
-- One live contract per deal at a time (amendments supersede their parent when countersigned).
create unique index contracts_one_open_per_deal_idx on inf.contracts (deal_id)
  where status in ('draft', 'sent', 'in_negotiation', 'ready_to_sign', 'signed_by_creator');

create table inf.contract_versions (
  id               uuid primary key default gen_random_uuid(),
  contract_id      uuid not null references inf.contracts (id) on delete restrict,
  version          int not null check (version >= 1),
  deal_version_id  uuid not null references inf.deal_versions (id),
  content          jsonb not null check (jsonb_typeof(content) = 'object' and jsonb_typeof(content -> 'sections') = 'array'),
  html             text not null check (char_length(html) between 20 and 2000000),
  sha256           text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  overrides        jsonb not null default '{}'::jsonb check (jsonb_typeof(overrides) = 'object'),
  note             text check (char_length(note) <= 1000),
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  unique (contract_id, version)
);
create trigger contract_versions_append_only before update or delete on inf.contract_versions for each row execute function inf.forbid_mutation();
alter table inf.contracts add constraint contracts_current_version_fk foreign key (current_version_id) references inf.contract_versions (id);

create table inf.contract_comments (
  id           uuid primary key default gen_random_uuid(),
  contract_id  uuid not null references inf.contracts (id) on delete cascade,
  version_id   uuid not null references inf.contract_versions (id),
  clause_key   text not null check (char_length(clause_key) between 1 and 60),
  parent_id    uuid references inf.contract_comments (id) on delete cascade,
  author_id    uuid not null default auth.uid(),
  author_side  text not null check (author_side in ('creator', 'agency', 'eduwit')),
  body         text not null check (char_length(body) between 1 and 4000),
  resolved_at  timestamptz,
  resolved_by  uuid,
  created_at   timestamptz not null default now()
);
create index contract_comments_idx on inf.contract_comments (contract_id, clause_key, created_at);

create table inf.contract_change_requests (
  id              uuid primary key default gen_random_uuid(),
  contract_id     uuid not null references inf.contracts (id) on delete cascade,
  version_id      uuid not null references inf.contract_versions (id),
  kind            text not null check (kind in ('clause', 'compensation')),
  clause_key      text check (char_length(clause_key) between 1 and 60),
  proposed_body   jsonb check (proposed_body is null or proposed_body ->> 'type' = 'doc'),
  proposed_terms  jsonb check (proposed_terms is null or jsonb_typeof(proposed_terms) = 'object'),
  note            text check (char_length(note) <= 2000),
  from_side       text not null check (from_side in ('creator', 'agency')),
  status          text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'countered', 'withdrawn')),
  created_by      uuid not null default auth.uid(),
  created_at      timestamptz not null default now(),
  decided_by      uuid,
  decided_at      timestamptz,
  decision_note   text check (char_length(decision_note) <= 2000),
  resolved_in_version_id uuid references inf.contract_versions (id),
  check ((kind = 'clause' and clause_key is not null and proposed_body is not null)
      or (kind = 'compensation' and proposed_terms is not null))
);
create index contract_change_requests_idx on inf.contract_change_requests (contract_id, status);

-- One-time signing codes (only their salted hash is stored).
create table inf.contract_sign_codes (
  id           uuid primary key default gen_random_uuid(),
  contract_id  uuid not null references inf.contracts (id) on delete cascade,
  version_id   uuid not null references inf.contract_versions (id),
  user_id      uuid not null,
  role         text not null check (role in ('creator', 'signatory')),
  channel      text not null check (channel in ('email', 'whatsapp')),
  code_hash    text not null,
  salt         text not null,
  attempts     int not null default 0,
  expires_at   timestamptz not null,
  consumed_at  timestamptz,
  created_at   timestamptz not null default now()
);
create index contract_sign_codes_idx on inf.contract_sign_codes (user_id, contract_id, created_at desc);

create table inf.signatures (
  id                uuid primary key default gen_random_uuid(),
  contract_id       uuid not null references inf.contracts (id) on delete restrict,
  version_id        uuid not null references inf.contract_versions (id),
  signer_user_id    uuid not null,
  signer_role       text not null check (signer_role in ('creator', 'agency', 'signatory')),
  signer_name       text not null check (char_length(signer_name) between 2 and 160),
  signer_designation text check (char_length(signer_designation) <= 120),
  document_sha256   text not null check (document_sha256 ~ '^[0-9a-f]{64}$'),
  consent_version   int not null references inf.consent_texts (version),
  consent_text      text not null,
  otp_channel       text not null,
  otp_reference     uuid not null,
  ip                inet,
  user_agent        text check (char_length(user_agent) <= 500),
  signed_at         timestamptz not null default now(),
  signed_at_ist     text not null default to_char(now() at time zone 'Asia/Kolkata', 'DD Mon YYYY HH24:MI:SS "IST"'),
  geo               jsonb
);
create trigger signatures_append_only before update or delete on inf.signatures for each row execute function inf.forbid_mutation();
create unique index signatures_once_idx on inf.signatures (version_id, signer_role);

-- Final signed PDFs (stored in the private bucket inf-contracts; the hash is re-checked on every download).
create table inf.contract_files (
  id           uuid primary key default gen_random_uuid(),
  contract_id  uuid not null references inf.contracts (id) on delete restrict,
  version_id   uuid not null references inf.contract_versions (id),
  kind         text not null default 'signed_pdf' check (kind in ('signed_pdf')),
  storage_path text not null unique,
  sha256       text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  created_at   timestamptz not null default now(),
  unique (version_id, kind)
);
create trigger contract_files_append_only before update or delete on inf.contract_files for each row execute function inf.forbid_mutation();

create trigger contracts_touch before update on inf.contracts for each row execute function inf.touch_updated_at();
create trigger contracts_audit after insert or update or delete on inf.contracts for each row execute function inf.audit_row('contract');
create trigger contract_versions_audit after insert on inf.contract_versions for each row execute function inf.audit_row('contract_version', 'html', 'content');
create trigger contract_comments_audit after insert or update on inf.contract_comments for each row execute function inf.audit_row('contract_comment');
create trigger contract_change_requests_audit after insert or update on inf.contract_change_requests for each row execute function inf.audit_row('contract_change_request');
create trigger signatures_audit after insert on inf.signatures for each row execute function inf.audit_row('signature', 'ip', 'user_agent');

-- ---------------------------------------------------------------------------------------------------------------
-- Access helpers
-- ---------------------------------------------------------------------------------------------------------------
-- Which side the caller is on for a contract: eduwit (staff with contract.read), creator, agency (negotiate grant).
create or replace function inf.contract_side(p_contract uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when inf.has_perm('contract.read') then 'eduwit'
    when coalesce(d.creator_id = inf.current_creator_id(), false) then 'creator'
    when inf.agency_can(d.creator_id, 'negotiate') then 'agency'
    end
    from inf.contracts c join inf.deals d on d.id = c.deal_id
   where c.id = p_contract;
$$;

create or replace function inf.contract_notify(p_contract uuid, p_to text, p_event text, p_title text, p_body text) returns void
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; d inf.deals; v_user uuid; v_key text := extract(epoch from clock_timestamp())::bigint::text;
begin
  select * into c from inf.contracts where id = p_contract;
  select * into d from inf.deals where id = c.deal_id;
  if p_to in ('creator', 'all') then
    select user_id into v_user from inf.creator_accounts where creator_id = d.creator_id;
    if v_user is not null then
      perform inf.notify(v_user, p_event, p_title, p_body, '/creator/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), true,
                         p_event || ':' || p_contract || ':c:' || v_key);
    end if;
    perform inf.notify(m.user_id, p_event, p_title, p_body, '/agency/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), false,
                       p_event || ':' || p_contract || ':' || m.user_id || ':' || v_key)
      from inf.agency_creator_links l join inf.agency_members m on m.agency_id = l.agency_id and m.status = 'active' and m.user_id is not null
     where l.creator_id = d.creator_id and l.status = 'active' and l.can_negotiate_sign;
  end if;
  if p_to in ('eduwit', 'all') then
    perform inf.notify(sp.user_id, p_event, p_title, p_body, '/admin/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), false,
                       p_event || ':' || p_contract || ':' || sp.user_id || ':' || v_key)
      from inf.staff_profiles sp
     where sp.status = 'active' and (sp.user_id = d.owner_id or (d.owner_id is null and exists (
             select 1 from inf.staff_role_grants g join inf.role_permissions rp on rp.role = g.role
              where g.user_id = sp.user_id and rp.permission = 'contract.write')));
  end if;
  if p_to = 'signatory' then
    perform inf.notify(sp.user_id, p_event, p_title, p_body, '/admin/contracts/' || p_contract, jsonb_build_object('contract_id', p_contract), true,
                       p_event || ':' || p_contract || ':' || sp.user_id || ':' || v_key)
      from inf.staff_profiles sp where sp.status = 'active' and sp.is_signatory;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Clause library and templates (staff)
-- ---------------------------------------------------------------------------------------------------------------
-- New clause, or a new version when the title, body or flags change (old contracts keep their version).
create or replace function inf.clause_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid; v_cur inf.clause_versions; v_next int;
begin
  if not inf.has_perm('clause.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.clauses (key, category, deal_types)
    values (p ->> 'key', p ->> 'category', coalesce(array(select jsonb_array_elements_text(p -> 'deal_types')), '{}'))
    returning id into v_id;
    insert into inf.clause_versions (clause_id, version, title, body, required, negotiable, locked)
    values (v_id, 1, trim(p ->> 'title'), p -> 'body', coalesce((p ->> 'required')::boolean, false),
            coalesce((p ->> 'negotiable')::boolean, false), coalesce((p ->> 'locked')::boolean, false));
    return v_id;
  end if;
  update inf.clauses set category = p ->> 'category', deal_types = coalesce(array(select jsonb_array_elements_text(p -> 'deal_types')), '{}')
   where id = v_id and archived_at is null;
  if not found then raise exception 'no such clause' using errcode = '22023'; end if;
  select v.* into v_cur from inf.clause_versions v join inf.clauses c on c.id = v.clause_id and v.version = c.current_version where c.id = v_id;
  if (v_cur.title, v_cur.body, v_cur.required, v_cur.negotiable, v_cur.locked)
     is distinct from (trim(p ->> 'title'), p -> 'body', coalesce((p ->> 'required')::boolean, false),
                       coalesce((p ->> 'negotiable')::boolean, false), coalesce((p ->> 'locked')::boolean, false)) then
    v_next := v_cur.version + 1;
    insert into inf.clause_versions (clause_id, version, title, body, required, negotiable, locked)
    values (v_id, v_next, trim(p ->> 'title'), p -> 'body', coalesce((p ->> 'required')::boolean, false),
            coalesce((p ->> 'negotiable')::boolean, false), coalesce((p ->> 'locked')::boolean, false));
    update inf.clauses set current_version = v_next where id = v_id;
  end if;
  return v_id;
end $$;

create or replace function inf.clause_mark_reviewed(p_clause uuid, p_version int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('clause.legal_review') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.clause_versions set reviewed_at = now(), reviewed_by = auth.uid()
   where clause_id = p_clause and version = p_version and reviewed_at is null;
  if not found then raise exception 'already reviewed or no such version' using errcode = '22023'; end if;
end $$;

create or replace function inf.clause_archive(p_clause uuid, p_archived boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('clause.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_archived and exists (select 1 from inf.template_clauses tc join inf.contract_templates t on t.id = tc.template_id
                             where tc.clause_id = p_clause and t.archived_at is null) then
    raise exception 'clause is used by a template' using errcode = '22023';
  end if;
  update inf.clauses set archived_at = case when p_archived then now() end where id = p_clause;
end $$;

create or replace function inf.template_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := nullif(p ->> 'id', '')::uuid; v_item jsonb; v_pos int := 0;
begin
  if not inf.has_perm('clause.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.contract_templates (name, description, title, header, footer)
    values (trim(p ->> 'name'), nullif(trim(p ->> 'description'), ''), trim(p ->> 'title'), p -> 'header', p -> 'footer')
    returning id into v_id;
  else
    update inf.contract_templates set name = trim(p ->> 'name'), description = nullif(trim(p ->> 'description'), ''),
           title = trim(p ->> 'title'), header = p -> 'header', footer = p -> 'footer'
     where id = v_id and archived_at is null;
    if not found then raise exception 'no such template' using errcode = '22023'; end if;
  end if;
  if p ? 'clauses' then
    delete from inf.template_clauses where template_id = v_id;
    for v_item in select * from jsonb_array_elements(p -> 'clauses') loop
      if not exists (select 1 from inf.clauses where id = (v_item ->> 'clause_id')::uuid and archived_at is null) then
        raise exception 'unknown clause' using errcode = '22023';
      end if;
      insert into inf.template_clauses (template_id, clause_id, position, condition)
      values (v_id, (v_item ->> 'clause_id')::uuid, v_pos, nullif(trim(v_item ->> 'condition'), ''));
      v_pos := v_pos + 1;
    end loop;
  end if;
  if coalesce((p ->> 'is_default')::boolean, false) then
    update inf.contract_templates set is_default = false where is_default and id <> v_id;
    update inf.contract_templates set is_default = true where id = v_id;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'a template with this name exists' using errcode = '23505';
end $$;

create or replace function inf.template_archive(p_template uuid, p_archived boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('clause.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.contract_templates set archived_at = case when p_archived then now() end,
         is_default = case when p_archived then false else is_default end
   where id = p_template;
end $$;

-- Everything the app needs to assemble a contract from a template: the template, its clauses' current versions.
create or replace function inf.template_source(p_template uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', t.id, 'name', t.name, 'description', t.description, 'title', t.title, 'header', t.header, 'footer', t.footer,
    'is_default', t.is_default, 'archived', t.archived_at is not null,
    'clauses', coalesce((select jsonb_agg(jsonb_build_object(
                  'clause_id', c.id, 'key', c.key, 'category', c.category, 'version', v.version, 'title', v.title, 'body', v.body,
                  'required', v.required, 'negotiable', v.negotiable, 'locked', v.locked, 'reviewed', v.reviewed_at is not null,
                  'condition', tc.condition) order by tc.position)
                  from inf.template_clauses tc join inf.clauses c on c.id = tc.clause_id
                  join inf.clause_versions v on v.clause_id = c.id and v.version = c.current_version
                 where tc.template_id = t.id), '[]'))
    from inf.contract_templates t
   where t.id = p_template and (inf.has_perm('contract.read') or inf.has_perm('clause.write'));
$$;

-- The library for the editor: every clause with its current version and review state.
create or replace function inf.clause_library(p_include_archived boolean default false) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'key', c.key, 'category', c.category, 'deal_types', to_jsonb(c.deal_types), 'version', v.version,
           'title', v.title, 'body', v.body, 'required', v.required, 'negotiable', v.negotiable, 'locked', v.locked,
           'reviewed_at', v.reviewed_at, 'archived', c.archived_at is not null, 'updated_at', c.updated_at,
           'versions', (select count(*) from inf.clause_versions x where x.clause_id = c.id))
         order by c.category, c.key), '[]')
    from inf.clauses c join inf.clause_versions v on v.clause_id = c.id and v.version = c.current_version
   where (inf.has_perm('contract.read') or inf.has_perm('clause.write')) and (p_include_archived or c.archived_at is null);
$$;

create or replace function inf.clause_history(p_clause uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('version', v.version, 'title', v.title, 'body', v.body, 'required', v.required,
                                               'negotiable', v.negotiable, 'locked', v.locked, 'reviewed_at', v.reviewed_at,
                                               'created_at', v.created_at) order by v.version desc), '[]')
    from inf.clause_versions v
   where v.clause_id = p_clause and (inf.has_perm('contract.read') or inf.has_perm('clause.write'));
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Contract lifecycle (staff)
-- ---------------------------------------------------------------------------------------------------------------
-- Everything the app needs to build a contract for a deal: the terms in force, parties, Eduwit and its signatory.
create or replace function inf.contract_source(p_deal uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare d inf.deals; v_out jsonb;
begin
  if not inf.has_perm('contract.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from inf.deals where id = p_deal;
  if d.id is null then return null; end if;
  select jsonb_build_object(
    'deal', jsonb_build_object('id', d.id, 'code', d.code, 'title', d.title, 'status', d.status, 'starts_on', d.starts_on,
                               'ends_on', d.ends_on, 'deal_model', d.deal_model, 'agreed_terms', d.agreed_terms,
                               'current_version_id', d.current_version_id,
                               'comp_config', (select v.comp_config from inf.deal_versions v where v.id = d.current_version_id)),
    'creator', (select jsonb_build_object('id', c.id, 'display_name', c.display_name, 'handle', c.handle, 'city', c.city,
                                          'state', c.state, 'email', c.email,
                                          'legal_name', (select k.name_on_pan from inf.creator_kyc k where k.creator_id = c.id),
                                          'pan_last4', (select k.pan_last4 from inf.creator_kyc k where k.creator_id = c.id),
                                          'gstin', (select k.gstin from inf.creator_kyc k where k.creator_id = c.id and k.gst_status <> 'unregistered' and k.gstin_verified))
                  from inf.creators c where c.id = d.creator_id),
    'campaign', (select jsonb_build_object('name', cp.name, 'deliverables', cp.deliverables) from inf.campaigns cp where cp.id = d.campaign_id),
    'agencies', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name))
                            from inf.agency_creator_links l join inf.agencies a on a.id = l.agency_id
                           where l.creator_id = d.creator_id and l.status = 'active' and l.can_negotiate_sign), '[]'),
    'organisation', inf.setting('organisation.profile'),
    'signatory', (select jsonb_build_object('name', sp.full_name, 'designation', sp.signatory_designation)
                    from inf.staff_profiles sp where sp.status = 'active' and sp.is_signatory order by sp.created_at limit 1),
    'contracts', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'number', c.number, 'status', c.status, 'kind', c.kind) order by c.created_at)
                             from inf.contracts c where c.deal_id = d.id), '[]'))
    into v_out;
  return v_out;
end $$;

-- A new contract (draft) for a deal's terms in force; the first version is added with contract_version_add.
create or replace function inf.contract_create(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare d inf.deals; v_id uuid; v_parent inf.contracts;
begin
  if not inf.has_perm('contract.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from inf.deals where id = (p ->> 'deal_id')::uuid for update;
  if d.id is null or d.current_version_id is null then raise exception 'the deal has no agreed terms' using errcode = '22023'; end if;
  if d.status in ('completed', 'terminated', 'expired') then raise exception 'deal is closed' using errcode = '22023'; end if;
  if nullif(p ->> 'parent_contract_id', '') is not null then
    select * into v_parent from inf.contracts where id = (p ->> 'parent_contract_id')::uuid;
    if v_parent.id is null or v_parent.deal_id <> d.id or v_parent.status <> 'active' then
      raise exception 'only an active contract of this deal can be amended' using errcode = '22023';
    end if;
  end if;
  if nullif(p ->> 'payee_agency_id', '') is not null and not exists (
       select 1 from inf.agency_creator_links l where l.agency_id = (p ->> 'payee_agency_id')::uuid and l.creator_id = d.creator_id
          and l.status = 'active' and l.can_negotiate_sign) then
    raise exception 'that agency cannot be the payee' using errcode = '22023';
  end if;
  insert into inf.contracts (deal_id, template_id, parent_contract_id, kind, payee_agency_id, effective_on, expires_on, stamp_duty_reference)
  values (d.id, (p ->> 'template_id')::uuid, v_parent.id,
          case when v_parent.id is not null then 'amendment' else coalesce(nullif(p ->> 'kind', ''), 'original') end,
          nullif(p ->> 'payee_agency_id', '')::uuid, coalesce(nullif(p ->> 'effective_on', '')::date, d.starts_on),
          coalesce(nullif(p ->> 'expires_on', '')::date, d.ends_on), nullif(trim(p ->> 'stamp_duty_reference'), ''))
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'this deal already has an open contract' using errcode = '23505';
end $$;

-- Adds a version (content and HTML assembled by the app). The database hashes the HTML. With p_resolve, the listed
-- change requests are closed as accepted or countered in this version.
create or replace function inf.contract_version_add(p_contract uuid, p_content jsonb, p_html text, p_overrides jsonb,
                                                    p_note text default null, p_resolve jsonb default '[]'::jsonb)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; d inf.deals; v_id uuid; v_item jsonb;
begin
  if not inf.has_perm('contract.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract for update;
  if c.id is null then raise exception 'no such contract' using errcode = '22023'; end if;
  if c.status not in ('draft', 'sent', 'in_negotiation', 'ready_to_sign') then
    raise exception 'a signed or closed contract cannot change' using errcode = '22023';
  end if;
  select * into d from inf.deals where id = c.deal_id;
  insert into inf.contract_versions (contract_id, version, deal_version_id, content, html, sha256, overrides, note)
  values (c.id, coalesce((select max(version) from inf.contract_versions where contract_id = c.id), 0) + 1, d.current_version_id,
          p_content, p_html, encode(sha256(convert_to(p_html, 'UTF8')), 'hex'), coalesce(p_overrides, '{}'::jsonb), nullif(trim(p_note), ''))
  returning id into v_id;
  for v_item in select * from jsonb_array_elements(coalesce(p_resolve, '[]'::jsonb)) loop
    update inf.contract_change_requests set status = v_item ->> 'status', decided_by = auth.uid(), decided_at = now(),
           decision_note = nullif(trim(v_item ->> 'note'), ''), resolved_in_version_id = v_id
     where id = (v_item ->> 'id')::uuid and contract_id = c.id and status = 'pending' and v_item ->> 'status' in ('accepted', 'countered');
    if not found then raise exception 'change request is not pending' using errcode = '22023'; end if;
  end loop;
  update inf.contracts set current_version_id = v_id,
         status = case when status in ('sent', 'ready_to_sign') then 'in_negotiation' else status end
   where id = c.id;
  if c.status <> 'draft' then
    perform inf.contract_notify(c.id, 'creator', 'contract.updated', 'Contract updated: ' || c.number,
                                'A new version of your contract is ready to review.');
  end if;
  return v_id;
end $$;

-- Send to the creator. With the legal-review gate on, every clause in the version must be reviewed.
create or replace function inf.contract_send(p_contract uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; v inf.contract_versions; v_gate boolean; v_unreviewed int; v_days int;
begin
  if not inf.has_perm('contract.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract for update;
  if c.status <> 'draft' then raise exception 'only a draft can be sent' using errcode = '22023'; end if;
  select * into v from inf.contract_versions where id = c.current_version_id;
  if v.id is null then raise exception 'the contract has no content yet' using errcode = '22023'; end if;
  v_gate := coalesce((inf.setting('contracts.signing') ->> 'legal_review_gate')::boolean, true);
  select count(*) into v_unreviewed
    from jsonb_array_elements(v.content -> 'sections') s
    join inf.clause_versions cv on cv.clause_id = (s ->> 'clause_id')::uuid and cv.version = (s ->> 'clause_version')::int
   where cv.reviewed_at is null and not coalesce((s ->> 'amended')::boolean, false);
  if v_gate and v_unreviewed > 0 then
    raise exception 'contains % clauses not yet legally reviewed', v_unreviewed using errcode = '22023';
  end if;
  v_days := coalesce((inf.setting('contracts.signing') ->> 'negotiation_deadline_days')::int, 7);
  update inf.contracts set status = 'sent', sent_at = now(), negotiation_deadline = now() + make_interval(days => v_days) where id = c.id;
  perform inf.contract_notify(c.id, 'creator', 'contract.sent', 'Contract to review: ' || c.number,
                              'Please review your contract. You can comment, suggest changes to negotiable clauses, or sign when it is ready.');
end $$;

create or replace function inf.contract_set_ready(p_contract uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts;
begin
  if not inf.has_perm('contract.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract for update;
  if c.status not in ('sent', 'in_negotiation') then raise exception 'cannot mark this contract ready' using errcode = '22023'; end if;
  if exists (select 1 from inf.contract_change_requests where contract_id = c.id and status = 'pending') then
    raise exception 'answer every pending change request first' using errcode = '22023';
  end if;
  update inf.contracts set status = 'ready_to_sign' where id = c.id;
  perform inf.contract_notify(c.id, 'creator', 'contract.ready', 'Ready to sign: ' || c.number,
                              'Your contract is final and ready for your signature.');
end $$;

create or replace function inf.contract_set_status(p_contract uuid, p_status text, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; v_ok boolean;
begin
  if not inf.has_perm('contract.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract for update;
  if c.id is null then raise exception 'no such contract' using errcode = '22023'; end if;
  v_ok := case
    when p_status = 'void' then c.status in ('draft', 'sent', 'in_negotiation', 'ready_to_sign', 'signed_by_creator')
    when p_status in ('terminated', 'completed') then c.status = 'active'
    else false end;
  if not v_ok then raise exception 'cannot move a % contract to %', c.status, p_status using errcode = '22023'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.contracts set status = p_status, status_reason = trim(p_reason), closed_at = now() where id = c.id;
  update inf.contract_change_requests set status = 'withdrawn' where contract_id = c.id and status = 'pending';
  perform inf.contract_notify(c.id, 'all', 'contract.' || p_status, 'Contract ' || c.number || ': ' || replace(p_status, '_', ' '), trim(p_reason));
end $$;

create or replace function inf.change_request_decide(p_request uuid, p_status text, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare r inf.contract_change_requests;
begin
  if not inf.has_perm('contract.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status <> 'rejected' then raise exception 'accept or counter by saving a new version' using errcode = '22023'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.contract_change_requests set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = trim(p_note)
   where id = p_request and status = 'pending'
  returning * into r;
  if r.id is null then raise exception 'change request is not pending' using errcode = '22023'; end if;
  perform inf.contract_notify(r.contract_id, 'creator', 'contract.change_rejected', 'Change request declined', trim(p_note));
end $$;

-- A structured compensation counter-offer accepted by Eduwit: the deal's terms are replaced (before signing) by a new
-- accepted version; the app then regenerates the contract from it.
create or replace function inf.deal_version_from_counter(p_request uuid, p_config jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare r inf.contract_change_requests; c inf.contracts; d inf.deals; cur inf.deal_versions; v_id uuid;
begin
  if not (inf.has_perm('contract.write') and inf.has_perm('deal.write')) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into r from inf.contract_change_requests where id = p_request and status = 'pending' and kind = 'compensation';
  if r.id is null then raise exception 'change request is not pending' using errcode = '22023'; end if;
  select * into c from inf.contracts where id = r.contract_id;
  if c.status not in ('sent', 'in_negotiation', 'ready_to_sign') then raise exception 'a signed or closed contract cannot change' using errcode = '22023'; end if;
  select * into d from inf.deals where id = c.deal_id for update;
  select * into cur from inf.deal_versions where id = d.current_version_id;
  if not inf.comp_config_valid(p_config) then raise exception 'invalid compensation config' using errcode = '22023'; end if;
  insert into inf.deal_versions (deal_id, version, comp_config, config_hash, origin, preset_id, effective_from, note, state, decided_by, decided_at)
  values (d.id, (select max(version) from inf.deal_versions where deal_id = d.id) + 1, p_config, inf.config_hash(p_config), 'counter_offer',
          cur.preset_id, cur.effective_from, 'Counter-offer agreed in contract ' || c.number, 'accepted', auth.uid(), now())
  returning id into v_id;
  update inf.deal_versions set state = 'superseded' where id = cur.id;
  update inf.deals set current_version_id = v_id, deal_model = inf.deal_model(p_config) where id = d.id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Negotiation (creator / agency; staff may comment too)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.contract_comment_add(p_contract uuid, p_clause text, p_body text, p_parent uuid default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; v_side text := inf.contract_side(p_contract); v_id uuid;
begin
  if v_side is null or (v_side = 'eduwit' and not inf.has_perm('contract.write')) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract;
  if c.status not in ('sent', 'in_negotiation', 'ready_to_sign') then raise exception 'comments are closed' using errcode = '22023'; end if;
  if not exists (select 1 from inf.contract_versions v, jsonb_array_elements(v.content -> 'sections') s
                  where v.id = c.current_version_id and s ->> 'key' = p_clause) then
    raise exception 'no such clause' using errcode = '22023';
  end if;
  insert into inf.contract_comments (contract_id, version_id, clause_key, parent_id, author_side, body)
  values (c.id, c.current_version_id, p_clause, p_parent, v_side, trim(p_body))
  returning id into v_id;
  if v_side <> 'eduwit' then
    update inf.contracts set status = 'in_negotiation' where id = c.id and status = 'sent';
    perform inf.contract_notify(c.id, 'eduwit', 'contract.comment', 'New comment on ' || c.number, left(trim(p_body), 200));
  else
    perform inf.contract_notify(c.id, 'creator', 'contract.comment', 'Eduwit replied on ' || c.number, left(trim(p_body), 200));
  end if;
  return v_id;
end $$;

create or replace function inf.contract_comment_resolve(p_comment uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare cm inf.contract_comments;
begin
  select * into cm from inf.contract_comments where id = p_comment;
  if cm.id is null or inf.contract_side(cm.contract_id) is null then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.contract_comments set resolved_at = now(), resolved_by = auth.uid() where id = p_comment and resolved_at is null;
end $$;

-- Suggested wording for a negotiable clause, or a structured compensation counter-offer.
create or replace function inf.change_request_create(p_contract uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; v_side text := inf.contract_side(p_contract); v_id uuid; v_section jsonb;
begin
  if v_side not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract for update;
  if c.status not in ('sent', 'in_negotiation', 'ready_to_sign') then raise exception 'negotiation is closed' using errcode = '22023'; end if;
  if p ->> 'kind' = 'clause' then
    select s into v_section from inf.contract_versions v, jsonb_array_elements(v.content -> 'sections') s
     where v.id = c.current_version_id and s ->> 'key' = p ->> 'clause_key';
    if v_section is null then raise exception 'no such clause' using errcode = '22023'; end if;
    if not coalesce((v_section ->> 'negotiable')::boolean, false) or coalesce((v_section ->> 'locked')::boolean, false) then
      raise exception 'this clause is not negotiable' using errcode = '22023';
    end if;
  elsif p ->> 'kind' <> 'compensation' then
    raise exception 'invalid change request' using errcode = '22023';
  end if;
  if exists (select 1 from inf.contract_change_requests where contract_id = c.id and status = 'pending'
              and kind = p ->> 'kind' and coalesce(clause_key, '') = coalesce(p ->> 'clause_key', '')) then
    raise exception 'a request for this is already pending' using errcode = '22023';
  end if;
  insert into inf.contract_change_requests (contract_id, version_id, kind, clause_key, proposed_body, proposed_terms, note, from_side)
  values (c.id, c.current_version_id, p ->> 'kind', nullif(p ->> 'clause_key', ''), p -> 'proposed_body', p -> 'proposed_terms',
          nullif(trim(p ->> 'note'), ''), v_side)
  returning id into v_id;
  update inf.contracts set status = 'in_negotiation' where id = c.id and status in ('sent', 'ready_to_sign');
  perform inf.contract_notify(c.id, 'eduwit', 'contract.change_requested', 'Change requested on ' || c.number,
                              case when p ->> 'kind' = 'clause' then 'Suggested wording for a clause.' else 'A compensation counter-offer.' end);
  return v_id;
end $$;

create or replace function inf.change_request_withdraw(p_request uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r inf.contract_change_requests;
begin
  select * into r from inf.contract_change_requests where id = p_request;
  if r.id is null or inf.contract_side(r.contract_id) not in ('creator', 'agency') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.contract_change_requests set status = 'withdrawn' where id = p_request and status = 'pending';
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.contract_detail(p_contract uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c inf.contracts; d inf.deals; v_side text := inf.contract_side(p_contract); v inf.contract_versions; v_me uuid := auth.uid();
begin
  if v_side is null then return null; end if;
  select * into c from inf.contracts where id = p_contract;
  if v_side <> 'eduwit' and c.status = 'draft' then return null; end if;
  select * into d from inf.deals where id = c.deal_id;
  select * into v from inf.contract_versions where id = c.current_version_id;
  return jsonb_build_object(
    'id', c.id, 'number', c.number, 'kind', c.kind, 'status', c.status, 'deal_id', c.deal_id, 'template_id', c.template_id,
    'parent', (select jsonb_build_object('id', p.id, 'number', p.number) from inf.contracts p where p.id = c.parent_contract_id),
    'effective_on', c.effective_on, 'expires_on', c.expires_on, 'stamp_duty_reference', c.stamp_duty_reference,
    'negotiation_deadline', c.negotiation_deadline, 'sent_at', c.sent_at, 'creator_signed_at', c.creator_signed_at,
    'countersigned_at', c.countersigned_at, 'closed_at', c.closed_at, 'status_reason', c.status_reason,
    'integrity_failed_at', c.integrity_failed_at, 'payee_agency_id', c.payee_agency_id,
    'deal', jsonb_build_object('id', d.id, 'code', d.code, 'title', d.title, 'status', d.status, 'current_version_id', d.current_version_id),
    'creator', (select jsonb_build_object('id', cr.id, 'display_name', cr.display_name, 'handle', cr.handle) from inf.creators cr where cr.id = d.creator_id),
    'side', v_side,
    'current', case when v.id is null then null else jsonb_build_object('id', v.id, 'version', v.version, 'content', v.content,
                    'sha256', v.sha256, 'created_at', v.created_at, 'note', v.note, 'deal_version_id', v.deal_version_id) end,
    'versions', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'version', x.version, 'sha256', x.sha256, 'created_at', x.created_at,
                                                              'note', x.note) order by x.version)
                            from inf.contract_versions x where x.contract_id = c.id), '[]'),
    'comments', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'clause_key', m.clause_key, 'parent_id', m.parent_id,
                                                              'author_side', m.author_side, 'body', m.body, 'created_at', m.created_at,
                                                              'resolved', m.resolved_at is not null, 'mine', m.author_id = v_me) order by m.created_at)
                            from inf.contract_comments m where m.contract_id = c.id), '[]'),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'clause_key', r.clause_key,
                                                              'proposed_body', r.proposed_body, 'proposed_terms', r.proposed_terms, 'note', r.note,
                                                              'from_side', r.from_side, 'status', r.status, 'created_at', r.created_at,
                                                              'decided_at', r.decided_at, 'decision_note', r.decision_note,
                                                              'resolved_in_version_id', r.resolved_in_version_id, 'version_id', r.version_id)
                                           order by r.created_at)
                            from inf.contract_change_requests r where r.contract_id = c.id), '[]'),
    'signatures', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'version_id', s.version_id, 'signer_role', s.signer_role,
                                                                'signer_name', s.signer_name, 'signer_designation', s.signer_designation,
                                                                'document_sha256', s.document_sha256, 'signed_at', s.signed_at,
                                                                'signed_at_ist', s.signed_at_ist, 'otp_channel', s.otp_channel)
                                             order by s.signed_at)
                              from inf.signatures s where s.contract_id = c.id), '[]'),
    'file', (select jsonb_build_object('id', f.id, 'sha256', f.sha256, 'created_at', f.created_at) from inf.contract_files f
              where f.contract_id = c.id and f.version_id = c.current_version_id),
    'can_write', v_side = 'eduwit' and inf.has_perm('contract.write'),
    'can_countersign', v_side = 'eduwit' and inf.has_perm('contract.countersign'),
    'consent', (select jsonb_build_object('version', t.version, 'body', t.body) from inf.consent_texts t order by t.version desc limit 1));
end $$;

-- The current version's HTML (for viewing and the PDF), for anyone who may open the contract.
create or replace function inf.contract_version_html(p_version uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'version', v.version, 'html', v.html, 'sha256', v.sha256, 'content', v.content,
                            'computed_sha256', encode(sha256(convert_to(v.html, 'UTF8')), 'hex'))
    from inf.contract_versions v join inf.contracts c on c.id = v.contract_id
   where v.id = p_version and inf.contract_side(c.id) is not null and (c.status <> 'draft' or inf.has_perm('contract.read'));
$$;

create or replace function inf.contracts_list(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_page int := greatest(coalesce((p ->> 'page')::int, 1), 1);
  v_size int := least(greatest(coalesce((p ->> 'page_size')::int, 25), 1), 100);
  v_status text[] := case when jsonb_typeof(p -> 'status') = 'array' and jsonb_array_length(p -> 'status') > 0
                          then array(select jsonb_array_elements_text(p -> 'status')) end;
  v_q text := nullif(trim(p ->> 'q'), '');
  v_total int; v_rows jsonb;
begin
  if not inf.has_perm('contract.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  with f as (
    select c.*, d.code as deal_code, d.title as deal_title, cr.display_name, cr.handle
      from inf.contracts c join inf.deals d on d.id = c.deal_id join inf.creators cr on cr.id = d.creator_id
     where (v_status is null or c.status = any (v_status))
       and (nullif(p ->> 'deal_id', '') is null or c.deal_id = (p ->> 'deal_id')::uuid)
       and (v_q is null or c.number ilike '%' || v_q || '%' or d.title ilike '%' || v_q || '%' or cr.display_name ilike '%' || v_q || '%'))
  select (select count(*) from f),
         coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'number', x.number, 'kind', x.kind, 'status', x.status,
                                                       'deal_id', x.deal_id, 'deal_code', x.deal_code, 'deal_title', x.deal_title,
                                                       'creator_name', x.display_name, 'handle', x.handle, 'updated_at', x.updated_at,
                                                       'pending_requests', (select count(*) from inf.contract_change_requests r
                                                                             where r.contract_id = x.id and r.status = 'pending'))
                                    order by x.updated_at desc)
                     from (select * from f order by updated_at desc offset (v_page - 1) * v_size limit v_size) x), '[]')
    into v_total, v_rows;
  return jsonb_build_object('total', v_total, 'page', v_page, 'page_size', v_size, 'rows', v_rows);
end $$;

create or replace function inf.my_contracts(p_creator uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'number', c.number, 'kind', c.kind, 'status', c.status,
                                               'deal_id', d.id, 'deal_title', d.title, 'updated_at', c.updated_at,
                                               'needs_action', c.status in ('sent', 'in_negotiation', 'ready_to_sign'))
                            order by c.updated_at desc), '[]')
    from inf.contracts c join inf.deals d on d.id = c.deal_id
   where d.creator_id = p_creator and c.status <> 'draft'
     and (coalesce(p_creator = inf.current_creator_id(), false) or inf.agency_can(p_creator, 'negotiate'));
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Signing (service role only: the app authenticated the person and passes their id, IP and user agent)
-- ---------------------------------------------------------------------------------------------------------------
-- Which signature p_user may give on the contract's current version now: 'creator' (the creator or their agency with
-- the negotiate grant), 'signatory' (an active Authorised Signatory), or null.
create or replace function inf.contract_signer_role(p_contract uuid, p_user uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when c.status = 'ready_to_sign' and (
           exists (select 1 from inf.creator_accounts a join inf.creators cr on cr.id = a.creator_id
                    where a.user_id = p_user and a.creator_id = d.creator_id and not cr.is_blocked and cr.status not in ('blocked', 'archived'))
        or exists (select 1 from inf.agency_members m join inf.agency_creator_links l on l.agency_id = m.agency_id
                    join inf.agencies ag on ag.id = m.agency_id
                    where m.user_id = p_user and m.status = 'active' and ag.status = 'active' and l.creator_id = d.creator_id
                      and l.status = 'active' and l.can_negotiate_sign)) then 'creator'
    when c.status = 'signed_by_creator' and exists (select 1 from inf.staff_profiles sp where sp.user_id = p_user and sp.status = 'active' and sp.is_signatory)
      then 'signatory'
    end
    from inf.contracts c join inf.deals d on d.id = c.deal_id
   where c.id = p_contract and coalesce(auth.role(), '') = 'service_role';
$$;

create or replace function inf.contract_sign_code_issue(p_contract uuid, p_user uuid, p_channel text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c inf.contracts; v_role text := inf.contract_signer_role(p_contract, p_user); v_code text;
  v_salt text := encode(extensions.gen_random_bytes(16), 'hex'); v_set jsonb := inf.setting('contracts.signing'); v_last timestamptz;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_role is null then return jsonb_build_object('ok', false, 'error', 'cannot_sign'); end if;
  if not (p_channel in (select jsonb_array_elements_text(v_set -> 'otp_channels'))) then
    return jsonb_build_object('ok', false, 'error', 'channel');
  end if;
  select created_at into v_last from inf.contract_sign_codes where user_id = p_user and contract_id = p_contract order by created_at desc limit 1;
  if v_last > now() - make_interval(secs => coalesce((v_set ->> 'otp_resend_cooldown_seconds')::int, 60)) then
    return jsonb_build_object('ok', false, 'error', 'cooldown');
  end if;
  if (select count(*) from inf.contract_sign_codes where user_id = p_user and created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('ok', false, 'error', 'too_many_codes');
  end if;
  select * into c from inf.contracts where id = p_contract;
  update inf.contract_sign_codes set consumed_at = now() where user_id = p_user and contract_id = p_contract and consumed_at is null;
  v_code := lpad((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000)::text, 6, '0');
  insert into inf.contract_sign_codes (contract_id, version_id, user_id, role, channel, code_hash, salt, expires_at)
  values (c.id, c.current_version_id, p_user, v_role, p_channel, inf.code_hash(v_code, v_salt, p_user), v_salt,
          now() + make_interval(mins => coalesce((v_set ->> 'otp_expiry_minutes')::int, 10)));
  return jsonb_build_object('ok', true, 'code', v_code, 'role', v_role, 'number', c.number,
                            'expires_in_seconds', coalesce((v_set ->> 'otp_expiry_minutes')::int, 10) * 60);
end $$;

-- Verifies the code and records the signature. p_version and p_sha256 are what the signer was shown: if the contract
-- changed since, the signature is refused.
create or replace function inf.contract_sign(p_contract uuid, p_user uuid, p_version uuid, p_sha256 text, p_name text,
                                             p_consent_version int, p_code text, p_ip text, p_user_agent text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c inf.contracts; v inf.contract_versions; d inf.deals; k inf.contract_sign_codes; v_role text; v_signer_role text;
  v_max int := coalesce((inf.setting('contracts.signing') ->> 'otp_max_attempts')::int, 5); v_consent inf.consent_texts;
  v_designation text; v_sig uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.contracts where id = p_contract for update;
  v_role := inf.contract_signer_role(p_contract, p_user);
  if v_role is null then return jsonb_build_object('ok', false, 'error', 'cannot_sign'); end if;
  select * into v from inf.contract_versions where id = c.current_version_id;
  if v.id <> p_version or v.sha256 <> p_sha256 or encode(sha256(convert_to(v.html, 'UTF8')), 'hex') <> v.sha256 then
    return jsonb_build_object('ok', false, 'error', 'changed');
  end if;
  select * into v_consent from inf.consent_texts where version = p_consent_version;
  if v_consent.version is null or v_consent.version <> (select max(version) from inf.consent_texts) then
    return jsonb_build_object('ok', false, 'error', 'consent');
  end if;
  if char_length(trim(coalesce(p_name, ''))) < 2 then return jsonb_build_object('ok', false, 'error', 'name'); end if;
  select * into k from inf.contract_sign_codes
   where user_id = p_user and contract_id = c.id and consumed_at is null and expires_at > now()
   order by created_at desc limit 1 for update;
  if k.id is null then return jsonb_build_object('ok', false, 'error', 'expired'); end if;
  if k.version_id <> v.id or k.role <> v_role then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  if k.attempts >= v_max then return jsonb_build_object('ok', false, 'error', 'too_many_attempts'); end if;
  if k.code_hash <> inf.code_hash(coalesce(p_code, ''), k.salt, p_user) then
    update inf.contract_sign_codes set attempts = attempts + 1, consumed_at = case when attempts + 1 >= v_max then now() end where id = k.id;
    return jsonb_build_object('ok', false, 'error', 'wrong_code', 'attempts_left', greatest(v_max - k.attempts - 1, 0));
  end if;
  update inf.contract_sign_codes set consumed_at = now() where id = k.id;
  select * into d from inf.deals where id = c.deal_id;
  v_signer_role := case when v_role = 'signatory' then 'signatory'
                        when exists (select 1 from inf.creator_accounts a where a.user_id = p_user and a.creator_id = d.creator_id) then 'creator'
                        else 'agency' end;
  if v_role = 'signatory' then
    select signatory_designation into v_designation from inf.staff_profiles where user_id = p_user;
  end if;
  insert into inf.signatures (contract_id, version_id, signer_user_id, signer_role, signer_name, signer_designation, document_sha256,
                              consent_version, consent_text, otp_channel, otp_reference, ip, user_agent)
  values (c.id, v.id, p_user, v_signer_role, trim(p_name), v_designation, v.sha256, v_consent.version, v_consent.body, k.channel, k.id,
          case when p_ip ~ '^[0-9a-fA-F:.]{3,45}$' then p_ip::inet end, left(p_user_agent, 500))
  returning id into v_sig;
  if v_role = 'creator' then
    update inf.contracts set status = 'signed_by_creator', creator_signed_at = now() where id = c.id;
    perform inf.contract_notify(c.id, 'signatory', 'contract.awaiting_countersign', 'Countersign: ' || c.number,
                                'The creator has signed. Please countersign for Eduwit.');
    perform inf.contract_notify(c.id, 'eduwit', 'contract.creator_signed', 'Creator signed ' || c.number, 'Waiting for the Authorised Signatory.');
  else
    update inf.contracts set status = 'active', countersigned_at = now() where id = c.id;
    -- The parent of an amendment is replaced by it.
    update inf.contracts set status = 'superseded', closed_at = now(), status_reason = 'Superseded by ' || c.number
     where id = c.parent_contract_id and status = 'active';
    update inf.deal_versions set is_signed = true where id = v.deal_version_id;
    update inf.deals set status = 'active', activated_at = coalesce(activated_at, now()), status_reason = 'Contract ' || c.number || ' countersigned'
     where id = d.id and status = 'agreed';
    perform inf.emit_event('contract.countersigned', 'contract', c.id::text, jsonb_build_object('version_id', v.id, 'sha256', v.sha256),
                           'contract_countersigned:' || c.id);
    perform inf.job_enqueue('contract.finalize', jsonb_build_object('contract_id', c.id), now(), 'contract_finalize:' || c.id);
    perform inf.contract_notify(c.id, 'all', 'contract.active', 'Contract signed: ' || c.number,
                                'Both parties have signed. The signed PDF with its signature certificate is attached to the contract.');
  end if;
  return jsonb_build_object('ok', true, 'signature_id', v_sig, 'role', v_signer_role);
end $$;

-- The final PDF (job contract.finalize, service role) and the download check.
create or replace function inf.contract_file_record(p_contract uuid, p_version uuid, p_path text, p_sha256 text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into inf.contract_files (contract_id, version_id, storage_path, sha256) values (p_contract, p_version, p_path, p_sha256)
  on conflict (version_id, kind) do nothing;
end $$;

-- What the download route needs to re-verify a signed contract: the stored HTML hash, the hash every signature
-- recorded, and the stored PDF's path and hash. Flags the contract when anything disagrees.
create or replace function inf.contract_integrity(p_contract uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c inf.contracts; v inf.contract_versions; f inf.contract_files; v_ok boolean; v_sigs int; v_bad int;
begin
  if inf.contract_side(p_contract) is null and coalesce(auth.role(), '') <> 'service_role' then return null; end if;
  select * into c from inf.contracts where id = p_contract;
  select * into v from inf.contract_versions where id = c.current_version_id;
  select * into f from inf.contract_files where version_id = v.id and kind = 'signed_pdf';
  select count(*), count(*) filter (where s.document_sha256 <> v.sha256 or s.version_id <> v.id)
    into v_sigs, v_bad from inf.signatures s where s.contract_id = c.id and s.version_id = v.id;
  v_ok := encode(sha256(convert_to(v.html, 'UTF8')), 'hex') = v.sha256 and v_bad = 0
          and (c.status not in ('active', 'completed', 'terminated', 'superseded') or v_sigs >= 2);
  if not v_ok and c.integrity_failed_at is null then
    update inf.contracts set integrity_failed_at = now() where id = c.id;
    perform inf.emit_event('contract.integrity_failed', 'contract', c.id::text, jsonb_build_object('version_id', v.id), 'contract_integrity:' || c.id);
  end if;
  return jsonb_build_object('ok', v_ok, 'version_id', v.id, 'sha256', v.sha256, 'signatures', v_sigs,
                            'file_path', f.storage_path, 'file_sha256', f.sha256, 'number', c.number, 'status', c.status);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Reminders (nightly): open negotiations near their deadline, and active contracts nearing expiry (30/15/7 days).
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.contracts_remind() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; v_set jsonb := inf.setting('contracts.signing'); v_n int := 0; v_days int;
begin
  for r in
    select c.id, c.number, c.negotiation_deadline, c.expires_on, c.status from inf.contracts c
     where c.status in ('sent', 'in_negotiation', 'ready_to_sign', 'signed_by_creator', 'active')
  loop
    if r.status <> 'active' and r.negotiation_deadline is not null then
      v_days := ceil(extract(epoch from (r.negotiation_deadline - now())) / 86400)::int;
      if v_days in (select (x)::int from jsonb_array_elements_text(v_set -> 'negotiation_reminder_days') x) or v_days = 0 then
        perform inf.contract_notify(r.id, case when r.status = 'signed_by_creator' then 'signatory' else 'all' end,
                                    'contract.reminder', 'Reminder: ' || r.number,
                                    case when r.status = 'signed_by_creator' then 'Waiting for the countersignature.'
                                         else 'This contract is still open. Please review or sign it.' end);
        v_n := v_n + 1;
      end if;
    elsif r.status = 'active' and r.expires_on is not null then
      v_days := r.expires_on - (now() at time zone 'Asia/Kolkata')::date;
      if v_days in (select (x)::int from jsonb_array_elements_text(v_set -> 'expiry_reminder_days') x) then
        perform inf.contract_notify(r.id, 'all', 'contract.expiring', r.number || ' expires in ' || v_days || ' days',
                                    'Renew the deal or let it end on its expiry date.');
        v_n := v_n + 1;
      elsif v_days < 0 then
        update inf.contracts set status = 'expired', closed_at = now(), status_reason = 'Expiry date passed' where id = r.id;
      end if;
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
end $$;

-- Renewal: a new draft deal with the same terms and new dates (its contract is generated as kind 'renewal').
create or replace function inf.deal_renew(p_deal uuid, p_starts_on date, p_ends_on date) returns uuid
language plpgsql security definer set search_path = '' as $$
declare d inf.deals; v_cfg jsonb; v_id uuid;
begin
  if not inf.has_perm('deal.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into d from inf.deals where id = p_deal;
  if d.id is null or d.status not in ('active', 'completed', 'expired') then raise exception 'only active or ended deals can be renewed' using errcode = '22023'; end if;
  if p_ends_on is not null and p_ends_on < p_starts_on then raise exception 'end before start' using errcode = '22023'; end if;
  select comp_config into v_cfg from inf.deal_versions where id = d.current_version_id;
  insert into inf.deals (creator_id, campaign_id, title, starts_on, ends_on, draft_config, preset_id, deal_model, owner_id, internal_notes)
  values (d.creator_id, d.campaign_id, left('Renewal: ' || d.title, 120), p_starts_on, p_ends_on, v_cfg, d.preset_id, d.deal_model,
          coalesce(d.owner_id, auth.uid()), 'Renewal of ' || d.code)
  returning id into v_id;
  perform inf.audit('deal', v_id::text, 'renewal_of', null, jsonb_build_object('deal_id', d.id, 'code', d.code));
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Storage: signed PDFs are written by the service role only; nobody reads the bucket directly (downloads go through
-- the app route, which re-verifies the hashes).
-- ---------------------------------------------------------------------------------------------------------------

-- ---------------------------------------------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.clauses enable row level security;
alter table inf.clause_versions enable row level security;
alter table inf.contract_templates enable row level security;
alter table inf.template_clauses enable row level security;
alter table inf.consent_texts enable row level security;
alter table inf.contracts enable row level security;
alter table inf.contract_versions enable row level security;
alter table inf.contract_comments enable row level security;
alter table inf.contract_change_requests enable row level security;
alter table inf.contract_sign_codes enable row level security;
alter table inf.signatures enable row level security;
alter table inf.contract_files enable row level security;

create policy clauses_staff_read on inf.clauses for select to authenticated using ((select inf.has_perm('contract.read')) or (select inf.has_perm('clause.write')));
create policy clause_versions_staff_read on inf.clause_versions for select to authenticated using ((select inf.has_perm('contract.read')) or (select inf.has_perm('clause.write')));
create policy contract_templates_staff_read on inf.contract_templates for select to authenticated using ((select inf.has_perm('contract.read')) or (select inf.has_perm('clause.write')));
create policy template_clauses_staff_read on inf.template_clauses for select to authenticated using ((select inf.has_perm('contract.read')) or (select inf.has_perm('clause.write')));
create policy consent_texts_read on inf.consent_texts for select to authenticated using (true);
create policy contracts_staff_read on inf.contracts for select to authenticated using ((select inf.has_perm('contract.read')));
create policy contract_versions_staff_read on inf.contract_versions for select to authenticated using ((select inf.has_perm('contract.read')));
create policy signatures_staff_read on inf.signatures for select to authenticated using ((select inf.has_perm('contract.read')));
create policy contract_files_staff_read on inf.contract_files for select to authenticated using ((select inf.has_perm('contract.read')));
-- contract_comments, contract_change_requests: through contract_detail(); contract_sign_codes: no client access.

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.clauses', 'authenticated', 'select'),
  ('table', 'inf.clause_versions', 'authenticated', 'select'),
  ('table', 'inf.contract_templates', 'authenticated', 'select'),
  ('table', 'inf.template_clauses', 'authenticated', 'select'),
  ('table', 'inf.consent_texts', 'authenticated', 'select'),
  ('table', 'inf.contracts', 'authenticated', 'select'),
  ('table', 'inf.contract_versions', 'authenticated', 'select'),
  ('table', 'inf.signatures', 'authenticated', 'select'),
  ('table', 'inf.contract_files', 'authenticated', 'select'),
  ('function', 'inf.contract_side(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.clause_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.clause_mark_reviewed(uuid, integer)', 'authenticated', 'execute'),
  ('function', 'inf.clause_archive(uuid, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.template_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.template_archive(uuid, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.template_source(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.clause_library(boolean)', 'authenticated', 'execute'),
  ('function', 'inf.clause_history(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.contract_source(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.contract_create(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.contract_version_add(uuid, jsonb, text, jsonb, text, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.contract_send(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.contract_set_ready(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.contract_set_status(uuid, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.change_request_decide(uuid, text, text)', 'authenticated', 'execute'),
  ('function', 'inf.deal_version_from_counter(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.contract_comment_add(uuid, text, text, uuid)', 'authenticated', 'execute'),
  ('function', 'inf.contract_comment_resolve(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.change_request_create(uuid, jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.change_request_withdraw(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.contract_detail(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.contract_version_html(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.contracts_list(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.my_contracts(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.contract_integrity(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.deal_renew(uuid, date, date)', 'authenticated', 'execute');
call inf.apply_client_grants();
