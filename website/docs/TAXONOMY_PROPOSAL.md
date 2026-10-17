# Taxonomy proposal

Spec Section 5. Based on the production catalogue as exported read-only on 17 Oct 2026
(`supabase/seed/catalog_sample.json`: 29 universities, 715 programmes, 32 synonyms) and the database report
(`docs/discovery/db.md`).

## 1. What the catalogue holds today

| Spec concept | Where it is today | Quality |
|---|---|---|
| Level | `catalog_programs.level` (`UG` 238, `PG` 461, `DIPLOMA` 14, `CERTIFICATE` 2) + `level_raw` (`PGDM`, `PGDM (Executive)`, `UG+PG (Dual Degree)`, `PGCM`…) | Good; PGDM/PGCM/dual degrees need their own canonical levels |
| Programme | `course_key` (33 keys) + `course` (display, with variants such as `MBA (with PAP option)`, `MBA (Dual Specialization)`, `MBA (With Internship)`, `B.Com (Honours)`, `BCA (Honors)`) | Good key; variants are attributes, not programmes |
| Specialisation | `specialization` free text: **277 distinct strings** for far fewer real specialisations (`Marketing` / `Marketing Management` / `Marketing Management (Hons)` / `… (with Pay After Placement option)` / `Marketing (Executive)`); delivery formats stored as specialisations (`Apprenticeship Embedded Degree Program` 24, `Work Integrated Learning Program` 14, `Work Linked Program` 11, `Work Integrated Program` 9) with the real subject inside `program_name` (`Master of Arts - Urdu - Apprenticeship Embedded Degree Program`); dual specialisations (`Marketing & HR`); languages of instruction (`Hindi Medium`, `Tamil Medium`…) | **Needs mapping** |
| Offering | one `catalog_programs` row (university × programme × specialisation × mode); stable `program_key` (md5 of university + name + mode); `id` changes when a row is renamed (old row deactivated) | Good |
| Mode | `mode`: Online 620, ODL 88, Regular 7 | Good (Regular rows are hidden from an online/ODL finder unless the owner says otherwise — D-013) |
| Fees | `fee_total` (629 rows), `fee_yearly` (428), `fee_semester` (511), `fee_exam` (337), `fee_registration` (237), `fee_other` jsonb (EMI 214, application fee 207, per-year/semester splits…); `flags` record fee sanity actions (59 "fee on request", 44 contradictions dropped) | Mostly good; 86 rows have no total |
| EMI | `fee_other.Emi` (214 rows) — amount, period not stated | Shown only as "Easy EMI available"; "from ₹X/month" only if the period is confirmed (A-TAX-2) |
| Duration | **no column**; explicit in `eligibility_text` for 45 rows; inferable from fee structure (`fee_other` keys `Year 3`, `Semester 4`; total ÷ yearly = 2.0 / 3.0; total ÷ semester = 4 / 6) | Derived deterministically where two signals agree (§4) |
| Intakes | **no column** | Not shown; facet hidden until data exists (A-TAX-2) |
| Eligibility | `min_qualification` (BACHELOR 557, 12TH 149, DIPLOMA 5, MASTER 4), `min_pct_general` (293), `min_pct_reserved` (94), `eligibility_text` (long free text incl. work-experience notes) | Good for qualification; % for 41% of rows |
| Entrance exam | not structured; sometimes in `eligibility_text` | Parsed only on explicit phrases; else hidden |
| University approvals | `catalog_universities.recognitions` text[] (UGC, AICTE, …) + `accreditation_text` (structured "DATA_CHUNK" blob with `[ACCREDITATIONS_AND_STANDINGS]`, `[METRICS_AND_RANKINGS]`) | NAAC parseable for 28/29; UGC-DEB status stated for 25/29 ("Not Stated in Source" for 4); NIRF only where text says NIRF |
| University state, type, logo, description | type in `institution_type`; **no state, logo, description** | Editorial `web_university_profiles` (admin), facts only from catalogue |
| Last verified | `updated_at` (catalogue load time, 30 Sep 2026 for all rows) | Shown as "Data last verified" (per row) |
| Synonyms | `catalog_synonyms`: 32 course-level aliases (no specialisation synonyms) | Extended in `web_tax_synonyms` |

## 2. Canonical model (website build: `web_tax_*`, keyed to catalogue ids)

