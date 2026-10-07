import "server-only";
import { createClient } from "@/lib/supabase/server";
import { DEFAULT_VALUES, type CapiCampaigns, type CapiOverview, type SignalValues } from "@/lib/capi";

/** CAPI reads as the signed-in Admin; b2b.capi_overview re-checks b2b.is_admin(). */
export async function capiOverview(status: string | null, platform: string | null): Promise<CapiOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("capi_overview", { p_status: status, p_platform: platform });
  if (error) throw new Error(`capi_overview failed (${error.code ?? "unknown"})`);
  return data as CapiOverview;
}

/** Signal values (settings capi.values and base_value_inr). The Admin reads b2b.settings under RLS. */
export async function capiValues(): Promise<SignalValues> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").from("settings").select("value").eq("key", "capi").maybeSingle();
  if (error) throw new Error(`capi settings read failed (${error.code ?? "unknown"})`);
  const v = (data?.value ?? {}) as { values?: Partial<SignalValues["values"]>; base_value_inr?: number };
  return { values: { ...DEFAULT_VALUES.values, ...(v.values ?? {}) }, base_value_inr: Number(v.base_value_inr ?? DEFAULT_VALUES.base_value_inr) };
}

/** Lead quality per paid campaign (b2b.capi_campaigns re-checks b2b.is_admin()). */
export async function capiCampaigns(days: number, platform: string | null): Promise<CapiCampaigns> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("capi_campaigns", { p_days: days, p_platform: platform });
  if (error) throw new Error(`capi_campaigns failed (${error.code ?? "unknown"})`);
  return data as CapiCampaigns;
}
