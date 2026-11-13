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

/**
 * retry: false means b2c.send_done marks the message failed and never queues it again, for one of two reasons: it may
 * have reached Meta (no answer in time, the connection dropped after the request went out, or a 5xx), so a student is
 * never sent it twice; or Meta refused it for good (classifyWaError: "final"), so trying again cannot help. connector:
 * Meta refused Spark's connection, not this message; the message is tried again as any failure is.
 */
export type SendResult = { ok: boolean; dry_run?: boolean; wamid?: string; error?: string; retry?: boolean; connector?: boolean };

const MAYBE_SENT = "it may have gone out, so it is not sent again automatically; check with the student and send again if it did not arrive";

/** Network failures that happen before the request reaches Meta (nothing was sent, so trying again is safe). */
const NOT_SENT_CODES = /^(ENOTFOUND|EAI_AGAIN|ECONNREFUSED|EHOSTUNREACH|ENETUNREACH|UND_ERR_CONNECT_TIMEOUT|CERT_|ERR_TLS_CERT|UNABLE_TO_|DEPTH_ZERO_SELF_SIGNED|SELF_SIGNED_CERT)/;

export function failedBeforeSending(e: unknown): boolean {
  const cause = (e as { cause?: { code?: unknown } } | null)?.cause;
  return typeof cause?.code === "string" && NOT_SENT_CODES.test(cause.code);
}

/** The error object of a Graph API answer (WhatsApp Cloud API). */
export type MetaError = { message?: string; code?: number; error_subcode?: number; error_data?: { details?: string } };

/**
 * What a 4xx answer from Meta means for the message that was being sent:
 *   final      Meta will never accept this message as it is: failed at once, with the reason (retry: false);
 *   connector  Meta is refusing Spark's connection (the token, a permission, the account or the number), not the
 *              message: reported on the WhatsApp connector; the message is tried again as before;
 *   retry      everything else, rate limits included: tried again as before (b2c.send_done, five attempts).
 * Decided by Meta's error code (the "code" of the answer's error object, as in Meta's WhatsApp Cloud API error list),
 * then by the HTTP status when the code is not one of these. Only codes whose meaning leaves no doubt are final; a code
 * that is not listed is tried again. A 5xx never comes here: sendWhatsApp treats it as "may have gone out".
 */
const WA_FINAL: Record<number, string> = {
  100: "a part of the message is not valid",                                                                      // Invalid parameter (with subcode 33 it is the connection: below)
  130472: "WhatsApp held it back as part of an experiment it is running on this number",                          // User's number is part of an experiment
  130497: "WhatsApp does not let this account message people in that country",                                    // Business account is restricted from messaging users in this country
  131008: "a required part of the message is missing",                                                            // Required parameter is missing
  131009: "a value in the message is not valid (often the phone number)",                                         // Parameter value is not valid
  131021: "the number is the sending number itself",                                                              // Recipient cannot be sender
  131026: "the number cannot receive it (not on WhatsApp, or it has not accepted WhatsApp's current terms)",      // Message undeliverable
  131030: "the number is not on the allowed list of a test WhatsApp account",                                     // Recipient phone number not in allowed list
  131047: "more than 24 hours have passed since the student last wrote, so only an approved template can be sent", // Re-engagement message
  131049: "WhatsApp chose not to deliver this marketing message to this person for now",                          // Meta chose not to deliver (per-person marketing limit)
  131050: "the person has stopped marketing messages from this number in WhatsApp",                               // User has stopped marketing messages
  131051: "WhatsApp does not support this type of message",                                                       // Unsupported message type
  132000: "the template was sent with the wrong number of values",                                                // Template param count mismatch
  132001: "the template does not exist in this language or is not approved",                                      // Template does not exist
  132005: "the template with its values is too long",                                                             // Template hydrated text too long
  132007: "the template's text breaks WhatsApp's format rules",                                                   // Template format character policy violated
  132012: "a template value has the wrong format",                                                                // Template parameter format mismatch
  132015: "WhatsApp has paused the template for low quality",                                                     // Template is paused
  132016: "WhatsApp has disabled the template for low quality",                                                   // Template is disabled
};
const WA_CONNECTOR: Record<number, string> = {
  0: "WhatsApp could not check the access token",                                                                 // AuthException
  10: "the access token has no permission for this",                                                              // Permission denied
  33: "the business phone number does not exist any more",                                                        // Parameter value is not valid (number deleted)
  190: "the access token has expired or is no longer valid",                                                      // Access token has expired
  368: "WhatsApp has blocked the account for a while for breaking its policies",                                  // Temporarily blocked for policies violations
  131005: "the access token has no permission to send from this number",                                          // Access denied
  131031: "WhatsApp has locked the account",                                                                      // Account has been locked
  131037: "the number's display name is not approved yet",                                                        // Display name approval needed
  131042: "there is a payment problem on the WhatsApp account",                                                   // Business eligibility payment issue
  131048: "WhatsApp is limiting how many messages this number may send (spam rate limit)",                        // Spam rate limit hit
  133006: "the phone number must be verified again",                                                              // Phone number re-verification needed
  133010: "the phone number is not registered with WhatsApp",                                                     // Phone number not registered
};
/** Rate limits that pass by themselves: 4 the app's calls, 80007 the account's, 130429 throughput, 131056 this pair of numbers. */
const WA_THROTTLED = new Set([4, 80007, 130429, 131056]);

