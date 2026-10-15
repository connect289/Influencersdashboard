import type { Metadata } from "next";
import { Kanban } from "@/components/lead/Kanban";
import { PipelineView, type PipelineParams } from "@/components/lead/PipelineView";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { stagesAndSubs } from "@/lib/stages";
import type { LeadRow } from "@/lib/types";

export const metadata: Metadata = { title: "Pipeline" };

/** The whole team's pipeline for the Admin, with the counsellor filter; Marketing sees the active leads by stage, read-only. */
export default async function WorkspacePipeline({ searchParams }: { searchParams: Promise<PipelineParams> }) {
  const me = await requireUser("workspace", "/w/pipeline");
  if (me.role === "admin") return <PipelineView me={me} base="/w/pipeline" leadBase="/w/leads" sp={await searchParams} />;
  let rows: LeadRow[];
  try {
    rows = (await rpc<{ rows: LeadRow[] }>("lead_list", { p: { filters: { all: [{ field: "status", op: "eq", value: "active" }] }, sort: { field: "stage_changed_at", dir: "desc" }, limit: 500 } })).rows;
  } catch (e) {
    return <Page title="Pipeline"><SetupError error={e} /></Page>;
  }
  const { stages, subs } = await stagesAndSubs();
  return (
    <Page title="Pipeline" sub={`${rows.length} active leads${rows.length === 500 ? " (first 500)" : ""}`}>
      <Kanban rows={rows} stages={stages} subs={subs} base="/w/leads" canWork={false} canMoveBack={false} showOwner />
    </Page>
  );
}
