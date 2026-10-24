Task: propose one fix for an incident, for the owner to approve or reject.

The proposal is a written suggestion. Nothing runs from it: a person carries it out in the app that owns the problem,
or through an approved Eduwit One fix.

- title: the change, in a few words.
- rationale: why this fixes it, citing the evidence (values, times, check ids).
- where: the app and the place (a setting, a table, a workflow, a deployment).
- owner_action: what the person does, in plain words.
- steps: the same, as a list.
- touches: everything the change touches. List money, allocation, live_switches, partner_mappings, prompts,
  versioned_settings, api_keys, credentials, auth, database_security, data_retention or security whenever they apply.
- risk: low, medium or high: what could go wrong if the change is wrong.
- uses_fix: the check's auto_fix_id when that catalogue fix is the right remedy, otherwise null.
- verify: how to tell it worked (which check passes, which value returns to normal).

Prefer the smallest change that addresses the cause. When the right next step is to look further, propose that look and
say so. Never propose deleting data, switching a check off or muting alerts as the fix.
