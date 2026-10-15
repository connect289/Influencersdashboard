-- M33b (15 Oct): the lead workspace. Tags, internal notes, a duplicate review and a merge for the Master Lead Table.
--   (1) b2b.tags / b2b.lead_tags   Admin-defined labels (name, colour), any number per lead; bulk tag / untag from the
--                                  table; a filter and a facet; a column in leads_list. Retired tags keep their rows.
--   (2) b2b.lead_notes             Internal notes on a lead (pinned first), never sent to students, partners or the B2C
--                                  CRM; soft-removed, every change logged.
--   (3) Duplicates                 lead_duplicates: live leads that share an email, a recorded number (lead_contacts or
--                                  alternate_phone against another lead's WhatsApp number) or a name and city; a pair
--                                  can be dismissed. lead_merge(keep, merge, reason) folds one lead into another: empty
--                                  fields of the kept lead are filled, the merged lead's phone and email become contacts
--                                  of the kept lead (so a new enquiry on that number joins it, m32b), notes, tags and
--                                  contacts move, a different course becomes a secondary interest, the merged lead is
--                                  marked merged (merged_into_id) and released from the B2C CRM's copy. Refused while the
--                                  merged lead is with a partner (recall it first) or carries an enrolment.
--   (4) lead_filter_sql, leads_facets, lead_a3_columns_sql REPLACED (m31l / m32c): the tag filter, facet and column.
-- Nothing on Witty's tables; no triggers on student_leads. Re-appliable.

create table if not exists b2b.tags (
  id          bigint generated always as identity primary key,
  name        text not null check (length(name) between 1 and 40),
  color       text not null default 'slate' check (color in ('slate', 'red', 'amber', 'green', 'blue', 'violet', 'pink')),
  created_by  uuid,
  created_at  timestamptz not null default now(),
  retired_at  timestamptz
);
create unique index if not exists tags_name_uq on b2b.tags (lower(name));

create table if not exists b2b.lead_tags (
  lead_id   bigint not null,
  tag_id    bigint not null references b2b.tags (id) on delete restrict,
  added_by  uuid,
  added_at  timestamptz not null default now(),
  primary key (lead_id, tag_id)
);
create index if not exists lead_tags_tag_idx on b2b.lead_tags (tag_id);

create table if not exists b2b.lead_notes (
  id            bigint generated always as identity primary key,
  lead_id       bigint not null,
  body          text not null check (length(body) between 1 and 4000),
  pinned        boolean not null default false,
  author_id     uuid,
  author_email  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index if not exists lead_notes_lead_idx on b2b.lead_notes (lead_id, pinned desc, created_at desc) where deleted_at is null;

create table if not exists b2b.duplicate_dismissals (
  lead_a      bigint not null,
  lead_b      bigint not null,
  dismissed_by uuid,
  dismissed_at timestamptz not null default now(),
  note        text,
  primary key (lead_a, lead_b),
  check (lead_a < lead_b)
);

do $rls$
declare t text;
begin
  foreach t in array array['tags', 'lead_tags', 'lead_notes', 'duplicate_dismissals'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- ---------- (1) tags ----------
create or replace function b2b.tags_list(p_include_retired boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'color', t.color, 'retired_at', t.retired_at,
                                                       'leads', (select count(*) from b2b.lead_tags lt join public.student_leads l on l.id = lt.lead_id
                                                                  where lt.tag_id = t.id and l.deleted_at is null and l.merged_into_id is null))
                                    order by t.retired_at nulls first, lower(t.name))
                     from b2b.tags t where p_include_retired or t.retired_at is null), '[]');
end $fn$;