```
web_tax_levels          certificate · diploma · ug · pg_diploma · pg · doctorate  (+ display order, label)
web_tax_categories      management · computer-applications-it · commerce · arts-humanities · science · social-work · education
web_tax_programmes      mba, mca, bba, bca, bcom, mcom, ba, ma, msc, bsc, msw, pgdm, pgcm, dba, dca, diploma,
                        certificate, bba-mba, bca-mca, bcom-mba (dual degrees as their own programmes)
                        → level_id, category_id, slug, display name, full name, typical aliases
web_tax_specialisations canonical names, e.g. marketing, finance, human-resource-management, business-analytics,
                        data-science, ai-ml, operations-supply-chain, international-business, digital-marketing,
                        healthcare-management, …, general
web_tax_programme_specialisations   which specialisations exist under which programme (for hierarchy-aware facets)
web_tax_goal_tags       career-switch · promotion · government-job-eligibility · higher-studies · start-a-business ·
                        upskill-while-working · first-degree   (editable data)
web_tax_career_tags     e.g. "Marketing manager", "Data analyst", "HR business partner" (editable data)
web_tax_synonyms        alias → (programme | specialisation | level | university), with kind and weight;
                        seeded from catalog_synonyms + Hinglish/misspellings ("bcom", "b com", "mba online karna hai",
                        "hrm", "human resources", "m.b.a.")
web_tax_offering_map    catalog_programs.id + program_key → programme_id, specialisation_ids[] (dual = 2),
                        format (standard | work-integrated | apprenticeship | work-linked | executive),
                        attributes (honours, pay_after_placement, internship, dual_specialisation, medium),
                        mapped_by (rule | admin), rule_id, confidence, reviewed_at, reviewed_by
web_tax_mapping_rules   ordered, data-driven rules used by the auto-mapper (regex on course/specialization/program_name)
```
Everything is data editable in the admin (Phase 10), never code. Goal and career tags attach to programmes and
specialisations (`web_tax_tag_links`).

## 3. Auto-mapping (deterministic, reviewed in the admin)
Rules run in order; the first confident match wins; anything below threshold stays **unmapped** (hidden from the
finder, listed in the unmapped-rows report, never lost).

1. **Programme** from `course_key` (33 keys → canonical programme; `pgdm` + `level_raw = PGDM (Executive)` → PGDM with
   attribute `executive`; dual degrees by key).
2. **Variant attributes** stripped from `course` and `specialization`: `(with PAP option)` / `(with Pay After Placement
   option)` → `pay_after_placement`; `(Honours)` / `(Hons)` / `(Honors)` → `honours`; `(Executive)` → `executive`;
   `(With Internship)` → `internship`; `(Dual Specialization)` → `dual_specialisation`.
3. **Format rows**: when `specialization` is a delivery format, the subject is taken from `program_name`
   (`<degree> - <subject> - <format>`), and the format becomes an attribute.
4. **Medium rows**: `Hindi Medium`, `Tamil Medium`… → specialisation `general` + attribute `medium`.
5. **Specialisation normalisation**: lower-case, `&` → `and`, strip "management" suffix only where a canonical mapping
   says so (e.g. `Marketing Management` → marketing; `Financial Management` / `Finance Management` / `Finance` →
   finance; `HR` / `HRM` / `Human Resource` / `HRM (Human Resource Management)` → human-resource-management;
   `AI & ML` / `Artificial Intelligence and Machine Learning` / `Machine Learning & AI` → ai-ml), then exact lookup in
   `web_tax_synonyms`, then trigram similarity ≥ 0.6 against canonical names (marked `confidence = fuzzy` for review).
6. **Dual specialisations** (`Marketing & HR`, `Finance & Systems`) → two specialisation ids.

Expected first-run coverage (dry run on the export, Phase 3 will record the real number): ≥ 95% of rows mapped
automatically, the rest in the review queue.

### Sample mappings
| catalogue `course` / `specialization` / `program_name` | → programme | specialisation(s) | attributes |
|---|---|---|---|
| MBA / Marketing Management | MBA | Marketing | – |
| MBA (Dual Specialization) / Finance | MBA | Finance | dual_specialisation |
| MBA (with PAP option) / Human Resource Management (with Pay After Placement option) | MBA | Human Resource Management | pay_after_placement |
| MBA / Marketing & HR | MBA | Marketing, Human Resource Management | – |
| MA / Apprenticeship Embedded Degree Program / "Master of Arts - Urdu - Apprenticeship Embedded Degree Program" | MA | Urdu | format: apprenticeship |
| B.Com (Honours) / Work Integrated Learning Program / "Bachelor of Commerce - General (Honours)- Work Integrated Learning Program" | B.Com | General | honours, format: work-integrated |
| PGDM (Executive) / Strategic Marketing Management (Executive) | PGDM | Marketing | executive |
| BA / Hindi Medium | BA | General | medium: Hindi |
| MCA / AI & ML | MCA | AI & Machine Learning | – |
| BCA (Honors) / Cyber Security | BCA | Cyber Security | honours |

