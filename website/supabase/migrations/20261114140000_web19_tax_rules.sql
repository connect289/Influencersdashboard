-- =====================================================================================================================
-- web19 · Each programme under its proper subject (docs/DECISIONS.md D-099). The catalogue published through Eduwit
-- Scout words many specialisations in ways the mapper did not know, so 150 programmes were listed under General (web18)
-- and 270 were matched only by similarity. The owner: "put each under its proper subject." Deterministic rules only:
--   1. Markers around a specialisation ("_MS", "_CAPM", " - Online", " - WLP", "(Work-Linked)", "(Capston)",
--      "BBA General with Internship", "Dual (…)" …) are removed before matching. The list is data
--      (public.web_tax_rules_decoration, one row per marker); the published wording stays in spec_display.
--   2. Lists ("A + B", "A, B and C") are matched part by part and every matched subject is stored. If a part has no
--      category, the others are used and the row is flagged for review, with the part named in rule_note.
--   3. Seven subjects the taxonomy did not have are added (Pharmaceutical Management, Aviation & Airport Management,
--      Media & Entertainment Management, Disaster Management, Product Management, Sustainability & ESG, Kannada), with
--      aliases for other wordings of existing subjects ("Hospital & Healthcare Management", "Financial Management" …).
--   4. Both new steps run only where the rules as they were found nothing, so a row that was exact / synonym / split
--      keeps its subjects; the similarity match and the General fallback (web18) stay behind them as last resorts.
--   5. The rows that were matched by similarity or listed under General are proposed again once, here.
-- Website objects only (web_*); the shared catalogue is only read. Idempotent. Rollback:
-- supabase/rollbacks/20261114140000_web19_tax_rules.rollback.sql
-- =====================================================================================================================

-- 1. Markers (data). pattern: a case-insensitive regular expression over the specialisation text; what it matches is
--    replaced by replace_with. "{course}" stands for the row's own course as published ("B.Com"). format / attribute
--    are set only where the catalogue spells the meaning out.
create table if not exists public.web_tax_rules_decoration (
  id integer generated always as identity primary key,
  priority integer not null default 100,
  pattern text not null unique,
  replace_with text not null default ' ',
  format text references public.web_tax_formats (id),
  attribute text check (attribute ~ '^[a-z_]+$'),
  note text,
  active boolean not null default true
);
alter table public.web_tax_rules_decoration enable row level security;
revoke all on public.web_tax_rules_decoration from anon, authenticated, public;
grant select, insert, update, delete on public.web_tax_rules_decoration to service_role;

insert into public.web_tax_rules_decoration (priority, pattern, replace_with, format, attribute) values
  (10, '^\s*dual\s*\((.+)\)\s*$', '\1', null, null),
  (20, '^\s*{course}(?:\s+|$)', ' ', null, null),
  (30, '\(\s*work[- ]linked\s*\)', ' ', 'work-linked', null),
  (30, '\(\s*wilp\s*\)', ' ', null, null),
  (30, '\(\s*aedp\s*\)', ' ', null, null),
  (30, '\(\s*wlp\s*\)', ' ', null, null),
  (30, '\(\s*odl\s*\)', ' ', null, null),
  (30, '\(\s*capstone?\s*\)', ' ', null, null),
  (30, '\(\s*ica\s*\)', ' ', null, null),
  (30, '\(\s*acca\s*\)', ' ', null, null),
  (30, '\(\s*industry\s*\)', ' ', null, null),
  (30, '\(\s*medavarsity\s*\)', ' ', null, null),
  (30, '\(\s*dpa\s*\)', ' ', null, null),
  (30, '\(\s*addra\s*\)', ' ', null, null),
  (30, '\(\s*environmental,\s*social\s*(?:&|and)\s*governance\s*\)', ' ', null, null),
  (40, '_\s*ms\s*$', ' ', null, null),
  (40, '_\s*capm\s*$', ' ', null, null),
  (40, '(?:\s+-)?\s+online\s*$', ' ', null, null),
  (40, '\s+-\s+odl\s*$', ' ', null, null),
  (40, '\s+-\s+wlp\s*$', ' ', null, null),
  (40, '\s+-\s+wip\s*$', ' ', null, null),
  (40, '\s+-\s+aedp\s*$', ' ', null, null),
  (40, '\s+-\s+microsoft\s*$', ' ', null, null),
  (40, '\s+-\s+capm\s*(?:&|and)\s*pwc\s+certification\s*$', ' ', null, null),
  (40, '\s+with\s+internship\s*$', ' ', null, 'internship'),
  (50, '\s+-\s+general\s*$', ' ', null, null),
  (60, '\s+(?:course|program(?:me)?)\s*$', ' ', null, null)
