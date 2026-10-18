# Changes to shared objects: proposal for approval

Status: **waiting for owner approval** (Phase 0, HARD STOP 1). Nothing in this list has been created, in production or
anywhere else. After approval, any change that differs from this list stops the build again (HARD STOP 2).

The shared Supabase project `xlseqwgyjuqhktrguhyc` serves Witty, the B2B CRM, the B2C CRM (Spark), the old CRM objects
and the legacy influencer dashboard. The portal's design goal is to need **as few shared changes as possible**. The
headline:

- **No trigger on `student_leads`.**
- **No new column on `student_leads`** or on any `w2_*`, `catalog_*`, `b2b.*` or `b2c.*` table.
- **No change to `lead_intake()`.**
- Attribution and stage sync are read-only sweeps from the portal's own schema (`STAGE_MAPPING.md` §4).

## A. New objects the portal owns (approval of the container, not of each table)

| # | Change | Why | Risk to others | Reversible by |
| --- | --- | --- | --- | --- |
| S-1 | Create schema **`inf`** holding every portal table, view and function (the spec's `inf_*` names become `inf.*`, e.g. `inf_creators` → `inf.creators`). `revoke all on schema inf from public`; `grant usage` to `authenticated` and `service_role` only; `alter default privileges in schema inf revoke execute on functions from public` | Same convention as `b2b` and `b2c`. Keeps the portal out of `public` (199 tables, including n8n's), makes grants and exposure per schema, and makes "outside the portal" easy to check: anything not in `inf` | None. New namespace | `drop schema inf cascade` (rollback script in RUNBOOK) |
| S-2 | Add `inf` to the Data API's **Exposed schemas** (Supabase dashboard, API settings) | supabase-js calls `inf` functions over PostgREST, the same way B2C exposes `b2c` | Low. Exposure lets PostgREST see the schema, but every table has RLS and the default grants are revoked; anon gets nothing | Remove from the list |
| S-3 | `pg_cron` jobs named **`inf-*`** (rows in the shared `cron.job` table): `inf-lead-sync` (every minute), `inf-commission-sync` (15 min), `inf-jobs` (every minute), `inf-notify` (30 s), `inf-nightly` (scorecards, retention, digest), `inf-facts` (dashboard summaries) | Scheduled work (spec 3) | Low. Jobs run as short, bounded batches with `statement_timeout` and a lock so they never overlap. `pg_cron` and `pgmq` are already installed | `cron.unschedule('inf-…')` |
| S-4 | Private **Storage buckets** `inf-contracts` (signed PDFs, write-once), `inf-kyc` (PAN and bank proofs), `inf-deliverables` (videos, resumable uploads), `inf-briefs`, `inf-invoices`, `inf-documents`; one bucket `inf-public-avatars` (public read, images only, size-limited) | Spec 3 uploads | None. Buckets are separate; `storage.objects` policies are scoped by `bucket_id like 'inf-%'` | Delete the buckets |
| S-5 | **Vault secrets** prefixed `inf_` (`inf_pii_key` for PAN and bank encryption, `inf_lead_ref_key`, `inf_internal_key`, webhook secrets, provider keys) | Spec 2.8 | None | Delete the secrets |
| S-6 | Add **`inf.creator_lead_feed`** (masked, creator-safe projection) and `inf.notifications` to the `supabase_realtime` **publication** (the publication is shared; today it holds no tables) | Spec 9.3 Realtime on the creator-safe projection only | Low. Only `inf` tables are added; RLS applies to Realtime | `alter publication supabase_realtime drop table …` |

## B. Using other products' objects (reads, and one write path)

