// node --test scripts/db/gen-checks.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { catalogue, LATE_APPS, lateMigration, loadChecks, migration, parseSource } from "./gen-checks.ts";
import { forTrial } from "./try-checks.ts";

const block = (extra: string, sql: string) =>
  `-- check: T-1\n-- app: platform\n-- kind: sql\n-- severity: P2\n-- cadence_s: 60\n-- title: t\n-- description: d\n${extra}${sql}\n`;

const migrationText = (file: string) =>
  readFileSync(new URL(`../../supabase/migrations/${file}`, import.meta.url), "utf8");

test("0006, the late apps' seeds and CHECKS.md are generated from the current sources", () => {
  const checks = loadChecks();
  assert.equal(migrationText("0006_seed_checks.sql"), migration(checks));
  for (const [app, late] of Object.entries(LATE_APPS))
    assert.equal(migrationText(late.file), lateMigration(checks, app), late.file);
  assert.equal(readFileSync(new URL("../../docs/CHECKS.md", import.meta.url), "utf8"), catalogue(checks));
});

test("an app registered after 0002 is seeded by its own file, right after the migration that registers it (D-096)", () => {
  const checks = loadChecks();
  const files = readdirSync(new URL("../../supabase/migrations/", import.meta.url));
  const forward = files.filter((f) => /^\d{4}_.*\.sql$/.test(f) && !f.endsWith(".rollback.sql")).sort();
  const base = /check \(key in \(([^)]*)\)\)/.exec(migrationText("0002_core_tables.sql"))?.[1] ?? "";
  for (const [app, late] of Object.entries(LATE_APPS)) {
    assert.ok(!base.includes(`'${app}'`), `${app} is not one of 0002's keys`);
    assert.equal(forward.indexOf(late.file), forward.indexOf(late.after) + 1, `${late.file} follows ${late.after}`);
    assert.match(
      migrationText(late.after),
      new RegExp(`add constraint apps_key_check\\s+check \\(key in \\([^)]*'${app}'`),
      `${late.after} adds the key`,
    );
    assert.ok(files.includes(late.file.replace(/\.sql$/, ".rollback.sql")), `${late.file} has a rollback`);
    assert.ok(!migration(checks).includes(`'app', '${app}'`), `0006 seeds no ${app} check`);
    assert.ok(
      checks.filter((c) => c.app === app).every((c) => lateMigration(checks, app).includes(`'id', '${c.id}'`)),
      `${late.file} seeds every ${app} check`,
    );
  }
});

test("Eduwit Scout's checks ship off until its Setup item is validated, and 0022 carries that item as config has it", () => {
  const ce = loadChecks().filter((c) => c.app === "catalogue_engine");
  assert.deepEqual(
    ce.map((c) => c.id),
    ["CE-01", "CE-02", "CE-03", "CE-04", "CE-05"],
  );
  for (const c of ce) assert.equal(c.disabled, "setup:catalogue_engine", c.id);
  const items = (
    JSON.parse(readFileSync(new URL("../../config/setup-items.json", import.meta.url), "utf8")) as {
      items: Array<{ id: string }>;
    }
  ).items;
  assert.equal(items.at(-1)?.id, "catalogue_engine", "the item is the catalogue's last, where 0022 appends it");
  const copy = /\$item\$(.*?)\$item\$/s.exec(migrationText("0022_catalogue_engine.sql"))?.[1] ?? "{}";
  assert.deepEqual(JSON.parse(copy), items.at(-1));
});

test("every check in the specification's catalogue is seeded", () => {
  const ids = new Set(loadChecks().map((c) => c.id));
  const spec = [
    "PLAT-01",
    "PLAT-02",
    "PLAT-03",
    "PLAT-04",
    "PLAT-05",
    "PLAT-06",
    "PLAT-07",
    "PLAT-08",
    "PLAT-09",
    ...Array.from({ length: 9 }, (_, i) => `WITTY-0${i + 1}`),
    ...Array.from({ length: 14 }, (_, i) => `B2B-${String(i + 1).padStart(2, "0")}`),
    ...Array.from({ length: 10 }, (_, i) => `B2C-${String(i + 1).padStart(2, "0")}`),
    ...Array.from({ length: 7 }, (_, i) => `WEB-0${i + 1}`),
    "INF-01",
    "INF-02",
    "INF-03",
    "INF-04",
    "CAT-01",
    "CAT-02",
    "CAT-03",
    "CAT-04",
    ...Array.from({ length: 7 }, (_, i) => `INT-0${i + 1}`),
    "ONE-01",
  ];
  assert.deepEqual(
    spec.filter((id) => !ids.has(id)),
    [],
  );
  assert.ok(
    [...ids].some((id) => id.startsWith("HB-")),
    "heartbeat checks seeded",
  );
});

test("a check that is off says why, in the Setup vocabulary", () => {
  for (const c of loadChecks().filter((x) => x.disabled))
    assert.match(c.disabled ?? "", /^(setup|blocked|owner|builder):/, c.id);
});

test("check SQL that could change data, chain statements or hide text is refused", () => {
  assert.throws(
    () => parseSource("t", block("", "with d as (delete from x returning 1) select true as ok, null::jsonb as value")),
    /forbidden word "delete"/,
  );
  assert.throws(() => parseSource("t", block("", "select true as ok, null::jsonb as value; select 1")), /;/);
  assert.throws(() => parseSource("t", block("", "select true as ok -- note\n, null::jsonb as value")), /no comments/);
  assert.throws(
    () =>
      parseSource(
        "t",
        block("", "select decrypted_secret is null as ok, null::jsonb as value from vault.decrypted_secrets"),
      ),
    /secret values/,
  );
  assert.throws(() => parseSource("t", block("", "values (true)")), /select or with/);
  assert.throws(() => parseSource("t", block("-- kind: http\n", "select 1")), /bad header|carry no SQL/);
  assert.equal(
    parseSource(
      "t",
      block("", "select true as ok, '{}'::jsonb as value from public.t where updated_at > now()"),
    )[0]?.sql?.startsWith("select"),
    true,
  );
});

test("the production trial replaces every one.* reference", () => {
  for (const c of loadChecks().filter((x) => x.sql)) assert.doesNotMatch(forTrial(c.sql as string), /\bone\./, c.id);
});

test("0028 re-seeds ONE-01 with the statement 0006 carries (D-102)", () => {
  const stmt = (text: string) => {
    const lines = text.split("\n");
    const i = lines.findIndex((l) => l.trim() === "'id', 'ONE-01',");
    let a = i;
    while (!lines[a].startsWith("select one.seed_check(")) a--;
    let b = i;
    while (!lines[b].trimEnd().endsWith("));")) b++;
    return lines.slice(a, b + 1).join("\n");
  };
  assert.equal(stmt(migrationText("0028_parked_checks_recover.sql")), stmt(migrationText("0006_seed_checks.sql")));
});

test("0029 seeds PLAT-10 with the statement 0006 carries (D-103)", () => {
  const stmt = (text: string) => {
    const lines = text.split("\n");
    const i = lines.findIndex((l) => l.trim() === "'id', 'PLAT-10',");
    let a = i;
    while (!lines[a].startsWith("select one.seed_check(")) a--;
    let b = i;
    while (!lines[b].trimEnd().endsWith("));")) b++;
    return lines.slice(a, b + 1).join("\n");
  };
  assert.equal(stmt(migrationText("0029_storage_within_plan.sql")), stmt(migrationText("0006_seed_checks.sql")));
});
