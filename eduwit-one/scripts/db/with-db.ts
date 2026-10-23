// Runs a command against a database named by an environment variable holding its URL:
//   node scripts/db/with-db.ts <ONE_STAGING_DB_URL|ONE_PROD_DB_URL> <command> [args...]
// The command gets libpq's PG* variables (password in PGPASSWORD) and ONE_DB_TARGET=staging|production. The URL is
// never printed. A staging variable that points at production, or a production variable that points elsewhere, is
// refused, so a pasted URL in the wrong variable cannot send a rehearsal to production.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { pgEnv, targetOf } from "./pg-env.ts";

const expected = { ONE_STAGING_DB_URL: "staging", ONE_PROD_DB_URL: "production" } as const;
type VarName = keyof typeof expected;

const [name, command, ...args] = process.argv.slice(2);
if (!name || !command || !(name in expected)) {
  console.error(`usage: with-db.ts <${Object.keys(expected).join("|")}> <command> [args...]`);
  process.exit(2);
}
const varName = name as VarName;
const url = process.env[varName]?.trim();
if (!url) {
  console.error(`${varName} is not set in this environment`);
  process.exit(2);
}
const env = pgEnv(url);
if (!env) {
  console.error(`${varName} is not a postgres:// URL`);
  process.exit(2);
}
const defaults = JSON.parse(readFileSync(new URL("../../config/defaults.json", import.meta.url), "utf8")) as {
  supabase: { production_ref: string; staging_ref: string };
};
const target = targetOf(url, defaults.supabase);
if (target !== expected[varName]) {
  console.error(`refused: ${varName} reaches ${target}, expected ${expected[varName]}`);
  process.exit(2);
}
const run = spawnSync(command, args, { stdio: "inherit", env: { ...process.env, ...env, ONE_DB_TARGET: target } });
process.exit(run.status ?? 1);
