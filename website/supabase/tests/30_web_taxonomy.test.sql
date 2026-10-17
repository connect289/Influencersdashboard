-- web3_taxonomy + derived facts: auto-mapper rules on synthetic catalogue rows (data-independent, so it runs on the
-- seeded local DB and on the empty production-schema replica), admin overrides, unmapped report, fact parsers.
begin;
create temp table r (ok boolean, name text) on commit drop;
alter table public.catalog_programs disable trigger user;
insert into public.catalog_universities (id, name, short_name, institution_type, recognitions, accreditation_text)
values (9101, 'Taxotest University', 'TXU', 'Private University', '{UGC}', null);

insert into public.catalog_programs (id, university_id, level, level_raw, course, course_key, specialization, program_name, mode, program_key, active) values
  (910001, 9101, 'PG', 'Postgraduate', 'MBA (with PAP option)', 'mba', 'Marketing Management (with Pay After Placement option)', 'Master of Business Administration - Marketing Management (with Pay After Placement option)', 'Online', 'tx1', true),
  (910002, 9101, 'PG', 'Postgraduate', 'MA', 'ma', 'Apprenticeship Embedded Degree Program', 'Master of Arts - Urdu - Apprenticeship Embedded Degree Program', 'Online', 'tx2', true),
  (910003, 9101, 'UG', 'Undergraduate', 'BCA', 'bca', 'Stack Development', 'Bachelor of Computer Applications- Full-Stack Development', 'Online', 'tx3', true),
  (910004, 9101, 'PG', 'Postgraduate', 'MBA', 'mba', 'Finance & Operations & Supply Chain Management', 'Master of Business Administration- Finance & Operations & Supply Chain Management', 'Online', 'tx4', true),
  (910005, 9101, 'UG', 'Undergraduate', 'BA', 'ba', 'Tamil Medium', 'Bachelor of Arts- Tamil Medium', 'Online', 'tx5', true),
  (910006, 9101, 'DIPLOMA', 'DIPLOMA', 'DIPLOMA', 'diploma', 'Finance Management', 'Post Graduate Diploma in Business Administration- Finance Management', 'ODL', 'tx6', true),
  (910007, 9101, 'CERTIFICATE', 'Certificate', 'Certificate', 'certificate', 'General', 'Certificate Programme in Digital Marketing- General', 'Online', 'tx7', true),
  (910008, 9101, 'DIPLOMA', 'DIPLOMA', 'DIPLOMA', 'diploma', '(ADDRA)', 'Advanced Diploma in Drug Regulatory Affairs Program - (ADDRA)', 'Online', 'tx8', true),
  (910009, 9101, 'PG', 'PGDM (Executive)', 'PGDM (Executive)', 'pgdm', 'Strategic Marketing Management (Executive)', 'Post Graduate Diploma in Management - Strategic Marketing Management (Executive)', 'Online', 'tx9', true),
  (910010, 9101, 'PG', 'Postgraduate', 'MBA', 'mba', 'Underwater Basket Weaving', 'Master of Business Administration- Underwater Basket Weaving', 'Online', 'tx10', true),
  (910011, 9101, 'PG', 'Postgraduate', 'MBA', 'mba', 'Intenational Finance', 'Master of Business Administration- Intenational Finance', 'Online', 'tx11', true),
  (910012, 9101, 'UG', 'Undergraduate', 'B.Tech', 'btech', 'Computer Science', 'Bachelor of Technology- Computer Science', 'Online', 'tx12', true),
  (910013, 9101, 'UG', 'Undergraduate', 'BBA', 'bba', 'commerce', 'Bachelor of Business Administration- Retail & E-commerce', 'Online', 'tx13', true),
  (910014, 9101, 'UG', 'Undergraduate', 'B.Com (Honours)', 'bcom', 'Work Integrated Learning Program', 'Bachelor of Commerce - General (Honours)- Work Integrated Learning Program', 'Online', 'tx14', true);

select public.web_tax_automap(false);

create temp view m as select catalog_program_id id, programme_id, specialisation_ids, spec_display, format, attributes, confidence, needs_review
  from public.web_tax_offering_map where catalog_program_id between 910001 and 910099;

