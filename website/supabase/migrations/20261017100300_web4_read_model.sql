-- web4_read_model — the search read model and query functions (spec 3A read path, 6.2–6.4, 6.6).
-- `web_offering_search` is built from an explicit allow-list of catalogue columns (no commission/partner/internal
-- fields), refreshed off the request path when the catalogue fingerprint changes (polling; no trigger is added to the
-- shared tables). One function per query returns results and facet counts in a single round trip.

insert into public.web_settings (key, value, description) values
  ('finder_page_size', '20', 'Programme groups (or offerings in the flat view) per page in the finder.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------
-- Derived facts (docs/TAXONOMY_PROPOSAL.md §4): every value carries its source; unknown stays unknown.

create or replace function public.web_derive_duration(p_elig text, p_fee_other jsonb, p_total numeric, p_yearly numeric, p_semester numeric)
returns jsonb language plpgsql immutable security definer set search_path = '' as $$
declare
  m text[]; v_months int; k text; n int; v_year_key int; v_sem_key int; r numeric;
  c_year_key numeric; c_sem_key numeric; c_ratio_y numeric; c_ratio_s numeric; cand numeric[]; x numeric; hits int;
begin
  m := regexp_match(coalesce(p_elig, ''), '\mduration\s*(?:of\s*|is\s*|:\s*|-\s*)?(\d+(?:\.\d+)?)\s*(years?|yrs?|months?|semesters?)\M', 'i');
  if m is not null then
    v_months := round(case when m[2] ~* '^y' then m[1]::numeric * 12 when m[2] ~* '^m' then m[1]::numeric
                          else m[1]::numeric * 6 end);
    if v_months between 1 and 72 then
      return jsonb_build_object('months', v_months, 'source', 'eligibility_text', 'snippet', m[1] || ' ' || m[2]);
    end if;
  end if;

  for k in select jsonb_object_keys(coalesce(p_fee_other, '{}')) loop
    if k ~* '^year\s+[\d,&\s]+$' then
      select max(d::int) into n from regexp_split_to_table(regexp_replace(k, '[^\d]+', ' ', 'g'), ' ') d where d <> '';
      v_year_key := greatest(coalesce(v_year_key, 0), n);
    elsif k ~* '^semester\s+[\d,&\s]+$' or k ~* '\msem(ester)?\s+[\d,&\s]+\)?$' then
      select max(d::int) into n from regexp_split_to_table(regexp_replace(k, '[^\d]+', ' ', 'g'), ' ') d where d <> '';
      v_sem_key := greatest(coalesce(v_sem_key, 0), n);
    end if;
  end loop;
  if v_year_key between 2 and 6 then c_year_key := v_year_key; end if;
  if v_sem_key between 2 and 12 then c_sem_key := v_sem_key / 2.0; end if;
  if p_total > 0 and p_yearly > 0 then
    r := p_total / p_yearly;
    if r between 0.95 and 6.3 and abs(r - round(r)) <= 0.05 * r then c_ratio_y := round(r); end if;
  end if;
  if p_total > 0 and p_semester > 0 then
    r := p_total / p_semester;
    if r between 1.9 and 12.6 and abs(r - round(r)) <= 0.05 * r then c_ratio_s := round(r) / 2.0; end if;
  end if;
  cand := array_remove(array[c_year_key, c_sem_key, c_ratio_y, c_ratio_s], null);
  foreach x in array cand loop
    select count(*) into hits from unnest(cand) y where y = x;
    if hits >= 2 then
      return jsonb_build_object('months', round(x * 12)::int, 'source', 'fee_schedule',
        'snippet', concat_ws(', ', 'year keys: ' || v_year_key, 'semester keys: ' || v_sem_key,
                             'total/yearly: ' || c_ratio_y, 'total/semester: ' || round(c_ratio_s * 2)));
    end if;
  end loop;
  return null;
end $$;

create or replace function public.web_naac_rank(p_grade text)
returns int language sql immutable parallel safe as $$
  select case p_grade when 'A++' then 7 when 'A+' then 6 when 'A' then 5 when 'B++' then 4 when 'B+' then 3
                      when 'B' then 2 when 'C' then 1 else 0 end
$$;

-- Parses approvals, NAAC and NIRF from the catalogue's structured accreditation text. Only explicit statements count.
create or replace function public.web_university_facts(p_text text, p_recognitions text[])
returns jsonb language plpgsql immutable security definer set search_path = '' as $$
declare
  t text := coalesce(p_text, '');
  s_status text; s_deb text; s_naac text; s_nat text; s_prog text;
  v_deb text; v_naac text; v_naac_accr boolean := false; v_aicte boolean;
  e text; v_rank int; v_band text; v_year int; v_cat text;
  best jsonb; progs jsonb := '[]'; v_best_key numeric; v_key numeric;
  not_stated constant text := '^\s*(not stated|n/a\M|none\M)';
begin
  s_status := btrim(substring(t from 'National Statutory Status:(.*?)Distance/Online Education Approvals'));
  s_deb := btrim(substring(t from 'Distance/Online Education Approvals:(.*?)NAAC Rating'));
  s_naac := btrim(substring(t from 'NAAC Rating & Specific Cycle Score:(.*?)Global/International'));
  s_nat := btrim(substring(t from 'National Institutional Standing \(Rank/Year/Agency\):(.*?)Program-Specific'));
  s_prog := btrim(btrim(substring(t from 'Program-Specific National Rankings \(Rank/Program/Year/Agency\):(.*?)(?:Enrollment|$)')), ' "');

  if s_deb is not null and s_deb !~* not_stated and s_deb ~* '(ugc[- ]?deb|distance education bureau|ugc[- ]entitled)' then
    v_deb := case when s_deb ~* 'entitled' then 'entitled' when s_deb ~* 'approved' then 'approved'
                  when s_deb ~* 'recogni[sz]ed' then 'recognised' else 'stated' end;
  end if;

  if s_naac is not null and s_naac !~* not_stated then
    v_naac := (regexp_match(s_naac, '(?:^|[^A-Za-z+])(A\+\+|A\+|A|B\+\+|B\+|B|C)(?:[^A-Za-z+]|$)'))[1];
    v_naac_accr := s_naac ~* '(naac|grade|accredit)';
  end if;

  v_aicte := exists (select 1 from unnest(coalesce(p_recognitions, '{}')) r where r ~* 'aicte')
             or coalesce(s_status, '') ~* 'aicte';

  -- NIRF: only entries whose text names NIRF; rank from "#N", "Ranked N", "Rank N", "No. N" or an ordinal; else a band.
  for e in select btrim(x) from regexp_split_to_table(coalesce(s_nat, ''), ';') x loop
    continue when e !~* '(nirf|national institutional ranking framework)';
    v_rank := coalesce((regexp_match(e, '#\s*(\d+)'))[1], (regexp_match(e, '(?:ranked|rank|no\.)\s*#?\s*(\d+)', 'i'))[1],
                       (regexp_match(e, '\m(\d+)(?:st|nd|rd|th)\M', 'i'))[1])::int;
    v_band := case when v_rank is null then coalesce((regexp_match(e, 'band\s+(\d+\s*[–-]\s*\d+)', 'i'))[1],
                                                     'Top ' || (regexp_match(e, 'top\s+(\d+)', 'i'))[1]) end;
    continue when v_rank is null and v_band is null;
    v_year := coalesce((regexp_match(e, 'NIRF\s*(20\d\d)', 'i'))[1], (regexp_match(e, '/\s*(20\d\d)\s*(?:/|$)'))[1])::int;
    v_cat := case when e ~* 'overall' then 'Overall' when e ~* 'universit' then 'University'
                  when e ~* 'engineering' then 'Engineering' when e ~* 'management' then 'Management' end;
    -- Prefer the most recent year, then a numeric rank over a band, then the best rank.
    v_key := coalesce(v_year, 1900) * 100000 + case when v_rank is not null then 50000 - v_rank else 0 end;
    if best is null or v_key > v_best_key then
      best := jsonb_strip_nulls(jsonb_build_object('rank', v_rank, 'band', v_band, 'year', v_year, 'category', v_cat, 'statement', e));
      v_best_key := v_key;
    end if;
  end loop;
  for e in select btrim(x) from regexp_split_to_table(coalesce(s_prog, ''), ';') x loop
    continue when e !~* '(nirf|national institutional ranking framework)';
    v_rank := coalesce((regexp_match(e, '#\s*(\d+)'))[1], (regexp_match(e, '(?:ranked|rank|no\.)\s*#?\s*(\d+)', 'i'))[1],
                       (regexp_match(e, '\m(\d+)(?:st|nd|rd|th)\M', 'i'))[1])::int;
    v_band := case when v_rank is null then 'Top ' || (regexp_match(e, 'top\s+(\d+)', 'i'))[1] end;
    continue when v_rank is null and v_band is null;
    v_year := coalesce((regexp_match(e, 'NIRF\s*(20\d\d)', 'i'))[1], (regexp_match(e, '/\s*(20\d\d)\s*(?:/|$)'))[1])::int;
    progs := progs || jsonb_strip_nulls(jsonb_build_object('discipline', nullif(btrim(regexp_replace(split_part(e, '/', 2), '\s*category\s*$', '', 'i')), ''),
      'rank', v_rank, 'band', v_band, 'year', v_year, 'statement', e));
  end loop;

  return jsonb_strip_nulls(jsonb_build_object(
    'ugc_deb', v_deb, 'ugc_deb_statement', case when v_deb is not null then s_deb end,
    'naac_grade', v_naac, 'naac_accredited', case when v_naac_accr then true end,
    'naac_statement', case when v_naac_accr then s_naac end,
    'aicte', case when v_aicte then true end,
    'nirf', best, 'nirf_programmes', case when jsonb_array_length(progs) > 0 then progs end));
end $$;

-- Eligibility (spec 6.2). Mirrored in web/lib/finder/eligibility.ts (tested against the same table).
-- p_qual: 10th | 12th | diploma | graduation | postgraduation. Returns eligible | check | not_eligible, or null.
create or replace function public.web_eligibility(p_qual text, p_level text, p_min_q text)
returns text language sql immutable parallel safe as $$
  select case
    when p_qual is null then null
    when p_min_q is null then 'check'
    when p_qual = 'diploma' and p_min_q = 'DIPLOMA' then 'eligible'
    when p_qual = 'diploma' and p_min_q = '12TH' then 'check'
    when (case p_qual when '10th' then 1 when '12th' then 2 when 'diploma' then 2 when 'graduation' then 3 when 'postgraduation' then 4 end)
      >= (case p_min_q when '12TH' then 2 when 'DIPLOMA' then 2 when 'BACHELOR' then 3 when 'MASTER' then 4 else 9 end) then 'eligible'
    -- UG rows that say a bachelor's degree is required contradict themselves (data report): never "not eligible".
    when p_level = 'ug' and p_min_q in ('BACHELOR', 'MASTER') then 'check'
    else 'not_eligible'
  end
$$;

create or replace function public.web_duration_bucket(p_months int)
returns text language sql immutable parallel safe as $$
  select case when p_months is null then null when p_months <= 12 then 'le12' when p_months <= 24 then '13-24'
              when p_months <= 36 then '25-36' else 'gt36' end
$$;

-- ---------------------------------------------------------------------------------------------------------------
create materialized view if not exists public.web_offering_search as
with uni as (
  select u.id, u.name, u.short_name, u.institution_type, p.slug, p.display_name, p.logo_path, p.logo_permitted, p.state,
         coalesce(p.published, true) as published,
         public.web_university_facts(u.accreditation_text, u.recognitions) || coalesce(p.facts_override, '{}') as f
  from public.catalog_universities u
  left join public.web_university_profiles p on p.catalog_university_id = u.id
), regular as (
  select coalesce((select value = 'true'::jsonb from public.web_settings where key = 'finder_include_regular_mode'), false) as include_regular
), prog_alias as (
  select target_id as id, string_agg(alias_norm, ' ') as txt from public.web_tax_synonyms where kind = 'programme' group by target_id
), spec_sets as (
  select ids, (select string_agg(s.name, ' + ' order by array_position(ids, s.id)) from public.web_tax_specialisations s where s.id = any(ids)) as name,
         (select string_agg(y.alias_norm, ' ') from public.web_tax_synonyms y where y.kind = 'specialisation' and y.target_id = any(ids)) as aliases,
         (select s.category_hint from public.web_tax_specialisations s where s.id = ids[1]) as category_hint
  from (select distinct specialisation_ids as ids from public.web_tax_offering_map) d
), base as (
  select c.id, c.program_key, c.university_id, c.program_name, c.mode, c.active, c.fee_total, c.fee_yearly,
         c.fee_semester, c.fee_exam, c.fee_registration, c.fee_other, c.flags, c.min_qualification, c.min_pct_general,
         c.min_pct_reserved, c.eligibility_text, c.brochure_url, c.updated_at,
         m.programme_id, m.specialisation_ids, m.spec_display, m.format, m.attributes, m.hidden_reason as map_hidden,
         pr.short_name as programme_name, pr.full_name as programme_full, pr.level_id, pr.active as programme_active,
         pr.sort as programme_sort, pr.search_prior as programme_prior,
         coalesce(pr.category_id, ss.category_hint, 'management') as category_id,
         ss.name as spec_name, ss.aliases as spec_aliases, pa.txt as programme_aliases
  from public.catalog_programs c
  left join public.web_tax_offering_map m on m.catalog_program_id = c.id
  left join public.web_tax_programmes pr on pr.id = m.programme_id
  left join spec_sets ss on ss.ids = m.specialisation_ids
  left join prog_alias pa on pa.id = m.programme_id
)
select
  b.id, b.program_key, b.university_id,
  uni.slug as uni_slug, coalesce(uni.display_name, uni.name) as uni_name, uni.short_name as uni_short,
  uni.institution_type as uni_type, case when uni.logo_permitted then uni.logo_path end as uni_logo, uni.state as uni_state,
  b.level_id, lv.label as level_label, lv.short_label as level_short, lv.sort as level_sort,
  b.category_id, cat.label as category_label,
  b.programme_id, b.programme_name, b.programme_full, b.programme_sort, coalesce(b.programme_prior, 0) as programme_prior,
  b.specialisation_ids as spec_ids, b.specialisation_ids[1] as spec_primary, b.spec_name,
  b.programme_id || ':' || array_to_string(b.specialisation_ids, '+') as group_key,
  b.spec_display, b.format, coalesce(b.attributes, '{}') as attributes, b.mode,
  b.fee_total, b.fee_yearly, b.fee_semester, b.fee_exam, b.fee_registration,
  case when b.fee_other->>'Emi' ~ '^\d+(\.\d+)?$' then (b.fee_other->>'Emi')::numeric end as emi_amount,
  coalesce('fee on request' = any(b.flags), false) or b.fee_total is null as fee_on_request,
  (d.dur->>'months')::int as duration_months, d.dur->>'source' as duration_source, d.dur->>'snippet' as duration_snippet,
  b.min_qualification, b.min_pct_general, b.min_pct_reserved,
  (regexp_match(coalesce(b.eligibility_text, ''), '(\d+)\+?\s*(?:years?|yrs?)\s+(?:of\s+)?(?:full[- ]time\s+)?(?:work|working|professional|managerial|industry|job)\s+experience', 'i'))[1]::int as work_exp_years,
  case when b.eligibility_text ~* '(no|without)\s+entrance\s+(exam|test)' or b.eligibility_text ~* 'entrance\s+(exam|test)\s+(is\s+)?not\s+(required|mandatory)' then false
       when b.eligibility_text ~* 'entrance\s+(exam|test)\s+(is\s+)?(required|mandatory|compulsory)' then true end as entrance_exam,
  uni.f->>'ugc_deb' as ugc_deb, uni.f->>'naac_grade' as naac_grade, public.web_naac_rank(uni.f->>'naac_grade') as naac_rank,
  coalesce((uni.f->>'naac_accredited')::boolean, false) as naac_accredited,
  (uni.f->'nirf'->>'rank')::int as nirf_rank, (uni.f->'nirf'->>'year')::int as nirf_year,
  uni.f ? 'nirf' or uni.f ? 'nirf_programmes' as nirf_ranked,
  coalesce((uni.f->>'aicte')::boolean, false) as aicte,
  b.updated_at as verified_at, coalesce(pop.score, 0) as popularity, b.brochure_url,
  coalesce((select array_agg(distinct l.tag_id) from public.web_tax_tag_links l
            where l.tag_kind = 'goal' and (l.programme_id = b.programme_id or l.specialisation_id = any(b.specialisation_ids))), '{}') as goal_ids,
  setweight(to_tsvector('simple', coalesce(public.web_norm(concat_ws(' ', b.programme_name, b.programme_full, b.programme_aliases)), '')), 'A')
  || setweight(to_tsvector('simple', coalesce(public.web_norm(concat_ws(' ', b.spec_name, b.spec_aliases)), '')), 'A')
  || setweight(to_tsvector('simple', coalesce(public.web_norm(concat_ws(' ', uni.display_name, uni.name, uni.short_name)), '')), 'B')
  || setweight(to_tsvector('simple', coalesce(public.web_norm(concat_ws(' ', b.program_name, b.spec_display, b.format)), '')), 'C') as search_doc,
  public.web_norm(concat_ws(' ', b.programme_name, b.spec_name, b.spec_display, uni.display_name, uni.short_name)) as search_text,
  (b.active and b.programme_id is not null and cardinality(b.specialisation_ids) > 0 and b.map_hidden is null
     and coalesce(b.programme_active, false) and uni.published and (b.mode is distinct from 'Regular' or (select include_regular from regular))) as visible,
  case when not b.active then 'inactive in catalogue'
       when b.programme_id is null or cardinality(b.specialisation_ids) = 0 then 'unmapped'
       when b.map_hidden is not null then b.map_hidden
       when not coalesce(b.programme_active, false) then 'programme hidden'
       when not uni.published then 'university hidden'
       when b.mode = 'Regular' and not (select include_regular from regular) then 'regular mode hidden (D-013)'
  end as hidden_reason
from base b
join uni on uni.id = b.university_id
left join public.web_tax_levels lv on lv.id = b.level_id
left join public.web_tax_categories cat on cat.id = b.category_id
left join public.web_offering_popularity pop on pop.catalog_program_id = b.id
cross join lateral (select public.web_derive_duration(b.eligibility_text, b.fee_other, b.fee_total, b.fee_yearly, b.fee_semester) as dur) d
with no data;

create unique index if not exists web_offering_search_id_idx on public.web_offering_search (id);
create index if not exists web_offering_search_doc_idx on public.web_offering_search using gin (search_doc);
create index if not exists web_offering_search_trgm_idx on public.web_offering_search using gist (search_text public.gist_trgm_ops);
create index if not exists web_offering_search_group_idx on public.web_offering_search (group_key) where visible;
create index if not exists web_offering_search_uni_idx on public.web_offering_search (uni_slug) where visible;
create index if not exists web_offering_search_pk_idx on public.web_offering_search (program_key);

revoke all on public.web_offering_search from anon, authenticated, public;
grant select on public.web_offering_search to service_role;

-- Facet options that exist in the visible catalogue (zero-count options are shown disabled, never hidden — spec 6.3).
create materialized view if not exists public.web_facet_values as
select distinct f.facet, f.value, f.label, f.sort
from public.web_offering_search o
cross join lateral (values
  ('level', o.level_id, o.level_label, o.level_sort::int),
  ('category', o.category_id, o.category_label, 0),
  ('programme', o.programme_id, o.programme_name, o.programme_sort::int),
  ('university', o.uni_slug, o.uni_name, 0),
  ('mode', o.mode, case o.mode when 'ODL' then 'Distance (ODL)' else o.mode end, case o.mode when 'Online' then 1 else 2 end),
  ('naac', o.naac_grade, 'NAAC ' || o.naac_grade, 10 - o.naac_rank),
  ('min_q', o.min_qualification, case o.min_qualification when '12TH' then 'Class 12' when 'DIPLOMA' then 'Diploma'
     when 'BACHELOR' then 'Bachelor''s degree' when 'MASTER' then 'Master''s degree' else o.min_qualification end,
     case o.min_qualification when '12TH' then 1 when 'DIPLOMA' then 2 when 'BACHELOR' then 3 else 4 end),
  ('state', o.uni_state, o.uni_state, 0)
) f(facet, value, label, sort)
where o.visible and f.value is not null
union
select 'spec', s.id, s.name, 0
from public.web_tax_specialisations s
where exists (select 1 from public.web_offering_search o where o.visible and s.id = any(o.spec_ids))
with no data;
create unique index if not exists web_facet_values_idx on public.web_facet_values (facet, value);
revoke all on public.web_facet_values from anon, authenticated, public;
grant select on public.web_facet_values to service_role;

-- ---------------------------------------------------------------------------------------------------------------
-- Refresh and change detection (polling; spec 3A: never on the request path).
create table if not exists public.web_catalog_state (
  id smallint primary key default 1 check (id = 1),
  fingerprint text,
  refreshed_at timestamptz,
  last_checked_at timestamptz,
  last_result jsonb
);
alter table public.web_catalog_state enable row level security;
revoke all on public.web_catalog_state from anon, authenticated, public;
grant select, insert, update, delete on public.web_catalog_state to service_role;

create or replace function public.web_catalog_fingerprint()
returns text language sql stable security definer set search_path = '' as $$
  select md5(concat_ws('|',
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') || ':' || coalesce(sum(id), 0) from public.catalog_programs),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.catalog_universities),
    (select count(*) from public.catalog_synonyms),
    (select value::text from public.w2_meta where key = 'catalog_version'),
    (select coalesce(max(updated_at)::text, '') from public.web_tax_offering_map),
    (select coalesce(max(updated_at)::text, '') from public.web_university_profiles),
    (select coalesce(max(updated_at)::text, '') from public.web_tax_programmes),
    (select coalesce(max(updated_at)::text, '') from public.web_tax_specialisations)))
$$;

-- Rebuilds the read model now (admin "refresh" button, seed, tests). Concurrent refresh keeps reads non-blocking.
create or replace function public.web_refresh_read_model()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_map jsonb; t0 timestamptz := clock_timestamp(); v_populated boolean;
begin
  v_map := public.web_tax_automap(false);
  select relispopulated into v_populated from pg_class where oid = 'public.web_offering_search'::regclass;
  if v_populated then
    refresh materialized view concurrently public.web_offering_search;
    refresh materialized view concurrently public.web_facet_values;
  else
    refresh materialized view public.web_offering_search;
    refresh materialized view public.web_facet_values;
  end if;
  insert into public.web_catalog_state (id, fingerprint, refreshed_at, last_checked_at, last_result)
  values (1, public.web_catalog_fingerprint(), now(), now(), v_map)
  on conflict (id) do update set fingerprint = excluded.fingerprint, refreshed_at = now(), last_checked_at = now(),
    last_result = excluded.last_result;
  perform public.web_outbox_enqueue('revalidate', 'revalidate:catalog:' || public.web_catalog_fingerprint(),
    jsonb_build_object('tags', jsonb_build_array('catalog')));
  return v_map || jsonb_build_object('refresh_ms', round(extract(epoch from clock_timestamp() - t0) * 1000),
    'visible', (select count(*) from public.web_offering_search where visible));
end $$;

-- Called every minute by pg_cron: refreshes only when the catalogue (or the taxonomy) changed.
create or replace function public.web_catalog_poll()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_fp text := public.web_catalog_fingerprint(); v_old text;
begin
  select fingerprint into v_old from public.web_catalog_state where id = 1;
  if v_old is not distinct from v_fp then
    update public.web_catalog_state set last_checked_at = now() where id = 1;
    return jsonb_build_object('changed', false);
  end if;
  return public.web_refresh_read_model() || jsonb_build_object('changed', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Query understanding: greedy longest-match of aliases (programme > specialisation > university > level > category >
-- mode > stopword), then typo correction by trigram similarity for leftover words.
create or replace function public.web_resolve_query(p_q text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  words text[] := string_to_array(coalesce(public.web_norm(p_q), ''), ' ');
  n int := coalesce(array_length(words, 1), 0);
  i int := 1; len int; phrase text; hit record; matched boolean;
  res jsonb := '{"programme":[],"specialisation":[],"university":[],"level":[],"category":[],"mode":[],"unmatched":[],"corrected":[]}';
  kinds constant text[] := array['programme', 'specialisation', 'university', 'level', 'category', 'mode', 'stopword'];
begin
  if n = 0 or words = array[''] then return res; end if;
  while i <= n loop
    matched := false;
    for len in reverse least(6, n - i + 1) .. 1 loop
      phrase := array_to_string(words[i:i+len-1], '');
      select s.kind, array_agg(distinct s.target_id) ids into hit
      from public.web_tax_synonyms s where s.alias_compact = phrase
      group by s.kind order by array_position(kinds, s.kind) limit 1;
      if hit.kind is not null then
        if hit.kind <> 'stopword' then
          res := jsonb_set(res, array[hit.kind], (res->hit.kind) || to_jsonb(hit.ids));
        end if;
        i := i + len; matched := true; exit;
      end if;
    end loop;
    if not matched then
      -- Typo tolerance: multi-word phrases first ("data sciense" → data science), then single words. A word that is a
      -- real token in the catalogue text ("data") stays as text instead of being "corrected".
      for len in reverse least(3, n - i + 1) .. 1 loop
        phrase := array_to_string(words[i:i+len-1], ' ');
        continue when length(phrase) < 4 or phrase ~ '^\d+$';
        if len = 1 and exists (select 1 from public.web_offering_search o where o.visible
                               and o.search_doc @@ to_tsquery('simple', quote_literal(phrase))) then
          exit;
        end if;
        select s.kind, s.target_id, s.alias_norm into hit from public.web_tax_synonyms s
        where s.kind in ('programme', 'specialisation', 'university') and s.alias_norm operator(public.%) phrase
          and public.similarity(s.alias_norm, phrase) >= case when len = 1 then 0.45 else 0.55 end
        order by public.similarity(s.alias_norm, phrase) desc, array_position(kinds, s.kind) limit 1;
        if hit.kind is not null then
          res := jsonb_set(res, array[hit.kind], (res->hit.kind) || to_jsonb(array[hit.target_id]));
          res := jsonb_set(res, '{corrected}', (res->'corrected') || jsonb_build_object('from', phrase, 'to', hit.alias_norm));
          i := i + len; matched := true; exit;
        end if;
      end loop;
      if not matched then
        if words[i] !~ '^\d+$' then -- numbers are parsed on the server (budgets, durations)
          res := jsonb_set(res, '{unmatched}', (res->'unmatched') || to_jsonb(words[i]));
        end if;
        i := i + 1;
      end if;
    end if;
  end loop;
  -- de-duplicate
  select jsonb_object_agg(k, coalesce((select jsonb_agg(distinct x) from jsonb_array_elements(v) x), '[]'))
    into res from jsonb_each(res) e(k, v);
  return res;
end $$;

create or replace function public.web_jarr(p jsonb)
returns text[] language sql immutable parallel safe as $$
  select case when jsonb_typeof(p) = 'array' and jsonb_array_length(p) > 0
              then array(select jsonb_array_elements_text(p)) end
$$;

-- Offering as returned to the finder (card level). Never includes eligibility free text or internal fields.
create or replace function public.web_offering_card(o public.web_offering_search, p_elig text)
returns jsonb language sql immutable security definer set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', o.id, 'program_key', o.program_key, 'group_key', o.group_key,
    'programme_id', o.programme_id, 'programme_name', o.programme_name, 'level_id', o.level_id, 'level_short', o.level_short,
    'spec_ids', to_jsonb(o.spec_ids), 'spec_name', o.spec_name, 'spec_display', o.spec_display,
    'university', jsonb_strip_nulls(jsonb_build_object('id', o.university_id, 'slug', o.uni_slug, 'name', o.uni_name,
                   'short', o.uni_short, 'logo', o.uni_logo, 'type', o.uni_type)),
    'mode', o.mode, 'format', o.format, 'attributes', case when o.attributes <> '{}' then o.attributes end,
    'fee', jsonb_strip_nulls(jsonb_build_object('total', o.fee_total, 'yearly', o.fee_yearly, 'semester', o.fee_semester,
                   'on_request', case when o.fee_on_request then true end)),
    'duration_months', o.duration_months, 'naac_grade', o.naac_grade,
    'naac_accredited', case when o.naac_accredited then true end, 'nirf_rank', o.nirf_rank, 'nirf_year', o.nirf_year,
    'ugc_deb', o.ugc_deb, 'aicte', case when o.aicte then true end, 'min_qualification', o.min_qualification,
    'min_pct_general', o.min_pct_general, 'work_exp_years', o.work_exp_years, 'entrance_exam', o.entrance_exam,
    'eligibility', p_elig, 'verified_at', o.verified_at))
$$;

-- The finder query (spec 6.2–6.4). Input (all optional):
--   q, level[], category[], programme[], spec[], university[] (slugs), mode[], fee_min, fee_max, duration[]
--   (le12|13-24|25-36|gt36), naac[], ugc_deb, aicte, nirf (booleans), min_q[], work_exp (required|not_required),
--   entrance (yes|no), state[], format[] (standard|work-integrated|apprenticeship|work-linked), goal,
--   qual (10th|12th|diploma|graduation|postgraduation), show_ineligible, sort (relevance|fee_asc|fee_desc|naac|duration|
--   popularity), view (grouped|flat), page, page_size, group_key, include_offerings.
-- Output: total, total_groups, items, facets (counts exclude each facet's own selection), resolved, relaxations, closest.
create or replace function public.web_search(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_res jsonb := public.web_resolve_query(p->>'q');
  r_prog text[] := public.web_jarr(v_res->'programme');
  r_spec text[] := public.web_jarr(v_res->'specialisation');
  r_uni text[] := public.web_jarr(v_res->'university');
  r_level text[] := public.web_jarr(v_res->'level');
  r_cat text[] := public.web_jarr(v_res->'category');
  r_mode text[] := public.web_jarr(v_res->'mode');
  a_level text[] := public.web_jarr(p->'level');
  a_cat text[] := public.web_jarr(p->'category');
  a_prog text[] := public.web_jarr(p->'programme');
  a_spec text[] := public.web_jarr(p->'spec');
  a_uni text[] := public.web_jarr(p->'university');
  a_mode text[] := public.web_jarr(p->'mode');
  a_dur text[] := public.web_jarr(p->'duration');
  a_naac text[] := public.web_jarr(p->'naac');
  a_minq text[] := public.web_jarr(p->'min_q');
  a_state text[] := public.web_jarr(p->'state');
  a_format text[] := public.web_jarr(p->'format');
  v_fee_min numeric := nullif(p->>'fee_min', '')::numeric;
  v_fee_max numeric := nullif(p->>'fee_max', '')::numeric;
  v_ugc boolean := coalesce((p->>'ugc_deb')::boolean, false);
  v_aicte boolean := coalesce((p->>'aicte')::boolean, false);
  v_nirf boolean := coalesce((p->>'nirf')::boolean, false);
  v_work text := nullif(p->>'work_exp', '');
  v_entr text := nullif(p->>'entrance', '');
  v_goal text := nullif(p->>'goal', '');
  v_qual text := nullif(p->>'qual', '');
  v_show_inel boolean := coalesce((p->>'show_ineligible')::boolean, false);
  v_sort text := coalesce(nullif(p->>'sort', ''), 'relevance');
  v_view text := coalesce(nullif(p->>'view', ''), 'grouped');
  v_group text := nullif(p->>'group_key', '');
  v_incl boolean := coalesce((p->>'include_offerings')::boolean, false) or v_group is not null;
  v_size int := least(100, greatest(1, coalesce(nullif(p->>'page_size', '')::int, 20)));
  v_page int := greatest(1, coalesce(nullif(p->>'page', '')::int, 1));
  g_prog text[]; g_spec text[];
  v_words text[] := public.web_jarr(v_res->'unmatched');
  v_used text[] := '{}'; v_ignored text[] := '{}'; w text; v_tsq tsquery; v_nomatch boolean := false;
  v_out jsonb;
begin
  if v_goal is not null then
    g_prog := array(select programme_id from public.web_tax_tag_links where tag_kind = 'goal' and tag_id = v_goal and programme_id is not null);
    g_spec := array(select specialisation_id from public.web_tax_tag_links where tag_kind = 'goal' and tag_id = v_goal and specialisation_id is not null);
  end if;
  -- Leftover words: kept only if they match some visible offering (prefix match); otherwise reported as ignored.
  foreach w in array coalesce(v_words, '{}') loop
    if exists (select 1 from public.web_offering_search o where o.visible and o.search_doc @@ to_tsquery('simple', quote_literal(w) || ':*')) then
      v_used := v_used || w;
    else
      v_ignored := v_ignored || w;
    end if;
  end loop;
  if cardinality(v_used) > 0 then
    v_tsq := to_tsquery('simple', array_to_string(array(select quote_literal(x) || ':*' from unnest(v_used) x), ' & '));
  end if;
  -- A query made only of unknown words matches nothing (the zero-results path then offers the closest matches).
  v_nomatch := public.web_norm(p->>'q') is not null and cardinality(v_used) = 0
    and r_prog is null and r_spec is null and r_uni is null and r_level is null and r_cat is null and r_mode is null
    and cardinality(coalesce(v_ignored, '{}')) > 0;

  with b as materialized (
    -- The query (text + resolved entities) narrows everything, facets included; filters are recorded per row as the
    -- list of facets the row fails, so each facet can be counted with every other filter applied (spec 6.3).
    select x.*, array_remove(array[
        case when not (a_level is null or x.level_id = any(a_level)) then 'level' end,
        case when not (a_cat is null or x.category_id = any(a_cat)) then 'category' end,
        case when not (a_prog is null or x.programme_id = any(a_prog)) then 'programme' end,
        case when not (a_spec is null or x.spec_ids && a_spec) then 'spec' end,
        case when not (a_uni is null or x.uni_slug = any(a_uni)) then 'university' end,
        case when not (a_mode is null or x.mode = any(a_mode)) then 'mode' end,
        case when not coalesce((v_fee_min is null or x.fee_total >= v_fee_min) and (v_fee_max is null or x.fee_total <= v_fee_max), false) then 'fee' end,
        case when not coalesce(a_dur is null or x.dur_bucket = any(a_dur), false) then 'duration' end,
        case when not coalesce(a_naac is null or x.naac_grade = any(a_naac), false) then 'naac' end,
        case when v_ugc and x.ugc_deb is null then 'ugc_deb' end,
        case when v_aicte and not x.aicte then 'aicte' end,
        case when v_nirf and not x.nirf_ranked then 'nirf' end,
        case when not coalesce(a_minq is null or x.min_qualification = any(a_minq), false) then 'min_q' end,
        case when not (v_work is null or (v_work = 'required' and x.work_exp) or (v_work = 'not_required' and not x.work_exp)) then 'work_exp' end,
        case when not (v_entr is null or (v_entr = 'yes' and x.entrance_exam is true) or (v_entr = 'no' and x.entrance_exam is false)) then 'entrance' end,
        case when not coalesce(a_state is null or x.uni_state = any(a_state), false) then 'state' end,
        case when not (a_format is null or coalesce(x.format, 'standard') = any(a_format)) then 'format' end,
        case when not (v_goal is null or v_goal = any(x.goal_ids)) then 'goal' end,
        case when v_group is not null and x.group_key <> v_group then 'group' end,
        case when not (v_qual is null or v_show_inel or x.elig <> 'not_eligible') then 'elig' end
      ], null) as fails
    from (
      select o.id, o.group_key, o.programme_id, o.level_id, o.category_id, o.spec_ids, o.university_id, o.uni_slug,
             o.uni_state, o.mode, o.fee_total, o.fee_on_request, o.duration_months, public.web_duration_bucket(o.duration_months) as dur_bucket,
             o.naac_grade, o.naac_rank, o.nirf_rank, o.nirf_ranked, o.ugc_deb, o.aicte, o.min_qualification,
             coalesce(o.work_exp_years, 0) > 0 as work_exp, o.entrance_exam, o.format, o.goal_ids, o.popularity,
             o.level_sort, o.programme_sort,
             public.web_eligibility(v_qual, o.level_id, o.min_qualification) as elig,
             (case when r_prog is not null and o.programme_id = any(r_prog) then 100 else 0 end
              + case when r_spec is not null and o.spec_ids && r_spec then 80 else 0 end
              + case when r_uni is not null and o.university_id::text = any(r_uni) then 50 else 0 end
              + case when v_tsq is not null then ts_rank(o.search_doc, v_tsq) * 20 else 0 end
              + o.popularity + o.naac_rank * 0.1 + o.programme_prior * 0.05)::numeric as score
      from public.web_offering_search o
      where o.visible and not v_nomatch
        and (r_prog is null or o.programme_id = any(r_prog))
        and (r_spec is null or o.spec_ids && r_spec)
        and (r_uni is null or o.university_id::text = any(r_uni))
        and (r_level is null or o.level_id = any(r_level))
        and (r_cat is null or o.category_id = any(r_cat))
        and (r_mode is null or o.mode = any(r_mode))
        and (v_tsq is null or o.search_doc @@ v_tsq)
    ) x
  ),
  ok as materialized (select * from b where cardinality(fails) = 0),
  one as materialized (select * from b where cardinality(fails) = 1),
  -- Facet counts. Rows passing every filter count towards every facet (one pass with grouping sets); rows failing
  -- exactly one filter count only towards that facet.
  counts_ok as (
    select case
             when grouping(level_id) = 0 then 'level' when grouping(category_id) = 0 then 'category'
             when grouping(programme_id) = 0 then 'programme' when grouping(uni_slug) = 0 then 'university'
             when grouping(mode) = 0 then 'mode' when grouping(dur_bucket) = 0 then 'duration'
             when grouping(naac_grade) = 0 then 'naac' when grouping(min_qualification) = 0 then 'min_q'
             when grouping(uni_state) = 0 then 'state' when grouping(fmt) = 0 then 'format'
             when grouping(ugc) = 0 then 'ugc_deb' when grouping(aicte) = 0 then 'aicte' when grouping(nirf_ranked) = 0 then 'nirf'
             when grouping(work_exp) = 0 then 'work_exp' when grouping(entrance_exam) = 0 then 'entrance'
             when grouping(elig) = 0 then 'elig' end as facet,
           coalesce(level_id, category_id, programme_id, uni_slug, mode, dur_bucket, naac_grade, min_qualification, uni_state, fmt,
             case when grouping(ugc) = 0 then ugc::text end, case when grouping(aicte) = 0 then aicte::text end,
             case when grouping(nirf_ranked) = 0 then nirf_ranked::text end, case when grouping(work_exp) = 0 then work_exp::text end,
             case when grouping(entrance_exam) = 0 then entrance_exam::text end, elig) as value,
           count(*) as n
    from (select ok.*, coalesce(ok.format, 'standard') as fmt, ok.ugc_deb is not null as ugc from ok) z
    group by grouping sets ((level_id), (category_id), (programme_id), (uni_slug), (mode), (dur_bucket), (naac_grade),
      (min_qualification), (uni_state), (fmt), (ugc), (aicte), (nirf_ranked), (work_exp), (entrance_exam), (elig))
    union all
    select 'spec', s, count(*) from ok, unnest(ok.spec_ids) s group by 2
    union all
    select 'goal', g, count(*) from ok, unnest(ok.goal_ids) g group by 2
  ),
  counts_one as (
    select one.fails[1] as facet,
      case one.fails[1] when 'level' then one.level_id when 'category' then one.category_id when 'programme' then one.programme_id
        when 'university' then one.uni_slug when 'mode' then one.mode when 'duration' then one.dur_bucket
        when 'naac' then one.naac_grade when 'min_q' then one.min_qualification when 'state' then one.uni_state
        when 'format' then coalesce(one.format, 'standard') when 'ugc_deb' then (one.ugc_deb is not null)::text
        when 'aicte' then one.aicte::text when 'nirf' then one.nirf_ranked::text when 'work_exp' then one.work_exp::text
        when 'entrance' then one.entrance_exam::text when 'elig' then one.elig end as value,
      count(*) as n
    from one where one.fails[1] not in ('spec', 'goal', 'fee', 'group') group by 1, 2
    union all
    select 'spec', s, count(*) from one, unnest(one.spec_ids) s where one.fails[1] = 'spec' group by 2
    union all
    select 'goal', g, count(*) from one, unnest(one.goal_ids) g where one.fails[1] = 'goal' group by 2
  ),
  counts as (select facet, value, sum(n)::int as n from (select * from counts_ok union all select * from counts_one) u
             where value is not null group by 1, 2),
  grp as (
    select ok.group_key as key, min(ok.id) as rep_id, count(*) as offerings, count(distinct ok.university_id) as universities,
      min(ok.fee_total) as fee_min, max(ok.fee_total) as fee_max, min(ok.duration_months) as dur_min, max(ok.duration_months) as dur_max,
      max(ok.naac_rank) as best_naac, max(ok.score) as score, sum(ok.popularity) as pop,
      min(ok.programme_sort) as psort, min(ok.level_sort) as lsort,
      count(*) filter (where ok.elig = 'eligible') as n_eligible, count(*) filter (where ok.elig = 'check') as n_check,
      count(*) filter (where ok.elig = 'not_eligible') as n_not_eligible,
      array_agg(distinct ok.mode) as modes, bool_or(ok.fee_on_request) as some_on_request
    from ok group by ok.group_key
  ),
  grp_page as materialized (
    select grp.*, row_number() over (order by
      case when v_sort = 'fee_asc' then fee_min end asc nulls last,
      case when v_sort = 'fee_desc' then fee_max end desc nulls last,
      case when v_sort = 'naac' then best_naac end desc nulls last,
      case when v_sort = 'duration' then dur_min end asc nulls last,
      case when v_sort = 'popularity' then pop end desc nulls last,
      score desc, pop desc, offerings desc, lsort, psort, key) as ord
    from grp
    order by ord limit case when v_view = 'flat' then 0 else v_size end offset (v_page - 1) * v_size
  ),
  top_u as (
    select t.group_key, jsonb_agg(jsonb_strip_nulls(jsonb_build_object('slug', m.uni_slug, 'name', m.uni_name, 'short', m.uni_short,
             'logo', m.uni_logo, 'naac_grade', m.naac_grade)) order by t.rk) as unis
    from (
      select d.group_key, d.id, row_number() over (partition by d.group_key order by d.naac_rank desc, d.nirf_rank asc nulls last, d.university_id) as rk
      from (select distinct on (ok.group_key, ok.university_id) ok.group_key, ok.university_id, ok.id, ok.naac_rank, ok.nirf_rank
            from ok where ok.group_key in (select key from grp_page) order by ok.group_key, ok.university_id, ok.fee_total) d) t
    join public.web_offering_search m on m.id = t.id
    where t.rk <= 3 group by t.group_key
  ),
  flat_page as materialized (
    select ok.id, ok.elig, ok.group_key, row_number() over (order by
      case when v_sort = 'fee_asc' then ok.fee_total end asc nulls last,
      case when v_sort = 'fee_desc' then ok.fee_total end desc nulls last,
      case when v_sort = 'naac' then ok.naac_rank end desc nulls last,
      case when v_sort = 'duration' then ok.duration_months end asc nulls last,
      case when v_sort = 'popularity' then ok.popularity end desc nulls last,
      ok.score desc, ok.naac_rank desc, ok.fee_total asc nulls last, ok.id) as ord
    from ok
    where v_view = 'flat' or (v_incl and ok.group_key in (select key from grp_page))
    order by ord limit case when v_view = 'flat' then v_size else 10000 end offset case when v_view = 'flat' then (v_page - 1) * v_size else 0 end
  ),
  cards as (
    select fp.group_key, fp.ord, public.web_offering_card(o, fp.elig) as card
    from flat_page fp join public.web_offering_search o on o.id = fp.id
  ),
  fv as (select * from public.web_facet_values)
  select jsonb_build_object(
    'total', (select count(*) from ok),
    'total_groups', (select count(*) from grp),
    'page', v_page, 'page_size', v_size, 'view', v_view, 'sort', v_sort,
    'items', case when v_view = 'flat' then coalesce((select jsonb_agg(card order by ord) from cards), '[]')
      else coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'key', g.key, 'programme_id', m.programme_id, 'programme_name', m.programme_name, 'programme_full', m.programme_full,
          'level_id', m.level_id, 'level_short', m.level_short, 'level_label', m.level_label, 'category_id', m.category_id,
          'spec_ids', to_jsonb(m.spec_ids), 'spec_name', m.spec_name,
          'offerings', g.offerings, 'universities', g.universities, 'fee_min', g.fee_min, 'fee_max', g.fee_max,
          'duration_min', g.dur_min, 'duration_max', g.dur_max,
          'best_naac', case g.best_naac when 7 then 'A++' when 6 then 'A+' when 5 then 'A' when 4 then 'B++' when 3 then 'B+' when 2 then 'B' when 1 then 'C' end,
          'modes', to_jsonb(g.modes), 'some_fee_on_request', case when g.some_on_request then true end,
          'eligibility', case when v_qual is not null then jsonb_build_object('eligible', g.n_eligible, 'check', g.n_check, 'not_eligible', g.n_not_eligible) end,
          'top_universities', (select tu.unis from top_u tu where tu.group_key = g.key),
          'items', case when v_incl then (select jsonb_agg(c.card order by (c.card->'fee'->>'total')::numeric asc nulls last, c.card->'university'->>'name')
                                          from cards c where c.group_key = g.key) end
        )) order by g.ord) from grp_page g join public.web_offering_search m on m.id = g.rep_id), '[]') end,
    'facets', jsonb_build_object(
      'level', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.sort), '[]')
                from fv left join counts c on c.facet = 'level' and c.value = fv.value where fv.facet = 'level'),
      'category', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by k.sort), '[]')
                from fv join public.web_tax_categories k on k.id = fv.value left join counts c on c.facet = 'category' and c.value = fv.value where fv.facet = 'category'),
      'programme', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'full', p2.full_name, 'level', p2.level_id,
                     'count', coalesce(c.n, 0)) order by lv.sort, p2.sort, fv.label), '[]')
                from fv join public.web_tax_programmes p2 on p2.id = fv.value join public.web_tax_levels lv on lv.id = p2.level_id
                left join counts c on c.facet = 'programme' and c.value = fv.value where fv.facet = 'programme'),
      'spec', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0))
                     order by coalesce(c.n, 0) desc, fv.label), '[]')
                from fv left join counts c on c.facet = 'spec' and c.value = fv.value where fv.facet = 'spec'),
      'university', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.label), '[]')
                from fv left join counts c on c.facet = 'university' and c.value = fv.value where fv.facet = 'university'),
      'mode', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.sort), '[]')
                from fv left join counts c on c.facet = 'mode' and c.value = fv.value where fv.facet = 'mode'),
      'naac', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.sort), '[]')
                from fv left join counts c on c.facet = 'naac' and c.value = fv.value where fv.facet = 'naac'),
      'min_q', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.sort), '[]')
                from fv left join counts c on c.facet = 'min_q' and c.value = fv.value where fv.facet = 'min_q'),
      'state', (select coalesce(jsonb_agg(jsonb_build_object('value', fv.value, 'label', fv.label, 'count', coalesce(c.n, 0)) order by fv.label), '[]')
                from fv left join counts c on c.facet = 'state' and c.value = fv.value where fv.facet = 'state'),
      'duration', (select jsonb_agg(jsonb_build_object('value', d.v, 'label', d.l, 'count', coalesce(c.n, 0)) order by d.s)
                from (values ('le12', 'Up to 1 year', 1), ('13-24', '1–2 years', 2), ('25-36', '2–3 years', 3), ('gt36', 'More than 3 years', 4)) d(v, l, s)
                left join counts c on c.facet = 'duration' and c.value = d.v),
      'format', (select jsonb_agg(jsonb_build_object('value', f.id, 'label', f.label, 'count', coalesce(c.n, 0)) order by f.s)
                from (select 'standard' id, 'Standard' label, 0 s union all select id, label, 1 from public.web_tax_formats) f
                left join counts c on c.facet = 'format' and c.value = f.id),
      'goal', (select coalesce(jsonb_agg(jsonb_build_object('value', t.id, 'label', t.label, 'count', coalesce(c.n, 0)) order by t.sort), '[]')
                from public.web_tax_goal_tags t left join counts c on c.facet = 'goal' and c.value = t.id where t.active),
      'fee', coalesce((select jsonb_build_object('min', min(z.fee_total), 'max', max(z.fee_total), 'on_request', count(*) filter (where z.fee_total is null),
                'global_min', gb.lo, 'global_max', gb.hi,
                'histogram', (select jsonb_agg(coalesce(h.n, 0) order by k.i) from generate_series(0, 15) k(i)
                              left join (select least(15, floor((z2.fee_total - gb.lo) / nullif(gb.hi - gb.lo, 0) * 16))::int as i, count(*) n
                                         from (select fee_total from ok union all select fee_total from one where one.fails[1] = 'fee') z2
                                         where z2.fee_total is not null group by 1) h on h.i = k.i))
              from (select fee_total from ok union all select fee_total from one where one.fails[1] = 'fee') z,
                   (select min(fee_total) lo, max(fee_total) hi from public.web_offering_search where visible) gb
              group by gb.lo, gb.hi),
              jsonb_build_object('min', null, 'max', null, 'on_request', 0, 'global_min', (select min(fee_total) from public.web_offering_search where visible),
                'global_max', (select max(fee_total) from public.web_offering_search where visible), 'histogram', '[]'::jsonb)),
      'ugc_deb', coalesce((select n from counts where facet = 'ugc_deb' and value = 'true'), 0),
      'aicte', coalesce((select n from counts where facet = 'aicte' and value = 'true'), 0),
      'nirf', coalesce((select n from counts where facet = 'nirf' and value = 'true'), 0),
      'work_exp', jsonb_build_object('required', coalesce((select n from counts where facet = 'work_exp' and value = 'true'), 0),
                                     'not_required', coalesce((select n from counts where facet = 'work_exp' and value = 'false'), 0)),
      'entrance', jsonb_build_object('yes', coalesce((select n from counts where facet = 'entrance' and value = 'true'), 0),
                                     'no', coalesce((select n from counts where facet = 'entrance' and value = 'false'), 0)),
      'eligibility', case when v_qual is not null then jsonb_build_object(
                'eligible', coalesce((select n from counts where facet = 'elig' and value = 'eligible'), 0),
                'check', coalesce((select n from counts where facet = 'elig' and value = 'check'), 0),
                'not_eligible', coalesce((select n from counts where facet = 'elig' and value = 'not_eligible'), 0)) end
    ),
    'relaxations', (select coalesce(jsonb_agg(jsonb_build_object('filter', r.f, 'count', r.n) order by r.n desc), '[]')
                    from (select one.fails[1] f, count(*) n from one where one.fails[1] <> 'group' group by 1) r
                    where not exists (select 1 from ok)),
    'resolved', v_res - 'unmatched' || jsonb_build_object('used_words', to_jsonb(v_used), 'ignored_words', to_jsonb(v_ignored))
  ) into v_out;

  -- Zero results caused by the text itself: how many results without the query, and the closest matches.
  if (v_out->>'total')::int = 0 and public.web_norm(p->>'q') is not null then
    v_out := v_out || jsonb_build_object(
      'without_query', (public.web_search((p - 'q') || '{"page_size":1}'::jsonb))->'total',
      'closest', coalesce((select jsonb_agg(public.web_offering_card(x, null)) from (
          select o.* from public.web_offering_search o where o.visible
          order by o.search_text operator(public.<->) public.web_norm(p->>'q'), o.naac_rank desc limit 5) x), '[]'));
  end if;
  return v_out;
