"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { deleteLeads, reassign, restoreLeads, routeToPartners, tagLeads } from "../actions";

type Person = { user_id: string; name: string };
const DELETE_REASONS = ["junk", "test", "duplicate entry", "spam", "student request"];

/**
 * Bulk tools over the ticked rows (spec B12.2). Reassign, tag and route ask for a reason where the database needs one;
 * delete is soft (30-day Recycle bin) and keeps leads with an enrolment.
 */
export function BulkBar({ people, admin, recycle }: { people: Person[]; admin: boolean; recycle: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [op, setOp] = useState<string>(recycle ? "restore" : admin ? "reassign" : "tag");
  const [to, setTo] = useState<string>("");
  const [text, setText] = useState("");
  const [reason, setReason] = useState(DELETE_REASONS[0]!);

  function selected(form: HTMLFormElement): number[] {
    return Array.from(document.querySelectorAll<HTMLInputElement>(`input[form="${form.id}"][name="lead"]:checked`)).map((i) => Number(i.value));
  }

  function run(form: HTMLFormElement) {
    const leads = selected(form);
    if (leads.length === 0) return void toast.error("Tick at least one lead.");
    start(async () => {
      let msg: string | null = null;
      let error: string | null = null;
      if (op === "reassign") {
        const r = await reassign(leads, to || null, text);
        if (r.ok) msg = `${r.data} reassigned.`; else error = r.error;
      } else if (op === "tag" || op === "untag") {
        const r = await tagLeads(leads, text, op === "tag");
        if (r.ok) msg = r.notice ?? "Done."; else error = r.error;
      } else if (op === "route") {
        const r = await routeToPartners(leads, text);
        if (r.ok) msg = `${r.data?.sent ?? 0} sent to partner routing.${r.data?.refused.length ? ` Refused: ${r.data.refused.map((x) => `#${x.lead_id} (${x.why})`).join(", ")}.` : ""}`;
        else error = r.error;
      } else if (op === "delete") {
        const r = await deleteLeads(leads, reason);
        if (r.ok) msg = `${r.data?.deleted ?? 0} moved to the Recycle bin.${r.data?.kept.length ? ` Kept: ${r.data.kept.map((x) => `#${x.lead_id} (${x.why})`).join(", ")}.` : ""}`;
        else error = r.error;
      } else if (op === "restore") {
        const r = await restoreLeads(leads);
        if (r.ok) msg = `${r.data} restored.`; else error = r.error;
      }
      if (error) toast.error(error);
      else {
        toast.success(msg ?? "Done.");
        setText("");
        router.refresh();
      }
    });
  }

  const needsText = op === "reassign" || op === "route" || op === "tag" || op === "untag";
  return (
    <form id="bulk" className="bulkbar" onSubmit={(e) => { e.preventDefault(); run(e.currentTarget); }}>
      <b>With the ticked leads:</b>
      <select className="input" value={op} onChange={(e) => setOp(e.target.value)} aria-label="Action">
        {recycle ? <option value="restore">Restore</option> : (
          <>
            {admin && <option value="reassign">Reassign</option>}
            <option value="tag">Add a tag</option>
            <option value="untag">Remove a tag</option>
            {admin && <option value="route">Send to partner routing</option>}
            {admin && <option value="delete">Delete</option>}
          </>
        )}
      </select>
      {op === "reassign" && (
        <select className="input" value={to} onChange={(e) => setTo(e.target.value)} aria-label="To">
          <option value="">Through the allocation rules</option>
          {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
        </select>
      )}
      {op === "delete" && (
        <select className="input" value={reason} onChange={(e) => setReason(e.target.value)} aria-label="Reason">
          {DELETE_REASONS.map((r) => <option key={r}>{r}</option>)}
        </select>
      )}
      {needsText && (
        <input className="input" value={text} onChange={(e) => setText(e.target.value)} required minLength={op.includes("tag") ? 1 : 3}
          placeholder={op.includes("tag") ? "Tag" : "Reason (kept in the audit log)"} aria-label={op.includes("tag") ? "Tag" : "Reason"} maxLength={300} />
      )}
      <button className={`btn ${op === "delete" ? "danger" : "ghost"} sm`} type="submit" disabled={busy}>{busy ? "Working…" : "Apply"}</button>
    </form>
  );
}
