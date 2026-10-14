import Link from "next/link";
import type { Metadata } from "next";
import { AlertTriangle } from "lucide-react";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { istDay, relative, when } from "@/lib/format";

export const metadata: Metadata = { title: "Home" };

type Home = {
  handoffs_today: { sales: number; nurture: number };
  unassigned: { count: number; oldest: string | null };
  sla_month: { met: number; breached: number };
  enrolled_month: number;
  to_verify: number;
  pool: number;
  funnel: { stage: string; n: number }[];
  handoffs_14d: { day: string; sales: number; nurture: number }[];
  sync: { last_batch_at: string | null; queued: number; failed: number; inbox_errors: number; last_received_at: string | null };
};

type TeamRow = { user: { user_id: string; full_name: string | null; role: string; is_active: boolean; monthly_cap: number; away_until: string | null; is_test_user: boolean };
  load: { month: number; open: number; day: number }; working_now: boolean; enrolled_month: number; calls_today: number; leave: { from_day: string; to_day: string }[] };

/** The Admin's home (spec B12.1): what needs attention now, then the month. */
export default async function WorkspaceHome() {
  await requireUser("workspace", "/w");
  let h: Home;
  let team: TeamRow[];
  try {
    [h, team] = await Promise.all([rpc<Home>("admin_home"), rpc<TeamRow[]>("team")]);
  } catch (e) {
    return <Page title="Home"><SetupError error={e} /></Page>;
  }
  const slaTotal = h.sla_month.met + h.sla_month.breached;
  const slaPct = slaTotal ? Math.round((h.sla_month.met / slaTotal) * 100) : null;
  const max = Math.max(1, ...h.funnel.map((f) => f.n));
  const dayMax = Math.max(1, ...h.handoffs_14d.map((d) => d.sales + d.nurture));
  const counsellors = team.filter((t) => ["counsellor", "sales_head"].includes(t.user.role) && t.user.is_active);
  return (
    <Page title="Home">
      {h.unassigned.count > 0 && (
        <div className="banner danger" role="alert">
          <AlertTriangle className="icon" aria-hidden />
          <div className="grow"><b>{h.unassigned.count} sales {h.unassigned.count === 1 ? "lead is" : "leads are"} waiting unassigned</b>, the oldest since {when(h.unassigned.oldest)}.</div>
          <Link className="btn ghost sm" href="/w/allocation?tab=queues">Open queues</Link>
        </div>
      )}
      {h.sync.failed > 0 || h.sync.inbox_errors > 0 ? (
        <div className="banner">
          <AlertTriangle className="icon" aria-hidden />
          <div className="grow">The link with the master lead table needs attention: {h.sync.failed} changes refused or failed this week, {h.sync.inbox_errors} incoming events with errors.</div>
          <Link className="btn ghost sm" href="/w/connectors">Connectors</Link>
        </div>
      ) : null}
      <div className="grid g4">
        <div className="stat"><span className="small muted">Hand-offs today</span><b>{h.handoffs_today.sales + h.handoffs_today.nurture}</b><span className="delta">{h.handoffs_today.sales} sales · {h.handoffs_today.nurture} nurture</span></div>
        <div className="stat"><span className="small muted">Unassigned now</span><b>{h.unassigned.count}</b>{h.unassigned.oldest && <span className="delta down">Oldest {relative(h.unassigned.oldest)}</span>}</div>
        <div className="stat"><span className="small muted">First-contact SLA this month</span><b>{slaPct === null ? "—" : `${slaPct}%`}</b><span className="delta">{h.sla_month.breached} breached</span></div>
        <div className="stat"><span className="small muted">Enrolled this month</span><b>{h.enrolled_month}</b><span className="delta">{h.to_verify} to verify</span></div>
      </div>
      <div className="grid g-lead">
        <section className="card pad stack">
          <h2>Sales funnel</h2>
          {h.funnel.map((f) => (
            <div key={f.stage} className="funnel-row">
              <span className="ellipsis">{f.stage}</span>
              <div className="bar-track"><div className={`bar-fill${f.stage === "Lost" ? " amber" : ""}`} style={{ width: `${(f.n / max) * 100}%` }} /></div>
              <span className="num right">{f.n}</span>
            </div>
          ))}
        </section>
        <section className="card pad stack">
          <h2>Hand-offs, last 14 days</h2>
          <svg className="chart" viewBox="0 0 280 120" role="img" aria-label="Hand-offs per day, sales and nurture">
            {h.handoffs_14d.map((d, i) => {
              const x = 6 + i * 19.5;
              const hs = (d.sales / dayMax) * 96;
              const hn = (d.nurture / dayMax) * 96;
              return (
                <g key={d.day}>
                  <rect x={x} y={104 - hs - hn} width={13} height={hn} fill="var(--amber)" rx={2}><title>{`${d.day}: ${d.nurture} nurture`}</title></rect>
                  <rect x={x} y={104 - hs} width={13} height={hs} fill="var(--primary)" rx={2}><title>{`${d.day}: ${d.sales} sales`}</title></rect>
                  {i % 3 === 0 && <text x={x} y={117}>{d.day.slice(8)}</text>}
                </g>
              );
            })}
          </svg>
          <div className="row small"><span className="chip soft">■ Sales</span><span className="chip warm">■ Nurture</span><span className="muted">Nurture pool now: {h.pool}</span></div>
          <div className="divider" />
          <div className="small muted">Last batch to the master lead table {when(h.sync.last_batch_at)} · {h.sync.queued} changes waiting · last event received {when(h.sync.last_received_at)}</div>
        </section>
      </div>
      <section className="stack">
        <h2>Team today</h2>
        <div className="table-wrap">
          <table>
            <thead><tr><th>Counsellor</th><th>Status</th><th className="right">Open leads</th><th className="right">This month / cap</th><th className="right">Calls today</th><th className="right">Enrolled this month</th></tr></thead>
            <tbody>
              {counsellors.length === 0 && <tr><td colSpan={6} className="muted">No counsellors yet. Add them under Teams.</td></tr>}
              {counsellors.map((t) => (
                <tr key={t.user.user_id}>
                  <td><b>{t.user.full_name}</b>{t.user.is_test_user && <span className="chip line"> Test</span>}</td>
                  <td>{t.leave.some((l) => l.from_day <= istDay(new Date())) ? <span className="chip risk">On leave</span> : t.user.away_until && new Date(t.user.away_until) > new Date() ? <span className="chip risk">Away</span> : t.working_now ? <span className="chip ok">Working</span> : <span className="chip line">Off</span>}</td>
                  <td className="right num">{t.load.open}</td>
                  <td className="right num">{t.load.month} / {t.user.monthly_cap}</td>
                  <td className="right num">{t.calls_today}</td>
                  <td className="right num">{t.enrolled_month}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </Page>
  );
}
