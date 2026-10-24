import { z } from "zod";
import { RealAppHealthClient } from "../clients/app-health.ts";
import { RealChatwootClient } from "../clients/chatwoot.ts";
import type { Credentials } from "../clients/credentials.ts";
import { RealEmailClient } from "../clients/email.ts";
import { RealN8nClient } from "../clients/n8n.ts";
import { RealVercelClient } from "../clients/vercel.ts";
import { RealWhatsAppClient } from "../clients/whatsapp.ts";
import { fetchJson, HttpError } from "../http.ts";
import type { Settings } from "../state.ts";
import { RealRunnerApi } from "../tests/apps.ts";

// The Setup page's validate buttons (spec §15): each exercises the value it checks, with the same client the probes
// use, so "validated" means the real call worked (standard 2: the validate button is the contract test).

export type Verdict = { ok: boolean; detail: string };
export type ValidateDeps = {
  settings: Settings;
  credentials: Credentials;
  /** Database facts the browser cannot fake: a check's last status, a heartbeat's verdict, the test items (0016). */
  facts: {
    checkStatus(id: string): Promise<string | null>;
    heartbeatOk(component: string): Promise<boolean>;
    testFacts(): Promise<TestFacts | null>;
  };
  /** Where the test runner login signs in (the shared Supabase project's API). */
  supabase?: { url?: string; anonKey?: string };
};

const testFactsSchema = z.object({
  identities: z.looseObject({ runner_email: z.string().nullish() }),
  spark_journey: z.object({
    found: z.boolean(),
    test_mode: z.boolean().optional(),
    published: z.boolean().optional(),
    status: z.string().nullish(),
    steps: z.number().optional(),
  }),
});
export type TestFacts = z.infer<typeof testFactsSchema>;
export const parseTestFacts = (v: unknown): TestFacts => testFactsSchema.parse(v);

const missing = (what: string): Verdict => ({ ok: false, detail: `${what} is not set (Vercel env or Vault)` });

function failure(e: unknown): Verdict {
  if (e instanceof HttpError) return { ok: false, detail: `the call failed: ${e.message}` };
  return { ok: false, detail: "the call failed" };
}

const monitorsSchema = z.object({
  stat: z.string(),
  monitors: z.array(z.object({ url: z.string(), status: z.number() })).optional(),
});

async function uptimeMonitors(deps: ValidateDeps) {
  const key = deps.credentials.uptimerobot;
  if (!key) return null;
  const api = (deps.settings.vendors as Record<string, string>).uptimerobot_api ?? "https://api.uptimerobot.com/v2";
  const { json } = await fetchJson("uptimerobot", `${api}/getMonitors`, {
    method: "POST",
    body: { api_key: key, format: "json" },
  });
  return monitorsSchema.parse(json);
}

