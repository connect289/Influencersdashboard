"use client";
import { useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { stageOverrideDecide } from "@/app/s/workspace-actions";
import { when } from "@/lib/format";

export type StageRequest = {
  id: number; lead_id: number; name: string | null; from: string | null; to: string | null; sub_stage: string; comment: string; by: string | null; created_at: string; mine: boolean;
};

/**
 * Stage changes waiting for approval (spec B3.1, B5): a counsellor asked to move a lead back; the sales head (their team)
 * or the Admin approves, which changes the stage, or declines. A counsellor sees their own requests waiting.
 */
export function StageApprovals({ requests, canDecide, leadBase }: { requests: StageRequest[]; canDecide: boolean; leadBase: string }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [notes, setNotes] = useState<Record<number, string>>({});
  if (requests.length === 0) return null;
  const decide = (q: StageRequest, approve: boolean) => start(async () => {
    const r = await stageOverrideDecide(q.id, approve, notes[q.id], q.lead_id);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Done.");
    router.refresh();
  });
  return (
    <section className="panel">
      <header><h3>{canDecide ? "Stage changes to approve" : "Waiting for approval"}</h3><span className="small muted">{requests.length}</span></header>
      <div className="body stack tight">
        {requests.map((q) => (
          <div key={q.id} className="stack tight" style={{ gap: 4 }}>
            <div className="row between wrap">
              <Link href={`${leadBase}/${q.lead_id}`}><b>{q.name ?? `Lead #${q.lead_id}`}</b></Link>
              <span className="small muted">{q.mine ? "You asked" : q.by ?? "A counsellor"} · {when(q.created_at)}</span>
            </div>
            <span className="small">{q.from ?? "?"} → <b>{q.to}</b> · {q.sub_stage}</span>
            <span className="small muted">&ldquo;{q.comment}&rdquo;</span>
            {canDecide && !q.mine && (
              <div className="row wrap" style={{ gap: 6 }}>
                <input className="input grow" style={{ minWidth: 160 }} value={notes[q.id] ?? ""} onChange={(e) => setNotes((n) => ({ ...n, [q.id]: e.target.value }))} maxLength={300} placeholder="Note (optional)" aria-label="Note" />
                <button type="button" className="btn primary sm" disabled={busy} onClick={() => decide(q, true)}>Approve</button>
                <button type="button" className="btn ghost sm" disabled={busy} onClick={() => decide(q, false)}>Decline</button>
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}
