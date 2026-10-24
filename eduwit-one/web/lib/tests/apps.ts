import { createHmac } from "node:crypto";
import { z } from "zod";
import type { Credentials } from "../clients/credentials.ts";
import { DEFAULT_POLICY, fetchJson, HttpError, type HttpPolicy } from "../http.ts";
import type { Settings } from "../state.ts";
import { totp } from "./totp.ts";
import type { Identities } from "./types.ts";

// The apps' own doors a journey uses outside schema one (D-070): B2B's intake API with the intake-only key, B2B's
// partner events signed as the test partner, app functions called as the test runner login (password and one-time
// code, so the session is two-factor), Witty's test harness in n8n, the test WhatsApp sender and Chatwoot's message
// list. Each is built only when what it needs is set; a journey's guard refuses to start without it. None of them
// returns a contact field to the journey, and none retries a call that is not safe to repeat.

const ONCE: HttpPolicy = { ...DEFAULT_POLICY, retries: 0, timeoutMs: 10_000 };

export type IntakeResult = { status: number; leadId: number; isTest: boolean; action: string; routing: string | null };

export interface B2bApi {
  /** Whether partner events can be signed (the test partner's secret is set). */
  readonly canSign: boolean;
  /** POST /v1/leads. A repeated idempotency key returns the stored answer, so this one may retry. */
  intake(body: Record<string, unknown>, idempotencyKey: string): Promise<IntakeResult>;
  /** POST /v1/partners/{slug}/events, signed with the test partner's inbound secret. */
  partnerEvent(slug: string, event: Record<string, unknown>, nowMs: number): Promise<{ status: number }>;
}

export interface RunnerApi {
  /** An app function called as the test runner login, in the app's schema. */
  rpc(schema: "b2b" | "b2c", fn: string, args: Record<string, unknown>): Promise<unknown>;
  /** Ends the session this pass signed in with, if any. */
  signOut(): Promise<void>;
}

export interface Harness {
  active(): Promise<boolean>;
  setActive(on: boolean): Promise<void>;
  /** Starts the configured scenario under a run tag; Witty records the run in w2_test_runs. */
  start(runTag: string): Promise<{ accepted: boolean }>;
}

export interface WaSender {
  /** A text from the test number to Witty's number. */
  send(text: string): Promise<{ id: string }>;
  /**
   * The numbers WhatsApp itself gives for the sender (the test number's id) and for Witty's own number id
   * (settings.whatsapp.phone_ids.witty), digits only: a run sends only when they are the test number and Witty's.
   */
  numbers(): Promise<{ sender: string | null; witty: string | null }>;
}

export interface ChatwootReader {
  /** Outgoing messages in a conversation since a time; only their type and time are read. */
  outgoingSince(conversationId: number, sinceUnix: number): Promise<number>;
}

export type TestApps = {
  b2b: B2bApi | null;
  runner: RunnerApi | null;
  harness: Harness | null;
  wa: WaSender | null;
  chatwoot: ChatwootReader | null;
};

const intakeSchema = z.object({
  ok: z.literal(true),
  lead_id: z.number(),
  action: z.string(),
  is_test: z.boolean(),
  routing: z.object({ status: z.string().nullable().optional() }).nullable().optional(),
});

export class RealB2bApi implements B2bApi {
  private readonly base: string;
  private readonly intakeKey: string;
  private readonly partnerSecret: string | null;

  constructor(base: string, intakeKey: string, partnerSecret: string | null) {
    this.base = base;
    this.intakeKey = intakeKey;
    this.partnerSecret = partnerSecret;
  }

  get canSign(): boolean {
    return this.partnerSecret !== null;
  }

  /** The status of a call B2B refuses before it stores anything, or 200 when it unexpectedly accepts it. */
  private async refusal(path: string, headers: Record<string, string>, body: Record<string, unknown>): Promise<number> {
    try {
      return (await fetchJson("test_b2b", `${this.base}${path}`, { method: "POST", headers, body }, ONCE)).status;
    } catch (e) {
      if (e instanceof HttpError && e.status !== undefined) return e.status;
      throw e;
    }
  }

  /**
   * Setup check of the intake key, writing nothing: B2B checks the key before the body, so an empty body answers 400
   * with a good key and 401 with a bad one.
   */
  async checkKey(): Promise<number> {
    return this.refusal(
      "/v1/leads",
      { authorization: `Bearer ${this.intakeKey}`, "idempotency-key": "eduwit-one-setup-check" },
      {},
    );
  }

