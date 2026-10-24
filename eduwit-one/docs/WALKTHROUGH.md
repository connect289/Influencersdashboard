# Eduwit One — a 30-minute walkthrough

A checklist to follow alone, signed in as the owner at `https://one.eduwit.in`, once the database is applied and the
app deployed (the "Before the first walkthrough" list at the end says what that takes). Tick each box as you go. Times
are a guide. Nothing here changes an app: every write on these pages stays in Eduwit One, except a fix proposal you
approve (step 6).

## 1. Sign in (2 minutes)

- [ ] Open `https://one.eduwit.in`, choose Google, use your `@eduwit.in` account.
- [ ] Enter the 6-digit code from your inbox. Tick "Trust this browser for 30 days" only on your own computer.
- [ ] The top bar shows your email and "owner". If you see "pending", your row in Settings → Users is missing or
      inactive (see "Locked out" in `RUNBOOK.md`).

## 2. The overview (3 minutes)

- [ ] Read the banners at the top of every page. Each says what needs you now: open P1s, unacknowledged incidents,
      maintenance in force, the fixes' observation window.
- [ ] One tile per app: green, amber or red, with its open incidents. Click a red one: it lists that app's incidents.
- [ ] No red banner saying "The minute tick last finished … ago". If there is one, checks and alerts are not running:
      `RUNBOOK.md` → Alerts, ONE-02, and "The external watchdog".

## 3. One incident, end to end (5 minutes)

- [ ] Incidents → open the newest P1 (or any open one).
- [ ] "Evidence": what the check saw on its last run. `status: error` or `source_missing` means the check could not run.
- [ ] "The check": what it watches, how often, and its rule. "Fixes" under it: which fixes are tried on this check,
      on or off. Press **Dry run now**: the answer says what the fix would do (it changes nothing).
- [ ] "AI notes" (once the AI key is set): a summary and a likely cause. Advice only.
- [ ] Press **Acknowledge**: the reminders stop. Resolve only once it is fixed, with a note.
- [ ] Phone: open the same page on your phone; it fits the screen.

## 4. The checks (3 minutes)

- [ ] Settings → Checks: every check with its switch, severity and cadence, each change with a reason.
- [ ] Its rule (SQL) is on any of its incidents' pages; `docs/CHECKS.md` in the repository lists them all.
- [ ] Do not switch off a P1 check to silence it; mute it instead (step 8) or fix the cause.

## 5. The fixes (6 minutes)

- [ ] Settings → Fixes. The banner says whether the 14-day observation window is running and when it ends.
- [ ] For each fix: when it is tried, what it does, what rights it has ("granted" means the database holds exactly
      those), how to undo it, and its dry runs.
- [ ] Three cannot act on their own (D-080): FIX-OUTBOX-W2 and FIX-CACHE-W2 only propose a change to Witty;
      FIX-OUTBOX-B2B opens a proposal that runs when you approve it.
- [ ] After the window: open a fix's "Switch and limits", read its dry runs first, and switch it on only if you would
      have agreed with every one. Give a reason; it is versioned.
- [ ] Actions (left menu): every run, real or dry, as it happens: "dry run", "about to act", "acted", "did nothing"
      (and why), "verified: held", "did not hold" or "unverified". Filter by fix. An incident marked "stopped" on
      Settings → Fixes had a run that did not hold: the fix no longer runs there by itself.

## 6. Proposals (4 minutes)

- [ ] Proposals: everything that needs a person, newest first, with its risk and who may approve it.
- [ ] Open a builder proposal: "Why", "The exact change", "Evidence". Approving records your decision; the change is
      made in the app named, not by Eduwit One.
- [ ] A proposal from a fix (source `check`) carries an amber note saying what approving does (B2B's own function
      under your session, a run with the fixer's rights, or a run queued for the app) and on which rows. To approve
      fewer rows, remove them from the change before approving; you cannot add any. If it ran, the rows' state shows
      on the page 10 minutes later; if nothing ran, the page says why.
- [ ] Reject needs a reason; snooze brings it back after the days you choose.

## 7. Tests, brief and Ask (4 minutes)

- [ ] Tests: the eleven synthetic tests, what each waits for (Setup items), last runs and step timings.
- [ ] Brief: yesterday's morning brief (also emailed at 08:00 IST) and the numbers it was written from, fixes
      included.
- [ ] Ask: type a question such as "Which checks failed most this week?". The answer lists the tools it used. Never
      type a student's name or phone.

## 8. Settings that matter (3 minutes)

- [ ] Settings → Setup: each credential, who provides it and whether it is validated. To rotate one, paste the new
      value and validate (`RUNBOOK.md` → Rotating a secret).
- [ ] Settings → Maintenance: mute an app or a check for a planned change, with a duration and a reason.
- [ ] Settings → Users: who can sign in. "Sign out everywhere" for a lost laptop.
- [ ] Audit: every change with who, when and the request id; export as CSV.

## 9. If you are paged (on the way out, no time)

1. Open the link in the email; acknowledge.
2. Read the evidence and the check; look at the app's own screen.
3. Fix it in the app, or mute with a reason while you work; resolve with a note.
4. No email but the watchdog paged: Supabase, pg_cron or Vercel is down. `RUNBOOK.md` → "The external watchdog".

## Before the first walkthrough

What has to happen once, in this order (each is the owner's; `docs/PHASES.md` lists them with their state):

1. Rehearse every migration on staging and commit the `REHEARSAL PASSED` row (`RUNBOOK-database.md` §2).
2. Dump production, then apply every migration within 24 hours (`RUNBOOK-database.md` §3, §4). The first tick after
   the apply starts the fixes' 14-day observation window by itself.
3. Expose schema `one` in the Supabase API (Setup item `supabase_api_schema`).
4. Deploy the app on Vercel Pro with its four environment values (Setup item `one_app_env`) and add the sign-in
   callback URL.
5. Fill the Setup items, starting with `email` (alerts) and `ai_key` (the AI), then the test identities.
6. Set up the UptimeRobot watchdog (`RUNBOOK.md`).
