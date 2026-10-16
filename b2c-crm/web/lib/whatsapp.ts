import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * WhatsApp Cloud API (the Eduwit B2C number). Pure helpers here; the network call takes its config as an argument so the
 * module can be unit-tested (whatsapp.test.ts). Nothing is sent unless the caller says the item is live: LIVE_MODE on,
 * Settings → live mode on, and not a test lead or test number (b2c.send_take decides the last three).
 */

export type WaMediaPayload = { type: "media"; media_kind: "image" | "document"; path?: string | null; link?: string | null; caption?: string | null; filename?: string | null };
export type WaPayload =
  | { type: "template"; template: { name: string; language: string; params: string[] } }
  | { type: "text"; text: string }
  | WaMediaPayload;

export type WaConfig = { phoneNumberId: string; token: string; apiVersion?: string };

export function waConfig(): WaConfig | null {
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const token = process.env.WHATSAPP_TOKEN;
  if (!phoneNumberId || !token) return null;
  return { phoneNumberId, token, apiVersion: process.env.WHATSAPP_API_VERSION || "v21.0" };
}

/**
 * The Graph API body for one message. Indian numbers are sent as 91XXXXXXXXXX. A media message goes as a link: the
 * caller passes a short-lived signed link for a stored file (`mediaLink`), or the payload's own https link (a brochure).
 */
