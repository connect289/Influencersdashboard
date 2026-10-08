-- M31h: Addendum 3 at intake (rulebook PART 1 'every lead', PART 4 'Several interests', PART 7.1 consent wording; design
-- m31h, D8, D30, D39; contract section 6).
--   lead_interest_add / lead_interests_apply / lead_interests_save   secondary interests in b2b.lead_interests (positions 2-10)
--   consent_ledger_record                                            one b2b.lead_consents 'given' row per purpose, with the text version
--   other_courses_list, opt_bool                                     small parsers (an other_courses value is an array or comma text)
--   consent_text_save                                                Admin: the registered consent wording per channel, lawyer approval
--   intake_lead, meta_lead_apply, intake_tick, lead_form_save, import_fields, import_commit, import_process, intake_manual,
--   api_b2c_lead_update                                              replaced, same signatures (m17c/m17d/m17e/m17f/m22b)
-- Rules: a form with partner_share needs a registered text that covers admission partners (lead_form_save refuses otherwise);
-- an import may 'route now' without partner_share (those students get the R8 request); import rows previewed blocked, or
-- invalid with 10-15 digits, are recorded and go to Not passed through R5 (only rows without a usable phone are skipped);
-- every intake path writes ledger rows and other_courses; the Intake API reports warnings about the consent text version.
-- Nothing here touches public.student_leads' shape: leads are still written only through public.lead_intake().

-- the Meta checkbox -> purpose map of a form lives in lead_forms.settings (design m31h (4): 'the lead_forms settings jsonb')
alter table b2b.lead_forms add column if not exists settings jsonb not null default '{}';

-- ---------- small parsers ----------
/* An other_courses value as a clean list: a JSON array of strings (or objects with course), or text split on , ; | and
   newlines. Trimmed, at most 120 characters each, repeats (case-insensitive) removed, order kept. */
create or replace function b2b.other_courses_list(p jsonb)
returns text[] language sql immutable set search_path = '' as $fn$
  with raw as (
    select case when jsonb_typeof(e.value) = 'object' then e.value ->> 'course'
                when jsonb_typeof(e.value) = 'string' then e.value #>> '{}' end v, e.ord
      from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) with ordinality e(value, ord)
    union all
    select s.v, s.ord
      from regexp_split_to_table(case when jsonb_typeof(p) = 'string' then p #>> '{}' else '' end, '[,;|\n]') with ordinality s(v, ord)
  ), c as (
    select left(trim(regexp_replace(v, '\s+', ' ', 'g')), 120) v, ord from raw where v is not null
  ), d as (
    select distinct on (lower(v)) v, ord from c where v <> '' order by lower(v), ord
  )
  select coalesce((select array_agg(d.v order by d.ord) from d), '{}'::text[]);
$fn$;

/* p ->> k as a boolean: null when absent; 22023 when it is not true/false. */
create or replace function b2b.opt_bool(p jsonb, k text)
returns boolean language plpgsql immutable set search_path = '' as $fn$
begin
  if p is null or not (p ? k) or jsonb_typeof(p -> k) = 'null' then return null; end if;
  if jsonb_typeof(p -> k) = 'boolean' then return (p ->> k)::boolean; end if;
  if lower(trim(p ->> k)) in ('true', '1', 'yes', 'on') then return true; end if;
  if lower(trim(p ->> k)) in ('false', '0', 'no', 'off') then return false; end if;
  raise exception '% must be true or false', k using errcode = '22023';
end $fn$;

-- ---------- secondary interests (D30) ----------
/* Adds one secondary interest. p_interest: a JSON string (the course) or {course, specialization?, level?, mode?, university?}.
   Skips the primary interest and live repeats (same course key or text, same specialization) and returns false; at most
   positions 2..10 (false when full); else inserts position = max live position + 1 and returns true. */
create or replace function b2b.lead_interest_add(p_lead_id bigint, p_interest jsonb, p_source text)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  prim jsonb;
  v_course text;
  v_spec text;
  v_lvl text;
  v_mode text;
  v_uni text;
  v_ck text;
  v_pos int;
  v_ids bigint[] := '{}';
  n int;
begin
  if p_source is null or p_source not in ('witty', 'web_agent', 'api', 'meta', 'google', 'import', 'manual', 'admin', 'b2c', 'backfill') then
    raise exception 'unknown interest source: %', coalesce(p_source, '(none)') using errcode = '22023';
  end if;
  if p_interest is null then return false; end if;
  if jsonb_typeof(p_interest) = 'string' then
    v_course := p_interest #>> '{}';
  elsif jsonb_typeof(p_interest) = 'object' then
    v_course := p_interest ->> 'course'; v_spec := p_interest ->> 'specialization'; v_lvl := p_interest ->> 'level';
    v_mode := p_interest ->> 'mode'; v_uni := p_interest ->> 'university';
  else
    return false;
  end if;
  v_course := left(nullif(trim(regexp_replace(coalesce(v_course, ''), '\s+', ' ', 'g')), ''), 120);
  if v_course is null then return false; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then return false; end if;

  v_ck := b2b.match_course_key(v_course);
  v_spec := case when b2b.norm_key(coalesce(v_spec, '')) in ('', 'general', 'any', 'notsure', 'none', 'na') then null else left(trim(v_spec), 120) end;
  v_uni := nullif(trim(coalesce(v_uni, '')), '');
  -- the primary interest stays derived from the lead row; the same course without a specialization, or with the same
  -- one, is a repeat (a different specialization of the same course is another interest, PART 4 'course + specialization')
  prim := b2b.lead_interest(l);
  if (prim ->> 'course_text') is not null
     and coalesce(prim ->> 'course_key', lower(prim ->> 'course_text')) = coalesce(v_ck, lower(v_course))
     and (v_spec is null or b2b.norm_key(prim ->> 'specialization') = b2b.norm_key(v_spec)) then
    return false;
  end if;
  -- a live repeat (the key the unique index uses, or the same course asked again without a specialization)
  if exists (select 1 from b2b.lead_interests i
              where i.lead_id = l.id and i.removed_at is null
                and coalesce(i.course_key, lower(i.course_text)) = coalesce(v_ck, lower(v_course))
                and (v_spec is null or coalesce(lower(i.specialization), '') = lower(v_spec))) then
    return false;
  end if;
  select coalesce(max(i.position), 1) + 1 into v_pos from b2b.lead_interests i where i.lead_id = l.id and i.removed_at is null;
  if v_pos > 10 then return false; end if;
  if v_uni is not null then v_ids := coalesce(b2b.university_ids(v_uni), '{}'::bigint[]); end if;

  insert into b2b.lead_interests (lead_id, position, course_text, course_key, specialization, level, mode, university_text, university_id, source, created_by)
  values (l.id, v_pos, v_course, v_ck, v_spec, left(nullif(trim(coalesce(v_lvl, '')), ''), 60), left(nullif(trim(coalesce(v_mode, '')), ''), 60),
          left(v_uni, 200), case when cardinality(v_ids) = 1 then v_ids[1] end, p_source, b2b.actor() ->> 'id')
  on conflict do nothing;
  get diagnostics n = row_count;
  return n > 0;
end $fn$;

/* Makes the lead's live secondary interests equal to p_list (strings or {course, …} objects, at most 9, in order): rows left
   out get removed_at, new ones are added through lead_interest_add (which skips the primary interest), positions follow the
   list order. Internal; lead_interests_save (Admin) and api_b2c_lead_update (B2C) call it.
   Returns {added [course…], removed [course…], list (lead_interest_list)}. */
