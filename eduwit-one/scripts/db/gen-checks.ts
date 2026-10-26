// Builds migration 0006 (seed of one.checks), the seed of each app registered after 0002 (LATE_APPS) and docs/CHECKS.md
// from the check sources in supabase/checks/*.sql.
//   node scripts/db/gen-checks.ts            write the files
//   node scripts/db/gen-checks.ts --check    exit 1 if any file is stale (CI and the unit test)
// A source file holds blocks that start with "-- check: <ID>", then "-- key: value" header lines, then the SQL (none
// for app-run kinds). The SQL rules mirror the CHECK constraint on one.checks.sql, so a bad check fails here, not at
// apply time. "-- search_path: public" runs a check that calls an app's invoker-rights function (D-042); a check whose
// value carries a "subjects" array gets one alert per new subject (D-043). Thresholds are read in SQL through one.threshold('<key>'); every key must exist in config/settings.json.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";

export type Check = {
  id: string; app: string; kind: string; severity: string; cadence_s: number; title: string; description: string;
  fix: string | null; tags: string[]; open_after: number; resolve_after: number; disabled: string | null; sql: string | null; source: string;
  search_path: "" | "public, pg_temp";
};

const root = new URL("../../", import.meta.url);
const KINDS = ["sql", "rpc", "http", "heartbeat", "test", "integrity"] as const;
const APP_RUN = new Set(["http", "test"]);
const APPS = ["witty", "b2b", "b2c", "web", "influencer", "one", "platform", "catalogue", "integrity", "catalogue_engine"];
/**
 * Apps whose key a migration after 0002 adds to one.apps (D-094). On a fresh install 0006 runs before that migration,
 * so its app row and checks would break 0002's key constraint there: they are seeded by a generated file of their own
 * (`file`), numbered right after the migration that registers the key (`after`). 0006 keeps the apps 0002 lists.
 */
export const LATE_APPS: Record<string, { name: string; file: string; after: string }> = {
  catalogue_engine: { name: "Catalogue Engine", file: "0022_seed_catalogue_engine_checks.sql", after: "0021_catalogue_engine.sql" },
};
const FORBIDDEN = /\b(insert|update|delete|truncate|alter|drop|create|grant|revoke|copy|call|perform|vacuum|reindex|refresh|lock|set|reset|notify)\b/i;

function fail(msg: string): never {
  throw new Error(`gen-checks: ${msg}`);
}

export function parseSource(name: string, text: string): Check[] {
  const blocks = text.split(/^(?=-- check: )/m).filter((b) => b.startsWith("-- check: "));
  return blocks.map((block) => {
    const lines = block.replace(/\s+$/, "").split("\n");
    const header: Record<string, string> = {};
    let i = 0;
    for (; i < lines.length && (lines[i] ?? "").startsWith("-- "); i++) {
      const m = /^-- ([a-z_]+): (.*)$/.exec(lines[i] ?? "");
      if (!m) fail(`${name}: bad header line "${lines[i]}"`);
      header[m[1] as string] = (m[2] as string).trim();
    }
    const body = lines.slice(i).join("\n").trim();
    const id = header.check ?? fail(`${name}: block without id`);
    const kind = header.kind ?? fail(`${id}: no kind`);
    const need = (k: string) => header[k] ?? fail(`${id}: missing ${k}`);
    const check: Check = {
      id, app: need("app"), kind, severity: need("severity"), cadence_s: Number(need("cadence_s")), title: need("title"),
      description: need("description"), fix: header.fix ?? null,
      tags: header.tags ? header.tags.split(",").map((t) => t.trim()).filter(Boolean) : [],
      open_after: Number(header.open_after ?? 1), resolve_after: Number(header.resolve_after ?? 3),
      disabled: header.disabled ?? null, sql: body === "" ? null : body, source: name,
      search_path: header.search_path === undefined ? "" : header.search_path === "public" ? "public, pg_temp" : fail(`${id}: search_path may only be public`),
    };
    validate(check);
    return check;
  });
}

