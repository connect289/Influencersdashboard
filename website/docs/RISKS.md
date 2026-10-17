# Risks

Likelihood (L) and impact (I): H / M / L. Owner-facing mitigations; the full technical detail is in the linked docs.

| # | Risk | L | I | Mitigation |
|---|---|---|---|---|
| R-01 | **Breaking a live product** (Witty, B2B CRM, Spark, Influencer Portal) through a shared-object change | M | H | `web_` prefix, additive-only migrations, shared changes isolated in `supabase/migrations-shared/` and listed in `APPROVALS_NEEDED.md`; every website migration is tested on the full production-schema replica (`prod-replica`) before go-live; go-live dry run (Phase 12). |
| R-02 | **Students mixed into the shared Auth** would create rows in `crm_users` via trigger `crm_on_auth_user_created` and require project-wide OTP changes | H (if Supabase Auth used) | H | Website-owned student verification (D-005). |
| R-03 | **Legacy content not migrated** because the current site is blocked from the build environment | H | M | Crawler ready; content blocks marked "Pending migration"; go-live checklist blocks launch until the crawl is imported and legal pages are verified verbatim (S-01). |
| R-04 | **Catalogue data quality** (missing fees/eligibility/approvals, naming variants) makes the finder look wrong | H | H | Taxonomy mapping layer, unmapped rows hidden but reported, missing fields never shown as guesses, data-quality dashboard in admin, "last verified" dates. See `TAXONOMY_PROPOSAL.md`. |
| R-05 | **Lead source rules**: the B2B engine treats `website_agent`/`web_agent` as sources that require an OTP-verified phone, but the owner decided no phone OTP at launch | H | H | See `SCHEMA_PLAN.md` §Leads and `APPROVALS_NEEDED.md`; the website sends `phone_verified=false` honestly and the owner decides the engine setting. |
| R-06 | **Partner-share consent** only counts if the website's consent text version is registered in `b2b.consent_texts` with lawyer approval | H | H | Consent text versions held in `web_consent_texts`; registration in `b2b.consent_texts` listed in `APPROVALS_NEEDED.md`; lawyer review S-44. |
| R-07 | **Witty divergence**: the website agent answers differently from WhatsApp Witty | M | H | Shared, versioned agent core (`AGENT_ARCHITECTURE.md`); same prompts and catalogue functions; contract tests comparing classification outputs. |
| R-08 | **AI cost or latency spikes** during ad campaigns | M | M | Prompt caching, per-session token budget, per-turn timeout, rate limits, circuit breaker → guided finder + form; cost metrics in admin. |
| R-09 | **Performance regressions** from the futuristic design on mid-range Android | M | H | Capability tiers, static-first HTML, shaders after first paint, budgets enforced by Lighthouse CI. |
| R-10 | **Commercial data leak** (partner commission via `catalog.partner_rates_v` or `offered_by_partner_count`) | L | H | The website never reads `partner_rates_v`; read model built from an explicit column allow-list; CI test greps responses and page source for banned fields. |
| R-11 | **Abuse of the gate** (fake leads, email bombing) without phone OTP | M | M | Turnstile, per IP/device/email limits, disposable-email blocklist, honeypot, junk score, code-send caps. |
| R-12 | **DNS cut-over** from Hostinger breaks email (MX/SPF) or old URLs | L | H | DNS plan copies every existing record first; only A/CNAME for the web host change; 301 map tested in CI; rollback = restore records (TTL lowered 48 h before). |
| R-13 | **n8n workflow not visible** (connector down); Witty's live pipeline reconstructed from repo patches and prompts | M | M | S-02; agent contract tests written against the documented contract. |
| R-14 | **Upstream API not ready** (Influencer Portal creator API) | H | L | Typed interface with mock; creator pages fall back to code-only attribution. |
