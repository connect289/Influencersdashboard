# Stage mapping: CRM data to creator-facing stages

Status: **proposal, waiting for owner approval** (Phase 0, HARD STOP 1).

This file covers spec Section 9.3 (creator stages), 9.4 (stage sync) and the seed values for `inf.stage_mappings`.
Every row here becomes data in `inf.stage_mappings`, editable by a Super Admin. Nothing is hard-coded except the fallback
("unmapped values show as the last known stage and raise a staff alert").

## 1. Where lead status lives today (verified 16 Oct 2026)

| Source | Owner | What it holds | How the portal reads it |
| --- | --- | --- | --- |
| `public.student_leads.stage` (+ `sub_stage`, `stage_changed_at`, `lost_reason`, `lost_at`) | **B2B CRM** (column owner per `docs/b2b-design.md`), set from partner sync and B2C hand-offs | Canonical Eduwit stage. Vocabulary in `b2b.settings.stages` (below) | Read-only, inside `inf` definer functions |
| `public.student_leads.lead_status` / `temperature` / `is_sales_ready` | **Witty** through `lead_intake()` | HOT / WARM / COLD / UNQUALIFIED; `is_sales_ready` turns true on the first HOT/WARM/COLD | Read-only |
| `public.student_leads.enrollment_status`, `enrollment_date`, `enrolled_program`, `enrolled_university`, `applied_at`, `application_status` | B2B (partners) and B2C (counsellors, through the B2B link) | Application and enrollment facts | Read-only |
| `public.b2c_lead_status_v` (versioned contract view, `view_version = 1`) | **B2C CRM (Spark)** | Lane, B2C stage, canonical stage (`assigned`, `contacted`, `counselled`, `applied`, `enrolled`, `lost`), closed reason | Read-only. Today granted to `service_role` only; `inf` definer functions read it as the function owner |
| `public.enrollments` (shared outcome table) and `b2c.enrollments` | B2B / B2C | Enrollment status `reported`, `verified`, refunds | Read-only, for enrolled, clawback and commission |
| `b2b.allocations.stage` and `partner_*_raw` | B2B | Partner-side detail | **Not read.** The B2B CRM already rolls these up into `student_leads.stage` |

B2B stage vocabulary (`b2b.settings.stages`): `new` (10), `qualifying` (20), `allocated` (30), `sent_to_partner` (40),
`duplicate_at_partner` (45), `contacted` (50), `counselled` (60), `applied` (70), `enrolled` (80), `verified` (90),
`commission_booked` (100), `paid` (110), `lost` (999), and the B2C-held states `nurture`, `assigned`, `dormant`,
`routed_to_partner`.

B2B lost reasons: `not reachable`, `not interested`, `not eligible`, `over budget`, `chose another provider`,
`enrolled elsewhere`, `duplicate`, `junk or test`, `wrong number`, `cannot be served`.

B2C stages (`b2c.stages` → canonical): New Lead → assigned; Could Not Connect, Contacted → contacted; Qualified,
Follow Up, Program Details Explained → counselled; Applicant, Docs Submitted → applied; Enrolled → enrolled; Lost → lost.

## 2. Creator-facing stages

`New → Qualifying → Qualified → Allocated → In counselling → Applied → Enrolled`, plus the terminal states
`Lost | Duplicate | Junk | Not attributed`. Each terminal state shows a reason category.

| Key | Label | Terminal | Reason category shown |
| --- | --- | --- | --- |
| `new` | New | no | |
| `qualifying` | Qualifying (Witty) | no | |
| `qualified` | Qualified | no | |
| `allocated` | Allocated | no | |
| `counselling` | In counselling | no | |
| `applied` | Applied | no | |
| `enrolled` | Enrolled | yes (success) | Shows "Cancelled" if the enrollment is later refunded |
| `lost` | Lost | yes | not reachable / not interested / not eligible / budget / chose another option |
| `duplicate` | Duplicate | yes | "Already enquired before your link" (attribution) or "Duplicate enquiry" (CRM) |
| `junk` | Junk | yes | invalid or test / wrong number |
| `not_attributed` | Not attributed | yes | outside window / self-referral / rejected after review (attribution statuses, never PII) |

## 3. Mapping rules (seed rows for `inf.stage_mappings`)

Evaluated in priority order (lowest number first); the first match wins. `source` says which field the rule reads.

