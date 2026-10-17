-- web4_read_model: facet logic, grouping, eligibility, zero results, details, allow-list. Uses two synthetic
-- universities (filtered by slug) so it is independent of the real catalogue and runs on the empty replica too.
begin;
create temp table r (ok boolean, name text) on commit drop;
alter table public.catalog_programs disable trigger user;
insert into public.catalog_universities (id, name, short_name, institution_type, recognitions, accreditation_text) values
  (9201, 'Zentest University', 'ZTU', 'Private University', '{UGC,AICTE}',
   'Distance/Online Education Approvals: UGC-DEB Entitled NAAC Rating & Specific Cycle Score: NAAC A++ Global/International x National Institutional Standing (Rank/Year/Agency): Ranked #20 / 2025 / NIRF Program-Specific National Rankings (Rank/Program/Year/Agency): Not Stated in Source Enrollment'),
  (9202, 'Quarktest University', 'QTU', 'Deemed-To-Be University', '{UGC}',
   'Distance/Online Education Approvals: Not Stated in Source NAAC Rating & Specific Cycle Score: NAAC A Global/International x');
insert into public.catalog_programs (id, university_id, level, level_raw, course, course_key, specialization, program_name, mode,
  fee_total, fee_yearly, fee_other, min_qualification, eligibility_text, program_key, active) values
  (920001, 9201, 'PG', 'Postgraduate', 'MBA', 'mba', 'Marketing', 'Master of Business Administration- Marketing', 'Online', 100000, 50000, '{"Year 2": 50000}', 'BACHELOR', null, 'zt1', true),
  (920002, 9201, 'PG', 'Postgraduate', 'MBA', 'mba', 'Finance', 'Master of Business Administration- Finance', 'ODL', 200000, 100000, '{"Year 2": 100000}', 'BACHELOR', 'Minimum 2 years of work experience required', 'zt2', true),
  (920003, 9202, 'PG', 'Postgraduate', 'MBA', 'mba', 'Marketing Management', 'Master of Business Administration- Marketing Management', 'Online', 150000, null, null, 'BACHELOR', null, 'zt3', true),
  (920004, 9201, 'UG', 'Undergraduate', 'BCA', 'bca', 'General', 'Bachelor of Computer Applications- General', 'Online', 90000, 30000, '{"Year 2": 30000, "Year 3": 30000}', '12TH', null, 'zt4', true),
  (920005, 9202, 'PG', 'Postgraduate', 'MA', 'ma', 'English', 'Master of Arts- English', 'Online', null, null, null, 'BACHELOR', null, 'zt5', true),
  (920006, 9202, 'PG', 'Postgraduate', 'MA', 'ma', 'English', 'Master of Arts- English (old)', 'Online', 80000, null, null, 'BACHELOR', null, 'zt6', false),
  (920007, 9201, 'PG', 'Postgraduate', 'MBA', 'mba', 'Marketing', 'Master of Business Administration- Marketing (campus)', 'Regular', 300000, null, null, 'BACHELOR', null, 'zt7', true);
select public.web_refresh_read_model();

create temp table t as select '{"university": ["zentest-university", "quarktest-university"]}'::jsonb as base;
create function pg_temp.s(extra jsonb) returns jsonb language sql as $$ select public.web_search((select base from t) || extra) $$;

insert into r select (pg_temp.s('{}') ->> 'total')::int = 5, 'visible offerings: active, mapped, not Regular (D-013)';
insert into r select not exists (select 1 from public.web_offering_search where id = 920007 and visible), 'Regular mode hidden by default';
insert into r select (pg_temp.s('{}') ->> 'total_groups')::int = 4, 'grouped by programme + specialisation';
insert into r select (select g->>'universities' = '2' and (g->>'fee_min')::numeric = 100000 and (g->>'fee_max')::numeric = 150000 and g->>'best_naac' = 'A++'
                      from jsonb_array_elements(pg_temp.s('{}') -> 'items') g where g->>'key' = 'mba:marketing'), 'group card: universities, fee range, best NAAC';
insert into r select (select jsonb_array_length(g->'top_universities') = 2 and g->'top_universities'->0->>'slug' = 'zentest-university'
                      from jsonb_array_elements(pg_temp.s('{}') -> 'items') g where g->>'key' = 'mba:marketing'), 'group card: top universities ranked by NAAC';

