// Probes for third-party services. Each makes a real read with the credential it finds and reports what it ran; a
// missing credential is "not_provided", a rejected one is "refused". A follow-up call that fails is reported as
// "could not read" and never turns into a fix suggestion (acting on a misread could, for example, add a second webhook).
import { env, field, hostOf, http, lightsail, list, refusedFix, safeUrl, unread, type Defaults, type Row } from "./lib.ts";

export async function probeGithub(cfg: Defaults): Promise<Row> {
  const token = env("ONE_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN");
  const url = `${cfg.vendors.github_api}/repos/${cfg.repo}/contents/`;
  const ran = `GET ${url} (default branch)`;
  if (!token) return { id: "github", status: "not_provided", ran, detail: "no GitHub token in the environment" };
  const r = await http(url, { headers: { authorization: `Bearer ${token}`, accept: "application/vnd.github+json", "user-agent": "eduwit-one-preflight" } });
  if (r.status !== 200) return { id: "github", status: "refused", ran, detail: `HTTP ${r.status || r.error}`, fix: refusedFix(r, hostOf(url), "re-attach the repository with read access") };
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

async function vercelStates(cfg: Defaults, teamId: string, names: string[], auth: Record<string, string>): Promise<string[]> {
  const states: string[] = [];
  for (const [app, project] of Object.entries(cfg.vercel.projects)) {
    if (!names.includes(project)) {
      states.push(`${app}: no project "${project}"`);
      continue;
    }
    const d = await http(`${cfg.vendors.vercel_api}/v6/deployments?teamId=${teamId}&app=${project}&target=production&limit=1`, { headers: auth });
    states.push(`${app}: ${unread("deployments", d) ?? String(list(field(d.body, "deployments"))[0]?.state ?? "no production deployment")}`);
  }
  return states;
}

export async function probeVercel(cfg: Defaults): Promise<Row> {
  const token = env("ONE_VERCEL_TOKEN", "VERCEL_TOKEN");
  const ran = `GET ${cfg.vendors.vercel_api}/v2/teams, /v9/projects, /v6/deployments?target=production`;
  if (!token) return { id: "vercel", status: "not_provided", ran, detail: "no Vercel token" };
  const auth = { authorization: `Bearer ${token}` };
  const teams = await http(`${cfg.vendors.vercel_api}/v2/teams?limit=20`, { headers: auth });
  const team = list(field(teams.body, "teams")).find((t) => t.slug === cfg.vercel.team);
  if (!team) return { id: "vercel", status: "refused", ran, detail: `team "${cfg.vercel.team}" not visible (HTTP ${teams.status || teams.error})`, fix: refusedFix(teams, hostOf(cfg.vendors.vercel_api), "add the token's user to the team, or issue a team-scoped token") };
  const projects = await http(`${cfg.vendors.vercel_api}/v9/projects?teamId=${String(team.id)}&limit=50`, { headers: auth });
  const problem = unread("projects", projects);
  if (problem) return { id: "vercel", status: "refused", ran, detail: problem, fix: "give the token project read access on the team" };
  const names = list(field(projects.body, "projects")).map((p) => String(p.name));
  const states = await vercelStates(cfg, String(team.id), names, auth);
  return { id: "vercel", status: "verified", ran, detail: `team ${cfg.vercel.team}, ${names.length} projects; ${states.join("; ")}` };
}

export async function probeChatwoot(cfg: Defaults): Promise<Row> {
  const token = env("ONE_CHATWOOT_TOKEN", "CHATWOOT_API_TOKEN");
  const account = env("ONE_CHATWOOT_ACCOUNT_ID", "CHATWOOT_ACCOUNT_ID") ?? cfg.chatwoot.account_id ?? undefined;
  const base = cfg.hosts.chatwoot;
  const ran = `GET ${base}/api/v1/accounts/<id>/inboxes and /webhooks`;
  if (!token || !account) return { id: "chatwoot", status: "not_provided", ran, detail: "token or account id missing" };
  const headers = { api_access_token: token };
  const inboxes = await http(`${base}/api/v1/accounts/${account}/inboxes`, { headers });
  if (inboxes.status !== 200) return { id: "chatwoot", status: "refused", ran, detail: `HTTP ${inboxes.status || inboxes.error}`, fix: refusedFix(inboxes, hostOf(base), "issue a new agent access token") };
  const names = list(field(inboxes.body, "payload")).map((i) => `${String(i.name)} (${String(i.channel_type)})`);
  const hooks = await http(`${base}/api/v1/accounts/${account}/webhooks`, { headers });
  const hooksProblem = unread("webhooks", hooks);
  if (hooksProblem) return { id: "chatwoot", status: "verified", ran, detail: `inboxes: ${names.join(", ")}; ${hooksProblem}` };
  const hookHosts = list(field(hooks.body, "payload", "webhooks")).map((w) => hostOf(String(w.url)));
  const n8nHost = hostOf(cfg.hosts.n8n);
  const pointsAtN8n = hookHosts.includes(n8nHost);
  return {
    id: "chatwoot",
    status: "verified",
    ran,
    detail: `inboxes: ${names.join(", ")}; webhook hosts: ${hookHosts.join(", ") || "none"}${pointsAtN8n ? "" : ` (none at ${n8nHost})`}`,
    fix: pointsAtN8n ? undefined : `check the Chatwoot webhook: none points at ${cfg.hosts.n8n}`,
  };
}

export async function probeN8n(cfg: Defaults): Promise<Row> {
  const key = env("ONE_N8N_API_KEY");
  const base = env("ONE_N8N_BASE_URL") ?? cfg.hosts.n8n;
  const ran = `GET ${safeUrl(base)}/api/v1/workflows?limit=100`;
  if (!key) return { id: "n8n_api", status: "not_provided", ran, detail: "no n8n API key for the app (the build session's n8n connector is separate)", fix: "n8n → Settings → n8n API → create a read key; store it as Vault one_n8n_key" };
  const r = await http(`${base}/api/v1/workflows?limit=100`, { headers: { "X-N8N-API-KEY": key } });
  if (r.status !== 200) return { id: "n8n_api", status: "refused", ran, detail: `HTTP ${r.status || r.error}`, fix: refusedFix(r, hostOf(base), "create a new n8n API key") };
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
  const r = await lightsail(cfg.vendors.lightsail_api, "GetInstances", region, accessKey, secretKey);
  if (r.status !== 200) {
    const type = String(field(r.body, "__type") ?? r.error ?? "error");
    return { id: "lightsail", status: "refused", ran, detail: `HTTP ${r.status}: ${type}`, fix: refusedFix(r, hostOf(cfg.vendors.lightsail_api.replace("{region}", region)), "allow lightsail:Get* in the n8n server's region (an AWS Organizations policy may deny it)") };
  }
  const instances = list(field(r.body, "instances"));
  if (instances.length === 0) return { id: "lightsail", status: "refused", ran, detail: `key valid, but no instances in ${region}`, fix: "set ONE_AWS_REGION to the n8n server's region, or create the key in the account that owns the server" };
  return { id: "lightsail", status: "verified", ran, detail: instances.map((i) => `${String(i.name)}: ${String(field(i, "state", "name"))}`).join(", ") };
}

export async function probeMeta(cfg: Defaults): Promise<Row> {
  const token = env("ONE_META_TOKEN");
  const account = env("ONE_META_AD_ACCOUNT_ID");
  const ran = `GET ${cfg.vendors.graph_api}/act_<id>?fields=name,account_status`;
  if (!token || !account) return { id: "meta", status: "not_provided", ran, detail: "no Meta ad-account token or account id", fix: "authorise the Meta Ads connector, or add an ad-account read token as Vault one_meta_token" };
  const r = await http(`${cfg.vendors.graph_api}/act_${account}?fields=name,account_status`, { headers: { authorization: `Bearer ${token}` } });
  if (r.status !== 200) return { id: "meta", status: "refused", ran, detail: `HTTP ${r.status || r.error}`, fix: refusedFix(r, hostOf(cfg.vendors.graph_api), "issue a token with ads_read on the ad account") };
  return { id: "meta", status: "verified", ran, detail: `ad account status ${String(field(r.body, "account_status"))}` };
}
