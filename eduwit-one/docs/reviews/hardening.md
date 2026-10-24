# Hardening review (security, self-healing, efficiency)

Three independent reviewers worked on 24 Oct 2026, each read-only, each on its own throwaway cluster, on commits
`131b298` to `f998342` of `claude/festive-babbage-7yhhx8`: an adversarial **security** review (external attacker,
prompt injection, key compromise, Postgres privilege escalation, internal routes), a **self-healing** review (every
way Eduwit One itself can break, and whether it notices and recovers) and an **efficiency and code-quality** review
(the tick's cost at a year's volume, indexes, pages, bundles, AI tokens, dead code). Their full reports are in the
build session's scratchpad; this file keeps the findings and what was done (D-084 to D-087).

**Verdicts.** Security: no blocker, 2 majors, 10 minors; the trust boundaries hold (the API roles reach schema `one`
only through the declared surface, the AI decides and executes nothing, approvals cannot be widened, the tooling cannot
reach production by accident). Self-healing: 1 blocker, 6 majors, 10 minors; the serialisation (locks, minute bucket,
leases, idempotency keys) is sound, but Eduwit One detected most of its own deaths only through the external watchdog,
repaired nothing itself, and two loops made things worse. Efficiency: 3 high, 9 medium, 9 low; bundles fine, two
pages slow at a year's volume, the minute readers without indexes.

## Security

