"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { taskDone, taskMove } from "@/app/s/actions";
import { TASK_KIND_LABEL } from "@/lib/labels";
import { NextPicker } from "./NextPicker";

/** Done (outcome + the next follow-up, unless the lead is closed) and Move (a new time) for one follow-up. */
export function TaskActions({ taskId, title, leadId, needsNext = true }: { taskId: number; title: string; leadId: number; needsNext?: boolean }) {
  const [mode, setMode] = useState<"done" | "move" | null>(null);
  return (
    <span className="row" style={{ gap: 4 }}>
      <button type="button" className="btn ghost sm" onClick={() => setMode("done")}>Done</button>
      <button type="button" className="btn quiet sm" onClick={() => setMode("move")}>Move</button>
      {mode === "done" && <DoneSheet taskId={taskId} title={title} leadId={leadId} needsNext={needsNext} onClose={() => setMode(null)} />}
      {mode === "move" && <MoveSheet taskId={taskId} title={title} leadId={leadId} onClose={() => setMode(null)} />}
    </span>
  );
}

function DoneSheet({ taskId, title, leadId, needsNext, onClose }: { taskId: number; title: string; leadId: number; needsNext: boolean; onClose: () => void }) {
  const router = useRouter();
  const [outcome, setOutcome] = useState("");
  const [next, setNext] = useState<string | null>(null);
  const [kind, setKind] = useState("call");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const save = () =>
    start(async () => {
      const r = await taskDone(taskId, outcome || "Done", next, kind, undefined, leadId);
      if (!r.ok) return setError(r.error);
      toast.success("Done.");
      onClose();
      router.refresh();
    });
  return (
    <Sheet title={`Done: ${title}`} onClose={onClose}>
      <label className="field"><span>What happened</span><input className="input" value={outcome} onChange={(e) => setOutcome(e.target.value)} maxLength={300} /></label>
      {needsNext && (
        <>
          <div className="field">
            <span>Next step</span>
            <div className="pills">
              {Object.entries(TASK_KIND_LABEL).map(([k, v]) => <button key={k} type="button" className="pill" aria-pressed={kind === k} onClick={() => setKind(k)}>{v}</button>)}
            </div>
          </div>
          <NextPicker value={next} onChange={setNext} />
        </>
      )}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={save} disabled={busy || (needsNext && !next)}>{busy ? "Saving…" : "Mark done"}</button>
    </Sheet>
  );
}

function MoveSheet({ taskId, title, leadId, onClose }: { taskId: number; title: string; leadId: number; onClose: () => void }) {
  const router = useRouter();
  const [next, setNext] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const save = () =>
    start(async () => {
      if (!next) return;
      const r = await taskMove(taskId, next, leadId);
      if (!r.ok) return setError(r.error);
      toast.success("Moved.");
      onClose();
      router.refresh();
    });
  return (
    <Sheet title={`Move: ${title}`} onClose={onClose}>
      <NextPicker value={next} onChange={setNext} label="New time" />
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={save} disabled={busy || !next}>{busy ? "Saving…" : "Move"}</button>
    </Sheet>
  );
}
