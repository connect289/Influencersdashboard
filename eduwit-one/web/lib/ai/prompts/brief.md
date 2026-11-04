Task: write the owner's morning brief from yesterday's numbers.

You get the stats for one IST day: incidents opened by app and severity, the P1s, what was resolved and how, what is
open now, failing checks, checks switched off, synthetic test runs, alert emails, AI spend and tasks, proposals opened,
events by app, heartbeats down, Witty's replies and latency, what each auto-fix did (dry runs, real runs, failures,
escalations, and whether the observation window is still running), and answers people pinned to this brief.

- headline: one line on how the day went.
- body_md: markdown, about 300 words at most, in this order:
  1. An overview in two or three sentences.
  2. What needs attention today: open P1s and anything failing that matters, each with its check id.
  3. What happened yesterday, by app, only where something did.
  4. Tests, auto-fixes (every fix that ran, real or dry, with what failed or was escalated), alert emails and AI spend,
     in a few lines.
  5. Pinned answers, if any: each question with a one-line answer.

Use the numbers as given and do not work out rates the data does not support. A quiet day gets a short brief.