end $$;

-- Free text → URL filters for the search box (spec 6.4 "natural language into structured filters"): entities become
-- facet values (universities as slugs, modes as URL values); words that matched nothing structured stay as text.
create or replace function public.web_resolve_to_filters(p_q text)
returns jsonb language sql stable security definer set search_path = '' as $$
  with r as (select public.web_resolve_query(p_q) as v)
  select jsonb_build_object(
    'programme', r.v->'programme', 'spec', r.v->'specialisation', 'level', r.v->'level', 'category', r.v->'category',
    'mode', coalesce((select jsonb_agg(case m when 'ODL' then 'odl' else lower(m) end) from jsonb_array_elements_text(r.v->'mode') m), '[]'),
    'uni', coalesce((select jsonb_agg(p.slug order by p.slug) from jsonb_array_elements_text(r.v->'university') u
                     join public.web_university_profiles p on p.catalog_university_id = u::bigint), '[]'),
    -- leftover words are kept as text only if some visible offering contains them; the rest are reported as ignored
    'text', coalesce((select jsonb_agg(w) from jsonb_array_elements_text(r.v->'unmatched') w
                      where exists (select 1 from public.web_offering_search o where o.visible
                                    and o.search_doc @@ to_tsquery('simple', quote_literal(w) || ':*'))), '[]'),
    'ignored', coalesce((select jsonb_agg(w) from jsonb_array_elements_text(r.v->'unmatched') w
                      where not exists (select 1 from public.web_offering_search o where o.visible
                                    and o.search_doc @@ to_tsquery('simple', quote_literal(w) || ':*'))), '[]'),
    'corrected', r.v->'corrected')
  from r
