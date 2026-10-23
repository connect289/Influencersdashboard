// Read-only trial of the SQL checks on a database that does not have schema one yet (production before the phase 1
// apply). Prints, per source file, one statement that runs inside "begin transaction read only" and returns one row
// per check: id, row count, ok, value. one.* references become the configured threshold and setting values or empty
// stand-ins, so the trial proves each check compiles and runs against the real app tables and shows what it would
// report today. Usage: node scripts/db/try-checks.ts [file.sql | --ids=ID,ID ...] > out.sql
import { readFileSync } from "node:fs";
import { loadChecks, type Check } from "./gen-checks.ts";

const settings = JSON.parse(readFileSync(new URL("../../config/settings.json", import.meta.url), "utf8")) as Record<string, unknown> & {
  thresholds: Record<string, number>;
};

/** Empty stand-ins for schema one's tables, with the columns the checks read. */
const EMPTY: Record<string, string> = {
  runs: "select null::text as kind, null::timestamptz as started_at, null::jsonb as report",
  results: "select null::text as check_id, null::text as status, null::jsonb as value, null::timestamptz as ran_at",
  check_state: "select null::text as check_id, null::timestamptz as last_ran_at",
  baselines: "select null::text as key, null::jsonb as value, null::timestamptz as captured_at",
  heartbeats: "select null::text as component, null::timestamptz as last_ok_at, null::text as last_error, null::jsonb as detail, null::int as expected_interval_s",
  ai_tasks: "select null::text as status",
  deliveries: "select null::text as status, null::timestamptz as created_at",
  ai_calls: "select null::numeric as cost_inr, null::timestamptz as created_at",
  privilege_baseline: "select null::text as fn, null::boolean as acknowledged, null::timestamptz as last_seen",
};
const KEYWORDS = new Set(["where", "on", "join", "left", "right", "inner", "order", "group", "limit", "union", "cross", "full", "having"]);

export function forTrial(sql: string): string {
  return sql
    .replace(/one\.threshold\('([a-z0-9_]+)'\)/g, (_, k: string) => `(${settings.thresholds[k]})::numeric`)
    .replace(/one\.setting\('([a-z0-9_]+)'\)/g, (_, k: string) => `('${JSON.stringify(settings[k] ?? null).replace(/'/g, "''")}'::jsonb)`)
    .replace(/one\.vault_names\(\)/g, "(select name from vault.secrets)")
    .replace(/one\.inf_health\(\)/g, "inf.health()")
    .replace(/one\.public_schema_writers\(\)/g, "(select r from unnest(array['public', 'anon', 'authenticated', 'service_role', 'authenticator']) r where has_schema_privilege(r, 'public', 'CREATE'))")
    .replace(/\bone\.([a-z_]+)\b(\s+(?:as\s+)?([a-z_][a-z0-9_]*))?/g, (whole, table: string, aliasPart: string | undefined, alias: string | undefined) => {
      const stand = EMPTY[table];
      if (!stand) throw new Error(`try-checks: no stand-in for one.${table}`);
      const keepAlias = alias !== undefined && !KEYWORDS.has(alias.toLowerCase());
      return `(${stand} where false) ${keepAlias ? alias : table}${!keepAlias && aliasPart ? aliasPart : ""}`;
    });
}

function trial(checks: Check[]): string {
  const parts = checks.filter((c) => c.sql !== null).map((c) =>
    `select '${c.id}' as id, count(*)::int as rows, bool_and(q.ok) as ok, (array_agg(q.value))[1] as value from (\n${forTrial(c.sql as string)}\n) q`);
  return `begin transaction read only;\n${parts.join("\nunion all\n")};`;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const ids = args.find((a) => a.startsWith("--ids="))?.slice(6).split(",");
  const files = args.filter((a) => !a.startsWith("--"));
  const checks = loadChecks().filter((c) => (files.length === 0 || files.includes(c.source)) && (!ids || ids.includes(c.id)));
  const bySource = new Map<string, Check[]>();
  for (const c of checks) bySource.set(c.source, [...(bySource.get(c.source) ?? []), c]);
  for (const [source, list] of bySource) console.log(`-- ${source}\n${trial(list)}\n`);
}
