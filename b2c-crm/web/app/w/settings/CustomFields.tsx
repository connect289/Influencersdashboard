"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ArrowDown, ArrowUp, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { customFieldsSave } from "../admin-actions";

export type CustomField = { key: string; label: string; type: "text" | "number" | "date" | "select" | "yes_no"; options?: string[] };
const TYPE_LABEL: Record<CustomField["type"], string> = { text: "Text", number: "Number", date: "Date", select: "One of a list", yes_no: "Yes or no" };
const keyOf = (label: string) => label.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").replace(/^(\d)/, "f_$1").slice(0, 31);

/** Extra profile fields on the lead screen (spec B8.3), defined by the Admin; values keep their change history on the lead. */
export function CustomFields({ fields: initial }: { fields: CustomField[] }) {
  const router = useRouter();
  const [fields, setFields] = useState<(CustomField & { optionsText?: string; saved?: boolean })[]>(
    initial.map((f) => ({ ...f, optionsText: (f.options ?? []).join(", "), saved: true })));
  const [why, setWhy] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const set = (i: number, p: Partial<(typeof fields)[number]>) => setFields(fields.map((f, j) => (j === i ? { ...f, ...p } : f)));
  const move = (i: number, d: -1 | 1) => { const n = [...fields]; const j = i + d; if (j < 0 || j >= n.length) return; [n[i], n[j]] = [n[j]!, n[i]!]; setFields(n); };
  const out = fields.map(({ key, label, type, optionsText }) => ({ key, label, type, ...(type === "select" ? { options: (optionsText ?? "").split(",").map((x) => x.trim()).filter(Boolean) } : {}) }));
  const dirty = JSON.stringify(out) !== JSON.stringify(initial.map(({ key, label, type, options }) => ({ key, label, type, ...(type === "select" ? { options } : {}) })));
  const save = () => start(async () => {
    const r = await customFieldsSave(out, why);
    if (!r.ok) return setError(r.error);
    setError(null); setWhy("");
    toast.success("Saved as a new version.");
    router.refresh();
  });
  return (
    <div className="stack">
      <p className="note">These appear on every lead&apos;s profile. The key is fixed once saved (values are stored under it); removing a field hides it but keeps the values already entered. At most 30.</p>
      <div className="table-wrap"><table>
        <thead><tr><th>Label</th><th>Key</th><th>Type</th><th>Choices (comma-separated)</th><th /></tr></thead>
        <tbody>
          {fields.length === 0 && <tr><td colSpan={5} className="muted">No custom fields yet.</td></tr>}
          {fields.map((f, i) => (
            <tr key={i}>
              <td><input className="input" value={f.label} maxLength={60} aria-label="Label"
                onChange={(e) => set(i, { label: e.target.value, ...(f.saved ? {} : { key: keyOf(e.target.value) }) })} /></td>
              <td><input className="input mono" value={f.key} maxLength={31} aria-label="Key" readOnly={f.saved}
                onChange={(e) => set(i, { key: e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, "_") })} /></td>
              <td><select className="input" value={f.type} aria-label="Type" onChange={(e) => set(i, { type: e.target.value as CustomField["type"] })}>
                {Object.entries(TYPE_LABEL).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></td>
              <td>{f.type === "select" ? <input className="input" value={f.optionsText ?? ""} aria-label="Choices" onChange={(e) => set(i, { optionsText: e.target.value })} placeholder="e.g. Self, Parent, Employer" /> : <span className="muted">—</span>}</td>
              <td className="row" style={{ gap: 2 }}>
                <button type="button" className="btn quiet sm" disabled={i === 0} onClick={() => move(i, -1)} aria-label="Move up"><ArrowUp className="icon s" aria-hidden /></button>
                <button type="button" className="btn quiet sm" disabled={i === fields.length - 1} onClick={() => move(i, 1)} aria-label="Move down"><ArrowDown className="icon s" aria-hidden /></button>
                <button type="button" className="btn quiet sm" onClick={() => setFields(fields.filter((_, j) => j !== i))} aria-label="Remove"><Trash2 className="icon s" aria-hidden /></button>
              </td>
            </tr>
          ))}
        </tbody>
      </table></div>
      {fields.length < 30 && <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => setFields([...fields, { key: "", label: "", type: "text" }])}><Plus className="icon s" aria-hidden />Add a field</button>}
      {dirty && <div className="row wrap">
        <input className="input grow" value={why} onChange={(e) => setWhy(e.target.value)} placeholder="Reason for the change (required)" aria-label="Reason" maxLength={300} />
        <button type="button" className="btn primary sm" disabled={busy || why.trim().length < 3} onClick={save}>{busy ? "Saving…" : "Save fields"}</button>
        <button type="button" className="btn quiet sm" onClick={() => { setFields(initial.map((f) => ({ ...f, optionsText: (f.options ?? []).join(", "), saved: true }))); setError(null); }}>Undo</button>
      </div>}
      {error && <p className="error" role="alert">{error}</p>}
    </div>
  );
}