$$;

-- Instant suggestions grouped as Programmes · Specialisations (as programme + specialisation groups) · Universities.
-- Guides are added by the website from web_resources (Phase 6).
create or replace function public.web_suggest(p_q text, p_limit int default 5)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  qn text := public.web_norm(p_q);
  v_res jsonb; last_word text; head text;
  c_prog text[]; c_spec text[]; c_uni text[];
  lim int := least(10, greatest(1, coalesce(p_limit, 5)));
begin
  if qn is null then
    return jsonb_build_object('programmes', '[]'::jsonb, 'groups', '[]'::jsonb, 'universities', '[]'::jsonb);
  end if;
  v_res := public.web_resolve_query(qn);
  last_word := regexp_replace(qn, '^.* ', '');
  head := nullif(btrim(left(qn, length(qn) - length(last_word))), '');
  -- Candidates: fully resolved words + prefix matches on the whole query and on the last (partial) word.
  c_prog := array(select jsonb_array_elements_text(v_res->'programme')) || array(
    select distinct s.target_id from public.web_tax_synonyms s where s.kind = 'programme'
      and (s.alias_norm like qn || '%' or (length(last_word) >= 2 and s.alias_norm like last_word || '%')));
  c_spec := array(select jsonb_array_elements_text(v_res->'specialisation')) || array(
    select distinct s.target_id from public.web_tax_synonyms s where s.kind = 'specialisation'
      and (s.alias_norm like qn || '%' or (length(last_word) >= 3 and s.alias_norm like last_word || '%')
           or (length(qn) >= 4 and s.alias_norm operator(public.%) qn and public.similarity(s.alias_norm, qn) >= 0.4)));
  c_uni := array(select jsonb_array_elements_text(v_res->'university')) || array(
    select distinct s.target_id from public.web_tax_synonyms s where s.kind = 'university'
      and (s.alias_norm like qn || '%' or (length(last_word) >= 3 and s.alias_norm like last_word || '%')
           or s.alias_norm like '% ' || qn || '%'
           or (length(qn) >= 4 and s.alias_norm operator(public.%) qn and public.similarity(s.alias_norm, qn) >= 0.4)));

  return jsonb_build_object(
    'programmes', coalesce((select jsonb_agg(x order by x->>'count' desc) from (
        select jsonb_build_object('id', o.programme_id, 'label', min(o.programme_name), 'full', min(o.programme_full),
          'level', min(o.level_short), 'count', count(*), 'universities', count(distinct o.university_id)) x
        from public.web_offering_search o where o.visible and o.programme_id = any(c_prog)
        group by o.programme_id order by count(*) desc limit lim) t), '[]'),
    'groups', coalesce((select jsonb_agg(x order by (x->>'count')::int desc) from (
        select jsonb_build_object('key', o.group_key, 'programme_id', min(o.programme_id), 'spec_ids', to_jsonb(min(o.spec_ids)),
          'label', min(o.programme_name) || ' · ' || min(o.spec_name), 'count', count(*),
          'universities', count(distinct o.university_id)) x
        from public.web_offering_search o
        where o.visible and o.spec_ids && c_spec and (cardinality(c_prog) = 0 or o.programme_id = any(c_prog))
          and o.spec_primary <> 'general'
        group by o.group_key order by count(*) desc limit lim) t), '[]'),
    'universities', coalesce((select jsonb_agg(x order by x->>'label') from (
        select jsonb_build_object('slug', o.uni_slug, 'label', min(o.uni_name), 'count', count(*)) x
        from public.web_offering_search o where o.visible and o.university_id::text = any(c_uni)
        group by o.uni_slug limit lim) t), '[]'),
    'resolved', v_res
  );
