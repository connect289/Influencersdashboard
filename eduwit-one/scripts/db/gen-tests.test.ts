// node --test scripts/db/gen-tests.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { build, type TestEntry, validate } from "./gen-tests.ts";

const read = (p: string) => readFileSync(new URL(`../../${p}`, import.meta.url), "utf8");

test("0015 and TESTS.md are generated from the current catalogue", () => {
  const { sql, md } = build();
  assert.equal(read("supabase/migrations/0015_seed_tests.sql"), sql);
  assert.equal(read("docs/TESTS.md"), md);
});

test("every test in the specification's catalogue is seeded", () => {
  const ids = (JSON.parse(read("config/tests.json")).tests as TestEntry[]).map((t) => t.id).sort();
  assert.deepEqual(ids, [
    "T-ALERT", "T-B2B-INTAKE", "T-B2B-PUSH", "T-B2C-NURTURE", "T-HANDOFF", "T-INFLUENCER", "T-WEB-ADVISOR",
    "T-WEB-CATALOG", "T-WEB-ENQUIRY", "T-WITTY-QUALIFY", "T-WITTY-TURN",
  ]);
});

test("a test needs real Setup items, a readable schedule and steps that fit", () => {
  const t: TestEntry = {
    id: "T-X", app: "one", title: "t", seam: "s", description: "d", severity: "P2", timeout_s: 120, needs: ["email"],
    steps: [{ key: "a", title: "A", timeout_s: 30 }], safety: "s", purge: "p",
  };
  const items = new Set(["email"]);
  assert.doesNotThrow(() => validate([t], items, { "T-X": "0 * * * *" }));
  assert.throws(() => validate([{ ...t, needs: ["nope"] }], items, { "T-X": "0 * * * *" }), /not a Setup item/);
  assert.throws(() => validate([t], items, { "T-X": "61 * * * *" }), /schedule/);
  assert.throws(() => validate([t], items, {}), /no schedule/);
  assert.throws(() => validate([{ ...t, steps: [{ key: "a", title: "A", timeout_s: 500 }] }], items, { "T-X": "0 * * * *" }), /timeout/);
  assert.throws(() => validate([{ ...t, steps: [t.steps[0] ?? { key: "a", title: "A", timeout_s: 1 }, { key: "a", title: "B", timeout_s: 1 }] }], items, { "T-X": "0 * * * *" }), /repeated/);
});
