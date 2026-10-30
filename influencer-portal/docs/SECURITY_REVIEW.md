# Security review (Phase 10.4)

Review date: 17–18 Oct 2026. Scope: the Influencer Portal in `influencer-portal/` (app code, `inf` migrations, route
handlers, jobs). Method: a read-only code review against the OWASP Top 10 and spec 19, then fixes with tests. Nothing
here touched the production project.

## Summary

| # | Finding | Severity | Status |
| --- | --- | --- | --- |
| 1 | Agency owner checks compared `inf.current_agency_id() = p_agency` bare. For anyone who is not an active agency member (a creator, staff without `agency.manage`, a removed member) the comparison is null, `not (false or null)` is null and the `raise` was skipped: such a caller could add themselves as an owner of any agency, remove members and send link requests in its name | High | Fixed |
| 2 | `inf.rate_check(key, limit, seconds)` was executable by `anon` and `authenticated` with a caller-chosen key, so anyone could exhaust another person's sign-in, code or password-link limits (targeted lockout) | Medium | Fixed |
| 3 | Creators (and agencies with the negotiate grant) could create `custom_url` links to any HTTPS host, making `/r/<code>` an open redirect on Eduwit's domain | Medium | Fixed |
| 4 | Webhook delivery relied on the connect-time DNS lookup check, which Node skips for literal addresses; `https://2130706433/` or `https://0x7f.1/` reached loopback (staff with `webhook.manage` only, blind) | Medium | Fixed |
| 5 | The bank-file download (GET) moves a batch to processing; a cross-site link could trigger it for a signed-in Finance user | Low | Fixed |
| 6 | Sign-out accepted POSTs without an `Origin` header | Low | Fixed |
| 7 | An approved deletion left the public avatar file in storage; KYC proof files were never removed; a null purge date meant KYC was never purged | Low | Fixed |
| 8 | The upload size check is advisory (a signed upload URL does not bind the declared size); the bucket limit is the real cap | Low | Accepted |
| 9 | `/m/[handle]` (public media kit page) is not rate limited; per-IP limits trust `x-forwarded-for` when not on Vercel | Low | Accepted (see go-live) |
| 10 | The `inf-briefs` bucket allows SVG | Low | Accepted |

Correctness defects found while adding the spec 20 journeys (not security, fixed in the same pass, D-183 to D-185): the
engine's commission subjects are `<rule>:enrol:<ref>` and `<rule>:lead:<id>`, but four consumers expected `enrol:` /
`lead:` at the start, so engine lines were not linked to their lead, Finance reconciliation was empty, and the
`lead.enrolled` notification never fired; recording a receipt from a reconciliation row failed for enrolments without
a CRM receipt; and a clawback inside the window (a `clawback` line) did not notify the creator.

## Fixes

1. **Agency owner checks** (`20261018000200_inf_agencies.sql`: `agency_member_add`, `agency_member_remove`,
   `agency_link_request`, `agency_link_request_by_handle`) now use
   `coalesce(inf.current_agency_id() = p_agency and inf.current_agency_role() = 'owner', false)`, the convention
   CLAUDE.md requires. pgTAP `010_agencies.sql` proves a creator and staff without `agency.manage` are refused for each
   function. A scan found no other bare `current_creator_id()` / `current_agency_id()` / `auth.uid()` comparisons inside
   `if not (...) then raise`.
2. **`rate_check`** is no longer granted to clients (server only, called with the service client from
   `lib/rate-limit.ts`). `001_privileges.sql` asserts `anon` can execute only `health()` and `media_kit_public()`.
3. **Custom link addresses** are staff only: `inf.link_create` refuses `custom_url` for creators and agencies, the link
   builder hides the option for them, and `019_attribution.sql` proves the refusal.
4. **Webhook literal addresses**: `literalHostAllowed()` (`lib/webhooks/ssrf.ts`, pure, also used in the browser form
   schema) parses the URL as Node does and refuses any non-public address written as the host, in decimal, hex, octal
   or IPv6 form. Delivery checks it before connecting and the endpoint form refuses such URLs on save. Unit tests cover
   the forms.
5. **Bank file**: the route refuses requests whose `Sec-Fetch-Site` is not `same-origin` or `none`.
6. **Sign-out**: refuses a missing or foreign `Origin`.
7. **Deletion storage**: `inf.privacy_deletion_decide` now computes the purge date itself (the last financial or
   contract record plus `financial_records_years`, as `deletionPlan` shows staff) instead of trusting the browser; when
   no record needs the KYC it is deleted at once. It returns the files to remove (the photo, and KYC proofs no longer
   needed), which the action deletes; when kept KYC reaches its purge date, `inf.retention_run` queues the new
   `storage.remove` job for its proof file. pgTAP `024_insight_privacy.sql` covers the purge date and the queued job.

