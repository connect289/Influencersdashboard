// Probes for Eduwit's own apps, the alerting and monitoring services, and the test identities.
import { env, field, http, list, unreachable, hostOf, type Defaults, type HostKey, type Row } from "./lib.ts";

export async function probeUptimeRobot(cfg: Defaults): Promise<Row> {
  const key = env("ONE_UPTIMEROBOT_KEY", "UPTIMEROBOT_API_KEY");
  const ran = `POST ${cfg.vendors.uptimerobot_api}/getMonitors and /getAlertContacts`;
  if (!key) return { id: "uptimerobot", status: "not_provided", ran, detail: "no UptimeRobot key" };
  const form = { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: `api_key=${encodeURIComponent(key)}&format=json` };
  const monitors = await http(`${cfg.vendors.uptimerobot_api}/getMonitors`, form);
  if (field(monitors.body, "stat") !== "ok") return { id: "uptimerobot", status: "refused", ran, detail: `HTTP ${monitors.status}`, fix: unreachable(monitors, "api.uptimerobot.com") ?? "create a read-only API key" };
  const rows = list(field(monitors.body, "monitors"));
  const up = rows.filter((m) => m.status === 2).length;
  const contacts = await http(`${cfg.vendors.uptimerobot_api}/getAlertContacts`, form);
  // UptimeRobot alert contact status: 0 not activated, 1 paused, 2 active.
  const contactStates = list(field(contacts.body, "alert_contacts")).map((c) => ({ 0: "not activated", 1: "paused", 2: "active" })[Number(c.status) as 0 | 1 | 2] ?? String(c.status));
  const active = contactStates.includes("active");
  return {
    id: "uptimerobot",
    status: "verified",
    ran,
    detail: `${up}/${rows.length} monitors up (${rows.map((m) => String(m.friendly_name)).join(", ")}); alert contacts: ${contactStates.join(", ") || "none"}`,
    fix: active ? undefined : "activate the alert contact in UptimeRobot, or its monitors never email",
  };
}

export async function probeResend(cfg: Defaults): Promise<Row> {
  const key = env("ONE_EMAIL_KEY", "RESEND_API_KEY");
  const ran = `GET ${cfg.vendors.resend_api}/domains and /emails?limit=1`;
  if (!key) return { id: "email", status: "not_provided", ran, detail: "no Resend key" };
  const headers = { authorization: `Bearer ${key}` };
  const domains = await http(`${cfg.vendors.resend_api}/domains`, { headers });
  if (domains.status !== 200) return { id: "email", status: "refused", ran, detail: `HTTP ${domains.status}`, fix: unreachable(domains, "api.resend.com") ?? "create a full-access Resend key" };
  const domain = list(field(domains.body, "data")).find((d) => d.name === cfg.email.domain);
  const emails = await http(`${cfg.vendors.resend_api}/emails?limit=1`, { headers });
  const last = list(field(emails.body, "data"))[0];
  const verified = domain?.status === "verified";
  return {
    id: "email",
    status: verified ? "verified" : "refused",
    ran,
    detail: `domain ${cfg.email.domain}: ${String(domain?.status ?? "absent")}; last email ${String(last?.created_at ?? "none")} ${String(last?.last_event ?? "")}`.trim(),
    fix: verified ? undefined : `verify ${cfg.email.domain} in Resend`,
  };
}

export async function probeB2bApi(cfg: Defaults): Promise<Row> {
  const key = env("ONE_B2B_READ_KEY", "B2B_READ_API_KEY");
  const url = `${cfg.hosts.b2b_app}/v1/referrals/EDUWITONEPREFLIGHT/outcomes?limit=1`;
  const ran = `GET ${url}`;
  if (!key) return { id: "b2b_app", status: "not_provided", ran, detail: "no B2B API key" };
  const r = await http(url, { headers: { authorization: `Bearer ${key}` } });
  if (r.status !== 200 || field(r.body, "ok") !== true) return { id: "b2b_app", status: "refused", ran, detail: `HTTP ${r.status}`, fix: unreachable(r, hostOf(cfg.hosts.b2b_app)) ?? "create a referrals-scoped key in the B2B admin" };
  return { id: "b2b_app", status: "verified", ran, detail: "referrals endpoint answered ok:true" };
}

/** Public health of each app host; the item id is the setup item each host unblocks. */
export async function probeHealth(cfg: Defaults, app: HostKey, itemId: string): Promise<Row> {
  const url = `${cfg.hosts[app]}${cfg.health_paths[app] ?? "/"}`;
  const ran = `GET ${url}`;
  const r = await http(url, {}, 10_000);
  if (r.status === 0) return { id: itemId, status: "refused", ran, detail: `no connection (${r.error ?? "error"})`, fix: unreachable(r, hostOf(url)) };
  const ok = r.status >= 200 && r.status < 400 && field(r.body, "ok") !== false && field(r.body, "status") !== "degraded";
  return { id: itemId, status: ok ? "verified" : "refused", ran, detail: `HTTP ${r.status}${typeof r.body === "object" && r.body ? ` ${JSON.stringify(r.body).slice(0, 120)}` : ""}` };
}

