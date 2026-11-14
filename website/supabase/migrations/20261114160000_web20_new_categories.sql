-- =====================================================================================================================
-- web20 · A new type of programme gets its own category (docs/DECISIONS.md D-100). The owner, 14 Nov 2026: BMS and MMS
-- are different programmes from BBA and MBA; "whenever you encounter a new type of program don't forcefully merge into
-- a different category, make new categories if need be, update the website with these with every new category."
--   1. BMS (Bachelor of Management Studies) and MMS (Master of Management Studies) become programme types of their own;
--      the two rules of web18 that listed them with BBA and MBA now point at them.
--   2. From now on the mapper creates what is missing instead of folding it into something else:
--        - a catalogue course with no programme type gets one (web_tax_ensure_programme): its id from the course key,
--          its name as the catalogue writes it, its level from the catalogue, in the group "Other programmes" until an
--          admin places it;
--        - a subject with no category gets one (web_tax_ensure_subject), named as the catalogue writes it, after the
--          markers of web19 are removed and lists are split.
--      The row is flagged for review with a note, so the new category's name and group can be checked in
--      Admin → Taxonomy. At most 40 categories are created in one run; beyond that a row waits under General, flagged.
--   3. The similarity match is kept for near-identical wordings only (0.75 instead of 0.6; a one-letter slip scores about 0.8): "Product Management" was
--      once matched to "Project Management" at 0.6.
-- The filters, the search and the pages read the taxonomy tables, so a new category shows on the website at the next
-- minute poll. Website objects only (web_*); the shared catalogue is only read. Idempotent. Rollback:
-- supabase/rollbacks/20261114160000_web20_new_categories.rollback.sql
-- =====================================================================================================================

insert into public.web_tax_categories (id, label, sort)
values ('other', 'Other programmes', 90) on conflict (id) do nothing;

insert into public.web_tax_programmes (id, short_name, full_name, level_id, category_id, sort, search_prior) values
  ('bms', 'BMS', 'Bachelor of Management Studies', 'ug', 'management', 20, 20),
  ('mms', 'MMS', 'Master of Management Studies', 'pg', 'management', 20, 20)
on conflict (id) do nothing;

update public.web_tax_rules_programme set programme_id = 'bms', note = 'Bachelor of Management Studies: a programme type of its own (web20)'
 where course_key = 'bms' and programme_id = 'bba';
update public.web_tax_rules_programme set programme_id = 'mms', note = 'Master of Management Studies: a programme type of its own (web20)'
 where course_key = 'mms' and programme_id = 'mba';

insert into public.web_tax_synonyms (alias, kind, target_id, source)
select x.alias, 'programme', x.target_id, 'seed' from (values
  ('bms', 'bms'), ('bachelor of management studies', 'bms'),
  ('mms', 'mms'), ('master of management studies', 'mms'), ('masters in management studies', 'mms')
) x(alias, target_id)
where not exists (select 1 from public.web_tax_synonyms s
                   where s.kind = 'programme' and s.alias_compact = replace(public.web_norm(x.alias), ' ', ''))
on conflict do nothing;

-- A programme type for a catalogue course that has none. Returns its id, or null when nothing was created (no course
-- key, or a rule exists already).
create or replace function public.web_tax_ensure_programme(c public.catalog_programs)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare v_id text; v_name text; v_level text;
begin
  if coalesce(btrim(c.course_key), '') = '' then return null; end if;
  if exists (select 1 from public.web_tax_rules_programme r where r.active and r.course_key = c.course_key) then return null; end if;
  v_id := public.web_slugify(c.course_key);
  if v_id is null or v_id !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(v_id) > 60 then return null; end if;
  v_name := left(coalesce(nullif(btrim(regexp_replace(coalesce(c.course, ''), '\s+', ' ', 'g')), ''), upper(c.course_key)), 80);
  v_level := case upper(coalesce(c.level, '')) when 'UG' then 'ug' when 'PG' then 'pg' when 'DIPLOMA' then 'diploma'
                                               when 'CERTIFICATE' then 'certificate' else 'pg' end;
  insert into public.web_tax_programmes (id, short_name, full_name, level_id, category_id, sort, search_prior)
  values (v_id, v_name, v_name, v_level, 'other', 100, 20)
  on conflict (id) do nothing;
  insert into public.web_tax_rules_programme (priority, course_key, programme_id, note)
  values (100, c.course_key, v_id, 'created from the catalogue: check the name, level and group');
  insert into public.web_tax_synonyms (alias, kind, target_id, source)
  select x.alias, 'programme', v_id, 'seed' from (values (c.course_key), (v_name)) x(alias)
   where public.web_norm(x.alias) is not null
     and not exists (select 1 from public.web_tax_synonyms s
                      where s.kind = 'programme' and s.alias_compact = replace(public.web_norm(x.alias), ' ', ''))
  on conflict do nothing;
  return v_id;