/* Create or rename / recolour a tag: p = {id?, name, color?}. Names are unique, case-insensitively. */
create or replace function b2b.tag_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_name text := left(trim(coalesce(p ->> 'name', '')), 40);
  v_color text := coalesce(nullif(p ->> 'color', ''), 'slate');
  v_id bigint := nullif(p ->> 'id', '')::bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_name = '' then raise exception 'give the tag a name' using errcode = '22023'; end if;
  if v_color not in ('slate', 'red', 'amber', 'green', 'blue', 'violet', 'pink') then raise exception 'unknown colour' using errcode = '22023'; end if;
  if exists (select 1 from b2b.tags t where lower(t.name) = lower(v_name) and t.id is distinct from v_id) then
    raise exception 'a tag with this name exists' using errcode = '22023';
  end if;
  if v_id is null then
    insert into b2b.tags (name, color, created_by) values (v_name, v_color, auth.uid()) returning id into v_id;
  else
    update b2b.tags set name = v_name, color = v_color, retired_at = null where id = v_id;
    if not found then raise exception 'tag not found' using errcode = 'P0002'; end if;
  end if;
  perform b2b.log_event('tag.saved', null, null, null, jsonb_build_object('tag_id', v_id, 'name', v_name, 'color', v_color));
  return jsonb_build_object('id', v_id, 'name', v_name, 'color', v_color);
end $fn$;

create or replace function b2b.tag_retire(p_id bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.tags set retired_at = now() where id = p_id and retired_at is null;
  if found then perform b2b.log_event('tag.retired', null, null, null, jsonb_build_object('tag_id', p_id)); end if;
  return found;
end $fn$;

/* Tag or untag up to 500 leads with one tag (by name; a new name creates the tag). Returns the counts. */
create or replace function b2b.leads_tag(p_ids bigint[], p_tag text, p_add boolean default true)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_name text := left(trim(coalesce(p_tag, '')), 40);
  v_tag bigint;
  n int := 0;
  v_id bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_name = '' then raise exception 'give a tag' using errcode = '22023'; end if;
  if p_ids is null or cardinality(p_ids) = 0 then return jsonb_build_object('changed', 0); end if;
  if cardinality(p_ids) > 500 then raise exception 'at most 500 leads at a time' using errcode = '22023'; end if;
  select t.id into v_tag from b2b.tags t where lower(t.name) = lower(v_name);
  if v_tag is null then
    if not p_add then return jsonb_build_object('changed', 0); end if;
    insert into b2b.tags (name, created_by) values (v_name, auth.uid()) returning id into v_tag;
    perform b2b.log_event('tag.saved', null, null, null, jsonb_build_object('tag_id', v_tag, 'name', v_name, 'color', 'slate'));
  end if;
  update b2b.tags set retired_at = null where id = v_tag and p_add;
  if p_add then
    for v_id in insert into b2b.lead_tags (lead_id, tag_id, added_by)
                select l.id, v_tag, auth.uid() from public.student_leads l where l.id = any (p_ids) and l.merged_into_id is null
                on conflict (lead_id, tag_id) do nothing returning lead_id loop
      perform b2b.log_event('lead.tagged', v_id, null, null, jsonb_build_object('tag_id', v_tag, 'tag', v_name));
      n := n + 1;
    end loop;
  else
    for v_id in delete from b2b.lead_tags where tag_id = v_tag and lead_id = any (p_ids) returning lead_id loop
      perform b2b.log_event('lead.untagged', v_id, null, null, jsonb_build_object('tag_id', v_tag, 'tag', v_name));
      n := n + 1;
    end loop;
  end if;
  return jsonb_build_object('changed', n, 'tag_id', v_tag, 'tag', v_name);
end $fn$;

/* One lead's tags, for the drawer. */
create or replace function b2b.lead_tags_of(p_lead_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select case when b2b.is_admin() then coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'color', t.color) order by lower(t.name))
                                                   from b2b.lead_tags lt join b2b.tags t on t.id = lt.tag_id where lt.lead_id = p_lead_id and t.retired_at is null), '[]')
         else '[]'::jsonb end;
$fn$;

-- ---------- (2) notes ----------
create or replace function b2b.lead_notes_list(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'body', n.body, 'pinned', n.pinned, 'author', coalesce(n.author_email, 'admin'),
                                                       'mine', n.author_id = auth.uid(), 'created_at', n.created_at, 'updated_at', n.updated_at)
                                    order by n.pinned desc, n.created_at desc)
                     from b2b.lead_notes n where n.lead_id = p_lead_id and n.deleted_at is null), '[]');
end $fn$;

