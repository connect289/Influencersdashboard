import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { SavedView } from "@/lib/types";

/** Standard views for an interface plus the person's own and those shared with their role (RLS decides). */
export async function viewsFor(role: "sales" | "workspace"): Promise<SavedView[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("saved_views")
    .select("id, name, role, filters, sort, layout, is_standard, owner_id")
    .or(`role.eq.${role},is_standard.eq.false`)
    .order("is_standard", { ascending: false })
    .order("position")
    .order("name");
  return (data ?? []) as SavedView[];
}
