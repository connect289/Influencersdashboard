"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { toast } from "sonner";
import { when } from "@/lib/format";
import { checklistSave } from "../admin-actions";

export type ChecklistData = {
  lists: { university: string; items: string[] }[];
  history: { at: string; by: string | null; detail: { university: string; old: string[] | null; new: string[]; reason: string | null } }[] | null;
};

/** Document checklists per university (spec B8.8): "*" is the default list for universities without their own. */
export function Checklists({ data, universities }: { data: ChecklistData; universities: string[] }) {
  const [adding, setAdding] = useState(false);
  const missing = universities.filter((u) => !data.lists.some((l) => l.university === u));
  return (
    <div className="stack">
      <p className="note">Counsellors tick these on each application. A university without its own list uses the default (*). Each change needs a reason and is kept below.</p>
      {data.lists.map((l) => <ListEditor key={l.university} university={l.university} items={l.items} />)}
      {adding ? <ListEditor university="" items={[]} fresh suggestions={missing} onDone={() => setAdding(false)} />
        : <button type="button" className="btn ghost sm" style={{ justifySelf: "start" }} onClick={() => setAdding(true)}><Plus className="icon s" aria-hidden />A list for a university</button>}
      <section className="panel">
        <header><h3>Change history</h3></header>
        <div className="body">
          {!data.history?.length ? <p className="note">No changes yet.</p> : (
            <div className="table-wrap" style={{ boxShadow: "none" }}><table>
              <thead><tr><th>When</th><th>Who</th><th>List</th><th>Change</th><th>Reason</th></tr></thead>
              <tbody>{data.history.map((h, i) => {
                const old = h.detail.old ?? [], nu = h.detail.new ?? [];
                const added = nu.filter((x) => !old.includes(x)), gone = old.filter((x) => !nu.includes(x));
                return <tr key={i}><td className="nowrap small">{when(h.at)}</td><td>{h.by ?? "—"}</td><td>{h.detail.university === "*" ? "Default" : h.detail.university}</td>
                  <td className="small">{[added.length && `added ${added.join(", ")}`, gone.length && `removed ${gone.join(", ")}`].filter(Boolean).join("; ") || "reordered"}</td>
                  <td className="small">{h.detail.reason ?? "—"}</td></tr>;
              })}</tbody>
            </table></div>
          )}
        </div>
      </section>
    </div>
  );
}

function ListEditor({ university, items, fresh, suggestions, onDone }: { university: string; items: string[]; fresh?: boolean; suggestions?: string[]; onDone?: () => void }) {
  const router = useRouter();
  const [uni, setUni] = useState(university);
  const [text, setText] = useState(items.join("\n"));
  const [why, setWhy] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const list = text.split("\n").map((x) => x.trim()).filter(Boolean);
  const dirty = fresh || list.join("\n") !== items.join("\n");
  const save = () => start(async () => {
    const r = await checklistSave(uni, list, why);
    if (!r.ok) return setError(r.error);
    setError(null); setWhy("");
    toast.success(r.notice ?? "Saved.");
    onDone?.();
    router.refresh();
  });
  return (
    <section className="panel">
      <header>
        {fresh ? <label className="field grow"><span>University (as on applications)</span>
          <input className="input" list="checklist-unis" value={uni} onChange={(e) => setUni(e.target.value)} maxLength={200} />
          <datalist id="checklist-unis">{(suggestions ?? []).map((u) => <option key={u} value={u} />)}</datalist></label>
          : <h3>{university === "*" ? "Default list (*)" : university}</h3>}
        {!fresh && <span className="small muted">{items.length} documents</span>}
      </header>
      <div className="body stack" style={{ gap: 8 }}>
        <label className="field"><span>One document a line</span><textarea className="input" rows={Math.min(10, Math.max(4, list.length + 1))} value={text} onChange={(e) => setText(e.target.value)} /></label>
        {dirty && <div className="row wrap">
          <input className="input grow" value={why} onChange={(e) => setWhy(e.target.value)} placeholder="Reason for the change (required)" aria-label="Reason" maxLength={300} />
          <button type="button" className="btn primary sm" disabled={busy || why.trim().length < 3 || !uni.trim()} onClick={save}>{busy ? "Saving…" : "Save"}</button>
          <button type="button" className="btn quiet sm" onClick={() => { setText(items.join("\n")); setError(null); onDone?.(); }}>{fresh ? "Cancel" : "Undo"}</button>
        </div>}
        {!fresh && university !== "*" && list.length === 0 && <p className="note">An empty list asks for no documents at all (it does not fall back to the default).</p>}
        {error && <p className="error" role="alert">{error}</p>}
      </div>
    </section>
  );
}