export async function probeWhatsApp(cfg: Defaults): Promise<Row> {
  const token = env("ONE_WHATSAPP_TOKEN");
  const wabas = env("ONE_WHATSAPP_WABA_IDS")?.split(",").map((s) => s.trim()).filter(Boolean) ?? [];
  const ran = `GET ${cfg.vendors.graph_api}/<waba>/message_templates?limit=1`;
  if (!token || wabas.length === 0) return { id: "whatsapp", status: "not_provided", ran, detail: "no WhatsApp token or WABA ids", fix: "Meta Business → System users → token with whatsapp_business_management; or approve reuse of Vault b2b_whatsapp_token" };
  const results: string[] = [];
  for (const waba of wabas) {
    const r = await http(`${cfg.vendors.graph_api}/${waba}/message_templates?limit=1`, { headers: { authorization: `Bearer ${token}` } });
    results.push(`${waba.slice(-4)}: HTTP ${r.status}`);
  }
  const ok = results.every((s) => s.endsWith("200"));
  return { id: "whatsapp", status: ok ? "verified" : "refused", ran, detail: results.join(", ") };
}

export async function probeAiKey(cfg: Defaults): Promise<Row> {
  const gemini = env("ONE_GEMINI_API_KEY");
  const anthropic = env("ONE_ANTHROPIC_API_KEY");
  if (gemini) {
    const r = await http(`${cfg.vendors.gemini_api}/models?pageSize=1`, { headers: { "x-goog-api-key": gemini } });
    return { id: "ai_key", status: r.status === 200 ? "verified" : "refused", ran: `GET ${cfg.vendors.gemini_api}/models`, detail: `Gemini HTTP ${r.status}` };
  }
  if (anthropic) {
    const r = await http(`${cfg.vendors.anthropic_api}/models?limit=1`, { headers: { "x-api-key": anthropic, "anthropic-version": "2023-06-01" } });
    return { id: "ai_key", status: r.status === 200 ? "verified" : "refused", ran: `GET ${cfg.vendors.anthropic_api}/models`, detail: `Anthropic HTTP ${r.status}` };
  }
  return { id: "ai_key", status: "not_provided", ran: "looked for ONE_GEMINI_API_KEY / ONE_ANTHROPIC_API_KEY", detail: "no model key in the environment (Vault presence is checked by the database probes)" };
}

/**
 * Identities that live only in the environment or defaults; database-backed ones (test phone, Spark test
 * user, test partner, test creator) come from the database probe or the connector merge file. An intake key
 * is only checked for presence: exercising it would create a lead, which only the synthetic test may do.
 */
export async function probeIdentities(cfg: Defaults): Promise<Row[]> {
  const mailbox = env("ONE_TEST_MAILBOX") ?? cfg.test_identities.mailbox ?? undefined;
  const preview = env("ONE_WEBSITE_PREVIEW_URL") ?? cfg.test_identities.website_preview_url ?? undefined;
  const intake = env("ONE_B2B_INTAKE_KEY", "B2B_INTAKE_TEST_KEY");
  const rows: Row[] = [
    mailbox
      ? { id: "test_mailbox", status: "verified", ran: "read ONE_TEST_MAILBOX", detail: "present; read access is exercised by T-WEB-ENQUIRY" }
      : { id: "test_mailbox", status: "not_provided", ran: "read ONE_TEST_MAILBOX", detail: "missing" },
    intake
      ? { id: "test_b2b_intake_key", status: "verified", ran: "read ONE_B2B_INTAKE_KEY (presence only)", detail: "present; exercised only by T-B2B-INTAKE on a test lead" }
      : { id: "test_b2b_intake_key", status: "not_provided", ran: "read ONE_B2B_INTAKE_KEY", detail: "missing" },
  ];
  if (!preview) {
    rows.push({ id: "test_preview_url", status: "not_provided", ran: "read ONE_WEBSITE_PREVIEW_URL", detail: "missing" });
  } else {
    const r = await http(`${preview}/api/health`, {}, 10_000);
    rows.push({ id: "test_preview_url", status: r.status === 200 ? "verified" : "refused", ran: `GET ${preview}/api/health`, detail: `HTTP ${r.status}`, fix: unreachable(r, hostOf(preview)) });
  }
  return rows;
}