export async function validate(kind: string, deps: ValidateDeps): Promise<Verdict> {
  const { settings, credentials } = deps;
  try {
    if (kind.startsWith("health:")) {
      const host = kind.slice(7) as keyof Settings["hosts"];
      const base = settings.hosts[host];
      if (!base) return { ok: false, detail: `no host ${host} in Settings → Hosts` };
      const path = settings.health_paths[host] ?? "/api/health";
      const r = await new RealAppHealthClient().health(`${base}${path}`, path === "/" ? "reachable" : "json_ok");
      return { ok: r.ok, detail: `GET ${base}${path}: HTTP ${r.status} in ${r.ms} ms` };
    }
    switch (kind) {
      case "n8n": {
        if (!credentials.n8n) return missing("one_n8n_key");
        const w = await new RealN8nClient(settings.hosts.n8n, credentials.n8n).workflow(settings.n8n.witty_workflow_id);
        return { ok: true, detail: `workflow "${w.name}" read; active: ${w.active}` };
      }
      case "chatwoot": {
        if (!credentials.chatwoot) return missing("one_chatwoot_token");
        const n = await new RealChatwootClient(settings.hosts.chatwoot, credentials.chatwoot).inboxCount(
          settings.chatwoot.account_id,
        );
        return { ok: true, detail: `${n} inbox${n === 1 ? "" : "es"} in account ${settings.chatwoot.account_id}` };
      }
      case "vercel": {
        if (!credentials.vercel) return missing("one_vercel_token");
        const project = settings.vercel.projects.website ?? "";
        const d = await new RealVercelClient(settings.vendors.vercel_api, credentials.vercel).latestProduction(
          project,
          settings.vercel.team,
        );
        return {
          ok: d !== null,
          detail: d ? `${project}: latest production deployment ${d.state}` : `${project}: no production deployment`,
        };
      }
      case "whatsapp": {
        if (!credentials.whatsapp) return missing("one_whatsapp_token");
        const phone = Object.values(settings.whatsapp.phone_ids ?? {})[0];
        if (!phone) return { ok: false, detail: "no phone number id in Settings → WhatsApp" };
        const p = await new RealWhatsAppClient(settings.vendors.graph_api, credentials.whatsapp).phoneNumber(phone);
        return { ok: true, detail: `phone ${phone}: status ${p.status ?? "?"}, quality ${p.quality_rating ?? "?"}` };
      }
      case "email": {
        if (!credentials.email) return missing("one_email_key");
        const to = z.array(z.string()).parse((settings.alerts as { p1?: { email?: unknown } }).p1?.email ?? [])[0];
        if (!to) return { ok: false, detail: "no P1 inbox in Settings → Alerts" };
        const { id } = await new RealEmailClient(settings.vendors.resend_api, credentials.email).send({
          from: settings.alerts.email_from,
          to,
          subject: "Eduwit One: test email from the Setup page",
          text: "This is a test from Eduwit One's Setup page. P1 alerts will arrive like this.",
          html: "<p>This is a test from Eduwit One's Setup page. P1 alerts will arrive like this.</p>",
          idempotencyKey: `setup-test:${Date.now()}`,
        });
        return { ok: true, detail: `test email to ${to} accepted (${id})` };
      }
      case "uptimerobot": {
        const m = await uptimeMonitors(deps);
        if (!m) return missing("one_uptimerobot_key");
        return { ok: m.stat === "ok", detail: `${m.monitors?.length ?? 0} monitors listed` };
      }
      case "watchdog": {
        const m = await uptimeMonitors(deps);
        if (!m) return missing("one_uptimerobot_key");
        const w = m.monitors?.find((x) => x.url.includes("/api/watchdog"));
        return w
          ? { ok: w.status === 2, detail: `monitor on ${w.url}: ${w.status === 2 ? "up" : `status ${w.status}`}` }
          : { ok: false, detail: "no monitor on /api/watchdog" };
      }
      case "plat05": {
        const s = await deps.facts.checkStatus("PLAT-05");
        return { ok: s === "ok", detail: `PLAT-05 last reported ${s ?? "nothing yet"}` };
      }
      case "api_schema":
        return { ok: true, detail: "this page read schema one through the Data API" };
      case "test_runner": {
        // Signs in as the login (password, then the one-time code) and asks each CRM what it is there.
        const f = await deps.facts.testFacts();
        const email = f?.identities.runner_email;
        if (!email) return { ok: false, detail: "test_identities.runner_email is not set" };
        if (!credentials.testRunnerPassword) return missing("one_test_runner_password");
        if (!credentials.testRunnerTotp) return missing("one_test_runner_totp");
        if (!deps.supabase?.url || !deps.supabase.anonKey) return missing("ONE_SUPABASE_URL or ONE_SUPABASE_ANON_KEY");
        const runner = new RealRunnerApi(deps.supabase.url, deps.supabase.anonKey, {
          email,
          password: credentials.testRunnerPassword,
          totpSecret: credentials.testRunnerTotp,
        });
        const admin = (await runner.rpc("b2b", "is_admin", {})) === true;
        const role = z
          .string()
          .nullable()
          .catch(null)
          .parse(await runner.rpc("b2c", "my_role", {}));
        return {
          ok: admin && role === "admin",
          detail: `signed in with two-factor; B2B admin: ${admin ? "yes" : "no"}; Spark role: ${role ?? "none"}`,
        };
      }
      case "spark_journey": {
        const j = (await deps.facts.testFacts())?.spark_journey;
        if (!j?.found) return { ok: false, detail: "no Spark journey with test_identities.spark_test_journey_id" };
        const ok = j.test_mode === true && j.published === true && (j.steps ?? 0) > 0;
        return {
          ok,
          detail: `journey ${j.status ?? "?"}, test mode ${j.test_mode ? "on" : "off"}, ${j.published ? `${j.steps ?? 0} published steps` : "not published"}`,
        };
      }
      case "app_link": {
        const ok = await deps.facts.heartbeatOk("one:app");
        return {
          ok,
          detail: ok
            ? "the database called the app and it answered (heartbeat one:app)"
            : "no recent answer from the app to the minute tick",
        };
      }
      default:
        return { ok: false, detail: `nothing to validate for ${kind}` };
    }
  } catch (e) {
    return failure(e);
  }
}
