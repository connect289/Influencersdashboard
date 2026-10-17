# Discovery: production database (catalogue, leads, agent messages)

Phase 0, read-only survey of Supabase project `xlseqwgyjuqhktrguhyc` (Mumbai) on **17 Oct 2026**. Every statement run was a
`SELECT` over tables, `pg_catalog` / `information_schema`, or `pg_get_functiondef` / `pg_get_viewdef` / `pg_get_triggerdef`,
plus the MCP `list_tables` / `list_extensions` / `list_migrations` calls. No function with side effects was called, nothing
was written. No personal data was copied: leads and messages were profiled with counts and enum-like values only.

Companion files:
- `website/supabase/prod-snapshot/catalog.sql`, `leads.sql`, `messages.sql`: reconstructed DDL + verbatim function bodies.
- `website/supabase/seed/catalog_sample.json`: full export of `catalog_universities` (29), `catalog_programs` (715),
  `catalog_synonyms` (32).
- `website/docs/discovery/crm-conventions.md`: the CRM code survey (Intake API, consent texts, staff auth).

---

## 0. Headline facts

| Topic | Fact |
|---|---|
| Catalogue source of truth | `public.catalog_universities` / `catalog_programs` / `catalog_synonyms`, loaded by Witty's n8n through `catalog_stage_add` + `catalog_commit` from one master sheet (`source_file = 'master'`). Everything else (`catalog.*` views, `b2c.programme_cache`, `course_directory`) is derived from it. |
| Catalogue size | 29 universities, 715 programmes (all `active`), 32 synonyms. Last load 30 Sep 2026 16:19 UTC (every row has the same `updated_at`). |
| Shape | Flat: one row = university × programme name × mode. Level, course (`course_key`), specialisation and mode are columns; no separate programme / specialisation / offering tables; **no duration, intake, EMI, state, logo, NAAC, NIRF, UGC-DEB validity or last-verified columns**. |
| Public read access | None. anon has no policy on `catalog_*` (RLS on) and no USAGE on schema `catalog`. The website needs its own read path (service-role server reads, or new `web_` views). |
| Lead write path | `public.lead_intake(p jsonb) → jsonb`, one overload, SECURITY DEFINER, EXECUTE only for `service_role`. Duplicate key = **phone only** (`crm_find_lead`). |
| Website `source_system` | `web_agent` (already a *trusted* value inside `lead_intake`). `lead_source` for the website agent: `website_agent` (consent-channel name and B2B routing list). Old OTP flow used `lead_source = 'website'`. |
| Verified flags | `student_leads.phone_verified_at`, `phone_verification_method`, `email_verified_at`, `email_confirmed` exist, but **`lead_intake` cannot set `email_verified_at` or `phone_verified_at`** (not in its allow-list). |
| Routing impact | B2B `engine.require_verified_phone_sources = ["website_agent","web_agent"]`: a website lead with `phone_verified_at IS NULL` is classed **unqualified (`phone_not_verified`)** and is not routed until a setting or directive changes. Owner decision "no phone OTP" conflicts with this; needs an approval. |
| Messages table | `public.w2_messages` (+ `w2_conversations`). Keyed by **phone**; **no channel, lead_id or session column**. Written by `w2_inbox_add` (in) and `w2_commit_turn` / `w2_nurture_done` (out). |
| Extensions | pgcrypto, pg_trgm (public), vector 0.8.0 (public), pg_cron, pg_net, pgmq, supabase_vault, uuid-ossp, pg_stat_statements. **Not installed: unaccent, pg_graphql, citext.** |
| Auth | 4 `auth.users` (all email-confirmed, 0 phone, 0 anonymous); identities: google 4, email 2. These are CRM staff, not students. |

---

## 1. Programme catalogue

### 1.1 Objects and row counts

| Object | Kind | Rows | Purpose / owner |
|---|---|---|---|
| `public.catalog_universities` | table | 29 | Universities. Owned by Witty. |
| `public.catalog_programs` | table | 715 | Programme offerings (university × programme × mode). Owned by Witty. |
| `public.catalog_synonyms` | table | 32 | Course-name aliases → `course_key`. Owned by Witty. |
| `public.catalog_stage` | table | 0 | Transient loader staging (`batch`, `kind` = university/program, `row` jsonb). Emptied by `catalog_commit`. |
| `catalog.universities_v` | view | 29 | 1:1 over `catalog_universities` (B2B CRM, m32c). |
| `catalog.synonyms_v` | view | 32 | 1:1 over `catalog_synonyms`. |
| `catalog.programmes_v` | view | 715 | Active programmes + university + live partner-offer overlay (fees fallback, intakes, deadlines, partner count). |
| `catalog.partner_rates_v` | view | 0 | **Commission rates per partner/programme. Commercial. Never expose.** |
| `catalog.changes` | table | 0 | Append-only change feed (`programme_version`, `rate`) for cache refresh. |
| `b2c.programme_cache` | table | 715 | B2C CRM's denormalised copy (adds `duration_months`, `emi_monthly`, `intakes`, `partners`). |
| `b2b.partner_programmes` (+ `_versions`, `_rows`, `_sources`) | tables | 0 | B2B partner price sheets matched to `catalog_programs.id` / `program_key` (m5a). Empty today. |
| `public.course_directory` | table | 715 | Legacy Witty v1 n8n vector store: one text chunk per programme, `embedding vector(3072)`. |
| `public.eduwit_knowledge_base` | table | 35 | Legacy v1 FAQ vector store (Drive PDFs), `vector(3072)`. |
| `public.w2_kb_docs` / `w2_kb_chunks` | tables | 1 / 1 | Witty 2.0 knowledge base (FAQ docs, chunks with `embedding` + `search_doc`). |

(`list_tables` reports `n_live_tup`, which is stale: it shows 0 rows for `course_directory` and `eduwit_knowledge_base`; `count(*)` gives 715 and 35.)

### 1.2 `public.catalog_universities`

```
id bigint PK default nextval   name text NOT NULL UNIQUE   short_name text   institution_type text
recognitions text[]            accreditation_text text     updated_at timestamptz NOT NULL default now()
```
- `institution_type` values: Private University (15), Deemed-To-Be University (7, plus one "Deemed-To-Be-University"),
  Public University (3), Private Deemed University, State University, Central University.
- `recognitions` is a free-form array: `{"UGC","JNRC","ASCO","OCI","AICTE","BCI","PCI","INC"}`,
  `{"UGC Recognized Private Deemed University"}`, `{"Recognized under Sections 2(f) and 12(B) of UGC Act","1956"}` (split on a
  comma), `{"Not Stated in Source"}` (3 universities), `{"UGC","NBA倾",...}` (stray CJK character).
