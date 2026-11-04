// Records the Mock clients' fixtures from real responses (spec standard 2: a fixture is recorded, never hand-written).
// Each response is parsed with the client's own schema and only those fields are written, so a fixture cannot hold a
// token, a contact or a message. Clients whose credential is absent are left as they are and reported.
//   node scripts/record-fixtures.ts            (in the cloud build environment: NODE_USE_ENV_PROXY=1 node ...)
// Credentials are read from the environment by the same names the app uses; nothing is printed but counts.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { RealAppHealthClient } from "../lib/clients/app-health.ts";
import { RealChatwootClient } from "../lib/clients/chatwoot.ts";
import { RealVercelClient } from "../lib/clients/vercel.ts";

type Defaults = {
  hosts: Record<string, string>;
  health_paths: Record<string, string>;
  vendors: Record<string, string>;
  vercel: { team: string; projects: Record<string, string> };
  chatwoot: { account_id: string };
};

const defaults = JSON.parse(readFileSync(new URL("../../config/defaults.json", import.meta.url), "utf8")) as Defaults;
const env = (...names: string[]) => names.map((n) => process.env[n]?.trim()).find(Boolean);

function write(client: string, scenario: string, data: unknown): void {
  const dir = new URL(`../lib/clients/fixtures/${client}/`, import.meta.url);
  mkdirSync(dir, { recursive: true });
  const meta = { recorded: true, recorded_at: new Date().toISOString(), by: "scripts/record-fixtures.ts" };
  writeFileSync(new URL(`${scenario}.json`, dir), `${JSON.stringify({ meta, data }, null, 2)}\n`);
}

async function appHealth(): Promise<string> {
  const client = new RealAppHealthClient();
  const byHost: Record<string, { ok: boolean; status: number }> = {};
  for (const app of ["website", "influencer", "b2b_app", "spark"]) {
    const host = defaults.hosts[app];
    const path = defaults.health_paths[app];
    if (!host || !path) continue;
    const r = await client.health(`${host}${path}`, path === "/api/health" ? "json_ok" : "reachable");
    byHost[new URL(host).host] = { ok: r.ok, status: r.status };
  }
  write("app-health", "live", byHost);
  return `app-health: ${Object.keys(byHost).length} hosts`;
}

async function vercel(): Promise<string> {
  const token = env("ONE_VERCEL_TOKEN", "VERCEL_TOKEN");
  const base = defaults.vendors.vercel_api;
  if (!token || !base) return "vercel: no token, left as is";
  const client = new RealVercelClient(base, token);
  const byProject: Record<string, unknown> = {};
  for (const key of ["website", "one"]) {
    const project = defaults.vercel.projects[key];
    if (!project) continue;
    try {
      byProject[project] = await client.deployments(project, defaults.vercel.team);
    } catch (e) {
      byProject[project] = { deployments: [], note: `not readable: ${e instanceof Error ? e.message : "error"}` };
    }
  }
  write("vercel", "live", byProject);
  return `vercel: ${Object.keys(byProject).length} projects`;
}

async function chatwoot(): Promise<string> {
  const token = env("ONE_CHATWOOT_TOKEN", "CHATWOOT_API_TOKEN");
  const host = defaults.hosts.chatwoot;
  if (!token || !host) return "chatwoot: no token, left as is";
  const client = new RealChatwootClient(host, token);
  const account = env("ONE_CHATWOOT_ACCOUNT_ID", "CHATWOOT_ACCOUNT_ID") ?? defaults.chatwoot.account_id;
  const until = Math.floor(Date.now() / 1000);
  const inboxes = await client.inboxes(account);
  const summary = await client.summary(account, until - 3 * 3600, until);
  write("chatwoot", "live", { inboxes, summary, labels: { default: { payload: [] } } });
  return `chatwoot: ${inboxes.payload.length} inboxes, summary recorded (labels not recorded: they need a conversation id)`;
}

for (const task of [appHealth, vercel, chatwoot]) {
  try {
    console.warn(await task());
  } catch (e) {
    console.warn(`${task.name}: failed (${e instanceof Error ? e.message : "error"})`);
  }
}
