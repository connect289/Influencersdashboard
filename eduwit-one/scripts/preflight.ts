// Eduwit One access preflight (spec §14, phase 0). Re-runnable at any time.
// Exercises every row of the prerequisites access list with a real read, list or ping and prints each as
// verified / refused / not_provided / unfilled with what it ran. Never prints or stores a secret.
//
//   node scripts/preflight.ts [--merge docs/preflight-connector.json] [--setup supabase/seed/setup.json] [--md docs/PREFLIGHT-table.md]
//
// In the cloud build environment, outbound HTTPS needs NODE_USE_ENV_PROXY=1. The merge file holds evidence the build
// session gathered through its connectors (Supabase, n8n, GitHub), each row dated by the file's run_at. Merge rules:
// a script result that is verified or refused wins; connector evidence fills only items the script could not reach;
// connector evidence older than preflight.connector_evidence_max_age_days becomes "unfilled" (re-run in a session).
import { readFileSync, writeFileSync } from "node:fs";
import { loadJson, type Defaults, type Row, type Status } from "./preflight/lib.ts";
import { probeChatwoot, probeGithub, probeLightsail, probeMeta, probeN8n, probeVercel } from "./preflight/probes-vendors.ts";
import { probeAiKey, probeB2bApi, probeHealth, probeIdentities, probeResend, probeUptimeRobot, probeWhatsApp } from "./preflight/probes-apps.ts";
import { probeDatabase } from "./preflight/probes-db.ts";

type SetupItem = { id: string; title: string; who: string; stores: string; unblocks: string[] };
type Sourced = Row & { source: "script" | "connector" | "none"; evidence_at: string | null };
type ConnectorFile = { run_at: string; rows: Row[]; annotations?: Array<{ id: string; detail?: string; fix?: string }> };

const STATUSES: Status[] = ["verified", "refused", "not_provided", "unfilled"];

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
}

/** A probe that throws becomes a refused row for its item instead of aborting the whole run. */
async function guarded(id: string, probe: () => Promise<Row | Row[] | undefined> | Row[]): Promise<Row[]> {
  try {
    const out = await probe();
    return out === undefined ? [] : Array.isArray(out) ? out : [out];
  } catch (e) {
    return [{ id, status: "refused", ran: "probe", detail: `probe crashed (${e instanceof Error ? e.name : "error"})`, fix: "re-run; if it repeats, fix the probe in scripts/preflight" }];
  }
}

async function runScriptProbes(cfg: Defaults): Promise<Row[]> {
  const runs = await Promise.all([
    guarded("github", () => probeGithub(cfg)),
    guarded("vercel", () => probeVercel(cfg)),
    guarded("chatwoot", () => probeChatwoot(cfg)),
    guarded("n8n_api", () => probeN8n(cfg)),
    guarded("lightsail", () => probeLightsail(cfg)),
    guarded("meta", () => probeMeta(cfg)),
    guarded("uptimerobot", () => probeUptimeRobot(cfg)),
    guarded("email", () => probeResend(cfg)),
    guarded("b2b_app", () => probeB2bApi(cfg)),
    guarded("whatsapp", () => probeWhatsApp(cfg)),
    guarded("ai_key", () => probeAiKey(cfg)),
    guarded("website_health", () => probeHealth(cfg, "website", "website_health")),
    guarded("influencer_portal", () => probeHealth(cfg, "influencer", "influencer_portal")),
    guarded("test_mailbox", () => probeIdentities(cfg)),
    guarded("supabase_prod_dump", () => probeDatabase(cfg)),
  ]);
  return runs.flat();
}

function readConnector(path: string | undefined, items: SetupItem[]): ConnectorFile {
  if (!path) return { run_at: "", rows: [] };
  const file = JSON.parse(readFileSync(path, "utf8")) as ConnectorFile;
  const ids = new Set(items.map((i) => i.id));
  for (const row of [...file.rows, ...(file.annotations ?? [])]) {
    if (!ids.has(row.id)) throw new Error(`merge file: unknown item id "${row.id}"`);
  }
  for (const row of file.rows) {
    if (!STATUSES.includes(row.status)) throw new Error(`merge file: bad status "${String(row.status)}" for ${row.id}`);
    if (row.status === "refused" && !row.fix) throw new Error(`merge file: refused row ${row.id} has no fix`);
  }
  if (Number.isNaN(Date.parse(file.run_at))) throw new Error("merge file: run_at is not a date");
  return file;
}

