"use client";
import { useState, useTransition } from "react";
import { istDay } from "@/lib/format";
import { simulate } from "../actions";

type Result = { leads: number; unassigned: number; by_person: { user_id: string; name: string | null; actual: number; simulated: number }[] };

/** Replays past hand-offs through today's rules, without changing anything (spec B7.6). */
export function Simulation() {
  const today = istDay(new Date());
  const monthStart = today.slice(0, 8) + "01";
  const [from, setFrom] = useState(monthStart);
  const [to, setTo] = useState(today);
  const [res, setRes] = useState<Result | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const run = () => start(async () => {
    const r = await simulate(from, to);
    if (!r.ok) return setError(r.error);
    setError(null);
    setRes(r.data ?? null);
  });
  return (
    <div className="stack">
      <p className="note">Runs the leads handed over in a period through the current rules, calendars and caps, and compares with who actually got them. Test leads are left out. Nothing is changed.</p>
      <div className="row wrap" style={{ alignItems: "flex-end" }}>
        <label className="field"><span>From</span><input className="input" type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} /></label>
        <label className="field"><span>To</span><input className="input" type="date" value={to} min={from} max={today} onChange={(e) => setTo(e.target.value)} /></label>
        <button type="button" className="btn primary" onClick={run} disabled={busy}>{busy ? "Running…" : "Run simulation"}</button>
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      {res && (
        <>
          <div className="grid g3">
            <div className="stat"><span className="small muted">Leads replayed</span><b>{res.leads}</b></div>
            <div className="stat"><span className="small muted">Nobody could take</span><b>{res.unassigned}</b></div>
          </div>
          <div className="table-wrap"><table>
            <thead><tr><th>Person</th><th className="right">Actually got</th><th className="right">Would get now</th><th className="right">Difference</th></tr></thead>
            <tbody>
              {res.by_person.map((p) => (
                <tr key={p.user_id ?? "none"}><td>{p.name ?? "—"}</td><td className="right num">{p.actual}</td><td className="right num">{p.simulated}</td>
                  <td className="right num">{p.simulated - p.actual > 0 ? "+" : ""}{p.simulated - p.actual}</td></tr>
              ))}
            </tbody>
          </table></div>
        </>
      )}
    </div>
  );
}