- **Approvals, NAAC, NIRF and rankings exist only inside `accreditation_text`**, a pasted "DATA_CHUNK" blob with labelled
  segments, e.g. `... Distance/Online Education Approvals: UGC-DEB Approved NAAC Rating & Specific Cycle Score: NAAC A
  (CGPA 3.15/4.0 in the First Cycle) ... National Institutional Standing (Rank/Year/Agency): #38 / 2025 / THE WEEK ...`.
  Labels are consistent enough to parse (`Distance/Online Education Approvals:`, `NAAC Rating & Specific Cycle Score:`,
  `National Institutional Standing (Rank/Year/Agency):`, `Other Quality Certifications:` which carries "AICTE Approved"),
  but values are prose and many are marketing claims.
- No state, city, logo, website, description, UGC-DEB entitlement validity or "last verified" column.

### 1.3 `public.catalog_programs`

```
id bigint PK                     university_id bigint NOT NULL FK → catalog_universities ON DELETE CASCADE
level text                       level_raw text          course text          course_key text
dual boolean NOT NULL false      specialization text     program_name text NOT NULL       mode text
fee_yearly numeric  fee_semester numeric  fee_total numeric  fee_exam numeric  fee_registration numeric
fee_other jsonb                  min_qualification text  min_pct_general numeric  min_pct_reserved numeric
eligibility_text text            brochure_url text       source_row integer   flags text[]
active boolean NOT NULL true     updated_at timestamptz NOT NULL   program_key text UNIQUE
search_doc tsvector GENERATED ALWAYS AS (to_tsvector('simple', program_name||' '||specialization||' '||course)) STORED
source_file text
```
Indexes: `(course_key, level, mode) WHERE active`, `(course_key, specialization) WHERE active`, GIN trigram on `course`,
`program_name`, `specialization`, GIN on `search_doc`, unique `program_key`, `university_id`, `source_file`.
Trigger `catalog_programs_fee_check_trg` (BEFORE INSERT/UPDATE) runs `w2_fee_sanity()` and rewrites fees (see §1.6).

**Identity.** `program_key = md5(lower(university.name)|lower(program_name)|lower(mode))`, set by `catalog_commit`, which
upserts on it and deactivates (never deletes) rows missing from a new load. So `id` is stable while the university name,
programme name and mode do not change; a renamed row gets a new id and the old one goes `active = false`. B2B partner
offers point at both `id` and `program_key` without a foreign key. **`web_` taxonomy tables should key on
`catalog_programs.id` and also store `program_key`** so a rename shows up as "unmapped" instead of silently mismatching.

**How each fact is stored**

| Fact | Where | Notes |
|---|---|---|
| Level | `level` ∈ PG 461, UG 238, DIPLOMA 14, CERTIFICATE 2 | `level_raw`: Postgraduate 433, Undergraduate 238, DIPLOMA 14, PGDM (Executive) 13, PGDM 10, UG+PG (Dual Degree) 3, PGCM 2, CERTIFICATE 1, Certificate 1. No PG Diploma or Doctorate level; PGDM/PGCM are filed under PG. |
| Programme | `course_key` (canonical-ish) + `course` (display) | see §1.5 |
| Specialisation | `specialization` | never null; "General" = no specialisation (72 rows) |
| University | `university_id` | |
| Mode | `mode` ∈ Online 620, ODL 88, Regular 7 | Regular = 7 BML Munjal on-campus MBAs |
| Total fee | `fee_total` | null for 86 rows |
| Per year | `fee_yearly` | null 287 |
| Per semester | `fee_semester` | null 204 |
| Exam / registration | `fee_exam` (null 378), `fee_registration` (null 478) | |
| EMI | `fee_other->'Emi'` (number, ₹/month) on 214 rows, range ₹1,042–₹18,710 | `catalog.programmes_v.emi_available/typical_emi` read other keys, so they are always null |
| Other fees | `fee_other` keys (83 distinct): Application Fee 207, Year 2 139, Transcript Fee 96, Convocation Fee 66, Semester 2/3/4 …, Pay After Placement variants, Hostel Charges, `as_imported` 64 (original values before the fee check) | free-form sheet headings, typos included ("Tution Fee", "Second Spilt Payment", "Pay After Placemnet Fees") |
| Duration | **not stored** | only derivable from `eligibility_text` prose (160 rows mention years/months) or fee keys (Semester 6, Year 3). `programmes_v.duration` reads `fee_other->>'duration'`, which no row has. `b2c.programme_cache.duration_months` exists (derived by the B2C CRM). |
| Eligibility | `min_qualification` ∈ BACHELOR 557, 12TH 149, DIPLOMA 5, MASTER 4; `min_pct_general` (null 422), `min_pct_reserved` (null 621); `eligibility_text` (never null; 12 = "Not specified") | `eligibility_text` is a flattened key/value dump ("Academic Level, GRADUATION, Min Score (General), …, Documents Required, …, Fees Structure, …") |
| Intakes / deadlines | **not stored** in `catalog_programs`; `programmes_v.intakes/deadlines` come only from live B2B partner offers (none today) | |
| Approvals (UGC-DEB, NAAC, NIRF, AICTE) | university level only, inside `accreditation_text` (+ `recognitions[]`) | nothing per programme (e.g. AICTE for MBA/MCA) |
| Last verified | **not stored**; only `updated_at` (load time, identical for all rows) | |
| Logo | **not stored** anywhere in the catalogue | `b2b.partners.logo_url` is for partner edtechs, not universities |
| Brochure | `brochure_url` (null 125); 569 URLs point at another Supabase project's public bucket (`clfjuwoibezhrkpawuij.supabase.co/storage/v1/object/public/university-asset/...`) | third-party hosting; may vanish |
| Pay-after-placement, internship, dual | encoded in `course` ("MBA (with PAP option)"), `specialization` ("… (with Pay After Placement option)"), `fee_other` keys and `dual` (11 rows) | |
| Data-quality flags | `flags[]`: "fee on request" 59; "fee check: …" 64 | |

### 1.4 `public.catalog_synonyms` (complete contents)

Course-level only; aliases are lower-case alphanumerics (spaces and dots removed). No specialisation or Hinglish synonyms.

| course_key | aliases |
|---|---|
| ba | bachelorofarts, baprog, baprogramme |
| bba | bachelorofbusinessadministration, bachelorsinbusinessadministration |
| bca | bachelorofcomputerapplication, bachelorofcomputerapplications |
| bcom | bachelorofcommerce, bcomhonours, bcomhons |
| bsc | bachelorofscience |
| btech | bachelorofengineering, bacheloroftechnology, be, engineering (no btech rows exist) |
| ma | masterofarts |
| mba | distancemba, emba, executivemasterofbusinessadministration, executivemba, masterofbusinessadministration, mastersinbusiness, mastersinbusinessadministration, onlinemba |
| mca | masterofcomputerapplication, masterofcomputerapplications |
| mcom | masterofcommerce |
| msc | masterofscience |
| mtech | masteroftechnology, me (no mtech rows exist) |
| pgdm | pgdiplomainmanagement, postgraduatediplomainmanagement |

