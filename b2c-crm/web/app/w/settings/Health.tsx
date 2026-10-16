import Link from "next/link";
import { CheckCircle2, AlertTriangle, XCircle } from "lucide-react";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";

export type Health = {
  at: string;
  overall: "ok" | "warn" | "bad";
  checks: { key: string; label: string; level: "ok" | "warn" | "bad"; detail: string }[];
  jobs: { name: string; schedule: string; last_status?: string | null; last_start?: string | null; last_end?: string | null; message?: string | null }[];
  calls: { last_at: string | null; failed_last_hour: number; ok_last_hour: number } | null;
  ai: { spent_today: number; cap: number | null; failed_today: number };
};

const ICON = { ok: CheckCircle2, warn: AlertTriangle, bad: XCircle } as const;
const TONE = { ok: "ok", warn: "risk", bad: "breach" } as const;
const NEXT: Record<string, string> = {
  timers: "Supabase → Integrations → Cron: the b2c-* jobs must be scheduled; a failed run shows its message below.",
  app: "Settings → app → base_url must be the site's address and the internal key must be in Vault (the deploy script sets both).",
  outbox: "Connectors → B2B CRM link: refused changes carry the master table's answer; failed ones retry every minute.",
  inbox: "Connectors → B2B CRM link: an event with an error is retried; if it stays, the payload is in the inbox table.",
  sending: "Connectors → WhatsApp and Email: a failed send keeps its error; held ones wait for consent or the window.",
  ai: "Settings → ai: the daily cap and the model; failed calls are in the AI usage panel on Analytics.",
  people: "Home shows unassigned leads; Nurture → Replies has the replies; counsellors see their unlogged calls on Today.",
};

/** System health (spec B15): the timers, the app, the queues and feeds, Claude, and what waits for a person. */
export async function HealthPanel() {
  const h = await rpc<Health>("system_health");
  const Overall = ICON[h.overall];
  return (
    <div className="stack">
      <div className={`banner ${h.overall === "bad" ? "danger" : h.overall === "warn" ? "" : "info"}`}>
        <Overall className="icon" aria-hidden />
        <div className="grow">{h.overall === "ok" ? <b>Everything is running.</b> : h.overall === "warn" ? <b>Running, with something to look at.</b> : <b>Something needs attention.</b>} <span className="small muted">Checked {when(h.at)}.</span></div>
        <Link className="btn ghost sm" href="/w/settings?tab=health">Check again</Link>
      </div>
      <div className="list">
        {h.checks.map((c) => {
          const Icon = ICON[c.level];
          return (
            <div key={c.key} className="li" style={{ gridTemplateColumns: "auto 1fr" }}>
              <span className={`chip ${TONE[c.level]}`}><Icon className="icon s" aria-hidden />{c.level === "ok" ? "OK" : c.level === "warn" ? "Look" : "Fix"}</span>
              <span className="t">{c.label}</span>
              <span className="s" style={{ gridColumn: "2" }}>{c.detail}</span>
              {c.level !== "ok" && NEXT[c.key] && <span className="s small" style={{ gridColumn: "2" }}>{NEXT[c.key]}</span>}
            </div>
          );
        })}
      </div>
      <details className="panel">
        <summary>Timers ({h.jobs.length})</summary>
        <div className="table-wrap" style={{ boxShadow: "none" }}>
          <table>
            <thead><tr><th>Timer</th><th>Schedule (UTC)</th><th>Last run</th><th>Result</th></tr></thead>
            <tbody>
              {h.jobs.length === 0 && <tr><td colSpan={4} className="muted">No b2c-* timers are scheduled in this database.</td></tr>}
              {h.jobs.map((j) => (
                <tr key={j.name}>
                  <td className="mono">{j.name}</td><td className="mono small">{j.schedule}</td>
                  <td className="small">{j.last_start ? when(j.last_start) : "never, or not recorded"}</td>
                  <td className="small">{j.last_status ? <span className={`chip ${j.last_status === "succeeded" ? "ok" : "breach"}`}>{j.last_status}</span> : "—"}{j.message && j.last_status !== "succeeded" ? <div className="muted">{j.message}</div> : null}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </div>
  );
}