on conflict (pattern) do nothing;

-- Removes every marker (repeated until nothing changes, so their order in the text does not matter).
create or replace function public.web_tax_strip_decorations(p text, p_course text, out clean text, out format text,
                                                            out attrs jsonb, out removed text[])
language plpgsql stable security definer set search_path = '' as $$
declare r record; v_pat text; v_course text; v_before text; v_hit text; i int;
begin
  clean := btrim(coalesce(p, '')); attrs := '{}'; removed := '{}';
  v_course := regexp_replace(btrim(regexp_replace(coalesce(p_course, ''), '\s*\(.*$', '')), '([][\\.^$*+?(){}|-])', '\\\1', 'g');
  for i in 1 .. 5 loop
    v_before := clean;
    for r in select * from public.web_tax_rules_decoration d where d.active order by d.priority, d.id loop
      v_pat := r.pattern;
      if position('{course}' in v_pat) > 0 then
        continue when v_course = '';
        v_pat := replace(v_pat, '{course}', v_course);
      end if;
      continue when clean !~* v_pat;
      -- what is removed is noted, except for a wrapper ("Dual (…)"), whose content stays
      if position('\1' in r.replace_with) = 0 then
        v_hit := (regexp_match(clean, '(' || v_pat || ')', 'i'))[1];
        removed := removed || btrim(regexp_replace(coalesce(v_hit, ''), '\s+', ' ', 'g'));
      end if;
      clean := btrim(regexp_replace(regexp_replace(clean, v_pat, r.replace_with, 'i'), '\s+', ' ', 'g'));
      if r.format is not null and format is null then format := r.format; end if;
      if r.attribute is not null then attrs := attrs || jsonb_build_object(r.attribute, true); end if;
    end loop;
    exit when clean = v_before;
  end loop;
end $$;

-- A list of subjects: parts separated by "+" or ","; each part is matched on its own (whole phrase, or two known
-- parts around an "and", as web_tax_resolve_spec does). ids keeps the published order without repeats.
create or replace function public.web_tax_resolve_parts(p text, out ids text[], out unmatched text[])
language plpgsql stable security definer set search_path = '' as $$
declare v_part text; v_ids text[]; v_id text;
begin
  ids := '{}'; unmatched := '{}';
  foreach v_part in array regexp_split_to_array(coalesce(p, ''), '\s*[+,]\s*') loop
    v_part := btrim(regexp_replace(btrim(v_part), '^(?:and|&)\s+', '', 'i'));
    continue when v_part = '';
    select r.ids into v_ids from public.web_tax_resolve_spec(v_part) r;
    if v_ids is null then
      unmatched := unmatched || v_part;
    else
      foreach v_id in array v_ids loop
        if not v_id = any (ids) then ids := ids || v_id; end if;
      end loop;
    end if;
  end loop;
end $$;

revoke all on function public.web_tax_strip_decorations(text, text) from public, anon, authenticated;
revoke all on function public.web_tax_resolve_parts(text) from public, anon, authenticated;
grant execute on function public.web_tax_strip_decorations(text, text) to service_role;
grant execute on function public.web_tax_resolve_parts(text) to service_role;

-- 2. Subjects the taxonomy did not have, and other wordings of the ones it has. An alias is added only when its
--    spelling is not known yet, so nothing that matched before matches differently.
insert into public.web_tax_specialisations (id, name, category_hint)
select x.id, x.name, x.category_hint from (values
  ('pharmaceutical-management', 'Pharmaceutical Management', 'management'),
  ('aviation-management', 'Aviation & Airport Management', 'management'),
  ('media-entertainment', 'Media & Entertainment Management', 'management'),
  ('disaster-management', 'Disaster Management', 'management'),
  ('product-management', 'Product Management', 'management'),
  ('sustainability-esg', 'Sustainability & ESG', 'management'),
  ('kannada', 'Kannada', 'arts-humanities')
) x(id, name, category_hint)
on conflict (id) do nothing;

