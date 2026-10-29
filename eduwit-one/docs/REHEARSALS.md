# Eduwit One — rehearsal record

One row per passed rehearsal. `scripts/db/rehearse.sh` appends a row when the full cycle passes on staging (apply, smoke,
rollback leaving nothing, apply, smoke). `scripts/db/apply.sh` refuses to touch production unless the current migration
set's hash (`node scripts/db/guards.ts --hash`) has a row here. Rows are never edited.

| When (UTC)        | Target  | Migration set (sha256)                                             | Result           | By                         |
| ----------------- | ------- | ------------------------------------------------------------------ | ---------------- | -------------------------- |
| 2026-10-24T15:41Z | staging | `60b7dbb4f2ae72d46e15ba0b4b08ba87157006d8293a510adaad2920b7cac6c0` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-10-29T05:53Z | staging | `5a5d4be69c48a68b88939f64be5a9124c0363afb2b4ef1d54261ce6707a8557d` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-10-29T10:32Z | staging | `d4c77dff9eefbc8d8fad0e817fb696399caf093c5f3aec0680f19a94d0d10949` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-10-29T11:21Z | staging | `37e6683604ad996604c158d35d8123c45e2f775a3cc6c2e1070b0b5f4861c546` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-10-29T12:45Z | staging | `6cd9d1210b8116d8646a511c784f022762dce1f863752542805c41b2f927e461` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