  /**
   * Setup check of the partner secret, writing nothing: B2B checks the signature before it reads the event, so a signed
   * event without an event_id answers 400 with the right secret, 401 with a wrong one and 404 for an unknown partner.
   */
  async checkPartner(slug: string, nowMs: number): Promise<number> {
    if (!this.partnerSecret) return 0;
    const ts = String(Math.floor(nowMs / 1000));
    const event = { type: "contacted" };
    const signature = createHmac("sha256", this.partnerSecret)
      .update(`${ts}.${JSON.stringify(event)}`)
      .digest("hex");
    return this.refusal(
      `/v1/partners/${encodeURIComponent(slug)}/events`,
      { "x-eduwit-timestamp": ts, "x-eduwit-signature": `sha256=${signature}` },
      event,
    );
  }

  async intake(body: Record<string, unknown>, idempotencyKey: string): Promise<IntakeResult> {
    const r = await fetchJson("test_b2b", `${this.base}/v1/leads`, {
      method: "POST",
      headers: { authorization: `Bearer ${this.intakeKey}`, "idempotency-key": idempotencyKey },
      body,
    });
    const j = intakeSchema.parse(r.json);
    return {
      status: r.status,
      leadId: j.lead_id,
      isTest: j.is_test,
      action: j.action,
      routing: j.routing?.status ?? null,
    };
  }

  async partnerEvent(slug: string, event: Record<string, unknown>, nowMs: number): Promise<{ status: number }> {
    if (!this.partnerSecret) throw new Error("the test partner's secret is not set (Setup item test_partner)");
    const ts = String(Math.floor(nowMs / 1000));
    // fetchJson sends JSON.stringify(body), so this is the raw body B2B checks the signature against.
    const signature = createHmac("sha256", this.partnerSecret)
      .update(`${ts}.${JSON.stringify(event)}`)
      .digest("hex");
    const r = await fetchJson("test_b2b", `${this.base}/v1/partners/${encodeURIComponent(slug)}/events`, {
      method: "POST",
      headers: { "x-eduwit-timestamp": ts, "x-eduwit-signature": `sha256=${signature}` },
      body: event,
    });
    return { status: r.status };
  }
}

const tokenSchema = z.object({
  access_token: z.string(),
  expires_in: z.number(),
  user: z
    .object({ factors: z.array(z.object({ id: z.string(), factor_type: z.string(), status: z.string() })).nullish() })
    .nullish(),
});

/** One claim of a JWT the auth server just issued (read, not verified: it came straight from the issuer). */
export function jwtClaim(token: string, claim: string): unknown {
  const part = token.split(".")[1];
  if (!part) return undefined;
  try {
    return (JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as Record<string, unknown>)[claim];
  } catch {
    return undefined;
  }
}

/**
 * The test runner login (D-070). Signs in with the password, then proves the TOTP factor, so the session is aal2 as the
 * B2B CRM's admin functions require. One instance serves one pass: it signs in on its first call and the pass signs it
 * out at its end, so no session outlives the invocation. The password and the TOTP secret come from Vault and are never
 * logged.
 */
export class RealRunnerApi implements RunnerApi {
  private readonly url: string;
  private readonly anonKey: string;
  private readonly email: string;
  private readonly password: string;
  private readonly totpSecret: string;
  private readonly now: () => number;
  private session: { token: string; until: number } | undefined;

  constructor(
    url: string,
    anonKey: string,
    login: { email: string; password: string; totpSecret: string },
    now: () => number = Date.now,
  ) {
    this.url = url;
    this.anonKey = anonKey;
    this.email = login.email;
    this.password = login.password;
    this.totpSecret = login.totpSecret;
    this.now = now;
  }

  private async signIn(): Promise<string> {
    const auth = (token?: string) => ({ apikey: this.anonKey, ...(token ? { authorization: `Bearer ${token}` } : {}) });
    const first = tokenSchema.parse(
      (
        await fetchJson(
          "test_runner_auth",
          `${this.url}/auth/v1/token?grant_type=password`,
          { method: "POST", headers: auth(), body: { email: this.email, password: this.password } },
          ONCE,
        )
      ).json,
    );
    const factor = first.user?.factors?.find((f) => f.factor_type === "totp" && f.status === "verified");
    if (!factor) throw new Error("the test runner login has no verified TOTP factor (Setup item test_runner_user)");
    const challenge = z
      .object({ id: z.string() })
      .parse(
        (
          await fetchJson(
            "test_runner_auth",
            `${this.url}/auth/v1/factors/${encodeURIComponent(factor.id)}/challenge`,
            { method: "POST", headers: auth(first.access_token), body: {} },
            ONCE,
          )
        ).json,
      );
    const verified = tokenSchema.parse(
      (
        await fetchJson(
          "test_runner_auth",
          `${this.url}/auth/v1/factors/${encodeURIComponent(factor.id)}/verify`,
          {
            method: "POST",
            headers: auth(first.access_token),
            body: { challenge_id: challenge.id, code: totp(this.totpSecret, this.now()) },
          },
          ONCE,
        )
      ).json,
    );
    if (jwtClaim(verified.access_token, "aal") !== "aal2")
      throw new Error("the test runner sign-in did not reach aal2");
    this.session = { token: verified.access_token, until: this.now() + Math.max(0, verified.expires_in - 120) * 1000 };
    return verified.access_token;
  }

