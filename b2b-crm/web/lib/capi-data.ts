import "server-only";
import { createClient } from "@/lib/supabase/server";
import { DEFAULT_VALUES, type CapiCampaigns, type CapiOverview, type SignalValues } from "@/lib/capi";
import { attributionSettings } from "@/lib/routing-data";

/** CAPI reads as the signed-in Admin; b2b.capi_overview re-checks b2b.is_admin(). The 'attribution' setting (what counts
 *  as paid, D38) rides along, read from b2b.settings by key under RLS like the 'capi' values below: the Setup tab's
 *  Attribution card edits it through b2b.attribution_settings_save. */
export async function capiOverview(status: string | null, platform: string | null): Promise<CapiOverview> {
  const supabase = await createClient();
  const [{ data, error }, attribution] = await Promise.all([
    supabase.schema("b2b").rpc("capi_overview", { p_status: status, p_platform: platform }),
    attributionSettings(),
  ]);
  if (error) throw new Error(`capi_overview failed (${error.code ?? "unknown"})`);
  return { ...(data as Omit<CapiOverview, "attribution">), attribution };
}

/** Signal values (settings capi.values and base_value_inr). The Admin reads b2b.settings under RLS. */
export async function capiValues(): Promise<SignalValues> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").from("settings").select("value").eq("key", "capi").maybeSingle();
  if (error) throw new Error(`capi settings read failed (${error.code ?? "unknown"})`);
  const v = (data?.value ?? {}) as { values?: Partial<SignalValues["values"]>; base_value_inr?: number };
  return { values: { ...DEFAULT_VALUES.values, ...(v.values ?? {}) }, base_value_inr: Number(v.base_value_inr ?? DEFAULT_VALUES.base_value_inr) };
}

/** Lead quality per paid campaign (b2b.capi_campaigns re-checks b2b.is_admin()). Rows are paid leads only, labelled by
 *  b2b.lead_campaign_detect (m31g): UTM-only, organic and influencer or referral leads are counted in `unpaid`. */
export async function capiCampaigns(days: number, platform: string | null): Promise<CapiCampaigns> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("capi_campaigns", { p_days: days, p_platform: platform });
  if (error) throw new Error(`capi_campaigns failed (${error.code ?? "unknown"})`);
  return data as CapiCampaigns;
}
