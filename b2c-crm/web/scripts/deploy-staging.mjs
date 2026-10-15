/**
 * Deploys the B2C CRM to Vercel for staging, end to end:
 *   NODE_USE_ENV_PROXY=1 node scripts/deploy-staging.mjs
 * Needs VERCEL_TOKEN, the staging SUPABASE_SERVICE_ROLE_KEY and the SMTP_* variables in the environment. Creates the
 * project `eduwit-b2c-crm` (root b2c-crm/web, linked to the GitHub repo) if it is missing, sets its variables (secrets
 * go straight from this environment to Vercel and are never printed), deploys the current branch as the project's
 * production deployment, then points the database timers at it (settings 'app'.base_url and Vault 'b2c_internal_key',
 * through b2c.app_deploy_set). LIVE_MODE stays off. Never touches any other Vercel project.
 */
import { randomBytes } from "node:crypto";
import { execSync } from "node:child_process";
import { createClient } from "@supabase/supabase-js";
import webpush from "web-push";
import { assertStagingKey, STAGING_REF } from "../e2e/fixtures.mjs";

const NAME = "eduwit-b2c-crm";
const REPO = "connect289/Influencersdashboard";
const ROOT = "b2c-crm/web";
const TEAM_SLUG = "eduwit";
const PUBLISHABLE = "sb_publishable_FcEGrrBhgofu7WPmwdYEHw_J1b_zYbo"; // staging, public by design

const token = process.env.VERCEL_TOKEN;
if (!token) throw new Error("Set VERCEL_TOKEN.");
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
assertStagingKey(serviceKey);
const branch = process.env.DEPLOY_BRANCH ?? execSync("git rev-parse --abbrev-ref HEAD").toString().trim();

async function api(method, path, body) {
  const url = `https://api.vercel.com${path}${path.includes("?") ? "&" : "?"}teamId=${team.id}`;
  let res;
  for (let attempt = 1; ; attempt++) {
    try {
      res = await fetch(url, { method, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
      if (res.status < 500 || attempt === 4) break;
    } catch (e) {
      if (attempt === 4) throw e; // a network blip: try again
    }
    await new Promise((r) => setTimeout(r, 2000 * 2 ** attempt));
  }
  const data = res.status === 204 ? {} : await res.json();
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${data?.error?.message ?? JSON.stringify(data).slice(0, 300)}`);
  return data;
}

const teams = await (await fetch("https://api.vercel.com/v2/teams", { headers: { Authorization: `Bearer ${token}` } })).json();
const team = teams.teams?.find((t) => t.slug === TEAM_SLUG);
if (!team) throw new Error(`Vercel team ${TEAM_SLUG} not found for this token.`);

// 1. the project
let project;
try {
  project = await api("GET", `/v9/projects/${NAME}`);
  if (project.rootDirectory !== ROOT) throw new Error(`Project ${NAME} exists with root ${project.rootDirectory}: refusing to change it.`);
  console.log(`project  ${NAME} (exists)`);
} catch (e) {
  if (!String(e.message).includes("404")) throw e;
  project = await api("POST", "/v11/projects", {
    name: NAME, framework: "nextjs", rootDirectory: ROOT, gitRepository: { type: "github", repo: REPO },
  });
  console.log(`project  ${NAME} (created)`);
}

// 2. its address
const domains = await api("GET", `/v9/projects/${project.id}/domains`);
const host = domains.domains?.find((d) => d.name.endsWith(".vercel.app"))?.name ?? `${NAME}.vercel.app`;
const site = `https://${host}`;
console.log(`address  ${site}`);

// 3. variables (production and preview); a secret that already exists is kept unless it must change
const existing = new Set((await api("GET", `/v9/projects/${project.id}/env`)).envs?.map((e) => e.key));
const internalKey = randomBytes(32).toString("hex"); // rotated on every deploy, written to Vault below
const vars = [
  ["NEXT_PUBLIC_SUPABASE_URL", `https://${STAGING_REF}.supabase.co`, "plain"],
  ["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", PUBLISHABLE, "plain"],
  ["NEXT_PUBLIC_SITE_URL", site, "plain"],
  ["SUPABASE_SERVICE_ROLE_KEY", serviceKey, "sensitive"],
  ["B2C_INTERNAL_KEY", internalKey, "sensitive"],
  ["LIVE_MODE", "off", "plain"],
  ["SMTP_HOST", process.env.SMTP_HOST, "plain"],
  ["SMTP_PORT", process.env.SMTP_PORT ?? "587", "plain"],
  ["SMTP_USER", process.env.SMTP_USER, "plain"],
  ["SMTP_PASSWORD", process.env.SMTP_PASSWORD, "sensitive"],
  ["SMTP_FROM", `Eduwit Spark <${(process.env.SMTP_FROM ?? "").match(/<([^>]+)>/)?.[1] ?? process.env.SMTP_USER}>`, "plain"], // the app's name, whatever the variable says
];
if (!existing.has("LINK_SECRET")) vars.push(["LINK_SECRET", randomBytes(32).toString("hex"), "sensitive"]); // signed links must survive redeploys
if (!existing.has("VAPID_PRIVATE_KEY")) { // phone alerts: a key pair made once; devices stay subscribed across deploys
  const vapid = webpush.generateVAPIDKeys();
  vars.push(["NEXT_PUBLIC_VAPID_PUBLIC_KEY", vapid.publicKey, "plain"], ["VAPID_PRIVATE_KEY", vapid.privateKey, "sensitive"], ["VAPID_SUBJECT", "mailto:connect@eduwit.in", "plain"]);
}
const body = vars.filter(([, v]) => v).map(([key, value, type]) => ({ key, value, type, target: ["production", "preview"] }));
await api("POST", `/v10/projects/${project.id}/env?upsert=true`, body);
console.log(`env      ${body.map((v) => v.key).join(", ")}`);

// 4. deploy this branch as the production deployment
const repoId = project.link?.repoId ?? (await api("GET", `/v9/projects/${project.id}`)).link?.repoId;
if (!repoId) throw new Error("The project is not linked to GitHub (is the Vercel GitHub app installed on the repo?).");
const dep = await api("POST", "/v13/deployments", { name: NAME, project: project.id, target: "production", gitSource: { type: "github", repoId, ref: branch } });
console.log(`deploy   ${dep.id} from ${branch}`);
let state = dep.readyState;
for (let i = 0; i < 90 && !["READY", "ERROR", "CANCELED"].includes(state); i++) {
  await new Promise((r) => setTimeout(r, 10_000));
  state = (await api("GET", `/v13/deployments/${dep.id}`)).readyState;
}
console.log(`state    ${state}`);
if (state !== "READY") throw new Error(`Deployment ended ${state}: see https://vercel.com/${TEAM_SLUG}/${NAME}`);

// 5. the database timers call the app at its address with the same key
const db = createClient(`https://${STAGING_REF}.supabase.co`, serviceKey, { auth: { persistSession: false } });
const { error } = await db.schema("b2c").rpc("app_deploy_set", { p_base_url: site, p_internal_key: internalKey });
if (error) throw new Error(`app_deploy_set: ${error.message}`);
console.log("timers   pointed at the site");

const login = await fetch(`${site}/login`);
console.log(`check    /login ${login.status}`);