create or replace function b2b.lead_note_add(p_lead_id bigint, p_body text, p_pinned boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint; v_body text := left(trim(coalesce(p_body, '')), 4000);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_body = '' then raise exception 'write something' using errcode = '22023'; end if;
  if not exists (select 1 from public.student_leads l where l.id = p_lead_id) then raise exception 'lead not found' using errcode = 'P0002'; end if;
  insert into b2b.lead_notes (lead_id, body, pinned, author_id, author_email)
  values (p_lead_id, v_body, coalesce(p_pinned, false), auth.uid(), auth.jwt() ->> 'email') returning id into v_id;
  perform b2b.log_event('lead.note_added', p_lead_id, null, null, jsonb_build_object('note_id', v_id, 'pinned', coalesce(p_pinned, false), 'preview', left(v_body, 80)));
  return jsonb_build_object('id', v_id);
end $fn$;

create or replace function b2b.lead_note_update(p_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare n b2b.lead_notes; v_body text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into n from b2b.lead_notes where id = p_id and deleted_at is null for update;
  if n.id is null then raise exception 'note not found' using errcode = 'P0002'; end if;
  v_body := case when p ? 'body' then left(trim(p ->> 'body'), 4000) else n.body end;
  if v_body = '' then raise exception 'write something' using errcode = '22023'; end if;
  update b2b.lead_notes set body = v_body, pinned = coalesce((p ->> 'pinned')::boolean, pinned), updated_at = now() where id = n.id;
  perform b2b.log_event('lead.note_updated', n.lead_id, null, null, jsonb_build_object('note_id', n.id, 'changes', p - 'body' || case when p ? 'body' then jsonb_build_object('body', true) else '{}'::jsonb end));
  return jsonb_build_object('id', n.id);
end $fn$;

create or replace function b2b.lead_note_remove(p_id bigint)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare v_lead bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.lead_notes set deleted_at = now() where id = p_id and deleted_at is null returning lead_id into v_lead;
  if v_lead is not null then perform b2b.log_event('lead.note_removed', v_lead, null, null, jsonb_build_object('note_id', p_id)); end if;
  return v_lead is not null;
end $fn$;

-- ---------- (3) duplicates and merging ----------
/* Pairs of live, unmerged, non-test leads that look like one student: the same email, a number one lead recorded
   (lead_contacts, alternate_phone) that is the other's WhatsApp number, or the same name and city. Newest first, at
   most p_limit pairs, dismissed pairs left out. No routing effect: the Admin decides. */
create or replace function b2b.lead_duplicates(p_limit int default 100)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    with live as (
      select l.id, l.student_name, l.whatsapp_number, lower(nullif(trim(l.email_id), '')) as email, l.city, l.created_at, l.destination_type, l.partner_id,
             l.interested_course, l.lead_source, regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') as digits,
             regexp_replace(coalesce(l.alternate_phone, ''), '\D', '', 'g') as alt
        from public.student_leads l
       where l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null
         and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))
    ), pairs as (
      select a.id as a_id, b.id as b_id, 'same email' as why from live a join live b on b.id > a.id and a.email is not null and a.email = b.email
      union
      select least(a.id, b.id), greatest(a.id, b.id), 'same phone number'
        from live a join live b on b.id <> a.id
       where length(b.digits) >= 10 and (a.alt = b.digits or exists (select 1 from b2b.lead_contacts c where c.lead_id = a.id and c.kind = 'phone' and c.removed_at is null and c.value = b.digits))
      union
      select a.id, b.id, 'same name and city' from live a join live b on b.id > a.id
       where length(coalesce(a.student_name, '')) >= 5 and lower(trim(a.student_name)) = lower(trim(b.student_name))
         and a.city is not null and lower(trim(a.city)) = lower(trim(b.city))
    ), agg as (
      select a_id, b_id, string_agg(why, ', ' order by why) as why from pairs
       where not exists (select 1 from b2b.duplicate_dismissals d where d.lead_a = a_id and d.lead_b = b_id)
       group by a_id, b_id
    )
    select jsonb_agg(jsonb_build_object('why', g.why,
             'a', (select jsonb_build_object('id', x.id, 'name', x.student_name, 'phone', x.whatsapp_number, 'email', x.email, 'city', x.city, 'course', x.interested_course,
                                             'source', x.lead_source, 'created_at', x.created_at, 'destination', x.destination_type, 'partner_id', x.partner_id,
                                             'has_enrollment', exists (select 1 from public.enrollments e where e.lead_id = x.id)) from live x where x.id = g.a_id),
             'b', (select jsonb_build_object('id', x.id, 'name', x.student_name, 'phone', x.whatsapp_number, 'email', x.email, 'city', x.city, 'course', x.interested_course,
                                             'source', x.lead_source, 'created_at', x.created_at, 'destination', x.destination_type, 'partner_id', x.partner_id,
                                             'has_enrollment', exists (select 1 from public.enrollments e where e.lead_id = x.id)) from live x where x.id = g.b_id))
           order by greatest(g.a_id, g.b_id) desc)
      from (select * from agg order by greatest(a_id, b_id) desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) g), '[]');
