import Link from "next/link";
import type { Metadata } from "next";
import { Kanban } from "@/components/lead/Kanban";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { stagesAndSubs } from "@/lib/stages";
import { team } from "@/lib/team";
import type { LeadRow } from "@/lib/types";

export const metadata: Metadata = { title: "Pipeline" };

/** The whole team's active leads by stage, or one counsellor's. */
export default async function WorkspacePipeline({ searchParams }: { searchParams: Promise<{ who?: string }> }) {
  const me = await requireUser("workspace", "/w/pipeline");
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
  const { stages, subs } = await stagesAndSubs();
  const canWork = me.role !== "marketing";
  const canMoveBack = me.role === "admin" || me.role === "sales_head";
  return (
    <Page title="Pipeline" sub={`${rows.length} active leads${rows.length === 500 ? " (first 500)" : ""}`}>
      <div className="hscroll">
        <Link className="pill" href="/w/pipeline" aria-pressed={!who} style={{ color: "inherit", textDecoration: "none" }}>Whole team</Link>
        {people.map((p) => <Link key={p.user_id} className="pill" href={`/w/pipeline?who=${p.user_id}`} aria-pressed={who === p.user_id} style={{ color: "inherit", textDecoration: "none" }}>{p.name}</Link>)}
      </div>
      <Kanban rows={rows} stages={stages} subs={subs} base="/w/leads" canWork={canWork} canMoveBack={canMoveBack} showOwner />
    </Page>
  );
}
