import Link from "next/link";
import type { Metadata } from "next";
import { TempChip } from "@/components/lead/Chips";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";
import { stagesAndSubs } from "@/lib/stages";
import { team } from "@/lib/team";
import type { LeadRow } from "@/lib/types";

export const metadata: Metadata = { title: "Pipeline" };

/** The whole team's active leads by stage, or one counsellor's. */
export default async function WorkspacePipeline({ searchParams }: { searchParams: Promise<{ who?: string }> }) {
  await requireUser("workspace", "/w/pipeline");
  const who = (await searchParams).who;
  let rows: LeadRow[];
  let people: { user_id: string; name: string }[];
  try {
    const filters = { all: [{ field: "status", op: "eq", value: "active" }, ...(who ? [{ field: "owner_id", op: "eq", value: who }] : [])] };
    const [res, t] = await Promise.all([rpc<{ rows: LeadRow[] }>("lead_list", { p: { filters, sort: { field: "stage_changed_at", dir: "desc" }, limit: 500 } }), team()]);
    rows = res.rows;
    people = t.filter((m) => m.user.is_active && ["counsellor", "sales_head"].includes(m.user.role)).map((m) => ({ user_id: m.user.user_id, name: m.user.full_name ?? m.user.email }));
  } catch (e) {
    return <Page title="Pipeline"><SetupError error={e} /></Page>;
  }
  const { stages } = await stagesAndSubs();
  return (
    <Page title="Pipeline" sub={`${rows.length} active leads${rows.length === 500 ? " (first 500)" : ""}`}>
      <div className="hscroll">
        <Link className="pill" href="/w/pipeline" aria-pressed={!who} style={{ color: "inherit", textDecoration: "none" }}>Whole team</Link>
        {people.map((p) => <Link key={p.user_id} className="pill" href={`/w/pipeline?who=${p.user_id}`} aria-pressed={who === p.user_id} style={{ color: "inherit", textDecoration: "none" }}>{p.name}</Link>)}
      </div>
      <div className="kanban">
        {stages.filter((s) => s.id !== 10).map((s) => {
          const ls = rows.filter((l) => l.stage_id === s.id);
          return (
            <section key={s.id} className="kcol" aria-label={s.name}>
              <header><span>{s.name}</span><span className="muted num">{ls.length}</span></header>
              {ls.map((l) => (
                <Link key={l.lead_id} className="kcard" href={`/w/leads/${l.lead_id}`}>
                  <b>{l.name ?? `Lead #${l.lead_id}`}</b>
                  <span className="muted">{l.course ?? "—"} · {l.owner_name ?? "Unassigned"}</span>
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