end $$;

-- Full detail for the offering panel (spec 6.6): only what the catalogue has, plus the same programme at other
-- universities. The catalogue replaces a renamed row with a new id (and a new program_key); an old deep link resolves
-- to the current offering of the same university, programme, specialisation and mode.
create or replace function public.web_offering_details(p_id bigint, p_qual text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o public.web_offering_search; c public.catalog_programs; v_fees jsonb; v_facts jsonb; v_moved boolean := false;
begin
  select * into o from public.web_offering_search where id = p_id;
  if o.id is not null and not o.visible then
    select s.* into o from public.web_offering_search s
     where s.visible and s.university_id = o.university_id and s.group_key = o.group_key and s.mode is not distinct from o.mode
     order by s.verified_at desc, s.id desc limit 1;
    v_moved := o.id is not null;
  end if;
  if o.id is null or not o.visible then return null; end if;
  select * into c from public.catalog_programs where id = o.id;
  -- Fee lines students pay; never internal keys (EMI, import notes) or prices of other things.
  select coalesce(jsonb_agg(jsonb_build_object('label', k, 'amount', v) order by k), '[]') into v_fees
  from jsonb_each(coalesce(c.fee_other, '{}')) e(k, v)
  where k not in ('Emi', 'as_imported') and jsonb_typeof(v) = 'number';
  select public.web_university_facts(u.accreditation_text, u.recognitions) || coalesce(p.facts_override, '{}') into v_facts
  from public.catalog_universities u left join public.web_university_profiles p on p.catalog_university_id = u.id
  where u.id = o.university_id;
  return public.web_offering_card(o, public.web_eligibility(p_qual, o.level_id, o.min_qualification)) || jsonb_strip_nulls(jsonb_build_object(
    'moved_from', case when v_moved then p_id end,
    'programme_full', o.programme_full, 'level_label', o.level_label, 'category_id', o.category_id,
    'category_label', o.category_label, 'program_name', c.program_name,
    'fee_exam', o.fee_exam, 'fee_registration', o.fee_registration, 'emi_amount', o.emi_amount,
    'fee_lines', case when jsonb_array_length(v_fees) > 0 then v_fees end,
    'duration_source', o.duration_source, 'min_pct_reserved', o.min_pct_reserved,
    'eligibility_text', nullif(btrim(c.eligibility_text), ''), 'brochure_url', o.brochure_url,
    'university_facts', v_facts,
    'alternatives', (select jsonb_agg(public.web_offering_card(a, public.web_eligibility(p_qual, a.level_id, a.min_qualification))
                       order by a.fee_total asc nulls last, a.naac_rank desc)
                     from public.web_offering_search a where a.visible and a.group_key = o.group_key and a.id <> o.id)
  ));
end $$;

-- Cards for a list of offering ids (shortlist), in the given order; hidden or unknown ids are skipped.
create or replace function public.web_offering_cards(p_ids bigint[], p_qual text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.web_offering_card(o, public.web_eligibility(p_qual, o.level_id, o.min_qualification)) order by t.ord), '[]')
  from unnest(p_ids[1:100]) with ordinality t(i, ord)
  join public.web_offering_search o on o.id = t.i and o.visible
