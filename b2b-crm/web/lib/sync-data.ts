import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { LeadPartnerSync, PartnerSync } from "@/lib/sync";

/** Sync reads as the signed-in Admin; b2b.partner_sync and b2b.lead_partner_sync re-check b2b.is_admin(). */
async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) throw new Error(`${fn} failed (${error.code ?? "unknown"})`);
  return data as T;
}

export const partnerSync = (id: number) => rpc<PartnerSync>("partner_sync", { p_partner_id: id });
export const leadPartnerSync = (id: number) => rpc<LeadPartnerSync>("lead_partner_sync", { p_lead_id: id });
