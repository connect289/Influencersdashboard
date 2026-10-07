-- M17c: the Excel/CSV import wizard (spec B4.1). The browser reads the file and sends its rows in chunks; everything
-- else happens here.
--   import_create        step 1–2: a job with the file name and the column mapping (optionally saved as a template)
--   import_stage_rows    rows in chunks of at most 2,000: mapped, normalised, checked, de-duplication previewed
--   import_preview       step 3–4: counts (new, merge, reopen, blocked, test, invalid), problems, rows to download
--   import_courses       step 3: each course as written, with its catalogue match and confidence, for the confirm step
--   (commit, the batch writer and rollback are in m17d)
-- Every lead goes through lead_intake() (source_system 'import'), so de-duplication, reopen and attribution are the same
-- as for every other source. The routing choice is recorded as an intake directive (m17a).

/* The import fields a file column can map to, and the lead_intake name each one is written as. */
create or replace function b2b.import_fields()
returns jsonb language sql immutable set search_path = '' as $fn$
  select '{"full_name":"full_name","first_name":null,"last_name":null,"phone":"phone","email":"email","alternate_phone":"alternate_phone",
           "city":"city","state":"state","country":"country","course":"interested_course","specialization":"interested_specialization",
           "university":"interested_university","programme_level":"programme_level","study_mode":"study_mode_preference",
           "highest_qualification":"highest_qualification","academic_score":"academic_score_raw","work_experience":"work_experience_raw",
           "annual_budget":"annual_budget_raw","enrollment_timeline":"enrollment_timeline","preferred_language":"preferred_language",
           "guardian_name":"guardian_name","guardian_phone":"guardian_phone","enquirer_relation":"enquirer_relation",
           "preferred_call_time":"preferred_call_time","notes":"notes","utm_source":"utm_source","utm_medium":"utm_medium",
           "utm_campaign":"utm_campaign","utm_content":"utm_content","utm_term":"utm_term","campaign":"campaign",
           "source_detail":"source_detail","referral_code":"referral_code"}'::jsonb;
$fn$;

create or replace function b2b.import_create(p jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_map jsonb := coalesce(p -> 'mapping', '{}');
  v_fields jsonb := b2b.import_fields();
  v_tpl bigint;
  v_id bigint;
  k text;
  v text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p ->> 'file_name', ''))) = 0 then raise exception 'the file name is missing' using errcode = '22023'; end if;
  if jsonb_typeof(v_map) <> 'object' then raise exception 'the column mapping is missing' using errcode = '22023'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(v_map) loop
    if v is not null and v <> 'ignore' and not (v_fields ? v) then raise exception 'unknown lead field: %', v using errcode = '22023'; end if;
  end loop;
  if not exists (select 1 from jsonb_each_text(v_map) x where x.value = 'phone') then
    raise exception 'map a column to the phone number' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_each_text(v_map) x where x.value not in ('ignore') group by x.value order by 1 desc limit 1) > 1 then
    raise exception 'each lead field can be mapped from one column only' using errcode = '22023';
  end if;
  if nullif(trim(p ->> 'template_name'), '') is not null then
    insert into b2b.import_templates (name, mapping, used_at) values (left(trim(p ->> 'template_name'), 80), v_map, now())
    on conflict (name) do update set mapping = excluded.mapping, used_at = now()
    returning id into v_tpl;
  elsif (p ->> 'template_id') is not null then
    update b2b.import_templates set used_at = now() where id = (p ->> 'template_id')::bigint returning id into v_tpl;
  end if;
  insert into b2b.imports (file_name, mapping, template_id, created_by)
  values (left(trim(p ->> 'file_name'), 200), v_map, v_tpl, b2b.actor() ->> 'id')
  returning id into v_id;
  perform b2b.log_event('import.created', null, null, null, jsonb_build_object('import_id', v_id, 'file_name', p ->> 'file_name'));
  return v_id;
