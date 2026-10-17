# Discovery: CRM code conventions (B2B and B2C)

Phase 0 read-only survey of `b2b-crm/web`, `b2c-crm/web`, `docs/` and `b2c-crm/docs/` (17 Oct 2026).

## 1. Stack and config
- **B2B** (`b2b-crm/web/package.json`): next ^16.3.8, react ^19.3.0, zod ^4.6.5, @supabase/supabase-js ^2.117.2, @supabase/ssr ^0.12.7, server-only, next-themes, geist, lucide-react, sonner, cmdk. Tailwind 4.3.3 via `@tailwindcss/postcss`. Messages API called with raw fetch (`lib/ai/worker.ts`). vitest ^5.0.3, TypeScript ^5.9.3, Node >=20.9, `"type": "module"`.
- **B2C (Spark)**: same core plus @anthropic-ai/sdk ^0.129.0, nodemailer, pdf-lib, qrcode, web-push. No Tailwind (hand CSS in `app/globals.css`). vitest + @playwright/test.
- **tsconfig** (both): `strict`, `noUncheckedIndexedAccess`, `allowJs:false`, `moduleResolution: bundler`, alias `@/*`.
- **next.config.ts**: `poweredByHeader:false`, `reactStrictMode`, security headers (XFO DENY, nosniff, Referrer-Policy, Permissions-Policy, HSTS preload, COOP) and `X-Robots-Tag: noindex` (**the website must NOT copy noindex**). CSP with per-request nonce built in `proxy.ts`.
- **vercel.json**: `{"framework":"nextjs","regions":["bom1"]}`. No Vercel crons; scheduling is pg_cron calling `/api/internal/*` with an internal key.
- **proxy.ts** (Next 16 replacement for middleware): Supabase session refresh via `getClaims()`, 12 h idle sign-out, login redirect, nonce CSP (`lib/security.ts buildCsp`). B2C also rate-limits via `b2c.rate_check`.
- No ESLint/Prettier configs. CI (`.github/workflows/b2c-crm-ci.yml`, Node 22): `tsc --noEmit`, `vitest run`, `npm audit --omit=dev --audit-level=high`.
- `b2c-crm/web/AGENTS.md`: this Next version has breaking changes; read `node_modules/next/dist/docs/` before writing code.

## 2. Structure, Supabase clients, env
- `app/(auth)/…` (login, verify/mfa, `actions.ts`), `app/auth/{callback,signout}/route.ts`, `app/v1/**` machine APIs, `app/api/health`, `app/api/internal`; `lib/*.ts` pure logic + `*.test.ts`, `*-data.ts` server reads; `lib/supabase/{server,browser,admin}.ts`.
- `server.ts`: `server-only`, `createServerClient` + publishable key + cookies (acts as the user under RLS). `admin.ts`: `server-only` service-role singleton, used only for signed-out flows and machine endpoints. Env through `lib/env.ts required()`; `siteUrl()` from `NEXT_PUBLIC_SITE_URL`, never request headers.
- RPC: schema-scoped snake_case (`supabase.schema("b2b").rpc(...)`), params `p_*` or a single `p jsonb`; DB functions `SECURITY DEFINER` + `set search_path = ''`; no anon execute.
- Env names (B2B): NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, SUPABASE_SERVICE_ROLE_KEY, NEXT_PUBLIC_SITE_URL, ANTHROPIC_API_KEY, AI_WORKER_KEY. B2C adds internal key, B2B_API_URL/B2B_API_KEY/B2B_SIGNING_SECRET, WhatsApp, SMTP_HOST/PORT/USER/PASSWORD/FROM, Google SA, VAPID, Exotel, Gmail OAuth.

## 3. Staff auth
- **B2C pattern (reuse):** Google OAuth (domain `@eduwit.in` only, invite check) or password, then **email-code second factor**: `b2c-crm/web/app/(auth)/actions.ts` (`sendCode`, `verifyCode`, trusted device 30 days), `lib/auth.ts` (`issueCode` → `b2c.mfa_issue`), SQL in `b2c-crm/supabase/migrations/b1_access.sql` (`b2c.email_codes`, bcrypt hash, 6 digits, 10 min, 5 attempts, 5 codes/hour; `mfa_verify` writes `b2c.session_checks` keyed on JWT `session_id`).
- **B2B:** Supabase TOTP MFA (`aal2`), allowlist `b2b.app_users`.

