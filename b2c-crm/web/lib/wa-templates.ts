import "server-only";
import { fetchChecked, hostList, hostOf, urlProblem, type FetchRules } from "@/lib/safe-fetch";
import { adminClient } from "@/lib/supabase/admin";
import { waConfig } from "@/lib/whatsapp";

/**
 * WhatsApp templates on the B2C number's Business account (spec B9.2): submit for Meta approval, and sync statuses and the
 * number's quality rating (hourly, from the reconcile job). Needs WHATSAPP_WABA_ID besides the sending config.
 */
export type TemplateRow = { id: number; name: string; language: string; category: string; body: string; variables: string[]; buttons: { type: string; text: string; url?: string }[];
  header?: WaHeader | null };
/** A template header: text, or an image, document or video whose sample Meta reviews (b2c.wa_header_ok). */
export type WaHeader = { type: "text"; text: string } | { type: "image" | "document" | "video"; example_url: string };

const SAMPLE: Record<string, string> = { first_name: "Asha", programme: "Online MBA", university: "Amity Online", counsellor: "Priya", counsellor_first_name: "Priya", next_working_time: "10:00 am on Mon 20 Oct" };

/** Meta's create-template body. Variables {{1}}… get example values (Meta requires them). */
export function templateBody(t: TemplateRow, headerHandle?: string): Record<string, unknown> {
  const components: Record<string, unknown>[] = [];
  const h = t.header;
  if (h?.type === "text") components.push({ type: "HEADER", format: "TEXT", text: h.text });
  else if (h) components.push({ type: "HEADER", format: h.type.toUpperCase(), example: { header_handle: [headerHandle ?? h.example_url] } });
  components.push({
    type: "BODY", text: t.body,
    ...(t.variables.length ? { example: { body_text: [t.variables.map((v) => SAMPLE[v] ?? "example")] } } : {}),
  });
  const buttons = t.buttons.filter((b) => b.text).map((b) => (b.type === "url" ? { type: "URL", text: b.text.slice(0, 25), url: b.url } : { type: "QUICK_REPLY", text: b.text.slice(0, 25) }));
  if (buttons.length) components.push({ type: "BUTTONS", buttons });
  return { name: t.name, language: t.language, category: t.category.toUpperCase(), components };
}

export async function submitTemplate(t: TemplateRow): Promise<{ ok: boolean; error?: string }> {
  const cfg = waConfig(); const waba = process.env.WHATSAPP_WABA_ID;
  if (!cfg || !waba) return { ok: false, error: "WhatsApp is not connected (WHATSAPP_WABA_ID, WHATSAPP_TOKEN)." };
  let handle: string | undefined;
  if (t.header && t.header.type !== "text") {
    const up = await uploadHeaderSample(t.header.example_url, cfg.token, cfg.apiVersion);
    if (!up.ok) return { ok: false, error: up.error };
    handle = up.handle;
  }
  const res = await fetch(`https://graph.facebook.com/${cfg.apiVersion}/${waba}/message_templates`, {
    method: "POST", headers: { authorization: `Bearer ${cfg.token}`, "content-type": "application/json" }, body: JSON.stringify(templateBody(t, handle)), signal: AbortSignal.timeout(20_000),
  });
  const b = (await res.json()) as { id?: string; status?: string; error?: { message?: string; error_user_msg?: string } };
  if (!res.ok) return { ok: false, error: b.error?.error_user_msg ?? b.error?.message ?? `HTTP ${res.status}` };
  await adminClient().rpc("wa_template_status", { p_name: t.name, p_language: t.language, p_status: b.status ?? "pending", p_meta_id: b.id ?? null, p_reason: null });
  return { ok: true };
}

/** Where a header sample may be downloaded from: Eduwit's domains, this site, Spark's storage, and MEDIA_FETCH_HOSTS. */
export function sampleRules(env: Record<string, string | undefined> = process.env): FetchRules {
  const own = [hostOf(env.NEXT_PUBLIC_SITE_URL), hostOf(env.NEXT_PUBLIC_SUPABASE_URL)].filter((h): h is string => !!h);
  return { hosts: [".eduwit.in", ...own, ...hostList(env.MEDIA_FETCH_HOSTS)], maxBytes: 16 * 1024 * 1024, timeoutMs: 20_000, maxRedirects: 3 };
}

/**
 * Meta reviews a media header from an uploaded sample: the sample link is fetched (allowed hosts only, see sampleRules)
 * and sent through the Resumable Upload API (needs WHATSAPP_APP_ID), which answers with the handle the template refers to.
 */
