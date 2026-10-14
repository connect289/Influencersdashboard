"use client";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ChevronDown } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { setStage } from "@/app/s/actions";
import type { Stage, SubStage } from "@/lib/types";
import { NextPicker } from "./NextPicker";

/**
 * Stage and sub-stage (spec B9): the sub-stage is required, Lost needs a comment, and work that continues needs the next
 * follow-up. Moving back is the Admin's (the database refuses it otherwise; the button is greyed for clarity).
 */
export function StageButton({ leadId, current, sub, stages, subs, canMoveBack, disabled }: {
  leadId: number; current: number | null; sub: string | null; stages: Stage[]; subs: SubStage[]; canMoveBack: boolean; disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const cur = stages.find((s) => s.id === current);
  return (
    <>
      <button type="button" className="chip soft" style={{ border: 0 }} onClick={() => setOpen(true)} disabled={disabled}>
        {cur?.name ?? "No stage"}{sub ? ` · ${sub}` : ""} <ChevronDown className="icon s" aria-hidden />
      </button>
      {open && <StageSheet leadId={leadId} cur={cur} stages={stages} subs={subs} canMoveBack={canMoveBack} onClose={() => setOpen(false)} />}
    </>
  );
}

export function StageSheet({ leadId, cur, stages, subs, canMoveBack, onClose, initial }: { leadId: number; cur?: Stage; stages: Stage[]; subs: SubStage[]; canMoveBack: boolean; onClose: () => void; initial?: number }) {
  const router = useRouter();
  const [stage, setStageId] = useState<number>(initial ?? cur?.id ?? 1);
  const [sub, setSub] = useState<string | null>(null);
  const [comment, setComment] = useState("");
  const [next, setNext] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const st = stages.find((s) => s.id === stage);
  const options = useMemo(() => subs.filter((s) => s.stage_id === stage).sort((a, b) => a.rank - b.rank), [subs, stage]);
  const subRow = options.find((s) => s.name === sub);
  const closing = stage === 9 || stage === 10;
  const needsComment = stage === 10 || subRow?.comment_required;
  const back = (s: Stage) => cur && s.rank < cur.rank && !s.reachable_from_any;
  const ready = !!sub && (closing || !!next) && (!needsComment || comment.trim().length >= 3) && (!st || !back(st) || comment.trim().length >= 3);

  const save = () =>
    start(async () => {
      const r = await setStage({ lead: leadId, stage, sub: sub!, comment: comment || undefined, next: closing ? undefined : next ?? undefined });
      if (!r.ok) return setError(r.error);
      toast.success(`Stage saved: ${st?.name} · ${sub}`);
      onClose();
      router.refresh();
    });

  return (
    <Sheet title="Change stage" onClose={onClose}>
      <div className="field">
        <span>Stage</span>
        <div className="pills">
          {stages.map((s) => (
            <button key={s.id} type="button" className="pill" aria-pressed={stage === s.id} disabled={back(s) && !canMoveBack}
              onClick={() => { setStageId(s.id); setSub(null); }} title={back(s) && !canMoveBack ? "Moving back needs the Admin" : undefined}>
              {s.name}
            </button>
          ))}
        </div>
      </div>
      <div className="field">
        <span>Sub-stage (required)</span>
        <div className="pills">
          {options.map((s) => <button key={s.name} type="button" className="pill" aria-pressed={sub === s.name} onClick={() => setSub(s.name)}>{s.name}</button>)}
        </div>
      </div>
      <label className="field">
        <span>Comment {needsComment || (st && back(st)) ? "(required)" : "(optional)"}</span>
        <textarea className="input" value={comment} onChange={(e) => setComment(e.target.value)} maxLength={1000} placeholder="Shown on the timeline" />
      </label>
      {!closing && <NextPicker value={next} onChange={setNext} />}
      {stage === 10 && subRow && (
        <div className="banner info">{subRow.returns_to_pool ? "The lead goes to the nurture pool; a journey starts later and it can come back to you hot." : "The lead closes and never returns to nurture."}</div>
      )}
      {stage === 9 && <div className="banner info">Record the enrolment (fee, date and proof) under Applications first; the stage then moves by itself.</div>}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={save} disabled={!ready || busy}>{busy ? "Saving…" : "Save stage"}</button>
      <p className="note">You see Eduwit&apos;s stages; the master lead table gets the matching canonical stage ({st?.canon}).</p>
    </Sheet>
  );
}
