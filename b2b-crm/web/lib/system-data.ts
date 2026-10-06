import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { ErasureRow, SystemOverview } from "@/lib/integrations";

/** System reads as the signed-in Admin; b2b.system_overview re-checks b2b.is_admin() and never returns key hashes or secrets. */
export async function systemOverview(): Promise<SystemOverview> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("system_overview");
  if (error) throw new Error(`system_overview failed (${error.code ?? "unknown"})`);
  return data as SystemOverview;
}

export async function openErasureRequests(): Promise<ErasureRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("erasure_requests_open");
  if (error) throw new Error(`erasure_requests_open failed (${error.code ?? "unknown"})`);
  return (data ?? []) as ErasureRow[];
}
