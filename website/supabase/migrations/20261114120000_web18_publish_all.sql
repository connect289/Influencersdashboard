-- =====================================================================================================================
-- web18 · Every programme of the catalogue is shown (docs/DECISIONS.md D-098). On 14 Nov 2026 the shared programme list
-- was replaced by the catalogue published through Eduwit Scout: 1,141 programmes at 38 universities. The auto-mapper
-- left 151 of them hidden ("unmapped"): 149 had a specialisation wording the taxonomy has no category for (variants
-- such as "Brand Management_MS", double specialisations such as "Business Analytics + Digital Marketing", and new
-- subjects), and 2 had a course with no taxonomy programme (BMS, MMS). The owner: "publish all program in the
-- catalogue."
--   1. web_tax_propose is the function as it was, plus one last step: when no specialisation was recognised, the
--      programme is listed under General. The card and the page keep the published wording (spec_display); the row is
--      flagged needs_review (its confidence stays empty) and rule_note says why, so an admin can give it its own
--      category in Admin → Taxonomy. Rows that had a specialisation keep exactly what they had.
--   2. BMS (Bachelor of Management Studies) is listed with BBA and MMS (Master of Management Studies) with MBA: two
--      rows in web_tax_rules_programme.
--   3. The rule-mapped rows that are hidden today are proposed again once, here (the minute poll only re-proposes a row
--      when its catalogue row changes). Rows mapped by an admin are not touched.
-- Website objects only (web_*); the shared catalogue is only read. Idempotent. Rollback:
-- supabase/rollbacks/20261114120000_web18_publish_all.rollback.sql
-- =====================================================================================================================

insert into public.web_tax_rules_programme (priority, course_key, programme_id, note)
select 100, x.course_key, x.programme_id, x.note
  from (values ('bms', 'bba', 'Bachelor of Management Studies: listed with BBA (web18)'),
               ('mms', 'mba', 'Master of Management Studies: listed with MBA (web18)')) x(course_key, programme_id, note)
 where not exists (select 1 from public.web_tax_rules_programme r where r.course_key = x.course_key);

create or replace function public.web_tax_propose(c public.catalog_programs)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_rule public.web_tax_rules_programme;
  v_format text; v_raw text; v_name text; v_tail text; v_capture text;
  v_course_attrs jsonb; v_spec_attrs jsonb; v_clean text; v_ids text[]; v_conf text; v_note text;
  v_attrs jsonb;
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

-- Once: the hidden rule-mapped rows are proposed again with the function above.
do $$
declare c public.catalog_programs; v jsonb;
begin
  for c in select cp.* from public.catalog_programs cp join public.web_tax_offering_map om on om.catalog_program_id = cp.id
            where om.mapped_by = 'rule' and (om.programme_id is null or cardinality(om.specialisation_ids) = 0)
            order by cp.id loop
    v := public.web_tax_propose(c);
    update public.web_tax_offering_map set
           programme_id = v ->> 'programme_id',
           specialisation_ids = array(select jsonb_array_elements_text(v -> 'specialisation_ids')),
           spec_display = v ->> 'spec_display', format = v ->> 'format', attributes = v -> 'attributes',
           confidence = v ->> 'confidence', rule_note = v ->> 'rule_note',
           needs_review = true, updated_at = now()
     where catalog_program_id = c.id and mapped_by = 'rule';
  end loop;
end $$;
