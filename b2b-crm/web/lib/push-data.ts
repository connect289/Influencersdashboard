import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { PartnerConnection, PushOverview } from "@/lib/push";

/** Push reads as the signed-in Admin; b2b.partner_connection and b2b.push_overview re-check b2b.is_admin() and never return secrets. */
async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) throw new Error(`${fn} failed (${error.code ?? "unknown"})`);
  return data as T;
}

export const partnerConnection = (id: number) => rpc<PartnerConnection | null>("partner_connection", { p_partner_id: id });
export const pushOverview = () => rpc<PushOverview>("push_overview", { p_partner_id: null });
