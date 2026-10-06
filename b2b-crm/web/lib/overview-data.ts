import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { CommandCenter, PoolGroup, PoolOverview } from "@/lib/overview";

/** Reads as the signed-in Admin; both functions re-check b2b.is_admin(). */
async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) throw new Error(`${fn} failed (${error.code ?? "unknown"})`);
  return data as T;
}

export const poolOverview = (group: PoolGroup | null) => rpc<PoolOverview>("pool_overview", { p_group: group });
export const commandCenter = () => rpc<CommandCenter>("command_center");
