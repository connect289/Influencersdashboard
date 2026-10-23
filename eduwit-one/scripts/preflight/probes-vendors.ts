// Probes for third-party services. Each one makes a real read with the credential it finds and
// reports what it ran; a missing credential is "not_provided", a rejected one is "refused".
import { env, field, http, lightsail, list, unreachable, hostOf, type Defaults, type Row } from "./lib.ts";

export async function probeGithub(cfg: Defaults): Promise<Row> {
  const token = env("ONE_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN");
  const ran = `GET ${cfg.vendors.github_api}/repos/${cfg.repo}/contents/ (default branch)`;
  if (!token) return { id: "github", status: "not_provided", ran, detail: "no GitHub token in the environment" };
  const r = await http(`${cfg.vendors.github_api}/repos/${cfg.repo}/contents/`, {
    headers: { authorization: `Bearer ${token}`, accept: "application/vnd.github+json", "user-agent": "eduwit-one-preflight" },
  });
  if (r.status !== 200) return { id: "github", status: "refused", ran, detail: `HTTP ${r.status}`, fix: unreachable(r, "api.github.com") ?? "re-attach the repo with read access" };
  const dirs = list(r.body).filter((e) => e.type === "dir").map((e) => String(e.name));
  const missing = cfg.required_repo_folders.filter((f) => !dirs.includes(f));
  return {
    id: "github",
    status: "verified",
    ran,
    detail: `top-level folders: ${dirs.join(", ")}${missing.length ? `; missing on the default branch: ${missing.join(", ")}` : ""}`,
    fix: missing.length ? `merge the branch that holds ${missing.join(", ")} into the default branch` : undefined,
  };
}

export async function probeVercel(cfg: Defaults): Promise<Row> {
  const token = env("ONE_VERCEL_TOKEN", "VERCEL_TOKEN");
  const ran = `GET ${cfg.vendors.vercel_api}/v2/teams, /v9/projects, /v6/deployments?target=production`;
  if (!token) return { id: "vercel", status: "not_provided", ran, detail: "no Vercel token" };
  const auth = { authorization: `Bearer ${token}` };
  const teams = await http(`${cfg.vendors.vercel_api}/v2/teams?limit=20`, { headers: auth });
  const team = list(field(teams.body, "teams")).find((t) => t.slug === cfg.vercel.team);
  if (!team) return { id: "vercel", status: "refused", ran, detail: `team "${cfg.vercel.team}" not visible (HTTP ${teams.status})`, fix: unreachable(teams, "api.vercel.com") ?? "add the token's user to the eduwit team" };
  const projects = await http(`${cfg.vendors.vercel_api}/v9/projects?teamId=${String(team.id)}&limit=50`, { headers: auth });
  const names = list(field(projects.body, "projects")).map((p) => String(p.name));
  const states: string[] = [];
  for (const [app, project] of Object.entries(cfg.vercel.projects)) {
    if (!names.includes(project)) {
      states.push(`${app}: no project "${project}"`);
      continue;
    }
    const d = await http(`${cfg.vendors.vercel_api}/v6/deployments?teamId=${String(team.id)}&app=${project}&target=production&limit=1`, { headers: auth });
    states.push(`${app}: ${String(list(field(d.body, "deployments"))[0]?.state ?? "no production deployment")}`);
  }
  return { id: "vercel", status: "verified", ran, detail: `team ${cfg.vercel.team}, ${names.length} projects; ${states.join("; ")}` };
}