end $$;

-- A subject for a wording that has no category. Returns its id, or null when nothing was created (the wording is
-- known already, or is not usable as a name).
create or replace function public.web_tax_ensure_subject(p_name text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')); v_id text;
begin
  if length(v_name) not between 3 and 60 or v_name !~ '[A-Za-z]{3}' then return null; end if;
  if public.web_tax_spec_lookup(v_name) is not null then return null; end if;
  v_id := public.web_slugify(v_name);
  if v_id is null or v_id !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or v_id = 'general' then return null; end if;
  insert into public.web_tax_specialisations (id, name, category_hint) values (v_id, v_name, null)
  on conflict (id) do nothing;
  insert into public.web_tax_synonyms (alias, kind, target_id, source) values (v_name, 'specialisation', v_id, 'seed')
  on conflict do nothing;
  if public.web_tax_spec_lookup(v_name) is null then return null; end if;
  return v_id;
end $$;

revoke all on function public.web_tax_ensure_programme(public.catalog_programs) from public, anon, authenticated;
revoke all on function public.web_tax_ensure_subject(text) from public, anon, authenticated;
grant execute on function public.web_tax_ensure_programme(public.catalog_programs) to service_role;
grant execute on function public.web_tax_ensure_subject(text) to service_role;

-- The proposal: the function as web19 left it, with the similarity bar raised and the unmatched parts reported.
create or replace function public.web_tax_propose(c public.catalog_programs)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_rule public.web_tax_rules_programme;
  v_format text; v_raw text; v_name text; v_tail text; v_capture text;
  v_course_attrs jsonb; v_spec_attrs jsonb; v_clean text; v_ids text[]; v_conf text; v_note text;
  v_attrs jsonb;
  v_core text; v_dformat text; v_dattrs jsonb; v_cattrs jsonb; v_removed text[]; v_pids text[]; v_unmatched text[];
begin
  select * into v_rule from public.web_tax_rules_programme r
   where r.active and r.course_key = c.course_key
     and (r.program_name_re is null or c.program_name ~* r.program_name_re)
   order by r.priority, r.id limit 1;

  v_raw := coalesce(c.specialization, '');
  v_name := coalesce(c.program_name, '');

  -- Delivery formats stored as the specialisation: the subject is inside program_name.
  select f.format into v_format from public.web_tax_rules_format f where f.active and v_raw ~* f.pattern limit 1;
  if v_format is not null then
    if right(v_name, length(v_raw)) = v_raw then
      v_name := regexp_replace(left(v_name, length(v_name) - length(v_raw)), '[\s-]+$', '');
    end if;
    v_raw := coalesce(substring(v_name from '^[^-]*-\s*(.+)$'), 'General');
    v_note := 'format row; subject from program_name';
  else
    -- Repair specialisations the loader cut at a hyphen ("Full-Stack Development" stored as "Stack Development").
    v_tail := btrim(substring(v_name from '^[^-]*-\s*(.+)$'));
    if v_tail is not null and length(v_tail) > length(v_raw) and v_raw <> ''
       and lower(v_tail) like '%' || lower(v_raw) and lower(v_tail) <> lower(v_raw)
       and substring(lower(v_tail) from length(v_tail) - length(v_raw)) ~ '^[-\s]' then
      v_raw := v_tail;
      v_note := 'specialisation repaired from program_name';
    end if;
  end if;

  select a.clean, a.attrs into v_clean, v_spec_attrs from public.web_tax_strip_attributes(v_raw) a;
  select a.attrs into v_course_attrs from public.web_tax_strip_attributes(c.course) a;
  v_attrs := coalesce(v_course_attrs, '{}') || coalesce(v_spec_attrs, '{}');

  select r.ids, r.confidence into v_ids, v_conf from public.web_tax_resolve_spec(v_clean) r;

  -- Generic programmes (diploma, certificate): the subject in the programme name beats a generic stored value.
  if v_rule.spec_from_name_re is not null and (v_ids is null or v_ids = array['general']) then
    v_capture := (regexp_match(c.program_name, v_rule.spec_from_name_re, 'i'))[1];
    if v_capture is not null then
      declare n_ids text[]; n_conf text;
      begin
        select r.ids, r.confidence into n_ids, n_conf from public.web_tax_resolve_spec(v_capture) r;
        if n_ids is not null then
          v_ids := n_ids; v_conf := 'name'; v_clean := initcap(v_capture);
          v_note := concat_ws('; ', v_note, 'specialisation from programme name');
        end if;
      end;
    end if;
  end if;

  -- web19: wordings of the published catalogue. Only when the rules above found nothing: variant and delivery
  -- markers are removed (web_tax_rules_decoration), then the whole text is matched, then each part of a list
  -- ("A + B", "A, B and C"). The published wording stays in spec_display.
  if v_ids is null then
    select d.clean, d.format, d.attrs, d.removed into v_core, v_dformat, v_dattrs, v_removed
      from public.web_tax_strip_decorations(v_clean, c.course) d;
    select a.clean, a.attrs into v_core, v_cattrs from public.web_tax_strip_attributes(v_core) a;
    if coalesce(v_core, '') = '' then v_core := 'General'; v_clean := 'General'; end if;  -- only the course was named
    select r.ids, r.confidence into v_ids, v_conf from public.web_tax_resolve_spec(v_core) r;
    if v_ids is null then
      select p.ids, p.unmatched into v_pids, v_unmatched from public.web_tax_resolve_parts(v_core) p;
      if cardinality(v_pids) > 0 then
        v_ids := v_pids;
        if cardinality(v_unmatched) = 0 then
          v_conf := 'split';
        else
          v_conf := null;  -- flagged for review: some parts have no category yet
          v_note := concat_ws('; ', v_note, 'no category for: ' || array_to_string(v_unmatched, ', '));
        end if;
      end if;
    end if;
    if v_ids is not null then
      v_attrs := v_attrs || coalesce(v_dattrs, '{}') || coalesce(v_cattrs, '{}');
      if v_format is null then v_format := v_dformat; end if;
      if cardinality(v_removed) > 0 then
        v_note := concat_ws('; ', v_note, 'matched without: ' || array_to_string(v_removed, ', '));
      end if;
    end if;
  end if;

  -- Similarity, for near-identical wordings only (a typing mistake); web20 raised the bar from 0.6 to 0.75 so that a
  -- different subject is not folded into a similar-sounding one (flagged for review).
  if v_ids is null and public.web_norm(v_clean) is not null then
    select array[s.target_id], 'fuzzy' into v_ids, v_conf
    from public.web_tax_synonyms s
    where s.kind = 'specialisation' and public.similarity(s.alias_norm, public.web_norm(v_clean)) >= 0.75
    order by public.similarity(s.alias_norm, public.web_norm(v_clean)) desc limit 1;
  end if;

  -- web18: every programme of the catalogue is shown (owner, 14 Nov 2026). A specialisation the taxonomy has no
  -- category for is listed under General; the published wording stays in spec_display, the confidence stays empty
  -- (so the row is flagged for review) and the note says why.
  if v_ids is null and v_rule.programme_id is not null
     and exists (select 1 from public.web_tax_specialisations s where s.id = 'general' and s.active) then
    v_ids := array['general'];
    v_note := concat_ws('; ', v_note, 'no category for this specialisation: listed under General');
  end if;

  return jsonb_build_object(
    'programme_id', v_rule.programme_id,
    'specialisation_ids', to_jsonb(coalesce(v_ids, '{}'::text[])),
    'spec_display', nullif(v_clean, ''),
    'format', v_format,
    'attributes', v_attrs,
    'confidence', v_conf,
    'rule_note', v_note,
    -- web20: the parts no category was found for (empty when the match is firm); web_tax_automap creates them
    'unmatched', case when v_conf is null then to_jsonb(coalesce(v_unmatched, '{}'::text[])) else '[]'::jsonb end
  );
end $function$;

-- The mapper: the function as it was (web3), plus the step marked web20.
create or replace function public.web_tax_automap(p_dry_run boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  c public.catalog_programs; v_map public.web_tax_offering_map; v jsonb; fp text;
  n_new int := 0; n_changed int := 0; n_review int := 0; n_same int := 0;
  n_made int := 0; v_part text; v_made boolean; c_max_made constant int := 40;
begin
  perform public.web_tax_sync_catalog();
  for c in select * from public.catalog_programs order by id loop
    fp := public.web_tax_fingerprint(c);
    select * into v_map from public.web_tax_offering_map where catalog_program_id = c.id;
    if v_map.catalog_program_id is not null and v_map.source_fingerprint = fp then
      n_same := n_same + 1;
      continue;
    end if;
    if v_map.mapped_by = 'admin' then
      n_review := n_review + 1;
      if not p_dry_run then
        update public.web_tax_offering_map set needs_review = true, source_fingerprint = fp, program_key = c.program_key,
          rule_note = 'catalogue row changed after admin mapping', updated_at = now()
        where catalog_program_id = c.id;
      end if;
      continue;
    end if;
    v := public.web_tax_propose(c);
    -- web20 (the owner, 14 Nov 2026: a new type of programme is never folded into another; it gets its own category).
    -- A course with no programme type gets one; a subject with no category gets one. Each is created once, from the
    -- catalogue's own wording, and the row is flagged so that an admin can check the name and the grouping. At most
    -- 40 are created in one run: beyond that a row waits under General, flagged, as before.
    v_made := false;
    if not p_dry_run and v ->> 'programme_id' is null and n_made < c_max_made
       and public.web_tax_ensure_programme(c) is not null then
      n_made := n_made + 1; v_made := true;
      v := public.web_tax_propose(c);
    end if;
    if not p_dry_run and v ->> 'programme_id' is not null and jsonb_array_length(coalesce(v -> 'unmatched', '[]'::jsonb)) > 0 then
      for v_part in select jsonb_array_elements_text(v -> 'unmatched') loop
        exit when n_made >= c_max_made;
        if public.web_tax_ensure_subject(v_part) is not null then n_made := n_made + 1; v_made := true; end if;
      end loop;
      if v_made then v := public.web_tax_propose(c); end if;
    end if;
    if v_made then
      v := v || jsonb_build_object('rule_note', concat_ws('; ', v ->> 'rule_note', 'new category created from the catalogue: check its name and group'));
    end if;
    if v_map.catalog_program_id is null then n_new := n_new + 1; else n_changed := n_changed + 1; end if;
    if not p_dry_run then
      insert into public.web_tax_offering_map as t (catalog_program_id, program_key, programme_id, specialisation_ids,
        spec_display, format, attributes, mapped_by, confidence, rule_note, source_fingerprint, needs_review, updated_at)
      values (c.id, c.program_key, v->>'programme_id',
        array(select jsonb_array_elements_text(v->'specialisation_ids')),
        v->>'spec_display', v->>'format', v->'attributes', 'rule', v->>'confidence', v->>'rule_note', fp,
        coalesce(v->>'confidence', 'none') in ('fuzzy', 'none') or v->>'programme_id' is null or v_made, now())
      on conflict (catalog_program_id) do update set
        program_key = excluded.program_key, programme_id = excluded.programme_id,
        specialisation_ids = excluded.specialisation_ids, spec_display = excluded.spec_display, format = excluded.format,
        attributes = excluded.attributes, confidence = excluded.confidence, rule_note = excluded.rule_note,
        source_fingerprint = excluded.source_fingerprint, needs_review = excluded.needs_review, updated_at = now()
      where t.mapped_by = 'rule';
    end if;
  end loop;
  return jsonb_build_object('new', n_new, 'changed', n_changed, 'admin_needs_review', n_review, 'unchanged', n_same,
    'categories_created', n_made,
    'dry_run', p_dry_run,
    'unmapped', (select count(*) from public.catalog_programs cp left join public.web_tax_offering_map om on om.catalog_program_id = cp.id
                 where cp.active and (om.programme_id is null or cardinality(om.specialisation_ids) = 0)));
end $function$;

-- Once: BMS and MMS move to their own programme types.
do $$
declare c public.catalog_programs; v jsonb;
begin
  for c in select cp.* from public.catalog_programs cp join public.web_tax_offering_map om on om.catalog_program_id = cp.id
            where om.mapped_by = 'rule' and cp.course_key in ('bms', 'mms') order by cp.id loop
    v := public.web_tax_propose(c);
    update public.web_tax_offering_map set
           programme_id = v ->> 'programme_id',
           specialisation_ids = array(select jsonb_array_elements_text(v -> 'specialisation_ids')),
           spec_display = v ->> 'spec_display', format = v ->> 'format', attributes = v -> 'attributes',
           confidence = v ->> 'confidence', rule_note = v ->> 'rule_note',
           needs_review = coalesce(v ->> 'confidence', 'none') in ('fuzzy', 'none') or v ->> 'programme_id' is null,
           updated_at = now()
     where catalog_program_id = c.id and mapped_by = 'rule';
  end loop;
end $$;
