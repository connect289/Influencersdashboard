// Probes for Eduwit's own apps, the alerting and monitoring services, and the test identities.
import { env, field, hostOf, http, list, refusedFix, safeUrl, unread, type Defaults, type HostKey, type Row } from "./lib.ts";

const CONTACT_STATES: Record<number, string> = { 0: "not activated", 1: "paused", 2: "active" };

export async function probeUptimeRobot(cfg: Defaults): Promise<Row> {
  const key = env("ONE_UPTIMEROBOT_KEY", "UPTIMEROBOT_API_KEY");
  const ran = `POST ${cfg.vendors.uptimerobot_api}/getMonitors and /getAlertContacts`;
  if (!key) return { id: "uptimerobot", status: "not_provided", ran, detail: "no UptimeRobot key" };
  const form = { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: `api_key=${encodeURIComponent(key)}&format=json` };
  const monitors = await http(`${cfg.vendors.uptimerobot_api}/getMonitors`, form);
  if (field(monitors.body, "stat") !== "ok") return { id: "uptimerobot", status: "refused", ran, detail: `HTTP ${monitors.status || monitors.error}`, fix: refusedFix(monitors, hostOf(cfg.vendors.uptimerobot_api), "create a read-only API key") };
  const rows = list(field(monitors.body, "monitors"));
  const up = rows.filter((m) => m.status === 2).length;
  const contacts = await http(`${cfg.vendors.uptimerobot_api}/getAlertContacts`, form);
  const contactsProblem = field(contacts.body, "stat") === "ok" ? undefined : unread("alert contacts", contacts) ?? "could not read alert contacts";
  const states = list(field(contacts.body, "alert_contacts")).map((c) => CONTACT_STATES[Number(c.status)] ?? `status ${String(c.status)}`);
  return {
    id: "uptimerobot",
    status: "verified",
    ran,
    detail: `${up}/${rows.length} monitors up (${rows.map((m) => String(m.friendly_name)).join(", ")}); alert contacts: ${contactsProblem ?? (states.join(", ") || "none")}`,
    fix: contactsProblem || states.includes("active") ? undefined : "activate the alert contact in UptimeRobot, or its monitors never email",
  };
}

export async function probeResend(cfg: Defaults): Promise<Row> {
  const key = env("ONE_EMAIL_KEY", "RESEND_API_KEY");
  const ran = `GET ${cfg.vendors.resend_api}/domains and /emails?limit=1`;
  if (!key) return { id: "email", status: "not_provided", ran, detail: "no Resend key" };
  const headers = { authorization: `Bearer ${key}` };
  const domains = await http(`${cfg.vendors.resend_api}/domains`, { headers });
  if (domains.status !== 200) return { id: "email", status: "refused", ran, detail: `HTTP ${domains.status || domains.error}`, fix: refusedFix(domains, hostOf(cfg.vendors.resend_api), "create a full-access Resend key") };
  const domain = list(field(domains.body, "data")).find((d) => d.name === cfg.email.domain);
  const emails = await http(`${cfg.vendors.resend_api}/emails?limit=1`, { headers });
  const last = list(field(emails.body, "data"))[0];
  const lastText = unread("recent emails", emails) ?? `last email ${String(last?.created_at ?? "none")} ${String(last?.last_event ?? "")}`.trim();
  const detail = `domain ${cfg.email.domain}: ${String(domain?.status ?? "absent")}; ${lastText}`;
  return domain?.status === "verified"
    ? { id: "email", status: "verified", ran, detail }
    : { id: "email", status: "refused", ran, detail, fix: `verify ${cfg.email.domain} in Resend (SPF and DKIM records)` };
}

/** Reads one referral's outcomes. Note: the B2B CRM records key usage (b2b.api_key_usage) for every keyed call (D-021). */
export async function probeB2bApi(cfg: Defaults): Promise<Row> {
  const key = env("ONE_B2B_READ_KEY", "B2B_READ_API_KEY");
  const url = `${cfg.hosts.b2b_app}/v1/referrals/${cfg.preflight.b2b_probe_referral_code}/outcomes?limit=1`;
  const ran = `GET ${safeUrl(url)}`;
  if (!key) return { id: "b2b_app", status: "not_provided", ran, detail: "no B2B API key" };
  const r = await http(url, { headers: { authorization: `Bearer ${key}` } });
  if (r.status !== 200 || field(r.body, "ok") !== true) return { id: "b2b_app", status: "refused", ran, detail: `HTTP ${r.status || r.error}`, fix: refusedFix(r, hostOf(cfg.hosts.b2b_app), "create a referrals-scoped key in the B2B admin") };
  return { id: "b2b_app", status: "verified", ran, detail: "referrals endpoint answered ok:true (the key's scopes are not visible to this call; see the annotation)" };
}

