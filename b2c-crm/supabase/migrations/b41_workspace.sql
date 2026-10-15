-- B2C CRM b41: completing the counsellor workspace (docs/completion-gaps.md, section C). Staging first. Idempotent.
--   WhatsApp media      images, documents and brochures out inside the window; inbound media stored privately, opened by
--                       signed link, attached to the application checklist in one tap (B8.5, B8.8)
--   programme_cache     the catalogue in one row per programme with duration, EMI, scholarship, intakes, partners and
--                       popularity; search with every filter and sort; compare 2-4; fit by eligibility and budget (B8.3, B8.9)
--   pipeline_board()    columns with expected commission, SLA colour, priority order, filters, counsellor filter (B8.2)
--   inbox_list()        searches message text and template names; counsellor, window and awaiting-reply filters;
--                       Marketing reads every conversation (B8.5, B15)
--   email library       author, uses and reply rate; every merge field from the lead (B8.6)
--   staff WhatsApp      reminders and alerts to a person's own number, by their choice (B8.2, B8.7, B17)
--   custom fields       Admin-defined profile fields with field history (B8.3)
--   checklists          per-university document checklists edited in Settings, with history; documents open by signed link (B8.8)
--   SLA by source       first-contact minutes by source as well as temperature; neglect alerts after 48 h untouched (B8.7)
-- The catalogue stays read-only: duration, EMI, scholarship and intakes come from catalog_programs.fee_other when the
-- B2B CRM's Programme Repository carries them (keys duration_months, emi_monthly, scholarship, intakes, deadline).

-- ---------- WhatsApp media (C1) ----------
alter table b2c.wa_messages add column if not exists media_path text;
alter table b2c.wa_messages add column if not exists media_error text;
alter table b2c.wa_messages add column if not exists media_tries int not null default 0;
create index if not exists wa_messages_media_todo on b2c.wa_messages (id) where direction = 'in' and media is not null and media_path is null;

/* A file or brochure to the student while the 24-hour window is open. p_path is a stored file under the lead's folder;
   p_link a public https link (a brochure from the Programme page). */
create or replace function b2c.wa_queue_media(p_lead bigint, p_kind text, p_path text, p_caption text default null, p_filename text default null, p_link text default null)
returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v_phone text := b2c.wa_phone(p_lead); v bigint; v_label text;
begin
  if p_kind not in ('image', 'document') then raise exception 'an image or a document'; end if;
  if (p_path is null) = (p_link is null) then raise exception 'choose a file or a link'; end if;
  if p_path is not null and p_path !~ ('^leads/' || p_lead || '/') then raise exception 'files are sent from the lead''s folder'; end if;
  if p_link is not null and p_link !~ '^https://' then raise exception 'links must start with https://'; end if;
  if b2c.may_message(p_lead) is not null then raise exception 'cannot message this student: %', b2c.may_message(p_lead); end if;
  if not b2c.window_open(v_phone) then raise exception 'the 24-hour window is closed: start with an approved template'; end if;
  v_label := coalesce(nullif(trim(p_filename), ''), case when p_kind = 'image' then 'image' else 'document' end);
  insert into b2c.wa_messages (phone, lead_id, direction, kind, body, media, media_path, status, category, purpose, user_id)
  values (v_phone, p_lead, 'out', 'media', left(nullif(trim(p_caption), ''), 1024),
          jsonb_strip_nulls(jsonb_build_object('kind', p_kind, 'filename', left(v_label, 120), 'link', p_link)), p_path, 'queued', 'service', 'sales', me)
  returning id into v;
  insert into b2c.send_queue (channel, lead_id, to_address, wa_message_id, payload, purpose)
  values ('whatsapp', p_lead, v_phone, v, jsonb_strip_nulls(jsonb_build_object('type', 'media', 'media_kind', p_kind, 'path', p_path, 'link', p_link,
          'caption', left(nullif(trim(p_caption), ''), 1024), 'filename', left(v_label, 120))), 'sales');
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id)
  values (p_lead, 'whatsapp', 'out', '[' || p_kind || '] ' || v_label || coalesce(': ' || left(nullif(trim(p_caption), ''), 300), ''), jsonb_build_object('message_id', v), me);
  update b2c.leads_state set last_activity_at = now() where lead_id = p_lead;
  perform b2c.queue_activity(p_lead, 'whatsapp', now(), 'media', null, v_label);
  return v;
end $f$;

/* Inbound media waiting to be fetched from WhatsApp and stored privately (the app's job). */
create or replace function b2c.wa_media_take(p_limit int default 10) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with t as (select id from b2c.wa_messages where direction = 'in' and media is not null and media ? 'id' and media_path is null and lead_id is not null and media_tries < 5
              order by id limit p_limit for update skip locked),
       m as (update b2c.wa_messages w set media_tries = w.media_tries + 1 from t where w.id = t.id returning w.id, w.lead_id, w.media)
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'lead_id', m.lead_id, 'media', m.media)), '[]') into v from m;
  return v;
end $f$;

create or replace function b2c.wa_media_stored(p_message bigint, p_path text, p_error text default null) returns void language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.wa_messages set media_path = case when p_error is null then p_path end, media_error = left(p_error, 300)
   where id = p_message and direction = 'in' and (p_path is null or p_path ~ ('^leads/' || lead_id || '/'));
end $f$;