-- facets exclude their own selection, include every other filter, and are hierarchy-aware
insert into r select (pg_temp.s('{"programme":["mba"]}') ->> 'total')::int = 3, 'programme filter';
insert into r select (select (f->>'count')::int from jsonb_array_elements(pg_temp.s('{"programme":["mba"]}') -> 'facets' -> 'programme') f where f->>'value' = 'bca') = 1,
  'programme facet ignores its own selection (BCA still counted)';
insert into r select (select (f->>'count')::int from jsonb_array_elements(pg_temp.s('{"programme":["mba"]}') -> 'facets' -> 'spec') f where f->>'value' = 'marketing') = 2
  and (select (f->>'count')::int from jsonb_array_elements(pg_temp.s('{"programme":["mba"]}') -> 'facets' -> 'spec') f where f->>'value' = 'english') = 0,
  'specialisation facet narrowed by the chosen programme (zero-count options kept, disabled)';
insert into r select (select (f->>'count')::int from jsonb_array_elements(pg_temp.s('{"programme":["bca"]}') -> 'facets' -> 'mode') f where f->>'value' = 'ODL') = 0,
  'zero-count mode option is present, not hidden';
insert into r select (pg_temp.s('{"fee_max":120000}') ->> 'total')::int = 2, 'fee ceiling (fee-on-request rows excluded when a fee filter is set)';
insert into r select (pg_temp.s('{}') -> 'facets' -> 'fee' ->> 'on_request')::int = 1, 'fee facet reports offerings without a published fee';
insert into r select (pg_temp.s('{"naac":["A++"]}') ->> 'total')::int = 3, 'NAAC facet';
insert into r select (pg_temp.s('{"ugc_deb":true}') ->> 'total')::int = 3 and (pg_temp.s('{}') -> 'facets' ->> 'ugc_deb')::int = 3, 'UGC-DEB facet only counts stated entitlement';
insert into r select (pg_temp.s('{"nirf":true}') ->> 'total')::int = 3, 'NIRF facet';
insert into r select (pg_temp.s('{"work_exp":"required"}') ->> 'total')::int = 1, 'work-experience facet parsed from eligibility text';
insert into r select (pg_temp.s('{"duration":["13-24"]}') ->> 'total')::int = 2 and (pg_temp.s('{"duration":["25-36"]}') ->> 'total')::int = 1, 'duration facet from derived durations';
insert into r select (pg_temp.s('{"mode":["ODL"]}') ->> 'total')::int = 1, 'mode facet';
insert into r select (pg_temp.s('{"goal":"first-degree"}') ->> 'total')::int = 1, 'goal tag narrows to linked programmes';

-- eligibility
insert into r select (pg_temp.s('{"qual":"12th"}') ->> 'total')::int = 1, 'not-eligible offerings hidden by default';
insert into r select (pg_temp.s('{"qual":"12th","show_ineligible":true}') ->> 'total')::int = 5, '…and shown with the toggle';
insert into r select (pg_temp.s('{"qual":"12th"}') -> 'facets' -> 'eligibility' ->> 'not_eligible')::int = 4, 'eligibility facet counts hidden offerings';
insert into r select (select f->>'eligibility' = 'eligible' from jsonb_array_elements(pg_temp.s('{"qual":"graduation","view":"flat"}') -> 'items') f where (f->>'id')::bigint = 920001), 'offering marked eligible';

-- zero results never dead-end
insert into r select (pg_temp.s('{"programme":["bca"],"mode":["ODL"]}') ->> 'total')::int = 0
  and (pg_temp.s('{"programme":["bca"],"mode":["ODL"]}') -> 'relaxations') @> '[{"filter": "mode", "count": 1}]', 'zero results: which filter to relax and what it gives';
insert into r select jsonb_typeof(pg_temp.s('{"programme":["bca"],"mode":["ODL"]}') -> 'facets' -> 'fee') = 'object', 'fee facet is an object even with zero results';
insert into r select (pg_temp.s('{"q":"qwzxv"}') ->> 'total')::int = 0 and jsonb_array_length(pg_temp.s('{"q":"qwzxv"}') -> 'closest') > 0
  and (pg_temp.s('{"q":"qwzxv"}') ->> 'without_query')::int = 5, 'zero results from text: closest matches + count without the query';