  async rpc(schema: "b2b" | "b2c", fn: string, args: Record<string, unknown>): Promise<unknown> {
    const token = this.session && this.session.until > this.now() ? this.session.token : await this.signIn();
    const r = await fetchJson(
      `test_runner_${schema}`,
      `${this.url}/rest/v1/rpc/${encodeURIComponent(fn)}`,
      {
        method: "POST",
        headers: {
          apikey: this.anonKey,
          authorization: `Bearer ${token}`,
          "content-profile": schema,
          "accept-profile": schema,
        },
        body: args,
      },
      ONCE,
    );
    return r.json;
  }

  async signOut(): Promise<void> {
    const session = this.session;
    this.session = undefined;
    if (!session) return;
    await fetchJson(
      "test_runner_auth",
      `${this.url}/auth/v1/logout?scope=local`,
      { method: "POST", headers: { apikey: this.anonKey, authorization: `Bearer ${session.token}` }, body: {} },
      ONCE,
    ).catch(() => undefined);
  }
}

const workflowSchema = z.object({ active: z.boolean() });

/** Witty's test harness workflow: switched on only while T-WITTY-QUALIFY runs (D-072). */
export class RealHarness implements Harness {
  private readonly base: string;
  private readonly apiKey: string;
  private readonly workflowId: string;
  private readonly webhookPath: string;
  private readonly scenario: string;

  constructor(base: string, apiKey: string, harness: { workflowId: string; webhookPath: string; scenario: string }) {
    this.base = base;
    this.apiKey = apiKey;
    this.workflowId = harness.workflowId;
    this.webhookPath = harness.webhookPath;
    this.scenario = harness.scenario;
  }

  private headers() {
    return { "X-N8N-API-KEY": this.apiKey };
  }

  async active(): Promise<boolean> {
    const r = await fetchJson("test_harness", `${this.base}/api/v1/workflows/${encodeURIComponent(this.workflowId)}`, {
      headers: this.headers(),
    });
    return workflowSchema.parse(r.json).active;
  }

  async setActive(on: boolean): Promise<void> {
    await fetchJson(
      "test_harness",
      `${this.base}/api/v1/workflows/${encodeURIComponent(this.workflowId)}/${on ? "activate" : "deactivate"}`,
      { method: "POST", headers: this.headers(), body: {} },
    );
  }

  async start(runTag: string): Promise<{ accepted: boolean }> {
    try {
      await fetchJson(
        "test_harness",
        `${this.base}${this.webhookPath}`,
        { method: "POST", body: { run_tag: runTag, only: [this.scenario] } },
        ONCE,
      );
      return { accepted: true };
    } catch (e) {
      // A webhook that answers only when the run ends times out here while the run goes on; the next step waits for
      // Witty's record of it, so a lost answer is not a failure.
      if (e instanceof Error && e.message === "timeout") return { accepted: false };
      throw e;
    }
  }
}

const waSentSchema = z.object({ messages: z.array(z.object({ id: z.string() })).min(1) });

const phoneNumberSchema = z.object({ display_phone_number: z.string().nullish() });

export class RealWaSender implements WaSender {
  private readonly graphBase: string;
  private readonly token: string;
  private readonly fromPhoneId: string;
  private readonly to: string;
  private readonly witty: { phoneId: string; token: string } | null;

  constructor(
    graphBase: string,
    token: string,
    route: { fromPhoneId: string; to: string; witty: { phoneId: string; token: string } | null },
  ) {
    this.graphBase = graphBase;
    this.token = token;
    this.fromPhoneId = route.fromPhoneId;
    this.to = route.to;
    this.witty = route.witty;
  }

