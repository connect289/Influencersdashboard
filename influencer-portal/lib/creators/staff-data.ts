import "server-only";
import type { Option, SavedView } from "@/components/creators/creator-filters";
import { creatorFiltersToQuery, creatorFilterSchema } from "@/lib/creators/crm";
import type { ServerSupabase } from "@/lib/supabase/server";

/** Active staff (owner and assignee pickers) and tiers. */
export async function loadPickers(
  supabase: ServerSupabase,
): Promise<{ owners: Option[]; tiers: Option[] }> {
  const [staff, tiers] = await Promise.all([
    supabase
      .from("staff_profiles")
      .select("user_id, full_name")
      .eq("status", "active")
      .order("full_name"),
    supabase.from("tiers").select("id, name").eq("active", true).order("rank"),
  ]);
  return {
    owners: (staff.data ?? []).map((s) => ({ id: s.user_id, name: s.full_name })),
    tiers: (tiers.data ?? []).map((x) => ({ id: x.id, name: x.name })),
  };
}

export async function loadSavedViews(
  supabase: ServerSupabase,
  userId: string,
): Promise<SavedView[]> {
  const { data } = await supabase
    .from("saved_views")
    .select("id, name, filters, is_shared, owner_id")
    .eq("scope", "creators")
    .order("name");
  return (data ?? []).map((v) => ({
    id: v.id,
    name: v.name,
    is_shared: v.is_shared,
    mine: v.owner_id === userId,
    query: creatorFiltersToQuery(creatorFilterSchema.parse(v.filters)),
  }));
}
