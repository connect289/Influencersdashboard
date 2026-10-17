-- Search benchmark at 10k+ offerings (spec 6.4: p95 < 150 ms). Runs inside a transaction and rolls back, so it can be
-- pointed at the local stack or the replica without leaving anything behind. Usage: psql <url> -f scripts/db/bench-10k.sql
\set QUIET on
begin;
alter table public.catalog_programs disable trigger user;
insert into public.catalog_universities (id, name, short_name, institution_type, recognitions, accreditation_text)
select 1000 + g, 'Bench University ' || g, 'BU' || g, u.institution_type, u.recognitions, u.accreditation_text
from generate_series(1, 100) g join public.catalog_universities u on u.id = 1 + (g % 29);
insert into public.catalog_programs (university_id, level, level_raw, course, course_key, dual, specialization, program_name,
  mode, fee_yearly, fee_semester, fee_total, fee_exam, fee_registration, fee_other, min_qualification, min_pct_general,
  min_pct_reserved, eligibility_text, flags, active, program_key)
select 1000 + ((c.id + g) % 100) + 1, c.level, c.level_raw, c.course, c.course_key, c.dual, c.specialization, c.program_name,
  c.mode, c.fee_yearly, c.fee_semester, c.fee_total * (0.8 + (g % 5) * 0.1), c.fee_exam, c.fee_registration, c.fee_other,
  c.min_qualification, c.min_pct_general, c.min_pct_reserved, c.eligibility_text, c.flags, c.active, md5(c.program_key || g)
from public.catalog_programs c, generate_series(1, 13) g;
select public.web_refresh_read_model() ->> 'refresh_ms' as refresh_ms;
select count(*) as visible from public.web_offering_search where visible;
\timing on
\set QUIET off
select length(public.web_search('{}')::text) as all_grouped;
select length(public.web_search('{"q":"mba in marketing"}')::text) as mba_marketing;
select length(public.web_search('{"programme":["mba"],"spec":["finance"],"naac":["A+","A++"],"fee_max":200000,"qual":"graduation"}')::text) as filtered;
select length(public.web_search('{"view":"flat","sort":"fee_asc"}')::text) as flat_fee;
select length(public.web_search('{"q":"data sciense"}')::text) as typo;
select length(public.web_search('{"q":"zzzz"}')::text) as zero;
select length(public.web_search('{"goal":"career-switch","qual":"graduation","page":3}')::text) as guided;
select length(public.web_suggest('mba mar')::text) as suggest;
rollback;
