// Writes a new migration for each generated kind whose sources changed. Usage: npm run gen:sql
// The first generation uses fixed timestamps that slot between the hand-written migrations; later changes get the
// current UTC timestamp (or one after the newest migration) so they apply after everything that exists.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { GENERATORS, latestRecordedHash, type GeneratedKind } from "@/lib/codegen/sql";

const dir = join(import.meta.dirname, "..", "supabase", "migrations");
const files = readdirSync(dir)
  .filter((f) => f.endsWith(".sql"))
  .map((name) => ({ name, content: readFileSync(join(dir, name), "utf8") }));
const firstSlot: Record<GeneratedKind, string> = {
  "permission-matrix": "20261017000300",
  "settings-definitions": "20261017000500",
  "comp-config-schema": "20261018000650",
  "deal-presets": "20261018000710",
  "clause-library": "20261019000110",
};

/** The current UTC time, or one second after the newest migration if that is later, so new files always sort last. */
function nextStamp(): string {
  const now = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14);
  const newest =
    files
      .map((f) => f.name.slice(0, 14))
      .sort()
      .at(-1) ?? "0";
  return now > newest ? now : (BigInt(newest) + 1n).toString();
}

for (const [kind, build] of Object.entries(GENERATORS) as [GeneratedKind, () => { sql: string; hash: string }][]) {
  const { sql, hash } = build();
  const recorded = latestRecordedHash(kind, files);
  if (recorded === hash) {
    console.info(`${kind}: up to date`);
    continue;
  }
  const stamp = recorded === null ? firstSlot[kind] : nextStamp();
  const name = `${stamp}_inf_${kind.replace(/-/g, "_")}.sql`;
  writeFileSync(join(dir, name), sql);
  console.info(`${kind}: wrote ${name}`);
}
