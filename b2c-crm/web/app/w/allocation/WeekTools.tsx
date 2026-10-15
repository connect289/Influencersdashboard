"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, Trash2, Upload } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { parseHolidays } from "@/lib/holidays";
import { breaksSave, holidaysImport } from "../admin-actions";

export type Break = { id: number; user_id: string | null; isodow: number | null; start: string; end: string; label: string };
const DOW = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** Breaks and lunch (spec B7.1): during a break only hot leads go to the person. Saving replaces the whole list. */
export function BreaksEditor({ breaks, people, admin }: { breaks: Break[]; people: { user_id: string; name: string }[]; admin: boolean }) {
  const router = useRouter();
  const initial = () => breaks.map((b) => ({ user_id: b.user_id ?? "", isodow: b.isodow ? String(b.isodow) : "", start: b.start.slice(0, 5), end: b.end.slice(0, 5), label: b.label }));
  const [rows, setRows] = useState(initial);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const set = (i: number, p: Partial<(typeof rows)[number]>) => setRows(rows.map((r, j) => (j === i ? { ...r, ...p } : r)));
  const dirty = JSON.stringify(rows) !== JSON.stringify(initial());
  const save = () => start(async () => {
    const r = await breaksSave(rows.map((x) => ({ user_id: x.user_id || null, isodow: x.isodow ? Number(x.isodow) : null, start: x.start, end: x.end, label: x.label })));
    if (!r.ok) return setError(r.error);
    setError(null);
    toast.success(r.notice ?? "Saved.");
    router.refresh();
  });
  const who = (id: string | null) => (id ? people.find((p) => p.user_id === id)?.name ?? "—" : "Everyone");
  if (!admin) {
    return (
      <section className="panel"><header><h3>Breaks and lunch</h3></header><div className="body small">
        {breaks.length === 0 ? <p className="note">None set.</p> : breaks.map((b) => <div key={b.id}>{b.label}: {who(b.user_id)}, {b.isodow ? DOW[b.isodow - 1] : "every day"} {b.start.slice(0, 5)}–{b.end.slice(0, 5)}</div>)}
      </div></section>
    );
  }
  return (
    <section className="panel">
      <header><h3>Breaks and lunch</h3><span className="small muted">only hot leads during a break</span></header>
      <div className="body stack" style={{ gap: 8 }}>
        {rows.length === 0 && <p className="note">No breaks: everyone takes leads all through their hours.</p>}
        {rows.map((r, i) => (
          <div key={i} className="row wrap" style={{ gap: 6 }}>
            <input className="input" style={{ maxWidth: 140 }} value={r.label} onChange={(e) => set(i, { label: e.target.value })} placeholder="Lunch" aria-label="Label" maxLength={40} />
            <select className="input" style={{ width: "auto" }} value={r.user_id} onChange={(e) => set(i, { user_id: e.target.value })} aria-label="Who">
              <option value="">Everyone</option>{people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
            </select>
            <select className="input" style={{ width: "auto" }} value={r.isodow} onChange={(e) => set(i, { isodow: e.target.value })} aria-label="Day">
              <option value="">Every day</option>{DOW.map((d, k) => <option key={d} value={k + 1}>{d}</option>)}
            </select>
            <input className="input" type="time" style={{ width: "auto" }} value={r.start} onChange={(e) => set(i, { start: e.target.value })} aria-label="From" />
            <input className="input" type="time" style={{ width: "auto" }} value={r.end} onChange={(e) => set(i, { end: e.target.value })} aria-label="To" />
            <button type="button" className="btn quiet sm" onClick={() => setRows(rows.filter((_, j) => j !== i))} aria-label="Remove"><Trash2 className="icon s" aria-hidden /></button>
          </div>
        ))}
        <div className="row wrap">
          <button type="button" className="btn quiet sm" onClick={() => setRows([...rows, { user_id: "", isodow: "", start: "13:30", end: "14:15", label: "Lunch" }])}><Plus className="icon s" aria-hidden />Add a break</button>
          {dirty && <>
            <button type="button" className="btn primary sm" disabled={busy || rows.some((r) => !r.start || !r.end || r.end <= r.start)} onClick={save}>{busy ? "Saving…" : "Save breaks"}</button>
            <button type="button" className="btn quiet sm" onClick={() => { setRows(initial()); setError(null); }}>Undo</button>
          </>}
        </div>
        {error && <p className="error" role="alert">{error}</p>}
      </div>
    </section>
  );
}

/** Holidays from a pasted list: "YYYY-MM-DD, name, national|company" a line. An existing date is updated. */
export function HolidayImport() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const parsed = parseHolidays(text);
  const save = () => start(async () => {
    const r = await holidaysImport(parsed.rows);
    if (!r.ok) return setError(r.error);
    toast.success(r.notice ?? "Saved.");
    setOpen(false); setText("");
    router.refresh();
  });
  return (
    <>
      <button type="button" className="btn ghost sm" style={{ justifySelf: "start" }} onClick={() => setOpen(true)}><Upload className="icon s" aria-hidden />Import holidays</button>
      {open && (
        <Sheet title="Import holidays" onClose={() => setOpen(false)}>
          <p className="note">Paste one holiday a line: <span className="mono">2026-11-08, Diwali, national</span>. The kind is national or company (company if left out). A CSV with a header line works too. At most 200 at a time.</p>
          <textarea className="input mono" rows={10} value={text} onChange={(e) => setText(e.target.value)} aria-label="Holidays" spellCheck={false} />
          {text.trim() && <p className="small">{parsed.rows.length} holidays read{parsed.errors.length ? `; ${parsed.errors.length} lines need fixing` : ""}.</p>}
          {parsed.errors.length > 0 && <ul className="small error" style={{ margin: 0, paddingLeft: 18 }}>{parsed.errors.slice(0, 8).map((e) => <li key={e}>{e}</li>)}</ul>}
          {error && <p className="error" role="alert">{error}</p>}
          <button type="button" className="btn primary block" disabled={busy || !parsed.rows.length || parsed.errors.length > 0 || parsed.rows.length > 200} onClick={save}>{busy ? "Saving…" : `Save ${parsed.rows.length} holidays`}</button>
        </Sheet>
      )}
    </>
  );
}
