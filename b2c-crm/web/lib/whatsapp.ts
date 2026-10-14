import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * WhatsApp Cloud API (the Eduwit B2C number). Pure helpers here; the network call takes its config as an argument so the
 * module can be unit-tested (whatsapp.test.ts). Nothing is sent unless the caller says the item is live: LIVE_MODE on,
 * Settings → live mode on, and not a test lead or test number (b2c.send_take decides the last three).
 */

export type WaPayload =
  | { type: "template"; template: { name: string; language: string; params: string[] } }
  | { type: "text"; text: string };

export type WaConfig = { phoneNumberId: string; token: string; apiVersion?: string };

export function waConfig(): WaConfig | null {
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const token = process.env.WHATSAPP_TOKEN;
  if (!phoneNumberId || !token) return null;
  return { phoneNumberId, token, apiVersion: process.env.WHATSAPP_API_VERSION || "v21.0" };
}

/** The Graph API body for one message. Indian numbers are sent as 91XXXXXXXXXX. */
export function messageBody(to: string, p: WaPayload): Record<string, unknown> {
  const digits = to.replace(/\D/g, "");
  const base = { messaging_product: "whatsapp", recipient_type: "individual", to: digits };
  if (p.type === "text") return { ...base, type: "text", text: { preview_url: false, body: p.text } };
  return {
    ...base,
    type: "template",
    template: {
      name: p.template.name,
      language: { code: p.template.language },
      components: p.template.params.length ? [{ type: "body", parameters: p.template.params.map((t) => ({ type: "text", text: String(t).slice(0, 1000) })) }] : [],
    },
  };
}

export type SendResult = { ok: boolean; dry_run?: boolean; wamid?: string; error?: string };

export async function sendWhatsApp(cfg: WaConfig | null, to: string, p: WaPayload, live: boolean): Promise<SendResult> {
  if (!live) return { ok: true, dry_run: true };
  if (!cfg) return { ok: false, error: "WhatsApp is not configured (WHATSAPP_PHONE_NUMBER_ID, WHATSAPP_TOKEN)." };
  try {
    const res = await fetch(`https://graph.facebook.com/${cfg.apiVersion ?? "v21.0"}/${cfg.phoneNumberId}/messages`, {
      method: "POST",
      headers: { authorization: `Bearer ${cfg.token}`, "content-type": "application/json" },
      body: JSON.stringify(messageBody(to, p)),
      signal: AbortSignal.timeout(15_000),
    });
    const body = (await res.json().catch(() => ({}))) as { messages?: { id: string }[]; error?: { message?: string; code?: number } };
    if (!res.ok) return { ok: false, error: body.error?.message ? `${body.error.code ?? res.status}: ${body.error.message}` : `HTTP ${res.status}` };
    return { ok: true, wamid: body.messages?.[0]?.id };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

/** Meta signs each webhook: X-Hub-Signature-256 = "sha256=" + HMAC-SHA256(app secret, raw body). */
export function verifyMetaSignature(rawBody: string, header: string | null, appSecret: string): boolean {
  if (!header) return false;
  const expected = Buffer.from("sha256=" + createHmac("sha256", appSecret).update(rawBody, "utf8").digest("hex"));
  const given = Buffer.from(header);
  return given.length === expected.length && timingSafeEqual(given, expected);
}

export type Inbound = {
  from: string; wamid: string; kind: "text" | "button" | "media" | "reaction" | "other"; text: string | null; button: string | null;
  profile_name: string | null; context_wamid: string | null; media: Record<string, unknown> | null;
};
export type StatusUpdate = { wamid: string; status: string; at: string; error: string | null };

type MetaMessage = {
  from: string; id: string; type: string; text?: { body?: string }; button?: { text?: string }; interactive?: { button_reply?: { title?: string }; list_reply?: { title?: string } };
  image?: Record<string, unknown>; document?: Record<string, unknown>; audio?: Record<string, unknown>; video?: Record<string, unknown>; context?: { id?: string };
};

/** Flattens a Cloud API webhook into inbound messages and delivery statuses. */
export function parseWebhook(body: unknown): { messages: Inbound[]; statuses: StatusUpdate[] } {
  const messages: Inbound[] = [];
  const statuses: StatusUpdate[] = [];
  const entries = (body as { entry?: { changes?: { value?: Record<string, unknown> }[] }[] })?.entry ?? [];
  for (const e of entries) {
    for (const c of e.changes ?? []) {
      const v = c.value ?? {};
      const contacts = (v.contacts as { wa_id: string; profile?: { name?: string } }[] | undefined) ?? [];
      for (const m of (v.messages as MetaMessage[] | undefined) ?? []) {
        const name = contacts.find((x) => x.wa_id === m.from)?.profile?.name ?? null;
        const button = m.button?.text ?? m.interactive?.button_reply?.title ?? m.interactive?.list_reply?.title ?? null;
        const media = m.image ?? m.document ?? m.audio ?? m.video ?? null;
        const kind: Inbound["kind"] = m.type === "text" ? "text" : button ? "button" : media ? "media" : m.type === "reaction" ? "reaction" : "other";
        messages.push({ from: m.from, wamid: m.id, kind, text: m.text?.body ?? null, button, profile_name: name, context_wamid: m.context?.id ?? null, media: media ? { type: m.type, ...media } : null });
      }
      for (const s of (v.statuses as { id: string; status: string; timestamp: string; errors?: { title?: string; message?: string }[] }[] | undefined) ?? []) {
        statuses.push({ wamid: s.id, status: s.status, at: new Date(Number(s.timestamp) * 1000).toISOString(), error: s.errors?.[0] ? s.errors[0].message ?? s.errors[0].title ?? null : null });
      }
    }
  }
  return { messages, statuses };
}
