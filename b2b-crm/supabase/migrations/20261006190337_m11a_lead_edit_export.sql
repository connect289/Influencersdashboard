-- M11a: lead editing with field history (spec B6.1.3) and a paged export for large downloads (B6.1, 20,000 rows).
-- Edits go through lead_intake() with source_system 'crm' (still the only writer of student_leads); this function
-- validates, compares, checks that the write reached the same lead, and keeps one history row per changed field.
-- lead_intake() cannot clear a value, so clearing is refused here. Not yet done (needs a lead_intake change, Vikas's
-- call): locking a corrected field so Witty does not overwrite it; until then the history shows when it was overwritten.

create table if not exists b2b.lead_edits (
  id         bigint generated always as identity primary key,
  lead_id    bigint not null,
  field      text not null,
  old_value  text,
  new_value  text not null,
  reason     text not null,
  actor_id   text,
  edited_at  timestamptz not null default now()
);
create index if not exists lead_edits_lead_idx on b2b.lead_edits (lead_id, edited_at desc);

alter table b2b.lead_exports add column if not exists status text not null default 'done';
alter table b2b.lead_exports add column if not exists finished_at timestamptz;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'lead_exports_status_check') then
    alter table b2b.lead_exports add constraint lead_exports_status_check check (status in ('running', 'done'));
  end if;
end $c$;

do $rls$
begin
  alter table b2b.lead_edits enable row level security;
  if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = 'lead_edits' and policyname = 'admin_read') then
    create policy admin_read on b2b.lead_edits for select to authenticated using ((select b2b.is_admin()));
  end if;
  revoke all on b2b.lead_edits from public, anon, authenticated;
  grant select on b2b.lead_edits to authenticated;
  grant all on b2b.lead_edits to service_role;
end $rls$;

/* The fields the Admin may correct, with how each is checked. Money, routing, consent, source and system fields are not here. */
create or replace function b2b.lead_edit_fields()
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'student_name', 'text', 'email_id', 'email', 'alternate_phone', 'phone', 'preferred_language', 'text', 'city', 'text', 'state', 'text',
    'guardian_name', 'text', 'guardian_phone', 'phone', 'interested_course', 'text', 'interested_specialization', 'text',
    'interested_university', 'text', 'program_level', 'text', 'study_mode_preference', 'text', 'highest_qualification', 'text',
    'academic_score_pct', 'percent', 'work_experience_years_num', 'years', 'annual_budget_inr', 'amount', 'enrollment_timeline', 'text',
    'lead_status', 'status', 'Comments', 'note');
$$;

