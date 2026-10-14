import type { Metadata } from "next";
import { Kanban } from "@/components/lead/Kanban";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { stagesAndSubs } from "@/lib/stages";
import type { LeadRow } from "@/lib/types";

export const metadata: Metadata = { title: "Pipeline" };

/** My active leads by stage. Drag a card to another stage, or use Move on it; the sub-stage, comment and next follow-up are asked there. */
export default async function PipelinePage() {
  const me = await requireUser("sales", "/s/pipeline");
  let rows: LeadRow[];
  try {
    rows = (await rpc<{ rows: LeadRow[] }>("lead_list", { p: { filters: { all: [{ field: "status", op: "eq", value: "active" }] }, sort: { field: "stage_changed_at", dir: "desc" }, limit: 500 } })).rows;
  } catch (e) {
    return <Page title="Pipeline"><SetupError error={e} /></Page>;
  }
  const { stages, subs } = await stagesAndSubs();
  const canWork = me.role !== "marketing";
  const canMoveBack = me.role === "admin" || me.role === "sales_head";
  return (
    <Page title="Pipeline" sub={`${rows.length} active leads`}>
      <Kanban rows={rows} stages={stages} subs={subs} base="/s/leads" canWork={canWork} canMoveBack={canMoveBack} />
    </Page>
  );
}
