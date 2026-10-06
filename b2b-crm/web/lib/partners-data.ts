import "server-only";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import type { PartnerDetail, PartnerListItem } from "@/lib/partners";

/** Partner reads as the signed-in Admin. b2b.partners_list / partner_detail re-check b2b.is_admin() and never return secrets. */

export async function listPartners(): Promise<PartnerListItem[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("partners_list");
  if (error) throw new Error(`partners_list failed (${error.code ?? "unknown"})`);
  return (data ?? []) as PartnerListItem[];
}

/** Memoised per request: the page and its metadata share one round trip. */
export const partnerDetail = cache(async (id: number): Promise<PartnerDetail | null> => {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("partner_detail", { p_id: id });
  if (error) throw new Error(`partner_detail failed (${error.code ?? "unknown"})`);
  return (data as PartnerDetail | null) ?? null;
});
