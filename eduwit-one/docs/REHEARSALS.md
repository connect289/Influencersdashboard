# Eduwit One — rehearsal record

One row per passed rehearsal. `scripts/db/rehearse.sh` appends a row when the full cycle passes on staging (apply, smoke,
rollback leaving nothing, apply, smoke). `scripts/db/apply.sh` refuses to touch production unless the current migration
set's hash (`node scripts/db/guards.ts --hash`) has a row here. Rows are never edited.

| When (UTC) | Target | Migration set (sha256) | Result | By |
| --- | --- | --- | --- | --- |
| 2026-10-24T15:41Z | staging | `60b7dbb4f2ae72d46e15ba0b4b08ba87157006d8293a510adaad2920b7cac6c0` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