create or replace function b2b.lead_edit(p_lead_id bigint, p_changes jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  l public.student_leads;
  f jsonb := b2b.lead_edit_fields();
  k text;
  v jsonb;
  v_kind text;
  v_old text;
  v_new text;
  v_in jsonb := '{}';
  v_changed jsonb := '[]';
  v_res jsonb;
  v_a jsonb := b2b.actor();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) not between 3 and 300 then raise exception 'say why you are correcting the lead' using errcode = '22023'; end if;
  if jsonb_typeof(p_changes) <> 'object' then raise exception 'nothing to change' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if l.deleted_at is not null or l.merged_into_id is not null then raise exception 'restore the lead before editing it' using errcode = '22023'; end if;

  for k, v in select key, value from jsonb_each(p_changes) loop
    v_kind := f ->> k;
    if v_kind is null then raise exception 'the field % cannot be edited here', k using errcode = '22023'; end if;
    v_new := nullif(trim(coalesce(v #>> '{}', '')), '');
    v_old := to_jsonb(l) ->> k;
    if v_new is null then
      if v_old is not null then raise exception '% cannot be emptied; correct it instead', replace(k, '_', ' ') using errcode = '22023'; end if;
      continue;
    end if;
    case v_kind
      when 'email' then
        v_new := lower(v_new);
        if v_new !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then raise exception 'the email address is not valid' using errcode = '22023'; end if;
      when 'phone' then
        v_new := regexp_replace(v_new, '\D', '', 'g');
        if length(v_new) = 10 then v_new := '91' || v_new; end if;
        if v_new !~ '^\d{11,15}$' then raise exception '% is not a phone number', replace(k, '_', ' ') using errcode = '22023'; end if;
        if v_new = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') then raise exception '% is the lead''s own number', replace(k, '_', ' ') using errcode = '22023'; end if;
      when 'percent' then
        if v_new !~ '^\d{1,3}(\.\d{1,2})?$' or v_new::numeric > 100 then raise exception 'the score is a percentage from 0 to 100' using errcode = '22023'; end if;
      when 'years' then
        if v_new !~ '^\d{1,2}(\.\d)?$' or v_new::numeric > 50 then raise exception 'work experience is a number of years' using errcode = '22023'; end if;
      when 'amount' then
        if v_new !~ '^\d{1,9}$' then raise exception 'the budget is a whole number of rupees' using errcode = '22023'; end if;
      when 'status' then
        v_new := upper(v_new);
        if v_new not in ('HOT', 'WARM', 'COLD', 'UNQUALIFIED', 'JUNK', 'PROGRAM_MISMATCH') then raise exception 'unknown classification' using errcode = '22023'; end if;
      when 'note' then
        if length(v_new) > 2000 then raise exception 'the note is longer than 2,000 characters' using errcode = '22023'; end if;
      else
        if length(v_new) > 200 then raise exception '% is longer than 200 characters', replace(k, '_', ' ') using errcode = '22023'; end if;
    end case;
    if v_kind in ('percent', 'years', 'amount') and v_old is not null and v_old::numeric = v_new::numeric then continue; end if;
    if v_new is not distinct from v_old then continue; end if;
    v_in := v_in || jsonb_build_object(k, v_new);
    v_changed := v_changed || jsonb_build_array(jsonb_build_object('field', k, 'old', v_old, 'new', v_new));
  end loop;

  if v_in = '{}' then return jsonb_build_object('changed', '[]'::jsonb); end if;
  v_res := public.lead_intake(jsonb_build_object('phone', l.whatsapp_number, 'source_system', 'crm', 'event_type', 'lead.edited', 'lead', v_in));
  if (v_res ->> 'lead_id')::bigint is distinct from l.id then
    raise exception 'the correction would have reached another lead (%); nothing was changed', v_res ->> 'lead_id' using errcode = '22023';
  end if;

  insert into b2b.lead_edits (lead_id, field, old_value, new_value, reason, actor_id)
  select l.id, c ->> 'field', c ->> 'old', c ->> 'new', trim(p_reason), v_a ->> 'id' from jsonb_array_elements(v_changed) c;
  perform b2b.log_event('lead.edited', l.id, null, null, jsonb_build_object('fields', (select jsonb_agg(c ->> 'field') from jsonb_array_elements(v_changed) c),
                                                                          'reason', trim(p_reason)));
  return jsonb_build_object('changed', v_changed);
end $$;

/* Field history for the drawer, with whether each correction still holds or something wrote over it since. */
create or replace function b2b.lead_edit_history(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare l public.student_leads;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then return '[]'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', e.id, 'field', e.field, 'old', e.old_value, 'new', e.new_value, 'reason', e.reason, 'at', e.edited_at,
             'current', to_jsonb(l) ->> e.field,
             'overwritten', e.id = (select max(x.id) from b2b.lead_edits x where x.lead_id = e.lead_id and x.field = e.field)
                            and (to_jsonb(l) ->> e.field) is distinct from e.new_value
                            and not (e.field in ('academic_score_pct', 'work_experience_years_num', 'annual_budget_inr')
                                     and (to_jsonb(l) ->> e.field)::numeric = e.new_value::numeric),
             'updated_by', l.updated_by) order by e.edited_at desc, e.id desc)
      from b2b.lead_edits e where e.lead_id = l.id), '[]');
end $$;

-- ---------- Paged export (the app streams the pages as one CSV download) ----------

