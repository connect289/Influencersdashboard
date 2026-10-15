import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Team, type TeamData } from "./Team";

export const metadata: Metadata = { title: "Team" };

/** M33a: who can use the CRM. b2b.team_list re-checks b2b.is_admin(). */
export default async function TeamPage() {
  await requireAdmin();
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("team_list");
  if (error) throw new Error(`team_list failed (${error.code ?? "unknown"})`);
  return (
    <>
      <PageHeader title="Team" description="Members and their roles, invitations, and each member's two-step rule. The database checks the role on every call." />
      <Team data={data as TeamData} />
    </>
  );
}
