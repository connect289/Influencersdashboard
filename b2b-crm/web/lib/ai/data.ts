import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { AiOverview, AiRunDetail, AskHistoryItem, MlOverview } from "./labels";

/** AI Optimiser reads as the signed-in Admin; every b2b.ai_* / ml_* function re-checks b2b.is_admin(). */
async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) throw new Error(`${fn} failed (${error.code ?? "unknown"})`);
  return data as T;
}

export const aiOverview = () => rpc<AiOverview>("ai_overview");
export const aiRunDetail = (id: number) => rpc<AiRunDetail | null>("ai_run_detail", { p_id: id });
export const mlOverview = () => rpc<MlOverview>("ml_overview");
export const askHistory = () => rpc<AskHistoryItem[]>("ai_ask_history", { p_limit: 20 });
