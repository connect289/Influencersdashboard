import "server-only";
import { adminClient } from "@/lib/supabase/admin";
import { waConfig } from "@/lib/whatsapp";

/**
 * Templates already on the B2C number's WhatsApp Business account (spec B9.2): read from the Graph API and handed to
 * b2c.wa_template_import, which adds the new ones as marketing templates and updates the status, id and approved text of
 * known ones (each change a new version). The caller checks the person's role first.
 */
export type MetaTemplate = { id: string; name: string; language: string; status: string; category?: string; components?: Record<string, unknown>[] };
export type ImportResult = { ok: true; fetched: number; added: number; updated: number } | { ok: false; error: string };

export async function importWaTemplates(): Promise<ImportResult> {
  const cfg = waConfig();
  const waba = process.env.WHATSAPP_WABA_ID;
  if (!cfg || !waba) return { ok: false, error: "WhatsApp is not connected: set WHATSAPP_WABA_ID, WHATSAPP_PHONE_NUMBER_ID and WHATSAPP_TOKEN on the server first." };
  const list: MetaTemplate[] = [];
  let url: string | null = `https://graph.facebook.com/${cfg.apiVersion ?? "v21.0"}/${waba}/message_templates?fields=id,name,language,status,category,components&limit=100`;
  try {
    for (let page = 0; url && page < 20; page++) {
      const res: Response = await fetch(url, { headers: { authorization: `Bearer ${cfg.token}` }, signal: AbortSignal.timeout(20_000) });
      const b = (await res.json().catch(() => ({}))) as { data?: MetaTemplate[]; paging?: { next?: string }; error?: { message?: string; code?: number } };
      if (!res.ok) return { ok: false, error: `WhatsApp refused the request: ${b.error?.message ?? `HTTP ${res.status}`}` };
      list.push(...(b.data ?? []));
      url = b.paging?.next ?? null;
    }
  } catch (e) {
    return { ok: false, error: `WhatsApp could not be reached: ${e instanceof Error ? e.message : String(e)}` };
  }
  const db = adminClient();
  const { data, error } = await db.rpc("wa_template_import", { p: list.map(toImport) });
  if (error) {
    await db.rpc("connector_report", { p_key: "whatsapp", p_ok: false, p_detail: null, p_error: `template import: ${error.message}` });
    return { ok: false, error: error.message };
  }
  await db.rpc("connector_report", { p_key: "whatsapp", p_ok: true, p_detail: { templates_imported_at: new Date().toISOString(), templates_on_account: list.length }, p_error: null });
  const r = (data ?? {}) as { added?: number; updated?: number };
  return { ok: true, fetched: list.length, added: r.added ?? 0, updated: r.updated ?? 0 };
}

/** The shape b2c.wa_template_import reads: name, language, status, category, id and Meta's components. */
export function toImport(t: MetaTemplate): Record<string, unknown> {
  return { id: t.id, name: t.name, language: t.language, status: t.status, category: t.category ?? "MARKETING", components: t.components ?? [] };
}