export function messageBody(to: string, p: WaPayload, mediaLink?: string | null): Record<string, unknown> {
  const digits = to.replace(/\D/g, "");
  const base = { messaging_product: "whatsapp", recipient_type: "individual", to: digits };
  if (p.type === "text") return { ...base, type: "text", text: { preview_url: false, body: p.text } };
  if (p.type === "media") {
    const link = mediaLink ?? p.link ?? null;
    if (!link || !/^https:\/\//.test(link)) throw new Error("a media message needs an https link");
    const caption = p.caption?.trim() ? p.caption.trim().slice(0, 1024) : undefined;
    if (p.media_kind === "image") return { ...base, type: "image", image: { link, ...(caption ? { caption } : {}) } };
    const filename = p.filename?.trim() ? p.filename.trim().replace(/[\r\n"\\/]+/g, "_").slice(0, 120) : undefined;
    return { ...base, type: "document", document: { link, ...(caption ? { caption } : {}), ...(filename ? { filename } : {}) } };
  }
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

export async function sendWhatsApp(cfg: WaConfig | null, to: string, p: WaPayload, live: boolean, mediaLink?: string | null): Promise<SendResult> {
  if (!live) return { ok: true, dry_run: true };
  if (!cfg) return { ok: false, error: "WhatsApp is not configured (WHATSAPP_PHONE_NUMBER_ID, WHATSAPP_TOKEN)." };
  try {
    const res = await fetch(`https://graph.facebook.com/${cfg.apiVersion ?? "v21.0"}/${cfg.phoneNumberId}/messages`, {
      method: "POST",
      headers: { authorization: `Bearer ${cfg.token}`, "content-type": "application/json" },
      body: JSON.stringify(messageBody(to, p, mediaLink)),
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

/** An inbound file as b2c.wa_inbound stores it (wa_messages.media): the media id the fetch job downloads by. */
export type InboundMedia = { type: string; id: string | null; mime_type: string | null; filename: string | null; caption: string | null; sha256: string | null };
export type Inbound = {
  from: string; wamid: string; kind: "text" | "button" | "media" | "reaction" | "other"; text: string | null; button: string | null;
  profile_name: string | null; context_wamid: string | null; media: InboundMedia | null;
};
export type StatusUpdate = { wamid: string; status: string; at: string; error: string | null };

type MetaMessage = {
  from: string; id: string; type: string; text?: { body?: string }; button?: { text?: string }; interactive?: { button_reply?: { title?: string }; list_reply?: { title?: string } };
  image?: MetaMedia; document?: MetaMedia; audio?: MetaMedia; video?: MetaMedia; sticker?: MetaMedia; context?: { id?: string };
};
type MetaMedia = { id?: string; mime_type?: string; filename?: string; caption?: string; sha256?: string };
const str = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

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
        const raw = m.image ?? m.document ?? m.audio ?? m.video ?? m.sticker ?? null;
        const media: InboundMedia | null = raw
          ? { type: m.type, id: str(raw.id), mime_type: str(raw.mime_type), filename: str(raw.filename), caption: str(raw.caption), sha256: str(raw.sha256) }
          : null;
        const kind: Inbound["kind"] = m.type === "text" ? "text" : button ? "button" : media ? "media" : m.type === "reaction" ? "reaction" : "other";
        messages.push({ from: m.from, wamid: m.id, kind, text: m.text?.body ?? null, button, profile_name: name, context_wamid: m.context?.id ?? null, media });
      }
      for (const s of (v.statuses as { id: string; status: string; timestamp: string; errors?: { title?: string; message?: string }[] }[] | undefined) ?? []) {
        statuses.push({ wamid: s.id, status: s.status, at: new Date(Number(s.timestamp) * 1000).toISOString(), error: s.errors?.[0] ? s.errors[0].message ?? s.errors[0].title ?? null : null });
      }
    }
  }
  return { messages, statuses };
}

// ---------- inbound media: fetched from Meta and kept in the private bucket (C1) ----------

/** What the b2c-documents bucket accepts (b10_storage.sql): PDFs and images up to 4 MB. Other files keep an error. */
export const MEDIA_BUCKET = "b2c-documents";
export const MEDIA_MAX_BYTES = 4 * 1024 * 1024;
const MEDIA_EXT: Record<string, string> = { "application/pdf": "pdf", "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };

export const baseMime = (mime: string | null | undefined) => (mime ?? "").split(";")[0]!.trim().toLowerCase();
export const mediaAllowed = (mime: string | null | undefined) => baseMime(mime) in MEDIA_EXT;

/** A file name safe for a storage key: letters, digits, dot, dash and underscore; the right extension for the type. */
export function safeFileName(name: string | null | undefined, mime: string | null | undefined, fallback = "file"): string {
  const ext = MEDIA_EXT[baseMime(mime)];
  const stem = (name ?? "").normalize("NFKD").replace(/\.[A-Za-z0-9]{1,5}$/, "").replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^[-.]+|[-.]+$/g, "").slice(0, 80) || fallback;
  return ext ? `${stem}.${ext}` : stem;
}

/** leads/<lead_id>/wa/<message_id>-<safe name>: under the lead's folder, as b2c.wa_media_stored requires. */
export function mediaPath(leadId: number, messageId: number, media: { filename?: string | null; mime_type?: string | null; type?: string | null }): string {
  return `leads/${leadId}/wa/${messageId}-${safeFileName(media.filename, media.mime_type, media.type || "file")}`;
}

/** Step 1: Meta's short-lived download link for a media id (GET /<media_id>). */
export async function mediaInfo(cfg: WaConfig, id: string, fetchImpl: typeof fetch = fetch): Promise<{ url: string; mime_type: string | null; file_size: number | null }> {
  if (!/^[A-Za-z0-9_.-]{1,128}$/.test(id)) throw new Error("not a media id");
  const res = await fetchImpl(`https://graph.facebook.com/${cfg.apiVersion ?? "v21.0"}/${encodeURIComponent(id)}`, {
    headers: { authorization: `Bearer ${cfg.token}` }, signal: AbortSignal.timeout(15_000), cache: "no-store",
  });
  const b = (await res.json().catch(() => ({}))) as { url?: string; mime_type?: string; file_size?: number | string; error?: { message?: string; code?: number } };
  if (!res.ok || !b.url) throw new Error(b.error?.message ? `${b.error.code ?? res.status}: ${b.error.message}` : `media lookup failed (HTTP ${res.status})`);
  return { url: b.url, mime_type: b.mime_type ?? null, file_size: b.file_size === undefined ? null : Number(b.file_size) };
}

/** Step 2: the bytes (the link needs the same bearer token), refused above the bucket's size. */
export async function mediaDownload(cfg: WaConfig, url: string, max = MEDIA_MAX_BYTES, fetchImpl: typeof fetch = fetch): Promise<{ bytes: Uint8Array; contentType: string | null }> {
  if (!/^https:\/\//.test(url)) throw new Error("not an https media link");
  const res = await fetchImpl(url, { headers: { authorization: `Bearer ${cfg.token}` }, signal: AbortSignal.timeout(30_000), cache: "no-store" });
  if (!res.ok) throw new Error(`media download failed (HTTP ${res.status})`);
  const declared = Number(res.headers.get("content-length") ?? 0);
  if (declared > max) throw new Error(`file larger than ${Math.round(max / 1048576)} MB`);
  const bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes.byteLength > max) throw new Error(`file larger than ${Math.round(max / 1048576)} MB`);
  return { bytes, contentType: res.headers.get("content-type") };
}