  private async number(phoneId: string, token: string): Promise<string | null> {
    const q = new URLSearchParams({ fields: "display_phone_number" });
    const { json } = await fetchJson("test_whatsapp", `${this.graphBase}/${encodeURIComponent(phoneId)}?${q}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    const n = phoneNumberSchema.parse(json).display_phone_number;
    return n ? n.replace(/\D/g, "") : null;
  }

  async numbers(): Promise<{ sender: string | null; witty: string | null }> {
    return {
      sender: await this.number(this.fromPhoneId, this.token),
      witty: this.witty ? await this.number(this.witty.phoneId, this.witty.token) : null,
    };
  }

  async send(text: string): Promise<{ id: string }> {
    const r = await fetchJson(
      "test_whatsapp",
      `${this.graphBase}/${encodeURIComponent(this.fromPhoneId)}/messages`,
      {
        method: "POST",
        headers: { authorization: `Bearer ${this.token}` },
        body: { messaging_product: "whatsapp", to: this.to, type: "text", text: { body: text } },
      },
      ONCE,
    );
    const id = waSentSchema.parse(r.json).messages[0]?.id;
    if (!id) throw new Error("WhatsApp returned no message id");
    return { id };
  }
}

const messagesSchema = z.object({
  payload: z.array(z.object({ message_type: z.number(), created_at: z.number() })),
});

export class RealChatwootReader implements ChatwootReader {
  private readonly host: string;
  private readonly token: string;
  private readonly accountId: string;

  constructor(host: string, token: string, accountId: string) {
    this.host = host;
    this.token = token;
    this.accountId = accountId;
  }

  async outgoingSince(conversationId: number, sinceUnix: number): Promise<number> {
    const r = await fetchJson(
      "test_chatwoot",
      `${this.host}/api/v1/accounts/${encodeURIComponent(this.accountId)}/conversations/${conversationId}/messages`,
      { headers: { api_access_token: this.token } },
    );
    // message_type 1 is outgoing. The content of each message is in the answer but is not kept.
    return messagesSchema.parse(r.json).payload.filter((m) => m.message_type === 1 && m.created_at >= sinceUnix).length;
  }
}

export type AppsEnv = { supabaseUrl?: string; anonKey?: string; n8nBase?: string };

/** Builds what the credentials and settings allow. In mock mode (tests, previews) nothing is built. */
export function testAppsFor(
  settings: Settings,
  credentials: Credentials,
  identities: Identities,
  env: AppsEnv,
): TestApps {
  if (process.env.ONE_CLIENT_MODE === "mock")
    return { b2b: null, runner: null, harness: null, wa: null, chatwoot: null };
  const n8n = settings.n8n;
  return {
    b2b: credentials.b2bIntake
      ? new RealB2bApi(settings.hosts.b2b_app, credentials.b2bIntake, credentials.testPartnerSecret ?? null)
      : null,
    runner:
      env.supabaseUrl &&
      env.anonKey &&
      identities.runner_email &&
      credentials.testRunnerPassword &&
      credentials.testRunnerTotp
        ? new RealRunnerApi(env.supabaseUrl, env.anonKey, {
            email: identities.runner_email,
            password: credentials.testRunnerPassword,
            totpSecret: credentials.testRunnerTotp,
          })
        : null,
    harness:
      credentials.n8n && n8n.test_harness_workflow_id && n8n.test_harness_webhook_path
        ? new RealHarness(env.n8nBase ?? settings.hosts.n8n, credentials.n8n, {
            workflowId: n8n.test_harness_workflow_id,
            webhookPath: n8n.test_harness_webhook_path,
            scenario: n8n.test_harness_scenario ?? "happy_path_mba",
          })
        : null,
    wa:
      credentials.testWhatsapp && identities.whatsapp_phone_number_id && identities.witty_number
        ? new RealWaSender(settings.vendors.graph_api, credentials.testWhatsapp, {
            fromPhoneId: identities.whatsapp_phone_number_id,
            to: identities.witty_number,
            witty:
              settings.whatsapp.phone_ids?.witty && credentials.whatsapp
                ? { phoneId: settings.whatsapp.phone_ids.witty, token: credentials.whatsapp }
                : null,
          })
        : null,
    chatwoot: credentials.chatwoot
      ? new RealChatwootReader(settings.hosts.chatwoot, credentials.chatwoot, settings.chatwoot.account_id)
      : null,
  };
}

/** Why the test WhatsApp route is not safe to send on, or null: WhatsApp's own numbers must be the test identities. */
export async function waRouteProblem(
  wa: WaSender,
  identities: Pick<Identities, "whatsapp_number" | "witty_number">,
): Promise<string | null> {
  const digits = (v: string | null) => (v ?? "").replace(/\D/g, "");
  const n = await wa.numbers();
  if (!n.sender || n.sender !== digits(identities.whatsapp_number)) {
    return "WhatsApp does not give the sender id the test number (test_identities.whatsapp_number)";
  }
  if (!n.witty) return "Witty's own number cannot be read (settings.whatsapp.phone_ids.witty and the WhatsApp token)";
  if (n.witty !== digits(identities.witty_number)) {
    return "test_identities.witty_number is not Witty's own number, as WhatsApp gives it";
  }
  return null;
}