insert into r select (select programme_id = 'mba' and specialisation_ids = '{marketing}' and attributes ? 'pay_after_placement' from m where id = 910001), 'PAP variant → MBA · Marketing + pay_after_placement';
insert into r select (select programme_id = 'ma' and specialisation_ids = '{urdu}' and format = 'apprenticeship' from m where id = 910002), 'format row: subject from program_name, format kept';
insert into r select (select specialisation_ids = '{software-development}' and spec_display = 'Full-Stack Development' from m where id = 910003), 'hyphen-cut specialisation repaired from program_name';
insert into r select (select specialisation_ids = '{finance,supply-chain-management}' and confidence = 'split' from m where id = 910004), 'dual specialisation split at the right "and"';
insert into r select (select specialisation_ids = '{general}' and attributes->>'medium' = 'Tamil' from m where id = 910005), 'medium of instruction is an attribute, not a subject';
insert into r select (select programme_id = 'pgdba' and specialisation_ids = '{finance}' from m where id = 910006), 'PG Diploma in Business Administration stored as DIPLOMA → PGDBA';
insert into r select (select programme_id = 'certificate' and specialisation_ids = '{digital-marketing}' and confidence = 'name' from m where id = 910007), 'generic certificate takes its subject from the name';
insert into r select (select specialisation_ids = '{drug-regulatory-affairs}' and spec_display = 'Drug Regulatory Affairs' from m where id = 910008), 'abbreviation-only specialisation resolved from the name';
insert into r select (select programme_id = 'pgdm' and specialisation_ids = '{marketing}' and attributes ? 'executive' from m where id = 910009), 'executive variant → PGDM · Marketing + executive';
insert into r select (select cardinality(specialisation_ids) = 0 and needs_review from m where id = 910010), 'unknown specialisation stays unmapped and flagged';
insert into r select (select specialisation_ids = '{international-finance}' from m where id = 910011), 'source typo mapped through synonyms';
insert into r select (select programme_id is null and needs_review from m where id = 910012), 'programme without a rule stays unmapped';
insert into r select (select specialisation_ids = '{retail-management,e-commerce}' from m where id = 910013), 'truncated "commerce" repaired to "Retail & E-commerce" and split';
insert into r select (select specialisation_ids = '{general}' and format = 'work-integrated' and attributes ? 'honours' from m where id = 910014), 'format row with honours subject';
insert into r select (select count(*) from public.web_tax_unmapped() where catalog_program_id in (910010, 910012)) = 2, 'unmapped rows are listed (nothing silently lost)';
insert into r select (select reason from public.web_tax_unmapped() where catalog_program_id = 910012) = 'no programme rule', 'unmapped reason explains why';

-- admin override persists; a later catalogue change flags it for review instead of overwriting
insert into r select (public.web_tax_set_mapping('{"catalog_program_id": 910010, "programme_id": "mba", "specialisation_ids": ["general-management"], "actor_email": "connect@eduwit.in"}') ->> 'ok')::boolean, 'admin mapping accepted';
insert into r select (public.web_tax_set_mapping('{"catalog_program_id": 910010, "programme_id": "mba", "specialisation_ids": ["nope"]}') ->> 'reason') = 'unknown_specialisation', 'admin mapping validated';
select public.web_tax_automap(false);
insert into r select (select specialisation_ids = '{general-management}' and not needs_review from m where id = 910010), 'automap never overwrites an admin mapping';
update public.catalog_programs set specialization = 'Underwater Basket Weaving II' where id = 910010;
select public.web_tax_automap(false);
insert into r select (select specialisation_ids = '{general-management}' and needs_review from m where id = 910010), 'changed row after admin mapping → kept and flagged for review';
insert into r select exists (select 1 from public.web_audit_log where action = 'taxonomy.set_mapping' and entity_id = '910010'), 'admin mapping audited';
insert into r select (select count(*) from public.web_university_profiles where catalog_university_id = 9101 and slug = 'taxotest-university') = 1, 'new university gets a profile with a slug';

-- normaliser and resolver
insert into r select public.web_norm('M.B.A. (Online) & HR') = 'mba online and hr', 'normaliser: dots, brackets, ampersand';
insert into r select (public.web_resolve_query('mba in marketing') -> 'programme') = '["mba"]' and (public.web_resolve_query('mba in marketing') -> 'specialisation') = '["marketing"]', 'resolver: programme + specialisation, stopwords ignored';
insert into r select (public.web_resolve_query('b com') -> 'programme') = '["bcom"]', 'resolver: spaced abbreviation';
insert into r select (public.web_resolve_query('mba online karna hai') -> 'mode') = '["Online"]', 'resolver: Hinglish filler ignored, mode kept';
insert into r select (public.web_resolve_query('hrm') -> 'specialisation') = '["human-resource-management"]', 'resolver: specialisation abbreviation';
insert into r select (public.web_resolve_query('pg diploma') -> 'level') = '["pg_diploma"]', 'resolver: longest match wins (pg diploma, not pg)';

