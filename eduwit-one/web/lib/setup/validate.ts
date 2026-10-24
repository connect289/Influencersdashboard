import { z } from "zod";
import { acceptsEffort, AnthropicModelClient, type ModelClient } from "../ai/client.ts";
import { aiSettingsSchema, route, TIERS } from "../ai/models.ts";
import { RealAppHealthClient } from "../clients/app-health.ts";
import { RealChatwootClient } from "../clients/chatwoot.ts";
import type { Credentials } from "../clients/credentials.ts";
import { RealEmailClient } from "../clients/email.ts";
import { RealN8nClient } from "../clients/n8n.ts";
import { RealVercelClient } from "../clients/vercel.ts";
import { RealWhatsAppClient } from "../clients/whatsapp.ts";
import { fetchJson, HttpError } from "../http.ts";
import type { Settings } from "../state.ts";
import { RealB2bApi, RealRunnerApi, RealWaSender, waRouteProblem } from "../tests/apps.ts";

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
    /** one.settings.ai, for the ai_key validator (0018). */
    aiSettings(): Promise<unknown>;
  };
  /** Where the test runner login signs in (the shared Supabase project's API). */
  supabase?: { url?: string; anonKey?: string };
};

const testFactsSchema = z.object({
  identities: z.looseObject({
    runner_email: z.string().nullish(),
    partner_slug: z.string().nullish(),
    whatsapp_number: z.string().nullish(),
    whatsapp_phone_number_id: z.string().nullish(),
    witty_number: z.string().nullish(),
  }),
  whatsapp_trusted: z.boolean().optional(),
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
      case "b2b_intake": {
        // Writes nothing: B2B checks the key before the body (D-070).
        if (!credentials.b2bIntake) return missing("one_b2b_intake_key");
        const status = await new RealB2bApi(settings.hosts.b2b_app, credentials.b2bIntake, null).checkKey();
        return status === 400
          ? { ok: true, detail: "B2B accepts the key (it refused an empty body after checking the key)" }
          : {
              ok: false,
              detail: status === 401 ? "B2B refuses the key, or it lacks the intake scope" : `B2B answered ${status}`,
            };
      }
      case "test_partner": {
        // Writes nothing: B2B checks the signature before it reads the event, then refuses it for lacking an event id.
        const slug = (await deps.facts.testFacts())?.identities.partner_slug;
        if (!slug) return { ok: false, detail: "test_identities.partner_slug is not set" };
        if (!credentials.b2bIntake) return missing("one_b2b_intake_key");
        if (!credentials.testPartnerSecret) return missing("one_test_partner_secret");
        const b2b = new RealB2bApi(settings.hosts.b2b_app, credentials.b2bIntake, credentials.testPartnerSecret);
        const status = await b2b.checkPartner(slug, Date.now());
        const why: Record<number, string> = {
          401: "B2B refuses the signature: the secret is not the partner's inbound secret",
          404: "B2B knows no such partner, or it has no inbound secret",
        };
        return status === 400
          ? { ok: true, detail: `B2B accepts events signed for ${slug}` }
          : { ok: false, detail: why[status] ?? `B2B answered ${status}` };
      }
      case "test_whatsapp": {
        const f = await deps.facts.testFacts();
        const ids = f?.identities;
        if (!ids?.whatsapp_number || !ids.whatsapp_phone_number_id || !ids.witty_number) {
          return {
            ok: false,
            detail: "set whatsapp_number, whatsapp_phone_number_id and witty_number in test_identities",
          };
        }
        if (!credentials.testWhatsapp) return missing("one_test_wa_token");
        if (!f?.whatsapp_trusted) return { ok: false, detail: "the test number is not in w2_trusted with is_test" };
        const wittyId = settings.whatsapp.phone_ids?.witty;
        const wa = new RealWaSender(settings.vendors.graph_api, credentials.testWhatsapp, {
          fromPhoneId: ids.whatsapp_phone_number_id,
          to: ids.witty_number,
          witty: wittyId && credentials.whatsapp ? { phoneId: wittyId, token: credentials.whatsapp } : null,
        });
        const problem = await waRouteProblem(wa, {
          whatsapp_number: ids.whatsapp_number,
          witty_number: ids.witty_number,
        });
        return problem
          ? { ok: false, detail: problem }
          : {
              ok: true,
              detail:
                "the sender is the test number, the recipient is Witty's number, and Witty trusts it as a test number",
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
      case "ai": {
        // Each tier's model, price and key, the refusal fallback, and a free call that proves the key and each model
        // (Claude only, owner 24 Oct; D-075).
        const ai = aiSettingsSchema.safeParse(await deps.facts.aiSettings());
        if (!ai.success) return { ok: false, detail: "Settings → AI cannot be read" };
        const key = credentials.anthropic;
        if (!key) return { ok: false, detail: "no Anthropic key (Vault one_anthropic_key or ONE_ANTHROPIC_API_KEY)" };
        const client: ModelClient = new AnthropicModelClient(key);
        const proved = new Map<string, { ok: boolean; detail: string }>();
        const prove = async (model: string) => {
          if (!proved.has(model)) proved.set(model, await client.check(model));
          return proved.get(model) ?? { ok: false, detail: "not checked" };
        };
        const lines: string[] = [];
        let ok = true;
        for (const tier of TIERS) {
          const r = route(ai.data, "triage", tier);
          if ("error" in r) {
            ok = false;
            lines.push(`${tier}: ${r.detail}`);
            continue;
          }
          const v = await prove(r.model);
          ok &&= v.ok;
          const effort = r.effort && !acceptsEffort(r.model) ? ", effort not sent to this model" : "";
          lines.push(
            `${tier}${r.tier !== tier ? ` (falls back to ${r.tier})` : ""}: ${v.ok ? `${r.model}${effort}` : v.detail}`,
          );
        }
        const fb = ai.data.refusal_fallback;
        if (fb) {
          if (!ai.data.prices[fb]) {
            ok = false;
            lines.push(`refusal fallback ${fb}: no price in Settings → AI`);
          } else {
            const v = await prove(fb);
            ok &&= v.ok;
            lines.push(`refusal fallback: ${v.ok ? fb : v.detail}`);
          }
        }
        return { ok, detail: lines.join("; ") };
      }
      default:
        return { ok: false, detail: `nothing to validate for ${kind}` };
    }
  } catch (e) {
    return failure(e);
  }
}