function merge(items: SetupItem[], script: Row[], connector: ConnectorFile, maxAgeDays: number, now: string): Sourced[] {
  const stale = Date.parse(now) - Date.parse(connector.run_at || now) > maxAgeDays * 86_400_000;
  return items.map((item): Sourced => {
    const own = script.find((r) => r.id === item.id);
    const evidence = connector.rows.find((r) => r.id === item.id);
    let row: Sourced;
    if (own?.status === "refused" && evidence?.status === "verified" && !stale) {
      // Both are true: the build session reached it through a connector, this run could not. Show both.
      row = { ...evidence, detail: `${evidence.detail} [this run: ${own.detail}; ${own.fix}]`, source: "connector", evidence_at: connector.run_at };
    } else if (own && (own.status === "verified" || own.status === "refused")) row = { ...own, source: "script", evidence_at: now };
    else if (evidence && stale && evidence.status === "verified") row = { ...evidence, status: "unfilled", detail: `connector evidence from ${connector.run_at} is older than ${maxAgeDays} days: ${evidence.detail}`, fix: "re-run the connector checks in a build session", source: "connector", evidence_at: connector.run_at };
    else if (evidence) row = { ...evidence, source: "connector", evidence_at: connector.run_at };
    else if (own) row = { ...own, source: "script", evidence_at: now };
    else row = { id: item.id, status: "unfilled", ran: "—", detail: "no probe and no connector evidence", source: "none", evidence_at: null };
    const note = connector.annotations?.find((a) => a.id === item.id);
    return note ? { ...row, detail: note.detail ? `${row.detail}; ${note.detail}` : row.detail, fix: note.fix ?? row.fix } as Sourced : row;
  });
}

function markdown(items: SetupItem[], rows: Sourced[]): string {
  const cell = (s: string | undefined | null): string => (s ?? "").replace(/\|/g, "\\|").replace(/\n/g, " ");
  const lines = ["| Item | Status | What was run | Result | Fix | Unblocks |", "| --- | --- | --- | --- | --- | --- |"];
  for (const row of rows) {
    const item = items.find((i) => i.id === row.id);
    const via = row.source === "connector" ? ` (connector, ${row.evidence_at?.slice(0, 10) ?? ""})` : "";
    lines.push(`| ${cell(item?.title ?? row.id)} | ${row.status} | ${cell(row.ran)}${via} | ${cell(row.detail)} | ${cell(row.fix)} | ${cell(item?.unblocks.join(", "))} |`);
  }
  return lines.join("\n");
}

function setupSeed(rows: Sourced[], at: string): unknown {
  const items: Record<string, unknown> = {};
  for (const row of rows) {
    items[row.id] = {
      status: row.status,
      validated: row.status === "verified",
      validated_at: row.status === "verified" ? row.evidence_at : null,
      ran: row.ran,
      detail: row.detail,
      fix: row.fix ?? null,
      source: row.source,
    };
  }
  return { generated_at: at, generated_by: "scripts/preflight.ts", items };
}

async function main(): Promise<void> {
  const cfg = loadJson<Defaults>("config/defaults.json");
  const { items } = loadJson<{ items: SetupItem[] }>("config/setup-items.json");
  const connector = readConnector(arg("--merge"), items);
  const at = new Date().toISOString();
  const rows = merge(items, await runScriptProbes(cfg), connector, cfg.preflight.connector_evidence_max_age_days, at);
  const table = markdown(items, rows);
  const counts = rows.reduce<Record<string, number>>((acc, r) => ({ ...acc, [r.status]: (acc[r.status] ?? 0) + 1 }), {});
  console.log(`Eduwit One preflight ${at}\n\n${table}\n\n${JSON.stringify(counts)}`);
  const setupPath = arg("--setup");
  if (setupPath) writeFileSync(setupPath, `${JSON.stringify(setupSeed(rows, at), null, 2)}\n`);
  const mdPath = arg("--md");
  if (mdPath) writeFileSync(mdPath, `<!-- generated by scripts/preflight.ts at ${at}; do not edit -->\n\n${table}\n`);
}

await main();
