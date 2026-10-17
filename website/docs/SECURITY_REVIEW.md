# Security review (Phase 12)

**Date:** 17 Oct 2026. **Scope:** the website only: `web/` (Next.js app, server actions, route handlers, proxy) and the
website's own migrations `supabase/migrations/2026*_web*.sql`. Shared objects and other products were out of scope;
what was seen in them is listed in `APPROVALS_NEEDED.md` ("Observed in shared objects").

**Method:** an independent, read-only code review (authorisation, SQL functions and grants, secrets, personal data,
input validation and abuse, cookies and sessions, CSRF, commercial data), followed by fixes, regression tests and the
full test suite. Automated checks that run on every build are listed at the end.

**Result:** no high-severity findings. 4 medium and 13 low findings: 16 fixed, 1 accepted with reasons (L12).

## Findings and fixes

| # | Severity | Finding | Fix | Test |
|---|---|---|---|---|
| M1 | Medium | Sign-in `next` accepted `/\evil.com` and `/<TAB>/evil.com`, which browsers treat as `//evil.com` (open redirect after a real sign-in) | `lib/security/paths.ts` `isLocalPath`/`safeLocalPath`: single leading `/`, no backslash, whitespace or control characters, same origin after resolution. Used on the server page and again in the browser before `router.replace` | `paths.test.ts` |
| M2 | Medium | "Book a callback" had no limit and each call updated the shared lead through `lead_intake` | Per-student limit (3 a day, fails closed); database: one request per student, day and slot (a repeat returns the booking and does not reach the lead), at most 3 a day (`web11_hardening`). Comparison saves and chat restarts also limited | `70_web_advisor` (2 new checks) |
| M3 | Medium | Without Upstash, rate limits silently became per server instance; if both stores failed, every limit allowed | On a deployed environment without a shared store, limits use the Postgres limiter (`web_rate_hit`). If no limiter is reachable, limits that cost money or touch the CRM (code sends and checks, chat turns, form submits, callbacks) refuse; browsing limits allow. Health reports the mode | unit + e2e |
| M4 | Medium | Staff Supabase session cookies were readable by scripts and sent to every page (`@supabase/ssr` defaults); those tokens are valid against the shared project | `lib/security/staff-cookies.ts`: HttpOnly, `path=/admin`, Secure in production, SameSite=Lax, in both the server client and the proxy refresh. All staff auth flows are server-side under `/admin` | admin e2e (sign-in, MFA, roles) |
| L1 | Low | Dev fallback secrets (public in the repo) were accepted on preview deployments | `env()` requires `SUPABASE_SECRET_KEY`, `WEB_SESSION_SECRET`, `WEB_INTERNAL_KEY` on preview as well as production | — |
| L2 | Low | Admin redirects could point to `//host` or `/\host` | Same `isLocalPath` rule (or `https://host…`) in the redirect form, the 404 one-click action, the proxy, and a database CHECK on `web_redirects.to_path` | `90_web_seo` |
| L3 | Low | The admin save merged the client-supplied record key object over validated fields | Only the entity's key columns, as strings or numbers, are taken from the key (save and delete) | admin e2e |
| L4 | Low | 404 beacon stored the path and "referrer" as sent; rows never expired | Path scrubbed of emails, phones and digit runs; referrer kept only if it is a bare hostname; own rate-limit bucket; rows not seen for 90 days pruned daily (`web_404_prune`) | `90_web_seo`, seo-toolkit e2e |
| L5 | Low | Funnel beacon accepted any context keys (scrubbing does not catch names) | Server-side per-event allow-list (`funnelContext`); own rate-limit bucket | `events.test.ts` |
| L6 | Low | No per-email cap on failed student code checks | Per-email limit (10 per 10 minutes) in addition to per IP and the 5-attempt code limit | — |
| L7 | Low | The viewer role could see student emails in privacy requests; insights showed raw chat text | Privacy requests: super admins only (page and navigation). Insights text is scrubbed before display | admin e2e |
| L8 | Low | `/api/health` was public and reported environment and provider configuration | Public callers get `{ ok }` (rate-limited); detail needs the internal bearer key | smoke e2e |
| L9 | Low | The SEO checker's link filter let `/\host` through and followed redirects | `isLocalPath` filter; `redirect: "manual"` | `onpage.test.ts` |
| L10 | Low | Witty's chat turned any https URL into a "Brochure" link (a prompt injection could add a phishing link) | Brochure links only come from catalogue placeholders; a literal URL in a model reply fails a web-only verifier rule (rewrite, then safe fallback) and the final text replaces the streamed text | — |
| L11 | Low | Fee lines were a denylist of `fee_other` keys | Allow-list by shape (fee, semester, year, payment, deposit, charges, tuition…) and a block-list of commercial words, so a commission-like key added to the sheet is never shown. All 59 current keys still show | manual query (recorded in PROGRESS) |
| L12 | Low | 7 immutable SQL helpers have no `search_path` | **Accepted (D-076).** They call only built-ins (pg_catalog is always searched first) or schema-qualified `public.web_norm`, are revoked from browser roles, and a `SET` clause would stop Postgres inlining them in search predicates. The Supabase advisor will list them as `function_search_path_mutable` | — |
| L13 | Low | First admin sign-in linked the allow-listed email by the token claim; sign-out keeps the trusted device | Linking requires the auth user's own confirmed email. Keeping the trusted device on sign-out is intended ("remember this device" skips the email code for 30 days on that browser only) and is documented in the runbook | `20_web_admin_auth` (2 new checks) |

