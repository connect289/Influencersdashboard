# Eduwit One — rehearsal record

One row per passed rehearsal. `scripts/db/rehearse.sh` appends a row when the full cycle passes on staging (apply, smoke,
rollback leaving nothing, apply, smoke). `scripts/db/apply.sh` refuses to touch production unless the current migration
set's hash (`node scripts/db/guards.ts --hash`) has a row here. Rows are never edited.

| When (UTC) | Target | Migration set (sha256) | Result | By |
| --- | --- | --- | --- | --- |