function validate(c: Check): void {
  if (!/^[A-Z0-9]+(-[A-Za-z0-9:._]+)+$/.test(c.id)) fail(`${c.id}: bad id`);
  if (!APPS.includes(c.app)) fail(`${c.id}: unknown app ${c.app}`);
  if (!(KINDS as readonly string[]).includes(c.kind)) fail(`${c.id}: unknown kind ${c.kind}`);
  if (!["P1", "P2", "P3"].includes(c.severity)) fail(`${c.id}: bad severity`);
  if (!Number.isInteger(c.cadence_s) || c.cadence_s < 60 || c.cadence_s > 604800) fail(`${c.id}: cadence_s out of range`);
  if (c.disabled !== null && !/^(setup|blocked|owner|builder):[a-z0-9_.:-]+$/.test(c.disabled)) fail(`${c.id}: bad disabled reason`);
  if (c.fix !== null && !/^FIX-[A-Z0-9-]+$/.test(c.fix)) fail(`${c.id}: bad fix id`);
  if (APP_RUN.has(c.kind)) {
    if (c.sql !== null) fail(`${c.id}: ${c.kind} checks are run by the app and carry no SQL`);
    return;
  }
  const sql = c.sql ?? fail(`${c.id}: ${c.kind} check needs SQL`);
  if (!/^(select|with)\b/i.test(sql)) fail(`${c.id}: SQL must start with select or with`);
  if (sql.includes(";")) fail(`${c.id}: SQL must not contain ;`);
  if (sql.includes("--")) fail(`${c.id}: no comments inside SQL; put the why in the description`);
  if (sql.includes("$sql$")) fail(`${c.id}: SQL must not contain $sql$`);
  const bad = FORBIDDEN.exec(sql);
  if (bad) fail(`${c.id}: SQL contains the forbidden word "${bad[0]}"`);
  if (/\bvault\.decrypted_secrets\b/i.test(sql)) fail(`${c.id}: checks never read secret values`);
}

export function loadChecks(): Check[] {
  const dir = new URL("supabase/checks/", root);
  const checks = readdirSync(dir).filter((f) => f.endsWith(".sql")).sort()
    .flatMap((f) => parseSource(f, readFileSync(new URL(f, dir), "utf8")));
  const seen = new Set<string>();
  for (const c of checks) {
    if (seen.has(c.id)) fail(`duplicate id ${c.id}`);
    seen.add(c.id);
  }
  const thresholds = (JSON.parse(readFileSync(new URL("config/settings.json", root), "utf8")) as { thresholds: Record<string, unknown> }).thresholds;
  for (const c of checks) {
    for (const m of (c.sql ?? "").matchAll(/one\.threshold\('([a-z0-9_]+)'\)/g)) {
      if (!(m[1] as string in thresholds)) fail(`${c.id}: threshold ${m[1]} is not in config/settings.json`);
    }
  }
  return checks.sort((a, b) => a.id.localeCompare(b.id, "en"));
}

const lit = (s: string | null) => (s === null ? "null" : `'${s.replace(/'/g, "''")}'`);

function seedCall(c: Check): string {
  const pairs: string[] = [
    `'id', ${lit(c.id)}`, `'app', ${lit(c.app)}`, `'kind', ${lit(c.kind)}`, `'severity', ${lit(c.severity)}`,
    `'cadence_s', ${c.cadence_s}`, `'open_after', ${c.open_after}`, `'resolve_after', ${c.resolve_after}`,
    `'title', ${lit(c.title)}`, `'description', ${lit(c.description)}`, `'auto_fix_id', ${lit(c.fix)}`,
    `'tags', ${lit(JSON.stringify(c.tags))}::jsonb`, `'enabled', ${c.disabled === null}`, `'disabled_reason', ${lit(c.disabled)}`,
    `'search_path', ${lit(c.search_path)}`,
    `'sql', ${c.sql === null ? "null::text" : `$sql$\n${c.sql}\n$sql$`}`,
  ];
  return `select one.seed_check(jsonb_build_object(\n  ${pairs.join(",\n  ")}));`;
}

