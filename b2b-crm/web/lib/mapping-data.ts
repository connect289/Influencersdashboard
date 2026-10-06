import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { OverviewRow, Studio } from "@/lib/mapping";

/** Mapping reads as the signed-in Admin; every b2b.mapping_* function re-checks b2b.is_admin(). */
export async function mappingOverview(): Promise<OverviewRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("mapping_overview");
  if (error) throw new Error(`mapping_overview failed (${error.code ?? "unknown"})`);
  return (data ?? []) as OverviewRow[];
}

export async function mappingStudio(partnerId: number): Promise<Studio | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("mapping_studio", { p_partner_id: partnerId });
  if (error) throw new Error(`mapping_studio failed (${error.code ?? "unknown"})`);
  return (data ?? null) as Studio | null;
}
