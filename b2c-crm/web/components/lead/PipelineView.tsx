import Link from "next/link";
import { Search } from "lucide-react";
import { Page, SetupError } from "@/components/shell/Page";
import type { Me } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { inr } from "@/lib/format";
import { salesPeople, type Person } from "@/lib/people";
import { stagesAndSubs } from "@/lib/stages";
import { PipelineBoard, type BoardColumn } from "./PipelineBoard";

export type PipelineParams = { temperature?: string; source?: string; hot?: string; overdue?: string; q?: string; owner?: string };

/** The pipeline page (spec B8.2) for /s/pipeline and /w/pipeline: filters, then the board from b2c.pipeline_board. */
export async function PipelineView({ me, base, leadBase, sp }: { me: Me; base: string; leadBase: string; sp: PipelineParams }) {
  const lead = me.role === "admin" || me.role === "sales_head";
  const owner = lead && sp.owner && /^[0-9a-f-]{36}$/i.test(sp.owner) ? sp.owner : null;
  let board: { columns: BoardColumn[] };
  let people: Person[] = [];
  try {
    [board, people] = await Promise.all([
      rpc<{ columns: BoardColumn[] }>("pipeline_board", { p: {
        owner, temperature: ["hot", "warm", "cold"].includes(sp.temperature ?? "") ? sp.temperature : null, source: sp.source?.trim() || null,
        hot: sp.hot === "1", overdue: sp.overdue === "1", search: sp.q?.trim() || "",
      } }),
      lead ? salesPeople(me) : Promise.resolve([]),
    ]);
  } catch (e) {
    return <Page title="Pipeline"><SetupError error={e} /></Page>;
  }
  const { stages, subs } = await stagesAndSubs();
  const total = board.columns.reduce((a, c) => a + c.count, 0);
  const value = board.columns.reduce((a, c) => a + Number(c.expected ?? 0), 0);
  return (
    <Page title="Pipeline" sub={`${total} active leads${value ? ` · ${inr(value)} expected commission` : ""}${owner ? ` · ${people.find((p) => p.user_id === owner)?.name ?? "one counsellor"}` : ""}`}>
      <form className="row wrap" action={base} role="search" style={{ gap: 6 }}>
        <label className="search grow" style={{ minWidth: 200 }}><Search className="icon s" aria-hidden /><input name="q" defaultValue={sp.q ?? ""} placeholder="Name or programme" aria-label="Search the pipeline" /></label>
        {lead && (
          <select className="input" name="owner" defaultValue={owner ?? ""} style={{ width: "auto" }} aria-label="Counsellor">
            <option value="">{me.role === "sales_head" ? "My whole team" : "Everyone"}</option>
            {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
          </select>
        )}
        <select className="input" name="temperature" defaultValue={sp.temperature ?? ""} style={{ width: "auto" }} aria-label="Temperature">
          <option value="">Any temperature</option><option value="hot">Hot</option><option value="warm">Warm</option><option value="cold">Cold</option>
        </select>
        <input className="input" name="source" defaultValue={sp.source ?? ""} placeholder="Source" style={{ width: 130 }} aria-label="Source" />
        <label className="checkbox"><input type="checkbox" name="hot" value="1" defaultChecked={sp.hot === "1"} /> Hot only</label>
        <label className="checkbox"><input type="checkbox" name="overdue" value="1" defaultChecked={sp.overdue === "1"} /> Overdue</label>
        <button className="btn ghost sm" type="submit">Show</button>
        {Object.values(sp).some(Boolean) && <Link className="btn quiet sm" href={base}>Clear</Link>}
      </form>
      <p className="note">Cards are in priority order: overdue follow-up, hot, SLA at risk, then the highest expected commission. The coloured edge is the first-contact SLA.</p>
      <PipelineBoard columns={board.columns} stages={stages} subs={subs} base={leadBase} canWork canMoveBack={lead} showOwner={me.role !== "counsellor"} />
    </Page>
  );
}
