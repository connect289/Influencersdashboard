// Prints one migration (or rollback) file as the single-session payload the rehearsal and the apply run: one
// transaction, the two catalogue fingerprints around the file, and the refusal when anything outside schema one
// changed (scripts/db/app-fingerprint.sql, fp-before.sql, fp-after.sql). psql's \set and \ir are expanded, so the
// output can go through any executor that takes a plain SQL string, such as Supabase's Management API (with-api.ts).
//   node scripts/db/wrap.ts <file.sql> [--discard-history]   --discard-history: a rollback in a rehearsal (0006, m8)
import { readFileSync } from "node:fs";
import { basename } from "node:path";

const here = new URL("./", import.meta.url);
const fingerprint = readFileSync(new URL("app-fingerprint.sql", here), "utf8");
if (fingerprint.split(":'fp_phase'").length !== 2 || !fingerprint.trimEnd().endsWith("\\gset fp_")) {
  console.error("wrap.ts: app-fingerprint.sql no longer has the shape this wrapper expands");
  process.exit(2);
}
/** app-fingerprint.sql with psql's variable and \gset expanded for one phase. */
export function fingerprintFor(phase: "before" | "after"): string {
  const t = fingerprint.replace(":'fp_phase'", `'${phase}'`).trimEnd();
  return `${t.slice(0, -"\\gset fp_".length).trimEnd()};\n`;
}
/** The check fp-after.sql runs after the fingerprint: everything in it but psql's meta-commands and comments. */
export function afterCheck(): string {
  const lines = readFileSync(new URL("fp-after.sql", here), "utf8")
    .split("\n")
    .filter((l) => !l.startsWith("\\") && !l.startsWith("--"));
  return `${lines.join("\n").trim()}\n`;
}
export function wrap(path: string, opts: { discardHistory?: boolean } = {}): string {
  let body = readFileSync(path, "utf8");
  if (!body.endsWith("\n")) body += "\n";
  return [
    "begin;\n",
    "set local lock_timeout = '5s'; set local statement_timeout = '5min';\n",
    opts.discardHistory ? "set local one.rollback_discards_history = 'on';\n" : "",
    "-- fp-before.sql, expanded for a single-session run\n",
    fingerprintFor("before"),
    `-- ${basename(path)}\n`,
    body,
    "-- fp-after.sql, expanded for a single-session run\n",
    fingerprintFor("after"),
    afterCheck(),
    "commit;\n",
  ].join("");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const file = args.find((a) => !a.startsWith("--"));
  if (!file) {
    console.error("usage: node scripts/db/wrap.ts <file.sql> [--discard-history]");
    process.exit(2);
  }
  process.stdout.write(wrap(file, { discardHistory: args.includes("--discard-history") }));
}
