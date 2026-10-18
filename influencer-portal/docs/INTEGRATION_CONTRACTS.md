# Integration contracts

Status: **proposal, waiting for owner approval** (Phase 0, HARD STOP 1). Each contract names who has to do what. The
portal never modifies Witty, n8n, Chatwoot, the CRMs or the website itself.

## 1. Creator codes and Witty (spec 9.1)

### 1.1 What Witty does today (verified on production, 16 Oct 2026)

- **Witty no longer fills `student_leads.referral_code`.** Witty 2.0 uses an **access-code soft gate**:
  1. The website (or any link) calls `public.w2_issue_code(p jsonb)` with `source`, `campaign`, `utm_*`, `click_ids`,
     `referrer`, `landing_url`, `fingerprint`, `ip`, `user_agent` and so on. It logs a row in `w2_clicks` and returns a
     **personal 6-character code** (alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, valid 30 days, bound to the first phone that
     redeems it). A source in `w2_sources` with `allow_reuse` can instead hand out one shared **campaign** code.
  2. The student messages Witty, e.g. "access code K7QM2X". `public.w2_redeem_code(phone, text)` finds the code with
     the regex `(access|activation) code [is|:|-] <6 alphanumerics>` (or a bare 6-character line), binds it to the
     phone and returns the code's `attribution` (source, campaign, every `utm_*`, click id, fingerprint, ip, kind).
  3. Witty calls `lead_intake()` with `access_code` (stored in `activation_code`), `source` (stored in `lead_source`)
     and `attribution`. `lead_intake()` writes a `touchpoints` row with the full `attribution` JSON on every
     non-chat-turn event (`lead.created`, `lead.qualified`, …).
- A code is **never required** (soft gate): with no code the chat continues as `whatsapp_direct`.
- `lead_intake()` already accepts `referral_code` and `referred_by_code` and keeps the **first** value it receives
  (first-touch columns).
- **Collision risk:** any 6-letter word on its own line, or text like "access code ABCDEF", is treated as an access-code
  attempt. A creator code must therefore never be exactly 6 letters and digits.

### 1.2 Creator code format (portal-owned)

- Pattern: `^[A-Z0-9]{2,12}(-[A-Z0-9]{1,8}){1,3}$`, uppercase, **at least one hyphen**, 5–32 characters. Example:
  `RAHUL-MBA-07`, `PRIYA-IG-3K`. The hyphen guarantees no clash with Witty's 6-character access codes.
- Matching is case-insensitive. Codes are unique across all creators forever (never reused, even after deactivation).
- The suffix generator uses Witty's no-confusion alphabet (no `0/O`, `1/I`), so codes survive being typed from a video.

### 1.3 Proposed contract: two routes, both feeding the same attribution

**Route A: link click (works with no Witty code change; needs one approval).**
1. Every creator link is a portal short link `https://<portal-domain>/r/<CODE>`.
2. The redirect handler logs the click in `inf.link_clicks` (hashed IP, user agent, referrer, UTM, device) and, for a
   `whatsapp_witty` link, calls Witty's **existing** `w2_issue_code()` exactly as the website does, with:
   `source = 'influencer'`, `campaign = <campaign slug>`, `utm_source = 'influencer'`, `utm_medium = <platform>`,
   `utm_campaign = <campaign slug>`, `utm_content = <CREATOR CODE>`, plus click metadata.
3. It redirects to `https://wa.me/<WITTY_NUMBER>?text=<template>`, where the template (setting per campaign) contains
   `access code <issued code>` and the creator code, e.g.
   `Hi Eduwit! I saw Rahul's video about the online MBA. My access code is K7QM2X (ref RAHUL-MBA-07)`.
4. Witty redeems the access code as usual. The creator code reaches `touchpoints.attribution.utm_content` with no
   change to Witty.
5. Link-preview crawlers (WhatsApp, Instagram, Facebook, X, Telegram, Slack unfurlers) are detected by user agent and
   `HEAD` method. They get the redirect without a code being issued (`is_bot: true` is passed, which `w2_issue_code`
   already honours), so previews never burn access codes or count as clicks.
