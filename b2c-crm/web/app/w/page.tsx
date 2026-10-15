import Link from "next/link";
import type { Metadata } from "next";
import { AlertTriangle } from "lucide-react";
import { Page, SetupError } from "@/components/shell/Page";
import { StageApprovals, type StageRequest } from "@/components/lead/StageApprovals";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { b2bConfig, liveMode } from "@/lib/env";
import { istDay, relative, when } from "@/lib/format";
import { googleSa } from "@/lib/gmail";
import { waConfig } from "@/lib/whatsapp";

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

/** The Admin's home (spec B12.1): what needs attention, four numbers, then the funnel and the team. */
export default async function WorkspaceHome() {
  const me = await requireUser("workspace", "/w");
  let h: Home;
  let team: TeamRow[];
  let health: { overall: "ok" | "warn" | "bad"; checks: { label: string; level: string; detail: string }[] } | null = null;
  try {
    [h, team, health] = await Promise.all([rpc<Home>("admin_home"), rpc<TeamRow[]>("team"),
      me.role === "admin" ? rpc<{ overall: "ok" | "warn" | "bad"; checks: { label: string; level: string; detail: string }[] }>("system_health").catch(() => null) : Promise.resolve(null)]);
  } catch (e) {
    return <Page title="Home"><SetupError error={e} /></Page>;
  }
  const requests = me.role === "admin" ? await rpc<StageRequest[]>("stage_requests_list").catch(() => [] as StageRequest[]) : [];
  const slaTotal = h.sla_month.met + h.sla_month.breached;
  const slaPct = slaTotal ? Math.round((h.sla_month.met / slaTotal) * 100) : null;
  const max = Math.max(1, ...h.funnel.map((f) => f.n));
  const dayMax = Math.max(1, ...h.handoffs_14d.map((d) => d.sales + d.nurture));
  const counsellors = team.filter((t) => ["counsellor", "sales_head"].includes(t.user.role) && t.user.is_active);
  const attention = [
    health?.overall === "bad" && { tone: "danger", text: <><b>Something is not running:</b> {health.checks.filter((c) => c.level === "bad").map((c) => `${c.label.toLowerCase()} (${c.detail})`).join("; ")}.</>, href: "/w/settings?tab=health", cta: "System health" },
    h.unassigned.count > 0 && { tone: "danger", text: <><b>{h.unassigned.count} sales {h.unassigned.count === 1 ? "lead is" : "leads are"} waiting unassigned</b>, the oldest since {when(h.unassigned.oldest)}.</>, href: "/w/allocation?tab=queues", cta: "Open queues" },
    (h.sync.failed > 0 || h.sync.inbox_errors > 0) && { tone: "", text: <>The link with the master lead table needs attention: {h.sync.failed} changes refused or failed this week, {h.sync.inbox_errors} incoming events with errors.</>, href: "/w/connectors", cta: "Connectors" },
    h.to_verify > 0 && { tone: "info", text: <><b>{h.to_verify} {h.to_verify === 1 ? "enrolment waits" : "enrolments wait"} for your verification.</b></>, href: "/w/enrollments", cta: "Verify" },
  ].filter(Boolean) as { tone: string; text: React.ReactNode; href: string; cta: string }[];

  // the Admin's setup checklist, shown until everything is connected (spec B15: the guide's "setting up, in order")
  const setup: { label: string; done: boolean; href: string; hint: string }[] = me.role === "admin" ? [
    { label: "Email for sign-in codes", done: !!process.env.SMTP_HOST, href: "/w/guide", hint: "SMTP in the site's variables" },
    { label: "Phone alerts", done: !!process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY, href: "/w/connectors", hint: "push keys" },
    { label: "Google Workspace", done: !!googleSa(), href: "/w/connectors", hint: "service account with delegation" },
    { label: "WhatsApp number", done: !!waConfig(), href: "/w/connectors", hint: "Cloud API token and number" },
    { label: "B2B CRM link", done: !!b2bConfig(), href: "/w/connectors", hint: "API key and signing secret" },
    { label: "Live mode", done: liveMode(), href: "/w/settings", hint: "after the end-to-end test" },
  ] : [];
  const todo = setup.filter((x) => !x.done);
  return (
    <Page title="Home" sub={`${h.handoffs_today.sales + h.handoffs_today.nurture} hand-offs today · ${h.pool} in the nurture pool`}>
      {todo.length > 0 && (
        <details className="panel" open={todo.length === setup.length}>
          <summary>Setting up: {setup.length - todo.length} of {setup.length} connected</summary>
          <div className="setup-list">
            {setup.map((x) => (
              <Link key={x.label} href={x.href} className={`setup-item${x.done ? " done" : ""}`}>
                <span className="setup-mark" aria-hidden>{x.done ? "✓" : ""}</span>
                <span className="grow"><b>{x.label}</b><span className="small muted"> · {x.hint}</span></span>
                {!x.done && <span className="chip line">to do</span>}
              </Link>
            ))}
          </div>
        </details>
      )}
      {attention.length > 0 && (
        <div className="attention">
          {attention.map((a) => (
            <div key={a.href} className={`banner ${a.tone}`} role={a.tone === "danger" ? "alert" : undefined}>
              <AlertTriangle className="icon" aria-hidden />
              <div className="grow">{a.text}</div>
              <Link className="btn ghost sm" href={a.href}>{a.cta}</Link>
            </div>
          ))}
        </div>
      )}
      <StageApprovals requests={requests} canDecide leadBase="/w/leads" />
      <div className="grid g4">
        <div className="stat">
          <span>Hand-offs today</span>
          <b>{h.handoffs_today.sales + h.handoffs_today.nurture}</b>
          <span className="delta">{h.handoffs_today.sales} sales · {h.handoffs_today.nurture} nurture</span>
          <div className="spark" aria-label="Hand-offs per day, last 14 days" role="img">
            {h.handoffs_14d.map((d, i) => <i key={d.day} className={i === h.handoffs_14d.length - 1 ? "today" : ""} style={{ height: `${Math.max(6, ((d.sales + d.nurture) / dayMax) * 100)}%` }} title={`${d.day}: ${d.sales} sales, ${d.nurture} nurture`} />)}
          </div>
        </div>
        <div className="stat"><span>Unassigned now</span><b>{h.unassigned.count}</b>{h.unassigned.oldest ? <span className="delta down">Oldest {relative(h.unassigned.oldest)}</span> : <span className="delta">Everyone has their leads</span>}</div>
        <div className="stat"><span>First-contact SLA this month</span><b>{slaPct === null ? "—" : `${slaPct}%`}</b><span className="delta">{h.sla_month.breached} breached</span></div>
        <div className="stat"><span>Enrolled this month</span><b>{h.enrolled_month}</b><span className="delta">{h.to_verify} to verify</span></div>
      </div>
      <div className="grid g-lead">
        <section className="panel">
          <header><h3>Team today</h3><Link className="btn quiet sm" href="/w/team">Performance</Link></header>
          <div className="table-wrap" style={{ boxShadow: "none" }}>
            <table>
              <thead><tr><th>Counsellor</th><th>Status</th><th className="right">Open</th><th className="right">Month / cap</th><th className="right">Calls today</th><th className="right">Enrolled</th></tr></thead>
              <tbody>
                {counsellors.length === 0 && <tr><td colSpan={6} className="muted">No counsellors yet. Add them under Teams.</td></tr>}
                {counsellors.map((t) => (
                  <tr key={t.user.user_id}>
                    <td><b>{t.user.full_name}</b>{t.user.is_test_user && <span className="chip line" style={{ marginLeft: 6 }}>Test</span>}</td>
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
        <section className="panel">
          <header><h3>Sales funnel</h3><Link className="btn quiet sm" href="/w/pipeline">Pipeline</Link></header>
          <div className="body">
            {h.funnel.map((f) => (
              <div key={f.stage} className="funnel-row">
                <span className="ellipsis">{f.stage}</span>
                <div className="bar-track"><div className={`bar-fill${f.stage === "Lost" ? " amber" : ""}`} style={{ width: `${(f.n / max) * 100}%` }} /></div>
                <span className="num right">{f.n}</span>
              </div>
            ))}
            <p className="note">Master lead table: last batch {when(h.sync.last_batch_at)} · {h.sync.queued} changes waiting · last event {when(h.sync.last_received_at)}.</p>
          </div>
        </section>
      </div>
    </Page>
  );
}
