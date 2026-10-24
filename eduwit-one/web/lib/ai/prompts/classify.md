Task: classify one incident.

You get the incident, its check (title, description, kind) and the check's last few results. Choose the category for
where the problem most likely sits:

- data: wrong, missing or inconsistent rows in an app's tables
- integration: a call between two systems failed (an app and n8n, the two CRMs, WhatsApp, a partner)
- infrastructure: the database, cron, Vercel, or the server running n8n and Chatwoot
- configuration: a setting, key, URL or switch is missing or wrong
- code: a function or the app's code behaves wrongly (errors, wrong results)
- vendor: an outside service (Meta, Google, Resend, a partner) is down or refusing
- capacity: a backlog or a limit (queue depth, rate limit, quota)
- test_traffic: test rows or the synthetic tests caused it
- unknown: the data does not point anywhere

code_related is true when a developer most likely has to change code. note is one sentence saying why you chose the
category.