$$;

create or replace function public.web_compare_offerings(p_ids bigint[], p_qual text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.web_offering_details(i, p_qual) order by ord) filter (where public.web_offering_details(i, p_qual) is not null), '[]')
  from unnest(p_ids[1:4]) with ordinality t(i, ord)
$$;

create or replace function public.web_universities()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x order by x->>'name'), '[]') from (
    select jsonb_strip_nulls(jsonb_build_object('slug', o.uni_slug, 'name', min(o.uni_name), 'short', min(o.uni_short),
      'type', min(o.uni_type), 'logo', min(o.uni_logo), 'state', min(o.uni_state), 'naac_grade', min(o.naac_grade),
      'nirf_rank', min(o.nirf_rank), 'ugc_deb', min(o.ugc_deb), 'aicte', bool_or(o.aicte),
      'offerings', count(*), 'programmes', count(distinct o.programme_id),
      'fee_min', min(o.fee_total), 'fee_max', max(o.fee_total), 'modes', to_jsonb(array_agg(distinct o.mode)),
      'verified_at', max(o.verified_at))) x
    from public.web_offering_search o where o.visible group by o.uni_slug) t
$$;

create or replace function public.web_university_details(p_slug text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'slug', p.slug, 'name', p.display_name, 'catalogue_name', u.name, 'short', u.short_name, 'type', u.institution_type,
    'logo', case when p.logo_permitted then p.logo_path end, 'state', p.state, 'city', p.city, 'website_url', p.website_url,
    'about', p.about,
    'facts', public.web_university_facts(u.accreditation_text, u.recognitions) || p.facts_override,
    'offerings', (select count(*) from public.web_offering_search o where o.visible and o.university_id = u.id),
    'programmes', (select jsonb_agg(distinct o.programme_id) from public.web_offering_search o where o.visible and o.university_id = u.id),
    'verified_at', u.updated_at))
  from public.web_university_profiles p join public.catalog_universities u on u.id = p.catalog_university_id
  where p.slug = p_slug and p.published