-- sorting, flat view, paging
insert into r select (pg_temp.s('{"view":"flat","sort":"fee_asc"}') -> 'items' -> 0 ->> 'id')::bigint = 920004, 'flat view sorted by fee (low to high)';
insert into r select (pg_temp.s('{"view":"flat","sort":"fee_desc"}') -> 'items' -> 0 ->> 'id')::bigint = 920002, 'flat view sorted by fee (high to low)';
insert into r select jsonb_array_length(pg_temp.s('{"view":"flat","page_size":2,"page":3}') -> 'items') = 1, 'paging';
insert into r select (select jsonb_array_length(g->'items') from jsonb_array_elements(pg_temp.s('{"group_key":"mba:marketing"}') -> 'items') g) = 2, 'group expansion returns its offerings';

-- details
insert into r select exists (select 1 from jsonb_array_elements(public.web_offering_details(920001) -> 'alternatives') a where (a->>'id')::bigint = 920003)
  and not exists (select 1 from jsonb_array_elements(public.web_offering_details(920001) -> 'alternatives') a where (a->>'id')::bigint = 920001), 'details: same programme at other universities';
insert into r select (public.web_offering_details(920006) ->> 'id')::bigint = 920005 and (public.web_offering_details(920006) ->> 'moved_from')::bigint = 920006, 'details: replaced (renamed) offering resolves to the current one';
insert into r select public.web_offering_details(920007) is null, 'details: hidden offering not served';
insert into r select (public.web_offering_details(920001) -> 'university_facts' ->> 'ugc_deb') = 'entitled', 'details: university facts';
insert into r select jsonb_array_length(public.web_compare_offerings(array[920001, 920003, 920004, 920005, 920002])) = 4, 'compare: at most 4';
insert into r select (public.web_university_details('zentest-university') ->> 'offerings')::int = 3, 'university details';
insert into r select exists (select 1 from jsonb_array_elements(public.web_suggest('zentest') -> 'universities') u where u->>'slug' = 'zentest-university'), 'suggest: universities';

-- the read model exposes only allow-listed columns (no commission, partner or internal fields)
insert into r select not exists (
  select 1 from pg_attribute a where a.attrelid = 'public.web_offering_search'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attname not in ('id','program_key','university_id','uni_slug','uni_name','uni_short','uni_type','uni_logo','uni_state',
      'level_id','level_label','level_short','level_sort','category_id','category_label','programme_id','programme_name',
      'programme_full','programme_sort','programme_prior','spec_ids','spec_primary','spec_name','group_key','spec_display','format',
      'attributes','mode','fee_total','fee_yearly','fee_semester','fee_exam','fee_registration','emi_amount','fee_on_request',
      'duration_months','duration_source','duration_snippet','min_qualification','min_pct_general','min_pct_reserved',
      'work_exp_years','entrance_exam','ugc_deb','naac_grade','naac_rank','naac_accredited','nirf_rank','nirf_year','nirf_ranked',
      'aicte','verified_at','popularity','brochure_url','goal_ids','search_doc','search_text','visible','hidden_reason')),
  'read model columns are an explicit allow-list';
insert into r select not has_table_privilege('anon', 'public.web_offering_search', 'SELECT')
  and not has_table_privilege('authenticated', 'public.web_offering_search', 'SELECT'), 'read model not readable by browser roles';

-- polling: unchanged catalogue → no refresh; a change → refresh + revalidation enqueued
insert into r select (public.web_catalog_poll() ->> 'changed')::boolean = false, 'poll: no change, no work';
update public.catalog_programs set fee_total = 95000, updated_at = now() + interval '1 second' where id = 920004;
insert into r select (public.web_catalog_poll() ->> 'changed')::boolean, 'poll: catalogue change detected';
insert into r select (select (f->'fee'->>'total')::numeric from jsonb_array_elements(pg_temp.s('{"view":"flat","programme":["bca"]}') -> 'items') f) = 95000, 'poll: read model refreshed';
insert into r select exists (select 1 from public.web_outbox where kind = 'revalidate' and payload @> '{"tags":["catalog"]}'), 'poll: revalidation queued in the outbox';

-- web11 (load tests): the search log takes a batch as well as one entry.
create temp table sl0 on commit drop as select count(*) n from public.web_search_log;
select public.web_search_log_add('[{"q":"Online MBA","results":3,"source":"api"},{"q":"zzzz","results":0,"source":"api"}]');
select public.web_search_log_add('{"q":"bca","results":5}');
insert into r select (select count(*) from public.web_search_log) - (select n from sl0) = 3, 'search log accepts a batch and a single entry';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
