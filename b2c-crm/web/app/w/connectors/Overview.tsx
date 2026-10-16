import { Check, CircleAlert } from "lucide-react";
import { inr, when } from "@/lib/format";
import { ImportTemplatesButton } from "./ImportTemplates";

export type ConnectorStatus = { last_ok_at: string | null; last_error_at: string | null; last_error: string | null; detail: Record<string, unknown>; updated_at: string };
export type ConnectorsOverview = {
  status: Record<string, ConnectorStatus>;
  b2b: { queued: number; refused_7d: number; last_applied_at: string | null };
  whatsapp: { sent_today: number; failed_today: number; templates: Record<string, number> | null; last_synced_at: string | null; staff_template: boolean };
  gmail: { sent_today: number; marketing_today: number; allowance: number; by_user: { name: string; sent_today: number }[]; connections: Record<string, number> };
  claude: { spent_today: number | null; budget: { daily_cap_inr?: number; model?: string } & Record<string, unknown> | null };
};

const NAMES: Record<string, string> = {
  b2b: "B2B CRM", whatsapp: "WhatsApp", gmail_system: "Gmail (system mail)", gmail_marketing: "Gmail (marketing)", claude: "Claude",
  telephony: "Telephony", directory: "Workspace directory", calendar: "Google Calendar",
};

function Health({ s }: { s?: ConnectorStatus }) {
  if (!s) return <span className="small muted">No call recorded yet.</span>;
  const broken = !!s.last_error_at && (!s.last_ok_at || s.last_error_at > s.last_ok_at);
  return (
    <span className="stack small" style={{ gap: 2 }}>
      <span>{broken ? <span className="chip breach"><CircleAlert className="icon s" aria-hidden />Failing</span> : <span className="chip ok"><Check className="icon s" aria-hidden />Working</span>}
        <span className="muted"> last success {when(s.last_ok_at)}</span></span>
      {s.last_error && <span className={broken ? "error" : "muted"}>Last error {when(s.last_error_at)}: {s.last_error}</span>}
    </span>
  );
}

/** The Admin's view of every connector (spec B17): figures for today, and each one's last success and last error. */
export function Overview({ o }: { o: ConnectorsOverview }) {
  const tpl = o.whatsapp.templates ?? {};
  const capInr = Number(o.claude.budget?.daily_cap_inr ?? o.claude.budget?.daily_cap ?? 0) || null;
  const spent = Number(o.claude.spent_today ?? 0);
  const gmailPct = o.gmail.allowance ? Math.round((o.gmail.sent_today / o.gmail.allowance) * 100) : null;
  const known = Object.keys(NAMES);
  const extra = Object.keys(o.status).filter((k) => !known.includes(k));
  return (
    <div className="stack">
      <div className="grid g3">
        <section className="card pad stack" style={{ gap: 8 }}>
          <h2>B2B CRM</h2>
          <dl className="kv">
            <dt>Waiting to send</dt><dd className="num">{o.b2b.queued}</dd>
            <dt>Refused or failed, 7 days</dt><dd className="num">{o.b2b.refused_7d}</dd>
            <dt>Last change applied</dt><dd>{when(o.b2b.last_applied_at)}</dd>
          </dl>
          <Health s={o.status.b2b} />
        </section>
        <section className="card pad stack" style={{ gap: 8 }}>
          <div className="row between"><h2>WhatsApp</h2><ImportTemplatesButton /></div>
          <dl className="kv">
            <dt>Sent today</dt><dd className="num">{o.whatsapp.sent_today}</dd>
            <dt>Failed today</dt><dd className="num">{o.whatsapp.failed_today}</dd>
            <dt>Templates</dt><dd>{Object.entries(tpl).map(([k, v]) => `${v} ${k}`).join(" · ") || "none"}</dd>
            <dt>Last template sync</dt><dd>{when(o.whatsapp.last_synced_at)}</dd>
            <dt>Staff alerts</dt><dd>{o.whatsapp.staff_template ? <span className="chip ok">Template approved</span> : <span className="chip risk">No approved template</span>}</dd>
          </dl>
          {!o.whatsapp.staff_template && <p className="note">Alerts to a person&apos;s own WhatsApp need an approved utility template named <span className="mono">staff_alert</span> with 3 variables, in this order: the title, the text, and the link. Create it under Templates (WhatsApp: sales and system) and submit it to Meta.</p>}
          <Health s={o.status.whatsapp} />
        </section>
        <section className="card pad stack" style={{ gap: 8 }}>
          <h2>Gmail</h2>
          <dl className="kv">
            <dt>Sent today</dt><dd className="num">{o.gmail.sent_today} of {o.gmail.allowance}{gmailPct !== null ? ` (${gmailPct}%)` : ""}</dd>
            <dt>Of which marketing</dt><dd className="num">{o.gmail.marketing_today}</dd>
            <dt>Personal connections</dt><dd>{Object.entries(o.gmail.connections ?? {}).map(([k, v]) => `${v} ${k}`).join(" · ") || "none yet"}</dd>
          </dl>
          {gmailPct !== null && <div className="bar-track"><div className={`bar-fill ${gmailPct >= 80 ? "amber" : ""}`} style={{ width: `${Math.min(100, gmailPct)}%` }} /></div>}
          {o.gmail.by_user.length > 0 && <div className="small">{o.gmail.by_user.map((u) => `${u.name}: ${u.sent_today}`).join(" · ")}</div>}
          <Health s={o.status.gmail_system} />
        </section>
        <section className="card pad stack" style={{ gap: 8 }}>
          <h2>Claude</h2>
          <dl className="kv">
            <dt>Spent today</dt><dd className="num">{inr(spent)}{capInr ? ` of ${inr(capInr)}` : ""}</dd>
            {o.claude.budget?.model ? <><dt>Model</dt><dd className="mono small">{String(o.claude.budget.model)}</dd></> : null}
          </dl>
          {capInr ? <div className="bar-track"><div className={`bar-fill ${spent / capInr >= 0.8 ? "amber" : ""}`} style={{ width: `${Math.min(100, (spent / capInr) * 100)}%` }} /></div> : null}
          <p className="note">At the daily cap Claude stops until midnight IST; nothing else stops. Change the cap under Settings → ai.</p>
          <Health s={o.status.claude} />
        </section>
      </div>
      <section className="stack">
        <h2>Last success and last error</h2>
        <div className="table-wrap"><table>
          <thead><tr><th>Connector</th><th>Status</th></tr></thead>
          <tbody>{[...known, ...extra].map((k) => <tr key={k}><td>{NAMES[k] ?? k}</td><td><Health s={o.status[k]} /></td></tr>)}</tbody>
        </table></div>
      </section>
    </div>
  );
}