$$;

-- Live numbers for the trust line (D-014): only claims the data supports.
create or replace function public.web_catalog_stats()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'universities', count(distinct university_id), 'offerings', count(*), 'programmes', count(distinct programme_id),
    'groups', count(distinct group_key),
    'universities_ugc_deb', count(distinct university_id) filter (where ugc_deb is not null),
    'universities_naac_a_plus', count(distinct university_id) filter (where naac_rank >= 6),
    'all_ugc_deb', count(distinct university_id) filter (where ugc_deb is not null) = count(distinct university_id),
    'fee_min', min(fee_total), 'verified_at', max(verified_at),
    'refreshed_at', (select refreshed_at from public.web_catalog_state where id = 1))
  from public.web_offering_search where visible
$$;

-- Programme + specialisation groups for sitemaps, curated views and the browse pages.
create or replace function public.web_browse()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'levels', (select jsonb_agg(jsonb_build_object('id', l.id, 'label', l.label, 'count',
        (select count(*) from public.web_offering_search o where o.visible and o.level_id = l.id)) order by l.sort)
      from public.web_tax_levels l where exists (select 1 from public.web_offering_search o where o.visible and o.level_id = l.id)),
    'categories', (select jsonb_agg(jsonb_build_object('id', c.id, 'label', c.label, 'count',
        (select count(*) from public.web_offering_search o where o.visible and o.category_id = c.id)) order by c.sort)
      from public.web_tax_categories c where exists (select 1 from public.web_offering_search o where o.visible and o.category_id = c.id)),
    'programmes', (select jsonb_agg(jsonb_build_object('id', p.id, 'label', p.short_name, 'full', p.full_name, 'level', p.level_id,
        'count', (select count(*) from public.web_offering_search o where o.visible and o.programme_id = p.id)) order by p.sort)
      from public.web_tax_programmes p where exists (select 1 from public.web_offering_search o where o.visible and o.programme_id = p.id)),
    'goals', (select jsonb_agg(jsonb_build_object('id', g.id, 'label', g.label, 'description', g.description) order by g.sort)
      from public.web_tax_goal_tags g where g.active))