insert into public.web_tax_synonyms (alias, kind, target_id, source)
select x.alias, 'specialisation', x.target_id, 'seed' from (values
  ('Pharmaceutical Management', 'pharmaceutical-management'),
  ('Aviation & Airport Management', 'aviation-management'),
  ('Media & Entertainment Management', 'media-entertainment'),
  ('Disaster Management', 'disaster-management'),
  ('Product Management', 'product-management'),
  ('Sustainability & ESG', 'sustainability-esg'),
  ('Kannada', 'kannada'),
  ('Pharmaceutical Management', 'pharmaceutical-management'),
  ('Airlines & Airport Management', 'aviation-management'),
  ('Aviation Management', 'aviation-management'),
  ('Entertainment and Media', 'media-entertainment'),
  ('Media and Entertainment', 'media-entertainment'),
  ('Disaster Management', 'disaster-management'),
  ('Product Management', 'product-management'),
  ('ESG', 'sustainability-esg'),
  ('Sustainability & ESG', 'sustainability-esg'),
  ('ESG Environmental, Social & Governance', 'sustainability-esg'),
  ('Sustainability', 'sustainability-esg'),
  ('Kannada', 'kannada'),
  ('Banking & Financial Services', 'banking-insurance'),
  ('Banking & Insurance', 'banking-insurance'),
  ('Banking and Finance', 'banking-insurance'),
  ('Banking', 'banking-insurance'),
  ('Hospital & Healthcare Management', 'healthcare-management'),
  ('Hospital Administration', 'healthcare-management'),
  ('Hospital Management', 'healthcare-management'),
  ('Healthcare Management', 'healthcare-management'),
  ('Business Intelligence & Business Analytics', 'business-analytics'),
  ('Business Analysis', 'business-analytics'),
  ('Information Technology Management', 'information-technology'),
  ('Information Technology', 'information-technology'),
  ('IT', 'information-technology'),
  ('Logistics & Supply Chain Management', 'supply-chain-management'),
  ('Logistics & Supply Chain', 'supply-chain-management'),
  ('Supply Chain Management', 'supply-chain-management'),
  ('Finance Management', 'finance'),
  ('Financial Management', 'finance'),
  ('Marketing Management', 'marketing'),
  ('Marketing & Sales Management', 'marketing'),
  ('Brand Management', 'marketing'),
  ('Digital Marketing Management', 'digital-marketing'),
  ('Accounting Management', 'accounting-taxation'),
  ('Accounting', 'accounting-taxation'),
  ('Taxation', 'accounting-taxation'),
  ('Global Financial Reporting', 'accounting-taxation'),
  ('Leadership Management', 'strategy-leadership'),
  ('Production and Operations Management', 'operations-management'),
  ('International Business Management', 'international-business'),
  ('Foreign Exchange Management', 'international-finance'),
  ('Intenational Finance', 'international-finance'),
  ('Family Business', 'entrepreneurship'),
  ('AI for Business', 'ai-ml'),
  ('Agentic AI', 'ai-ml'),
  ('Agentic AI & Intelligent Systems', 'ai-ml'),
  ('Generative AI & Agentic Systems', 'ai-ml'),
  ('Generative AI and Intelligent Application', 'ai-ml'),
  ('AI & ML', 'ai-ml'),
  ('AI & Machine Learning', 'ai-ml'),
  ('AI', 'ai-ml'),
  ('Data & AI', 'ai-ml'),
  ('Decision Science', 'data-science'),
  ('Next-Gen Technologies & Digital Intelligence', 'emerging-technologies'),
  ('ERP & Digital Transformation', 'digital-business'),
  ('Fintech and Digital Financial Services', 'fintech'),
  ('Financial Technology', 'fintech'),
  ('Accounting Analytics', 'financial-analytics'),
  ('Digital Finance & Accountinc Analytics', 'financial-analytics'),
  ('Digital Finance & Accounting Analytics', 'financial-analytics'),
  ('Web Development', 'software-development'),
  ('Full Stack Software Development', 'software-development'),
  ('Full Stack Development', 'software-development'),
  ('Global Economics', 'economics'),
  ('Development Economics', 'economics'),
  ('Politics', 'political-science'),
  ('Tourism', 'tourism-management'),
  ('Tourism & Travel Management', 'tourism-management'),
  ('Hospitality', 'hospitality-management'),
  ('Retail', 'retail-management'),
  ('E-Commerce', 'e-commerce'),
  ('Professional Arabic', 'arabic'),
  ('Premium', 'general')
) x(alias, target_id)
where not exists (select 1 from public.web_tax_synonyms s
                   where s.kind = 'specialisation' and s.alias_compact = replace(public.web_norm(x.alias), ' ', ''))
on conflict do nothing;

-- 3. The proposal: the function as it was (web18) plus the step marked web19.
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

-- 4. Once: the rows matched by similarity or listed under General are proposed again with the rules above.
do $$
declare c public.catalog_programs; v jsonb;
begin
  for c in select cp.* from public.catalog_programs cp join public.web_tax_offering_map om on om.catalog_program_id = cp.id
            where om.mapped_by = 'rule' and (om.confidence is null or om.confidence = 'fuzzy')
            order by cp.id loop
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
