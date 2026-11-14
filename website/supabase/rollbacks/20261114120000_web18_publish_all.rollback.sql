-- Rollback of 20261114120000_web18_publish_all.sql: web_tax_propose as it was (web3). The two programme rules for BMS and
-- MMS are removed. Rows already listed under General keep their mapping until the catalogue row changes or an admin
-- maps them; to hide them again, clear specialisation_ids where rule_note like '%listed under General%'.
delete from public.web_tax_rules_programme where course_key in ('bms', 'mms') and note like '%(web18)';

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