6. If `w2_issue_code()` fails or is slow (timeout 1.5 s), the redirect still happens, with a pre-filled text carrying
   only `ref <CREATOR CODE>`. The click is logged with `issue_failed`, so attribution can fall back to Route B or to
   review.
- **Needs approval:** the portal calls `w2_issue_code()`, which writes to `w2_clicks` and `w2_access_codes` (Witty's
  tables, through Witty's own public function, the same way the website does). Listed in `SHARED_CHANGES.md` S-4.
- **Optional, Witty team:** add `w2_sources` row `influencer` (`channel = 'influencer'`) so these clicks show as a known
  source in Witty's reports.

**Route B: typed code (needs a small Witty change by the Witty team).** For QR codes on posters, codes spoken in
videos, and students who type the creator code themselves.
1. On the first student message (and any message before a code is bound), Witty looks for a token matching the
   creator code pattern above.
2. Witty validates it with `inf.witty_resolve_code(p_code text) returns jsonb`, a `SECURITY DEFINER` function
   executable by `service_role` only (no PII; returns `{ "valid": true, "code": "RAHUL-MBA-07", "campaign": "...",
   "programme_key": "...", "message": null }` or `{ "valid": false }`).
3. If valid, Witty passes it on the next `lead_intake()` call as `lead.referral_code = '<CODE>'` and adds
   `attribution.creator_code = '<CODE>'`. `lead_intake()` already accepts both and keeps the first referral code.
4. If invalid, Witty carries on as normal (soft gate). It **never** blocks or tells the student off.

**Website landing pages:** `https://<website>/c/<handle>?code=<CODE>&utm_...`. The website calls `w2_issue_code()` as it
already does and passes `utm_content=<CODE>` (and `utm_source=influencer`), so these leads attribute through the same
Route A path. Public landing data comes from the API in section 4.

### 1.4 Where the portal looks for a creator code on a lead (in order)

1. `student_leads.referral_code` (Route B, Intake API, website forms).
2. `touchpoints.attribution->>'creator_code'`, then `->>'utm_content'` when `->>'utm_source' = 'influencer'`
   (Route A, website).
3. The access code's attribution: `student_leads.activation_code` → `w2_access_codes.attribution` (same keys), for
   leads whose touchpoint was written before the creator code reached it.

Each candidate is matched case-insensitively against `inf.tracking_links.code`. Codes that match nothing are ignored,
so a legacy referral code never credits anyone.

## 2. CRM stage events (spec 9.4)

See `STAGE_MAPPING.md` §4. Recommended: an `inf` sweep that reads `student_leads` (`updated_at` watermark) and
`b2c_lead_status_v` for attributed leads only. **No change is needed from the B2B or B2C teams.**

- The B2C view is versioned (`view_version = 1`). The portal checks the version on every sweep; on an unknown version it
  stops reading the view and raises a staff alert, rather than misreading it.
- Optional later: register the portal as a consumer of the B2B outbox (`b2b.webhook_endpoints`, consumer
  `influencer_portal`, events `lead.status_changed`, `lead.enrolled`) if sub-minute latency becomes necessary. The B2B
  Admin does that, not the portal.

## 3. Eduwit commission receipts (spec 5 Money, 6.1 B confirmation)

**Finding:** per-enrollment commission received **is derivable**, with no manual entry, from both CRMs:

| Product | Source | "Received" means |
| --- | --- | --- |
| B2B (partner leads) | `b2b.earnings` (`kind = 'commission'`, per `enrollment_id` and `lead_id`, `gross_inr`, `gst_inr`, `net_inr`, `status`, `invoice_id`) → `b2b.invoices` (`status`, `paid_at`, `received_inr`, `tds_inr`) | The earning is `realised` and its invoice is `paid` (or `partly_paid`, pro rata by `received_inr / total_inr`) |
| B2C (in-house leads) | `public.b2c_enrollment_money_v` (versioned, `view_version = 1`): `university_commission_gross / _gst / _net`, `university_commission_status` | Status `paid` |

Proposed contract:

- `inf.commission_receipts_sync()` (pg_cron, every 15 minutes) copies, for **attributed leads only**, one row per
  enrollment into `inf.eduwit_commission_receipts`: `student_lead_id`, `enrollment_ref` (`b2b:<id>` or `b2c:<id>`),
  `gross_paise`, `gst_paise`, `net_paise`, `received_paise`, `received_on`, `status`
  (`expected | partly_received | received | reversed`), `source` (`b2b | b2c | manual`) and a `source_version`
  hash so later changes in the CRM write a new row (append-only history), never an update.
- Finance can add a **manual** receipt or override (reason required, audit-logged) when a CRM has no record, for
  example for a legacy enrollment.
- **Request to the B2B team (recommended, not blocking):** publish a versioned contract view
  `public.b2b_enrollment_money_v` (like B2C's view) so the portal stops reading `b2b.earnings`/`b2b.invoices`
  internals. Until then, all reads of B2B internals sit in that one function, so a B2B change breaks exactly one place.
- Production holds **0** enrollments, earnings and invoices today, so there is nothing to backfill.

## 4. Public API for the website (spec 9.1, 18)

`GET https://<portal-domain>/api/public/v1/creators/{handle}` (no auth, rate-limited per IP, cached 5 minutes at the edge):

```json
{
  "handle": "rahulteaches",
  "display_name": "Rahul Verma",
  "photo_url": "https://<signed or public CDN url>",
  "bio": "…",
  "code": "RAHUL-WEB-01",
  "featured_programmes": [
    { "programme_id": 123, "name": "Online MBA", "university": "…", "level": "PG", "mode": "Online",
      "fee_total_inr": 150000, "duration": "2 years" }
  ],
  "whatsapp_link": "https://<portal-domain>/r/RAHUL-WEB-01"
}
```

- Only `active` creators who opted in to a public page (`public_page_enabled`). Unknown or inactive handle → `404`.
- Avatars live in a separate bucket `inf-public-avatars` that holds only images the creator chose to publish.
- No creator email, phone, legal name, PAN, earnings or follower data unless the creator ticks "show on public page".

## 5. Outbound webhooks (spec 18)

`inf.webhook_endpoints` (URL https only, events list, secret in Vault) and `inf.webhook_deliveries` (append-only
log). Signed `X-Eduwit-Signature: t=<unix>,v1=<hex HMAC-SHA256 of "<t>.<body>">`, the same scheme the B2B CRM uses for
partner pushes. Retries with backoff (1 min, 5 min, 30 min, 2 h, 6 h, 12 h), then dead with a staff alert. Idempotency
header `X-Eduwit-Event-Id`.

Events: `lead.attributed`, `lead.enrolled`, `contract.signed`, `deliverable.live`, `payout.paid`, `creator.activated`.
Payloads carry ids, codes, stages and amounts in paise, **never a student's phone or email** (the student is identified
by `lead_ref` only).

## 6. Oversight system (spec 18)

- `GET /api/health`: no auth, returns only `{ status, checks: { db, storage, queue }, version, time }` without detail
  (detail would help an attacker). Detailed status needs the internal key.
- `GET /api/metrics/summary`: header `Authorization: Bearer <INF_INTERNAL_API_KEY>` (constant-time compare), returns
  counts (creators by status, leads attributed today, payouts due, queue depth, failed jobs, last sweep time).

## 7. Notifications and OTP (spec 14, 8.4)

Provider-agnostic adapters with mock providers until credentials arrive (HARD STOP 4):

- **Email:** adapters for SMTP (Google Workspace, as B2C uses), Resend and Brevo (as B2B uses). Choose one in the
  open questions.
- **WhatsApp:** Meta Cloud API template messages, direct to Graph API (both CRMs do this). Needs a number, WABA id,
  approved templates and a token.
- **In-app:** `inf.notifications` with Realtime.