| # | Finding | Resolution |
| --- | --- | --- |
| M1 | SQL check values and errors were never redacted: a failed cron job's libpq DETAIL line put a phone and an email into `one.results`, the incident's evidence, the P1 email and the incident page (the AI's context was clean) | `one.mask_text` and `one.mask_json` (phones with or without a country code or a space, 11–15-digit numbers, emails → `[phone]`, `[email]`, words kept) in `one.evaluate`, `claim_deliveries` and `ui_incident`; tested end to end in `99_hardening.sql` §6a |
| M2 | An engineer could blind a protected check (cadence 7 days, open_after 60) or a P1 test (schedule "0 0 31 2 *") without the owner | Raising `cadence_s` or `open_after` on a P1, integrity, security, money or consent check and rescheduling a P1 test are the owner's; a day of month above 28 is refused for everyone; tested §6b |
| m1 | The owner could backdate `observation_started_at` before the first tick and switch a fix on at once | `ui_settings_put` keeps the stored start whatever the form sends; tested §6c |
| m2 | `tests` and `witty` (engineer-editable) had no shape check; a bad `purge_after_days` stopped the purge | Shapes for `tests`, `witty`, `hosts`, `vendors`, `vercel`, `chatwoot`, `n8n`, `whatsapp`, `health_paths`, `retention`, and `checks.transaction_timeout` at least 5 s (with F6); tested |
| m3 | A saved view with non-numeric days made every brief email unreadable | `ui_view_save` validates days; `compose.ts` coerces with a fallback (web) |
| m4 | Histories were append-only by convention; `ui_mute` rewrote an audit row | `forbid_mutation` trigger on the audit, settings versions, sign-in log and results; `one.mute` writes its request id itself; `one.retention()` is the one writer; tested §6d |
| m5 | `/api/watchdog` made one service-role RPC per unauthenticated request | Verdict cached 10 s; 429 past 20 requests a minute per instance (web) |
| m6 | `one_internal_key` travelled as a static bearer in pg_net's PUBLIC-readable queue; it also signed the idle cookie; the runbook rotated it in the dashboard's SQL editor | `one.job_call` sends `x-one-token: <ts>.<HMAC-SHA256(key, ts\|path)>`, good for 90 s; the app checks it (and still accepts a person's bearer); the cookie key is derived from the key; the runbook rotates from psql |
| m7 | The AI's triage summary was pasted into P1 emails unlabelled | Prefixed "AI summary (advisory):" (web) |
| m8 | `one.redact` kept a 10-digit non-Indian JSON number | A 10-digit number starting 3 to 9 is masked like the string, and 11 to 15 digits as before; epoch seconds (10 digits starting 1 or 2, until 2065) stay, as two earlier reviews asked; tested |
| m9 | No nosniff, Referrer-Policy or Permissions-Policy headers | Added in `next.config.ts` (web) |
| m10 | `fix_plan_within` made a rowless approval a silent no-op | `coalesce(jsonb_typeof(...), '')`; tested |
| note | The service-role key yields every Vault `one_*` secret, the test runner's two factors included (by design, D-059/D-070) | Recorded in D-086; the owner may keep the two factors in Vercel env only |
| note | Any Google account can leave an `auth.users` row in the shared project through the provider's flow | The runbook says to keep Supabase sign-ups disabled or the provider domain-limited |

Sound (probed): the API surface equals `one.api_grants`, all SECURITY DEFINER, no table privilege for any API role,
anon has no schema USAGE; a foreign JWT reaches only `me`, `auth_device_check`, `auth_sign_out`; engineers are refused
on owner keys, P1 disable, fix approvals, others' devices; approvals cannot be widened or redirected; the service role
cannot call `ui_*`, `fix_run`, `proposal_execute`, `one.secret`, nor feed `one:tick` heartbeats; Ask's tools are
read-only and holder-bound; AI writes are contained and double-masked; email HTML is escaped; sign-in codes and cookies
as designed; CSP nonce and strict-dynamic; least privilege of the two roles as smoke asserts; the guards and the
fingerprint refuse every bad statement tried; the tooling cannot reach a remote database by accident.

## Self-healing

| # | Finding | Resolution |
| --- | --- | --- |
| F1 **B** | A mail provider refusing fast turned every alert into `failed` within 3 minutes; ONE-02 and the watchdog counted only pending/sending, so P1s went nowhere while the monitor read ok | Alert, escalation and storm emails are tried 8 times with a growing wait (2…60 min); ONE-02 and `one.watchdog()` count a delivery that failed in the last 6 hours; tested §7a |
| F2 M | A tick blocked on its session lock refreshed the heartbeat first and returned: HB-one:tick, ONE-01 and PLAT-02 stayed green; nothing broke the lock | The heartbeat is written after the lock and the minute; `one.tick_lock_holder()` finds a holder of this role older than 10 minutes and the tick terminates it, noting it in the heartbeat's error; HB-one:tick judges the last finished tick (F13); tested §7b, §7e |
| F3 M | A check or copy killed again on every retry FATALed the cron session and re-paged PLAT-01 for ever | A check stops after three kills (its incident says so and how to reset); a copy halves its batch per kill and stops at three; PLAT-01 ignores a one-tick run a reported kill ended; tested §7c |
| F4 M | Reopens kept `opened_at`, so a burst of reopening P1s was not a storm, and a flapping check paged per flap | `reopened_at`, counted by ONE-STORM; the third reopen goes to the digest with the tag `flapping`; tested §7d |
| F5 M | Nothing watched `one-nightly` | ONE-03 (P2, hourly); the tick re-creates a missing job of its own two; tested §7e |
| F6 M | The settings the app parses had no server-side shape; a typo took every tick route down | Shapes in `settings_check` (with m2); the app parses each probe's settings on its own (web) |
| F7 M | PLAT-04 could not see a request pg_net never answered | PLAT-04 fails on a tick request still queued after 2 minutes |
| F8 m | The sender had no deadline; the route's limit equalled pg_net's timeout | Sender deadline at +25 s, email retries 0 inside the tick, `maxDuration` 50 (web) |
| F9 m | A refusal in the fixes' window start aborted the tick after its app call | Wrapped; the report carries `fixes_window_error` |
| F10 m | No retention for audit, codes, sign-in log; `results_days` 0 accepted; ok results kept 90 days | Two-tier results retention, app-report audit rows 30 days, codes 7 days, sign-in log a year; `retention` validated; tested §7g |
| F11 m | A fix entry missing a field was accepted | `is distinct from` in the shape check |
| F12 m | The nightly's bucket depended on the session time zone | IST date at UTC midnight |
| F13 m | HB-one:tick could never fail | Replaced (F2) |
| F14 m | No settings restore although D-065 promised one | `one.ui_settings_restore`; tested §6d |
| F15 m | Nothing reported "no active owner" | ONE-04 (P1, security); tested §7f |
| F16 m | Failed fix acts and failed AI tasks never reached ONE-01 | Counted with thresholds `fix_failed_acts_max`, `ai_failed_tasks_max` |

Sound: tick and by-hand exclusion, bucket idempotency, kill-then-run-last, delivery claims and keys, storm suppression
for fresh openings, AI leases and budget gates, test leases and purge back-off, the watchdog reading finished ticks,
every key-rotation path ending at the watchdog, IST without DST, API roles without table privilege.

## Efficiency

| # | Finding | Resolution |
| --- | --- | --- |
| 1 H | `ui_incident` read a check's results `order by id desc` (0.7–1.9 s at 90 days) | `order by ran_at desc, id desc` |
| 2 H | The incident page fetched the whole Fixes page; `ui_fixes` probed every action row (1.2 s) | Grouped counts in one pass; index `actions (fix_id, incident_id, step)`; `ui_incident` carries a light `fixes` list |
| 3 H | The funnel tested every event against every pattern (1–3 s) | Patterns matched against distinct (app, type) pairs, then an equality join; index `events (app, type, occurred_at)` |
| 4 M | `one.runs` had no index for ONE-01, PLAT-04, the shell, health and the watchdog | `(kind, started_at)` and `(kind, finished_at)`; fillfactor 70 |
| 5 M | ONE-01's spend used a non-sargable date cast and duplicated `ai_spent_today()` | Uses the function |
| 6 M | `one.audit` had no target index and grew without bound | `(target, id)`; app-report rows pruned after 30 days; mute writes once |
| 7 M | `fix_verify_due` and `app_fixes_claim` scanned every historical run | Bounded to 7 and 2 days; partial index on before rows |
| 8 M | `one.redact` cost 0.85 ms per payload | Left for later (listed in D-087) |
| 9 M | Deliveries died after two tries; watchdog blind (= F1) | Done with F1 |
| 10 M | 97 % of results are ok rows kept 90 days | Two-tier retention (`ok_results_days` 14) |
| 11 M | `ui_overview` evaluated heartbeats 18 times and scanned events per app | One pass each; index `events (app, occurred_at)` |
| 12 M | Two commits per check per tick | Left for later |
| 13–21 L | AI context pretty-printed; app checks' own scans; incidents index; `ui_actions` day cast; events overlap; sender deadline; middleware claims; four rpc wrappers; swallowed causes | Done: incidents index, `ui_actions` window, sender deadline (F8). Left for later: the rest, listed in D-087 |
| dead | `one.record_action` never called | Dropped |

## After the fixes

On the final tree of 24 Oct: the local database test (`scripts/db/local-test.sh`: every migration applied between
catalogue fingerprints, 16 test files and the smoke test, rolled back to nothing, applied and tested again) passes;
the tooling tests (22), the guards (42 files), every generator's drift check (91 checks, settings, tests, docs,
prompts) and the tooling typecheck pass; `npm run check` in `web/` passes (typecheck, lint, format, 219 unit tests);
the click-through passes (152 pages, 20 of 20 writes, 41 RPC functions). Along the way the tests themselves were
corrected where they encoded the old behaviour: a run by hand on an incident just acted on now waits for the verdict,
not the cooldown; an unproven fix hands the app one execution; the storm check's state row is made before it is
killed; the flap test marks deliveries by id, not by time; and `one.tick_lock_holder` now reads the lock the way
pg_locks shows a bigint advisory key (objsubid 1, classid by sign), which the first version did not.