## Verified (no change needed)

- **Admin:** every admin page and server action calls `requireAdmin(role)` (sign-in, allow-list, email second factor,
  role) before any database call; role-gated SQL functions re-check the role. The MFA cookie is HMAC-signed, bound to
  the user and session, valid 12 hours, compared in constant time.
- **Students:** every action acts only on the signed-in student; application steps and feedback check ownership.
- **Machine endpoints:** `/api/internal/*` and `/api/metrics` need a bearer key, compared in constant time.
- **Database:** every website function is `SECURITY DEFINER` with `search_path = ''` (except the helpers in L12 and the
  D-055 wrappers), revoked from `public`, `anon`, `authenticated`, granted to `service_role` only; every website table
  has RLS and no browser-role grants (1049 automated checks in `00_web_security`). Dynamic SQL in the admin functions
  quotes identifiers with `%I` and values with `%L` or binds them; table and column names come from an allow-list only
  the service role can change. Leads are written only through `lead_intake`.
- **Secrets:** no client component imports server code or secret environment variables; every `lib/server` module
  imports `server-only`; `NEXT_PUBLIC_*` holds only ids, URLs and the publishable key.
- **Personal data:** logs scrub every field; analytics and Pixel events are allow-listed and scrubbed; the Conversions
  API hashes email and phone; URLs carry no personal data; rate-limit keys are hashed.
- **Sessions:** `ew_sid` is HttpOnly, Secure, SameSite=Lax, HMAC-signed, 90 days, revoked on sign-out; codes are stored
  only as HMACs bound to the attempt.
- **CSRF:** server actions use Next's origin check; `/api/witty` needs a JSON body and the Lax cookie; beacons carry no
  authority.
- **XSS and headers:** `dangerouslySetInnerHTML` only for the static boot script and escaped JSON-LD; chat text is built
  as React nodes; CSP (nonce + `strict-dynamic` on account and admin), `frame-ancestors 'none'`, HSTS with preload,
  nosniff, `X-Frame-Options: DENY`, Referrer-Policy; account and admin responses are `no-store`.
- **Commercial data:** no commission, payout or partner fields anywhere in the website or its read model; the search
  view lists catalogue columns explicitly.

## Dependencies (`npm audit`, 17 Oct 2026)

- **Production dependencies:** 0 vulnerabilities (`npm audit --omit=dev`).
- **Development only:** 22 advisories (16 high), all in `@lhci/cli` → `lighthouse` → `puppeteer-core` and in
  `eslint-config-next` → `fast-glob`/`micromatch`. These run only in CI and on developer machines against our own
  pages, never in the deployed site. The suggested fixes are breaking downgrades of Lighthouse CI; revisit when
  upstream releases fixes. (Also see D-065: Lighthouse CI is only ever run through `npm run lhci`.)

## Automated security checks on every build

- `00_web_security.test.sql`: grants, RLS, `search_path`, no browser-role access, on a fresh database and on the
  production-schema replica.
- `check-shared-unchanged.sh`: shared objects identical to production after applying the website migrations.
- Unit tests: scrubbing, analytics allow-lists, local-path rules, CSP builder.
- e2e: security headers, health output contains no secrets, admin role boundaries, gate rate limits and Turnstile.
- Copy check: banned claims (`content/banned-claims.json`).

## Before go-live

- Set `WEB_SESSION_SECRET` (S-22), `WEB_INTERNAL_KEY` (S-23), `SUPABASE_SECRET_KEY` (S-11) and `CRON_SECRET` for
  **production and preview**; Upstash (S-15) is recommended so rate limits do not load Postgres.
- Turnstile keys (S-13): without them, production refuses gate submissions (fails closed).
- Run the Supabase security advisor after the production apply and compare with the expected list above.
