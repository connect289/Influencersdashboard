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
| 2026-10-30T09:46Z | staging | `e884abe082b8be76927554f515f57b7c2e2d1332f44d9c4d2501b3e1874c8210` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-10-30T10:27Z | staging | `1853354adde14c1f642c86b09ffe02cd65508ca38cb57207c9f8712b66e0568b` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-10-30T22:27Z | staging | `7e1fd5ce722353e1fee871b8e42c302494089dc4e1daebf22efe827f5120b808` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-10-30T23:08Z | staging | `f22eca31951a853646461440300048ed270168fbcdcdc82c74c0affb759e2d77` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-10-31T03:47Z | staging | `fd3fb19c78d287f9b3a8efa3fd5ad79424223c5aaa6013cde1218aafb26952ab` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-01T22:05Z | staging | `71a140f5ee3d5970d200cc0f6015a8d301050d98973ff448e1101f1397760608` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-01T22:44Z | staging | `d20923f57b3dd873396db9509b36a400f588ca8b80fd216429217fd53f7489da` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-02T10:29Z | staging | `588cee7e0f3fd168a79de9c5f801b4ef6ecdfa330bc798ec6a54d1ad6c0fa5f3` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-03T05:12Z | staging | `1c775e4d8db17e8857934d4ef84c17b49176d27e4ef93d436ff29bd6d545f4c9` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-03T15:46Z | staging | `d0991cdaefe61c4aae709991465b1003d1bbff93cbaa1c6ddc680b61e758dca5` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-04T02:39Z | staging | `ee27ac4733e23823f035eaa51110f68160ccb23fd0ddf5ee0610c3c55e7b8b40` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-11T08:48Z | staging | `668e96f5ab5f3b7f82846114721e2c5ca88bd9d4b5f287dd112f6234ba81fed9` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-13T12:14Z | staging | `d933ee64fe6d1329c1f3500c2ee9356da21321d616eabd37082d26f4b5667442` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-13T23:24Z | staging | `b38c97c03f9de97b0177b988f27c4c0a95f7d168d6b0536d1ab80c8bc99a5682` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
| 2026-11-14T04:45Z | staging | `ca6509062d45b72cca6a4d43868c22e16f5437287ac77c8cf1e467c594472f4a` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |
