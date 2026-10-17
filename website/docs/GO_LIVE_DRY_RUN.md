# Production migration dry run (Phase 12)

**Date:** 17 Oct 2026. **Target:** `prod-replica`, a fresh copy of the production schema (public, b2b, b2c, catalog,
built from the read-only snapshots and the CRMs' migrations; 42/42 fingerprint rows identical to production's
`fingerprint.prod.txt` taken the same day). **Production was not touched.**

**Re-run:** `scripts/db/go-live-dry-run.sh` (about 3 minutes; rebuilds the replica). Run it again on the day of
go-live after refreshing `scripts/db/fingerprint.prod.txt` from production (read-only `fingerprint.sql`), because
other products may have migrated in the meantime.

## Result: PASSED

### 1. Website migrations (in order, each in its own transaction, `lock_timeout` 5 s, `statement_timeout` 5 min)

| Migration | Time | Locks stronger than ACCESS SHARE on shared tables |
|---|---|---|
| web1_foundation | 102 ms | none |
| web2_admin_auth | 80 ms | none |
| web3_taxonomy | 176 ms | none |
| web4_read_model | 193 ms | `cron.job` row insert only (the `web_catalog_poll` job, A-CRON-1) |
| web5_curated_views | 77 ms | none |
| web6_content | 113 ms | none |
| web7_students_leads | 159 ms | none |
| web8_advisor | 81 ms | none |
| web9_admin | 85 ms | none |
| web10_seo_toolkit | 98 ms | none |
| web11_hardening | 75 ms | none |
| **Total** | **1.24 s** | |

The website migrations only read shared tables (the read model is built from `catalog_*`); they never lock them
against writes, so Witty and the CRMs keep working during the apply. Times are on the replica's empty catalogue copy
plus the seeded read model; on production the first read-model build reads the ~715 catalogue rows (2.9 s measured
locally; 39 s at 10,000 offerings, refreshed `CONCURRENTLY` so reads never wait).

### 2. Tests on the replica after the website migrations

All 10 SQL suites pass (1,049 security checks, foundation, admin auth, taxonomy, search, search quality, leads,
Witty, admin, SEO). **Shared objects unchanged:** every fingerprint row outside `web_*` matches production.

### 3. Every item in APPROVALS_NEEDED.md

| Order | Proposal | Approval item | Time | Check |
|---|---|---|---|---|
| 1 | `s07_b2b_routing_web_leads.sql` | 🔴 A-B2B-1 routing of email-verified website leads (via the CRM's audited `b2b.set_setting`) | 68 ms | applied; rollback restores the setting |
| 2 | `s05_b2b_consent_texts_web.sql` | 🔴 A-CONSENT-1 website consent texts in `b2b.consent_texts` (lawyer date set after S-44) | 60 ms | applied; bodies byte-identical to the website's |
| 3 | `s01_lead_intake_email_verified.sql` | A-LEAD-1, A-LEAD-2, A-LEAD-3 (`email_verified_at` write-once for `web_agent`; agent fields into `custom_fields`) | 73 ms | smoke test passed (stored, write-once, other sources refused) |
| 4 | `s04_w2_prompts_channel_web.sql` | A-AGENT-4 `channel_web` prompt row | 51 ms | applied |
| 5 | `s06_unaccent.sql` | A-EXT-1 (optional) | 62 ms | applied |
| 6 | `s02_w2_messages_channel.sql` | A-AGENT-2 + A-AGENT-3 (columns only; **apply only together with the CRM reader changes**) | 61 ms | smoke test passed (existing rows and writers stay `whatsapp`) |
| 7 | `s03_shared_taxonomy.sql` | A-TAX-1 (later, not needed for launch) | 89 ms | smoke test passed (website reads through the compatibility views) |

All 10 SQL suites pass again **with every proposal applied** (security suite: 1,039 checks, fewer because s03 turns
10 website tables into views over the shared tables).

Not SQL: A-AGENT-1 (Witty's engine package; the website ships with Witty off), A-TAX-2 (catalogue fields, catalogue
owner), A-AGENT-5 and A-AUTH-1 (optional / not recommended), A-CRON-1 (inside web4: created only where pg_cron
exists, as in production).

### 4. Rollback

Reverse order: each proposal's `*.rollback.sql`, then `scripts/db/rollback-web.sql` (177 ms). The final state equals
the baseline exactly: schema fingerprint of public/b2b/b2c/catalog, the shared data the proposals touch
(`w2_prompts`, `b2b.consent_texts`, `b2b.settings.engine`), installed extensions and pg_cron jobs. After the rollback
the replica is again identical to production (42/42 rows).

`rollback-web.sql` refuses to run while any non-website object depends on a website object, so its `CASCADE` can never
reach a shared object. It does **not** remove business data written to shared tables through approved paths (leads,
touchpoints), and it drops website-only data with the tables (take the backup in RUNBOOK §Go-live step 1 first; the
consent ledger must be kept).

Also checked on every build (`npm run db:gate` → `check-shared-proposals.sh`): each proposal applied, smoke-tested and
rolled back inside one transaction returns to the identical state.

## Known limits of the dry run

- The replica holds the production **schema** and seeded catalogue, not production's live data volume or traffic.
  Timings on production will be of the same order (the migrations are DDL plus small seeds), but the first read-model
  refresh and `s01` (a function replacement) should be applied in a quiet period.
- `s01` is generated from production's `lead_intake` body as of 17 Oct 2026; its rollback file is that body verbatim.
  On go-live day, compare `md5(prosrc)` of `public.lead_intake` on production with the snapshot (RUNBOOK) and
  regenerate s01 if Witty's or the CRMs' owners changed it.
- `s07` and `s05` are settings/data changes in the B2B CRM; the B2B owner may prefer to make them in the CRM UI. The
  SQL files are equivalent and audited (`b2b.settings_versions`).
