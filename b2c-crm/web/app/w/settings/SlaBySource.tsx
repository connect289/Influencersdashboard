"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { settingSave } from "../actions";

type Temp = "hot" | "warm" | "cold";
type Minutes = Partial<Record<Temp, number>>;
export type SlaSetting = Minutes & { by_source?: Record<string, Minutes> } & Record<string, unknown>;
const TEMPS: [Temp, string][] = [["hot", "Hot"], ["warm", "Warm"], ["cold", "Cold"]];

/** First-contact minutes by source as well as by temperature (spec B8.7): a source's own figure wins; empty uses the default. */
export function SlaBySource({ value }: { value: SlaSetting }) {
  const router = useRouter();
  const start0 = () => Object.entries(value.by_source ?? {}).map(([source, m]) => ({ source, hot: m.hot ?? null, warm: m.warm ?? null, cold: m.cold ?? null }));
  const [rows, setRows] = useState(start0);
  const [why, setWhy] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const set = (i: number, p: Partial<(typeof rows)[number]>) => setRows(rows.map((r, j) => (j === i ? { ...r, ...p } : r)));
  const bySource = Object.fromEntries(rows.filter((r) => r.source.trim()).map((r) => [r.source.trim(), Object.fromEntries(TEMPS.filter(([t]) => r[t] !== null).map(([t]) => [t, r[t]]))]));
  const dirty = JSON.stringify(bySource) !== JSON.stringify(value.by_source ?? {});
  const dupes = new Set(rows.map((r) => r.source.trim())).size !== rows.length;
  const save = () => start(async () => {
    const r = await settingSave("sla_minutes", { ...value, by_source: bySource }, why);
    if (!r.ok) return setError(r.error);
    setError(null); setWhy("");
    toast.success("Saved as a new version.");
    router.refresh();
  });
  return (
    <section className="panel">
      <header><h3>First-contact SLA</h3><span className="small muted">working minutes</span></header>
      <div className="body stack" style={{ gap: 8 }}>
        <p className="small">Default by temperature: hot {value.hot ?? "—"}, warm {value.warm ?? "—"}, cold {value.cold ?? "—"} minutes (change these under Settings → sla minutes).</p>
        <p className="note">A source listed here uses its own minutes; leave a box empty to use the default for that temperature. The source is the lead&apos;s source exactly as on the Leads page (for example website or meta_ads). New leads use the change; leads already waiting keep their deadline.</p>
        <div className="table-wrap"><table>
          <thead><tr><th>Source</th>{TEMPS.map(([, l]) => <th key={l} className="right">{l}</th>)}<th /></tr></thead>
          <tbody>
            {rows.length === 0 && <tr><td colSpan={5} className="muted">Every source uses the default.</td></tr>}
            {rows.map((r, i) => (
              <tr key={i}>
                <td><input className="input mono" value={r.source} onChange={(e) => set(i, { source: e.target.value })} maxLength={60} aria-label="Source" /></td>
                {TEMPS.map(([t, l]) => <td key={t} className="right"><input className="input num" type="number" min={1} max={10080} style={{ maxWidth: 110 }} aria-label={`${l} minutes`}
                  value={r[t] ?? ""} placeholder={String(value[t] ?? "")} onChange={(e) => set(i, { [t]: e.target.value === "" ? null : Number(e.target.value) })} /></td>)}
                <td><button type="button" className="btn quiet sm" onClick={() => setRows(rows.filter((_, j) => j !== i))} aria-label="Remove"><Trash2 className="icon s" aria-hidden /></button></td>
              </tr>
            ))}
          </tbody>
        </table></div>
        <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => setRows([...rows, { source: "", hot: null, warm: null, cold: null }])}><Plus className="icon s" aria-hidden />Add a source</button>
        {dirty && <div className="row wrap">
          <input className="input grow" value={why} onChange={(e) => setWhy(e.target.value)} placeholder="Reason for the change (required)" aria-label="Reason" maxLength={300} />
          <button type="button" className="btn primary sm" disabled={busy || why.trim().length < 3 || dupes} onClick={save}>{busy ? "Saving…" : "Save"}</button>
          <button type="button" className="btn quiet sm" onClick={() => { setRows(start0()); setError(null); }}>Undo</button>
        </div>}
        {dupes && <p className="error">A source is listed twice.</p>}
        {error && <p className="error" role="alert">{error}</p>}
      </div>
    </section>
  );
}

/** Team and revenue on student_leads (spec B3.3): off until the B2B CRM's write API accepts the fields. */
export function B2bWrites({ value }: { value: { team_and_revenue?: boolean } & Record<string, unknown> }) {
  const router = useRouter();
  const [why, setWhy] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const on = !!value.team_and_revenue;
  const flip = () => start(async () => {
    const r = await settingSave("b2b_writes", { ...value, team_and_revenue: !on }, why);
    if (!r.ok) return setError(r.error);
    setError(null); setWhy("");
    toast.success(on ? "Switched off." : "Switched on: the next assignment and commission change go to the master lead table.");
    router.refresh();
  });
  return (
    <section className="panel">
      <header><h3>Team and revenue on the master lead table</h3><span className={`chip ${on ? "ok" : "line"}`}>{on ? "On" : "Off"}</span></header>
      <div className="body stack" style={{ gap: 8 }}>
        <p className="small">When on, each assignment writes the counsellor&apos;s team (team_id) and each commission change writes expected and realised net revenue to the lead in the master lead table.</p>
        <div className="banner">Keep this off until the B2B CRM confirms its write API accepts team_id, expected_net_revenue_inr and realised_net_revenue_inr. A field it refuses holds back the other changes in the same update.</div>
        <div className="row wrap">
          <input className="input grow" value={why} onChange={(e) => setWhy(e.target.value)} placeholder="Reason (required)" aria-label="Reason" maxLength={300} />
          <button type="button" className={`btn ${on ? "ghost" : "primary"} sm`} disabled={busy || why.trim().length < 3} onClick={flip}>{busy ? "Saving…" : on ? "Switch off" : "Switch on"}</button>
        </div>
        {error && <p className="error" role="alert">{error}</p>}
      </div>
    </section>
  );
}
