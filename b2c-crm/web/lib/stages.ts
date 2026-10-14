import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Stage, SubStage } from "@/lib/types";

/** Eduwit's stages and sub-stages (b2c.stages, b2c.sub_stages), in rank order. */
export async function stagesAndSubs(): Promise<{ stages: Stage[]; subs: SubStage[] }> {
  const supabase = await createClient();
  const [s, ss] = await Promise.all([
    supabase.from("stages").select("id, name, rank, canon, reachable_from_any, is_closed").eq("active", true).order("rank"),
    supabase.from("sub_stages").select("stage_id, name, rank, returns_to_pool, comment_required").eq("active", true).order("rank"),
  ]);
  return { stages: (s.data ?? []) as Stage[], subs: (ss.data ?? []) as SubStage[] };
}
