"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { when } from "@/lib/format";
import { ROLE_LABEL } from "@/lib/labels";
import { phoneSet } from "./phone-actions";

export type Directory = {
  people: { user_id: string; name: string | null; email: string; role: string; active: boolean; mobile: string | null; caller_id: string | null }[];
  company_caller_id: string | null;
  history: { at: string; name: string | null; kind: string; old: string | null; new: string | null; reason: string | null; by: string | null }[];
};

/**
 * Phone numbers (Admin): each person's work mobile (the number they dial from; Exotel rings it first when calling through
 * the CRM is on) and, optionally, their own caller ID (the number students see). A number held by someone else can be
 * moved; every change keeps who, when and why.
 */
export function PhoneNumbers({ d }: { d: Directory }) {
  const [edit, setEdit] = useState<{ user: Directory["people"][number]; kind: "mobile" | "caller_id" } | null>(null);
  const people = d.people.filter((p) => p.active && p.role !== "marketing");
  return (
    <section className="stack">
      <div className="row between"><h2>Phone numbers</h2><span className="small muted">Company caller ID: {d.company_caller_id ?? "not set (Settings → telephony)"}</span></div>
      <div className="table-wrap"><table>
        <thead><tr><th>Person</th><th>Work mobile</th><th>Caller ID students see</th></tr></thead>
        <tbody>{people.map((p) => (
          <tr key={p.user_id}>
            <td><b>{p.name ?? p.email}</b><div className="small muted">{ROLE_LABEL[p.role] ?? p.role}</div></td>
            <td><span className="mono">{p.mobile ?? "—"}</span> <button type="button" className="btn quiet sm" onClick={() => setEdit({ user: p, kind: "mobile" })}>Change</button></td>
            <td><span className="mono">{p.caller_id ?? <span className="muted">company number</span>}</span> <button type="button" className="btn quiet sm" onClick={() => setEdit({ user: p, kind: "caller_id" })}>Change</button></td>
          </tr>
        ))}</tbody>
      </table></div>
      {d.history.length > 0 && (
        <details><summary className="small">History of changes ({d.history.length})</summary>
          <div className="table-wrap"><table>
            <thead><tr><th>When</th><th>Person</th><th>Number</th><th>From → to</th><th>Why</th><th>By</th></tr></thead>
            <tbody>{d.history.map((h, i) => <tr key={i}><td className="small">{when(h.at)}</td><td>{h.name}</td><td>{h.kind === "mobile" ? "Work mobile" : "Caller ID"}</td>
              <td className="mono small">{h.old ?? "—"} → {h.new ?? "—"}</td><td className="small">{h.reason ?? "—"}</td><td className="small">{h.by ?? "system"}</td></tr>)}</tbody>
          </table></div></details>
      )}
      {edit && <PhoneSheet user={edit.user} kind={edit.kind} onClose={() => setEdit(null)} />}
    </section>
  );
}

function PhoneSheet({ user, kind, onClose }: { user: Directory["people"][number]; kind: "mobile" | "caller_id"; onClose: () => void }) {
  const router = useRouter();
  const [num, setNum] = useState((kind === "mobile" ? user.mobile : user.caller_id) ?? "");
  const [reason, setReason] = useState("");
  const [held, setHeld] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const save = (move = false) => start(async () => {
    const r = await phoneSet({ user_id: user.user_id, kind, number: num, reason, move });
    if (!r.ok) {
      if (/is allocated to/.test(r.error)) return setHeld(r.error);
      return void toast.error(r.error);
    }
    toast.success(r.data?.moved_from ? `Moved from ${r.data.moved_from}. Both are told.` : r.notice ?? "Saved.");
    onClose();
    router.refresh();
  });
  return (
    <Sheet title={`${kind === "mobile" ? "Work mobile" : "Caller ID"} for ${user.name ?? user.email}`} onClose={onClose}>
      <div className="stack">
        <label className="field"><span>{kind === "mobile" ? "Work mobile" : "Caller ID (leave empty to use the company number)"}</span>
          <input className="input mono" value={num} onChange={(e) => { setNum(e.target.value); setHeld(null); }} placeholder="+91 90000 00000" inputMode="tel" /></label>
        <label className="field"><span>Reason (kept in the history)</span><input className="input" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. new company SIM" /></label>
        <p className="note">{kind === "mobile" ? "The number they dial from. When calling through the CRM is on, Exotel rings this phone first." : "The number students see when calling through the CRM is on (an Exotel virtual number)."}</p>
        {held && <div className="banner"><div className="grow">{held}.</div><button type="button" className="btn ghost sm" disabled={busy} onClick={() => save(true)}>Move it</button></div>}
        <button type="button" className="btn primary block" disabled={busy || reason.trim().length < 3} onClick={() => save(false)}>Save</button>
      </div>
    </Sheet>
  );
}
