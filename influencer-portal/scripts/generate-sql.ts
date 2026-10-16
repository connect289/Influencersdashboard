// Writes a new migration for each generated kind whose sources changed. Usage: npm run gen:sql
// The first generation uses fixed timestamps that slot between the hand-written migrations; later changes get the
// current UTC timestamp so they apply after everything that exists.
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
};

function utcStamp(): string {
  return new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14);
}

for (const [kind, build] of Object.entries(GENERATORS) as [GeneratedKind, () => { sql: string; hash: string }][]) {
  const { sql, hash } = build();
  const recorded = latestRecordedHash(kind, files);
  if (recorded === hash) {
    console.info(`${kind}: up to date`);
    continue;
  }
  const stamp = recorded === null ? firstSlot[kind] : utcStamp();
  const name = `${stamp}_inf_${kind.replace(/-/g, "_")}.sql`;
  writeFileSync(join(dir, name), sql);
  console.info(`${kind}: wrote ${name}`);
}