end $fn$;

/* One raw row (an object keyed by file column) as lead fields, normalised, with its problems. */
create or replace function b2b.import_map_row(p_map jsonb, p_raw jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  v_fields jsonb := b2b.import_fields();
  o jsonb := '{}';
  pr text[] := '{}';
  k text;
  f text;
  v text;
  v_first text;
  v_last text;
  v_phone text;
begin
  for k, f in select key, value #>> '{}' from jsonb_each(p_map) loop
    continue when f is null or f = 'ignore';
    v := nullif(trim(regexp_replace(coalesce(p_raw ->> k, ''), '\s+', ' ', 'g')), '');
    continue when v is null;
    if f = 'first_name' then v_first := v;
    elsif f = 'last_name' then v_last := v;
    else o := o || jsonb_build_object(f, left(v, 500));
    end if;
  end loop;
  if o ->> 'full_name' is null and coalesce(v_first, v_last) is not null then
    o := o || jsonb_build_object('full_name', trim(concat_ws(' ', v_first, v_last)));
  end if;
  if o ? 'full_name' then o := jsonb_set(o, '{full_name}', to_jsonb(initcap(lower(o ->> 'full_name')))); end if;
  v_phone := public.crm_norm_phone(o ->> 'phone');
  if v_phone is null then pr := array_append(pr, 'no phone');
  else
    o := jsonb_set(o, '{phone}', to_jsonb(v_phone));
    if not b2b.is_test_phone(v_phone) and b2b.phone_problem(v_phone) is not null then pr := array_append(pr, replace(b2b.phone_problem(v_phone), '_', ' ')); end if;
  end if;
  if o ? 'email' then
    if lower(o ->> 'email') ~ '^[a-z0-9._%+''-]+@[a-z0-9.-]+\.[a-z]{2,}$' then o := jsonb_set(o, '{email}', to_jsonb(lower(o ->> 'email')));
    else pr := array_append(pr, 'invalid email (dropped)'); o := o - 'email'; end if;
  end if;
  if o ? 'alternate_phone' then
    if public.crm_norm_phone(o ->> 'alternate_phone') is null then o := o - 'alternate_phone';
    else o := jsonb_set(o, '{alternate_phone}', to_jsonb(public.crm_norm_phone(o ->> 'alternate_phone'))); end if;
  end if;
  if o ? 'guardian_phone' then
    if public.crm_norm_phone(o ->> 'guardian_phone') is null then o := o - 'guardian_phone';
    else o := jsonb_set(o, '{guardian_phone}', to_jsonb(public.crm_norm_phone(o ->> 'guardian_phone'))); end if;
  end if;
  if o ->> 'course' is null then pr := array_append(pr, 'no course'); end if;
  return jsonb_build_object('lead', o, 'phone', v_phone, 'problems', to_jsonb(pr));
end $fn$;

/* Rows p_start_row, p_start_row + 1, … of the file (row 1 is the first data row). At most 2,000 per call. */
create or replace function b2b.import_stage_rows(p_import_id bigint, p_start_row int, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  i b2b.imports;
  v_max int := coalesce((select (value ->> 'import_max_rows')::int from b2b.settings where key = 'intake'), 50000);
  n int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into i from b2b.imports where id = p_import_id for update;
  if i.id is null then raise exception 'import not found' using errcode = 'P0002'; end if;
  if i.status <> 'staging' then raise exception 'this import is no longer being prepared' using errcode = '22023'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 2000 then raise exception 'send at most 2,000 rows at a time' using errcode = '22023'; end if;
  if p_start_row < 1 or p_start_row + jsonb_array_length(p_rows) - 1 > v_max then
    raise exception 'an import holds at most % rows', v_max using errcode = '22023';
  end if;

  insert into b2b.import_rows (import_id, row_no, raw, lead, phone, problems)
  select i.id, p_start_row + (r.ord - 1)::int, r.raw, m -> 'lead', m ->> 'phone', array(select jsonb_array_elements_text(m -> 'problems'))
    from jsonb_array_elements(p_rows) with ordinality r(raw, ord)
    cross join lateral b2b.import_map_row(i.mapping, r.raw) m
   where jsonb_typeof(r.raw) = 'object'
  on conflict (import_id, row_no) do update set raw = excluded.raw, lead = excluded.lead, phone = excluded.phone, problems = excluded.problems,
                                                 preview = null, existing_lead_id = null;
  get diagnostics n = row_count;

  -- de-duplication preview for the rows just staged
  update b2b.import_rows x
     set preview = case
           when x.phone is null or 'invalid phone' = any (x.problems) then 'invalid'
           when 'blocked phone' = any (x.problems) then 'blocked'
           when b2b.is_test_phone(x.phone) then 'test'
           when exists (select 1 from b2b.import_rows y where y.import_id = x.import_id and y.phone = x.phone and y.row_no < x.row_no) then 'duplicate_in_file'
           when f.id is null then 'new'
           when f.stage = 'lost' or f.enrollment_status is not null then 'reopen'
           else 'merge' end,
         existing_lead_id = f.id
    from (select y.id from b2b.import_rows y
           where y.import_id = i.id and y.row_no between p_start_row and p_start_row + jsonb_array_length(p_rows) - 1) z
    left join lateral (select l.id, l.stage, l.enrollment_status from public.student_leads l, b2b.import_rows y2   -- as public.crm_find_lead
                        where y2.id = z.id and regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') = y2.phone
                          and l.deleted_at is null and l.merged_into_id is null
                        order by l.created_at desc limit 1) f on true
   where x.id = z.id;

  update b2b.imports set total_rows = (select count(*) from b2b.import_rows where import_id = i.id) where id = i.id;
  return jsonb_build_object('staged', n, 'total', (select total_rows from b2b.imports where id = i.id));
end $fn$;

/* Each course as written in the file, with its catalogue match. confidence 1: an exact key or synonym; else the best
   similarity to a catalogue course or programme name. Below 0.6 the Admin confirms; with no candidate the rows are
   programme mismatch (not passed to any CRM) unless the Admin picks a course. */
create or replace function b2b.import_courses(p_import_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('text', c.txt, 'rows', c.n, 'key', k.key, 'confidence', k.conf,
                                        'label', (select p.course from public.catalog_programs p where p.course_key = k.key limit 1),
                                        'choice', (select course_choices -> c.txt from b2b.imports where id = p_import_id),
                                        'candidates', k.cands) order by k.conf nulls first, c.n desc)
      from (select lead ->> 'course' txt, count(*) n from b2b.import_rows where import_id = p_import_id and lead ? 'course' group by 1) c
      cross join lateral (
        select coalesce(b2b.match_course_key(c.txt), (select x.course_key from (
                 select p.course_key, greatest(public.similarity(lower(p.course), lower(c.txt)), public.similarity(lower(p.program_name), lower(c.txt))) s
                   from public.catalog_programs p where p.active order by 2 desc limit 1) x where x.s >= 0.45)) key,
               case when b2b.match_course_key(c.txt) is not null then 1
                    else (select round(max(greatest(public.similarity(lower(p.course), lower(c.txt)), public.similarity(lower(p.program_name), lower(c.txt))))::numeric, 2)
                            from public.catalog_programs p where p.active) end conf,
               (select coalesce(jsonb_agg(jsonb_build_object('key', y.course_key, 'label', y.course, 's', round(y.s::numeric, 2)) order by y.s desc), '[]')
                  from (select * from (select distinct on (p.course_key) p.course_key, p.course,
                                              greatest(public.similarity(lower(p.course), lower(c.txt)), public.similarity(lower(p.program_name), lower(c.txt))) s
                                         from public.catalog_programs p where p.active order by p.course_key, 3 desc) y0
                         where y0.s >= 0.2 order by y0.s desc limit 5) y) cands) k), '[]');