$$;

-- Search log (no PII: the server scrubs emails/phones before calling; queries are normalised and truncated).
create table if not exists public.web_search_log (
  id bigint generated always as identity primary key,
  q_norm text check (length(q_norm) <= 200),
  filters jsonb not null default '{}',
  results integer not null,
  latency_ms integer,
  zero boolean generated always as (results = 0) stored,
  source text not null default 'finder' check (source in ('finder', 'suggest', 'advisor', 'api')),
  created_at timestamptz not null default now()
);
create index if not exists web_search_log_at_idx on public.web_search_log (created_at desc);
create index if not exists web_search_log_zero_idx on public.web_search_log (created_at desc) where zero;
alter table public.web_search_log enable row level security;
revoke all on public.web_search_log from anon, authenticated, public;
grant select, insert on public.web_search_log to service_role;

create or replace function public.web_search_log_add(p jsonb)
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.web_search_log (q_norm, filters, results, latency_ms, source)
  values (left(public.web_norm(p->>'q'), 200), coalesce(p->'filters', '{}') - 'q', coalesce((p->>'results')::int, 0),
          (p->>'latency_ms')::int, coalesce(p->>'source', 'finder'))
$$;

-- Data-quality dashboard numbers (admin, spec 11 / 5.3).
create or replace function public.web_data_quality()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'offerings_total', (select count(*) from public.web_offering_search),
    'visible', (select count(*) from public.web_offering_search where visible),
    'hidden_by_reason', (select jsonb_object_agg(r, n) from (select hidden_reason r, count(*) n from public.web_offering_search
                          where not visible group by 1) t),
    'mapping_by_confidence', (select jsonb_object_agg(coalesce(confidence, 'none'), n) from (select confidence, count(*) n
                          from public.web_tax_offering_map group by 1) t),
    'needs_review', (select count(*) from public.web_tax_offering_map where needs_review),
    'no_fee', (select count(*) from public.web_offering_search where visible and fee_total is null),
    'no_duration', (select count(*) from public.web_offering_search where visible and duration_months is null),
    'duration_by_source', (select jsonb_object_agg(coalesce(duration_source, 'unknown'), n) from (select duration_source, count(*) n
                          from public.web_offering_search where visible group by 1) t),
    'no_min_pct', (select count(*) from public.web_offering_search where visible and min_pct_general is null),
    'ug_requires_bachelor', (select count(*) from public.web_offering_search where visible and level_id = 'ug' and min_qualification = 'BACHELOR'),
    'universities_without_ugc_deb', (select jsonb_agg(distinct uni_name) from public.web_offering_search where visible and ugc_deb is null),
    'universities_without_naac_grade', (select jsonb_agg(distinct uni_name) from public.web_offering_search where visible and naac_grade is null),
    'zero_result_searches_7d', (select count(*) from public.web_search_log where zero and created_at > now() - interval '7 days'),
    'refreshed_at', (select refreshed_at from public.web_catalog_state where id = 1))
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.web_derive_duration(text, jsonb, numeric, numeric, numeric)', 'public.web_naac_rank(text)',
    'public.web_university_facts(text, text[])', 'public.web_eligibility(text, text, text)', 'public.web_duration_bucket(integer)',
    'public.web_catalog_fingerprint()', 'public.web_refresh_read_model()', 'public.web_catalog_poll()',
    'public.web_resolve_query(text)', 'public.web_resolve_to_filters(text)', 'public.web_jarr(jsonb)', 'public.web_offering_card(public.web_offering_search, text)',
    'public.web_search(jsonb)', 'public.web_suggest(text, integer)', 'public.web_offering_details(bigint, text)',
    'public.web_compare_offerings(bigint[], text)', 'public.web_offering_cards(bigint[], text)', 'public.web_universities()', 'public.web_university_details(text)',
    'public.web_catalog_stats()', 'public.web_browse()', 'public.web_search_log_add(jsonb)', 'public.web_data_quality()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- pg_cron: poll the catalogue every minute (production has pg_cron; the local stack may not).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('web_catalog_poll', '* * * * *', 'select public.web_catalog_poll()');
  end if;
end $$;

select public.web_refresh_read_model();