/** Public health of each app host; the item id is the setup item each host unblocks. */
export async function probeHealth(cfg: Defaults, app: HostKey, itemId: string): Promise<Row> {
  const url = `${cfg.hosts[app]}${cfg.health_paths[app] ?? "/"}`;
  const ran = `GET ${safeUrl(url)}`;
  const r = await http(url, {}, 10_000);
  const ok = r.status >= 200 && r.status < 400 && field(r.body, "ok") !== false && field(r.body, "status") !== "degraded";
  const summary = typeof r.body === "object" && r.body ? { ok: field(r.body, "ok"), status: field(r.body, "status"), checks: field(r.body, "checks") } : undefined;
  const detail = `HTTP ${r.status || r.error}${summary ? ` ${JSON.stringify(summary).slice(0, 160)}` : ""}`;
  return ok
    ? { id: itemId, status: "verified", ran, detail }
    : { id: itemId, status: "refused", ran, detail, fix: refusedFix(r, hostOf(url), `the ${app} health endpoint is not ok: check its deployment and /api/health`) };
}

export async function probeWhatsApp(cfg: Defaults): Promise<Row> {
  const token = env("ONE_WHATSAPP_TOKEN");
  const wabas = env("ONE_WHATSAPP_WABA_IDS")?.split(",").map((s) => s.trim()).filter(Boolean) ?? [];
  const ran = `GET ${cfg.vendors.graph_api}/<waba>/message_templates?limit=1`;
  if (!token || wabas.length === 0) return { id: "whatsapp", status: "not_provided", ran, detail: "no WhatsApp token or WABA ids", fix: "Meta Business → System users → token with whatsapp_business_management; or approve reuse of Vault b2b_whatsapp_token" };
  const results: Array<{ waba: string; status: number }> = [];
  for (const waba of wabas) {
    const r = await http(`${cfg.vendors.graph_api}/${waba}/message_templates?limit=1`, { headers: { authorization: `Bearer ${token}` } });
    results.push({ waba: waba.slice(-4), status: r.status });
  }
  const detail = results.map((x) => `…${x.waba}: HTTP ${x.status}`).join(", ");
  return results.every((x) => x.status === 200)
    ? { id: "whatsapp", status: "verified", ran, detail }
    : { id: "whatsapp", status: "refused", ran, detail, fix: "give the system user the WhatsApp accounts that failed, with whatsapp_business_management" };
}

export async function probeAiKey(cfg: Defaults): Promise<Row | undefined> {
  // Claude only (owner, 24 Oct; D-004, D-078).
  const anthropic = env("ONE_ANTHROPIC_API_KEY");
  if (!anthropic) return undefined; // Vault presence comes from the database probe or the connector file.
  const ran = `GET ${cfg.vendors.anthropic_api}/models`;
  const r = await http(`${cfg.vendors.anthropic_api}/models?limit=1`, {
    headers: { "x-api-key": anthropic, "anthropic-version": "2023-06-01" },
  });
  return r.status === 200
    ? { id: "ai_key", status: "verified", ran, detail: "Anthropic models listed" }
    : { id: "ai_key", status: "refused", ran, detail: `HTTP ${r.status || r.error}`, fix: refusedFix(r, hostOf(ran.slice(4)), "issue a new API key for Eduwit One's own project") };
}

/**
 * Identities that live only in the environment or defaults. A value that exists but cannot be exercised without a
 * write (a mailbox, an intake key) is "unfilled: present, not exercised": only its synthetic test may use it.
 */
export async function probeIdentities(cfg: Defaults): Promise<Row[]> {
  const mailboxEnv = env("ONE_TEST_MAILBOX");
  const mailbox = mailboxEnv ?? cfg.test_identities.mailbox ?? undefined;
  const previewEnv = env("ONE_WEBSITE_PREVIEW_URL");
  const preview = previewEnv ?? cfg.test_identities.website_preview_url ?? undefined;
  const intake = env("ONE_B2B_INTAKE_KEY", "B2B_INTAKE_TEST_KEY");
  const rows: Row[] = [
    mailbox
      ? { id: "test_mailbox", status: "unfilled", ran: mailboxEnv ? "read ONE_TEST_MAILBOX" : "read defaults.test_identities.mailbox", detail: "present, not exercised: reading it needs its key; T-WEB-ENQUIRY exercises it" }
      : { id: "test_mailbox", status: "not_provided", ran: "read ONE_TEST_MAILBOX and defaults.test_identities.mailbox", detail: "missing" },
    intake
      ? { id: "test_b2b_intake_key", status: "unfilled", ran: "read ONE_B2B_INTAKE_KEY (presence only)", detail: "present, not exercised: using it creates a lead, which only T-B2B-INTAKE may do" }
      : { id: "test_b2b_intake_key", status: "not_provided", ran: "read ONE_B2B_INTAKE_KEY", detail: "missing" },
  ];
  if (!preview) {
    rows.push({ id: "test_preview_url", status: "not_provided", ran: "read ONE_WEBSITE_PREVIEW_URL and defaults.test_identities.website_preview_url", detail: "missing" });
    return rows;
  }
  const r = await http(`${preview}/api/health`, {}, 10_000);
  const ran = `GET ${safeUrl(`${preview}/api/health`)} (from ${previewEnv ? "ONE_WEBSITE_PREVIEW_URL" : "defaults"})`;
  rows.push(r.status === 200
    ? { id: "test_preview_url", status: "verified", ran, detail: "HTTP 200" }
    : { id: "test_preview_url", status: "refused", ran, detail: `HTTP ${r.status || r.error}`, fix: refusedFix(r, hostOf(preview), "check the preview deployment URL") });
  return rows;
}