## 4. Derived facts — rules (no guessing)
Every derived value stores its **source** (`catalogue_field`, `eligibility_text`, `accreditation_text`,
`fee_schedule`) and the matched snippet, and the admin data-quality dashboard lists them.
- **Duration**: (a) explicit `Duration … N years/months/semesters` in `eligibility_text`; else (b) the highest
  `Year N` / `Semester N` key in `fee_other` together with a consistent total÷yearly or total÷semester ratio (within 5%);
  otherwise **unknown** (not shown, not in the facet).
- **NAAC grade**: regex over `accreditation_text` `NAAC Rating…:` section (`A++`, `A+`, `A`, `B++`, `B+`, `B`); "NAAC
  Accredited" without grade → shown as "NAAC accredited"; "Not Stated in Source" → nothing.
- **UGC-DEB**: `Distance/Online Education Approvals:` section mentioning "UGC-DEB" (approved / entitled / recognised);
  "Not Stated in Source" → nothing (and the homepage trust line drops "100% UGC-DEB entitled" unless every listed
  university has it — D-014).
- **NIRF**: only a ranking whose agency is NIRF; other agencies (THE WEEK, India Today) are not shown as NIRF.
- **AICTE**: `recognitions` contains `AICTE`.
- **Entrance exam**: explicit "entrance exam/test required|not required" phrases only.
- **Work experience required**: explicit "N years of work experience" phrases only.
- **EMI**: "Easy EMI available" when `fee_other.Emi` is present (spec 14 says show it alongside every fee; the owner
  decided "Easy EMI available" appears with every fee — D-015 records that it is shown on all fees, and the amount only
  when present).

## 5. Data-quality report (initial; full detail in `docs/discovery/db.md`)
| Issue | Rows | Example |
|---|---|---|
| Specialisation naming variants | 277 strings | `Marketing`, `Marketing Management`, `Marketing Management (Hons)`, `Digital Marketing (Executive)` |
| Delivery format stored as specialisation | 58 | `Work Linked Program` with subject in `program_name` |
| No total fee | 86 (59 "fee on request") | flags `fee on request` |
| Contradictory fee fields dropped by the loader | 44 | flag `fee check: yearly and total fees contradict each other; both dropped` |
| No duration column | 715 | derived for most rows (§4) |
| No intakes | 715 | facet hidden |
| Min % missing | 422 | eligibility shows qualification only |
| UGC-DEB status not stated | 4 universities | BML Munjal, Christ, DPU-COL, MITSDE |
| NAAC grade not stated | 1 university | MITSDE |
| Duplicate-looking rows (same university × programme × specialisation × mode) | 16 groups | AJU MBA Marketing (standard vs dual specialisation) — resolved by attributes |
| Regular (on-campus) mode | 7 | hidden from the finder by default |
| Specialisation cut at a hyphen by the loader | ≥ 7 | id 531 "Retail & E-commerce" → `commerce`; 623/581 "Full-Stack Development" → `Stack Development`; 151 "Open-Source Technologies" → `Source Technologies` — the mapper re-derives the specialisation from `program_name` when the stored value is a suffix of a hyphenated word |
| UG rows requiring a bachelor's degree (contradiction) | 89 | id 700 VGU "BBA- FinTech" says "Passed 10+2" in its text — eligibility shows **"Check eligibility"** (never "Not eligible") whenever `level = UG` and `min_qualification = BACHELOR` |
| Same programme name in two modes | 14 DDU pairs | ODL ₹42,500 vs Online ₹52,500 — mode always shown |
| `catalog.programmes_v` duration/EMI always null (wrong `fee_other` keys) | all | the website does not read `catalog.*`; handoff note to the B2B owner |
| Brochures hosted in another Supabase project's storage | 569 | brochure links shown only as "Download brochure" with `rel="noopener"`; flagged for the owner |
| Typos in source | a few | `Intenational Finance`, `Digital Finance & Accountinc Analytics` (mapped via synonyms) |

## 6. Shared layer (later)
Promote `web_tax_*` to shared `catalog_tax_*` with a rename migration (A-TAX-1) once approved, so Witty's
`w2_search_programs` and the CRMs use the same canonical names. The website code reads the taxonomy only through
`web_*` functions, so the promotion needs no UI change.
