"use client";
import { useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { relative, when } from "@/lib/format";
import { queueAllocate } from "../admin-actions";
import { reassign } from "../actions";

export type QueueRow = {
  lead_id: number; name: string | null; course: string | null; hot: boolean; temperature: string | null; source: string | null; waiting_since: string | null;
  is_test: boolean; queue: "unassigned" | "waiting_hours" | "manual"; rule: string | null; why: string | null; eligible: { user_id: string; name: string }[] | null; decided_at: string | null;
};
export type Queues = Record<"unassigned" | "waiting_hours" | "manual", QueueRow[]>;

const QUEUES: [keyof Queues, string, string][] = [
  ["manual", "Manual queue", "A rule sends these to a person to hand out. The minute timer leaves them alone: give each one to someone, or decide again by the rules."],
  ["unassigned", "Unassigned", "Nobody could take these: everyone at their cap, on leave, away or off hours with no on-call. The engine retries every minute."],
  ["waiting_hours", "Waiting for working hours", "Not hot and outside hours: they go to the next person who starts work."],
];

/** The queues apart (spec B7.4): one click decides again now; "Give to…" picks a person with a reason. */
export function QueuesView({ queues, people, canAct }: { queues: Queues; people: { user_id: string; name: string }[]; canAct: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [give, setGive] = useState<QueueRow | null>(null);
  const decide = (l: QueueRow) => start(async () => {
    const r = await queueAllocate(l.lead_id);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Done.");
    router.refresh();
  });
  return (
    <div className="stack">
      {QUEUES.map(([k, title, note]) => (
        <section key={k} className="panel">
          <header><h3>{title}</h3><span className={`chip ${queues[k].length ? (k === "waiting_hours" ? "line" : "risk") : "ok"}`}>{queues[k].length}</span></header>
          <div className="body stack" style={{ gap: 8 }}>
            <p className="note">{note}</p>
            {queues[k].length > 0 && (
              <div className="table-wrap" style={{ boxShadow: "none" }}><table>
                <thead><tr><th>Student</th><th>Source</th><th>Waiting</th><th>Last decision</th>{canAct && <th />}</tr></thead>
                <tbody>{queues[k].map((l) => (
                  <tr key={l.lead_id}>
                    <td><Link href={`/w/leads/${l.lead_id}`}>{l.name ?? `Lead #${l.lead_id}`}</Link>{l.hot && <span className="chip hot" style={{ marginLeft: 4 }}>Hot</span>}{l.is_test && <span className="chip line" style={{ marginLeft: 4 }}>Test</span>}
                      <div className="small muted">{l.course ?? "—"}</div></td>
                    <td className="small">{l.source ?? "—"}</td>
                    <td className="small nowrap" title={when(l.waiting_since)}>{relative(l.waiting_since)}</td>
                    <td className="small">{l.rule ?? "—"}{l.why ? <div className="muted">{l.why}</div> : null}</td>
                    {canAct && <td className="row" style={{ gap: 4, justifyContent: "flex-end" }}>
                      <button type="button" className="btn ghost sm" disabled={busy} onClick={() => decide(l)}>Decide now</button>
                      <button type="button" className="btn quiet sm" disabled={busy} onClick={() => setGive(l)}>Give to…</button>
                    </td>}
                  </tr>
                ))}</tbody>
              </table></div>
            )}
          </div>
        </section>
      ))}
      {give && <GiveSheet lead={give} people={people} onClose={() => setGive(null)} />}
    </div>
  );
}

function GiveSheet({ lead, people, onClose }: { lead: QueueRow; people: { user_id: string; name: string }[]; onClose: () => void }) {
  const router = useRouter();
  const eligible = new Set((lead.eligible ?? []).map((e) => e.user_id));
  const [who, setWho] = useState((lead.eligible ?? [])[0]?.user_id ?? "");
  const [why, setWhy] = useState(lead.queue === "manual" ? "manual queue" : "");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const save = () => start(async () => {
    const r = await reassign([lead.lead_id], who, why);
    if (!r.ok) return setError(r.error);
    toast.success(r.notice ?? "Given.");
    onClose();
    router.refresh();
  });
  return (
    <Sheet title={`Give ${lead.name ?? `lead #${lead.lead_id}`} to…`} onClose={onClose}>
      <label className="field"><span>Counsellor</span><select className="input" value={who} onChange={(e) => setWho(e.target.value)}>
        <option value="">Choose</option>
        {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}{eligible.has(p.user_id) ? " · eligible now" : ""}</option>)}
      </select></label>
      {lead.is_test && <p className="note">A test lead: give it to a test user or the Admin.</p>}
      <label className="field"><span>Reason (on the timeline)</span><input className="input" value={why} onChange={(e) => setWhy(e.target.value)} maxLength={200} /></label>
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" disabled={busy || !who || why.trim().length < 3} onClick={save}>{busy ? "Giving…" : "Give the lead"}</button>
      <p className="note">The person is told at once; the assignment message goes to the student as usual.</p>
    </Sheet>
  );
}