const PREAMBLE = `-- 0006 the apps and the check catalogue (spec §6). GENERATED by scripts/db/gen-checks.ts from supabase/checks/*.sql;
-- edit the sources, never this file. Seeding rule (spec §16.8): a check's rule (sql, kind, title, description, app)
-- always follows the migration; its operational fields (enabled, severity, cadence, open/resolve counts) keep a
-- person's edit (updated_by <> 'seed').

insert into one.apps (key, name) values
  ('witty', 'Witty'), ('b2b', 'B2B CRM'), ('b2c', 'Spark (B2C CRM)'), ('web', 'Website and web advisor'),
  ('influencer', 'Influencer portal'), ('one', 'Eduwit One'), ('platform', 'Platform (Supabase, pg_cron)'),
  ('catalogue', 'Shared catalogue'), ('integrity', 'Cross-app integrity')
on conflict (key) do update set name = excluded.name;

create or replace function one.seed_check(p jsonb) returns void
language plpgsql set search_path = '' as $$
begin
  insert into one.checks as c (id, app, title, description, kind, sql, search_path, severity, cadence_s, open_after,
                               resolve_after, tags, enabled, disabled_reason, auto_fix_id)
  values (p ->> 'id', p ->> 'app', p ->> 'title', p ->> 'description', p ->> 'kind', p ->> 'sql', coalesce(p ->> 'search_path', ''),
          (p ->> 'severity')::one.severity, (p ->> 'cadence_s')::int,
          coalesce((p ->> 'open_after')::int, 1), coalesce((p ->> 'resolve_after')::int, 3),
          coalesce(array(select jsonb_array_elements_text(p -> 'tags')), '{}'),
          coalesce((p ->> 'enabled')::boolean, true), p ->> 'disabled_reason', p ->> 'auto_fix_id')
  on conflict (id) do update set
    app = excluded.app, title = excluded.title, description = excluded.description, kind = excluded.kind,
    sql = excluded.sql, search_path = excluded.search_path, auto_fix_id = excluded.auto_fix_id, tags = excluded.tags,
    severity = case when c.updated_by = 'seed' then excluded.severity else c.severity end,
    cadence_s = case when c.updated_by = 'seed' then excluded.cadence_s else c.cadence_s end,
    open_after = case when c.updated_by = 'seed' then excluded.open_after else c.open_after end,
    resolve_after = case when c.updated_by = 'seed' then excluded.resolve_after else c.resolve_after end,
    enabled = case when c.updated_by = 'seed' then excluded.enabled else c.enabled end,
    disabled_reason = case when c.updated_by = 'seed' then excluded.disabled_reason else c.disabled_reason end,
    version = c.version + 1, updated_at = now()
  where (c.sql, c.search_path, c.title, c.kind, c.description, c.severity, c.cadence_s, c.enabled, c.disabled_reason, c.tags, c.auto_fix_id)
        is distinct from (excluded.sql, excluded.search_path, excluded.title, excluded.kind, excluded.description, excluded.severity,
                          excluded.cadence_s, excluded.enabled, excluded.disabled_reason, excluded.tags, excluded.auto_fix_id);
end $$;
`;

/** 0006: the apps 0002 lists and their checks. */
export function migration(checks: Check[]): string {
  const own = checks.filter((c) => !(c.app in LATE_APPS));
  return `${PREAMBLE}\n${own.map(seedCall).join("\n\n")}\n\nselect one.capture_baselines();\ncall one.apply_grants();\n`;
}

