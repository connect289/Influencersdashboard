import type { Metadata } from "next";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { TeamView } from "@/components/team/TeamView";
import { requireUser } from "@/lib/auth";

export const metadata: Metadata = { title: "My team" };

/** The sales head's team: the month against target (they set counsellors' targets), activity and capacity. */
export default async function SalesTeamPage() {
  const me = await requireUser("sales", "/s/team");
  if (me.role !== "sales_head" && me.role !== "admin") return <Page title="My team"><Empty>This page is for the sales head.</Empty></Page>;
  let body: React.ReactNode;
  try {
    body = await TeamView({ canSetTargets: true });
  } catch (e) {
    body = <SetupError error={e} />;
  }
  return <Page title="My team">{body}</Page>;
}
