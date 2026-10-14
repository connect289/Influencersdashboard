import "server-only";
import { adminClient } from "@/lib/supabase/admin";
import { waConfig } from "@/lib/whatsapp";

/**
 * WhatsApp templates on the B2C number's Business account (spec B9.2): submit for Meta approval, and sync statuses and the
 * number's quality rating (hourly, from the reconcile job). Needs WHATSAPP_WABA_ID besides the sending config.
 */
export type TemplateRow = { id: number; name: string; language: string; category: string; body: string; variables: string[]; buttons: { type: string; text: string; url?: string }[] };

const SAMPLE: Record<string, string> = { first_name: "Asha", programme: "Online MBA", university: "Amity Online", counsellor: "Priya", counsellor_first_name: "Priya", next_working_time: "10:00 am on Mon 20 Oct" };

/** Meta's create-template body. Variables {{1}}… get example values (Meta requires them). */
export function templateBody(t: TemplateRow): Record<string, unknown> {
  const components: Record<string, unknown>[] = [{
    type: "BODY", text: t.body,
    ...(t.variables.length ? { example: { body_text: [t.variables.map((v) => SAMPLE[v] ?? "example")] } } : {}),
  }];
  const buttons = t.buttons.filter((b) => b.text).map((b) => (b.type === "url" ? { type: "URL", text: b.text.slice(0, 25), url: b.url } : { type: "QUICK_REPLY", text: b.text.slice(0, 25) }));
  if (buttons.length) components.push({ type: "BUTTONS", buttons });
  return { name: t.name, language: t.language, category: t.category.toUpperCase(), components };
}

export async function submitTemplate(t: TemplateRow): Promise<{ ok: boolean; error?: string }> {
  const cfg = waConfig(); const waba = process.env.WHATSAPP_WABA_ID;
  if (!cfg || !waba) return { ok: false, error: "WhatsApp is not connected (WHATSAPP_WABA_ID, WHATSAPP_TOKEN)." };
  const res = await fetch(`https://graph.facebook.com/${cfg.apiVersion}/${waba}/message_templates`, {
    method: "POST", headers: { authorization: `Bearer ${cfg.token}`, "content-type": "application/json" }, body: JSON.stringify(templateBody(t)), signal: AbortSignal.timeout(20_000),
  });
  const b = (await res.json()) as { id?: string; status?: string; error?: { message?: string; error_user_msg?: string } };
  if (!res.ok) return { ok: false, error: b.error?.error_user_msg ?? b.error?.message ?? `HTTP ${res.status}` };
  await adminClient().rpc("wa_template_status", { p_name: t.name, p_language: t.language, p_status: b.status ?? "pending", p_meta_id: b.id ?? null, p_reason: null });
  return { ok: true };
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
