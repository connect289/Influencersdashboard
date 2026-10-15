export type CapacityData = {
  rows: { user_id: string; name: string | null; cap: number | null; assigned: number; open: number; enrollments: number }[];
  today: { handed_off: number; assigned: number; waiting: number };
  capacity_alert_pct: number;
  hiring_trigger_enrollments: number;
  hiring: boolean;
};

/** Capacity (spec B7.4, B7.5): this month's leads against each cap, open leads, enrolments, today's intake and the hiring flag. */
export function Capacity({ c }: { c: CapacityData }) {
  const total = c.rows.reduce((a, r) => a + Number(r.assigned), 0);
  const caps = c.rows.reduce((a, r) => a + Number(r.cap ?? 0), 0);
  const teamPct = caps ? Math.round((total / caps) * 100) : null;
  return (
    <div className="stack">
      {c.hiring && <div className="banner" role="alert">Time to plan hiring: the team is at {c.capacity_alert_pct}% of its caps, or counsellors average {c.hiring_trigger_enrollments}+ enrolments this month (Eduwit&apos;s hiring rule).</div>}
      <div className="grid g4">
        <div className="stat"><span>Handed over today</span><b>{c.today.handed_off}</b><span className="delta">test leads left out</span></div>
        <div className="stat"><span>Assigned today</span><b>{c.today.assigned}</b></div>
        <div className="stat"><span>Waiting for a counsellor</span><b>{c.today.waiting}</b>{c.today.waiting > 0 && <span className="delta down">see Queues</span>}</div>
        <div className="stat"><span>Team this month</span><b>{teamPct === null ? "—" : `${teamPct}%`}</b><span className="delta">{total} of {caps} leads</span></div>
      </div>
      <div className="table-wrap"><table>
        <thead><tr><th>Counsellor</th><th className="right">This month / cap</th><th style={{ minWidth: 180 }}>Of cap</th><th className="right">Open now</th><th className="right">Enrolled this month</th></tr></thead>
        <tbody>
          {c.rows.length === 0 && <tr><td colSpan={5} className="muted">Nobody takes leads yet.</td></tr>}
          {c.rows.map((r) => {
            const pct = r.cap ? Math.round((Number(r.assigned) / Number(r.cap)) * 100) : null;
            return (
              <tr key={r.user_id}>
                <td>{r.name ?? "—"}</td>
                <td className="right num">{r.assigned} / {r.cap ?? "—"}</td>
                <td>{pct !== null ? <div className="row" style={{ gap: 6 }}><div className="bar-track grow"><div className={`bar-fill ${pct >= c.capacity_alert_pct ? "amber" : ""}`} style={{ width: `${Math.min(100, pct)}%` }} /></div><span className="small num">{pct}%</span></div> : <span className="muted small">no cap</span>}</td>
                <td className="right num">{r.open}</td>
                <td className="right num">{r.enrollments}{Number(r.enrollments) >= c.hiring_trigger_enrollments ? <span className="chip warm" style={{ marginLeft: 4 }}>hiring rule</span> : null}</td>
              </tr>
            );
          })}
        </tbody>
      </table></div>
      <p className="note">The Admin is alerted once a month when someone passes {c.capacity_alert_pct}% of their cap, and when the team reaches the hiring trigger. Change both under Settings → allocation (capacity_alert_pct, hiring_trigger_enrollments).</p>
    </div>
  );
}