export async function uploadHeaderSample(url: string, token: string, apiVersion = "v21.0", fetcher: typeof fetchChecked = fetchChecked): Promise<{ ok: true; handle: string } | { ok: false; error: string }> {
  const app = process.env.WHATSAPP_APP_ID;
  if (!app) return { ok: false, error: "A media header needs WHATSAPP_APP_ID on the server, to upload the sample to Meta." };
  const rules = sampleRules();
  const problem = urlProblem(url, rules.hosts);
  if (problem) return { ok: false, error: `The sample link cannot be used (${problem}). Put the file on eduwit.in or in Spark's storage, or have the developer add its host to MEDIA_FETCH_HOSTS.` };
  try {
    const file = await fetcher(url, rules);
    if (file.status < 200 || file.status >= 300) return { ok: false, error: `The sample link answered ${file.status}.` };
    const bytes = new Uint8Array(file.body);
    const type = (file.contentType ?? "application/octet-stream").split(";")[0]!;
    const start = await fetch(`https://graph.facebook.com/${apiVersion}/${app}/uploads?file_length=${bytes.length}&file_type=${encodeURIComponent(type)}`, {
      method: "POST", headers: { authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(20_000),
    });
    const s = (await start.json().catch(() => ({}))) as { id?: string; error?: { message?: string } };
    if (!start.ok || !s.id) return { ok: false, error: s.error?.message ?? `Upload refused (${start.status}).` };
    const put = await fetch(`https://graph.facebook.com/${apiVersion}/${s.id}`, {
      method: "POST", headers: { authorization: `OAuth ${token}`, file_offset: "0" }, body: bytes, signal: AbortSignal.timeout(60_000),
    });
    const h = (await put.json().catch(() => ({}))) as { h?: string; error?: { message?: string } };
    if (!put.ok || !h.h) return { ok: false, error: h.error?.message ?? `Upload refused (${put.status}).` };
    return { ok: true, handle: h.h };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

/** Hourly: every template's status, and the number's quality rating (shown on the Nurture page). */
export async function syncTemplates(force = false): Promise<{ synced: number; skipped?: string }> {
  const cfg = waConfig(); const waba = process.env.WHATSAPP_WABA_ID;
  if (!cfg || !waba) return { synced: 0, skipped: "WhatsApp is not connected" };
  const db = adminClient();
  const { data: last } = await db.rpc("sync_get", { p_key: "wa_templates_synced_at" });
  if (!force && last && Date.now() - new Date(String(last)).getTime() < 55 * 60_000) return { synced: 0, skipped: "synced within the hour" };
  let url: string | null = `https://graph.facebook.com/${cfg.apiVersion}/${waba}/message_templates?fields=name,language,status,id,rejected_reason&limit=200`;
  let n = 0;
  for (let page = 0; url && page < 10; page++) {
    const res: Response = await fetch(url, { headers: { authorization: `Bearer ${cfg.token}` }, signal: AbortSignal.timeout(20_000) });
    const b = (await res.json()) as { data?: { name: string; language: string; status: string; id: string; rejected_reason?: string }[]; paging?: { next?: string } };
    for (const t of b.data ?? []) {
      await db.rpc("wa_template_status", { p_name: t.name, p_language: t.language, p_status: t.status, p_meta_id: t.id, p_reason: t.rejected_reason && t.rejected_reason !== "NONE" ? t.rejected_reason : null });
      n++;
    }
    url = b.paging?.next ?? null;
  }
  const q = await fetch(`https://graph.facebook.com/${cfg.apiVersion}/${cfg.phoneNumberId}?fields=quality_rating,messaging_limit_tier`, { headers: { authorization: `Bearer ${cfg.token}` }, signal: AbortSignal.timeout(15_000) });
  if (q.ok) {
    const v = (await q.json()) as { quality_rating?: string; messaging_limit_tier?: string };
    await db.from("settings").upsert({ key: "wa_quality", value: { rating: v.quality_rating ?? null, tier: v.messaging_limit_tier ?? null, at: new Date().toISOString() }, updated_at: new Date().toISOString() });
    if (v.quality_rating && v.quality_rating !== "GREEN") {
      await db.rpc("notify_admins", { p_kind: "wa_quality", p_title: `WhatsApp quality rating: ${v.quality_rating}`, p_body: "Slow down marketing on the B2C number.", p_link: "/w/nurture", p_lead: null, p_dedupe: `waq:${v.quality_rating}:${new Date().toISOString().slice(0, 10)}`, p_heads: false });
    }
  }
  await db.rpc("sync_set", { p_key: "wa_templates_synced_at", p_value: new Date().toISOString() });
  return { synced: n };
}