/** The seed of an app registered after 0002: its app row and its checks, through 0006's one.seed_check (same rule). */
export function lateMigration(checks: Check[], app: string): string {
  const late = LATE_APPS[app] ?? fail(`${app} is not a late app`);
  const own = checks.filter((c) => c.app === app);
  if (own.length === 0) fail(`${app}: no checks to seed in ${late.file}`);
  const head = [
    `-- ${late.file.slice(0, 4)} the ${late.name}: its app row and its checks. GENERATED by scripts/db/gen-checks.ts from`,
    `-- supabase/checks/*.sql; edit the sources, never this file. ${late.after} adds the key ${app}`,
    "-- to one.apps, and a fresh install runs 0006 before it, so this app is seeded here, after it (D-094). Same rule as",
    "-- 0006 (one.seed_check): a check's rule follows the migration; a person's edits to its switch, severity and cadence",
    "-- are kept. After changing one of these checks, apply this file again, not 0006.",
    "",
    `insert into one.apps (key, name) values (${lit(app)}, ${lit(late.name)})`,
    "on conflict (key) do update set name = excluded.name;",
  ].join("\n");
  return `${head}\n\n${own.map(seedCall).join("\n\n")}\n`;
}

const md = (s: string) => s.replace(/\|/g, "\\|");

export function catalogue(checks: Check[]): string {
  const rows = checks.map((c) =>
    `| ${c.id} | ${c.app} | ${c.kind} | ${c.severity} | ${c.cadence_s < 3600 ? `${c.cadence_s / 60} min` : `${c.cadence_s / 3600} h`} | ${c.disabled ? `off: \`${c.disabled}\`` : "on"} | ${md(c.title)} | ${c.fix ?? "—"} |`);
  const details = checks.map((c) => `- **${c.id}**: ${md(c.description)} (source \`supabase/checks/${c.source}\`)`);
  const byState = { on: checks.filter((c) => !c.disabled).length, off: checks.filter((c) => c.disabled).length };
  return [
    "# Eduwit One — checks catalogue",
    "",
    "GENERATED by `scripts/db/gen-checks.ts` from `supabase/checks/*.sql`; never edit by hand (spec operating rule 8).",
    `${checks.length} checks: ${byState.on} on, ${byState.off} off until configured. App-run kinds (http, test) are reported by the`,
    "app through `one.report_result()`; every other kind is a SQL statement run by `one.tick()` as the database owner.",
    `Migration 0006 seeds them, except an app registered after 0002, seeded by its own file (D-094): ${Object.entries(LATE_APPS)
      .map(([app, l]) => `${app} by \`${l.file}\``)
      .join(", ")}.`,
    "",
    "| ID | App | Kind | Severity | Cadence | State | Fires when | Fix |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ...rows,
    "",
    "## What each check reads",
    "",
    ...details,
    "",
  ].join("\n");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const checks = loadChecks();
  const outputs: [URL, string][] = [
    [new URL("supabase/migrations/0006_seed_checks.sql", root), migration(checks)],
    ...Object.entries(LATE_APPS).map(([app, l]): [URL, string] => [new URL(`supabase/migrations/${l.file}`, root), lateMigration(checks, app)]),
    [new URL("docs/CHECKS.md", root), catalogue(checks)],
  ];
  if (process.argv.includes("--check")) {
    const stale = outputs.filter(([url, text]) => readFileSync(url, "utf8") !== text).map(([url]) => url.pathname.split("/eduwit-one/")[1]);
    if (stale.length) {
      console.error(`stale: ${stale.join(", ")}; run node scripts/db/gen-checks.ts`);
      process.exit(1);
    }
    console.log(`checks current (${checks.length})`);
  } else {
    for (const [url, text] of outputs) writeFileSync(url, text);
    console.log(`wrote 0006_seed_checks.sql, ${Object.values(LATE_APPS).map((l) => l.file).join(", ")} and docs/CHECKS.md (${checks.length} checks)`);
  }
}