export async function probeChatwoot(cfg: Defaults): Promise<Row> {
  const token = env("ONE_CHATWOOT_TOKEN", "CHATWOOT_API_TOKEN");
  const account = env("ONE_CHATWOOT_ACCOUNT_ID", "CHATWOOT_ACCOUNT_ID");
  const base = cfg.hosts.chatwoot;
  const ran = `GET ${base}/api/v1/accounts/<id>/inboxes and /webhooks`;
  if (!token || !account) return { id: "chatwoot", status: "not_provided", ran, detail: "token or account id missing" };
  const headers = { api_access_token: token };
  const inboxes = await http(`${base}/api/v1/accounts/${account}/inboxes`, { headers });
  if (inboxes.status !== 200) return { id: "chatwoot", status: "refused", ran, detail: `HTTP ${inboxes.status}`, fix: unreachable(inboxes, hostOf(base)) ?? "issue a new agent access token" };
  const names = list(field(inboxes.body, "payload")).map((i) => `${String(i.name)} (${String(i.channel_type)})`);
  const hooks = await http(`${base}/api/v1/accounts/${account}/webhooks`, { headers });
  const hookHosts = list(field(hooks.body, "payload", "webhooks")).map((w) => hostOf(String(w.url)));
  const n8nHost = hostOf(cfg.hosts.n8n);
  const pointsAtN8n = hookHosts.includes(n8nHost);
  return {
    id: "chatwoot",
    status: "verified",
    ran,
    detail: `inboxes: ${names.join(", ")}; webhook hosts: ${hookHosts.join(", ") || "none"}${pointsAtN8n ? "" : ` (none at ${n8nHost})`}`,
    fix: pointsAtN8n ? undefined : `point the Chatwoot webhook at ${cfg.hosts.n8n}`,
  };
}

export async function probeN8n(cfg: Defaults): Promise<Row> {
  const key = env("ONE_N8N_API_KEY");
  const base = env("ONE_N8N_BASE_URL") ?? cfg.hosts.n8n;
  const ran = `GET ${base}/api/v1/workflows?limit=100`;
  if (!key) return { id: "n8n_api", status: "not_provided", ran, detail: "no n8n API key for the app (the build session's n8n connector is separate)", fix: "n8n → Settings → n8n API → create a read key; store as Vault one_n8n_key" };
  const r = await http(`${base}/api/v1/workflows?limit=100`, { headers: { "X-N8N-API-KEY": key } });
  if (r.status !== 200) return { id: "n8n_api", status: "refused", ran, detail: `HTTP ${r.status}`, fix: unreachable(r, hostOf(base)) ?? "create a new n8n API key" };
  const flows = list(field(r.body, "data"));
  const witty = flows.find((w) => w.id === cfg.n8n.witty_workflow_id);
  return { id: "n8n_api", status: "verified", ran, detail: `${flows.length} workflows; Eduwit Witty active: ${String(witty?.active ?? "not found")}` };
}

export async function probeLightsail(cfg: Defaults): Promise<Row> {
  const accessKey = env("ONE_AWS_ACCESS_KEY_ID", "EDUWIT_AWS_ACCESS_KEY_ID");
  const secretKey = env("ONE_AWS_SECRET_ACCESS_KEY", "EDUWIT_AWS_SECRET_ACCESS_KEY");
  const region = env("ONE_AWS_REGION", "EDUWIT_AWS_REGION") ?? cfg.aws.lightsail_default_region;
  const ran = `Lightsail GetInstances in ${region} (SigV4)`;
  if (!accessKey || !secretKey) return { id: "lightsail", status: "not_provided", ran, detail: "no AWS access key" };
  const r = await lightsail("GetInstances", region, accessKey, secretKey);
  if (r.status !== 200) {
    const message = String(field(r.body, "Message") ?? r.error ?? "").slice(0, 160);
    return { id: "lightsail", status: "refused", ran, detail: `HTTP ${r.status}: ${message}`, fix: unreachable(r, `lightsail.${region}.amazonaws.com`) ?? "set the region of the n8n server and allow lightsail:Get* there (an organisation SCP may deny it)" };
  }
  const instances = list(field(r.body, "instances"));
  if (instances.length === 0) return { id: "lightsail", status: "refused", ran, detail: `key valid, but no instances in ${region}`, fix: "set ONE_AWS_REGION to the region of the n8n server, or create the key in the account that owns it" };
  const states = instances.map((i) => `${String(i.name)}: ${String(field(i, "state", "name"))}`);
  return { id: "lightsail", status: "verified", ran, detail: states.join(", ") };
}