| # | Object | Use | Why it needs approval |
| --- | --- | --- | --- |
| S-7 | `public.student_leads`, `public.touchpoints` | **Read only**, inside `inf` `SECURITY DEFINER` functions owned by `postgres`: attribution, stage sync, the masked creator lead pipeline, the staff lead view | Reads the master table. No grants change: creators and agency users get **no** grant on either table |
| S-8 | `public.w2_access_codes`, `public.w2_clicks`, `public.w2_conversations` | **Read only**: attribution fallback (access code's attribution), click-fingerprint and "never responded to Witty" fraud signals (`last_student_at`) | Witty's tables |
| S-9 | `public.b2c_lead_status_v`, `public.b2c_enrollment_money_v`, `public.enrollments`, `b2c.enrollments` | **Read only**: stage sync, enrollment and refund facts, commission received (B2C) | B2C contract views (versioned) and the shared outcome table |
| S-10 | `b2b.earnings`, `b2b.invoices` | **Read only**: commission received (B2B), isolated in one function until B2B publishes a contract view (`INTEGRATION_CONTRACTS.md` §3) | Reads B2B internals |
| S-11 | `catalog.programmes_v`, `catalog.universities_v`, `catalog.partner_rates_v`, `public.catalog_programs`, `public.catalog_universities` | **Read only**: programme pickers, approved claims, simulator margin (Eduwit commission per programme). Commission figures are shown to staff only, never to creators | Catalogue and commission data |
| S-12 | **Calling `public.w2_issue_code()`** from the portal's `/r/<code>` redirect for WhatsApp links (Route A in `INTEGRATION_CONTRACTS.md` §1.3). It inserts into `w2_clicks` and `w2_access_codes` through Witty's own public function, exactly as the website does | Lets creator links work with **no Witty code change** | This is the portal's **only write path into another product's tables**. If you decline it, WhatsApp links use Route B only (needs the Witty change) |

## C. Requests to other teams (they make the change, not the portal)

| # | Team | Request | Needed for |
| --- | --- | --- | --- |
| R-1 | Witty | Recognise typed creator codes (pattern `^[A-Z0-9]{2,12}(-[A-Z0-9]{1,8}){1,3}$`), validate with `inf.witty_resolve_code()`, and pass `lead.referral_code` plus `attribution.creator_code` to `lead_intake()` | Route B (QR codes, typed codes). Not needed for links |
| R-2 | Witty | Optional: add `w2_sources` row `influencer` (channel `influencer`) | Clean Witty reports |
| R-3 | Witty / n8n | Confirm the database role n8n connects with (`service_role` or `postgres`) so `inf.witty_resolve_code` can be granted to exactly that role | Route B |
| R-4 | B2B | Optional: publish `public.b2b_enrollment_money_v` (versioned) | Removes the read of B2B internals (S-10) |
| R-5 | Website | Pass `utm_source=influencer&utm_content=<CODE>` into `w2_issue_code()` on `/c/<handle>` pages and render them from the public API | Website landing pages |

## D. Project-level settings (Supabase dashboard; shared by every product)

| # | Setting | Why | Effect on other products |
| --- | --- | --- | --- |
| S-13 | **Auth: allow new sign-ups** (if currently off; I can't read this from SQL) | Creator self sign-up (spec 13) and invite acceptance | Anyone can then create an auth account. B2B and B2C already refuse any account not on their allowlists, and the portal refuses accounts without an `inf` profile. **Side effect:** the old CRM's trigger `crm_on_auth_user_created` inserts every new auth user into `public.crm_users` as an **inactive viewer** (no access; `crm_role()` requires `is_active`). Creators will appear there; see risk RK-3 |
| S-14 | **Auth: redirect URLs** for the portal's domain(s); email OTP template wording that works for every product (or a portal-specific sender through custom SMTP) | Creator email OTP and Google sign-in | Shared templates change for every product. Phase 1 found the magic-link template must carry the 6-digit `{{ .Token }}` (creators type the code); the proposed neutral template is `supabase/templates/magic_link.html` |
| S-15 | **Auth: leaked-password protection on** (currently off, per the security advisor) | Staff password sign-in (spec 19) | Stronger passwords for every product |

## E. Existing exposures found (not caused by the portal; flagged under HARD STOP 3)

These are **legacy influencer-dashboard objects**. Both CRM specs said to leave them alone. The new portal never
uses them, but they contradict the new rule that creators must never see a student's phone or email, so you need to
decide what happens to them.

| # | Object | Problem | Recommendation (your decision; I won't change them without approval) |
| --- | --- | --- | --- |
| L-1 | RLS policy **"Influencers can only view their own student leads"** on `student_leads` (`referral_code = current_referral_code() or is_admin()`), plus `authenticated` holding SELECT on `student_leads` | Any auth user with an active row in `public.influencers` can read **every column** of their referred leads, including phone, email and IP, through `/rest/v1/student_leads`. Three such rows exist (`priyansh01`, `vikas01`, `Normie2314`, created 9–12 Jul 2026) | At portal go-live: drop the policy (or set the three rows to `inactive`, which closes it at once, since `current_referral_code()` requires `status = 'active'`) |
| L-2 | `public.influencer_dashboard_leads(code, password)` executable by **anon**; `public.influencer_auth.secret_password` stored in **plain text** | Masks phone/email (last 4 digits), but passwords are plain text and the function is public. Rows: `organic`, `influencer_a`, `influencer_b` | Retire at portal go-live: revoke execute from anon and authenticated, then drop. Migrate any real creator into the portal by invitation |
| L-3 | `public.is_admin()` = "JWT email is connect@eduwit.in" (no MFA check), used by the legacy policies | A Google sign-in without any second factor grants full read of `student_leads` and `influencers` through these legacy policies | Retire with L-1 |

## F. Explicitly not requested

- No trigger on `student_leads`, `touchpoints` or any `w2_*` table (sweep instead; trigger option kept in
  `STAGE_MAPPING.md` §4 if you prefer instant updates).
- No new column anywhere outside `inf`.
- No change to `lead_intake()`, `w2_crm_owned()`, `crm_*` functions, B2B or B2C functions, n8n or Chatwoot.
- No write to the legacy `influencers` / `influencer_auth` tables. The portal never inserts a creator there, so
  creators can never get the legacy full-row access in L-1.
