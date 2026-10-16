// Runs the pgTAP files in supabase/tests against the LOCAL database with psql and checks the TAP output.
// No pg_prove image needed. Every file wraps itself in begin … rollback, so nothing persists.
// Usage: node scripts/test-db.mjs [filter]      (DB URL from LOCAL_DB_URL, default the local stack)
import { spawnSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { join } from "node:path";

const dbUrl = process.env.LOCAL_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54422/postgres";
if (!/@(127\.0\.0\.1|localhost|postgres|db)(:\d+)?\//.test(dbUrl)) {
  console.error("Refusing to run tests against a non-local database.");
  process.exit(2);
}
const dir = join(import.meta.dirname, "..", "supabase", "tests");
const filter = process.argv[2];
const files = readdirSync(dir).filter((f) => f.endsWith(".sql") && (!filter || f.includes(filter))).sort();

let failedFiles = 0;
let total = 0;
for (const file of files) {
  const r = spawnSync("psql", [dbUrl, "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-f", file], { cwd: dir, encoding: "utf8" });
  const lines = (r.stdout ?? "").split("\n").map((l) => l.trim()).filter(Boolean);
  const plan = lines.find((l) => /^1\.\.\d+$/.test(l));
  const planned = plan ? Number(plan.split("..")[1]) : NaN;
  const oks = lines.filter((l) => /^ok \d+/.test(l)).length;
  const notOks = lines.filter((l) => /^not ok \d+/.test(l));
  const ok = r.status === 0 && notOks.length === 0 && oks === planned;
  total += oks;
  if (!ok) {
    failedFiles++;
    console.error(`✗ ${file}: ${oks}/${Number.isNaN(planned) ? "?" : planned} passed`);
    for (const l of lines.filter((x) => /^not ok|^#/.test(x))) console.error(`    ${l}`);
    if (r.stderr) console.error(r.stderr.split("\n").map((l) => `    ${l}`).join("\n"));
  } else {
    console.info(`✓ ${file}: ${oks} tests`);
  }
}
console.info(`\n${files.length - failedFiles}/${files.length} files passed, ${total} assertions.`);
process.exit(failedFiles ? 1 : 0);