end $fn$;

/* The Admin's choice for a course as written: a catalogue course key, or null to keep it as written. */
create or replace function b2b.import_set_course(p_import_id bigint, p_text text, p_course_key text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_course_key is not null and not exists (select 1 from public.catalog_programs where course_key = p_course_key) then
    raise exception 'that course is not in the catalogue' using errcode = '22023';
  end if;
  update b2b.imports set course_choices = case when p_course_key is null then course_choices - p_text
                                               else course_choices || jsonb_build_object(p_text, p_course_key) end
   where id = p_import_id and status = 'staging';
  if not found then raise exception 'import not found or already committed' using errcode = '22023'; end if;
end $fn$;

/* Steps 3–4: counts, problems and the job's state. */
create or replace function b2b.import_preview(p_import_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare i b2b.imports;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into i from b2b.imports where id = p_import_id;
  if i.id is null then raise exception 'import not found' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'import', to_jsonb(i),
    'preview', coalesce((select jsonb_object_agg(coalesce(preview, 'pending'), n) from (select preview, count(*) n from b2b.import_rows where import_id = i.id group by 1) x), '{}'),
    'status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from b2b.import_rows where import_id = i.id group by 1) x), '{}'),
    'actions', coalesce((select jsonb_object_agg(action, n) from (select action, count(*) n from b2b.import_rows where import_id = i.id and action is not null group by 1) x), '{}'),
    'problems', coalesce((select jsonb_object_agg(p, n) from (select p, count(*) n from b2b.import_rows, unnest(problems) p where import_id = i.id group by 1) x), '{}'),
    'sample', coalesce((select jsonb_agg(jsonb_build_object('row_no', row_no, 'lead', lead, 'problems', problems, 'preview', preview, 'existing_lead_id', existing_lead_id,
                                                            'status', status, 'lead_id', lead_id, 'action', action, 'error', error) order by row_no)
                          from (select * from b2b.import_rows where import_id = i.id order by (cardinality(problems) = 0), row_no limit 50) s), '[]'),
    'can_rollback', i.status = 'done' and i.finished_at > now() - make_interval(hours => coalesce((select (value ->> 'rollback_hours')::int from b2b.settings where key = 'intake'), 24)));
end $fn$;

/* Rows for download: all, or one preview group, 5,000 at a time. */
create or replace function b2b.import_rows_page(p_import_id bigint, p_preview text, p_after int)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('row_no', row_no, 'phone', phone, 'name', lead ->> 'full_name', 'email', lead ->> 'email', 'course', lead ->> 'course',
                                                       'preview', preview, 'problems', array_to_string(problems, '; '), 'existing_lead_id', existing_lead_id,
                                                       'status', status, 'action', action, 'lead_id', lead_id, 'error', error) order by row_no)
                     from (select * from b2b.import_rows where import_id = p_import_id and (p_preview is null or preview = p_preview) and row_no > coalesce(p_after, 0)
                            order by row_no limit 5000) r), '[]');
end $fn$;

revoke execute on function b2b.import_fields(), b2b.import_create(jsonb), b2b.import_map_row(jsonb, jsonb), b2b.import_stage_rows(bigint, int, jsonb),
                           b2b.import_courses(bigint), b2b.import_set_course(bigint, text, text), b2b.import_preview(bigint), b2b.import_rows_page(bigint, text, int)
  from public, anon, authenticated;
grant execute on function b2b.import_fields(), b2b.import_map_row(jsonb, jsonb) to service_role;
grant execute on function b2b.import_create(jsonb), b2b.import_stage_rows(bigint, int, jsonb), b2b.import_courses(bigint), b2b.import_set_course(bigint, text, text),
                          b2b.import_preview(bigint), b2b.import_rows_page(bigint, text, int)
  to authenticated, service_role;
