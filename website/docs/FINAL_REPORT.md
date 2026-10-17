# eduwit.in — final build report (Phases 0–12)

**Status: built and verified locally; ready for your go-live decision. Nothing has been applied to production,
nothing deployed, no DNS changed.** Branch `claude/inspiring-babbage-8asj1y`, phases tagged `website-phase-0-done` …
`website-phase-12-done` (tags are in the build session's clone; the branch holds every commit).

## 1. What was built

| Phase | Outcome |
|---|---|
| 0 Discovery | Read-only study of production, the CRMs and Witty; schema plan, risks, approvals and setup lists |
| 1 Design | Design system, component library, style guide; two concepts built on real data — **Concept A (Luminous), confirmed by you**; Concept B kept and switchable (`design_concept`) |
| 2 Foundation | Next.js 16 app (React Server Components, cache components), security headers and CSP, settings and flags, observability, admin sign-in with an emailed second factor |
| 3 Catalogue | Website taxonomy over the shared catalogue (programmes, specialisations, levels, synonyms, goals), a read model refreshed only when the catalogue changes |
| 4 Finder | Programme finder: free-text and typo-tolerant search, facets, grouped and flat views, eligibility, shareable URLs; search 29–145 ms at 10,000 offerings |
| 5 Detail and universities | Detail panel and sheets with deep links, university pages, curated views, compare and shortlist, structured data |
| 6 Content | Home, about, how it works, contact, FAQs, guides framework, legal page shells, redirect map, popular searches |
| 7 Leads | Inline email verification; leads only through `lead_intake` (once, de-duplicated, with attribution and versioned consent); application and enquiry forms; student accounts; privacy requests |
| 8 Witty | Witty on the website end to end (gate, streamed replies with programme cards, storage, leads, feedback, callbacks, history) — **off** until Witty's engine is verified (A-AGENT-1) and a key is supplied (S-14) |
| 9 Technical SEO | Curated-only indexing, sitemaps by type, canonical rules, OG images, analytics events with server/browser de-duplication, performance budgets in CI |
| 10 Admin | Content editor for 15 content types, flags, funnels and Witty insights, data quality, taxonomy mapping, outbox monitor, privacy requests, audit log, roles |
| 11 SEO toolkit | Search Console dashboard, opportunity finder, keywords, content planner with grounded briefs/drafts and mandatory author + reviewer, on-page checker, internal links, 404 monitor, local SEO |
| Catalogue sync (after Phase 12) | The programme list follows the shared catalogue Witty and the CRMs use, whoever edits it: any change is on the website within ~2 minutes; brand-new courses alert super admins until mapped (D-081) |
| 12 Hardening | Security review and fixes, accessibility audit, load tests and database protection, production migration dry run with rollbacks, runbook, DNS plan, go-live checklist |

## 2. Test and quality results (final build, 17 Oct 2026)

| Check | Result |
|---|---|
| Typecheck, lint, copy check | clean |
| Unit tests (Vitest) | **187 passed** |
| SQL tests, fresh database and production-schema replica | **all 10 suites pass** (1,051 security checks + 273 functional checks) |
| Shared objects after applying the website's migrations | **unchanged** (every fingerprint row matches production) |
| Shared proposals (APPROVALS) | **7/7** apply, pass smoke tests, roll back to an identical state |
| Production migration dry run | **passed**: 1.24 s for all website migrations, no locks on shared tables, full rollback back to production's exact fingerprint |
| End-to-end (Playwright, laptop + Pixel 7) | **174 passed, 0 failed** (32 skipped by design: laptop-only flows on the phone project) |
| Accessibility (axe WCAG 2.1 AA, both themes, both devices) | **0 violations**; 2 keyboard-focus bugs found and fixed |
| Lighthouse CI (mobile, median of 3, 13 paths) | accessibility 1.00 and SEO 1.00 on every indexable page; LCP 1.67–1.84 s; CLS ≤ 0.067; performance 0.88–0.98. Total blocking time: the first full run was over the 300 ms budget on 3 paths (322–433 ms); a re-run of those pages passed (medians 215–285 ms) with single runs spread 172–487 ms on this noisy container — see `PERFORMANCE.md` |
| Load tests | 10k offerings ✔ · 1,000 visitors ✔ for ad-shaped traffic on one box (page views p95 10 ms) · 200 Witty conversations ✔ (800/800 turns) — production-like repeat recommended (S-55) |
| Security review | no high findings; 4 medium + 13 low → 16 fixed, 1 accepted; production dependencies: 0 vulnerabilities |

Details: `SECURITY_REVIEW.md`, `ACCESSIBILITY.md`, `LOAD_TESTS.md`, `GO_LIVE_DRY_RUN.md`, `PERFORMANCE.md`,
`PROGRESS.md` (every phase gate and self-review).

## 3. Design choice

Concept A (Luminous) — dark-first, aurora light, glass surfaces, amber accent — confirmed by you on 17 Oct. It follows
the visitor's light/dark setting (`default_theme`). To switch to Concept B (Prism): Admin → Flags and settings →
`design_concept = b` (no redeploy). Branch `concept-b` (local, not pushed) holds the Phase 1 state.

## 4. Decisions, approvals and setup

- **`DECISIONS.md`:** 80 decisions taken without you (D-001 … D-080), each with the reason and how to change it.
  Phase 12 added D-076 (accepted search-path finding), D-077 (rate limits never per instance), D-078 (staff sessions
  confined to `/admin`), D-079 (callback limits), D-080 (protecting the shared database under traffic spikes).
- **`APPROVALS_NEEDED.md`:** 14 items. **Two block go-live:** 🔴 A-B2B-1 (let email-verified website leads route —
  without it no website lead reaches a partner or the B2C team) and 🔴 A-CONSENT-1 (register the website consent texts
  in the B2B CRM, after the lawyer's review S-44). Every SQL item has a migration, a rollback and (where it changes
  behaviour) a smoke test; s02 must ship together with the CRM reader changes; s03 is for later.
- **`SETUP_CHECKLIST.md`:** accounts, keys and owner inputs (S-01 … S-55). The go-live subset is in
  `GO_LIVE_CHECKLIST.md`.

## 5. Known issues and limits

1. **Legal pages are empty placeholders and the redirect map is partial.** The current eduwit.in could not be reached
   from the build environment (S-01), so its legal texts, copy and full URL list were not migrated. Before go-live:
   paste the legal texts in Admin → Legal pages (with the S-44 additions), and either allow the crawl (S-01) or list
   the old URLs so the 301 map is complete.
2. **Interim copy** on home / about / how it works (S-48) and no testimonials published (S-49).
3. **Witty on the website is off** until A-AGENT-1 and S-14. Time to first token with the real models is unmeasured
   (p50 1.31 s with an 800 ms simulated model; the extractor call before the first token may push p95 past 1.5 s).
4. **Load at production scale is unverified.** On this 4-vCPU box hard loads of many different finder URLs saturate a
   single process; production spreads them over Vercel instances, and the shared database is the real limit. Fixes
   are in (connection cap, batched logging, shared remote cache, optional read replica); decide S-54 and run S-55
   before paid traffic.
5. **Search edge cases at 10k offerings:** zero-result searches 255–287 ms; a full read-model rebuild takes 39 s
   (concurrent, reads never wait). Fine at today's 715 offerings (2.9 s).
6. **Accessibility:** automated and keyboard checks pass; a manual screen-reader pass (NVDA, VoiceOver) is recommended.
7. **Dev tooling advisories:** 22 in Lighthouse CI and the lint config (development only; production 0).
8. **Incident during the build (D-065):** one Lighthouse run used `npx lhci`, which downloaded an unrelated public
   package named `lhci` instead of the project's tool. Its code was inspected afterwards: one `console.log`, no install
   scripts, no file or network access; it was deleted. Since then tools run only from the project's pinned binaries
   (`npm run lhci`, `npx --no`). Nothing else was affected.

## 6. Go-live steps (after your approval)

Full procedure: `RUNBOOK.md` §5–§7; tick list: `GO_LIVE_CHECKLIST.md`.

1. Approve go-live, A-B2B-1 and A-CONSENT-1; lawyer review (S-44); legal texts in the admin; supply the blocking
   setup items (Vercel, Supabase keys, secrets, email provider, Turnstile, Hostinger DNS access).
2. T-7: export the Hostinger DNS zone, lower TTLs, set up the Vercel project and domains.
3. T-1: refresh the production fingerprint and re-run `scripts/db/go-live-dry-run.sh`.
4. Go-live day: restore point → website migrations → approved shared changes (s07, s05, s01, s04) → deploy → smoke
   test on the Vercel URL → DNS (`@` and `www` only; email records untouched) → checks and 24-hour watch.
5. Rollback at any point in the first 14 days: DNS back to Hostinger in minutes; database rollback scripts ready.
