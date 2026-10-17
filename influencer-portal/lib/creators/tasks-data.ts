import "server-only";
import type { TaskRow } from "@/components/creators/tasks";
import type { ServerSupabase } from "@/lib/supabase/server";

/** Tasks the caller can see (RLS), with assignee and related creator names. */
export async function loadTasks(
  supabase: ServerSupabase,
  opts: { status?: "open" | "done"; assignee?: string; creatorId?: string; limit?: number } = {},
): Promise<{ tasks: TaskRow[]; error: boolean }> {
  let q = supabase
    .from("tasks")
    .select("id, title, description, assignee_id, due_at, priority, status, related_type, related_id")
    .neq("status", "cancelled")
    .order("status")
    .order("due_at", { ascending: true, nullsFirst: false })
    .limit(opts.limit ?? 100);
  if (opts.status) q = q.eq("status", opts.status);
  if (opts.assignee) q = q.eq("assignee_id", opts.assignee);
  if (opts.creatorId) q = q.eq("related_type", "creator").eq("related_id", opts.creatorId);
  const { data, error } = await q;
  if (error) return { tasks: [], error: true };
  const staffIds = [...new Set(data.map((d) => d.assignee_id).filter((x): x is string => Boolean(x)))];
  const creatorIds = [
    ...new Set(
      data
        .filter((d) => d.related_type === "creator")
        .map((d) => d.related_id)
        .filter((x): x is string => Boolean(x)),
    ),
  ];
  const [staff, creators] = await Promise.all([
    staffIds.length
      ? supabase.from("staff_profiles").select("user_id, full_name").in("user_id", staffIds)
      : Promise.resolve({ data: [] as { user_id: string; full_name: string }[] }),
    creatorIds.length
      ? supabase.from("creators").select("id, display_name").in("id", creatorIds)
      : Promise.resolve({ data: [] as { id: string; display_name: string }[] }),
  ]);
  const names = new Map((staff.data ?? []).map((s) => [s.user_id, s.full_name]));
  const labels = new Map((creators.data ?? []).map((c) => [c.id, c.display_name]));
  return {
    tasks: data.map((d) => ({
      ...d,
      assignee_name: d.assignee_id ? (names.get(d.assignee_id) ?? null) : null,
      related_label: d.related_id ? (labels.get(d.related_id) ?? null) : null,
    })),
    error: false,
  };
}
