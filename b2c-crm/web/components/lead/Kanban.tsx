"use client";
import { useState } from "react";
import Link from "next/link";
import { MoveRight } from "lucide-react";
import { when } from "@/lib/format";
import type { LeadRow, Stage, SubStage } from "@/lib/types";
import { TempChip } from "./Chips";
import { StageSheet } from "./StageButton";

type Move = { lead: LeadRow; to?: number };

/**
 * The pipeline board (spec B8.4). Drag a card to another stage, or use Move on the card (keyboard and phone): the stage
 * sheet opens on the target stage and asks for the sub-stage, comment and next follow-up as usual.
 */
export function Kanban({ rows, stages, subs, base, canWork, canMoveBack, showOwner }: {
  rows: LeadRow[]; stages: Stage[]; subs: SubStage[]; base: string; canWork: boolean; canMoveBack: boolean; showOwner?: boolean;
}) {
  const [move, setMove] = useState<Move | null>(null);
  const [over, setOver] = useState<number | null>(null);
  const byId = new Map(rows.map((r) => [r.lead_id, r]));

  return (
    <>
      <div className="kanban">
        {stages.filter((s) => s.id !== 10).map((s) => {
          const ls = rows.filter((l) => l.stage_id === s.id);
          return (
            <section key={s.id} className={`kcol${over === s.id ? " drop" : ""}`} aria-label={s.name}
              onDragOver={canWork ? (e) => { e.preventDefault(); e.dataTransfer.dropEffect = "move"; setOver(s.id); } : undefined}
              onDragLeave={() => setOver((o) => (o === s.id ? null : o))}
              onDrop={canWork ? (e) => {
                e.preventDefault();
                setOver(null);
                const lead = byId.get(Number(e.dataTransfer.getData("text/x-lead")));
                if (lead && lead.stage_id !== s.id) setMove({ lead, to: s.id });
              } : undefined}>
              <header><span>{s.name}</span><span className="muted num">{ls.length}</span></header>
              {ls.map((l) => (
                <div key={l.lead_id} className="kcard" draggable={canWork}
                  onDragStart={(e) => { e.dataTransfer.setData("text/x-lead", String(l.lead_id)); e.dataTransfer.effectAllowed = "move"; }}>
                  <Link href={`${base}/${l.lead_id}`} draggable={false}><b>{l.name ?? `Lead #${l.lead_id}`}</b></Link>
                  <span className="muted">{l.course ?? "—"}{showOwner ? ` · ${l.owner_name ?? "Unassigned"}` : ""}</span>
                  <span className="row between"><span>{l.sub_stage ?? ""}</span><TempChip t={l.temperature} /></span>
                  <span className="row between">
                    <span className="muted">Next {when(l.next_task_due_at)}</span>
                    {canWork && (
                      <button type="button" className="btn quiet sm" onClick={() => setMove({ lead: l })} aria-label={`Move ${l.name ?? "lead"} to another stage`}>
                        <MoveRight className="icon s" aria-hidden />
                      </button>
                    )}
                  </span>
                </div>
              ))}
            </section>
          );
        })}
      </div>
      {move && (
        <StageSheet leadId={move.lead.lead_id} cur={stages.find((x) => x.id === move.lead.stage_id)} stages={stages} subs={subs}
          canMoveBack={canMoveBack} initial={move.to} onClose={() => setMove(null)} />
      )}
    </>
  );
}