create or replace function b2b.lead_interests_apply(p_lead_id bigint, p_list jsonb, p_source text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  x jsonb;
  v_course text;
  v_spec text;
  v_key text;
  v_keys text[] := '{}';
  v_items jsonb := '[]';
  v_added text[] := '{}';
  v_removed text[] := '{}';
  rr record;
  i int;
begin
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if p_list is null or jsonb_typeof(p_list) <> 'array' then raise exception 'other interests must be a list' using errcode = '22023'; end if;
  if jsonb_array_length(p_list) > 9 then raise exception 'up to 9 other interests' using errcode = '22023'; end if;
  for x in select e from jsonb_array_elements(p_list) e loop
    if jsonb_typeof(x) = 'string' then v_course := x #>> '{}'; v_spec := null;
    elsif jsonb_typeof(x) = 'object' then v_course := x ->> 'course'; v_spec := x ->> 'specialization';
    else raise exception 'each interest is a course name or an object with a course' using errcode = '22023'; end if;
    v_course := left(nullif(trim(regexp_replace(coalesce(v_course, ''), '\s+', ' ', 'g')), ''), 120);
    if v_course is null then raise exception 'each interest needs a course' using errcode = '22023'; end if;
    v_spec := case when b2b.norm_key(coalesce(v_spec, '')) in ('', 'general', 'any', 'notsure', 'none', 'na') then null else left(trim(v_spec), 120) end;
    v_key := coalesce(b2b.match_course_key(v_course), lower(v_course)) || '|' || coalesce(lower(v_spec), '');
    continue when v_key = any (v_keys);
    v_keys := array_append(v_keys, v_key);
    v_items := v_items || jsonb_build_array(case when jsonb_typeof(x) = 'object' then x || jsonb_build_object('course', v_course)
                                                 else jsonb_build_object('course', v_course) end);
  end loop;
  -- rows left out are removed
  for rr in select i2.id, i2.course_text, coalesce(i2.course_key, lower(i2.course_text)) || '|' || coalesce(lower(i2.specialization), '') k
              from b2b.lead_interests i2 where i2.lead_id = l.id and i2.removed_at is null order by i2.position, i2.id loop
    if not (rr.k = any (v_keys)) then
      update b2b.lead_interests set removed_at = now() where id = rr.id;
      v_removed := array_append(v_removed, rr.course_text);
    end if;
  end loop;
  -- new ones are added (the primary interest and live repeats are skipped by lead_interest_add)
  for i in 1 .. coalesce(jsonb_array_length(v_items), 0) loop
    if b2b.lead_interest_add(l.id, v_items -> (i - 1), p_source) then
      v_added := array_append(v_added, v_items -> (i - 1) ->> 'course');
    end if;
  end loop;
  -- positions follow the list order
  for i in 1 .. cardinality(v_keys) loop
    update b2b.lead_interests set position = least(i + 1, 10)
     where lead_id = l.id and removed_at is null
       and coalesce(course_key, lower(course_text)) || '|' || coalesce(lower(specialization), '') = v_keys[i];
  end loop;
  return jsonb_build_object('added', to_jsonb(v_added), 'removed', to_jsonb(v_removed), 'list', b2b.lead_interest_list(l));
end $fn$;

/* Admin: the lead's other interests, replaced whole (reason required). Logs lead.interests_changed; returns lead_interest_list. */
create or replace function b2b.lead_interests_save(p_lead_id bigint, p_list jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare res jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if not exists (select 1 from public.student_leads where id = p_lead_id) then raise exception 'lead not found' using errcode = 'P0002'; end if;
  res := b2b.lead_interests_apply(p_lead_id, p_list, 'admin');
  perform b2b.log_event('lead.interests_changed', p_lead_id, null, null,
                        jsonb_build_object('added', res -> 'added', 'removed', res -> 'removed', 'reason', left(trim(p_reason), 300),
                                           'count', jsonb_array_length(res -> 'list') - 1));
  return res -> 'list';
end $fn$;

-- ---------- the consent ledger (D8) ----------
/* One 'given' ledger row per purpose stamped in p_consent {sales_at, partner_share_at, marketing_at, text_version}, at the
   stamp's time (clamped to now()), under the given text version. Identical rows are not written twice. Returns the number
   of rows written. p_source: a lead_consents.source value. */
create or replace function b2b.consent_ledger_record(p_lead_id bigint, p_consent jsonb, p_source text, p_evidence jsonb default '{}')
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_ver text := nullif(trim(coalesce(p_consent ->> 'text_version', '')), '');
  v_at timestamptz;
  n int := 0;
  rr record;
begin
  if p_lead_id is null or p_consent is null or jsonb_typeof(p_consent) <> 'object' then return 0; end if;
  if p_source is null or p_source not in ('form', 'api', 'import', 'manual', 'witty', 'meta_form', 'google_form', 'b2c_crm', 'admin', 'wa_request', 'backfill') then
    raise exception 'unknown consent source: %', coalesce(p_source, '(none)') using errcode = '22023';
  end if;
  for rr in select * from (values ('sales', p_consent ->> 'sales_at'), ('partner_share', p_consent ->> 'partner_share_at'),
                                  ('marketing', p_consent ->> 'marketing_at')) v(purpose, at_text) loop
    continue when rr.at_text is null;
    v_at := b2b.try_timestamptz(rr.at_text);
    continue when v_at is null;
    v_at := least(v_at, now());
    continue when exists (select 1 from b2b.lead_consents c
                           where c.lead_id = p_lead_id and c.purpose = rr.purpose and c.state = 'given' and c.at = v_at
                             and c.text_version is not distinct from v_ver and c.source = p_source);
    insert into b2b.lead_consents (lead_id, purpose, state, at, text_version, source, evidence, actor)
    values (p_lead_id, rr.purpose, 'given', v_at, v_ver, p_source,
            case when jsonb_typeof(p_evidence) = 'object' then p_evidence else '{}'::jsonb end, b2b.actor());
    n := n + 1;
  end loop;
  return n;
end $fn$;

/* Admin: a registered consent text (PART 7.1). p = {version (pk, 1-80 chars), channel, purposes [sales|partner_share|
   marketing], body, covers_admission_partners, active, lawyer_approved?, approval_note?}; keys left out keep the stored
   value. Approval needs a note of at least 10 characters (and a body); changing the body or the coverage of an approved
   text clears lawyer_approved_at / approved_by (the lawyer checks the new wording). Logs consent_text.saved; returns the row. */
create or replace function b2b.consent_text_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cur b2b.consent_texts;
  r b2b.consent_texts;
  v_version text := nullif(trim(coalesce(p ->> 'version', '')), '');
  v_channel text;
  v_purposes text[];
  v_body text;
  v_covers boolean;
  v_active boolean;
  v_approve boolean;
  v_note text;
  v_by text;
  v_clear boolean := false;
  v_changed text[] := '{}';
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'the consent text must be an object' using errcode = '22023'; end if;
  if v_version is null or length(v_version) > 80 or v_version ~ '[[:cntrl:]]' then
    raise exception 'a version id of 1 to 80 characters is required' using errcode = '22023';
  end if;
  select * into cur from b2b.consent_texts where version = v_version for update;

  v_channel := coalesce(nullif(trim(coalesce(p ->> 'channel', '')), ''), cur.channel);
  if v_channel is null or v_channel not in ('witty', 'website_agent', 'web_form', 'meta_form', 'google_form', 'import', 'manual', 'api', 'wa_request') then
    raise exception 'unknown consent channel: %', coalesce(v_channel, '(none)') using errcode = '22023';
  end if;
  if p ? 'purposes' then
    if jsonb_typeof(p -> 'purposes') <> 'array' then raise exception 'purposes must be a list' using errcode = '22023'; end if;
    v_purposes := array(select distinct x from jsonb_array_elements_text(p -> 'purposes') x order by x);
    if cardinality(v_purposes) = 0 or exists (select 1 from unnest(v_purposes) x where x not in ('sales', 'partner_share', 'marketing')) then
      raise exception 'purposes are sales, partner_share and marketing' using errcode = '22023';
    end if;
  else
    v_purposes := cur.purposes;
  end if;
  if v_purposes is null then raise exception 'say which purposes the text covers (sales, partner_share, marketing)' using errcode = '22023'; end if;
  v_body := case when p ? 'body' then left(nullif(trim(coalesce(p ->> 'body', '')), ''), 4000) else cur.body end;
  v_covers := coalesce(b2b.opt_bool(p, 'covers_admission_partners'), cur.covers_admission_partners, false);
  v_active := coalesce(b2b.opt_bool(p, 'active'), cur.active, true);
  if v_covers and v_body is null then
    raise exception 'give the consent wording that names our admission partners (edtech companies)' using errcode = '22023';
  end if;
  if v_covers and not ('partner_share' = any (v_purposes)) then
    raise exception 'a text that covers admission partners must include the partner_share purpose' using errcode = '22023';
  end if;
  v_approve := b2b.opt_bool(p, 'lawyer_approved');
  v_note := left(nullif(trim(coalesce(p ->> 'approval_note', '')), ''), 1000);
  if coalesce(v_approve, false) then
    if length(coalesce(v_note, '')) < 10 then raise exception 'an approval note of at least 10 characters is required' using errcode = '22023'; end if;
    if v_body is null then raise exception 'the wording must be saved before it is approved' using errcode = '22023'; end if;
  end if;
  v_by := coalesce((select u.email from b2b.app_users u where u.user_id = auth.uid()), b2b.actor() ->> 'id', 'admin');

  if cur.version is null then
    insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at, approved_by, approval_note)
    values (v_version, v_channel, v_purposes, v_body, v_covers, v_active,
            case when coalesce(v_approve, false) then now() end, case when coalesce(v_approve, false) then v_by end, v_note)
    returning * into r;
    v_changed := array['created'];
  else
    v_clear := cur.lawyer_approved_at is not null and v_approve is distinct from true
               and (cur.body is distinct from v_body or cur.covers_admission_partners <> v_covers);
    update b2b.consent_texts
       set channel = v_channel, purposes = v_purposes, body = v_body, covers_admission_partners = v_covers, active = v_active,
           lawyer_approved_at = case when v_approve then now() when v_approve = false or v_clear then null else lawyer_approved_at end,
           approved_by = case when v_approve then v_by when v_approve = false or v_clear then null else approved_by end,
           approval_note = case when v_approve then v_note when v_approve = false or v_clear then null else coalesce(v_note, approval_note) end
     where version = v_version
    returning * into r;
    if cur.channel is distinct from r.channel then v_changed := array_append(v_changed, 'channel'); end if;
    if cur.purposes is distinct from r.purposes then v_changed := array_append(v_changed, 'purposes'); end if;
    if cur.body is distinct from r.body then v_changed := array_append(v_changed, 'body'); end if;
    if cur.covers_admission_partners is distinct from r.covers_admission_partners then v_changed := array_append(v_changed, 'covers_admission_partners'); end if;
    if cur.active is distinct from r.active then v_changed := array_append(v_changed, 'active'); end if;
    if cur.lawyer_approved_at is distinct from r.lawyer_approved_at then v_changed := array_append(v_changed, 'lawyer_approved_at'); end if;
  end if;
  perform b2b.log_event('consent_text.saved', null, null, null,
                        jsonb_build_object('version', r.version, 'channel', r.channel, 'purposes', to_jsonb(r.purposes),
                                           'covers_admission_partners', r.covers_admission_partners, 'active', r.active,
                                           'approved', r.lawyer_approved_at is not null, 'approval_cleared', v_clear,
                                           'changed', to_jsonb(v_changed), 'reason', left(trim(p_reason), 300)));
  return to_jsonb(r);
end $fn$;

-- ---------- the import fields ----------
/* The import fields a file column, a form question or an API lead can carry, and the lead_intake name each one is written
   as (null: handled by intake itself, not a lead_intake column). other_courses is new (D30). */
create or replace function b2b.import_fields()
returns jsonb language sql immutable set search_path = '' as $fn$
  select '{"full_name":"full_name","first_name":null,"last_name":null,"phone":"phone","email":"email","alternate_phone":"alternate_phone",
           "city":"city","state":"state","country":"country","course":"interested_course","specialization":"interested_specialization",
           "university":"interested_university","programme_level":"programme_level","study_mode":"study_mode_preference",
           "other_courses":null,
           "highest_qualification":"highest_qualification","academic_score":"academic_score_raw","work_experience":"work_experience_raw",
           "annual_budget":"annual_budget_raw","enrollment_timeline":"enrollment_timeline","preferred_language":"preferred_language",
           "guardian_name":"guardian_name","guardian_phone":"guardian_phone","enquirer_relation":"enquirer_relation",
           "preferred_call_time":"preferred_call_time","notes":"notes","utm_source":"utm_source","utm_medium":"utm_medium",
           "utm_campaign":"utm_campaign","utm_content":"utm_content","utm_term":"utm_term","campaign":"campaign",
           "source_detail":"source_detail","referral_code":"referral_code"}'::jsonb;