create or replace function b2b.leads_export_start(p jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_id bigint; v_a jsonb := b2b.actor();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  perform b2b.lead_filter_sql(p);   -- refuses bad filters before anything is logged
  insert into b2b.lead_exports (actor_id, filters, row_count, masked, status)
  values (v_a ->> 'id', p - 'after' - 'limit', 0, coalesce((p ->> 'masked')::boolean, false), 'running') returning id into v_id;
  return v_id;
end $$;

/* One page of an export, newest first. The filters and masking come from the export row, never from the caller. */
create or replace function b2b.leads_export_page(p_export_id bigint, p_after jsonb, p_limit int default 2000)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  x b2b.lead_exports;
  v_a jsonb := b2b.actor();
  v_cap int := 50000;
  v_limit int;
  v_where text;
  v_keyset text := '';
  v_rows jsonb;
  v_n int;
  v_next jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into x from b2b.lead_exports where id = p_export_id for update;
  if x.id is null or x.status <> 'running' or x.actor_id is distinct from v_a ->> 'id' or x.at < now() - interval '1 hour' then
    raise exception 'this export is closed; start a new one' using errcode = '22023';
  end if;
  v_limit := least(greatest(coalesce(p_limit, 2000), 100), 5000, v_cap - x.row_count);
  v_where := b2b.lead_filter_sql(x.filters);
  if p_after ->> 'id' is not null then
    v_keyset := format(' and (l.created_at, l.id) < (%L::timestamptz, %L::bigint)', p_after ->> 'v', p_after ->> 'id');
  end if;
  if v_limit > 0 then
    execute format($q$
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc), '[]'::jsonb) from (
        select l.id, l.created_at, l.student_name,
               case when %3$L::boolean then '******' || right(regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'), 4) else l.whatsapp_number end as phone,
               case when %3$L::boolean and position('@' in coalesce(l.email_id, '')) > 0 then left(l.email_id, 1) || '***@' || split_part(l.email_id, '@', 2) else l.email_id end as email,
               l.city, l.state, l.interested_course, l.interested_specialization, coalesce(l.interested_university, l.university_preference) as university,
               l.program_level, l.study_mode_preference, l.highest_qualification, l.lead_status, l.stage, l.sub_stage,
               l.lead_source, l.channel, l.campaign, l.utm_source, l.utm_medium, l.utm_campaign,
               case when np.lead_id is not null then 'not_passed' else coalesce(l.destination_type, 'unrouted') end as destination,
               coalesce(p.display_name, p.name) as partner, a.reference, a.status as allocation_status, a.b2c_lane, l.partner_stage_raw,
               l.consent_partner_share_at, l.last_activity_at, l.deleted_at,
               (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)) as is_test
          from public.student_leads l
          left join b2b.allocations a on a.id = l.allocation_id
          left join b2b.partners p on p.id = a.partner_id
          left join b2b.not_passed np on np.lead_id = l.id and np.passed_at is null
         where %1$s%2$s
         order by l.created_at desc, l.id desc
         limit %4$s
      ) r
    $q$, v_where, v_keyset, x.masked, v_limit) into v_rows;
  else
    v_rows := '[]';
  end if;

  v_n := jsonb_array_length(v_rows);
  update b2b.lead_exports set row_count = row_count + v_n where id = x.id returning * into x;
  if v_n = v_limit and x.row_count < v_cap then
    v_next := jsonb_build_object('v', v_rows -> (v_n - 1) ->> 'created_at', 'id', v_rows -> (v_n - 1) ->> 'id');
  else
    update b2b.lead_exports set status = 'done', finished_at = now() where id = x.id;
    perform b2b.log_event('leads.exported', null, null, null, jsonb_build_object('export_id', x.id, 'rows', x.row_count, 'masked', x.masked,
                                                                               'capped', x.row_count >= v_cap));
  end if;
  return jsonb_build_object('rows', v_rows, 'next', v_next, 'total', x.row_count, 'capped', v_next is null and x.row_count >= v_cap);
end $$;

revoke execute on function b2b.lead_edit_fields() from public, anon;
grant execute on function b2b.lead_edit_fields() to authenticated, service_role;
revoke execute on function b2b.lead_edit(bigint, jsonb, text), b2b.lead_edit_history(bigint), b2b.leads_export_start(jsonb),
                           b2b.leads_export_page(bigint, jsonb, int) from public, anon;
grant execute on function b2b.lead_edit(bigint, jsonb, text), b2b.lead_edit_history(bigint), b2b.leads_export_start(jsonb),
                          b2b.leads_export_page(bigint, jsonb, int) to authenticated, service_role;
