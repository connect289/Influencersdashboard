"use client";
import { useState } from "react";
import Link from "next/link";
import { AlertTriangle, Clock, Flame, MoveRight } from "lucide-react";
import { inr, when } from "@/lib/format";
import type { Stage, SubStage } from "@/lib/types";
import { TempChip } from "./Chips";
import { StageSheet } from "./StageButton";

export type BoardCard = {
  lead_id: number; name: string | null; course: string | null; university: string | null; sub_stage: string | null; temperature: "hot" | "warm" | "cold" | null;
  hot: boolean; next_task_due_at: string | null; overdue: boolean; sla: "red" | "amber" | "green" | null; expected: number | null; owner_name: string | null; days_in_stage: number | null;
};
export type BoardColumn = { stage_id: number; name: string; canon: string; count: number; expected: number | null; cards: BoardCard[] };

const SLA_EDGE: Record<string, string> = { red: "var(--red)", amber: "var(--amber)", green: "var(--green)" };

/**
 * The pipeline (spec B8.2) from b2c.pipeline_board: a column per Eduwit stage with its count and expected commission, cards
 * in the database's priority order (overdue, hot, SLA at risk, highest value) with the SLA colour on the edge. Drag a card,
 * or use Move on it: the stage sheet asks for the sub-stage, comment and next follow-up under the stage rules.
 */
export function PipelineBoard({ columns, stages, subs, base, canWork, canMoveBack, showOwner }: {
  columns: BoardColumn[]; stages: Stage[]; subs: SubStage[]; base: string; canWork: boolean; canMoveBack: boolean; showOwner?: boolean;
}) {
  const [move, setMove] = useState<{ lead: number; from: number; to?: number } | null>(null);
  const [over, setOver] = useState<number | null>(null);
  const from = new Map(columns.flatMap((c) => c.cards.map((k) => [k.lead_id, c.stage_id] as const)));

  return (
    <>
      <div className="kanban">
        {columns.map((c) => (
          <section key={c.stage_id} className={`kcol${over === c.stage_id ? " drop" : ""}`} aria-label={c.name}
            onDragOver={canWork ? (e) => { e.preventDefault(); e.dataTransfer.dropEffect = "move"; setOver(c.stage_id); } : undefined}
            onDragLeave={() => setOver((o) => (o === c.stage_id ? null : o))}
            onDrop={canWork ? (e) => {
              e.preventDefault();
              setOver(null);
              const lead = Number(e.dataTransfer.getData("text/x-lead"));
              const was = from.get(lead);
              if (lead && was !== undefined && was !== c.stage_id) setMove({ lead, from: was, to: c.stage_id });
            } : undefined}>
            <header>
              <span>{c.name}</span>
              <span className="muted num" title="Leads · expected commission">{c.count}{c.expected ? ` · ${inr(c.expected)}` : ""}</span>
            </header>
            {c.count > c.cards.length && <span className="note">Showing the first {c.cards.length} by priority.</span>}
            {c.cards.map((k) => (
              <div key={k.lead_id} className="kcard" draggable={canWork} style={k.sla ? { boxShadow: `inset 3px 0 0 ${SLA_EDGE[k.sla]}, var(--shadow-1)` } : undefined}
                onDragStart={(e) => { e.dataTransfer.setData("text/x-lead", String(k.lead_id)); e.dataTransfer.effectAllowed = "move"; }}>
                <Link href={`${base}/${k.lead_id}`} draggable={false}><b>{k.name ?? `Lead #${k.lead_id}`}</b></Link>
                <span className="muted">{k.course ?? "—"}{k.university ? ` · ${k.university}` : ""}{showOwner ? ` · ${k.owner_name ?? "Unassigned"}` : ""}</span>
                <span className="row between"><span>{k.sub_stage ?? ""}</span>{k.hot && k.temperature !== "hot" ? <span className="chip hot"><Flame className="icon s" aria-hidden />Hot</span> : <TempChip t={k.temperature} />}</span>
                <span className="row wrap" style={{ gap: 4 }}>
                  {k.overdue && <span className="chip breach"><Clock className="icon s" aria-hidden />Overdue</span>}
                  {k.sla === "red" && <span className="chip breach"><AlertTriangle className="icon s" aria-hidden />SLA breached</span>}
                  {k.sla === "amber" && <span className="chip risk"><Clock className="icon s" aria-hidden />SLA at risk</span>}
                  {k.expected ? <span className="chip line">{inr(k.expected)}</span> : null}
                </span>
                <span className="row between">
                  <span className="muted">Next {when(k.next_task_due_at)}{k.days_in_stage ? ` · ${k.days_in_stage} d in stage` : ""}</span>
                  {canWork && (
                    <button type="button" className="btn quiet sm" onClick={() => setMove({ lead: k.lead_id, from: c.stage_id })} aria-label={`Move ${k.name ?? "lead"} to another stage`}>
                      <MoveRight className="icon s" aria-hidden />
                    </button>
                  )}
                </span>
              </div>
            ))}
          </section>
        ))}
      </div>
      {move && (
        <StageSheet leadId={move.lead} cur={stages.find((x) => x.id === move.from)} stages={stages} subs={subs}
          canMoveBack={canMoveBack} initial={move.to} onClose={() => setMove(null)} />
      )}
    </>
  );
}
