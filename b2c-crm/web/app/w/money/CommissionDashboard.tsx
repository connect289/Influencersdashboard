import Link from "next/link";
import { date, inr } from "@/lib/format";
import { LINE_STATUS } from "@/lib/money";

export type CommissionDash = {
  totals: { amount: number; lines: number; enrollments: number };
  by_counsellor: { counsellor_id: string; name: string | null; amount: number; lines: number; by_status: Record<string, number>; enrollment_ids: number[] }[];
  by_status: Record<string, { amount: number; lines: number }>;
  by_month: { month: string; amount: number; lines: number; enrollment_ids: number[] }[];
  runs: { id: number; period: string; status: string; totals: { amount?: number; counsellors?: number; lines?: number } | null; approved_at: string | null; pay_on: string }[];
  next_run: string;
};

const ORDER = ["needs_rate", "provisional", "confirmed", "due", "settled"];
const ids = (xs: number[]) => `/w/enrollments?ids=${[...new Set(xs)].slice(0, 300).join(",")}`;

/** The Admin's commission dashboard (spec B11.3): owed by counsellor, status and month, and the run calendar. Every number opens its enrolments. */
export function CommissionDashboard({ d, test }: { d: CommissionDash; test: boolean }) {
  const statuses = [...ORDER.filter((s) => d.by_status[s]), ...Object.keys(d.by_status).filter((s) => !ORDER.includes(s))];
  const max = Math.max(1, ...d.by_month.map((m) => Number(m.amount)));
  const today = new Date().toISOString().slice(0, 10);
  return (
    <section className="stack">
      <div className="row wrap between">
        <h2>Counsellor commission owed{test && <span className="chip warm" style={{ marginLeft: 6 }}>test</span>}</h2>
        <Link className="btn quiet sm" href={test ? "/w/money?tab=commission" : "/w/money?tab=commission&test=1"}>{test ? "Show real enrolments" : "Show test enrolments"}</Link>
      </div>
      <div className="grid g4">
        <div className="stat"><span>Owed, last 12 months</span><b>{inr(d.totals.amount)}</b><span className="delta">{d.totals.lines} lines · {d.totals.enrollments} enrolments</span></div>
        {statuses.slice(0, 3).map((s) => (
          <div key={s} className="stat"><span>{LINE_STATUS[s]?.label ?? s}</span><b>{inr(d.by_status[s]!.amount)}</b><span className="delta">{d.by_status[s]!.lines} lines</span></div>
        ))}
      </div>
      <div className="grid g2">
        <section className="panel">
          <header><h3>By counsellor</h3></header>
          <div className="table-wrap" style={{ boxShadow: "none" }}><table>
            <thead><tr><th>Counsellor</th>{statuses.map((s) => <th key={s} className="right">{LINE_STATUS[s]?.label ?? s}</th>)}<th className="right">Total</th></tr></thead>
            <tbody>
              {d.by_counsellor.length === 0 && <tr><td colSpan={statuses.length + 2} className="muted">Nothing owed in this period.</td></tr>}
              {d.by_counsellor.map((c) => (
                <tr key={c.counsellor_id}>
                  <td>{c.name ?? "—"}</td>
                  {statuses.map((s) => <td key={s} className="right num">{c.by_status[s] ? inr(c.by_status[s]) : "—"}</td>)}
                  <td className="right num"><Link href={ids(c.enrollment_ids)} title={`${c.enrollment_ids.length} enrolments`}>{inr(c.amount)}</Link></td>
                </tr>
              ))}
            </tbody>
          </table></div>
        </section>
        <section className="panel">
          <header><h3>By month of enrolment</h3></header>
          <div className="body">
            {d.by_month.length === 0 ? <p className="note">No enrolments in the last 12 months.</p> : d.by_month.map((m) => (
              <div key={m.month} className="funnel-row">
                <span>{m.month}</span>
                <div className="bar-track"><div className="bar-fill" style={{ width: `${(Number(m.amount) / max) * 100}%` }} /></div>
                <Link className="num right" href={ids(m.enrollment_ids)} title={`${m.lines} lines`}>{inr(m.amount)}</Link>
              </div>
            ))}
          </div>
        </section>
      </div>
      <section className="panel">
        <header><h3>Run calendar</h3><span className="small muted">next run prepared on {date(d.next_run)}</span></header>
        <div className="table-wrap" style={{ boxShadow: "none" }}><table>
          <thead><tr><th>Month</th><th>Status</th><th className="right">Counsellors</th><th className="right">Amount</th><th>Pay on</th><th /></tr></thead>
          <tbody>
            {d.runs.length === 0 && <tr><td colSpan={6} className="muted">No runs yet.</td></tr>}
            {d.runs.map((r) => (
              <tr key={r.id}>
                <td>{r.period.slice(0, 7)}</td>
                <td><span className={`chip ${r.status === "approved" || r.status === "paid" ? "ok" : r.status === "cancelled" ? "line" : "warm"}`}>{r.status}</span></td>
                <td className="right num">{r.totals?.counsellors ?? 0}</td>
                <td className="right num">{inr(r.totals?.amount)}</td>
                <td className={r.pay_on < today && r.status === "draft" ? "error" : undefined}>{date(r.pay_on)}</td>
                <td><Link className="btn quiet sm" href={`/w/money?tab=runs&run=${r.id}`}>Open</Link></td>
              </tr>
            ))}
          </tbody>
        </table></div>
      </section>
    </section>
  );
}
