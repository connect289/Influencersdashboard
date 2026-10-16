import type { Metadata } from "next";
import { Page, SetupError } from "@/components/shell/Page";
import { CommissionLines } from "@/components/money/CommissionLines";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { date, inr } from "@/lib/format";
import type { CommissionLine } from "@/lib/money";

export const metadata: Metadata = { title: "My money" };

type Mine = {
  name: string | null; month: string; year_to_date: number;
  tiles: { provisional: number; confirmed: number; due: number; settled: number; needs_rate: number };
  lines: CommissionLine[];
  by_university: { university: string; amount: number; enrollments: number }[];
  by_month: { month: string; amount: number; settled: number }[];
  target: { commission: number | null; enrollments: number | null; enrollments_done: number } | null;
  statements: { run_id: number; period: string; approved_at: string; amount: number }[];
};

/** My money (spec B11.2): what my enrolments owe, line by line, with the partners considered and the rate; my statements. */
export default async function MyMoneyPage() {
  await requireUser("sales", "/s/money");
  let m: Mine;
  try {
    m = await rpc<Mine>("my_commission", { p: {} });
  } catch (e) {
    return <Page title="My money"><SetupError error={e} /></Page>;
  }
  const monthTotal = m.tiles.provisional + m.tiles.confirmed + m.tiles.due + m.tiles.settled;
  const max = Math.max(1, ...m.by_month.map((x) => Number(x.amount)));
  return (
    <Page title="My money" sub="What your enrolments owe Eduwit: the commission partners pay for each programme, at the highest partner rate.">
      <div className="stack">
        <div className="grid g4">
          <div className="stat"><span className="small muted">This month</span><b>{inr(monthTotal)}</b>
            <span className="delta">{m.target?.commission ? `${Math.round((monthTotal / m.target.commission) * 100)}% of ${inr(m.target.commission)} target` : "no commission target"}</span></div>
          <div className="stat"><span className="small muted">Provisional</span><b>{inr(m.tiles.provisional)}</b><span className="delta">refund window still open</span></div>
          <div className="stat"><span className="small muted">Due in the next run</span><b>{inr(m.tiles.due + m.tiles.confirmed)}</b><span className="delta">{inr(m.tiles.due)} due now</span></div>
          <div className="stat"><span className="small muted">This financial year</span><b>{inr(m.year_to_date)}</b><span className="delta">{inr(m.tiles.settled)} settled this month</span></div>
        </div>
        {m.tiles.needs_rate > 0 && <div className="banner">{m.tiles.needs_rate} of your enrolments wait for a rate from the Admin; they are counted once it is set.</div>}
        <div className="grid g2">
          <section className="card pad stack">
            <h2>Last 12 months</h2>
            <div className="hbars" role="list">
              {m.by_month.map((x) => (
                <div key={x.month} className="hbar" role="listitem">
                  <span className="small mono">{x.month.slice(0, 7)}</span>
                  <div className="hbar-track"><div className="hbar-fill" style={{ width: `${(Math.max(0, Number(x.amount)) / max) * 100}%` }} title={`${inr(x.amount)}, ${inr(x.settled)} settled`} /></div>
                  <span className="small right num">{inr(x.amount)}</span>
                </div>
              ))}
            </div>
          </section>
          <section className="card pad stack">
            <h2>Statements</h2>
            {m.statements.length === 0 ? <p className="note">No approved runs yet. Each approved run gives you a statement here.</p> : (
              <div className="table-wrap"><table>
                <thead><tr><th>Run</th><th>Approved</th><th className="right">Settled</th><th /></tr></thead>
                <tbody>{m.statements.map((s) => <tr key={s.run_id}><td>{s.period.slice(0, 7)}</td><td>{date(s.approved_at)}</td><td className="right num">{inr(s.amount)}</td>
                  <td><a className="btn quiet sm" href={`/s/money/statement/${s.run_id}`} target="_blank" rel="noopener">PDF</a></td></tr>)}</tbody>
              </table></div>
            )}
            {m.by_university.length > 0 && <>
              <h3>By university, this year</h3>
              <div className="table-wrap"><table>
                <tbody>{m.by_university.map((u) => <tr key={u.university}><td>{u.university}</td><td className="right num">{u.enrollments}</td><td className="right num">{inr(u.amount)}</td></tr>)}</tbody>
              </table></div>
            </>}
          </section>
        </div>
        <section className="stack">
          <h2>Lines</h2>
          <p className="note">Open the rate on a line to see every partner that offers the programme, its rate, and which one was used.</p>
          <CommissionLines lines={m.lines} leadHref={(id) => `/s/leads/${id}`} />
        </section>
      </div>
    </Page>
  );
}