/* The stored file of a message, for a signed link: anyone who may see the lead. */
create or replace function b2c.wa_media_open(p_message bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare m b2c.wa_messages;
begin
  select * into m from b2c.wa_messages where id = p_message;
  if m.id is null or m.lead_id is null or not coalesce(b2c.can_see(m.lead_id), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  if m.media_path is null then raise exception 'this file is still being fetched'; end if;
  return jsonb_build_object('bucket', 'b2c-documents', 'path', m.media_path, 'filename', coalesce(m.media ->> 'filename', 'file'), 'mime', m.media ->> 'mime_type');
end $f$;

/* One tap: a document the student sent on WhatsApp goes onto the application checklist. */
create or replace function b2c.wa_media_attach(p_message bigint, p_application bigint, p_kind text) returns bigint language plpgsql security definer set search_path = '' as $f$
declare m b2c.wa_messages;
begin
  select * into m from b2c.wa_messages where id = p_message and direction = 'in';
  if m.id is null or m.lead_id is null then raise exception 'unknown message'; end if;
  perform b2c.require_lead(m.lead_id);
  if m.media_path is null then raise exception 'this file is still being fetched'; end if;
  if coalesce(trim(p_kind), '') = '' then raise exception 'choose the checklist item'; end if;
  if p_application is not null and not exists (select 1 from b2c.applications a where a.id = p_application and a.lead_id = m.lead_id) then raise exception 'unknown application'; end if;
  return b2c.document_add(m.lead_id, p_application, trim(p_kind), m.media_path, coalesce(m.media ->> 'filename', p_kind), 'whatsapp');
end $f$;

-- ---------- the programme catalogue, cached (C2, C6) ----------
create table if not exists b2c.programme_cache (
  id bigint primary key,                    -- catalog_programs.id
  university_id bigint,
  university text,
  university_short text,
  name text,
  course text,
  specialization text,
  level text,
  mode text,
  duration_months int,
  fee_yearly numeric,
  fee_semester numeric,
  fee_total numeric,
  fee_exam numeric,
  fee_registration numeric,
  emi_monthly numeric,
  scholarship text,
  intakes text[] not null default '{}',
  deadline text,
  accreditation text,
  recognitions jsonb,
  min_qualification text,
  min_rank int,
  min_pct numeric,
  eligibility text,
  brochure_url text,
  partners jsonb not null default '[]'::jsonb,   -- [{partner_id, name, commission}] Admin and Marketing only
  enrollments int not null default 0,
  search_doc tsvector,
  active boolean not null default true,
  catalog_updated_at timestamptz,
  cached_at timestamptz not null default now()
);
create index if not exists programme_cache_search on b2c.programme_cache using gin (search_doc);
alter table b2c.programme_cache enable row level security;

create or replace function b2c.num_or_null(p text) returns numeric language sql immutable set search_path = '' as $f$
  select nullif(regexp_replace(coalesce(p, ''), '[^0-9.]', '', 'g'), '')::numeric
$f$;

/* Rebuilt when the catalogue changes (checked every 15 minutes) or on demand. */
create or replace function b2c.programme_cache_refresh(p_force boolean default false) returns int language plpgsql security definer set search_path = '' as $f$
declare v_cat timestamptz; v_cached timestamptz; n int; v_b2b boolean := to_regclass('b2b.partner_programmes') is not null and to_regclass('b2b.partners') is not null;
begin
  select max(greatest(p.updated_at, u.updated_at)) into v_cat from public.catalog_programs p join public.catalog_universities u on u.id = p.university_id;
  select max(catalog_updated_at) into v_cached from b2c.programme_cache where active;
  if not p_force and v_cached is not null and v_cat <= v_cached
     and (select count(*) from b2c.programme_cache where active) = (select count(*) from public.catalog_programs where active) then
    return 0;
  end if;
  insert into b2c.programme_cache (id, university_id, university, university_short, name, course, specialization, level, mode, duration_months,
         fee_yearly, fee_semester, fee_total, fee_exam, fee_registration, emi_monthly, scholarship, intakes, deadline, accreditation, recognitions,
         min_qualification, min_rank, min_pct, eligibility, brochure_url, enrollments, search_doc, active, catalog_updated_at, cached_at)
  select p.id, u.id, u.name, u.short_name, coalesce(p.program_name, p.course), p.course, p.specialization, p.level, p.mode,
         coalesce(b2c.num_or_null(p.fee_other ->> 'duration_months')::int, (b2c.num_or_null(p.fee_other ->> 'duration_years') * 12)::int,
                  case when p.fee_total > 0 and p.fee_yearly > 0 then round(p.fee_total / p.fee_yearly * 12)::int end),
         p.fee_yearly, p.fee_semester, p.fee_total, p.fee_exam, p.fee_registration,
         coalesce(b2c.num_or_null(p.fee_other ->> 'emi_monthly'), b2c.num_or_null(p.fee_other ->> 'emi')),
         nullif(p.fee_other ->> 'scholarship', ''),
         coalesce(case jsonb_typeof(p.fee_other -> 'intakes') when 'array' then array(select trim(x) from jsonb_array_elements_text(p.fee_other -> 'intakes') x)
                       when 'string' then array(select trim(x) from regexp_split_to_table(p.fee_other ->> 'intakes', '[,;/]') x where trim(x) <> '') end, '{}'),
         nullif(p.fee_other ->> 'deadline', ''), u.accreditation_text, to_jsonb(u.recognitions),
         p.min_qualification, b2c.qual_rank(p.min_qualification), p.min_pct_general, p.eligibility_text, p.brochure_url,
         (select count(*) from b2c.enrollments e where e.programme_id = p.id and e.status in ('reported', 'verified')),
         coalesce(p.search_doc, to_tsvector('simple', concat_ws(' ', p.program_name, p.course, p.specialization, u.name, u.short_name))),
         p.active, greatest(p.updated_at, u.updated_at), now()
    from public.catalog_programs p join public.catalog_universities u on u.id = p.university_id
  on conflict (id) do update set university_id = excluded.university_id, university = excluded.university, university_short = excluded.university_short,
         name = excluded.name, course = excluded.course, specialization = excluded.specialization, level = excluded.level, mode = excluded.mode,
         duration_months = excluded.duration_months, fee_yearly = excluded.fee_yearly, fee_semester = excluded.fee_semester, fee_total = excluded.fee_total,
         fee_exam = excluded.fee_exam, fee_registration = excluded.fee_registration, emi_monthly = excluded.emi_monthly, scholarship = excluded.scholarship,
         intakes = excluded.intakes, deadline = excluded.deadline, accreditation = excluded.accreditation, recognitions = excluded.recognitions,
         min_qualification = excluded.min_qualification, min_rank = excluded.min_rank, min_pct = excluded.min_pct, eligibility = excluded.eligibility,
         brochure_url = excluded.brochure_url, enrollments = excluded.enrollments, search_doc = excluded.search_doc, active = excluded.active,
         catalog_updated_at = excluded.catalog_updated_at, cached_at = now();
  get diagnostics n = row_count;
  update b2c.programme_cache c set active = false, cached_at = now() where c.active and not exists (select 1 from public.catalog_programs p where p.id = c.id);
  if v_b2b then
    execute $q$
      update b2c.programme_cache c set partners = coalesce((
        select jsonb_agg(jsonb_build_object('partner_id', pa.id, 'name', coalesce(pa.display_name, pa.name), 'commission', pp.commission) order by coalesce(pa.display_name, pa.name))
          from b2b.partner_programmes pp join b2b.partners pa on pa.id = pp.partner_id
         where pp.programme_id = c.id and pp.active and (pp.valid_to is null or pp.valid_to > now())
           and coalesce(pa.status, 'active') = 'active'), '[]'::jsonb)
    $q$;
  end if;
  return n;
end $f$;

/* Eduwit's commission on a programme (the counsellor commission owed to Eduwit): the university rate on the fee. */
create or replace function b2c.programme_commission(p_university bigint, p_programme bigint, p_fee_year numeric, p_fee_total numeric) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare r b2c.university_rates; v_base numeric;
begin
  r := b2c.university_rate_for(p_university, p_programme, current_date);
  if r.id is null then return null; end if;
  v_base := case r.fee_base when 'total' then coalesce(p_fee_total, p_fee_year) else coalesce(p_fee_year, p_fee_total) end;
  return jsonb_build_object('rate_type', r.rate_type, 'value', r.value, 'fee_base', r.fee_base,
    'amount', case r.rate_type when 'percent' then round(v_base * r.value / 100) when 'fixed' then r.value end);
end $f$;

/* One programme as the screens show it; partner and commission figures only for the Admin and Marketing. */
create or replace function b2c.programme_json(c b2c.programme_cache, p_money boolean, p_rank int default null, p_budget numeric default null) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('id', c.id, 'name', c.name, 'course', c.course, 'specialization', c.specialization, 'level', c.level, 'mode', c.mode,
           'university', c.university, 'university_id', c.university_id, 'university_short', c.university_short, 'duration_months', c.duration_months,
           'fee_yearly', c.fee_yearly, 'fee_semester', c.fee_semester, 'fee_total', c.fee_total, 'fee_exam', c.fee_exam, 'fee_registration', c.fee_registration,
           'emi_monthly', c.emi_monthly, 'scholarship', c.scholarship, 'intakes', to_jsonb(c.intakes), 'deadline', c.deadline,
           'accreditation', c.accreditation, 'recognitions', c.recognitions, 'min_qualification', c.min_qualification, 'min_pct', c.min_pct,
           'eligibility', c.eligibility, 'brochure_url', c.brochure_url, 'enrollments', c.enrollments,
           'eligible', case when p_rank is null or c.min_rank is null then null else p_rank >= c.min_rank end,
           'within_budget', case when p_budget is null or coalesce(c.fee_yearly, c.fee_total) is null then null else coalesce(c.fee_yearly, c.fee_total) <= p_budget end)
      || case when p_money then jsonb_build_object('partners', c.partners, 'eduwit_commission', b2c.programme_commission(c.university_id, c.id, c.fee_yearly, c.fee_total)) else '{}'::jsonb end
$f$;

/* The Programme page (B8.9): search, filters, sort, paging; "eligible for this lead" when opened from a lead. */
create or replace function b2c.programme_search(p jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare q text := nullif(trim(p ->> 'q'), ''); v_money boolean := b2c.my_role() in ('admin', 'marketing'); v_lead bigint := nullif(p ->> 'lead', '')::bigint;
        v_rank int; v_budget numeric; v_sort text := coalesce(p ->> 'sort', 'name'); v jsonb; v_total int;
        v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 100), 1), 300); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0);
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_lead is not null then
    if not coalesce(b2c.can_see(v_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
    select b2c.qual_rank(r.record -> 'education' ->> 'highest_qualification'), b2c.num_or_null(r.record -> 'interest' ->> 'annual_budget_inr')
      into v_rank, v_budget from b2c.lead_records r where r.lead_id = v_lead;
  end if;
  if not exists (select 1 from b2c.programme_cache) then perform b2c.programme_cache_refresh(true); end if;
  with f as (
    select c from b2c.programme_cache c
     where c.active
       and (q is null or c.search_doc @@ websearch_to_tsquery('simple', q) or c.name ilike '%' || q || '%' or c.university ilike '%' || q || '%' or c.specialization ilike '%' || q || '%')
       and (p ->> 'level' is null or c.level ilike p ->> 'level')
       and (p ->> 'mode' is null or c.mode ilike p ->> 'mode')
       and (p ->> 'course' is null or c.course ilike '%' || (p ->> 'course') || '%' or c.name ilike '%' || (p ->> 'course') || '%')
       and (p ->> 'university' is null or c.university ilike '%' || (p ->> 'university') || '%' or c.university_short ilike p ->> 'university')
       and (p ->> 'specialization' is null or c.specialization ilike '%' || (p ->> 'specialization') || '%')
       and (p ->> 'fee_max' is null or coalesce(c.fee_total, c.fee_yearly) <= (p ->> 'fee_max')::numeric)
       and (p ->> 'fee_min' is null or coalesce(c.fee_total, c.fee_yearly) >= (p ->> 'fee_min')::numeric)
       and (p ->> 'duration_max' is null or c.duration_months <= (p ->> 'duration_max')::int)
       and (p ->> 'duration_min' is null or c.duration_months >= (p ->> 'duration_min')::int)
       and (p ->> 'intake' is null or exists (select 1 from unnest(c.intakes) i where i ilike '%' || (p ->> 'intake') || '%'))
       and (p ->> 'accreditation' is null or c.accreditation ilike '%' || (p ->> 'accreditation') || '%' or c.recognitions::text ilike '%' || (p ->> 'accreditation') || '%')
       and (p ->> 'emi' is null or not (p ->> 'emi')::boolean or c.emi_monthly is not null)
       and (not coalesce((p ->> 'eligible')::boolean, false) or v_rank is null or c.min_rank is null or v_rank >= c.min_rank))
  select (select count(*) from f),
         coalesce(jsonb_agg(b2c.programme_json(s.c, v_money, v_rank, v_budget) order by s.ord1, s.ord2 nulls last, s.nm, s.fid), '[]')
    into v_total, v
    from (select f.c, case v_sort when 'popularity' then -(f.c).enrollments else 0 end ord1,
                 case v_sort when 'fee' then coalesce((f.c).fee_total, (f.c).fee_yearly) when 'fee_desc' then -coalesce((f.c).fee_total, (f.c).fee_yearly)
                             when 'duration' then (f.c).duration_months end ord2, (f.c).name nm, (f.c).id fid
            from f order by ord1, ord2 nulls last, nm, fid limit v_limit offset v_offset) s;
  return jsonb_build_object('total', v_total, 'rows', v, 'eligible_rank', v_rank, 'budget', v_budget);
end $f$;

/* Filter choices for the Programme page. */
create or replace function b2c.programme_facets() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'universities', (select coalesce(jsonb_agg(distinct university), '[]') from b2c.programme_cache where active),
    'specializations', (select coalesce(jsonb_agg(distinct specialization), '[]') from b2c.programme_cache where active and specialization is not null),
    'levels', (select coalesce(jsonb_agg(distinct level), '[]') from b2c.programme_cache where active and level is not null),
    'modes', (select coalesce(jsonb_agg(distinct mode), '[]') from b2c.programme_cache where active and mode is not null),
    'intakes', (select coalesce(jsonb_agg(distinct i), '[]') from b2c.programme_cache, unnest(intakes) i where active),
    'fee', (select jsonb_build_object('min', min(coalesce(fee_total, fee_yearly)), 'max', max(coalesce(fee_total, fee_yearly))) from b2c.programme_cache where active),
    'duration', (select jsonb_build_object('min', min(duration_months), 'max', max(duration_months)) from b2c.programme_cache where active));
end $f$;

/* Compare 2 to 4 programmes side by side (optionally for a lead's eligibility and budget). */
create or replace function b2c.programme_compare(p_ids bigint[], p_lead bigint default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int; v_budget numeric; v_money boolean := b2c.my_role() in ('admin', 'marketing'); v jsonb;
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(cardinality(p_ids), 0) not between 2 and 4 then raise exception 'compare 2 to 4 programmes'; end if;
  if p_lead is not null then
    if not coalesce(b2c.can_see(p_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
    select b2c.qual_rank(r.record -> 'education' ->> 'highest_qualification'), b2c.num_or_null(r.record -> 'interest' ->> 'annual_budget_inr')
      into v_rank, v_budget from b2c.lead_records r where r.lead_id = p_lead;
  end if;
  select coalesce(jsonb_agg(b2c.programme_json(c, v_money, v_rank, v_budget) order by array_position(p_ids, c.id)), '[]') into v
    from b2c.programme_cache c where c.id = any (p_ids);
  if jsonb_array_length(v) <> cardinality(p_ids) then raise exception 'unknown programme'; end if;
  return v;
end $f$;

/* Programme fit (B8.3): the catalogue ranked against the lead's interest (course 4, specialization 3, university 2,
   mode 1), with eligibility (qualification against the minimum), budget, EMI and duration side by side. */
create or replace function b2c.programme_fit(p_lead bigint, p_limit int default 12) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare l record; v_level text; v_rank int; v_budget numeric; v_money boolean := b2c.my_role() in ('admin', 'marketing');
begin
  if not coalesce(b2c.can_see(p_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  select lower(nullif(trim(v.course), '')) as course, lower(nullif(trim(v.specialization), '')) as spec, lower(nullif(trim(v.university), '')) as uni,
         lower(nullif(trim(v.study_mode), '')) as mode, lower(nullif(trim(v.programme_level), '')) as level, v.qualification
    into l from b2c.leads_v v where v.lead_id = p_lead;
  select b2c.num_or_null(r.record -> 'interest' ->> 'annual_budget_inr') into v_budget from b2c.lead_records r where r.lead_id = p_lead;
  v_rank := b2c.qual_rank(l.qualification);
  v_level := case when l.level in ('pg', 'postgraduate', 'post graduate', 'post-graduate', 'masters', 'master') then 'pg'
                  when l.level in ('ug', 'undergraduate', 'under graduate', 'under-graduate', 'bachelors', 'bachelor') then 'ug'
                  else l.level end;
  if not exists (select 1 from b2c.programme_cache) then perform b2c.programme_cache_refresh(true); end if;
  return jsonb_build_object(
    'interest', jsonb_build_object('course', l.course, 'specialization', l.spec, 'university', l.uni, 'mode', l.mode, 'level', l.level,
                                   'qualification', l.qualification, 'budget', v_budget),
    'rows', (select coalesce(jsonb_agg(b2c.programme_json(s.c, v_money, v_rank, v_budget)
                               || jsonb_build_object('fit', s.fit, 'matched', to_jsonb(array_remove(array[s.m_course, s.m_spec, s.m_uni, s.m_mode], null))) order by s.ord), '[]')
      from (select s1.*, row_number() over (order by s1.fit desc, (s1.ok is false), (s1.in_budget is false), coalesce((s1.c).fee_total, (s1.c).fee_yearly) nulls last, (s1.c).university) ord
              from (select s0.*, case when s0.m_course is not null then 4 else 0 end + case when s0.m_spec is not null then 3 else 0 end
                                 + case when s0.m_uni is not null then 2 else 0 end + case when s0.m_mode is not null then 1 else 0 end as fit,
                           case when v_rank is null or (s0.c).min_rank is null then null else v_rank >= (s0.c).min_rank end ok,
                           case when v_budget is null or coalesce((s0.c).fee_yearly, (s0.c).fee_total) is null then null else coalesce((s0.c).fee_yearly, (s0.c).fee_total) <= v_budget end in_budget
                      from (select c,
                                   case when l.course is not null and (lower(coalesce(c.course, '')) = l.course or position(l.course in lower(coalesce(c.name, ''))) > 0) then 'course' end as m_course,
                                   case when l.spec is not null and position(l.spec in lower(coalesce(c.specialization, ''))) > 0 then 'specialization' end as m_spec,
                                   case when l.uni is not null and (position(l.uni in lower(coalesce(c.university, ''))) > 0 or lower(coalesce(c.university_short, '')) = l.uni) then 'university' end as m_uni,
                                   case when l.mode is not null and lower(coalesce(c.mode, '')) = l.mode then 'mode' end as m_mode
                              from b2c.programme_cache c
                             where c.active and (v_level is null or lower(c.level) = v_level)) s0) s1
             where s1.fit > 0
             order by 2 limit least(greatest(coalesce(p_limit, 12), 1), 50)) s));
end $f$;

-- ---------- Pipeline (C3) ----------
/* Expected commission on an open lead: the enrolment's earnings when there is one, else the university rate on the
   application's fee or on the interested programme's fee (where the university is known). */
create or replace function b2c.lead_expected_value(p_lead bigint) returns numeric language plpgsql stable security definer set search_path = '' as $f$
declare v numeric; a record; c b2c.programme_cache; l record;
begin
  select sum(g.gross) into v from b2c.enrollments e join b2c.earnings g on g.enrollment_id = e.id where e.lead_id = p_lead;
  if v is not null then return v; end if;
  select lower(nullif(trim(x.course), '')) course, lower(nullif(trim(x.university), '')) uni into l from b2c.leads_v x where x.lead_id = p_lead;
  select ap.fee_amount, ap.university into a from b2c.applications ap where ap.lead_id = p_lead and ap.status not in ('withdrawn', 'rejected') order by ap.created_at desc limit 1;
  select * into c from b2c.programme_cache pc
   where pc.active and ((a.university is not null and pc.university ilike '%' || a.university || '%')
                        or (a.university is null and l.uni is not null and (position(l.uni in lower(pc.university)) > 0 or lower(coalesce(pc.university_short, '')) = l.uni)))
     and (l.course is null or lower(coalesce(pc.course, '')) = l.course or position(l.course in lower(coalesce(pc.name, ''))) > 0)
   order by pc.fee_yearly nulls last limit 1;
  if c.id is null then return null; end if;
  return (b2c.programme_commission(c.university_id, c.id, coalesce(a.fee_amount, c.fee_yearly), coalesce(a.fee_amount, c.fee_total)) ->> 'amount')::numeric;
end $f$;

/* The kanban: one column per Eduwit stage, with the count, expected commission and cards in priority order
   (overdue follow-up, hot, SLA at risk, highest expected value). */
create or replace function b2c.pipeline_board(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_owner uuid; v_money boolean;
begin
  if v_role is null or v_role = 'marketing' then raise exception 'not allowed' using errcode = '42501'; end if;
  v_money := true;
  v_owner := case when v_role in ('admin', 'sales_head') then nullif(p ->> 'owner', '')::uuid else me end;
  return (with l as (
      select v.lead_id, v.name, v.course, v.university, v.stage_id, v.sub_stage, v.temperature, v.hot, v.next_task_due_at, v.owner_id, v.owner_name, v.source,
             v.sla_due_at, v.sla_met_at, v.sla_breached_at, v.stage_changed_at, v.is_test,
             coalesce(v.next_task_due_at < now(), false) overdue,
             case when v.sla_breached_at is not null and v.sla_met_at is null then 'red'
                  when v.sla_met_at is null and v.sla_due_at is not null and v.sla_due_at < now() + interval '15 minutes' then 'amber'
                  when v.sla_met_at is null and v.sla_due_at is not null then 'green' end sla,
             b2c.lead_expected_value(v.lead_id) expected
        from b2c.leads_v v
       where v.status = 'active' and v.deleted_at is null and v.stage_id is not null
         and (v_owner is null or v.owner_id = v_owner)
         and (v_role <> 'counsellor' or v.owner_id = me)
         and (coalesce((p ->> 'include_test')::boolean, v_role = 'admin') or not v.is_test)
         and (p ->> 'temperature' is null or v.temperature = p ->> 'temperature')
         and (p ->> 'source' is null or v.source = p ->> 'source')
         and (not coalesce((p ->> 'hot')::boolean, false) or v.hot)
         and (not coalesce((p ->> 'overdue')::boolean, false) or v.next_task_due_at < now())
         and (coalesce(trim(p ->> 'search'), '') = '' or v.name ilike '%' || trim(p ->> 'search') || '%' or v.course ilike '%' || trim(p ->> 'search') || '%'))
    select jsonb_build_object('columns', coalesce(jsonb_agg(jsonb_build_object('stage_id', st.id, 'name', st.name, 'canon', st.canon,
             'count', coalesce(c.n, 0), 'expected', case when v_money then coalesce(c.x, 0) end, 'cards', coalesce(c.cards, '[]')) order by st.id), '[]'))
      from b2c.stages st
      left join lateral (select count(*) n, sum(l.expected) x,
                                (select jsonb_agg(jsonb_build_object('lead_id', k.lead_id, 'name', k.name, 'course', k.course, 'university', k.university, 'sub_stage', k.sub_stage,
                                          'temperature', k.temperature, 'hot', k.hot, 'next_task_due_at', k.next_task_due_at, 'overdue', k.overdue, 'sla', k.sla,
                                          'expected', k.expected, 'owner_name', k.owner_name, 'days_in_stage', floor(extract(epoch from now() - k.stage_changed_at) / 86400)::int)
                                          order by k.overdue desc, k.hot desc, (k.sla in ('red', 'amber')) desc nulls last, k.expected desc nulls last, k.next_task_due_at nulls last)
                                   from (select * from l l2 where l2.stage_id = st.id
                                          order by l2.overdue desc, l2.hot desc, (l2.sla in ('red', 'amber')) desc nulls last, l2.expected desc nulls last limit 100) k) cards
                           from l where l.stage_id = st.id) c on true
     where st.id not in (9, 10) or coalesce((p ->> 'closed')::boolean, false));
end $f$;

-- ---------- Inbox (C5, D3) ----------
/* Every conversation the person may read: counsellors their own leads, the Admin and the sales head all, Marketing all
   read-only. Searches name, number, message text and template name; filters by counsellor, unread, window, awaiting reply. */
create or replace function b2c.inbox_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid(); v_q text := nullif(trim(p ->> 'search'), ''); v_digits text;
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_digits := nullif(regexp_replace(coalesce(v_q, ''), '\D', '', 'g'), '');
  return (select coalesce(jsonb_agg(x order by x ->> 'last_at' desc nulls last), '[]') from (
    select jsonb_build_object('phone', c.phone, 'lead_id', c.lead_id, 'name', v.name, 'course', v.course, 'owner_id', v.owner_id, 'owner_name', v.owner_name,
                              'status', v.status, 'unread', c.unread,
                              'window_open', c.last_inbound_at > now() - interval '24 hours', 'window_closes_at', c.last_inbound_at + interval '24 hours',
                              'awaiting_reply', coalesce(lm.direction = 'in', false),
                              'last_at', greatest(c.last_inbound_at, c.last_outbound_at), 'read_only', v_role = 'marketing',
                              'last', lm.body, 'last_template', lm.template_name, 'last_direction', lm.direction,
                              'match', case when v_q is not null then (select left(m.body, 160) from b2c.wa_messages m where m.phone = c.phone and m.body ilike '%' || v_q || '%' order by m.created_at desc limit 1) end) x
      from b2c.wa_conversations c
      left join b2c.leads_v v on v.lead_id = c.lead_id
      left join lateral (select m.body, m.template_name, m.direction from b2c.wa_messages m where m.phone = c.phone order by m.created_at desc, m.id desc limit 1) lm on true
     where (v_role in ('admin', 'marketing', 'sales_head') or v.owner_id = me)
       and (v_q is null or v.name ilike '%' || v_q || '%' or (v_digits is not null and c.phone like '%' || v_digits || '%')
            or exists (select 1 from b2c.wa_messages m where m.phone = c.phone and (m.body ilike '%' || v_q || '%' or m.template_name ilike '%' || v_q || '%')))
       and (not coalesce((p ->> 'unread')::boolean, false) or c.unread > 0)
       and (p ->> 'owner' is null or v_role = 'counsellor' or (p ->> 'owner' = 'none' and v.owner_id is null) or v.owner_id::text = p ->> 'owner')
       and (p ->> 'window' is null or (p ->> 'window' = 'open') = coalesce(c.last_inbound_at > now() - interval '24 hours', false))
       and (not coalesce((p ->> 'awaiting')::boolean, false) or lm.direction = 'in')
     order by greatest(c.last_inbound_at, c.last_outbound_at) desc nulls last
     limit least(coalesce((p ->> 'limit')::int, 200), 500)) q);
end $f$;

-- ---------- Sales email library (C4) ----------
/* The shared library: author, uses, reply rate (an inbound email on the same thread after a send). Hidden templates
   only for the Admin and their author. */
create or replace function b2c.email_library(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.require('templates_sales_email'); v_admin boolean := b2c.my_role() = 'admin';
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'category', t.category, 'subject', t.subject, 'body', t.body,
             'attachments', t.attachments, 'parent_id', t.parent_id, 'version', t.version, 'recommended', t.recommended, 'hidden', t.hidden,
             'owner_id', t.owner_id, 'author', u.full_name, 'mine', t.owner_id = me, 'uses', s.sent, 'replies', s.replied,
             'reply_rate', case when s.sent > 0 then round(100.0 * s.replied / s.sent) end, 'updated_at', t.updated_at)
             order by t.recommended desc, case when s.sent >= 5 then s.replied::numeric / s.sent end desc nulls last, t.updated_at desc), '[]')
    from b2c.sales_email_templates t
    left join b2c.users u on u.user_id = t.owner_id
    left join lateral (select count(*)::int sent,
                              count(*) filter (where exists (select 1 from b2c.emails i where i.direction = 'in' and i.thread_id = e.thread_id and e.thread_id is not null
                                                                and i.created_at > e.created_at))::int replied
                         from b2c.emails e where e.template_id = t.id and e.direction = 'out') s on true
   where t.deleted_at is null and (not t.hidden or v_admin or t.owner_id = me)
     and (p ->> 'category' is null or t.category = p ->> 'category')
     and (not coalesce((p ->> 'mine')::boolean, false) or t.owner_id = me)
     and (coalesce(trim(p ->> 'search'), '') = '' or t.name ilike '%' || trim(p ->> 'search') || '%' or t.subject ilike '%' || trim(p ->> 'search') || '%'));
end $f$;

/* Every merge field a sales email or WhatsApp message may use, from the lead, its best-fitting programme and the counsellor. */
create or replace function b2c.merge_values(p_lead bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); u b2c.users; v jsonb; f jsonb; t timestamptz;
begin
  if not coalesce(b2c.can_see(p_lead), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into u from b2c.users where user_id = coalesce((select owner_id from b2c.leads_state where lead_id = p_lead), me);
  f := b2c.programme_fit(p_lead, 1) -> 'rows' -> 0;
  select min(due_at) into t from b2c.tasks where lead_id = p_lead and status = 'open';
  select jsonb_build_object(
      'first_name', b2c.first_name(p_lead),
      'programme', coalesce(nullif(x.course, ''), f ->> 'name', 'your programme'),
      'university', coalesce(nullif(x.university, ''), f ->> 'university', 'the university'),
      'fee', case when f ->> 'fee_yearly' is not null then 'Rs ' || to_char((f ->> 'fee_yearly')::numeric, 'FM99,99,99,999') || ' a year'
                  when f ->> 'fee_total' is not null then 'Rs ' || to_char((f ->> 'fee_total')::numeric, 'FM99,99,99,999') || ' in all' end,
      'emi', case when f ->> 'emi_monthly' is not null then 'Rs ' || to_char((f ->> 'emi_monthly')::numeric, 'FM99,99,99,999') || ' a month' end,
      'brochure_link', f ->> 'brochure_url',
      'counsellor_name', coalesce(u.full_name, u.email),
      'counsellor_first_name', split_part(coalesce(u.full_name, u.email, ''), ' ', 1),
      'counsellor_number', u.phone,
      'followup_time', case when t is not null then to_char(t at time zone 'Asia/Kolkata', 'FMDD Mon, FMHH12:MI AM') end)
    into v from b2c.leads_v x where x.lead_id = p_lead;
  return jsonb_strip_nulls(v);
end $f$;

-- ---------- WhatsApp to a person's own number (C7, D5) ----------
alter table b2c.users add column if not exists wa_alerts text[] not null default '{}';
alter table b2c.notifications add column if not exists wa_at timestamptz;
insert into b2c.settings (key, value) values ('staff_alerts', '{"template": "staff_alert", "kinds": ["reminder", "overdue", "sla_breach", "escalation", "assignment", "neglect", "metric_alert"]}')
on conflict (key) do nothing;

/* Which alerts a person also wants on WhatsApp (their own number from Teams). */
create or replace function b2c.my_wa_alerts_set(p_kinds text[]) returns text[] language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_allowed text[];
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  select array(select jsonb_array_elements_text(b2c.setting('staff_alerts') -> 'kinds')) into v_allowed;
  if exists (select 1 from unnest(coalesce(p_kinds, '{}')) k where not k = any (v_allowed)) then raise exception 'unknown alert'; end if;
  if cardinality(coalesce(p_kinds, '{}')) > 0 and coalesce(b2c.norm_phone((select phone from b2c.users where user_id = me)), '') = '' then
    raise exception 'add your mobile number in Teams first';
  end if;
  update b2c.users set wa_alerts = coalesce(p_kinds, '{}'), updated_at = now() where user_id = me;
  return coalesce(p_kinds, '{}');
end $f$;

/* Every minute: new notifications of the kinds a person chose go to their own number, through the approved staff template.
   Without an approved template nothing is sent (the Connectors page says so). */
create or replace function b2c.staff_wa_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare s jsonb := b2c.setting('staff_alerts'); t b2c.wa_templates; r record; n int := 0; v_base text := b2c.setting('app') ->> 'base_url';
begin
  select * into t from b2c.wa_templates where name = s ->> 'template' and status = 'approved' and archived_at is null order by version desc limit 1;
  if t.id is null then return jsonb_build_object('sent', 0, 'why', 'no approved staff template'); end if;
  for r in select n.id, n.title, n.body, n.link, b2c.norm_phone(u.phone) phone from b2c.notifications n join b2c.users u on u.user_id = n.user_id
            where n.wa_at is null and n.created_at > now() - interval '15 minutes' and n.kind = any (u.wa_alerts) and u.is_active
              and coalesce(b2c.norm_phone(u.phone), '') <> '' order by n.id limit 200 for update of n skip locked loop
    insert into b2c.send_queue (channel, lead_id, to_address, payload, purpose, dedupe_key)
    values ('whatsapp', null, r.phone, jsonb_build_object('type', 'template', 'template', jsonb_build_object('name', t.name, 'language', t.language,
            'params', (select coalesce(jsonb_agg(case o when 1 then left(r.title, 200) when 2 then left(coalesce(r.body, ''), 300)
                                                                 else coalesce(v_base, '') || coalesce(r.link, '') end order by o), '[]')
                         from jsonb_array_elements_text(t.variables) with ordinality x(v, o)))), 'staff_alert', 'staffwa:' || r.id)
    on conflict do nothing;
    update b2c.notifications set wa_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('sent', n);
end $f$;

-- ---------- custom profile fields (C9) ----------
alter table b2c.leads_state add column if not exists custom jsonb not null default '{}'::jsonb;
insert into b2c.settings (key, value) values ('custom_fields', '{"fields": []}') on conflict (key) do nothing;

/* The Admin defines the fields: [{key, label, type: text|number|date|select|yes_no, options}] (versioned like every setting). */
create or replace function b2c.custom_fields_save(p_fields jsonb, p_reason text) returns int language plpgsql security definer set search_path = '' as $f$
declare x jsonb;
begin
  perform b2c.require('settings');
  if jsonb_typeof(p_fields) <> 'array' or jsonb_array_length(p_fields) > 30 then raise exception 'at most 30 fields'; end if;
  for x in select * from jsonb_array_elements(p_fields) loop
    if coalesce(x ->> 'key', '') !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'field keys are lower-case letters, digits and _'; end if;
    if coalesce(trim(x ->> 'label'), '') = '' then raise exception 'every field needs a label'; end if;
    if coalesce(x ->> 'type', '') not in ('text', 'number', 'date', 'select', 'yes_no') then raise exception 'unknown field type %', x ->> 'type'; end if;
    if x ->> 'type' = 'select' and jsonb_array_length(coalesce(x -> 'options', '[]')) = 0 then raise exception '% needs its choices', x ->> 'label'; end if;
  end loop;
  if (select count(distinct y ->> 'key') from jsonb_array_elements(p_fields) y) <> jsonb_array_length(p_fields) then raise exception 'two fields share a key'; end if;
  return b2c.set_setting('custom_fields', jsonb_build_object('fields', p_fields), p_reason);
end $f$;

create or replace function b2c.custom_field_set(p_lead bigint, p_key text, p_value text) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); d jsonb; v jsonb; v_old jsonb;
begin
  select x into d from jsonb_array_elements(b2c.setting('custom_fields') -> 'fields') x where x ->> 'key' = p_key;
  if d is null then raise exception 'unknown field'; end if;
  if nullif(trim(p_value), '') is null then v := null;
  else
    v := case d ->> 'type'
      when 'number' then to_jsonb(b2c.num_or_null(p_value))
      when 'date' then to_jsonb(p_value::date::text)
      when 'yes_no' then to_jsonb(lower(p_value) in ('yes', 'true', '1'))
      else to_jsonb(left(trim(p_value), 300)) end;
    if d ->> 'type' = 'select' and not exists (select 1 from jsonb_array_elements_text(d -> 'options') o where o = p_value) then raise exception 'choose one of the options'; end if;
    if d ->> 'type' = 'number' and v = 'null'::jsonb then raise exception 'enter a number'; end if;
  end if;
  select custom -> p_key into v_old from b2c.leads_state where lead_id = p_lead for update;
  if v_old is not distinct from v then return (select custom from b2c.leads_state where lead_id = p_lead); end if;
  update b2c.leads_state set custom = case when v is null then custom - p_key else custom || jsonb_build_object(p_key, v) end, updated_at = now() where lead_id = p_lead;
  insert into b2c.field_history (lead_id, field, old_value, new_value, kind, actor_id) values (p_lead, 'custom.' || p_key, v_old, v, 'human_correction', me);
  return (select custom from b2c.leads_state where lead_id = p_lead);
end $f$;

-- ---------- document checklists (C10, D4) and opening documents ----------
/* The Admin edits a university's checklist ('*' is the default list); each change is kept in the audit log. */
create or replace function b2c.checklist_save(p_university text, p_items text[], p_reason text default null) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v_old jsonb; v_items jsonb;
begin
  if coalesce(trim(p_university), '') = '' then raise exception 'name the university (or * for the default list)'; end if;
  select coalesce(jsonb_agg(trim(x)), '[]') into v_items from (select distinct on (lower(trim(x))) x from unnest(coalesce(p_items, '{}')) x where trim(x) <> '') q;
  select items into v_old from b2c.document_checklists where university = trim(p_university);
  if jsonb_array_length(v_items) = 0 and trim(p_university) = '*' then raise exception 'the default list cannot be empty'; end if;
  insert into b2c.document_checklists (university, items) values (trim(p_university), v_items)
  on conflict (university) do update set items = excluded.items;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'checklist_changed', jsonb_build_object('university', trim(p_university), 'old', v_old, 'new', v_items, 'reason', p_reason));
end $f$;

create or replace function b2c.checklists() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'lists', (select coalesce(jsonb_agg(jsonb_build_object('university', c.university, 'items', c.items) order by c.university <> '*', c.university), '[]') from b2c.document_checklists c),
    'history', case when b2c.my_role() = 'admin' then (select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'by', u.full_name, 'detail', a.detail) order by a.at desc), '[]')
                    from (select * from b2c.audit_log where action = 'checklist_changed' order by at desc limit 50) a left join b2c.users u on u.user_id = a.actor_id) end);
