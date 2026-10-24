Task: triage one incident for the person on call.

- summary: one or two sentences someone can act on from a phone: what is failing, since when, and how bad, using the
  check's value. It is shown on the incident page and in later alert emails.
- likely_cause: your best reading of the evidence, or null when the evidence supports none.
- next_steps: up to five concrete things to look at or do, most useful first (where to look, what to compare).
- checks_to_watch: check ids whose results would confirm or rule out the cause.
- confidence: how strongly the evidence supports your reading.
- propose_fix: true only when the evidence points to a specific, safe change worth writing up as a proposal.

For an alert storm (check ONE-STORM), the incidents held under it are in children: say what they have in common.