-- university facts parser (strings from the catalogue's accreditation_text)
insert into r select public.web_university_facts('[ACCREDITATIONS_AND_STANDINGS] National Statutory Status: UGC Recognized, AICTE Recognized Distance/Online Education Approvals: UGC-DEB Approved NAAC Rating & Specific Cycle Score: NAAC A (CGPA 3.15/4.0 in the First Cycle) Global/International Accreditations: Not Stated in Source', '{UGC,AICTE}')
  @> '{"ugc_deb": "approved", "naac_grade": "A", "aicte": true}', 'facts: UGC-DEB approved, NAAC A, AICTE';
insert into r select (public.web_university_facts('Distance/Online Education Approvals: Not Stated in Source NAAC Rating & Specific Cycle Score: Not Stated in Source Global/International x', '{}') ? 'ugc_deb') is false
  and (public.web_university_facts('Distance/Online Education Approvals: Not Stated in Source NAAC Rating & Specific Cycle Score: Not Stated in Source Global/International x', '{}') ? 'naac_grade') is false, 'facts: "Not Stated in Source" yields nothing';
insert into r select public.web_university_facts('NAAC Rating & Specific Cycle Score: re-accredited with A++ Grade (CGPA 3.60/4.00) by NAAC in its Fourth Cycle Global/International x', '{}') ->> 'naac_grade' = 'A++', 'facts: NAAC grade inside prose';
insert into r select (public.web_university_facts('NAAC Rating & Specific Cycle Score: NAAC Accredited Global/International x', '{}')) @> '{"naac_accredited": true}'
  and not (public.web_university_facts('NAAC Rating & Specific Cycle Score: NAAC Accredited Global/International x', '{}') ? 'naac_grade'), 'facts: accredited without a grade shows no grade';
insert into r select public.web_university_facts('National Institutional Standing (Rank/Year/Agency): Ranked #36 in University Category / 2022 / NIRF; Ranked #71 in Overall Category / 2022 / NIRF Program-Specific National Rankings (Rank/Program/Year/Agency): Not Stated in Source Enrollment', '{}') -> 'nirf'
  @> '{"rank": 36, "year": 2022, "category": "University"}', 'facts: best NIRF rank of the latest year';
insert into r select (public.web_university_facts('National Institutional Standing (Rank/Year/Agency): #38 / 2025 / THE WEEK Hansa Research Program-Specific National Rankings (Rank/Program/Year/Agency): #184 / BBA program / 2024 / India Today Enrollment', '{}') ? 'nirf') is false, 'facts: other agencies are never shown as NIRF';
insert into r select public.web_university_facts('National Institutional Standing (Rank/Year/Agency): Ranked in Band 151–200 / 2024 / NIRF 2023 Program-Specific', '{}') -> 'nirf' @> '{"band": "151–200", "year": 2023}', 'facts: NIRF band without a rank';
insert into r select public.web_university_facts('National Institutional Standing (Rank/Year/Agency): Not Stated Program-Specific National Rankings (Rank/Program/Year/Agency): No. 1 / Pharmacy / 2024 / NIRF Enrollment', '{}') -> 'nirf_programmes' -> 0
  @> '{"rank": 1, "discipline": "Pharmacy", "year": 2024}', 'facts: programme-specific NIRF rank';

-- duration (two agreeing signals or an explicit statement; otherwise unknown)
insert into r select public.web_derive_duration('Fees: duration 2 years (63200 * 2 = 126400)', null, null, null, null) @> '{"months": 24, "source": "eligibility_text"}', 'duration: explicit statement';
insert into r select public.web_derive_duration(null, '{"Year 2": 30000, "Year 3": 30000}', 90000, 30000, null) @> '{"months": 36, "source": "fee_schedule"}', 'duration: year keys + total/yearly agree';
insert into r select public.web_derive_duration(null, '{"Semester 2,3 & 4": 1}', 120000, null, 30000) @> '{"months": 24}', 'duration: semester keys + total/semester agree';
insert into r select public.web_derive_duration(null, '{"Year 2": 30000}', null, null, null) is null, 'duration: one signal is not enough';
insert into r select public.web_derive_duration('a bachelor''s degree of 3 years duration', null, null, null, null) is null, 'duration: prior-degree length is not the programme length';

-- eligibility truth table
insert into r select public.web_eligibility('graduation', 'pg', 'BACHELOR') = 'eligible', 'eligibility: graduate → PG eligible';
insert into r select public.web_eligibility('12th', 'pg', 'BACHELOR') = 'not_eligible', 'eligibility: Class 12 → PG not eligible';
insert into r select public.web_eligibility('12th', 'ug', 'BACHELOR') = 'check', 'eligibility: contradictory UG row → check, never "not eligible"';
insert into r select public.web_eligibility('diploma', 'ug', '12TH') = 'check', 'eligibility: diploma vs Class 12 → check';
insert into r select public.web_eligibility('12th', 'ug', null) = 'check', 'eligibility: unknown requirement → check';
insert into r select public.web_eligibility(null, 'ug', '12TH') is null, 'eligibility: unknown student → not shown';
insert into r select public.web_eligibility('10th', 'certificate', '12TH') = 'not_eligible', 'eligibility: Class 10 → not eligible for Class-12 programmes';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
