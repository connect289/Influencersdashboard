# Setup checklist — credentials, accounts and owner inputs

Everything the website needs that the build could not get by itself. Until each item is supplied, the site runs on a
mock adapter for it and keeps working. Env var names are exactly as read by `web/lib/server/env.ts`.

Status: ☐ needed · ◐ partly · ☑ done

## Access for the build environment
| # | Item | Why | Status |
|---|---|---|---|
| S-01 | Allow `eduwit.in`, `www.eduwit.in`, `horizons-cdn.hostinger.com` in the cloud environment's Network access (Allowed domains) | Crawl the current site to migrate its copy, legal pages, testimonials, images and every URL (D-006). **Go-live blocker:** the six legal pages are migrated verbatim from this crawl (`scripts/crawl-legacy-site.mjs` → `scripts/import-legacy.mjs` → review `supabase/seed-legacy.sql`) | ☐ |
| S-02 | Witty n8n workflow export (JSON) or n8n API access (the n8n connector failed to connect) | Confirm the live agent pipeline exactly; today it is reconstructed from `b2b-crm/witty/patch_nodes.py`, docs and `w2_prompts` | ☐ |

## Accounts and keys
| # | Item | Env vars | Mock until then | Status |
|---|---|---|---|---|
| S-10 | Vercel project (root dir `website/web`, region `bom1`) | — | local only | ☐ |
| S-11 | Supabase service-role key for production (set only at go-live) | `SUPABASE_SECRET_KEY`, `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | local stack | ☐ |
| S-12 | Transactional email provider for verification codes and confirmations (sender e.g. `no-reply@eduwit.in`, SPF/DKIM/DMARC) | `EMAIL_PROVIDER` (`smtp`/`resend`), `EMAIL_SMTP_HOST`, `EMAIL_SMTP_PORT`, `EMAIL_SMTP_USER`, `EMAIL_SMTP_PASSWORD`, `EMAIL_FROM`, `RESEND_API_KEY` | Mailpit locally; console log otherwise | ☐ |
| S-13 | Cloudflare Turnstile site key and secret (production refuses test keys, D-050) | `NEXT_PUBLIC_TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY` | Turnstile test keys (evaluated locally) | ☐ |
| S-14 | Anthropic API key for Witty on the website (models set in `web_settings.web_advisor_models`); optional `WEB_ANTHROPIC_BASE_URL`; `WEB_ADVISOR_PROVIDER=mock` forces the scripted provider outside production | `ANTHROPIC_API_KEY` | scripted provider (same JSON contracts; D-059) | ☐ |
| S-15 | Upstash Redis (rate limits, code attempt counters, hot search cache) | `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` | in-memory store | ☐ |
| S-16 | GA4 measurement ID | `NEXT_PUBLIC_GA4_ID` | not loaded | ☐ |
| S-17 | Meta Pixel ID and Conversions API token (+ test event code for staging) | `NEXT_PUBLIC_META_PIXEL_ID`, `META_CAPI_TOKEN`, `META_CAPI_TEST_CODE` | events logged to `web_outbox` only | ☐ |
| S-18 | Microsoft Clarity project ID (optional) | `NEXT_PUBLIC_CLARITY_ID` | not loaded | ☐ |
| S-19 | Sentry DSN | `SENTRY_DSN`, `NEXT_PUBLIC_SENTRY_DSN` | console | ☐ |
| S-20 | Google Search Console access (service account added as a user on the eduwit.in property, or owner OAuth) | `GSC_SA_EMAIL`, `GSC_SA_PRIVATE_KEY`, `GSC_SITE_URL` | sample data | ☐ |
| S-21 | Google OAuth client for admin sign-in (Supabase Auth Google provider; already used by the CRMs) | Supabase dashboard | email sign-in | ☐ |
| S-22 | Session signing secret (32+ random bytes) | `WEB_SESSION_SECRET` | dev default (refused in production) | ☐ |
| S-23 | Internal key for pg_cron → website calls (outbox worker, revalidation) | `WEB_INTERNAL_KEY` | dev default | ☐ |
| S-24 | Hostinger DNS access for the cut-over (only at go-live) | — | — | ☐ |
| S-25 | Phone-OTP provider (SMS or WhatsApp) — only if `require_phone_otp` is ever turned on | `PHONE_OTP_PROVIDER`, provider keys | adapter disabled | ☐ (not needed at launch) |

## Owner inputs
| # | Item | Status |
|---|---|---|
| S-40 | Confirm the SVG trace of the logo, or supply the original vector file | ☐ |
| S-41 | Which university logos and names Eduwit may use (`web_university_profiles.logo_permitted`) | ☐ |
| S-42 | WhatsApp number for "Talk to a counsellor" (default: Witty's +91 96439 77407 until told otherwise) | ☐ |
| S-43 | Influencer Portal public creator API (`GET {CREATOR_API_URL}/creators/{handle}` → `handle, display_name, photo_url, bio, code, featured[{title, href}]`, schema in `web/lib/server/creators.ts`); until then creator pages are neutral (D-051) | ☐ |
| S-44 | Lawyer review of the updated consent text and Privacy Policy additions (`docs/legal/consent-texts.md`, `docs/legal/privacy-policy-proposed-additions.md`) | ☐ |
| S-48 | Review the interim homepage / About / How it works copy (`content/home.ts`, `content/about.ts`) — replaced by the current site's copy after the crawl, or approved as is (D-044) | ☐ |
| S-49 | Testimonials: confirm each student agreed to be quoted (the importer adds them unpublished) | ☐ |
| S-50 | Named authors and reviewers for guides (spec 13.4) — needed before any guide is published | ☐ |
| S-45 | Real photography of Indian learners (licensed), or approval of generated abstract imagery | ☐ |
| S-46 | University state, city and official website for each university (`web_university_profiles`; enables the state facet) — not in the catalogue | ☐ |
| S-47 | Vercel plan: per-minute Vercel Cron (outbox worker) needs Pro; on Hobby, pg_cron + pg_net can call the worker instead (Phase 7 decides) | ☐ |
