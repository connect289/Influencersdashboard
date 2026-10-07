import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { CapiOverview } from "@/lib/capi";

/** CAPI reads as the signed-in Admin; b2b.capi_overview re-checks b2b.is_admin(). */
export async function capiOverview(status: string | null, platform: string | null): Promise<CapiOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("capi_overview", { p_status: status, p_platform: platform });
  if (error) throw new Error(`capi_overview failed (${error.code ?? "unknown"})`);
  return data as CapiOverview;
}
