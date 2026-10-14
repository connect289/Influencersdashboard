import { rpc } from "@/lib/data";
import { inr, when } from "@/lib/format";
import { TargetEditor } from "./TargetEditor";

type Six = { calls: number; connected: number; counselled: number; applications: number; enrollments: number; commission: number };
type Board = { month: string; rows: { user_id: string | null; name: string; me: boolean; actual: Six; target: (Partial<Six> & { source?: string }) | null }[] };
type Activity = { rows: { user_id: string; name: string; role: string; calls: number; connected: number; whatsapp_sent: number; email_sent: number; overdue_tasks: number;
  untouched: number; sla_breaches: number; unlogged_calls: number; first_contact_median_min: number | null; away_until: string | null }[] };
type Capacity = { rows: { user_id: string; name: string; cap: number | null; assigned: number; open: number; enrollments: number }[]; hiring: boolean; capacity_alert_pct: number; hiring_trigger_enrollments: number };

const COLS: [keyof Six, string][] = [["enrollments", "Enrolments"], ["applications", "Applications"], ["counselled", "Counselled"], ["connected", "Connected"], ["calls", "Calls"], ["commission", "Commission"]];

/** Team performance (spec B11.3): the month against target, the activity monitor and capacity. */
export async function TeamView({ canSetTargets }: { canSetTargets: boolean }) {
  const [board, act, cap] = await Promise.all([rpc<Board>("leaderboard", { p_month: null }), rpc<Activity>("activity_monitor", { p: {} }), rpc<Capacity>("capacity")]);
  const ist = new Date(Date.now() + 5.5 * 3600e3);
  const dayShare = ist.getUTCDate() / new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth() + 1, 0)).getUTCDate();
  return (
    <div className="stack">
      {cap.hiring && <div className="banner">The team is near capacity (assignments at {cap.capacity_alert_pct}% of caps, or {cap.hiring_trigger_enrollments}+ enrolments a head). Time to plan hiring.</div>}
      <section className="card pad stack">
        <h2>This month against target</h2>
        <p className="note">The marker on each bar is where the month is today ({Math.round(dayShare * 100)}%); a bar short of it is behind pace.</p>
        {board.rows.length === 0 ? <p className="note">No counsellors yet.</p> : (
          <div className="table-wrap"><table>
            <thead><tr><th>Counsellor</th>{COLS.map(([k, l]) => <th key={k} className="right">{l}</th>)}{canSetTargets && <th />}</tr></thead>
            <tbody>{board.rows.map((r, i) => (
              <tr key={r.user_id ?? i}><td>{r.name}</td>
                {COLS.map(([k]) => {
                  const a = Number(r.actual[k] ?? 0), t = r.target?.[k] === undefined || r.target?.[k] === null ? null : Number(r.target[k]);
                  return (
                    <td key={k} className="right" style={{ minWidth: 96 }}>
                      <span className="num">{k === "commission" ? inr(a) : a}</span>{t ? <span className="small muted"> / {k === "commission" ? inr(t) : t}</span> : null}
                      {t ? <div className="bar-track pace" style={{ ["--pace" as string]: `${dayShare * 100}%`, marginTop: 4 }}><div className={`bar-fill ${a / t < dayShare ? "amber" : ""}`} style={{ width: `${Math.min(100, (a / t) * 100)}%` }} /></div> : null}
                    </td>
                  );
                })}
                {canSetTargets && <td>{r.user_id && <TargetEditor user={r.user_id} name={r.name} month={board.month} target={r.target as Record<string, unknown> | null} />}</td>}
              </tr>
            ))}</tbody>
          </table></div>
        )}
      </section>
      <section className="card pad stack">
        <h2>Activity this month</h2>
        <div className="table-wrap"><table>
          <thead><tr><th>Person</th><th className="right">Calls</th><th className="right">Connected</th><th className="right">WhatsApp</th><th className="right">Email</th>
            <th className="right">Median first contact</th><th className="right">SLA breaches</th><th className="right">Overdue tasks</th><th className="right">Untouched</th><th className="right">Unlogged calls</th></tr></thead>
          <tbody>{act.rows.map((r) => (
            <tr key={r.user_id}><td>{r.name}{r.away_until && new Date(r.away_until) > new Date() ? <div className="small muted">away till {when(r.away_until)}</div> : null}</td>
              <td className="right num">{r.calls}</td><td className="right num">{r.connected}</td><td className="right num">{r.whatsapp_sent}</td><td className="right num">{r.email_sent}</td>
              <td className="right num">{r.first_contact_median_min === null ? "–" : `${Math.round(r.first_contact_median_min)} min`}</td>
              <td className="right num">{r.sla_breaches ? <span className="chip breach">{r.sla_breaches}</span> : 0}</td>
              <td className="right num">{r.overdue_tasks ? <span className="chip risk">{r.overdue_tasks}</span> : 0}</td>
              <td className="right num">{r.untouched}</td><td className="right num">{r.unlogged_calls}</td></tr>
          ))}</tbody>
        </table></div>
      </section>
      <section className="card pad stack">
        <h2>Capacity</h2>
        {cap.rows.length === 0 ? <p className="note">Nobody takes leads yet.</p> : (
          <div className="table-wrap"><table>
            <thead><tr><th>Person</th><th className="right">Assigned this month</th><th className="right">Monthly cap</th><th style={{ width: "30%" }}>Use</th><th className="right">Open leads</th><th className="right">Enrolments</th></tr></thead>
            <tbody>{cap.rows.map((r) => {
              const pct = r.cap ? Math.round((r.assigned / r.cap) * 100) : null;
              return (
                <tr key={r.user_id}><td>{r.name}</td><td className="right num">{r.assigned}</td><td className="right num">{r.cap ?? "–"}</td>
                  <td>{pct !== null && <div className="row" style={{ gap: 6 }}><div className="bar-track grow"><div className={`bar-fill ${pct >= cap.capacity_alert_pct ? "amber" : ""}`} style={{ width: `${Math.min(100, pct)}%` }} /></div><span className="small num">{pct}%</span></div>}</td>
                  <td className="right num">{r.open}</td><td className="right num">{r.enrollments}</td></tr>
              );
            })}</tbody>
          </table></div>
        )}
      </section>
    </div>
  );
}