Specialisation abbreviations live **hard-coded inside `w2_search_programs`** (ai, ml, aiml, hr, hrm, it, ba, scm, ds, ib, om,
pm, dm, fin, mkt, ops), not in a table.

### 1.5 Distinct values

**course_key / course (rows, distinct specialisations)**

| course_key | level | course labels | rows | specs |
|---|---|---|---|---|
| mba | PG | MBA, MBA (Dual Specialization) 7, MBA (With Internship) 4, MBA (with PAP option) 15 | 252 | 122 |
| bba | UG | BBA, BBA (With Internship) 1, BBA (with PAP option) 4 | 108 | 66 |
| mca | PG | MCA, MCA (With Internship) 1 | 72 | 49 |
| ma | PG | MA | 65 | 17 |
| bca | UG | BCA, BCA (Honors) 4, BCA (with PAP option) 4 | 56 | 40 |
| ba | UG | BA, BA (Education) 1 | 36 | 19 |
| bcom | UG | B.Com, B.Com (Honours) 6 | 35 | 24 |
| mcom | PG | M.Com, M.Com (With Internship) 3 | 27 | 12 |
| pgdm | PG | PGDM, PGDM (Executive) 13 | 23 | 23 |
| msc | PG | M.Sc | 15 | 8 |
| diploma | DIPLOMA | DIPLOMA | 12 | 9 |
| bsc | UG | B.Sc | 3 | 3 |
| msw, certificate, pgcm | PG / CERTIFICATE / PG | MSW, Certificate/CERTIFICATE, PGCM | 2 each | |
| bbamba, bcommba, bcamca | PG (dual) | BBA+MBA, B.Com+MBA, BCA+MCA | 1 each | |
| dca, dba | DIPLOMA | DCA, DBA ("Diploma in Business Administration") | 1 each | |

**Specialisations**: ~290 distinct strings. Top: General 72, Human Resource Management 33, Apprenticeship Embedded Degree
Program 24, Marketing Management 24, Finance 18, Marketing 18, Business Analytics 16, Financial Management 15, Data Science
14, Work Integrated Learning Program 14, Economics 13, Political Science 12, Digital Marketing 11, Operations Management 11,
Work Linked Program 11, English 10. Full list: `select specialization, count(*) from catalog_programs group by 1`.

**University programme counts**: BVDU 55, Shoolini 55, Amity 45, DSU 43, MUJ 43, DDU 42, VGU 32, CCSU 31, DPU-COL 31, LPU 31,
MITSDE 30, Jain 29, SMU 28, UPES 25, NMIMS 22, AJU 20, AU 20, Galgotias 18, Alliance 16, GLA 15, AMU 14, Uttaranchal 14,
Jamia Hamdard 13, MZU 13, Christ 9, BML Munjal 7, VIT 7, JIIT 5, Sandip 2.

### 1.6 Data-quality issues (with examples)

1. **Specialisation naming variants (no canonical layer).** HR: "Human Resource Management" 33, "Human Resource" 5, "HR" 1,
   "HRM (Human Resource Management)" 1, "Human Resource Management (Honours)" 1, "… (with Pay After Placement option)" 2.
   Finance: "Finance" 18, "Financial Management" 15, "Finance Management" 7, "Finance & Accounting" 3. Marketing:
   "Marketing" 18 vs "Marketing Management" 24. AI/ML: "Artificial Intelligence & Machine Learning" 4, "… and Machine
   Learning" 2, "AI & ML" 1, "Machine Learning and Artificial Intelligence" 1, "Machine Learning & AI" 1. Agri: "Agribusiness
   Management" 2, "Agri Business Management" 1, "AgriBusiness Management" 1, "Agri Business" 1. Healthcare: "Health Care
   Management" 2, "Healthcare Management" 2, "Hospital and Healthcare Management" 2. Spelling: "Cyber Security" 4 vs
   "Cybersecurity" 2, "Blockchain Technology" vs "Technologies", "Intenational Finance", "Digital Finance & Accountinc Analytics".
2. **Specialisation mis-parsed on the hyphen** in "Programme- Specialisation": id 531 "Bachelor of Business Administration-
   Retail & E-commerce" → specialization **"commerce"**; 623/581 "Full-Stack Development" → **"Stack Development"**; 151
   "Open-Source Technologies" → **"Source Technologies"**; 557 "E-Business" → "Business"; 540 "E-Commerce" → "Commerce";
   431 → "general (DPA)"; 432 → "(ADDRA)".
