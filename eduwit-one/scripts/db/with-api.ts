// Runs one SQL text against a Supabase project through the Management API (POST /v1/projects/<ref>/database/query),
// the executor the Supabase connector uses, as the postgres role. For a machine that has HTTPS to api.supabase.com but
// no Postgres connection (D-090). The project is named by target, never by ref or URL, and resolved from
// config/defaults.json; the personal access token comes from SUPABASE_ACCESS_TOKEN and is never printed: it reaches
// curl through a config on stdin, not through argv. The rows come back on stdout as JSON; an error's message goes to
// stderr. Session settings do not survive between calls, so a payload carries its own transaction (scripts/db/wrap.ts).
//   node scripts/db/with-api.ts <staging|production> <file.sql>
//   node scripts/db/with-api.ts <staging|production> --sql "<statement>"
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const refs = (
  JSON.parse(readFileSync(new URL("../../config/defaults.json", import.meta.url), "utf8")) as {
    supabase: { production_ref: string; staging_ref: string };
  }
).supabase;
const targets: Record<string, string> = { staging: refs.staging_ref, production: refs.production_ref };

const [target, source, inline] = process.argv.slice(2);
const ref = target === undefined ? undefined : targets[target];
if (!target || !ref || !source || (source === "--sql" && inline === undefined)) {
  console.error("usage: node scripts/db/with-api.ts <staging|production> <file.sql | --sql \"<statement>\">");
  process.exit(2);
}
const sql = source === "--sql" ? (inline as string) : readFileSync(source, "utf8");
const token = process.env["SUPABASE_ACCESS_TOKEN"]?.trim();
if (!token) {
  console.error(
    "SUPABASE_ACCESS_TOKEN is not set. Store a Supabase personal access token as a secret of the environment (cloud environment menu → Edit → Network secrets, or an environment variable) and start a new session. Never paste it into a chat.",
  );
  process.exit(2);
}
console.error(`target ${target} (${ref}), ${Buffer.byteLength(sql)} bytes of SQL`);
const url = `https://api.supabase.com/v1/projects/${ref}/database/query`;
if (process.env["ONE_API_DRY_RUN"] === "1") {
  console.error(`dry run: would POST to ${url}`);
  process.exit(0);
}

const dir = mkdtempSync(join(tmpdir(), "one-api-"));
try {
  const body = join(dir, "body.json");
  const out = join(dir, "response.json");
  writeFileSync(body, JSON.stringify({ query: sql }), { mode: 0o600 });
  // curl honours HTTPS_PROXY and the machine's CA store. The token travels in a config read from stdin.
  const run = spawnSync(
    "curl",
    ["-sS", "-K", "-", "-X", "POST", "-H", "Content-Type: application/json", "-H", "Accept: application/json",
     "--data-binary", `@${body}`, "-o", out, "-w", "%{http_code}", url],
    { input: `header = "Authorization: Bearer ${token.replace(/(["\\])/g, "\\$1")}"\n`, encoding: "utf8" },
  );
  if (run.status !== 0) {
    console.error(`curl failed (exit ${run.status}): ${(run.stderr ?? "").trim()}`);
    process.exit(1);
  }
  const status = run.stdout.trim();
  let response = "";
  try {
    response = readFileSync(out, "utf8");
  } catch {
    response = "";
  }
  if (!status.startsWith("2")) {
    console.error(`http ${status}: ${response.trim()}`);
    process.exit(1);
  }
  process.stdout.write(response.endsWith("\n") ? response : `${response}\n`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
