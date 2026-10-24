Task: an incident was resolved as fixed. Decide whether a synthetic test should guard against it coming back, and if
so, describe one.

Synthetic tests run end to end through the apps' own APIs with test identities only (harness phones starting 9100009 or
910000, the test partner, test users), and a purge soft-deletes what they create. You get the incident, its check and
rule, its history and the existing tests.

- needed: false when an existing test or the check itself already covers it (say which in the rationale).
- rationale: why a test is or is not needed.
- risk: what could go wrong when the test runs (it acts in production, with test identities).
- test: null when not needed; otherwise its title, app, trigger (a schedule or an event), steps (each with what it
  expects to see), safety (how it stays on test identities and never reaches a real student, partner or inbox) and
  purge (what it leaves behind and how that is removed).
