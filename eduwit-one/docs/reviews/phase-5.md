# Phase 5 (synthetic tests) review

A fresh, adversarial review of Eduwit One phase 5 at commit `e4e5eee` (`c53c320..e4e5eee`) on
`claude/festive-babbage-7yhhx8`, run read-only by a separate agent on 24 Oct 2026.

**Scope.** Migrations 0014 to 0017 with their rollbacks; the local tests `96_tests_runner.sql`, `97_tests_seams.sql`
and `98_tests_journeys.sql`; `web/lib/tests/**`, `web/lib/setup/validate.ts`, `web/lib/actions/setup.ts`, the tick and
test routes; `config/tests.json`, `config/setup-items.json`; D-068 to D-072 and the runbook's synthetic-tests section.
The B2B and Spark code in the monorepo was read to check what the journeys call.

**Method.** `scripts/db/local-test.sh` (passed), `vitest` in `lib/tests` (62 passed), `tsc` (clean), and reading.

**Verdict.** 1 blocker, 5 majors, 9 minors, and seven documentation errors. The safety core held: every lead fact goes
through `test_run_lead` (a test lead on the run's own phones), no fact returns a phone or email, the two-factor sign-in
and the partner signature match Supabase Auth and B2B, and 0016 creates on a database without the app tables.

## Findings and what was done

| # | Finding | Resolution |
| --- | --- | --- |
| B1 | Five of seven journeys could never switch on: `test_b2b_intake_key`, `test_partner` and `test_whatsapp_number` had no validator, and the Setup page refuses to validate an item without one | Validators `b2b_intake` (an empty body: B2B checks the key first and answers 400 for a good key, writing nothing), `test_partner` (a signed event without an event id: 400 for the right secret, before anything is stored) and `test_whatsapp` (WhatsApp's own numbers for the sender and for Witty's phone id must be the test number and Witty's number, and the number must be a trusted test number). T-WITTY-TURN checks the same numbers before every run. A unit test now fails if any Setup item names a validator that does not exist |
| M1 | `b2b.command_center` returns recent events with student names, and the leak step polled it every 3 s | Read once per run (a poll repeats only after an error); D-070 records it and the counts-only alternative |
| M2 | Leases were kept after a pass, so a waiting run was picked up two or three ticks later; runs were driven one after another, inflating step timings by up to about 135 s; the purge rarely had time | The runner polls all runs in rounds, releases the lease of a run still waiting (`test_run_save` with lease 0), and stops 8 s before the deadline so the purge always runs (D-068) |
| M3 | A failed harness start left Witty's harness switched on | The start step switches it off itself when the start fails after switching it on (D-072) |
| M4 | The purge marked a run purged even when a delete failed, and nothing reported it | A run stays due when any delete failed, with retries 1, 2, 4… hours apart; the new check ONE-PURGE (P2) reports runs still not purged a day after the window (D-071) |
| M5 | One transient error in a poll failed the whole run (and opened a P1) | A poll's error is retried until the step's own timeout; only `Failed` (a definite wrong result) or `Unsafe` ends a run at once |
| m1 | The call step refused Spark's mock call after it had started it | Spark gives a test lead the mock provider when a real one is set; that answer is accepted and the mock logs the call itself; D-070 credits the right check |
| m2 | `setup_test_facts` treated every journey as published (`current_version` is 0, not null, before publishing) | `> 0`; the test's stub now matches Spark's column |
| m3 | `phone.allocate` ignored `student_leads.destination_type`; a longer prefix would leave few phones | The prefix is exactly `9100009`; a phone that already holds any lead is refused |
| m4 | A runner dying between an action and its save repeated the action on resume | An `acting` mark is saved before every action; a resumed run with the mark fails the step instead of acting again |
| m5 | Every invocation signed in afresh and left the session open | One sign-in per pass at most, and a sign-out at its end |
| m6 | The Chatwoot step failed when Witty stored the conversation id after the inbox row | The id is read in the Chatwoot step itself, which waits for it |
| m7 | The nurture facts counted sends and runs from Spark's other journeys | The facts take the test's own journey run id and count sends since enrolment |
| m8 | Overlapping purge passes aborted on a run already purged; with the login unset, the five oldest runs blocked all others | Each run's purge is isolated; up to 50 due runs are read and runs needing the login are skipped, not blocking |
| m9 | T-B2B-PUSH started without the partner secret, stranding a routed lead | The guard requires the secret |
| Docs | RUNBOOK (B1), D-068/D-070 (M2, m1, m5), D-071's phone reuse and its list of what stays, D-072 (M3), TESTS.md purge texts for T-WITTY-TURN, T-WITTY-QUALIFY and T-B2B-PUSH, a wrong D-068 citation, and `0003`'s note naming a route that does not exist | All corrected |

## Found while verifying the review

Checking the review's list of what the purge leaves behind showed that every foreign key to `student_leads` comes from
a legacy table in schema `public`; B2B's and Spark's own tables have none. The first design ended the purge with
Witty's `w2_test_reset` on each phone, which hard-deletes the phone's test leads and would have left B2B's allocations
and Spark's rows pointing at deleted leads. The purge now uses only the CRMs' own soft deletes and hard-deletes nothing,
and phone allocation no longer resets a phone (D-071).