3. **Attributes stuffed into course/specialisation**: Pay After Placement (23 rows) in both `course` and `specialization`;
   "(Honours)"/"(Hons)" (e.g. "Marketing Management (Hons)", "Finance Management (Hons)"); "(Executive)"; programme types as
   specialisations ("Apprenticeship Embedded Degree Program" 24, "Work Integrated Learning Program" 14, "Work Linked
   Program" 11, "Work Integrated Program" 9); medium of instruction as specialisation (BA "Hindi/Tamil/Telugu/Kannada/
   Malayalam Medium", ids 72–77); dual specialisations as one string ("Marketing & HR", "Finance & Operations & Supply Chain
   Management").
4. **Same offering in two modes = two rows with identical `program_name`.** 14 DDU pairs (ODL + Online), e.g. ids 247/248
   "Master of Business Administration- Marketing" (ODL ₹42,500 / Online ₹52,500). Correct as offerings, but the finder must
   show mode explicitly. Distinct (university, course_key, specialisation, mode) = 677 of 715, so ~38 further rows collide on
   that key (dual/PAP/internship/Honours variants).
5. **Missing fees.** 86 rows have no fee at all (59 flagged "fee on request", e.g. id 138 SMU "MBA- Finance & Healthcare");
   287 no yearly, 204 no semester. Show "Ask an advisor" for these.
6. **Inconsistent fee units, auto-corrected.** `w2_fee_sanity` dropped or moved values on 64 rows (originals kept in
   `fee_other.as_imported`): 17 "yearly and total fees contradict each other; both dropped" (e.g. id 82 AMU MA Urdu:
   yearly 15,800 vs total 8,500 → both null), 13 "semester fee … dropped", 9 "semester and total … both dropped",
   7 "yearly fee was the total for 6 semesters; moved to total" (id 531 MUJ BBA: ₹1,39,500 moved from yearly to total),
   14 "do not fully agree; review the sheet" (kept), 1 all dropped. `fee_semester × 2 ≠ fee_yearly` on 162 rows (often
   because semester 1 includes one-time fees). Some "yearly" figures are first-year-only ("The above fee is applicable to
   First year only").
7. **Eligibility contradictions.** 89 UG rows have `min_qualification = 'BACHELOR'` (BCA 29, BBA 33, BA 16, B.Com 8, B.Sc 3),
   e.g. id 700 VGU "BBA- FinTech" whose own text says "Passed 10+2". `eligibility_text` is an unstructured dump; 12 rows say
   "Not specified". Percentages missing on 422 rows.
8. **Approvals not structured.** No UGC-DEB/NAAC/NIRF/AICTE columns; university-level prose only. Christ University's
   "Distance/Online Education Approvals" is "Not Stated in Source"; MITSDE (30 programmes, ODL PGDM) shows only "AICTE
   Approved" and no UGC-DEB; BML Munjal is a Regular (on-campus) programme set with "Not Stated in Source". Several "NIRF"
   statements are vague ("Recognized in National Institutional Ranking Framework …", "Top 200 / 2024 / NIRF Recognized").
   Spec §1 says "29 UGC-DEB entitled universities"; the data does not show that for every one of the 29.
9. **University text hygiene.** `accreditation_text` sometimes wrapped in literal quotes or `"[` … (AJU, Amity, JIIT);
   `recognitions` contains "NBA倾", "1956" (split), "Not Stated in Source"; `short_name` equals the full name for 8
   universities; `name` for D. Y. Patil is "D. Y. Patil University" (`w2_search_programs` has a special dot-stripping match).
10. **Level taxonomy gaps.** No PG Diploma level (PGDM/PGCM/Executive PGDM under PG); "DBA" is a Diploma (not a Doctorate);
    dual degrees (BBA+MBA) are level PG; "Certificate" vs "CERTIFICATE"; `level_raw` "Postgraduate" vs "PGDM (Executive)".
11. **Odd rows.** id 607 "Master of Business Administration Premium- General"; id 431 Diploma in Professional Arabic, total
    ₹9,500; MITSDE PGDM rows each with a unique specialisation (23 PGDM rows, 23 specs).
12. **Synonyms**: course-level only; `btech`/`mtech`/`be`/`engineering` map to course_keys with no rows; no specialisation
    synonyms; no Hinglish ("mba online karna hai", "b com").
13. **Derived views partially broken**: `catalog.programmes_v.duration`, `emi_available`, `typical_emi`,
    `scholarship_notes` are always null (wrong `fee_other` keys); `intakes`/`deadlines` empty until partners publish offers.
14. **Freshness**: one load for everything (30 Sep 2026); no per-row verification date. "Last verified" must come from a
    `web_` table or from `updated_at` with that caveat.

### 1.7 Who reads the catalogue (source of truth)

- **Witty (n8n)** loads it (`catalog_stage_add` → `catalog_commit`, bumps `w2_meta.catalog_version`, clears
  `w2_search_cache`) and reads it through `w2_search_programs(q jsonb)` (course via `catalog_synonyms`, specialisation via
  trigram similarity + hard-coded abbreviations, mode, university fuzzy match; returns up to 30 rows with fees, `fee_emi`
  from `fee_other->>'Emi'`, `pay_after_placement`, `loan_available` (regex on eligibility text), `brochure_url`), its cached
  wrapper `w2_search_programs_cached`, and `w2_catalog_index()` (prompt text listing courses, top 6 specialisations, modes,
  levels). The legacy `course_directory` vector store is v1 and unused by SQL.
- **B2B CRM** reads `catalog_programs` directly in ~30 functions (matching partner sheets: `b2b.match_course_key`,
  `programme_match_version`, `catalogue_search`, rates, money) and owns schema `catalog` (views for the B2C CRM).
- **B2C CRM** reads `catalog.programmes_v` / `universities_v` as role `b2c_app` into `b2c.programme_cache` (715 rows) and
  serves `b2c.programme_search` / `programme_facets`.
- Repo: `b2b-crm/supabase/migrations/m32c_a4_catalog.sql` (views), `20261006133457_m5a_programme_repository.sql`
  (partner programme repository: "Reads catalog_* only … nothing on catalog_* changes"); `b2c-crm/supabase/migrations/b41*`,
  `b44*` (cache, search, facets).

**Conclusion:** `public.catalog_*` is the single source of truth; partner offers (`b2b.partner_programmes`) are an overlay
that can only add fees/intakes for programmes already in the catalogue. The website should read `catalog_programs` +
`catalog_universities` (via its own `web_` views/functions with a server-side service-role client) and never
`catalog.partner_rates_v` or `b2b.partner_programmes.commission`.

### 1.8 Can a shared taxonomy layer be added?

Yes, additively. Nothing in the catalogue has a canonical programme/specialisation table today, and every consumer keys on
`catalog_programs.id` / `program_key` / `course_key`. A versioned layer (canonical levels, programmes, specialisations,
synonyms, attribute tags such as PAP / Honours / Executive / medium, and a mapping table `offering → (programme,
specialisation, attributes)` keyed on `catalog_programs.id` + `program_key`) can sit beside the catalogue without touching
it. Build it as `web_` tables now; promoting it to a shared schema (e.g. `taxonomy.*`, read by Witty's `w2_search_programs`
and the B2B matcher) needs owner approval because those functions would have to change.

---

## 2. `public.student_leads`

150 columns, `id bigint GENERATED BY DEFAULT AS IDENTITY`. Full DDL in `prod-snapshot/leads.sql`. 2 rows today
(`lead_source = whatsapp_direct`, `channel = whatsapp`, `updated_by = witty`); backups `student_leads_backup_20261001/02/04/05`
hold 94–98 earlier rows (`lead_source`: organic 90, legacy 2, test_hermes 1, null 5; `lead_status`: HOT 37, UNQUALIFIED 31,
WARM 16, COLD 13, JUNK 1; `stage`: qualifying 67, new 30, lost 1).

Columns relevant to the website (types; defaults):

| Group | Columns |
|---|---|
| Identity / contact | `whatsapp_number` text (the phone, digits with 91), `alternate_phone`, `student_name`, `email_id`, `name_confirmed` bool, `email_confirmed` bool |
| **Verification** | `phone_verified_at` timestamptz, `phone_verification_method` text (Witty sets `whatsapp_inbound`; old OTP `sms_otp`), `email_verified_at` timestamptz |
| **Consent** | `consent_sales_at`, `consent_marketing_at`, `consent_partner_share_at` timestamptz, `consent_text_version` text; `is_opted_out` bool NOT NULL false, `opted_out_at`, `opted_out_channels` text[] |
| **Source / attribution** | `lead_source`, `channel`, `source_detail`, `campaign`, `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term`, `click_ids` jsonb, `landing_url`, `referrer_url`, `first_touch_at`, `last_touch_at`, `last_touch_source`, `publisher_id` bigint |
| **Referral / creator** | `referral_code` (influencer code; RLS policy for influencers uses it), `referred_by_code`, `activation_code` (Witty access code) |
| Agent | `first_agent_channel`, `web_session_id` text, `chatwoot_conversation_id`, `is_bot_paused`, `last_agent_message_at` |
| Device / abuse | `ip_address`, `device`, `fingerprint` (no junk-score column; `is_duplicate_suspect`, `duplicate_claim_count` exist; JUNK is a `lead_status` value) |
| Qualification (Witty fields) | `interested_course`, `interested_specialization`, `field_of_interest`, `interested_university`, `university_preference`, `program_level`, `study_mode_preference`, `highest_qualification`, `current_study`, `academic_percentage_gpa` (raw) / `academic_score_pct` numeric(5,2), `work_experience_years` (raw) / `work_experience_years_num` numeric(4,1), `current_job_role`, `annual_budget` (raw) / `annual_budget_inr` numeric(12,2), `enrollment_timeline`, `primary_motivation`, `preferred_counseling_time`, `preferred_language`, `city`, `state`, `country` default 'India', `current_city_country`, `enquirer_relation`, `guardian_name`, `guardian_phone`, `programme_segment`, `"Comments"` |
| **Classification** | `lead_status` default 'UNQUALIFIED' (HOT/WARM/COLD/UNQUALIFIED/JUNK/PROGRAM_MISMATCH), `lead_classification`, `temperature` (CHECK hot/warm/cold), `admission_readiness`, `eligibility_status`, `lead_stage` (Witty conversation phase), `intent_type`, `extraction_confidence`, `lead_score` |
| Pipeline (CRMs own these) | `stage`, `sub_stage`, `stage_changed_at`, `is_sales_ready`, `sales_ready_at`, `owner_user_id`, `destination_type` (CHECK in_house/partner), `partner_id`, `allocation_id`, application_*/enrollment_*/fee_* , `cycle_no`, `lost_*`, `merged_into_id`, `deleted_at`, `anonymised_at`, `is_test`, `custom_fields` jsonb, `updated_by` |

There is **no** dedicated `phone_verified` / `email_verified` boolean, junk-risk score, `consent_version` (it is
`consent_text_version`), creator-code column other than `referral_code` / `referred_by_code`, or application-request flag.

Triggers: `student_leads_touch_trg` (BEFORE UPDATE, sets `updated_at`), `student_leads_bulk_delete_guard` (AFTER DELETE,
>5 rows blocked), `student_leads_truncate_guard`, `crm_auto_assign` (**disabled**).
RLS: policies only for `authenticated` (influencer by `referral_code = current_referral_code()`, CRM staff via `crm_can_see`).
anon has no SELECT grant.

---

## 3. `lead_intake()` and the approved write / enrichment path

### 3.1 Signature, security, grants
```
public.lead_intake(p jsonb) RETURNS jsonb   -- the only overload
LANGUAGE plpgsql  SECURITY DEFINER  SET search_path TO 'public'
ACL {postgres=X/postgres, service_role=X/postgres}   -- anon: no, authenticated: no, service_role: yes
```
Depends on `crm_norm_phone`, `crm_find_lead`, `w2_is_test`, `w2_crm_owned` (all in `leads.sql`).

### 3.2 Input contract
```json
{ "phone": "required; digits after crm_norm_phone, >= 10 (10-digit → 91 prefix)",
  "source_system": "default 'api'; trusted: 'witty' | 'web_agent' | 'crm'",
  "event_type": "default 'lead.updated' (seen: lead.created, lead.qualified, lead.verified, lead.edited, lead.interest, chat.turn, classification_changed, lead.escalated)",
  "lead": { "...fields..." }, "attribution": {}, "idempotency_key": "unique in touchpoints", "occurred_at": "timestamptz", "is_test": false }
```
`lead` keys are mapped (`full_name→student_name`, `email→email_id`, `source→lead_source`, `classification→lead_status`,
`classification_ai→lead_classification`, `readiness→admission_readiness`, `eligibility→eligibility_status`,
`conversation_phase→lead_stage`, `programme_level→program_level`, `academic_score_raw→academic_percentage_gpa`,
`work_experience_raw→work_experience_years`, `annual_budget_raw→annual_budget`, `location_raw→current_city_country`,
`preferred_call_time→preferred_counseling_time`, `access_code→activation_code`, `device_type→device`,
`device_fingerprint→fingerprint`, `notes→Comments`, `is_name_confirmed`, `is_email_confirmed`) and then filtered by an
allow-list of 70 columns (all qualification, attribution, consent and agent columns in §2, including `web_session_id`,
`referral_code`, `referred_by_code`, `first_agent_channel`). **Anything else is silently dropped**, notably
`email_verified_at`, `phone_verified_at`, `temperature`, `stage`, `custom_fields`, `is_test` (inside `lead`), and Witty's
`final_program_id` / `final_program_name` / `programs_shown`. `is_opted_out` is read separately (can only turn on).

### 3.3 Duplicate detection and merge rules
- Key: **phone only** — `crm_find_lead(phone)`: digits of `whatsapp_number` equal, `deleted_at IS NULL`,
  `merged_into_id IS NULL`, newest first. **Email is never used**; a returning visitor with the same email but a different
  phone creates a second lead.
- New phone → insert (`stage 'new'`, `country 'India'`, `is_test` from `p.is_test` or `w2_is_test`, `updated_by =
  source_system`; `phone_verified_at` only when `source_system = 'witty'`) → `action 'created'`, all fields written.
- Existing phone → `action 'merged'`; if the lead was `lost` or enrolled it is reopened (`stage 'qualifying'`,
  `cycle_no + 1` after 90 days or enrolment) → `action 'reopened'`.
- Field writes: for trusted systems (`witty`, `web_agent`, `crm`) or a new lead, non-first-touch fields are overwritten; for
  any other system they only fill blanks. **First-touch fields are never overwritten** (`lead_source`, `channel`,
  `source_detail`, `campaign`, all `utm_*`, `click_ids`, `landing_url`, `referrer_url`, `referral_code`,
  `referred_by_code`, `activation_code`, `ip_address`, `device`, `fingerprint`, all `consent_*`, `consent_text_version`,
  `first_agent_channel`). Consequence: if a Witty lead later consents on the website, the website's consent timestamp/version
  will **not** replace Witty's; record it in a `web_` consent ledger (and `b2b.lead_consents` via the B2B path) instead.
- `lead_status` HOT/WARM/COLD ⇒ `temperature` set, `is_sales_ready = true` (never reverts), `stage new → qualifying`
  (also when `interested_course` or `highest_qualification` arrives).
- Touchpoint inserted unless (merged AND `event_type = 'chat.turn'`) or `source_system = 'crm'`; `on conflict
  (idempotency_key) do nothing` (the lead update is not idempotent, only the touchpoint).

### 3.4 Output
`{ lead_id, action: 'created'|'merged'|'reopened', phone, stage, is_sales_ready, is_test, crm_owned }`.

### 3.5 Source values (what to send)
- `source_system` (touchpoints, trust): use **`web_agent`** for the website (advisor and forms). It is already trusted
  by `lead_intake`, recognised by `b2b.intake_lead`, `b2b.lead_interest_add`, `b2b.is_chat_lead`, `crm_score_lead__impl`
  ("form_filled" engagement), `b2c.apply_envelope` and the B2B UI label "Website agent".
- `lead.source` → `lead_source` (free text): **`website_agent`** for the advisor (it is the consent channel name in
  `b2b.consent_texts` and the default of `engine.require_verified_phone_sources`), and a form value for programme/enquiry
  forms. Forms: B2B docs map substrings `web|form|landing|site` to channel `web_form`; suggest `lead_source = 'website_form'`
  and `channel = 'web_form'`. `w2_sources` also has slug `website` (channel website) and `crm_verify_check` defaults
  `lead_source` to `website`. Pick one per surface and record it in `DECISIONS.md`. Witty uses `whatsapp_direct` / `organic` /
  `legacy` / `test_harness`.
- `lead.channel`: Witty sends `whatsapp`; the website should send `web` (advisor) / `web_form` (forms).
  `first_agent_channel`: `web` for advisor leads.

### 3.6 Known callers and wrappers
- Witty: `w2_commit_turn` (each gated turn: `w2_crm_payload(...)` → `lead_intake`, failures queued in `w2_outbox`,
  retried by `w2_outbox_retry`), `w2_try_claim`.
- Old CRM: `crm_new_lead`, `crm_update_lead(p_id, p)` (source_system `crm`, requires a CRM role, authenticated),
  `crm_journey_tick`, **`crm_verify_check`** (see 3.7).
- B2B CRM: `b2b.intake_lead(p_lead, p_opts)` (SECURITY DEFINER, service_role) behind `b2b.api_intake_lead(p_key,
  p_idempotency_key, p_body)` = `POST https://crm.eduwit.in/v1/leads` (body keys `lead, source, channel, campaign, utm,
  click_ids, landing_url, consent, phone_verified, occurred_at, route, b2c_lane`; lead fields from `b2b.import_fields()`).
  It always calls `lead_intake` with **`source_system = 'api'` (untrusted: fills blanks only)**, writes the consent ledger
  (`b2b.lead_consents`) and warnings (consent version not registered / does not cover partners), adds secondary interests,
  and sets `b2b.intake_directives.phone_trusted` when `phone_verified = true`. It does not accept `email_verified`,
  `web_session_id`, `referred_by_code` or `referrer_url`. The B2B handover (`docs/HANDOVER.md` §5, `go-live-setup.md` §7.4)
  says website **forms** should use this API.
- Also: `b2b.lead_edit`, `b2b.apply_partner_fields`, `b2b.import_process`, `b2b.b2ccrm_event_ingest`, `b2b.consent_answer`.

### 3.7 Existing website verification flow (old CRM)
`crm_verify_start(p jsonb)` / `crm_verify_check(p_id, p_code, p jsonb)` (SECURITY DEFINER, **service_role only**,
table `public.verifications`, settings `crm_settings.comms.otp` = 10-min TTL, **3** attempts, 30 s resend, 3 codes per target
per hour, 10 per IP per hour; SHA-256 of `target:code`). `crm_verify_start` returns the plain code to the caller (the caller
sends it). Kind `phone` → `lead_intake(source_system 'web_agent', event 'lead.verified', lead_source default 'website')` +
`phone_verified_at`. Kind `email` → **does not create a lead**; it only stamps `email_verified_at` + `email_confirmed` on the
lead found by `context.phone` (or `context.lead_id`). This is the only existing code path that sets `email_verified_at`.

### 3.8 The approved path for enriching an existing lead
There is no separate "update lead fields" function for agents: **enrichment = calling `lead_intake` again with the same
phone**. Witty does exactly that every turn (`w2_crm_payload` builds the full profile; `event_type 'chat.turn'` merges
without a touchpoint; qualification events such as `lead.qualified` / `classification_changed` add one). For the website:
- Advisor turns and form steps 2–4: `lead_intake({source_system:'web_agent', event_type:'chat.turn' | 'lead.updated',
  phone, lead:{...}, idempotency_key})` from the server (service role), same as Witty. Being trusted, `web_agent` overwrites
  qualification fields (so the website can also overwrite fresher Witty data — acceptable, same as Witty-vs-CRM today).
- Fields with no column (e.g. application request, preferred intake, EMI interest, contact mode, board/university, year of
  passing, chosen offering id) → `web_` table keyed to `lead_id`, or `custom_fields` only after approval (not in the
  allow-list).
- `email_verified_at` → needs either an approved addition to the `lead_intake` allow-list, or calling `crm_verify_check`
  (email) after the lead exists (which would mean creating the lead before the email is verified — conflicts with spec).
  Recommend: add `email_verified_at` (and a `web_agent` phone-verification method of `unverified`) to the allow-list via an
  approved shared migration; until then store the verification in `web_` and pass `is_email_confirmed: true`
  (`email_confirmed`), which `lead_intake` does accept.

### 3.9 Routing consequence of "no phone OTP"
`b2b.lead_class` adds `phone_not_verified` (class `unqualified`, not routed) for any lead whose `lead_source` is in
`b2b.settings.engine.require_verified_phone_sources` (production: `["website_agent","web_agent"]`), or that has a
`web_session_id`, or any touchpoint with `source_system = 'web_agent'`, while `phone_verified_at IS NULL` and no
`b2b.intake_directives.phone_trusted`. So **every website lead will sit unqualified in the B2B engine** under the current
setting. Options (all need owner approval, list in `APPROVALS_NEEDED.md`): change the setting to `[]` (B2B admin UI,
Routing → engine), treat email verification as sufficient by writing an intake directive with `phone_trusted` (only
possible through `b2b.intake_lead` / Intake API `phone_verified: true`, which would be untruthful), or turn on phone OTP.
Witty leads are unaffected (their `phone_verified_at` is set on creation).

### 3.10 `public.touchpoints`
`id bigint, lead_id bigint NOT NULL FK → student_leads ON DELETE CASCADE, phone text NOT NULL, source_system text NOT NULL,
event_type text NOT NULL, source text, campaign text, attribution jsonb NOT NULL '{}', idempotency_key text UNIQUE, payload
jsonb (the raw lead object), occurred_at, created_at`. 3 rows (witty: lead.created 2, lead.qualified 1); backup adds
lead.updated, chat.turn, classification_changed, lead.escalated. Written only by `lead_intake`.

---

## 4. Agent messages: `public.w2_messages` and `public.w2_conversations`

### 4.1 `w2_messages` (168 rows: in 84, out 84)
```
id bigint PK   phone text NOT NULL   direction text NOT NULL   kind text NOT NULL default 'chat'   message_id text
run_id text    content text          answer_mode text          reply_source text   model text
prompt_tokens int  cached_tokens int  output_tokens int  latency_ms int  verify_errors jsonb  sent boolean  meta jsonb
created_at timestamptz NOT NULL default now()
unique (message_id) WHERE direction = 'in'; indexes (phone, created_at), (created_at)
```
- Distinct values: `direction` in/out; `kind` chat 84, reply 79, gate 4, nurture 1; `answer_mode` DIRECTIONAL 21, PROGRAMS 20,
  ACK 16, ANSWER 9, NO_MATCH 7, GATE 4, GREETING 4, HANDOFF 1, CLOSE 1 (null on inbound); `reply_source` counselor 71,
  fixed 10, fallback 3; `model` "gemini-3.6-flash + gemini-3.6-flash" 74, "gemini-3.6-flash" 9.
- `meta` keys: inbound `conversation_id`, `content_type`, `has_attachment`, `referral`; outbound `prompt_source`,
  `knowledge`, `catalog_cached`; nurture `step`, `template`.
- **No channel column, no lead_id, no session/conversation id column, no tool-call columns.** Tool calls/results are not
  stored per message (Witty logs extracted facts in `w2_fact_log` and turn payloads in `w2_events`).
- Writers: `w2_inbox_add(p)` (inbound, from the Chatwoot webhook via n8n; dedups on `message_id` through `w2_inbox`),
  `w2_commit_turn(p)` (outbound reply, `p.log` → one row; same transaction updates `w2_conversations`, `w2_fact_log`,
  `w2_events`, and syncs the lead through `lead_intake`), `w2_nurture_done(p)` (kind 'nurture'). All SECURITY INVOKER,
  called by n8n with the service role.
- Readers: B2C CRM `b2c.witty_messages(p_lead, p_limit)` / `witty_transcript` / `may_market` / `witty_busy` (they join by
  phone), B2B `lead_detail`, `student_last_inbound`, `reenquiry_scan`, old CRM `crm_timeline__impl`, `crm_whatsapp_window__impl`
  (24-hour WhatsApp window!), `crm_marketing_allowed`, `crm_score_lead__impl`, Witty health/learning digests and test harness.
  **Caution:** web rows keyed by the same phone would appear in these readers and could be mistaken for WhatsApp activity
  (e.g. opening the WhatsApp 24-hour window, "witty_busy"); a channel marker is required before the website writes here.

### 4.2 `w2_conversations` (16 rows; PK `phone`)
Columns: `phone, conversation_id (Chatwoot), account_id, state jsonb, classification (UNQUALIFIED 11, WARM 3, HOT 1,
PROGRAM_MISMATCH 1), readiness (PLANNING 9, EXPLORING 5, READY_NOW 2), eligibility, pending_question, bot_paused, opted_out,
consent_at, escalated_at, lead_source (test_harness 12, whatsapp_direct 2), activation_code, crm_record_id (= lead id as
text), version, lock_id, lock_until, access_code, access_at, attribution jsonb, last_student_at, nurture_step,
nurture_next_at, created_at, updated_at`. One conversation per phone, forever; relation to messages and leads is by phone
(`crm_record_id` holds the lead id after the first CRM sync). `state` holds the whole agent memory (profile with
value/status per field, phase, flags.shown_rows, recent_turns, enquirer, consent, attribution …).

### 4.3 Related Witty tables
`w2_inbox` (raw inbound), `w2_outbox` (CRM sync retries), `w2_events`, `w2_fact_log`, `w2_feedback` (rating per `phone` +
`run_id`, `source` default 'counselor'; 0 rows — usable for web thumbs up/down with `source = 'web'`), `w2_prompts`
(`name, version, body` — 2 rows: Witty's prompts are already a versioned table), `w2_meta` (`lessons_version`,
`bot_rules`, `catalog_version`), `w2_sources` (slugs: whatsapp_direct, legacy, shared, **website**, organic),
`w2_access_codes` / `w2_clicks` (website "get a WhatsApp code" funnel via `w2_register_lead`), `w2_learnings`,
`w2_kb_docs/chunks`, `w2_search_cache`, `w2_test_runs`.

### 4.4 What the website needs approved to use the shared table "in its existing format"
Minimum, zero-DDL option: write web rows with `phone` = verified lead's phone, `direction`, `kind` ('chat' in / 'reply'
out), `run_id`, `content`, `model`, token counts, `latency_ms`, and `meta = {"channel":"web","web_session_id":…,
"lead_id":…,"tool_calls":[…]}`; use a `message_id` like `web:<uuid>` for inbound uniqueness. Still needs approval because
of the reader side effects above. Cleaner option (shared migration, approval): add nullable `channel text default
'whatsapp'`, `lead_id bigint`, `session_id text`, `tool_calls jsonb` to `w2_messages`, and teach the WhatsApp-window /
busy readers to filter `channel = 'whatsapp'`. Do not create rows in `w2_conversations` for web sessions without approval
(Witty's lease/nurture logic scans it); keep web session state in `web_` tables.

---

## 5. Extensions and migration history

**Installed** (`list_extensions`): plpgsql 1.0, pgcrypto 1.3 (extensions), uuid-ossp 1.1 (extensions), pg_stat_statements
1.11 (extensions), supabase_vault 0.3.1 (vault), **pg_trgm 1.6 (public)**, **vector 0.8.0 (public)**, **pg_cron 1.6.4**,
**pg_net 0.20.3** (extensions), **pgmq 1.5.1** (pgmq).
**Available but not installed:** unaccent, pg_graphql, citext, fuzzystrmatch, pg_jsonschema, hypopg, index_advisor,
pgroonga, rum, btree_gin/gist, http, pg_partman, etc. (The website's search must not depend on `unaccent` unless installing it
is approved; trigram + `simple` tsvector is what Witty uses.)

pg_cron jobs touching leads: `b2b-route-ready-leads` every minute (`select b2b.route_ready_leads(25)`).

**Migration history** (`supabase_migrations.schema_migrations`, 229 entries):
- No baseline entry: the original Witty/old-CRM/influencer schema predates tracking (B2B repo has
  `00000000000000_baseline.sql` as a file only).
- `20261006095337 disable_crm_auto_assign`, `close_influencer_exposure`, then B2B CRM `m1_…` → `m23b_…` (6–7 Oct),
  `w1_witty_addendum3`, `m24a…m31p` (8 Oct, 17-digit versions), `w2_witty_b2c` (14 Oct), B2C CRM "Spark" `b1_access_part0`
  … `b38_guides_features_part0` + `phase3_ledger_guards` (15 Oct), `m32a…m33f` (15 Oct), `spark_b44/b45` (15–16 Oct),
  Witty `w3_witty_soft_gate_a…e`, `w3_witty_extractor_prompt_v6`, `w3_witty_health_digest`, `w3_witty_send_failed`,
  `w3b_search_programs_emi_fields`, `w3b_nurture_due_context`, latest **`20261016124923 spark_b46_health_timer_calls`**.
- Naming: `m<N><letter>_…` B2B CRM, `b<N>_…_part<k>` / `spark_b<N>_…` B2C CRM, `w<N>_witty_…` Witty. Suggested for the
  website: `web<N>_…` (and nothing applied to production before go-live).

---

## 6. RLS and grant posture (public read access)

- `catalog_universities`, `catalog_programs`: RLS on; anon and authenticated hold **full** table privileges (SELECT, INSERT,
  UPDATE, DELETE, TRUNCATE…), only policy `crm_staff_select` (SELECT to authenticated where `crm_role() IS NOT NULL`).
  ⇒ anon reads nothing; non-CRM authenticated users read nothing. (TRUNCATE is not governed by RLS: anon/authenticated
  holding TRUNCATE on these tables is a latent risk worth flagging to the owner.)
- `catalog_synonyms`, `catalog_stage`, `course_directory`, `eduwit_knowledge_base`, all `w2_*`: RLS on, **no policies**,
  full grants to anon/authenticated ⇒ service_role only (same TRUNCATE caveat).
- Schema `catalog`: USAGE only for `b2c_app` and `service_role`; views granted to them only. Views are plain (owner
  `postgres`, not `security_invoker`) so they bypass base-table RLS — fine for service-role use, unsuitable to expose.
- `student_leads`, `touchpoints`: no anon SELECT; authenticated policies for influencers/CRM staff only.
- Many `w2_*` and `catalog_*` loader functions are EXECUTE-able by PUBLIC/anon but are SECURITY INVOKER, so RLS blocks
  anon. `crm_norm_phone`, `crm_mask_phone` are harmless. `influencer_dashboard_leads(p_referral_code, p_password)` and
  `b2b.api_*` are anon-executable SECURITY DEFINER endpoints guarded by their own key/password checks.
- PostgREST exposed schemas are not readable from SQL here; the B2B migration `m14c_anon_schema_usage` granted anon USAGE on
  `b2b` for its key-checked API functions.
- Advisor: `b2b.witty_backup_20261015` and `b2b.witty_backup_20261016` have RLS **disabled**; they currently carry no
  anon/authenticated table grants, so they are not readable through the API, but they should get RLS enabled (or be dropped)
  by their owner. Remediation SQL (not run): `ALTER TABLE b2b.witty_backup_20261015 ENABLE ROW LEVEL SECURITY; ALTER TABLE
  b2b.witty_backup_20261016 ENABLE ROW LEVEL SECURITY;`
- **No view intended for public reads exists.** The website needs new `web_` read objects (e.g. `web_offerings_v` or RPCs
  returning only public columns: no `partner_*`, no `commission`, no `offered_by_partner_count` if considered
  commercial), served from the website server with the service role, or granted to anon with explicit column lists after
  approval.

---

## 7. Auth

`auth.users`: 4 users, all email-confirmed, none with a phone, none anonymous; last sign-in 16 Oct 2026. `auth.identities`:
google 4, email 2. These are staff (B2B/B2C CRMs use Google + email codes / TOTP). No student accounts exist; the website's
Supabase Auth email-OTP users would be the first student users in this project's `auth.users`, which the CRMs'
`crm_role()` / `b2b.app_users` / `b2c.users` checks already exclude. Confirm with the owner that student sign-ups in the
shared `auth.users` are acceptable (e.g. CRM login pages must not let a student account in; they check allowlists).

---

## 8. Answers to spec Section 18 questions 1, 2, 3

**Q1. Exact `catalog_*` structure and how Witty and the CRMs use it. Can a shared taxonomy layer be added?**
Three tables: `catalog_universities` (29: name, short_name, institution_type, recognitions[], accreditation_text blob),
`catalog_programs` (715 flat rows: level, course/course_key, specialization, program_name, mode, five fee columns +
`fee_other` jsonb incl. `Emi`, min_qualification/percentages, eligibility_text, brochure_url, flags, program_key), and
`catalog_synonyms` (32 course aliases), plus loader staging `catalog_stage`. No duration, intake, logo, state, structured
approval, NAAC/NIRF or verification-date fields. Witty loads it from a master sheet and queries it with
`w2_search_programs` / `w2_catalog_index`; the B2B CRM matches partner price sheets to it and publishes the read-only
`catalog` schema views; the B2C CRM caches `catalog.programmes_v` into `b2c.programme_cache`. A shared taxonomy layer can be
added additively beside it (keyed on `catalog_programs.id` + `program_key`); build it as `web_` tables now and propose
promotion (and Witty/B2B adoption) in `APPROVALS_NEEDED.md`. Data needs heavy normalisation (§1.6).

**Q2. Exact `student_leads` columns (phone-verified / email-verified flag?), `lead_intake()` signature and duplicate
logic, and the value for `source`.**
150 columns (§2). Verification is timestamp-based: `phone_verified_at` + `phone_verification_method`, `email_verified_at`
(+ boolean `email_confirmed`); consent is `consent_sales_at` / `consent_partner_share_at` / `consent_marketing_at` +
`consent_text_version`. Signature `public.lead_intake(p jsonb) RETURNS jsonb`, SECURITY DEFINER, service_role-only; input
`{phone, source_system, event_type, lead{}, attribution{}, idempotency_key, occurred_at, is_test}`; output
`{lead_id, action, phone, stage, is_sales_ready, is_test, crm_owned}`. Duplicates: phone only (digits match, not
deleted/merged, newest); existing phone ⇒ merge (trusted sources overwrite, others fill blanks; first-touch attribution and
consent never overwritten); lost/enrolled ⇒ reopen. Use `source_system = 'web_agent'` and `lead.source =
'website_agent'` for the advisor (forms: `website_form` / channel `web_form`, to confirm). `lead_intake` cannot set
`email_verified_at` or mark the phone unverified explicitly (unverified = `phone_verified_at IS NULL`); and with the current
B2B setting web leads without a verified phone are held as `phone_not_verified`. Both need approval (§3.8, §3.9).

**Q3. The messages table name and schema, and how Witty writes to it.**
`public.w2_messages` (§4.1) with per-phone state in `public.w2_conversations` (§4.2). Witty (n8n) writes inbound messages
through `w2_inbox_add(p jsonb)` (Chatwoot webhook → `w2_inbox` dedup → `w2_messages` direction 'in', kind 'chat') and each
outbound reply through `w2_commit_turn(p jsonb)` (`p.log` → `w2_messages` direction 'out', with answer_mode, reply_source,
model, token counts, latency, verify_errors, meta; same transaction updates conversation state, fact log, events and calls
`lead_intake` via `w2_crm_payload`); nurture messages via `w2_nurture_done`. The table has no channel, lead_id, session or
tool-call columns; a web channel can only be marked in `meta` today, and several CRM readers would treat web rows as
WhatsApp activity, so writing web messages needs an approved channel marker (§4.4).
