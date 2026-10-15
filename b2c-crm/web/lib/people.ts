import "server-only";
import type { Me } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export type Person = { user_id: string; name: string };

/**
 * People who hold leads, for the counsellor filters and the sales head's reassign: the Admin sees everyone, a sales head
 * with a team their team (b2c.in_my_team), anyone else nobody. Read from b2c.users (staff may read it).
 */
export async function salesPeople(me: Pick<Me, "user_id" | "role">): Promise<Person[]> {
  if (me.role !== "admin" && me.role !== "sales_head" && me.role !== "marketing") return [];
  const supabase = await createClient();
  const { data } = await supabase.from("users").select("user_id, full_name, email, role, is_active, team")
    .eq("is_active", true).in("role", ["counsellor", "sales_head", "admin"]).order("full_name");
  const rows = (data ?? []) as { user_id: string; full_name: string | null; email: string; role: string; team: string | null }[];
  const myTeam = me.role === "sales_head" ? rows.find((r) => r.user_id === me.user_id)?.team ?? null : null;
  return rows.filter((r) => !myTeam || r.team === myTeam).map((r) => ({ user_id: r.user_id, name: r.full_name ?? r.email }));
}