end $fn$;

create or replace function b2b.lead_duplicate_dismiss(p_a bigint, p_b bigint, p_note text default null)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_a is null or p_b is null or p_a = p_b then raise exception 'two different leads' using errcode = '22023'; end if;
  insert into b2b.duplicate_dismissals (lead_a, lead_b, dismissed_by, note) values (least(p_a, p_b), greatest(p_a, p_b), auth.uid(), left(p_note, 300))
  on conflict (lead_a, lead_b) do nothing;
  perform b2b.log_event('lead.duplicate_dismissed', least(p_a, p_b), null, null, jsonb_build_object('other_lead_id', greatest(p_a, p_b), 'note', left(p_note, 300)));
  return true;
end $fn$;

/* Fold p_merge into p_keep. See the file header for what moves. The merged lead keeps its own history (allocations,
   events, money rows stay on its id); it is marked merged_into_id and leaves the B2C CRM's copy. */
create or replace function b2b.lead_merge(p_keep bigint, p_merge bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  k public.student_leads;
  m public.student_leads;
  v_fill jsonb := '{}';
  v_filled text[] := '{}';
  c text;
  v_sql text;
  v_row jsonb;
  v_contacts int := 0;
  v_notes int := 0;
  v_tags int := 0;
  v_mdigits text;
  v_kdigits text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if p_keep is null or p_merge is null or p_keep = p_merge then raise exception 'choose two different leads' using errcode = '22023'; end if;
  select * into k from public.student_leads where id = p_keep for update;
  select * into m from public.student_leads where id = p_merge for update;
  if k.id is null or m.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if k.deleted_at is not null or k.merged_into_id is not null or k.anonymised_at is not null then raise exception 'the lead to keep is deleted, merged or erased' using errcode = '22023'; end if;
  if m.deleted_at is not null or m.merged_into_id is not null or m.anonymised_at is not null then raise exception 'the lead to merge is deleted, merged or erased' using errcode = '22023'; end if;
  if exists (select 1 from public.enrollments e where e.lead_id = m.id) then
    raise exception 'the lead to merge has an enrolment; keep that lead instead' using errcode = '22023';
  end if;
  if exists (select 1 from b2b.allocations a where a.id = m.allocation_id and a.destination_type = 'partner' and a.status in ('queued', 'pushing', 'pushed', 'accepted')) then
    raise exception 'the lead to merge is with a partner; recall it first' using errcode = '22023';
  end if;
  perform set_config('b2b.actor', 'admin', true);

  -- 1. empty fields of the kept lead are filled from the merged lead
  foreach c in array array['student_name', 'email_id', 'alternate_phone', 'city', 'state', 'country', 'interested_course', 'interested_specialization',
                           'interested_university', 'program_level', 'study_mode_preference', 'highest_qualification', 'current_study', 'academic_score_pct',
                           'work_experience_years_num', 'current_job_role', 'guardian_name', 'guardian_phone', 'preferred_language', 'enquirer_relation',
                           'annual_budget_inr', 'enrollment_timeline', 'preferred_counseling_time', 'lead_source', 'channel', 'campaign',
                           'consent_sales_at', 'consent_marketing_at', 'consent_partner_share_at', 'consent_text_version', 'first_touch_at'] loop
    if nullif(trim(coalesce(to_jsonb(k) ->> c, '')), '') is null and nullif(trim(coalesce(to_jsonb(m) ->> c, '')), '') is not null then
      v_fill := v_fill || jsonb_build_object(c, to_jsonb(m) -> c);
      v_filled := array_append(v_filled, c);
    end if;
  end loop;
  v_fill := v_fill || jsonb_build_object('custom_fields', coalesce(m.custom_fields, '{}') || coalesce(k.custom_fields, '{}'),
                                         'contact_attempts', coalesce(k.contact_attempts, 0) + coalesce(m.contact_attempts, 0),
                                         'last_activity_at', greatest(k.last_activity_at, m.last_activity_at, now()));
  v_row := to_jsonb(k) || v_fill;
  select string_agg(format('%I = r.%I', x, x), ', ') into v_sql from jsonb_object_keys(v_fill) x;
  execute format('update public.student_leads t set %s, updated_by = $3 from jsonb_populate_record(null::public.student_leads, $1) r where t.id = $2', v_sql)
    using v_row, k.id, 'b2b:merge';

  -- 2. the merged lead's number and email become contacts of the kept lead (a new enquiry on them joins it, m32b)
  v_mdigits := public.crm_norm_phone(m.whatsapp_number);
  v_kdigits := public.crm_norm_phone(k.whatsapp_number);
  if v_mdigits is not null and v_mdigits is distinct from v_kdigits then
    insert into b2b.lead_contacts (lead_id, kind, value, label, origin, actor, event_id)
    values (k.id, 'phone', v_mdigits, 'alternate', 'admin', jsonb_build_object('merge_of', m.id), null)
    on conflict (lead_id, kind, value) do update set removed_at = null;
    if nullif(trim(coalesce(k.alternate_phone, '')), '') is null and not (v_fill ? 'alternate_phone') then
      update public.student_leads set alternate_phone = v_mdigits where id = k.id;
    end if;
  end if;
  if nullif(lower(trim(coalesce(m.email_id, ''))), '') is not null and lower(trim(coalesce(m.email_id, ''))) is distinct from lower(trim(coalesce(k.email_id, ''))) then
    insert into b2b.lead_contacts (lead_id, kind, value, label, origin, actor) values (k.id, 'email', lower(trim(m.email_id)), 'alternate', 'admin', jsonb_build_object('merge_of', m.id))
    on conflict (lead_id, kind, value) do update set removed_at = null;
  end if;
  -- 3. contacts, notes and tags move
  update b2b.lead_contacts set lead_id = k.id where lead_id = m.id
     and not exists (select 1 from b2b.lead_contacts x where x.lead_id = k.id and x.kind = b2b.lead_contacts.kind and x.value = b2b.lead_contacts.value);
  get diagnostics v_contacts = row_count;
  update b2b.lead_notes set lead_id = k.id where lead_id = m.id;
  get diagnostics v_notes = row_count;
  insert into b2b.lead_tags (lead_id, tag_id, added_by) select k.id, tag_id, added_by from b2b.lead_tags where lead_id = m.id on conflict do nothing;
  get diagnostics v_tags = row_count;
  -- 4. a different course becomes a secondary interest of the kept lead
  if nullif(trim(coalesce(m.interested_course, '')), '') is not null and lower(trim(m.interested_course)) is distinct from lower(trim(coalesce(k.interested_course, ''))) then
    perform b2b.lead_interest_add(k.id, jsonb_strip_nulls(jsonb_build_object('course', m.interested_course, 'specialization', m.interested_specialization,
                                   'level', m.program_level, 'mode', m.study_mode_preference, 'university', m.interested_university)), 'admin');
  end if;
  -- 5. the merged lead is marked merged and leaves the B2C CRM's copy
  update public.student_leads set merged_into_id = k.id, deleted_at = now(), updated_by = 'b2b:merge' where id = m.id;
  perform b2b.log_event('lead.merged', k.id, null, null, jsonb_build_object('merged_lead_id', m.id, 'reason', left(trim(p_reason), 300), 'filled', to_jsonb(v_filled),
                        'contacts_moved', v_contacts, 'notes_moved', v_notes, 'tags_moved', v_tags));
  perform b2b.log_event('lead.merged_into', m.id, null, null, jsonb_build_object('kept_lead_id', k.id, 'reason', left(trim(p_reason), 300)));
  perform b2b.b2c_sync_lead(m.id, false, 'merge');
  perform b2b.b2c_sync_lead(k.id, false, 'merge');
  return jsonb_build_object('kept', k.id, 'merged', m.id, 'filled', to_jsonb(v_filled), 'contacts_moved', v_contacts, 'notes_moved', v_notes, 'tags_moved', v_tags);
end $fn$;

-- ---------- (4) the table: the tag filter, facet and column ----------
create or replace function b2b.lead_filter_sql(p jsonb)
returns text language plpgsql immutable set search_path = '' as $fn$
declare
  w      text[] := array['l.merged_into_id is null'];
  q      text := left(trim(coalesce(p ->> 'q', '')), 100);
  digits text;
  pat    text;
  arr    text[];
begin
  if coalesce((p ->> 'bin')::boolean, false) then
    w := array_append(w, 'l.deleted_at is not null');
  else
    w := array_append(w, 'l.deleted_at is null');
  end if;

  if not coalesce((p ->> 'include_test')::boolean, false) then
    w := array_append(w, 'not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))');
  end if;

  if q <> '' then
    pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
    digits := regexp_replace(q, '\D', '', 'g');
    w := array_append(w, format('(l.student_name ilike %1$L or l.email_id ilike %1$L%2$s%3$s)',
      pat,
      case when length(digits) >= 4 then format(' or regexp_replace(coalesce(l.whatsapp_number, ''''), ''\D'', '''', ''g'') like %L', '%' || digits || '%') else '' end,
      case when q ~ '^\d{1,18}$' then format(' or l.id = %L::bigint', q) else '' end));
  end if;

  if jsonb_typeof(p -> 'stage') = 'array' and jsonb_array_length(p -> 'stage') > 0 then
    select array_agg(x) into arr from jsonb_array_elements_text(p -> 'stage') x;
    w := array_append(w, format('l.stage = any (%L::text[])', arr));
  end if;
  if jsonb_typeof(p -> 'source') = 'array' and jsonb_array_length(p -> 'source') > 0 then
    select array_agg(x) into arr from jsonb_array_elements_text(p -> 'source') x;
    w := array_append(w, format('coalesce(l.lead_source, ''(none)'') = any (%L::text[])', arr));
  end if;
  if jsonb_typeof(p -> 'status') = 'array' and jsonb_array_length(p -> 'status') > 0 then
    select array_agg(upper(x)) into arr from jsonb_array_elements_text(p -> 'status') x;
    w := array_append(w, format('upper(coalesce(nullif(l.lead_status, ''''), ''NONE'')) = any (%L::text[])', arr));
  end if;
  case p ->> 'destination'
    when 'unrouted' then w := array_append(w, 'l.destination_type is null');
    when 'partner'  then w := array_append(w, 'l.destination_type = ''partner''');
    when 'in_house' then w := array_append(w, 'l.destination_type = ''in_house''');
    when 'not_passed' then w := array_append(w, 'exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)');
    -- Addendum 3 views
    when 'barred' then w := array_append(w, 'exists (select 1 from b2b.partner_bars pb where pb.lead_id = l.id or (pb.phone_digits is not null and length(pb.phone_digits) >= 10 '
                                            || 'and pb.phone_digits = regexp_replace(coalesce(l.whatsapp_number, ''''), ''\D'', '''', ''g'')))');
    when 'qualification_nurture' then w := array_append(w, 'exists (select 1 from b2b.allocations qa where qa.id = l.allocation_id and qa.destination_type = ''in_house'' '
                                            || 'and qa.status = ''handed_off'' and qa.reason in (''not_qualified'', ''consent_no_answer''))');
    when 'awaiting_consent' then w := array_append(w, 'exists (select 1 from b2b.consent_requests cr where cr.lead_id = l.id and cr.status in (''queued'', ''requested'', ''sent'', ''unsendable''))');
    when 'reenquired' then w := array_append(w, 'exists (select 1 from b2b.lead_reenquiries rq where rq.lead_id = l.id and rq.acknowledged_at is null)');
    when 'lost_grace' then w := array_append(w, 'exists (select 1 from b2b.allocations ga where ga.id = l.allocation_id and ga.destination_type = ''partner'' '
                                            || 'and ga.lost_at is not null and ga.lost_revived_at is null and ga.status in (''pushed'', ''accepted''))');
    else null;
  end case;
  -- M33b: tags (any of the named tags)
  if jsonb_typeof(p -> 'tags') = 'array' and jsonb_array_length(p -> 'tags') > 0 then
    select array_agg(lower(x)) into arr from jsonb_array_elements_text(p -> 'tags') x;
    w := array_append(w, format('exists (select 1 from b2b.lead_tags lt join b2b.tags tg on tg.id = lt.tag_id where lt.lead_id = l.id and lower(tg.name) = any (%L::text[]))', arr));
  end if;
  -- the paid label (Meta / Google attribution, no routing effect)
  case p ->> 'paid'
    when 'meta'   then w := array_append(w, 'exists (select 1 from b2b.lead_campaigns lc where lc.lead_id = l.id and lc.paid and lc.platform = ''meta'')');
    when 'google' then w := array_append(w, 'exists (select 1 from b2b.lead_campaigns lc where lc.lead_id = l.id and lc.paid and lc.platform = ''google'')');
    when 'any'    then w := array_append(w, 'exists (select 1 from b2b.lead_campaigns lc where lc.lead_id = l.id and lc.paid)');
    else null;
  end case;
  -- Addendum 2: default views hide not-passed (junk / mismatch) leads; the "Not passed" view and the recycle bin show them
  if coalesce(p ->> 'destination', '') <> 'not_passed' and not coalesce((p ->> 'bin')::boolean, false)
     and not coalesce((p ->> 'with_not_passed')::boolean, false) then
    w := array_append(w, 'not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)');
  end if;

  return array_to_string(w, ' and ');
end $fn$;

create or replace function b2b.leads_facets(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_where text;
  v_all   text;
  v_base  jsonb := jsonb_build_object('include_test', p -> 'include_test', 'bin', p -> 'bin', 'q', p -> 'q');
  v_out   jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  -- facet counts ignore the facet filters themselves, so every option stays visible; only the routing facet counts
  -- not-passed leads (its "Not passed" option), the others follow the list, which hides them
  v_where := b2b.lead_filter_sql(v_base);
  v_all := b2b.lead_filter_sql(v_base || '{"with_not_passed": true}');
  execute format($q$
    select jsonb_build_object(
      'stage',       (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(l.stage, '(none)') k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'source',      (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(l.lead_source, '(none)') k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'status',      (select coalesce(jsonb_object_agg(k, n), '{}') from (select upper(coalesce(nullif(l.lead_status, ''), 'NONE')) k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'destination', (select coalesce(jsonb_object_agg(k, n), '{}') from (select case when exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null) then 'not_passed' else coalesce(l.destination_type, 'unrouted') end k, count(*) n from public.student_leads l where %2$s group by 1) s)
                     || jsonb_build_object(
                          'barred', (select count(*) from public.student_leads l where %3$s),
                          'qualification_nurture', (select count(*) from public.student_leads l where %4$s),
                          'awaiting_consent', (select count(*) from public.student_leads l where %5$s),
                          'reenquired', (select count(*) from public.student_leads l where %6$s),
                          'lost_grace', (select count(*) from public.student_leads l where %7$s)),
      'paid',        jsonb_build_object('meta', (select count(*) from public.student_leads l where %8$s),
                                        'google', (select count(*) from public.student_leads l where %9$s),
                                        'any', (select count(*) from public.student_leads l where %10$s)),
      'tags',        (select coalesce(jsonb_object_agg(k, n), '{}') from (select tg.name k, count(*) n from public.student_leads l join b2b.lead_tags lt on lt.lead_id = l.id join b2b.tags tg on tg.id = lt.tag_id where %1$s and tg.retired_at is null group by 1) s),
      'bin',         (select count(*) from public.student_leads l where l.deleted_at is not null and l.merged_into_id is null),
      'tests',       (select count(*) from public.student_leads l where l.deleted_at is null and l.merged_into_id is null and (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)))
    )
  $q$, v_where, v_all,
       b2b.lead_filter_sql(v_base || '{"destination": "barred"}'), b2b.lead_filter_sql(v_base || '{"destination": "qualification_nurture"}'),
       b2b.lead_filter_sql(v_base || '{"destination": "awaiting_consent"}'), b2b.lead_filter_sql(v_base || '{"destination": "reenquired"}'),
       b2b.lead_filter_sql(v_base || '{"destination": "lost_grace"}'),
       b2b.lead_filter_sql(v_base || '{"paid": "meta"}'), b2b.lead_filter_sql(v_base || '{"paid": "google"}'), b2b.lead_filter_sql(v_base || '{"paid": "any"}')) into v_out;
  return v_out;
end $fn$;

create or replace function b2b.lead_a3_columns_sql()
returns text language sql immutable set search_path = '' as $fn$
  select $c$
               bar.bar_reason as partner_bar_reason, bar.barred_at as partner_barred_at,
               coalesce(op.n, 0)::int as other_providers_count, op.names as other_providers,
               ca.b2c_lane, coalesce(l.allocation_reason, ca.alloc_reason) as allocation_reason,
               case when bar.bar_reason is not null and (l.destination_type = 'in_house' or (ih.status = 'handed_off' and l.allocation_id = ih.id)) then 'barred'
                    when ih.id is null or ih.outcome in ('requalified', 'routed_to_partners') then null
                    when exists (select 1 from b2b.allocations pa where pa.lead_id = l.id and pa.destination_type = 'partner'
                                    and pa.origin in ('to_partners', 'requalify', 'reroute') and (pa.created_at, pa.id) > (ih.created_at, ih.id)) then null
                    when ih.reason in ('not_qualified', 'consent_no_answer') then 'qualification_nurture'
                    else 'selling' end as hold_kind,
               exists (select 1 from b2b.lead_reenquiries rq where rq.lead_id = l.id and rq.acknowledged_at is null) as reenquired_open,
               pc.platform as paid_platform,
               b2b.consent_state_of(b2b.partner_consent(l)) as consent_state,
               ca.lost_grace_until,
               -- Addendum 4 §3: the B2C CRM's own stage and counsellor, for leads it holds; §7: its money, once it publishes it
               case when l.destination_type = 'in_house' then l.custom_fields -> 'b2c' ->> 'stage' end as b2c_stage,
               case when l.destination_type = 'in_house' then l.custom_fields -> 'b2c' ->> 'sub_stage' end as b2c_sub_stage,
               case when l.destination_type = 'in_house' then l.custom_fields -> 'b2c' ->> 'owner_name' end as b2c_owner_name,
               case when l.destination_type = 'in_house' then b2b.b2c_money_of(l.id) end as b2c_money,
               -- M33b: the lead's tags
               (select coalesce(array_agg(tg.name order by tg.name), '{}') from b2b.lead_tags lt join b2b.tags tg on tg.id = lt.tag_id where lt.lead_id = l.id and tg.retired_at is null) as tags
  $c$;
$fn$;

revoke execute on function b2b.tags_list(boolean), b2b.tag_save(jsonb), b2b.tag_retire(bigint), b2b.leads_tag(bigint[], text, boolean), b2b.lead_tags_of(bigint),
                           b2b.lead_notes_list(bigint), b2b.lead_note_add(bigint, text, boolean), b2b.lead_note_update(bigint, jsonb), b2b.lead_note_remove(bigint),
                           b2b.lead_duplicates(int), b2b.lead_duplicate_dismiss(bigint, bigint, text), b2b.lead_merge(bigint, bigint, text) from public, anon;
grant execute on function b2b.tags_list(boolean), b2b.tag_save(jsonb), b2b.tag_retire(bigint), b2b.leads_tag(bigint[], text, boolean), b2b.lead_tags_of(bigint),
                          b2b.lead_notes_list(bigint), b2b.lead_note_add(bigint, text, boolean), b2b.lead_note_update(bigint, jsonb), b2b.lead_note_remove(bigint),
                          b2b.lead_duplicates(int), b2b.lead_duplicate_dismiss(bigint, bigint, text), b2b.lead_merge(bigint, bigint, text) to authenticated, service_role;