| Priority | Source | Match | Creator stage | Reason category |
| --- | --- | --- | --- | --- |
| 10 | attribution status | `duplicate` | `duplicate` | already enquired before your link |
| 11 | attribution status | `outside_window` | `not_attributed` | outside the attribution window |
| 12 | attribution status | `self_referral` | `not_attributed` | self-referral |
| 13 | attribution status | `fraud_suspected` | (stage from CRM, shown with "under review") | under review |
| 14 | attribution status | `manually_rejected` | `not_attributed` | rejected after review |
| 20 | `student_leads.enrollment_status` | in (`refunded`, `cancelled`) | `enrolled` + flag `cancelled` | enrollment cancelled |
| 21 | `student_leads.stage` | in (`enrolled`, `verified`, `commission_booked`, `paid`) | `enrolled` | |
| 22 | `student_leads.enrollment_status` | in (`reported`, `verified`) | `enrolled` | |
| 23 | `b2c_lead_status_v.canonical_stage` | `enrolled` | `enrolled` | |
| 30 | `student_leads.stage` = `lost` and `lost_reason` | `duplicate` | `duplicate` | duplicate enquiry |
| 31 | `student_leads.stage` = `lost` and `lost_reason` | in (`junk or test`, `wrong number`) | `junk` | invalid or test / wrong number |
| 32 | `student_leads.stage` = `lost` and `lost_reason` | `not reachable` | `lost` | not reachable |
| 33 | `student_leads.stage` = `lost` and `lost_reason` | `not interested` | `lost` | not interested |
| 34 | `student_leads.stage` = `lost` and `lost_reason` | `not eligible` | `lost` | not eligible |
| 35 | `student_leads.stage` = `lost` and `lost_reason` | `over budget` | `lost` | budget |
| 36 | `student_leads.stage` = `lost` and `lost_reason` | in (`chose another provider`, `enrolled elsewhere`) | `lost` | chose another option |
| 37 | `student_leads.stage` = `lost` and `lost_reason` | `cannot be served` | `lost` | programme not available |
| 39 | `student_leads.stage` | `lost` (any other or empty reason) | `lost` | other |
| 40 | `b2c_lead_status_v.canonical_stage` | `lost` | `lost` | from `closed_reason`, mapped like the B2B reasons |
| 50 | `student_leads.stage` | `applied` | `applied` | |
| 51 | `b2c_lead_status_v.canonical_stage` | `applied` | `applied` | |
| 52 | `student_leads.applied_at` | is not null | `applied` | |
| 60 | `student_leads.stage` | in (`contacted`, `counselled`) | `counselling` | |
| 61 | `b2c_lead_status_v.canonical_stage` | in (`contacted`, `counselled`) | `counselling` | |
| 70 | `student_leads.stage` | in (`allocated`, `sent_to_partner`, `duplicate_at_partner`, `routed_to_partner`, `assigned`) | `allocated` | |
| 71 | `student_leads.stage` | in (`nurture`, `dormant`) | `allocated` | (none; the creator sees "Allocated", not the internal nurture state) |
| 72 | `b2c_lead_status_v.canonical_stage` | `assigned` | `allocated` | |
| 80 | `student_leads.stage` | `qualifying` and `is_sales_ready` | `qualified` | |
| 81 | `student_leads.stage` | `qualifying` | `qualifying` | |
| 90 | `student_leads.stage` | `new` or empty | `new` | |
| 999 | (fallback) | anything else | last known creator stage | staff alert `inf.stage_unmapped` |

Notes:

- `duplicate_at_partner` maps to `allocated`, not `duplicate`. It means the partner already had the student, and the B2B
  CRM then tries the next partner or hands the lead to B2C. It's still a valid Eduwit lead for the creator.
- **Stages never move backwards for the creator** unless a rule says so (a reopened lead keeps `enrolled` history, and
  a new enquiry cycle adds a timeline entry). This matches the B2B rule that stages never move backwards.
- `qualified` uses `is_sales_ready`, which Witty sets on its first HOT/WARM/COLD classification. If the owner wants
  "qualified" to mean HOT/WARM only, change rule 80 to `lead_status in ('HOT','WARM')` (a data edit, no code).

## 4. How stage events are produced (spec 9.4): proposal

**Recommended: a read-only sweep, with no trigger on any shared table.**

- `inf.lead_sync_tick()` runs from `pg_cron` every minute (setting `attribution.sweep_interval_seconds`; pg_cron supports
  second-level schedules, as the B2B CRM uses).
- It reads `public.student_leads` rows with `updated_at > watermark` (index `student_leads_updated_at_idx` already
  exists), **restricted to leads that have an attribution record**, plus `b2c_lead_status_v` rows for those leads
  (`updated_at > watermark`).
- For each lead it evaluates the rules above, and when the creator stage, the reason or a milestone date changes, it
  appends one row to `inf.lead_stage_events` (idempotency key `lead_id:creator_stage:source_changed_at`) and updates
  the creator-safe projection `inf.creator_lead_feed` (Realtime).
- Watermarks live in `inf.sync_state`, with a 2-minute overlap. Processing is idempotent, so the overlap only costs
  repeated no-op checks.
- Domain events (`lead.stage_changed`, `lead.enrolled`, `lead.enrollment_cancelled`) are written to `inf.domain_events`
  for the compensation runner, notifications and outbound webhooks.

Why not the alternatives:

| Option | Coupling | Risk to Witty and the CRMs | Latency | Verdict |
| --- | --- | --- | --- | --- |
| **Sweep (recommended)** | Reads two indexed columns | None: no new object on any shared table, nothing runs inside anyone's transaction | ≤ 1 min | Least coupled |
| Trigger on `student_leads` | A new trigger on the master table | Runs inside Witty's and every CRM's write; any error or slowness hits them. B2B's rule allows only "enqueue-only, never raises" triggers | Instant | Possible later if seconds matter |
| Subscribe to the B2B outbox (`b2b.webhook_endpoints`) | Depends on B2B event shapes and an HTTP endpoint | Low, but the B2B admin must register the portal as a consumer; payloads are B2B-internal and may carry fields creators must never see | Seconds | Kept as an option, not needed |

The portal **never writes** to `student_leads`, `b2c.*`, `b2b.*` or `w2_*`.

## 5. Open questions

1. Approve the mapping table above, in particular `nurture` / `dormant` → Allocated and `duplicate_at_partner` →
   Allocated?
2. Should "Qualified" mean any Witty classification (`is_sales_ready`, recommended because it matches the CRMs) or only
   HOT/WARM?
3. Approve the sweep (no trigger) for stage sync and attribution?