$fn$;

-- ---------- the intake core ----------
/* p_lead: standard intake field names (import_fields), plus phone; other_courses is an array or comma-separated text.
   p_opts: source_system, lead_source, channel, campaign, click_ids, utm, landing_url, consent {sales_at, partner_share_at,
   marketing_at, text_version, evidence?}, is_test, idempotency_key, occurred_at, directive {directive, b2c_lane,
   phone_trusted}, directive_source, attribution.
   Writes the lead through public.lead_intake(), the directive, the secondary interests (other_courses, and a different
   course on an existing lead), and a ledger row per consent purpose. Returns {lead_id, action, is_test, warnings [],
   outlook, interests_added, routing {status, destination, outlook, outlook_reason, outlook_lane, waiting_for, missing}}.
   Warnings: 'consent text version not registered', 'consent text does not cover admission partners'. */
create or replace function b2b.intake_lead(p_lead jsonb, p_opts jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_fields jsonb := b2b.import_fields();
  v_lead jsonb := '{}';
  c jsonb := case when jsonb_typeof(p_opts -> 'consent') = 'object' then p_opts -> 'consent' else '{}'::jsonb end;
  d jsonb := p_opts -> 'directive';
  v_res jsonb;
  v_id bigint;
  l public.student_leads;
  r jsonb;
  o jsonb;
  k text;
  v text;
  x text;
  v_phone text := public.crm_norm_phone(p_lead ->> 'phone');
  v_sys text := coalesce(p_opts ->> 'source_system', 'api');
  v_isrc text := case v_sys when 'meta' then 'meta' when 'google' then 'google' when 'manual' then 'manual' when 'import' then 'import'
                            when 'witty' then 'witty' when 'web_agent' then 'web_agent' when 'b2c' then 'b2c' when 'b2c_crm' then 'b2c' else 'api' end;
  v_csrc text := case v_sys when 'meta' then 'meta_form' when 'google' then 'google_form' when 'manual' then 'manual' when 'import' then 'import'
                            when 'witty' then 'witty' when 'b2c_crm' then 'b2c_crm' else 'api' end;
  v_ver text := nullif(trim(coalesce(c ->> 'text_version', '')), '');
  v_warn text[] := '{}';
  v_course text;
  v_prim jsonb;
  v_added int := 0;
begin
  if v_phone is null or length(v_phone) < 10 then raise exception 'phone is missing or too short' using errcode = '22023'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(p_lead) loop
    continue when k = 'phone' or v is null or trim(v) = '' or not (v_fields ? k) or v_fields ->> k is null;
    v_lead := v_lead || jsonb_build_object(v_fields ->> k, left(trim(v), 500));
  end loop;
  if p_lead ->> 'full_name' is null and coalesce(p_lead ->> 'first_name', p_lead ->> 'last_name') is not null then
    v_lead := v_lead || jsonb_build_object('full_name', trim(concat_ws(' ', p_lead ->> 'first_name', p_lead ->> 'last_name')));
  end if;
  if v_lead ? 'email' then
    if lower(v_lead ->> 'email') ~ '^[a-z0-9._%+''-]+@[a-z0-9.-]+\.[a-z]{2,}$' then v_lead := jsonb_set(v_lead, '{email}', to_jsonb(lower(v_lead ->> 'email')));
    else v_lead := v_lead - 'email'; end if;
  end if;
  v_lead := v_lead || jsonb_strip_nulls(jsonb_build_object(
    'source', p_opts ->> 'lead_source', 'channel', p_opts ->> 'channel', 'campaign', coalesce(p_opts ->> 'campaign', v_lead ->> 'campaign'),
    'click_ids', p_opts -> 'click_ids',
    'utm_source', coalesce(p_opts -> 'utm' ->> 'source', v_lead ->> 'utm_source'), 'utm_medium', coalesce(p_opts -> 'utm' ->> 'medium', v_lead ->> 'utm_medium'),
    'utm_campaign', coalesce(p_opts -> 'utm' ->> 'campaign', v_lead ->> 'utm_campaign'),
    'landing_url', p_opts ->> 'landing_url',
    'consent_sales_at', b2b.try_timestamptz(c ->> 'sales_at'), 'consent_partner_share_at', b2b.try_timestamptz(c ->> 'partner_share_at'),
    'consent_marketing_at', b2b.try_timestamptz(c ->> 'marketing_at'), 'consent_text_version', v_ver));

  v_res := public.lead_intake(jsonb_strip_nulls(jsonb_build_object(
    'phone', v_phone, 'source_system', v_sys, 'event_type', coalesce(p_opts ->> 'event_type', 'lead.created'),
    'lead', v_lead, 'idempotency_key', p_opts ->> 'idempotency_key', 'occurred_at', b2b.try_timestamptz(p_opts ->> 'occurred_at'),
    'attribution', coalesce(p_opts -> 'attribution', '{}'), 'is_test', case when coalesce((p_opts ->> 'is_test')::boolean, false) then true end)));
  v_id := (v_res ->> 'lead_id')::bigint;

  select * into l from public.student_leads where id = v_id;
  if d is not null and l.destination_type is null then
    insert into b2b.intake_directives (lead_id, source, directive, b2c_lane, phone_trusted)
    values (v_id, coalesce(p_opts ->> 'directive_source', 'api'), coalesce(d ->> 'directive', 'route'), d ->> 'b2c_lane', coalesce((d ->> 'phone_trusted')::boolean, false))
    on conflict (lead_id) do update set source = excluded.source, import_id = null, directive = excluded.directive, b2c_lane = excluded.b2c_lane,
                                        phone_trusted = b2b.intake_directives.phone_trusted or excluded.phone_trusted,
                                        created_at = now(), released_at = null, released_by = null;
  end if;

  -- secondary interests (D30): a different course on an existing lead (lead_intake keeps the stored course for these
  -- sources), then other_courses; lead_interest_add skips the primary interest and repeats
  v_course := nullif(trim(coalesce(v_lead ->> 'interested_course', '')), '');
  if v_course is not null and coalesce(v_res ->> 'action', '') <> 'created' then
    v_prim := b2b.lead_interest(l);
    if coalesce(v_prim ->> 'course_key', lower(coalesce(v_prim ->> 'course_text', ''))) is distinct from coalesce(b2b.match_course_key(v_course), lower(v_course)) then
      if b2b.lead_interest_add(v_id, jsonb_strip_nulls(jsonb_build_object('course', v_course, 'specialization', v_lead ->> 'interested_specialization',
                                 'level', v_lead ->> 'programme_level', 'mode', v_lead ->> 'study_mode_preference', 'university', v_lead ->> 'interested_university')), v_isrc) then
        v_added := v_added + 1;
      end if;
    end if;
  end if;
  foreach x in array b2b.other_courses_list(p_lead -> 'other_courses') loop
    if b2b.lead_interest_add(v_id, to_jsonb(x), v_isrc) then v_added := v_added + 1; end if;
  end loop;

  -- the consent ledger (D8) and the wording warnings (PART 7.1)
  if coalesce(c ->> 'sales_at', c ->> 'partner_share_at', c ->> 'marketing_at') is not null then
    perform b2b.consent_ledger_record(v_id, c, v_csrc,
              jsonb_strip_nulls(jsonb_build_object('source_system', v_sys, 'lead_source', p_opts ->> 'lead_source', 'channel', p_opts ->> 'channel',
                                                   'idempotency_key', p_opts ->> 'idempotency_key'))
              || case when jsonb_typeof(c -> 'evidence') = 'object' then c -> 'evidence' else '{}'::jsonb end);
    if v_ver is null or not exists (select 1 from b2b.consent_texts t where t.version = v_ver) then
      v_warn := array_append(v_warn, 'consent text version not registered');
    end if;
    if c ->> 'partner_share_at' is not null and not b2b.consent_text_covers(v_ver) then
      v_warn := array_append(v_warn, 'consent text does not cover admission partners');
    end if;
  end if;

  r := b2b.lead_readiness(l);
  o := b2b.route_outlook(l);
  return jsonb_build_object('lead_id', v_id, 'action', v_res ->> 'action', 'is_test', (v_res ->> 'is_test')::boolean,
    'warnings', to_jsonb(v_warn), 'outlook', o ->> 'outlook', 'interests_added', v_added,
    'routing', jsonb_build_object(
      'status', case when l.destination_type is not null then 'already_routed'
                     when (r ->> 'ready')::boolean then 'queued' else 'waiting' end,
      'destination', l.destination_type,
      'outlook', o ->> 'outlook', 'outlook_reason', o ->> 'reason', 'outlook_lane', o ->> 'lane',
      'waiting_for', r -> 'missing', 'missing', r -> 'not_qualified'));
end $fn$;

-- ---------- Meta Lead Ads ----------
/* Writes one fetched Meta lead (the Graph API answer) through intake_lead. Purposes come from the form's consent_purposes;
   a purpose named in the form's consent_checkbox_map (lead_forms.settings) is stamped only when its checkbox is required or
   ticked in custom_disclaimer_responses. utm_medium is 'paid_social' only when the lead is not organic. */
create or replace function b2b.meta_lead_apply(p_req_id bigint, g jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  q b2b.intake_requests;
  m jsonb;
  f jsonb;
  v_res jsonb;
  v_form text := coalesce(g ->> 'form_id', (select form_ref from b2b.intake_requests where id = p_req_id));
  v_organic boolean := lower(coalesce(g ->> 'is_organic', 'false')) in ('true', '1');
  v_purposes text[];
  v_map jsonb;
  v_ticked text[];
  v_eff text[];
  v_when text;
begin
  select * into q from b2b.intake_requests where id = p_req_id;
  if not exists (select 1 from b2b.lead_forms where platform = 'meta' and form_ref = v_form) then
    insert into b2b.lead_forms (platform, form_ref, name, page_ref) values ('meta', v_form, 'Meta form ' || v_form, q.raw ->> 'page_id')
    on conflict do nothing;
    perform b2b.log_event('alert.intake_new_form', null, null, null, jsonb_build_object('platform', 'meta', 'form_id', v_form));
  end if;
  m := b2b.form_answers_to_lead('meta', v_form,
         (select coalesce(jsonb_agg(jsonb_build_object('key', x ->> 'name', 'value', array_to_string(array(select jsonb_array_elements_text(x -> 'values')), ', '))), '[]')
            from jsonb_array_elements(coalesce(g -> 'field_data', '[]')) x));
  f := m -> 'form';
  v_purposes := array(select jsonb_array_elements_text(case when jsonb_typeof(f -> 'consent_purposes') = 'array' then f -> 'consent_purposes' else '["sales"]'::jsonb end));
  v_map := case when jsonb_typeof(f -> 'settings' -> 'consent_checkbox_map') = 'object' then f -> 'settings' -> 'consent_checkbox_map' else '{}'::jsonb end;
  v_ticked := array(select x ->> 'checkbox_key'
                      from jsonb_array_elements(case when jsonb_typeof(g -> 'custom_disclaimer_responses') = 'array' then g -> 'custom_disclaimer_responses' else '[]'::jsonb end) x
                     where lower(coalesce(x ->> 'is_checked', '')) in ('1', 'true') and x ->> 'checkbox_key' is not null);
  -- purposes named by a checkbox: stamped when the box is required or ticked; the other purposes follow the form
  v_eff := array(select p from unnest(v_purposes) p
                  where not exists (select 1 from jsonb_each(v_map) e where coalesce(e.value ->> 'purpose', e.value #>> '{}') = p))
           || array(select distinct coalesce(e.value ->> 'purpose', e.value #>> '{}') from jsonb_each(v_map) e
                     where coalesce(e.value ->> 'purpose', e.value #>> '{}') in ('sales', 'partner_share', 'marketing')
                       and (lower(coalesce(e.value ->> 'required', 'false')) in ('true', '1') or e.key = any (v_ticked)));
  v_when := coalesce(g ->> 'created_time', q.received_at::text);

  v_res := b2b.intake_lead(m -> 'lead', jsonb_build_object(
    'source_system', 'meta', 'lead_source', 'meta_lead_ad', 'channel', 'meta_lead_ads',
    'campaign', coalesce(f ->> 'campaign', g ->> 'campaign_name'),
    'utm', jsonb_build_object('source', case lower(coalesce(g ->> 'platform', '')) when 'ig' then 'instagram' else 'facebook' end,
                              'medium', case when v_organic then 'organic_social' else 'paid_social' end,
                              'campaign', g ->> 'campaign_name'),
    'click_ids', jsonb_strip_nulls(jsonb_build_object('leadgen_id', q.idempotency_key, 'form_id', v_form, 'ad_id', coalesce(g ->> 'ad_id', q.raw ->> 'ad_id'),
                                                      'adset_id', coalesce(g ->> 'adset_id', q.raw ->> 'adgroup_id'), 'campaign_id', g ->> 'campaign_id',
                                                      'page_id', q.raw ->> 'page_id', 'platform', g ->> 'platform')),
    'consent', jsonb_strip_nulls(jsonb_build_object(
                 'sales_at', case when 'sales' = any (v_eff) then v_when end,
                 'partner_share_at', case when 'partner_share' = any (v_eff) then v_when end,
                 'marketing_at', case when 'marketing' = any (v_eff) then v_when end,
                 'text_version', coalesce(f ->> 'consent_version', 'meta_form:' || v_form),
                 'evidence', jsonb_strip_nulls(jsonb_build_object('form_ref', v_form, 'leadgen_id', q.idempotency_key,
                                                                  'ticked', case when cardinality(v_ticked) > 0 then to_jsonb(v_ticked) end)))),
    'occurred_at', g ->> 'created_time', 'idempotency_key', 'meta:' || q.idempotency_key,
    'attribution', jsonb_build_object('platform', 'meta', 'form_id', v_form, 'ad_id', g ->> 'ad_id', 'campaign_id', g ->> 'campaign_id',
                                      'organic', g ->> 'is_organic', 'unmapped', m -> 'unmapped')));
  update b2b.intake_requests set status = 'done', result = v_res, lead_id = (v_res ->> 'lead_id')::bigint, done_at = now(), error = null,
                                 raw = q.raw || jsonb_build_object('graph', g) where id = q.id;
  return v_res;
end $fn$;

/* The Meta fetch loop (pg_net, every 10 seconds): the Graph fetch now also asks for custom_disclaimer_responses. */
create or replace function b2b.intake_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'intake'), '{}');
  v_token text := b2b.intake_secret('meta.page_token_id');
  r record;
  h record;
  g jsonb;
  n_sent int := 0;
  n_done int := 0;
begin
  perform set_config('b2b.actor', 'system', true);
  -- answers that came back
  for r in select q.id, q.net_request_id, q.attempts from b2b.intake_requests q
            where q.source = 'meta' and q.status = 'fetching' and q.net_request_id is not null order by q.id limit 200 loop
    select x.status_code, x.content, x.timed_out, x.error_msg into h from net._http_response x where x.id = r.net_request_id;
    continue when not found;
    begin
      if h.status_code between 200 and 299 then
        g := h.content::jsonb;
        perform b2b.meta_lead_apply(r.id, g);
        n_done := n_done + 1;
      else
        update b2b.intake_requests set status = case when r.attempts >= 3 then 'error' else 'received' end, net_request_id = null,
               error = left(coalesce('Graph API ' || h.status_code || ': ' || left(h.content, 200), h.error_msg, 'timed out'), 300)
         where id = r.id;
        if r.attempts >= 3 then perform b2b.log_event('alert.intake_failed', null, null, null, jsonb_build_object('source', 'meta', 'request_id', r.id)); end if;
      end if;
    exception when others then
      update b2b.intake_requests set status = 'error', error = left(sqlerrm, 300), net_request_id = null where id = r.id;
      perform b2b.log_event('alert.intake_failed', null, null, null, jsonb_build_object('source', 'meta', 'request_id', r.id, 'error', left(sqlerrm, 200)));
    end;
  end loop;
  -- new leadgen ids: fetch the lead (needs the page token)
  if v_token is not null then
    for r in select q.id, q.idempotency_key from b2b.intake_requests q
              where q.source = 'meta' and q.status = 'received' and q.attempts < 4 order by q.id limit 50 loop
      update b2b.intake_requests
         set status = 'fetching', attempts = attempts + 1,
             net_request_id = net.http_get(
               url := 'https://graph.facebook.com/' || coalesce(s -> 'meta' ->> 'api_version', 'v21.0') || '/' || r.idempotency_key,
               params := jsonb_build_object('fields', 'created_time,field_data,ad_id,ad_name,adset_id,campaign_id,campaign_name,form_id,platform,is_organic,custom_disclaimer_responses'),
               headers := jsonb_build_object('Authorization', 'Bearer ' || v_token),
               timeout_milliseconds := 10000)
       where id = r.id;
      n_sent := n_sent + 1;
    end loop;
  end if;
  return jsonb_build_object('fetching', n_sent, 'done', n_done);
end $fn$;

-- ---------- the Admin ----------
/* A Meta or Google form: question mapping, defaults, campaign, consent line, purposes, and consent_checkbox_map
   {checkbox key: purpose | {purpose, required}} (stored in settings). partner_share, as a purpose or in the map, needs a
   registered consent text that covers admission partners (consent_text_covers(consent_version)). */
create or replace function b2b.lead_form_save(p jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint;
  v_fields jsonb := b2b.import_fields();
  k text;
  v text;
  v_purposes text[];
  v_cmap jsonb := coalesce(p -> 'consent_checkbox_map', p -> 'settings' -> 'consent_checkbox_map');
  v_settings jsonb;
  v_version text := nullif(trim(coalesce(p ->> 'consent_version', '')), '');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(p ->> 'platform', '') not in ('meta', 'google') then raise exception 'choose Meta or Google' using errcode = '22023'; end if;
  if coalesce(p ->> 'form_ref', '') !~ '^[A-Za-z0-9_.:-]{1,80}$' then raise exception 'the form ID is the number or ID the platform shows' using errcode = '22023'; end if;
  if length(trim(coalesce(p ->> 'name', ''))) < 2 then raise exception 'give the form a name' using errcode = '22023'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(coalesce(p -> 'field_map', '{}')) loop
    if v <> 'ignore' and not (v_fields ? v) then raise exception 'unknown lead field: %', v using errcode = '22023'; end if;
  end loop;
  for k in select jsonb_object_keys(coalesce(p -> 'defaults', '{}')) loop
    if k not in ('course', 'specialization', 'university', 'programme_level', 'study_mode', 'campaign') then
      raise exception 'a form default can set course, specialization, university, level, mode or campaign' using errcode = '22023';
    end if;
  end loop;
  if jsonb_typeof(coalesce(p -> 'consent_purposes', '["sales"]')) <> 'array' then raise exception 'consent purposes must be a list' using errcode = '22023'; end if;
  v_purposes := array(select jsonb_array_elements_text(coalesce(p -> 'consent_purposes', '["sales"]')));
  if exists (select 1 from unnest(v_purposes) x where x not in ('sales', 'partner_share', 'marketing')) then
    raise exception 'unknown consent purpose' using errcode = '22023';
  end if;
  if v_cmap is not null and jsonb_typeof(v_cmap) <> 'null' then
    if jsonb_typeof(v_cmap) <> 'object' then raise exception 'the consent checkbox map pairs a checkbox key with a purpose' using errcode = '22023'; end if;
    for k, v in select e.key, coalesce(e.value ->> 'purpose', e.value #>> '{}') from jsonb_each(v_cmap) e loop
      if length(trim(k)) = 0 or length(k) > 120 then raise exception 'checkbox keys are 1 to 120 characters' using errcode = '22023'; end if;
      if v is null or v not in ('sales', 'partner_share', 'marketing') then
        raise exception 'checkbox % must map to sales, partner_share or marketing', k using errcode = '22023';
      end if;
    end loop;
    v_cmap := (select coalesce(jsonb_object_agg(e.key, jsonb_build_object('purpose', coalesce(e.value ->> 'purpose', e.value #>> '{}'),
                                                                           'required', lower(coalesce(e.value ->> 'required', 'false')) in ('true', '1'))), '{}')
                 from jsonb_each(v_cmap) e);
    v_settings := jsonb_build_object('consent_checkbox_map', v_cmap);
  end if;
  -- PART 7.1: sharing with partners needs the wording that names them, registered and covering
  if ('partner_share' = any (v_purposes) or exists (select 1 from jsonb_each(coalesce(v_cmap, '{}')) e where e.value ->> 'purpose' = 'partner_share'))
     and not b2b.consent_text_covers(v_version) then
    raise exception 'register the consent text that names our admission partners (edtech companies) first' using errcode = '22023';
  end if;

  insert into b2b.lead_forms (platform, form_ref, name, page_ref, field_map, defaults, campaign, consent_text, consent_version, consent_purposes, active, settings, updated_by)
  values (p ->> 'platform', p ->> 'form_ref', trim(p ->> 'name'), nullif(trim(p ->> 'page_ref'), ''), coalesce(p -> 'field_map', '{}'), coalesce(p -> 'defaults', '{}'),
          nullif(trim(p ->> 'campaign'), ''), nullif(trim(p ->> 'consent_text'), ''), v_version, v_purposes, coalesce((p ->> 'active')::boolean, true),
          coalesce(v_settings, '{}'), b2b.actor() ->> 'id')
  on conflict (platform, form_ref) do update
    set name = excluded.name, page_ref = excluded.page_ref, field_map = excluded.field_map, defaults = excluded.defaults, campaign = excluded.campaign,
        consent_text = excluded.consent_text, consent_version = excluded.consent_version, consent_purposes = excluded.consent_purposes,
        active = excluded.active, settings = coalesce(v_settings, b2b.lead_forms.settings), updated_at = now(), updated_by = excluded.updated_by
  returning id into v_id;
  perform b2b.log_event('intake.form_saved', null, null, null, jsonb_build_object('form_id', v_id, 'platform', p ->> 'platform', 'form_ref', p ->> 'form_ref',
                                                                                  'consent_version', v_version, 'purposes', to_jsonb(v_purposes),
                                                                                  'checkbox_map', v_cmap is not null));
  return v_id;
end $fn$;

/* "New lead": the Admin types a lead in. route: route, hold or b2c. lead.other_courses (array or comma text) becomes
   secondary interests; consent_version (optional) names a registered consent text, else 'manual:<consent_where>'; the
   purposes given are written to the ledger. The answer carries the intake warnings and the outlook. */
create or replace function b2b.intake_manual(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_res jsonb;
  v_purposes jsonb := coalesce(p -> 'consent_purposes', '[]');
  v_version text := nullif(trim(coalesce(p ->> 'consent_version', '')), '');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(p ->> 'route', '') not in ('route', 'hold', 'b2c') then raise exception 'choose what happens to the lead' using errcode = '22023'; end if;
  if p ->> 'route' = 'b2c' and coalesce(p ->> 'b2c_lane', '') not in ('sales', 'nurture') then raise exception 'choose the B2C lane' using errcode = '22023'; end if;
  if not v_purposes ? 'sales' then raise exception 'record that the student agreed to be contacted' using errcode = '22023'; end if;
  if length(trim(coalesce(p ->> 'consent_where', ''))) < 3 then raise exception 'say how the student agreed (call, walk-in, event…)' using errcode = '22023'; end if;
  if v_version is not null and not exists (select 1 from b2b.consent_texts t where t.version = v_version) then
    raise exception 'unknown consent text version: %', v_version using errcode = '22023';
  end if;
  if length(trim(coalesce(p -> 'lead' ->> 'full_name', ''))) < 2 then raise exception 'give the student''s name' using errcode = '22023'; end if;
  if b2b.phone_problem(public.crm_norm_phone(p -> 'lead' ->> 'phone')) is not null and not b2b.is_test_phone(public.crm_norm_phone(p -> 'lead' ->> 'phone')) then
    raise exception 'the phone number is not valid' using errcode = '22023';
  end if;
  v_res := b2b.intake_lead(p -> 'lead', jsonb_build_object(
    'source_system', 'manual', 'lead_source', coalesce(nullif(trim(p ->> 'source'), ''), 'manual_entry'), 'channel', 'manual', 'campaign', p ->> 'campaign',
    'consent', jsonb_strip_nulls(jsonb_build_object('sales_at', now(), 'partner_share_at', case when v_purposes ? 'partner_share' then now() end,
                                  'marketing_at', case when v_purposes ? 'marketing' then now() end,
                                  'text_version', coalesce(v_version, 'manual:' || left(trim(p ->> 'consent_where'), 80)),
                                  'evidence', jsonb_build_object('where', left(trim(p ->> 'consent_where'), 300), 'entered_by', b2b.actor() ->> 'id'))),
    'idempotency_key', 'manual:' || gen_random_uuid(), 'directive_source', 'manual',
    'directive', jsonb_build_object('directive', p ->> 'route', 'b2c_lane', p ->> 'b2c_lane', 'phone_trusted', true),
    'attribution', jsonb_build_object('entered_by', b2b.actor() ->> 'id', 'note', p ->> 'note')));
  insert into b2b.intake_requests (source, idempotency_key, raw, status, result, lead_id, done_at)
  values ('manual', 'manual:' || (v_res ->> 'lead_id') || ':' || extract(epoch from clock_timestamp()), p, 'done', v_res, (v_res ->> 'lead_id')::bigint, now());
  perform b2b.log_event('lead.entered', (v_res ->> 'lead_id')::bigint, null, null,
                        jsonb_build_object('action', v_res ->> 'action', 'route', p ->> 'route', 'warnings', v_res -> 'warnings', 'outlook', v_res ->> 'outlook'));
  return v_res;
end $fn$;

-- ---------- the import wizard (D39) ----------
/* Step 5. p: {source_label, campaign, routing_choice route|hold|b2c, b2c_lane, consent {where, when, text, purposes [sales,
   partner_share, marketing], covers_admission_partners?}}. 'route' no longer needs partner_share: students without it get
   the R8 request (rate-limited). The consent text is registered as consent_texts 'import:<id>' (covers false unless
   stated). Rows without a usable phone (none, or not 10-15 digits) are skipped; blocked and invalid-pattern rows are kept
   and become Not passed through R5 when import_process writes them. */
create or replace function b2b.import_commit(p_import_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.imports;
  c jsonb := coalesce(p -> 'consent', '{}');
  v_when timestamptz;
  v_purposes text[];
  v_covers boolean;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into i from b2b.imports where id = p_import_id for update;
  if i.id is null then raise exception 'import not found' using errcode = 'P0002'; end if;
  if i.status <> 'staging' then raise exception 'this import was already committed' using errcode = '22023'; end if;
  if i.total_rows = 0 then raise exception 'the file has no rows' using errcode = '22023'; end if;
  if length(trim(coalesce(p ->> 'source_label', ''))) < 2 then raise exception 'give a source label' using errcode = '22023'; end if;
  if coalesce(p ->> 'routing_choice', '') not in ('route', 'hold', 'b2c') then raise exception 'choose what happens to the leads' using errcode = '22023'; end if;
  if p ->> 'routing_choice' = 'b2c' and coalesce(p ->> 'b2c_lane', '') not in ('sales', 'nurture') then raise exception 'choose the B2C lane' using errcode = '22023'; end if;
  if length(trim(coalesce(c ->> 'where', ''))) < 3 or length(trim(coalesce(c ->> 'text', ''))) < 10 then
    raise exception 'give the consent basis: where the students agreed and the consent text' using errcode = '22023';
  end if;
  begin v_when := (c ->> 'when')::timestamptz; exception when others then v_when := null; end;
  if v_when is null or v_when > now() then raise exception 'give when the students agreed (a date not in the future)' using errcode = '22023'; end if;
  if jsonb_typeof(c -> 'purposes') <> 'array' or not (c -> 'purposes') ? 'sales' then
    raise exception 'the consent must at least cover being contacted about courses' using errcode = '22023';
  end if;
  v_purposes := array(select distinct x from jsonb_array_elements_text(c -> 'purposes') x order by x);
  if exists (select 1 from unnest(v_purposes) x where x not in ('sales', 'partner_share', 'marketing')) then
    raise exception 'unknown consent purpose' using errcode = '22023';
  end if;
  v_covers := 'partner_share' = any (v_purposes) and coalesce(b2b.opt_bool(c, 'covers_admission_partners'), false);

  update b2b.imports
     set status = 'committing', committed_at = now(), source_label = left(lower(regexp_replace(trim(p ->> 'source_label'), '[^a-zA-Z0-9]+', '_', 'g')), 60),
         campaign = nullif(left(trim(coalesce(p ->> 'campaign', '')), 120), ''),
         consent = jsonb_build_object('where', left(trim(c ->> 'where'), 300), 'when', v_when, 'text', left(trim(c ->> 'text'), 2000), 'purposes', to_jsonb(v_purposes),
                                      'covers_admission_partners', v_covers, 'text_version', 'import:' || i.id),
         routing_choice = p ->> 'routing_choice', b2c_lane = case when p ->> 'routing_choice' = 'b2c' then p ->> 'b2c_lane' end
   where id = i.id;
  -- the import's wording is a registered consent text (PART 7.1); the Admin approves or edits it in Consent texts
  insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active)
  values ('import:' || i.id, 'import', v_purposes, left(trim(c ->> 'text'), 2000), v_covers, true)
  on conflict (version) do nothing;
  -- only rows without a usable phone are skipped (D39); blocked and invalid-pattern rows are recorded and go to Not passed
  update b2b.import_rows set status = 'skipped', error = 'no usable phone number', done_at = now()
   where import_id = i.id and status = 'staged'
     and (phone is null or length(regexp_replace(phone, '\D', '', 'g')) not between 10 and 15);
  perform b2b.log_event('import.committed', null, null, null,
                        jsonb_build_object('import_id', i.id, 'rows', i.total_rows, 'routing_choice', p ->> 'routing_choice', 'source_label', p ->> 'source_label',
                                           'purposes', to_jsonb(v_purposes), 'covers_admission_partners', v_covers));
  return b2b.import_process(i.id, 300);
end $fn$;

/* Writes up to p_limit staged rows of a committing import through lead_intake(). Safe to call concurrently. Each row also
   gets its directive (blocked / invalid rows: 'route', so R5 records them as Not passed at once), its other_courses and a
   different course on an existing lead as secondary interests, and a ledger row per consent purpose. The import's counts
   add recorded_not_passed (rows written whose preview was blocked or invalid). */
create or replace function b2b.import_process(p_import_id bigint, p_limit int)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.imports;
  x record;
  v_lead jsonb;
  v_res jsonb;
  v_key text;
  v_course text;
  v_purposes jsonb;
  v_lead_id bigint;
  v_np boolean;
  v_prim jsonb;
  oc text;
  n int := 0;
  v_left int;
  v_np_n int;
begin
  select * into i from b2b.imports where id = p_import_id;
  if i.id is null or i.status <> 'committing' then return jsonb_build_object('processed', 0, 'left', 0, 'status', i.status); end if;
  v_purposes := coalesce(i.consent -> 'purposes', '[]');
  perform set_config('b2b.actor', coalesce(nullif(current_setting('b2b.actor', true), ''), 'system'), true);
  for x in select * from b2b.import_rows where import_id = i.id and status = 'staged' order by row_no
            limit least(greatest(coalesce(p_limit, 300), 1), 2000) for update skip locked loop
    begin
      v_np := x.preview in ('blocked', 'invalid');
      v_lead := x.lead - 'phone' - 'course' - 'specialization' - 'university' - 'study_mode' - 'academic_score' - 'work_experience' - 'annual_budget' - 'other_courses';
      v_key := i.course_choices ->> (x.lead ->> 'course');
      v_course := coalesce((select p.course from public.catalog_programs p where p.course_key = v_key limit 1), x.lead ->> 'course');
      v_lead := v_lead || jsonb_strip_nulls(jsonb_build_object(
        'interested_course', v_course, 'interested_specialization', x.lead ->> 'specialization', 'interested_university', x.lead ->> 'university',
        'study_mode_preference', x.lead ->> 'study_mode', 'academic_score_raw', x.lead ->> 'academic_score',
        'work_experience_raw', x.lead ->> 'work_experience', 'annual_budget_raw', x.lead ->> 'annual_budget',
        'source', i.source_label, 'channel', 'import', 'campaign', coalesce(x.lead ->> 'campaign', i.campaign),
        'consent_sales_at', case when v_purposes ? 'sales' then i.consent ->> 'when' end,
        'consent_partner_share_at', case when v_purposes ? 'partner_share' then i.consent ->> 'when' end,
        'consent_marketing_at', case when v_purposes ? 'marketing' then i.consent ->> 'when' end,
        'consent_text_version', 'import:' || i.id));
      v_res := public.lead_intake(jsonb_build_object('phone', x.phone, 'source_system', 'import', 'event_type', 'lead.imported', 'lead', v_lead,
                                                     'idempotency_key', 'import:' || i.id || ':' || x.row_no,
                                                     'attribution', jsonb_build_object('import_id', i.id, 'source_label', i.source_label, 'campaign', i.campaign, 'row_no', x.row_no)));
      v_lead_id := (v_res ->> 'lead_id')::bigint;
      if exists (select 1 from public.student_leads l where l.id = v_lead_id and l.destination_type is null) then
        insert into b2b.intake_directives (lead_id, source, import_id, directive, b2c_lane, phone_trusted)
        values (v_lead_id, 'import', i.id, case when v_np then 'route' else i.routing_choice end, case when v_np then null else i.b2c_lane end, true)
        on conflict (lead_id) do update set source = 'import', import_id = excluded.import_id, directive = excluded.directive, b2c_lane = excluded.b2c_lane,
                                            phone_trusted = true, created_at = now(), released_at = null, released_by = null;
      end if;
      -- secondary interests (D30): a different course on an existing lead, then other_courses
      if v_course is not null and coalesce(v_res ->> 'action', '') <> 'created' then
        select b2b.lead_interest(l) into v_prim from public.student_leads l where l.id = v_lead_id;
        if coalesce(v_prim ->> 'course_key', lower(coalesce(v_prim ->> 'course_text', ''))) is distinct from coalesce(b2b.match_course_key(v_course), lower(v_course)) then
          perform b2b.lead_interest_add(v_lead_id, jsonb_strip_nulls(jsonb_build_object('course', v_course, 'specialization', x.lead ->> 'specialization',
                                          'mode', x.lead ->> 'study_mode', 'university', x.lead ->> 'university')), 'import');
        end if;
      end if;
      foreach oc in array b2b.other_courses_list(x.lead -> 'other_courses') loop
        perform b2b.lead_interest_add(v_lead_id, to_jsonb(oc), 'import');
      end loop;
      -- the consent ledger (D8): the import's basis, under its registered text
      perform b2b.consent_ledger_record(v_lead_id, jsonb_strip_nulls(jsonb_build_object(
                'sales_at', case when v_purposes ? 'sales' then i.consent ->> 'when' end,
                'partner_share_at', case when v_purposes ? 'partner_share' then i.consent ->> 'when' end,
                'marketing_at', case when v_purposes ? 'marketing' then i.consent ->> 'when' end,
                'text_version', 'import:' || i.id)), 'import',
              jsonb_strip_nulls(jsonb_build_object('import_id', i.id, 'row_no', x.row_no, 'where', i.consent ->> 'where')));
      update b2b.import_rows set status = 'imported', lead_id = v_lead_id, action = v_res ->> 'action', done_at = now() where id = x.id;
    exception when others then
      update b2b.import_rows set status = 'error', error = left(sqlerrm, 300), done_at = now() where id = x.id;
    end;
    n := n + 1;
  end loop;

  select count(*) filter (where status = 'staged'), count(*) filter (where status = 'imported' and preview in ('blocked', 'invalid'))
    into v_left, v_np_n from b2b.import_rows where import_id = i.id;
  if v_left = 0 then
    update b2b.imports set status = 'done', finished_at = now(),
           counts = (select jsonb_build_object('imported', count(*) filter (where status = 'imported'), 'skipped', count(*) filter (where status = 'skipped'),
                                               'errors', count(*) filter (where status = 'error'), 'created', count(*) filter (where action = 'created'),
                                               'merged', count(*) filter (where action = 'merged'), 'reopened', count(*) filter (where action = 'reopened'),
                                               'recorded_not_passed', count(*) filter (where status = 'imported' and preview in ('blocked', 'invalid')))
                       from b2b.import_rows where import_id = i.id)
     where id = i.id and status = 'committing';
    if found then perform b2b.log_event('import.done', null, null, null, (select counts || jsonb_build_object('import_id', id) from b2b.imports where id = i.id)); end if;
  end if;
  return jsonb_build_object('processed', n, 'left', v_left, 'status', case when v_left = 0 then 'done' else 'committing' end, 'recorded_not_passed', v_np_n);
end $fn$;

-- ---------- the B2C CRM's write API ----------
/* B2C writes its fields on a lead it holds. p: {request_id, if_version?, actor: {id, email, name}, set: {field: value}}.
   set.other_courses (a list of course names, or comma text, at most 9) replaces the lead's secondary interests (source
   'b2c'); it is reported in b2c.lead_updated's changes like any field, so a re-decision can read it (D11). */
create or replace function b2b.api_b2c_lead_update(p_key text, p_lead_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k jsonb := b2b.b2c_key(p_key);
  cfg jsonb := b2b.b2c_link_cfg();
  v_req text := left(trim(coalesce(p ->> 'request_id', '')), 100);
  v_actor jsonb := coalesce(p -> 'actor', '{}');
  l public.student_leads;
  w b2b.b2c_writes;
  f jsonb;
  c jsonb;
  v_key text;
  v_val jsonb;
  v_ver int;
  v_errors jsonb := '{}';
  v_cols jsonb := '{}';
  v_diff jsonb := '{}';
  v_row jsonb;
  v_sql text;
  v_res jsonb;
  v_status int;
  v_oc text[];
  v_oc_cur text[];
  v_oc_set boolean := false;
begin
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if v_req = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'request_id is required (unique per change, reused on retries)'); end if;
  select * into w from b2b.b2c_writes where coalesce(api_key_id, 0) = coalesce((k ->> 'api_key_id')::bigint, 0) and kind = 'update' and request_id = v_req;
  if w.id is not null then return w.response || jsonb_build_object('replayed', true); end if;
  if jsonb_typeof(p -> 'set') is distinct from 'object' or (select count(*) from jsonb_object_keys(p -> 'set')) = 0 then
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'set must be an object of field: value');
  end if;
  if jsonb_typeof(v_actor) <> 'object' or length(v_actor::text) > 1000 then return jsonb_build_object('ok', false, 'status', 400, 'error', 'actor must be a small object'); end if;

  select * into l from public.student_leads where id = p_lead_id for update;
  v_ver := b2b.b2c_version(p_lead_id);
  v_res := case
    when l.id is null then jsonb_build_object('ok', false, 'status', 404, 'error', 'no such lead')
    when l.deleted_at is not null or l.merged_into_id is not null or l.anonymised_at is not null
      then jsonb_build_object('ok', false, 'status', 410, 'error', 'the lead was deleted or merged', 'merged_into_id', l.merged_into_id)
    when not b2b.b2c_holds(l) then jsonb_build_object('ok', false, 'status', 409, 'error', 'the B2C CRM does not hold this lead', 'destination', l.destination_type)
    when p ? 'if_version' and nullif(p ->> 'if_version', '')::int is distinct from v_ver
      then jsonb_build_object('ok', false, 'status', 409, 'error', 'version conflict: the lead changed since your copy', 'version', v_ver,
                              'record', b2b.b2c_record(l))
  end;
  if v_res is null then
    for v_key, v_val in select key, value from jsonb_each(p -> 'set') loop
      if v_key = 'other_courses' then
        -- the secondary interests (D30): a list of course names, or comma text; null or [] clears them
        if jsonb_typeof(v_val) not in ('array', 'string', 'null') then v_errors := v_errors || jsonb_build_object(v_key, 'must be a list of course names'); continue; end if;
        if jsonb_typeof(v_val) = 'array' and exists (select 1 from jsonb_array_elements(v_val) e where jsonb_typeof(e) not in ('string', 'object')) then
          v_errors := v_errors || jsonb_build_object(v_key, 'must be a list of course names'); continue;
        end if;
        v_oc := b2b.other_courses_list(v_val);
        if cardinality(v_oc) > 9 then v_errors := v_errors || jsonb_build_object(v_key, 'at most 9 other courses'); continue; end if;
        v_oc_cur := array(select i.course_text from b2b.lead_interests i where i.lead_id = l.id and i.removed_at is null order by i.position, i.id);
        if (select array_agg(lower(y) order by lower(y)) from unnest(v_oc) y) is distinct from (select array_agg(lower(y) order by lower(y)) from unnest(v_oc_cur) y) then
          v_oc_set := true;
          v_diff := v_diff || jsonb_build_object('other_courses', jsonb_build_object('from', to_jsonb(v_oc_cur), 'to', to_jsonb(v_oc)));
        end if;
        continue;
      end if;
      select x into f from jsonb_array_elements(b2b.b2c_fields()) x where x ->> 'field' = v_key;
      if f is null then v_errors := v_errors || jsonb_build_object(v_key, 'unknown field'); continue; end if;
      if f ->> 'write' <> 'b2c' or not (cfg -> 'writable') ? v_key then v_errors := v_errors || jsonb_build_object(v_key, 'is read-only for the B2C CRM'); continue; end if;
      c := b2b.b2c_coerce(f, v_val);
      if c ? 'error' then v_errors := v_errors || jsonb_build_object(v_key, c ->> 'error'); continue; end if;
      if f ->> 'kind' = 'stage' and c ->> 'value' is not null and not (c ->> 'value') = any (b2b.b2c_stage_keys()) then
        v_errors := v_errors || jsonb_build_object(v_key, 'is not a known stage'); continue;
      end if;
      if v_key = 'custom_fields' then
        c := jsonb_build_object('value', jsonb_strip_nulls(coalesce(l.custom_fields, '{}') || coalesce(c -> 'value', '{}')));
      end if;
      if (to_jsonb(l) -> (f ->> 'column')) is distinct from (c -> 'value') then
        v_cols := v_cols || jsonb_build_object(f ->> 'column', c -> 'value');
        v_diff := v_diff || jsonb_build_object(v_key, jsonb_build_object('from', to_jsonb(l) -> (f ->> 'column'), 'to', c -> 'value'));
      end if;
    end loop;
    if v_errors <> '{}' then
      v_res := jsonb_build_object('ok', false, 'status', 422, 'error', 'some fields were refused', 'fields', v_errors);
    end if;
  end if;

  if v_res is null and v_diff = '{}' then
    v_res := jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('lead_id', l.id, 'version', v_ver, 'changed', '[]'::jsonb));
  elsif v_res is null then
    perform set_config('b2b.actor', 'b2c_crm', true);
    if v_cols <> '{}' then
      -- a new stage stamps stage_changed_at unless the caller gave it
      if v_cols ? 'stage' and not v_cols ? 'stage_changed_at' then v_cols := v_cols || jsonb_build_object('stage_changed_at', now()); end if;
      v_row := to_jsonb(l) || v_cols;
      select string_agg(format('%I = r.%I', x, x), ', ') into v_sql from jsonb_object_keys(v_cols) x;
      execute format('update public.student_leads t set %s, updated_by = $3 from jsonb_populate_record(null::public.student_leads, $1) r where t.id = $2', v_sql)
        using v_row, l.id, left('b2c_crm:' || coalesce(v_actor ->> 'email', v_actor ->> 'id', 'api'), 120);
    end if;
    if v_oc_set then perform b2b.lead_interests_apply(l.id, to_jsonb(v_oc), 'b2c'); end if;
    perform b2b.log_event('b2c.lead_updated', l.id, l.allocation_id, null,
                          jsonb_build_object('changes', v_diff, 'actor', v_actor, 'request_id', v_req, 'api_key', k ->> 'name'));
    perform b2b.b2c_sync_lead(l.id, false, 'b2c:' || v_req);
    perform b2b.outbox_kick();
    v_res := jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
      'lead_id', l.id, 'version', b2b.b2c_version(l.id), 'changed', (select jsonb_agg(x) from jsonb_object_keys(v_diff) x),
      'record', (select b2b.b2c_record(n) from public.student_leads n where n.id = l.id)));
  end if;

  v_status := (v_res ->> 'status')::int;
  insert into b2b.b2c_writes (api_key_id, request_id, lead_id, kind, actor, changes, status, http_status, error, version_before, version_after, response)
  values ((k ->> 'api_key_id')::bigint, v_req, p_lead_id, 'update', v_actor, coalesce(nullif(v_diff, '{}'), p -> 'set'),
          case when v_status = 200 and v_diff = '{}' then 'unchanged' when v_status = 200 then 'applied' when v_status = 409 and v_res ? 'version' then 'conflict' else 'rejected' end,
          v_status, v_res ->> 'error', v_ver, case when v_status = 200 then b2b.b2c_version(p_lead_id) end,
          v_res - 'record' || case when v_res -> 'result' ? 'record' then jsonb_build_object('result', (v_res -> 'result') - 'record') else '{}' end)
  on conflict do nothing;
  return v_res;
end $fn$;

-- ---------- grants ----------
-- new internal functions: service_role only
revoke execute on function b2b.other_courses_list(jsonb), b2b.opt_bool(jsonb, text), b2b.lead_interest_add(bigint, jsonb, text),
                           b2b.lead_interests_apply(bigint, jsonb, text), b2b.consent_ledger_record(bigint, jsonb, text, jsonb)
  from public, anon, authenticated;
grant execute on function b2b.other_courses_list(jsonb), b2b.opt_bool(jsonb, text), b2b.lead_interest_add(bigint, jsonb, text),
                          b2b.lead_interests_apply(bigint, jsonb, text), b2b.consent_ledger_record(bigint, jsonb, text, jsonb)
  to service_role;
-- new Admin RPCs (they check b2b.is_admin())
revoke execute on function b2b.lead_interests_save(bigint, jsonb, text), b2b.consent_text_save(jsonb, text) from public, anon;
grant execute on function b2b.lead_interests_save(bigint, jsonb, text), b2b.consent_text_save(jsonb, text) to authenticated, service_role;
-- replaced functions keep their grants (restated as in m17c/m17d/m17e/m17f/m22b)
revoke execute on function b2b.intake_lead(jsonb, jsonb), b2b.meta_lead_apply(bigint, jsonb), b2b.intake_tick(), b2b.import_fields(), b2b.import_process(bigint, int)
  from public, anon, authenticated;
grant execute on function b2b.intake_lead(jsonb, jsonb), b2b.meta_lead_apply(bigint, jsonb), b2b.intake_tick(), b2b.import_fields(), b2b.import_process(bigint, int)
  to service_role;
revoke execute on function b2b.lead_form_save(jsonb), b2b.intake_manual(jsonb), b2b.import_commit(bigint, jsonb) from public, anon;
grant execute on function b2b.lead_form_save(jsonb), b2b.intake_manual(jsonb), b2b.import_commit(bigint, jsonb) to authenticated, service_role;
revoke execute on function b2b.api_b2c_lead_update(text, bigint, jsonb) from public;
grant execute on function b2b.api_b2c_lead_update(text, bigint, jsonb) to anon, authenticated, service_role;
