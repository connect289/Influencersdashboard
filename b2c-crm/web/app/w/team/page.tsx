import type { Metadata } from "next";
import { Page, SetupError } from "@/components/shell/Page";
import { TeamView } from "@/components/team/TeamView";
import { requireUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Team performance" };

/** Team performance for the Admin (targets) and Marketing (read only). */
export default async function TeamPage() {
  const me = await requireUser("workspace", "/w/team");
  let body: React.ReactNode;
  try {
    body = await TeamView({ canSetTargets: me.role === "admin" });
  } catch (e) {
    body = <SetupError error={e} />;
  }
  return <Page title="Team performance">{body}</Page>;
}
