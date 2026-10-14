import Link from "next/link";
import type { Metadata } from "next";
import { TempChip } from "@/components/lead/Chips";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";
import { stagesAndSubs } from "@/lib/stages";
import type { LeadRow } from "@/lib/types";

export const metadata: Metadata = { title: "Pipeline" };

/** My active leads by stage. Open a card to change its stage (the sub-stage, comment and next follow-up are asked there). */
export default async function PipelinePage() {
  await requireUser("sales", "/s/pipeline");
  let rows: LeadRow[];
  try {
    rows = (await rpc<{ rows: LeadRow[] }>("lead_list", { p: { filters: { all: [{ field: "status", op: "eq", value: "active" }] }, sort: { field: "stage_changed_at", dir: "desc" }, limit: 500 } })).rows;
  } catch (e) {
    return <Page title="Pipeline"><SetupError error={e} /></Page>;
  }
  const { stages } = await stagesAndSubs();
  return (
    <Page title="Pipeline" sub={`${rows.length} active leads`}>
      <div className="kanban">
        {stages.filter((s) => s.id !== 10).map((s) => {
          const ls = rows.filter((l) => l.stage_id === s.id);
          return (
            <section key={s.id} className="kcol" aria-label={s.name}>
              <header><span>{s.name}</span><span className="muted num">{ls.length}</span></header>
              {ls.map((l) => (
                <Link key={l.lead_id} className="kcard" href={`/s/leads/${l.lead_id}`}>
                  <b>{l.name ?? `Lead #${l.lead_id}`}</b>
                  <span className="muted">{l.course ?? "—"}</span>
                  <span className="row between"><span>{l.sub_stage ?? ""}</span><TempChip t={l.temperature} /></span>
                  <span className="muted">Next {when(l.next_task_due_at)}</span>
                </Link>
              ))}
            </section>
          );
        })}
      </div>
    </Page>
  );
}
