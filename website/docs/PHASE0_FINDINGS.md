# Phase 0 findings

Read-only discovery, 17 Oct 2026. Detailed reports: `docs/discovery/db.md` (production database),
`docs/discovery/witty.md` + `witty-prompts.md` (Witty's agent), `docs/discovery/crm-conventions.md` (CRM code),
`docs/discovery/replica.md` (production-schema replica). Nothing was written to production.

## 1. Headline findings
1. **The current site could not be crawled.** The build environment's network policy denies `eduwit.in`,
   `www.eduwit.in` and `horizons-cdn.hostinger.com` (CONNECT 403; WebFetch DNS failure; no search-engine copy). A real
   browser crawler is ready (`web/scripts/crawl-legacy-site.mjs`). Migrated copy is held as marked "Pending migration"
   placeholders and never invented (D-006, S-01). **Go-live is blocked on this crawl** (legal pages must be verbatim).
2. **The catalogue is a flat, Witty-owned sheet import**: 29 universities, 715 programmes (all active), 32 course
   synonyms. Fees are mostly present (629 totals); **duration, intakes, NAAC/NIRF, UGC-DEB, state, logo and a
   verification date are not structured** (approvals live in a prose blob). 277 specialisation strings need a canonical
   layer. → `TAXONOMY_PROPOSAL.md`.
3. **Leads:** `public.lead_intake(p jsonb)` is the only writer (service role only), de-duplicates **on phone only**, and
   trusts `source_system = 'web_agent'` (overwrite) — the website uses that (D-009). It **drops `email_verified_at`**
   (A-LEAD-1).
4. **🔴 Routing conflict:** the B2B engine setting `require_verified_phone_sources = ["website_agent","web_agent"]` holds
   every website lead without an OTP-verified phone as unqualified. With "no phone OTP at launch", **website leads would
   never be routed** until the owner changes that setting (A-B2B-1).
5. **🔴 Consent:** partner-share consent only counts in the B2B CRM if the website's consent text version is registered
   and lawyer-approved (A-CONSENT-1).
6. **Witty 2.0 is live** and is a deterministic pipeline (extractor LLM → JS engine → counselor LLM → verifier) on Gemini,
   with prompts in `w2_prompts`. The decision engine lives in n8n code that could not be read. The website implements
   Witty's published contract in a shareable package and ships the advisor **off** until it is verified against Witty's
   own code (D-012, A-AGENT-1).
7. **Shared messages table hazard:** `w2_messages` has no channel column and the CRMs compute the WhatsApp 24-hour window
   from it; writing web turns there would break WhatsApp sending rules. Web transcript goes to `web_advisor_messages`
   (same columns + channel) until A-AGENT-2/3 (D-010).
8. **Shared Auth hazard:** a trigger copies every new `auth.users` row into `crm_users`; Auth OTP settings are
   project-wide. Students are verified by the website itself (D-005).
9. **Extensions:** `pg_trgm`, `pg_cron`, `pg_net`, `pgmq`, `vector` are installed; **`unaccent` is not** (A-EXT-1,
   fallback `web_normalise`).
10. **CRM conventions** (Next 16, TS 5.9 strict, `bom1`, service-role RPC, `SECURITY DEFINER` + `search_path=''`,
    SQL tests in `begin…rollback`, email-code 2FA for staff) are followed by the website (D-003, D-004).
11. **Security observations outside scope** (TRUNCATE grants on `catalog_*`/`w2_*` to anon/authenticated; RLS off on two
    B2B backup tables) are reported in `APPROVALS_NEEDED.md` for their owners; nothing was changed.

## 2. Content inventory (current site)
| Item (spec §1) | Status |
|---|---|
| Hero copy, stats, course offerings, "bridge between students and universities" section | Pending crawl |
| Services: Educational Counselling · Course Discovery & Comparison · Application & Enrollment Support | Names known from the spec; descriptions pending crawl |
| Testimonials | Pending crawl |
| Contact details | Known from the spec: 267-F3, Neeti Khand-1, Indirapuram, Ghaziabad, UP 201014 · +91-9650683269 · connect@eduwit.in · GST 09BXLPJ7928K1ZP |
| Consent text on the contact form | Pending crawl (the gate/form texts are drafted in `docs/legal/consent-texts.md` for lawyer review) |
| About page | Pending crawl |
| Six legal pages (`/legal/terms-and-conditions`, `/privacy-policy`, `/disclaimer`, `/refund-policy`, `/cookie-policy`, `/data-privacy-opt-out`) | URLs reserved and identical; bodies pending verbatim crawl |
| Logo | Supplied by the owner (17 Oct); SVG trace produced (`web/public/brand/eduwit-logo.svg`, mark, wordmark, dark variant) — confirm (S-40) |
| Every URL | `docs/URL_REDIRECT_MAP.md` (partial until the crawl) |

## 3. University pages — keep or drop? (spec 6.6)
University-level data is **sufficient** for genuinely useful pages: name, type, recognitions, UGC-DEB statement (25/29),
NAAC grade (28/29), stated rankings, and the full list of the university's offerings with fees in the finder format.
Editorial "about" text and state come from the admin (`web_university_profiles`), logos only with permission.
**Recommendation: keep `/universities/[slug]`.** Universities whose approvals are "Not Stated in Source" show no approval
claim, only what is stated.

## 4. Answers to spec Section 18 open questions
| # | Question | Answer (source) |
|---|---|---|
| 1 | `catalog_*` structure, how Witty and the CRMs use it, can a shared taxonomy be added? | Three tables + loader staging (db.md §1). Witty loads and searches it (`w2_search_programs`); B2B matches partner sheets and publishes `catalog.*` views; B2C caches those views. A shared taxonomy can be added **additively** keyed on `catalog_programs.id` + `program_key`; built now as `web_tax_*`, promotion = A-TAX-1. |
| 2 | `student_leads` columns, verified flags, `lead_intake()` signature and duplicate logic, `source` value | 150 columns; `phone_verified_at`/`phone_verification_method`, `email_verified_at` + `email_confirmed`, `consent_*_at` + `consent_text_version`. `lead_intake(p jsonb) → jsonb`, service role only; merge on phone; trusted sources overwrite, first-touch fields never. Use `source_system='web_agent'`; `lead_source='website_agent'` (Witty gate) / `'website_form'` (forms); channel `web` / `web_form` (D-009). Unverified phone = `phone_verified_at` null (no flag needed). |
| 3 | Messages table name/schema, how Witty writes | `public.w2_messages` (+ state in `w2_conversations`, keyed by phone). Written by `w2_inbox_add` (in) and `w2_commit_turn` (out). No channel/lead/session/tool columns (db.md §4, witty.md §7). |
| 4 | Witty's implementation and Witty 2.0 status; best way to share the core | Witty 2.0 is live (n8n pipeline, Gemini, `w2_prompts` v6). Share: prompts by reference, same SQL tools, same lead payload via `lead_intake`, decision engine as a shared versioned package (`AGENT_ARCHITECTURE.md`). |
| 5 | Transactional email provider | Not configured for the website. **Assumption:** SMTP through the Google Workspace relay already used by the B2C CRM, sender `no-reply@eduwit.in` (SPF/DKIM/DMARC to confirm); Resend adapter also built. Mailpit locally (S-12, D-017). |
| 6 | Which university logos may be used | Unknown. `logo_permitted` defaults to **false** for every university → text fallback until the owner confirms (S-41). |
| 7 | Vector/high-resolution logo | Owner supplied a 1264×1264 JPG; an SVG trace was produced and is used (S-40). |
| 8 | WhatsApp number for "Talk to a counsellor" | **Assumption:** Witty's number +91 96439 77407 with a pre-filled message ("Hi, I'd like to talk to a counsellor about …"); Witty's engine already treats that as an `asks_human` intent and hands off. Configurable in `web_settings.counsellor_whatsapp` (S-42, D-016). |
| 9 | Influencer Portal public creator API | Not specified anywhere in the repo. Built against a typed `CreatorProfileProvider` with a mock; the creator code is always attached to the lead (`referred_by_code`) and never gates access (S-43, D-018). |
