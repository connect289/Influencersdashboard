# Go-live checklist

Tick in order. Details for every step: `RUNBOOK.md` §5–§7. Nothing here has been done; production is untouched.

## Owner decisions (blocking)

- [ ] Written go-live approval from the owner (spec 0: the only stop of the build).
- [ ] 🔴 **A-B2B-1** approved — website leads route without an OTP-verified phone (else no website lead reaches a
      partner or the B2C team). File: `s07_b2b_routing_web_leads.sql`, or the B2B admin flips the setting.
- [ ] 🔴 **A-CONSENT-1** approved — website consent texts registered in the B2B CRM (`s05_…`), after
- [ ] **S-44** lawyer review of the consent texts and Privacy Policy additions (`docs/legal/`).
- [x] **Legal pages filled** (22 Oct 2026, from the owner's documents; Data Privacy & Opt-out drafted for the DPDP Act).
      Lawyer review (S-44) still recommended — open points in PROGRESS.md.
- [ ] **S-48** homepage / About / How it works copy approved (interim copy written from the spec).
- [ ] A-LEAD-1/2/3 (`s01`) and A-AGENT-4 (`s04`) approved or deferred (the site works without them; see
      APPROVALS_NEEDED for the fallbacks).

## Accounts and secrets (blocking)

- [ ] S-10 Vercel project on the Hobby plan (root `website/web`, region `bom1`); no Vercel crons — jobs run from Supabase pg_cron (D-082)
- [ ] S-11 Supabase keys; S-22 `WEB_SESSION_SECRET`; S-23 `WEB_INTERNAL_KEY` — production **and** preview
- [ ] S-12 email provider with SPF/DKIM/DMARC for the sending domain (verification codes)
- [ ] S-13 Turnstile keys for eduwit.in (production refuses test keys)
- [ ] S-21 Google OAuth for admin sign-in (or use email + password)
- [ ] S-24 Hostinger DNS access

## Recommended before launch (not blocking)

- [ ] S-15 Upstash (rate limits without loading Postgres) · S-19 Sentry · S-16/S-17/S-18 analytics IDs · S-20 Search Console
- [ ] S-54 read replica decision and S-55 production-like load test **before paid traffic**
- [ ] S-40/S-41/S-45 logo, university logos, photography · S-42 WhatsApp number confirmed · S-46/S-53 university details
- [ ] S-49 testimonials consent · S-50 named authors/reviewers (needed before any guide is published)
- [ ] Witty on the website stays **off** until A-AGENT-1 (Witty's engine verified) and S-14 (model key)

## T-7 days

- [ ] DNS zone exported from Hostinger (all records, dated); TTL of `@` and `www` lowered to 300 s
- [ ] Vercel environment variables set; domains added in Vercel (no DNS change yet)

## T-1 day

- [ ] `fingerprint.prod.txt` refreshed from production (read-only); `scripts/db/go-live-dry-run.sh` → `DRY RUN PASSED`
- [ ] `lead_intake` md5 on production unchanged since the snapshot (else `scripts/db/make-s01.py`, re-review)

## Go-live day

- [ ] Full `pg_dump` of production taken and stored safely (Free plan: no point-in-time recovery)
- [ ] Website migrations web1…web13 applied (each in a transaction, `lock_timeout` 5 s); `check-shared-unchanged.sh` OK
- [ ] Approved shared changes applied in order s07 → s05 → s01 → s04 (→ s06); s02/s03 **not** now
- [ ] Vault secret `web_internal_key` created; jobs `web_catalog_poll`, `web_outbox_worker`, `web_seo_daily` listed in `cron.job`
- [ ] Production deploy; `internal_base_url` set to the `*.vercel.app` URL; outbox worker running; smoke test on the `*.vercel.app` URL (home, search, university, curated view, test enquiry →
      lead in the CRM, admin sign-in, `/api/health`, outbox running)
- [ ] `internal_base_url` switched to `https://eduwit.in` right after the DNS change
- [ ] DNS: `@` → Vercel A record, `www` → `cname.vercel-dns.com`; MX/SPF/DKIM/DMARC untouched; certificate issued;
      `www` → apex redirect set in Vercel
- [ ] Old URLs 301 (spot-check 10 from `URL_REDIRECT_MAP.md`); sitemap submitted; a real enquiry reaches the CRM
- [ ] 24-hour watch: leads per hour, outbox dead letters = 0, errors, Search Console

## Rollback (if needed, first 14 days)

- [ ] DNS records back to the exported Hostinger values (minutes, TTL 300 s)
- [ ] If the database layer is at fault: proposal rollbacks in reverse order, backup of `web_*`, `rollback-web.sql`