end $f$;

/* A stored document, for a signed link: anyone who may see the lead (counsellors their own leads). Logged. */
create or replace function b2c.document_open(p_document bigint) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare d b2c.documents;
begin
  select * into d from b2c.documents where id = p_document and removed_at is null;
  if d.id is null or not coalesce(b2c.can_see(d.lead_id), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (b2c.uid(), 'document_open', d.lead_id, jsonb_build_object('document', d.id));
  return jsonb_build_object('bucket', 'b2c-documents', 'path', d.storage_path, 'filename', coalesce(d.file_name, d.kind));
end $f$;

-- ---------- SLA by source and neglect (C11) ----------
alter table b2c.leads_state add column if not exists neglect_alerted_at timestamptz;
update b2c.settings set value = value || '{"by_source": {}}' where key = 'sla_minutes' and not value ? 'by_source';

/* First-contact minutes: by source when the Admin set one ({"by_source": {"website": {"hot": 10, "warm": 120}}}), else by temperature. */
create or replace function b2c.sla_minutes_for(p_lead bigint, p_hot boolean, p_temperature text, p_default int) returns int language sql stable security definer set search_path = '' as $f$
  select coalesce(b2c.num_or_null(b2c.setting('sla_minutes') -> 'by_source' -> (select r.record -> 'source' ->> 'lead_source' from b2c.lead_records r where r.lead_id = p_lead)
                    ->> case when p_hot then 'hot' else coalesce(nullif(p_temperature, ''), 'warm') end)::int, p_default)
$f$;

/* Leads untouched for 48 hours (setting followups.untouched_hours) are flagged to the counsellor and the Admin once per spell. */
create or replace function b2c.neglect_tick() returns int language plpgsql security definer set search_path = '' as $f$
declare h int := coalesce((b2c.setting('followups') ->> 'untouched_hours')::int, 48); r record; n int := 0;
begin
  for r in select s.lead_id, s.owner_id, s.is_test, coalesce(s.last_activity_at, s.assigned_at) last_at from b2c.leads_state s
            where s.status = 'active' and s.owner_id is not null and s.deleted_at is null and s.stage_id not in (9, 10)
              and coalesce(s.last_activity_at, s.assigned_at) < now() - make_interval(hours => h)
              and (s.neglect_alerted_at is null or s.neglect_alerted_at < coalesce(s.last_activity_at, s.assigned_at))
            limit 300 loop
    perform b2c.notify(r.owner_id, 'neglect', 'Untouched for ' || h || ' hours', 'Work this lead today.', '/s/leads/' || r.lead_id, r.lead_id, 'neglect:' || r.lead_id || ':' || extract(epoch from r.last_at)::bigint);
    if not r.is_test then
      perform b2c.notify_admins('neglect', 'Lead untouched for ' || h || ' hours', null, '/w/leads/' || r.lead_id, r.lead_id, 'neglect:' || r.lead_id || ':' || extract(epoch from r.last_at)::bigint, false);
    end if;
    update b2c.leads_state set neglect_alerted_at = now() where lead_id = r.lead_id;
    n := n + 1;
  end loop;
  return n;
end $f$;

select b2c.programme_cache_refresh(true);

-- ---------- timers ----------
do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-programme-cache') then
    perform cron.schedule('b2c-programme-cache', '*/15 * * * *', 'select b2c.programme_cache_refresh(false)');
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-staff-alerts') then
    perform cron.schedule('b2c-staff-alerts', '* * * * *', 'select b2c.staff_wa_tick()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'b2c-neglect') then
    perform cron.schedule('b2c-neglect', '7,37 * * * *', 'select b2c.neglect_tick()');
  end if;
end $d$;

-- ---------- redefined: assignment uses the SLA by source (b4 body otherwise unchanged) ----------
CREATE OR REPLACE FUNCTION b2c.assign(p_lead bigint, p_user uuid, p_decision bigint, p_trigger text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare
  s b2c.leads_state; u b2c.users; v_sub text; v_sla int; v_due timestamptz; v_start timestamptz; v_in_hours boolean; v_name text;
  m jsonb := b2c.setting('sla_minutes');
begin
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  select * into u from b2c.users where user_id = p_user;
  update b2c.assignments set ended_at = now(), end_reason = coalesce(p_reason, p_trigger) where lead_id = p_lead and ended_at is null;
  insert into b2c.assignments (lead_id, user_id, decision_id, trigger, reason, by_user) values (p_lead, p_user, p_decision, p_trigger, p_reason, b2c.uid());
  v_sub := case p_trigger when 'reengaged' then 'Re-engaged from nurture' when 're_enquiry' then 'Re-enquiry' when 'created' then 'Created by me'
                          when 'returned_from_partners' then 'Returned from partners' else 'Fresh assignment' end;
  v_sla := case when s.hot or p_trigger = 'reengaged' then (m ->> 'hot')::int
                when coalesce(s.temperature, '') = 'warm' then (m ->> 'warm')::int else coalesce((m ->> 'cold')::int, 1440) end;
  if s.temperature is null and not s.hot and p_trigger <> 'reengaged' then v_sla := (m ->> 'warm')::int; end if;
  v_sla := b2c.sla_minutes_for(p_lead, s.hot or p_trigger = 'reengaged', s.temperature, v_sla);
  v_in_hours := b2c.working_now(p_user, now());
  v_start := coalesce(b2c.next_working_at(p_user, now()), now());
  v_due := coalesce(b2c.add_working_minutes(p_user, now(), v_sla), now() + make_interval(mins => v_sla));
  update b2c.leads_state set
    owner_id = p_user, assigned_at = now(), status = 'active',
    previous_owner_id = case when s.owner_id is distinct from p_user then coalesce(s.owner_id, s.previous_owner_id) else s.previous_owner_id end,
    stage_id = case when s.stage_id is null or s.stage_id in (9, 10) or p_trigger in ('reengaged', 'created') then 1 else s.stage_id end,
    sub_stage = case when s.stage_id is null or s.stage_id in (9, 10) or p_trigger in ('reengaged', 'created') then v_sub else s.sub_stage end,
    stage_changed_at = case when s.stage_id is null or s.stage_id in (9, 10) or p_trigger in ('reengaged', 'created') then now() else s.stage_changed_at end,
    hot = s.hot or p_trigger = 'reengaged',
    reengaged_at = case when p_trigger = 'reengaged' then now() else s.reengaged_at end,
    journey = null,
    sla_due_at = case when s.first_contacted_at is null or p_trigger = 'reengaged' then v_due else s.sla_due_at end,
    sla_met_at = case when p_trigger = 'reengaged' then null else s.sla_met_at end,
    sla_breached_at = case when p_trigger = 'reengaged' then null else s.sla_breached_at end,
    next_task_due_at = v_due, updated_at = now()
  where lead_id = p_lead;
  update b2c.tasks set owner_id = p_user where lead_id = p_lead and status = 'open';
  insert into b2c.tasks (lead_id, owner_id, kind, title, due_at, suggested, source)
  select p_lead, p_user, 'call', case when s.handling ->> 'first_contact_script' = 'neutral_adviser' then 'First call: neutral-adviser opening' else 'First call' end,
         v_due, false, 'assignment'
   where not exists (select 1 from b2c.tasks t where t.lead_id = p_lead and t.status = 'open' and t.kind = 'call');
  select st.name into v_name from b2c.stages st join b2c.leads_state x on x.stage_id = st.id where x.lead_id = p_lead;
  perform b2c.queue_update(p_lead, jsonb_build_object(
    'owner_user_id', p_user, 'owner_name', u.full_name, 'assigned_at', now(), 'stage', 'assigned', 'stage_changed_at', now(),
    'sub_stage', left(v_sub, 80), 'b2c_stage', v_name, 'b2c_sub_stage', v_sub, 'next_task_due_at', v_due), false);
  insert into b2c.activities (lead_id, kind, body, meta, actor_id, at)
  values (p_lead, 'assignment', 'Assigned to ' || coalesce(u.full_name, u.email) || coalesce(' (' || p_reason || ')', ''),
          jsonb_build_object('decision_id', p_decision, 'trigger', p_trigger), b2c.uid(), now());
  perform b2c.notify(p_user, case when p_trigger = 'reengaged' then 'reengaged' else 'assigned' end,
                     case when p_trigger = 'reengaged' then 'Hot: a nurtured lead re-engaged' else 'New lead assigned' end,
                     coalesce(s.reengage_trigger, s.handoff_reason), '/s/leads/' || p_lead, p_lead, 'assign:' || p_lead || ':' || coalesce(p_decision, 0));
  perform b2c.queue_assignment_message(p_lead, p_user, v_in_hours, v_start);
end $f$;

-- ---------- redefined: share up to 4 programmes, as the comparison allows (b11 body otherwise unchanged) ----------
CREATE OR REPLACE FUNCTION b2c.programme_share(p_lead bigint, p_programmes bigint[], p_channel text, p_note text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare me uuid := b2c.require_lead(p_lead); v bigint; v_items jsonb; v_names text;
begin
  if p_channel is null or p_channel not in ('whatsapp', 'email', 'call', 'meeting') then raise exception 'say how the programme was shared'; end if;
  if coalesce(cardinality(p_programmes), 0) = 0 then raise exception 'choose at least one programme'; end if;
  if cardinality(p_programmes) > 4 then raise exception 'share at most 4 programmes at a time'; end if;
  select jsonb_agg(jsonb_build_object('id', pr.id, 'name', coalesce(pr.program_name, pr.course), 'university', un.name) order by array_position(p_programmes, pr.id)),
         string_agg(coalesce(pr.program_name, pr.course) || ' (' || un.name || ')', ', ' order by array_position(p_programmes, pr.id))
    into v_items, v_names
    from public.catalog_programs pr join public.catalog_universities un on un.id = pr.university_id
   where pr.id = any (p_programmes);
  if v_items is null or jsonb_array_length(v_items) <> cardinality(p_programmes) then raise exception 'unknown programme'; end if;
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id)
  values (p_lead, 'programme_shared', case when p_channel in ('whatsapp', 'email') then 'out' end,
          case p_channel when 'call' then 'Explained on a call: ' when 'meeting' then 'Explained in a meeting: '
                         when 'whatsapp' then 'Shared on WhatsApp: ' else 'Shared by email: ' end || v_names
            || coalesce(E'\n' || nullif(trim(p_note), ''), ''),
          jsonb_build_object('programmes', v_items, 'channel', p_channel), me)
  returning id into v;
  update b2c.leads_state set last_activity_at = now() where lead_id = p_lead;
  return v;
end $f$;

-- ---------- redefined: the lead screen also gets done tasks, custom fields, partner history and documents (b5 body otherwise unchanged) ----------
CREATE OR REPLACE FUNCTION b2c.lead_detail(p_lead bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $f$
declare v jsonb;
begin
  if not b2c.can_see(p_lead) then raise exception 'not allowed' using errcode = '42501'; end if;
  select jsonb_build_object(
    'lead', (select to_jsonb(x) from b2c.leads_v x where x.lead_id = p_lead),
    'record', (select r.record from b2c.lead_records r where r.lead_id = p_lead),
    'pending', b2c.pending_set(p_lead),
    'contacts', (select coalesce(jsonb_agg(to_jsonb(c) order by c.origin = 'intake' desc, c.created_at), '[]') from b2c.lead_contacts c where c.lead_id = p_lead and c.removed_at is null),
    'tasks', (select coalesce(jsonb_agg(to_jsonb(t) order by t.due_at), '[]') from b2c.tasks t where t.lead_id = p_lead and t.status = 'open'),
    'timeline', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'direction', a.direction, 'outcome', a.outcome, 'body', a.body,
                                 'internal', a.internal, 'at', a.at, 'actor', (select u.full_name from b2c.users u where u.user_id = a.actor_id), 'meta', a.meta) order by a.at desc), '[]')
                  from (select * from b2c.activities a where a.lead_id = p_lead and (not a.internal or b2c.my_role() in ('admin', 'sales_head')) order by a.at desc limit 150) a),
    'unlogged_call', (select to_jsonb(c) from b2c.calls c where c.lead_id = p_lead and c.logged_at is null and c.user_id = b2c.uid() order by c.tapped_at desc limit 1),
    'applications', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]') from b2c.applications a where a.lead_id = p_lead),
    'enrollments', (select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at), '[]') from b2c.enrollments e where e.lead_id = p_lead),
    'decision', (select to_jsonb(d) from b2c.allocation_decisions d where d.lead_id = p_lead and not d.simulated order by d.at desc limit 1),
    'consent_request', (select to_jsonb(q) from b2c.consent_requests q where q.lead_id = p_lead order by q.created_at desc limit 1),
    'history', (select coalesce(jsonb_agg(to_jsonb(h) order by h.at desc), '[]') from b2c.field_history h where h.lead_id = p_lead),
    'done_tasks', (select coalesce(jsonb_agg(to_jsonb(t) order by t.done_at desc), '[]') from (select * from b2c.tasks t where t.lead_id = p_lead and t.status <> 'open' order by t.done_at desc nulls last limit 30) t),
    'custom_fields', b2c.setting('custom_fields') -> 'fields',
    'custom', (select s.custom from b2c.leads_state s where s.lead_id = p_lead),
    'partner', (select jsonb_build_object('lost', s.partner_lost, 'tried', s.partners_tried, 'flagged', s.flagged, 'routing_requested_at', s.routing_requested_at)
                  from b2c.leads_state s where s.lead_id = p_lead),
    'documents', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'application_id', d.application_id, 'kind', d.kind, 'file_name', d.file_name, 'source', d.source, 'created_at', d.created_at) order by d.created_at desc), '[]')
                    from b2c.documents d where d.lead_id = p_lead and d.removed_at is null))
  into v;
  return v;