## 4. Catalogue and leads
- Base tables `public.catalog_programs`, `catalog_universities`, `catalog_synonyms` are **owned by Witty — never change**. Read-only views in schema `catalog` (`b2b-crm/supabase/migrations/m32c_a4_catalog.sql`): `programmes_v` (fees, EMI, intakes, accreditation, `offered_by_partner_count`), `universities_v`, `synonyms_v`, **`partner_rates_v` (commission — never public)**, `catalog.changes` (poll for cache refresh). Grants to role `b2c_app` and service_role.
- B2C caches catalogue in `b2c.programme_cache` (b41) and serves `b2c.programme_search(p jsonb)` / `programme_facets` (b44).
- Leads: master `public.student_leads`, written only via `public.lead_intake(p jsonb)` (merges on phone). Trusted `source_system` values: `witty`, `web_agent`, `crm`.
- **Intake API** (`docs/intake-api.md`; `b2b-crm/web/app/v1/leads/route.ts`; SQL `b2b.api_intake_lead`): `POST https://crm.eduwit.in/v1/leads`, Bearer key (scope intake), `Idempotency-Key`. Top-level keys: lead, source, channel, campaign, utm, click_ids, landing_url, consent{sales_at, partner_share_at, marketing_at, text_version}, phone_verified, occurred_at, route (auto/hold/b2c), b2c_lane. Lead fields: full_name, first/last_name, phone (required), email, alternate_phone, city, state, country, course, specialization, university, programme_level, study_mode, highest_qualification, academic_score, work_experience, annual_budget, enrollment_timeline, preferred_language, guardian_*, enquirer_relation, preferred_call_time, notes, utm_*, campaign, source_detail, referral_code. Responses 201/200/409/413/422/429/503. Test phones `910000…`.
  - `source` free text → `lead_source`. `website_agent`/`web_agent` **require an OTP-verified phone** (`engine.require_verified_phone_sources`); substrings `web|form|landing|site` → channel `web_form`. Paid click IDs → B2C sales lane.
  - `docs/go-live-setup.md` §7.4 and `docs/HANDOVER.md` line 99 say the website should use this API from its server.
- Old website OTP (`/api/v1/verify/*`, `public.crm_verify_check`) lives in the old CRM.

## 5. Email
- B2C: nodemailer over SMTP (Google Workspace relay `smtp-relay.gmail.com:587`), SMTP_* env; dry-run log without SMTP_HOST. Plain-text templates (`lib/mail.ts codeEmail`).
- B2B student notifications: Resend or Brevo via pg_net.

## 6. Design
- Geist Sans/Mono, `lang="en-IN"`. Brand: navy `#0B2F5E` / `#072E5A`, amber `#F5A800` / `#F4A504` (`b2c-crm/docs/brand/palette.md`). Amber is never text on white (B2C uses amber-ink `#8A5A00`). B2C dark: bg `#0A1322`, surface `#122036`.
- next-themes with CSP nonce.

## 7. Testing
- Vitest node env; Playwright (`b2c-crm/web/playwright.config.ts`) laptop + Pixel 7, `next dev -p 3100`, refuses production keys.
- SQL tests run inside `begin … rollback`, results into temp table, `set local role authenticated` + `request.jwt.claims`.
- B2C local DB: plain Postgres + `b2c-crm/supabase/tests/local_stubs.sql` + b1…b45. B2B staging from `00000000000000_baseline.sql`; `deploy.sh`/`deploy.mjs` skip recorded migrations, pause `b2b-*` crons.

## 8. Website-related facts
- `docs/B2B_CRM_PROMPT.md` l.78: website forms post to the Intake API with UTM/click IDs; hosts the website agent and Meta/Google tags.
- Hosts: crm.eduwit.in, spark.eduwit.in, n8n.eduwit.in. Witty WhatsApp: **+91 96439 77407**.
- **Consent texts** (`b2b.consent_texts`, m31a): channels witty, website_agent, web_form, meta_form, google_form, import, manual, api, wa_request. A website `text_version` counts as partner-share consent **only if registered** there as active with `covers_admission_partners=true`, purpose partner_share and a lawyer approval date; wording must name "our admission partners (edtech companies)" (`docs/go-live-setup.md` §4).
- Influencers: `public.influencers` (referral_code, auth_uid). Lead carries `referral_code`. Referral API `GET /v1/referrals/{code}/outcomes` (no PII). **No public creator-profile API exists.**
- **Meta CAPI**: B2B sends server events only for paid leads (event IDs `<lead>:<signal>:<cycle>`); its "Lead" signal exists but is **off by default** and never sent live. The website may send Pixel + CAPI `Lead` without collision today; pass fbclid/gclid/fbp/fbc in `click_ids`.