export function classifyWaError(status: number, e?: MetaError | null): { kind: "final" | "retry" | "connector"; reason?: string } {
  const code = typeof e?.code === "number" ? e.code : null;
  if (code !== null) {
    // 100 with subcode 33: "object does not exist or cannot be loaded": the phone number id, or the token's access to it
    if (code === 100 && e?.error_subcode === 33) return { kind: "connector", reason: "the phone number id is wrong, or the access token may not use it" };
    if (WA_THROTTLED.has(code)) return { kind: "retry" };
    const final = WA_FINAL[code];
    if (final) return { kind: "final", reason: final };
    const connector = WA_CONNECTOR[code] ?? (code >= 200 && code <= 299 ? "the access token lacks a permission" : undefined); // 200–299: API permission
    if (connector) return { kind: "connector", reason: connector };
  }
  if (status === 429) return { kind: "retry" };
  if (status === 401) return { kind: "connector", reason: "the access token was refused" };
  if (status === 403) return { kind: "connector", reason: "WhatsApp does not allow this account or token to send" };
  return { kind: "retry" };
}

export async function sendWhatsApp(cfg: WaConfig | null, to: string, p: WaPayload, live: boolean, mediaLink?: string | null, fetchImpl: typeof fetch = fetch): Promise<SendResult> {
  if (!live) return { ok: true, dry_run: true };
  if (!cfg) return { ok: false, error: "WhatsApp is not configured (WHATSAPP_PHONE_NUMBER_ID, WHATSAPP_TOKEN)." };
  let body: string;
  try {
    body = JSON.stringify(messageBody(to, p, mediaLink));
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
  try {
    const res = await fetchImpl(`https://graph.facebook.com/${cfg.apiVersion ?? "v21.0"}/${cfg.phoneNumberId}/messages`, {
      method: "POST",
      headers: { authorization: `Bearer ${cfg.token}`, "content-type": "application/json" },
      body,
      signal: AbortSignal.timeout(15_000),
    });
    const b = (await res.json().catch(() => ({}))) as { messages?: { id: string }[]; error?: MetaError };
    if (!res.ok) {
      const error = b.error?.message ? `${b.error.code ?? res.status}: ${b.error.message}` : `HTTP ${res.status}`;
      if (res.status >= 500) return { ok: false, retry: false, error: `WhatsApp answered ${error}; ${MAYBE_SENT}` };
      const refusal = classifyWaError(res.status, b.error);
      const detail = b.error?.error_data?.details;
      const said = `${error}${detail && detail !== b.error?.message ? ` (${detail})` : ""}`.slice(0, 300);
      if (refusal.kind === "final") return { ok: false, retry: false, error: `WhatsApp refused it: ${refusal.reason}. It is not sent again automatically. (${said})` };
      if (refusal.kind === "connector") return { ok: false, connector: true, error: `WhatsApp refused Spark's connection, not this message: ${refusal.reason}. (${said})` };
      return { ok: false, error };
    }
    return { ok: true, wamid: b.messages?.[0]?.id };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (failedBeforeSending(e)) return { ok: false, error: msg };
    const timeout = e instanceof Error && (e.name === "TimeoutError" || e.name === "AbortError");
    return { ok: false, retry: false, error: `${timeout ? "No answer from WhatsApp in time" : `The connection to WhatsApp failed (${msg})`}; ${MAYBE_SENT}` };
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

/**
 * Flattens a Cloud API webhook into inbound messages and delivery statuses. Only changes for Spark's own number are read
 * (value.metadata.phone_number_id = WHATSAPP_PHONE_NUMBER_ID, when set): other numbers on the same Meta app or account
 * are never taken for Spark messages.
 */
export function parseWebhook(body: unknown, phoneNumberId: string | undefined = process.env.WHATSAPP_PHONE_NUMBER_ID): { messages: Inbound[]; statuses: StatusUpdate[] } {
  const messages: Inbound[] = [];
  const statuses: StatusUpdate[] = [];
  const entries = (body as { entry?: { changes?: { value?: Record<string, unknown> }[] }[] })?.entry ?? [];
  for (const e of entries) {
    for (const c of e.changes ?? []) {
      const v = c.value ?? {};
      if (phoneNumberId && String((v.metadata as { phone_number_id?: unknown } | undefined)?.phone_number_id ?? "") !== phoneNumberId) continue;
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