end $f$;

-- ---------- grants ----------
grant execute on function b2c.wa_queue_media(bigint, text, text, text, text, text), b2c.wa_media_open(bigint), b2c.wa_media_attach(bigint, bigint, text),
  b2c.programme_search(jsonb), b2c.programme_facets(), b2c.programme_compare(bigint[], bigint), b2c.programme_fit(bigint, integer), b2c.pipeline_board(jsonb),
  b2c.inbox_list(jsonb), b2c.email_library(jsonb), b2c.merge_values(bigint), b2c.my_wa_alerts_set(text[]), b2c.custom_fields_save(jsonb, text),
  b2c.custom_field_set(bigint, text, text), b2c.checklist_save(text, text[], text), b2c.checklists(), b2c.document_open(bigint),
  b2c.programme_share(bigint, bigint[], text, text), b2c.lead_detail(bigint) to authenticated;
grant execute on function b2c.wa_media_take(integer), b2c.wa_media_stored(bigint, text, text), b2c.programme_cache_refresh(boolean), b2c.staff_wa_tick(),
  b2c.neglect_tick() to service_role;
revoke execute on function b2c.wa_media_take(integer), b2c.wa_media_stored(bigint, text, text), b2c.programme_cache_refresh(boolean), b2c.staff_wa_tick(),
  b2c.neglect_tick(), b2c.num_or_null(text), b2c.programme_commission(bigint, bigint, numeric, numeric), b2c.programme_json(b2c.programme_cache, boolean, integer, numeric),
  b2c.lead_expected_value(bigint), b2c.sla_minutes_for(bigint, boolean, text, integer), b2c.assign(bigint, uuid, bigint, text, text) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
