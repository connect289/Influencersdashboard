-- Load tests only (docs/LOAD_TESTS.md): grows the LOCAL catalogue to 10,000+ offerings (14× the real one, 129
-- universities) and COMMITS it so the website can be load-tested over HTTP. Never run against production or the
-- replica; `npm run db:reset` restores the real local data. The synthetic rows use university ids 1001–1100.
\set ON_ERROR_STOP on
-- Run only through `npm run load:seed` (fixed local URL, port 54322).
do $$ begin
  if exists (select 1 from public.catalog_universities where id > 1000) then raise exception 'seed-10k: already seeded'; end if;
end $$;
begin;
alter table public.catalog_programs disable trigger user;
insert into public.catalog_universities (id, name, short_name, institution_type, recognitions, accreditation_text)
select 1000 + g, 'Load Test University ' || g, 'LTU' || g, u.institution_type, u.recognitions, u.accreditation_text
from generate_series(1, 100) g join public.catalog_universities u on u.id = 1 + (g % 29);
insert into public.catalog_programs (university_id, level, level_raw, course, course_key, dual, specialization, program_name,
  mode, fee_yearly, fee_semester, fee_total, fee_exam, fee_registration, fee_other, min_qualification, min_pct_general,
  min_pct_reserved, eligibility_text, flags, active, program_key)
select 1000 + ((c.id + g) % 100) + 1, c.level, c.level_raw, c.course, c.course_key, c.dual, c.specialization, c.program_name,
  c.mode, c.fee_yearly, c.fee_semester, c.fee_total * (0.8 + (g % 5) * 0.1), c.fee_exam, c.fee_registration, c.fee_other,
  c.min_qualification, c.min_pct_general, c.min_pct_reserved, c.eligibility_text, c.flags, c.active, md5(c.program_key || g)
from public.catalog_programs c, generate_series(1, 13) g
where c.university_id <= 1000;
alter table public.catalog_programs enable trigger user;
commit;
select public.web_refresh_read_model() ->> 'refresh_ms' as refresh_ms;
select count(*) as offerings, count(*) filter (where visible) as visible, count(distinct university_id) as universities from public.web_offering_search;
