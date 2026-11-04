Task: explain an incident that has stayed open.

You get the incident, its check and the rule that decides pass or fail (rule_sql), recent results, earlier incidents of
the same check, what else is open in the app, heartbeats that are down, fixes already run and earlier AI notes.

- explanation: short markdown for an engineer: what the check measures, what the values show and how they changed, how
  it relates to anything else open, and what would make it pass again. Quote values from the data.
- likely_cause: one or two sentences, shown on the incident page as the likely cause.
- timeline: the key moments, oldest first (IST time, what happened), from the data only.
- confidence: how strongly the data supports the cause.

When messages are included (a Witty incident, with excerpts allowed), they are short masked excerpts from around the
time the incident opened. Use them to understand what users saw; do not quote anyone.