## Checklist (spec 19)

| Area | Evidence |
| --- | --- |
| Injection | Every database call is an RPC with typed parameters; all `inf` functions set `search_path = ''` (479 headers scanned); CSV exports neutralise formula cells (`lib/csv.ts`) |
| Access control | RLS on every `inf` table; client grants only through `inf.client_grants` and `inf.apply_client_grants()` (revokes everything else); pgTAP per role in `supabase/tests` (24 files, 884 assertions) |
| Students' contact details | Creators and agencies read leads only through `inf.creator_lead_feed`, filled with `inf.mask_phone` / `inf.mask_email`; the leads export and the privacy export use the masked feed (pgTAP `019`, `024`) |
| PAN and bank | Encrypted with `inf.pii_encrypt` (Vault key); decrypted only in `kyc_reveal` (permission, reason, audited) and `payout_bank_rows` (permission, audited) |
| Authentication | Staff: password (breach check, lockout) plus emailed code or a trusted device; creators and agencies: email code; session idle timeout setting enforced by `inf.session_ok()`; device list with remote sign-out |
| CSRF | Server actions use Next's origin check; mutating route handlers check `isSameOrigin` or an internal key (constant-time compare); the one state-changing GET checks `Sec-Fetch-Site` |
| CSP and headers | Per-request nonce CSP with `strict-dynamic`, `frame-ancestors 'none'`, `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`; HSTS (2 years, preload), nosniff, Referrer-Policy, COOP, Permissions-Policy (`proxy.ts`, `next.config.ts`; e2e `auth.spec.ts` checks every response) |
| Rate limits | Staff sign-in 30/5 min per IP; creator code 30/10 min per IP and 5/10 min per email; code verify 10/10 min; staff code 5 sends and 10 checks per 10 min plus 5 attempts per code; password link 3/hour; sign-up 10/hour per IP and 3/hour per email; redirect 120/min (over the limit the visitor is still redirected but counted as a bot); public API and media-kit PDF 60/min |
| Files | Private buckets with size limits and MIME allow-lists (avatars public); uploads only through one-time signed URLs issued after a database permission check; downloads checked first, then 60-second signed URLs (1 hour for deliverable review files) |
| Service role | `lib/supabase/admin.ts`, `lib/env.ts` and `lib/rate-limit.ts` are `server-only`; no client component imports them; every caller authorises first; `lib/env.ts` refuses a key whose project does not match the URL and refuses this environment's staging key against a local URL |
| Webhooks | HMAC-SHA256 signatures with timestamps, HTTPS only, no redirects, 10-second timeout, public addresses only (names checked at connect time, literals before), payloads without contact details |
| Secrets | Only `.env.example` (placeholders) is committed; a pattern scan found no keys or tokens |
| Dependencies | `npm audit --omit=dev`: 0 vulnerabilities (17 Oct 2026) |
| Accessibility | axe (WCAG 2.1 A/AA) on the key screens of every portal in `e2e/a11y.spec.ts`; contrast pairs unit-tested in `lib/design/contrast.test.ts` |

## Before go-live

- Deploy on Vercel (or set `clientIp` to trust only the platform's header) so per-IP limits cannot be spoofed.
- Add the `/m/[handle]` page to the edge rate limit (or Vercel firewall) with the public API limits.
- Re-run `npm audit --omit=dev` and this checklist against the release candidate.

## Estate audit, 30 Oct 2026

Review of the `inf` schema's client-callable functions and the app's routes. Changes in
`20261030000100_inf_audit_guards.sql` (D-192, pgTAP `025_audit_guards.sql`) unless noted:

| # | Change | Status |
| --- | --- | --- |
| 11 | Null-safe side checks in seven content and contract functions | Fixed |
| 12 | `eligibility_gaps` is internal (no client grant) | Fixed |
| 13 | `creator_profile_update` applies `avatar_set`'s own-folder rule | Fixed |
| 14 | `kyc_save` keeps the KYC proof in the creator's own folder | Fixed |
| 15 | `thread_post` accepts only the attachment path shape the app writes | Fixed |
| 16 | `tiers_list` answers staff, creators and the service role | Fixed |
| 17 | The short-link route handles any path segment without an error (`decodeCodeSegment`) | Fixed |
| 18 | `npm audit --omit=dev`: nodemailer 10.1.7, fast-uri 3.1.9 (0 vulnerabilities) | Fixed |
