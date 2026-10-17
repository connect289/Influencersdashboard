# Testing

How the suites map to spec 20 (testing and acceptance). Commands are in the root `CLAUDE.md`.

## Suites

| Suite | Where | What |
| --- | --- | --- |
| Unit (Vitest) | `lib/**/*.test.ts` | Pure engines and helpers: compensation engine (exhaustive), simulator, TDS and GST, attribution rules, stages, fraud, ledger plan, lifecycle, payout, reconciliation, analytics, scorecards, tiers, privacy plan, webhooks, codegen drift, message keys, contrast |
| Database (pgTAP) | `supabase/tests/*.sql` | RLS and grants per role on every `inf` table and creator-facing function, masking proofs, money and status rules. Dates use the IST calendar day, as the database does |
| End to end (Playwright) | `e2e/*.spec.ts` | Journeys against a production build, the local stack and the seed; `a11y.spec.ts` runs axe on key screens |

## Spec 20 coverage

**Unit tests**: compensation engine (`lib/compensation/engine.test.ts`), attribution rules (`lib/attribution/rules.test.ts`),
masking (`supabase/tests/019_attribution.sql` and the feed tests), TDS and GST (`lib/compensation/tax.test.ts`), milestone
triggers, slabs and recoupment (`engine.test.ts`, `lib/ledger/plan.test.ts`).

**RLS tests**: every `inf` table and creator-facing function per role in `supabase/tests`; "no creator or agency path
returns an unmasked phone or email" is proved in `019_attribution.sql` (the lead feed, lead detail and agency views),
`002_rls_roles.sql` (only `lead.contacts` holders see contacts), `010_agencies.sql` (agencies cannot read creator
contact details), `023_communication.sql` (webhook payloads carry no contact details; templates cannot use them) and
`024_insight_privacy.sql` (the data export).

**End-to-end journeys**

| Spec 20 journey | Spec file and test |
| --- | --- |
| 1. A prospect is invited, completes onboarding and KYC, and is approved | `onboarding.spec.ts` (invitation, sign-up, every onboarding step, approval), `profile-kyc.spec.ts` (KYC submitted masked, Finance verifies) |
| 2. An open campaign gets an application, countered and accepted; deal, contract, brief and deliverables are created | `campaigns.spec.ts` (apply, counter, accept, contract drafted), `content.spec.ts` (the brief and deliverables of the deal) |
| 3. Contract negotiation, OTP sign, countersign, signed PDF with certificate | `contracts.spec.ts` |
| 4. Brief acknowledged; concept, draft, timestamped review, approval, live, verification; milestone payable | `content.spec.ts`, `finance.spec.ts` (the payable milestone) |
| 5. Link clicked, lead arrives, attributed, enrols; commission accrues, confirmed on receipt, paid in a batch with a UTR; creator notified | `leads.spec.ts` (click and redirect, sweep), `journeys.spec.ts` 5a–5b (enrolment, accrual, receipt on the Finance screen, confirmation, notification), `finance.spec.ts` (batch, two approvals, bank file, paid with UTR, notification) |
| 6. Duplicate lead and self-referral are not credited, with the reason shown | `journeys.spec.ts` 6 |
| 7. Clawback inside the refund window | `journeys.spec.ts` 7 |
| 8. Commission-only, fixed-only and hybrid (recoupable advance, retroactive slabs) deals produce exactly the expected ledgers | `journeys.spec.ts` 8 (real runner over fixture deals), with the engine cases in `engine.test.ts` |

`journeys.spec.ts` writes enrolments and refunds to the local copies of the shared tables, as the CRMs would, and refuses
to run unless the Supabase URL is local.
