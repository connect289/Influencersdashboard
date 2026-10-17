# Runbook

Operating and go-live notes for the Influencer Portal. The full deployment checklist, dry-run report and rollback
script are completed in Phase 10 (HARD STOP 6); items are collected here as each phase adds them.

## Go-live checklist (collected so far)

| # | Item | Added |
| --- | --- | --- |
| G-1 | Mark the shared baseline applied, never run it: `supabase migration repair --status applied 00000000000000` (D-34). Then apply only the `inf` migrations | Phase 1 |
| G-2 | Add `inf` to the Data API's exposed schemas (SHARED_CHANGES S-2) | Phase 1 |
| G-3 | Vault secrets: `inf_app_base_url`, `inf_internal_key` (cron dispatch), **`inf_pii_key`** (created by migration 20261018000100 if missing) | Phase 1–2 |
| G-4 | **Back up `inf_pii_key`** to the company password manager immediately after go-live. Without it, stored PAN and bank account numbers cannot be decrypted. Never rotate it without the re-encryption script | Phase 2 |
| G-5 | Legal review of the compliance course text (`inf.course_lessons`, `inf.course_questions`) and of the creator platform terms and privacy notice before creators are invited | Phase 2 |
| G-6 | Auth settings: allow sign-ups (S-13), redirect URLs and the code-carrying email template (S-14), leaked-password protection (S-15) | Phase 1–2 |
| G-7 | Retire the legacy influencer objects L-1 to L-3 (SHARED_CHANGES §E) | Phase 0 |
| G-8 | Optional: CAPTCHA keys for `/signup` (D-50) | Phase 2 |

## Operations

- **Public media kits** (`/m/<handle>`) exist only for approved creators who turned the page on; responses are rate
  limited per IP and cached for five minutes. Every page carries `X-Robots-Tag: noindex`.
- **Dormancy** runs inside the nightly `inf-nightly` job (`inf.nightly_prune()` → `inf.creators_flag_dormant()`).
- **Production schema drift check** (read-only): run `scripts/baseline/generate-baseline.sql` against production and
  compare with `scripts/baseline/exact.sql` (or compare per-object md5 hashes as done at the Phase 2 gate).
