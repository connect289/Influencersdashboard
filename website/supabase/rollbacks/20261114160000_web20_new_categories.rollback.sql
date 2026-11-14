-- Rollback of 20261114160000_web20_new_categories.sql: web_tax_propose as web19 left it and web_tax_automap as it was
-- (web3). The programme types BMS and MMS, the group "Other programmes" and any category created since stay (rows point
-- at them); to list BMS with BBA and MMS with MBA again, point the two rules of web_tax_rules_programme back.
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

  -- Fuzzy fallback (flagged for review).
  if v_ids is null and public.web_norm(v_clean) is not null then
    select array[s.target_id], 'fuzzy' into v_ids, v_conf
    from public.web_tax_synonyms s
    where s.kind = 'specialisation' and public.similarity(s.alias_norm, public.web_norm(v_clean)) >= 0.6
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
    'rule_note', v_note
  );
end $function$;

create or replace function public.web_tax_automap(p_dry_run boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  c public.catalog_programs; v_map public.web_tax_offering_map; v jsonb; fp text;
  n_new int := 0; n_changed int := 0; n_review int := 0; n_same int := 0;
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
    if v_map.catalog_program_id is null then n_new := n_new + 1; else n_changed := n_changed + 1; end if;
    if not p_dry_run then
      insert into public.web_tax_offering_map as t (catalog_program_id, program_key, programme_id, specialisation_ids,
        spec_display, format, attributes, mapped_by, confidence, rule_note, source_fingerprint, needs_review, updated_at)
      values (c.id, c.program_key, v->>'programme_id',
        array(select jsonb_array_elements_text(v->'specialisation_ids')),
        v->>'spec_display', v->>'format', v->'attributes', 'rule', v->>'confidence', v->>'rule_note', fp,
        coalesce(v->>'confidence', 'none') in ('fuzzy', 'none') or v->>'programme_id' is null, now())
      on conflict (catalog_program_id) do update set
        program_key = excluded.program_key, programme_id = excluded.programme_id,
        specialisation_ids = excluded.specialisation_ids, spec_display = excluded.spec_display, format = excluded.format,
        attributes = excluded.attributes, confidence = excluded.confidence, rule_note = excluded.rule_note,
        source_fingerprint = excluded.source_fingerprint, needs_review = excluded.needs_review, updated_at = now()
      where t.mapped_by = 'rule';
    end if;
  end loop;
  return jsonb_build_object('new', n_new, 'changed', n_changed, 'admin_needs_review', n_review, 'unchanged', n_same,
    'dry_run', p_dry_run,
    'unmapped', (select count(*) from public.catalog_programs cp left join public.web_tax_offering_map om on om.catalog_program_id = cp.id
                 where cp.active and (om.programme_id is null or cardinality(om.specialisation_ids) = 0)));
end $function$;
