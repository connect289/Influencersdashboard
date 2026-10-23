// node --test scripts/db/gen-checks.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { catalogue, loadChecks, migration, parseSource } from "./gen-checks.ts";
import { forTrial } from "./try-checks.ts";

const block = (extra: string, sql: string) =>
  `-- check: T-1\n-- app: platform\n-- kind: sql\n-- severity: P2\n-- cadence_s: 60\n-- title: t\n-- description: d\n${extra}${sql}\n`;

test("0006 and CHECKS.md are generated from the current sources", () => {
  const checks = loadChecks();
  assert.equal(readFileSync(new URL("../../supabase/migrations/0006_seed_checks.sql", import.meta.url), "utf8"), migration(checks));
  assert.equal(readFileSync(new URL("../../docs/CHECKS.md", import.meta.url), "utf8"), catalogue(checks));
});

test("every check in the specification's catalogue is seeded", () => {
  const ids = new Set(loadChecks().map((c) => c.id));
  const spec = ["PLAT-01", "PLAT-02", "PLAT-03", "PLAT-04", "PLAT-05", "PLAT-06", "PLAT-07", "PLAT-08", "PLAT-09",
    ...Array.from({ length: 9 }, (_, i) => `WITTY-0${i + 1}`), ...Array.from({ length: 14 }, (_, i) => `B2B-${String(i + 1).padStart(2, "0")}`),
    ...Array.from({ length: 10 }, (_, i) => `B2C-${String(i + 1).padStart(2, "0")}`), ...Array.from({ length: 7 }, (_, i) => `WEB-0${i + 1}`),
    "INF-01", "INF-02", "INF-03", "INF-04", "CAT-01", "CAT-02", "CAT-03", "CAT-04", ...Array.from({ length: 7 }, (_, i) => `INT-0${i + 1}`), "ONE-01"];
  assert.deepEqual(spec.filter((id) => !ids.has(id)), []);
  assert.ok([...ids].some((id) => id.startsWith("HB-")), "heartbeat checks seeded");
});

test("a check that is off says why, in the Setup vocabulary", () => {
  for (const c of loadChecks().filter((x) => x.disabled)) assert.match(c.disabled ?? "", /^(setup|blocked|owner|builder):/, c.id);
});

test("check SQL that could change data, chain statements or hide text is refused", () => {
  assert.throws(() => parseSource("t", block("", "with d as (delete from x returning 1) select true as ok, null::jsonb as value")), /forbidden word "delete"/);
  assert.throws(() => parseSource("t", block("", "select true as ok, null::jsonb as value; select 1")), /;/);
  assert.throws(() => parseSource("t", block("", "select true as ok -- note\n, null::jsonb as value")), /no comments/);
  assert.throws(() => parseSource("t", block("", "select decrypted_secret is null as ok, null::jsonb as value from vault.decrypted_secrets")), /secret values/);
  assert.throws(() => parseSource("t", block("", "values (true)")), /select or with/);
  assert.throws(() => parseSource("t", block("-- kind: http\n", "select 1")), /bad header|carry no SQL/);
  assert.equal(parseSource("t", block("", "select true as ok, '{}'::jsonb as value from public.t where updated_at > now()"))[0]?.sql?.startsWith("select"), true);
});

test("the production trial replaces every one.* reference", () => {
  for (const c of loadChecks().filter((x) => x.sql)) assert.doesNotMatch(forTrial(c.sql as string), /\bone\./, c.id);
});
