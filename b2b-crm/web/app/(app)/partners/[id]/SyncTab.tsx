import Link from "next/link";
import { Activity, CircleCheck, Gauge, Timer } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import {
  formatLag, formatWorkingMinutes, healthState, onTimeRate, SLA_LABEL, SLA_STATUS, type PartnerSync, type SlaKey,
} from "@/lib/sync";
import { DeadLetters, ExportCompare, ReconItems, RunNow } from "./SyncControls";

function Stat({ label, value, sub, tone }: { label: string; value: React.ReactNode; sub?: React.ReactNode; tone?: "danger" | "warning" }) {
  return (
    <div className="min-w-0 px-4 py-3">
      <p className="text-[11.5px] text-muted">{label}</p>
      <p className={cn("tabular text-lg font-semibold", tone === "danger" ? "text-danger" : tone === "warning" ? "text-warning" : "text-fg")}>{value}</p>
      {sub && <p className="truncate text-[11.5px] text-subtle">{sub}</p>}
    </div>
  );
}

function Daily({ days }: { days: PartnerSync["health"]["daily"] }) {
  const max = Math.max(1, ...days.map((d) => d.events));
  return (
    <div className="px-5 pb-4">
      <p className="mb-2 text-[11.5px] text-muted">Events per day, last 7 days</p>
      <div className="flex items-end gap-2" role="img" aria-label={days.map((d) => `${d.day}: ${d.events} events, ${d.errors} failed`).join("; ")}>
        {days.map((d) => (
          <div key={d.day} className="flex min-w-0 flex-1 flex-col items-center gap-1">
            <div className="flex h-16 w-full flex-col justify-end overflow-hidden rounded-sm bg-surface-2" title={`${d.events} events, ${d.errors} failed`}>
              {d.errors > 0 && <div className="w-full bg-danger" style={{ height: `${(100 * d.errors) / max}%` }} />}
              <div className="w-full bg-info" style={{ height: `${(100 * (d.events - d.errors)) / max}%` }} />
            </div>
            <span className="text-[10.5px] text-subtle">{new Date(`${d.day}T00:00:00`).toLocaleDateString("en-IN", { weekday: "short" })}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

const pct = (v: number | null) => (v === null ? "–" : `${Math.round(v * 100)}%`);

/** The partner's sync health, SLA scorecard, dead letters and reconciliation (spec B8.4, B8.5). */
export function SyncTab({ s }: { s: PartnerSync }) {
  const h = s.health;
  const state = healthState(h);
  const sla = s.partner.sla;
  const target: Record<SlaKey, string> = {
    first_attempt: `${sla.first_contact_hours} working hour${sla.first_contact_hours === 1 ? "" : "s"} from the push`,
    first_connect: `${sla.first_connect_days} working day${sla.first_connect_days === 1 ? "" : "s"}`,
    counselling_outcome: `${sla.outcome_days} working days`,
    status_update: `every ${sla.status_update_days} days while open`,
    enrollment_proof: `${sla.proof_days} days after enrolled`,
  };
  const rows = (Object.keys(SLA_LABEL) as SlaKey[]).map((k) => s.scorecard.find((r) => r.sla === k) ?? { sla: k, met: 0, met_late: 0, breached: 0, pending: 0, median_working_min: null });

  return (
    <div className="space-y-6">
      <Card className="min-w-0">
        <CardHeader
          title="Sync health"
          description="Events the partner sends back, and pushes Eduwit sends it, over the last 7 days."
          action={<Badge tone={state.tone === "neutral" ? "neutral" : state.tone}>{state.label}</Badge>}
        />
        {state.reasons.length > 0 && (
          <ul className="space-y-1 border-b border-border px-5 py-3 text-[12.5px] text-muted">
            {state.reasons.map((r) => <li key={r}>• {r}</li>)}
          </ul>
        )}
        <div className="grid grid-cols-2 divide-border border-b border-border sm:grid-cols-3 lg:grid-cols-6 [&>*]:border-border max-lg:[&>*]:border-b sm:[&>*]:border-r">
          <Stat label="Last event" value={h.last_event_at ? <span title={formatDateTime(h.last_event_at)}>{relativeTime(h.last_event_at)}</span> : "Never"} sub={`${h.events_24h} in 24 h · ${h.events_7d} in 7 days`} />
          <Stat label="Event lag (p50 / p95)" value={`${formatLag(h.lag_p50_s)} / ${formatLag(h.lag_p95_s)}`} sub="From the partner's event time to receipt" tone={h.lag_p95_s !== null && h.lag_p95_s > 900 ? "warning" : undefined} />
          <Stat label="Failed events" value={h.errors_7d} sub={h.events_7d ? `${pct(h.errors_7d / h.events_7d)} of 7 days` : "No events"} tone={h.errors_7d ? "danger" : undefined} />
          <Stat label="Dead letters" value={h.dead_letters} sub={`${h.held} held for mapping`} tone={h.dead_letters ? "warning" : undefined} />
          <Stat label="Pushes" value={h.pushes_7d} sub={`${h.push_failures_7d} failed · ${h.push_backlog} waiting`} tone={h.pushes_7d && h.push_failures_7d / h.pushes_7d > 0.1 ? "warning" : undefined} />
          <Stat label="Bad signatures" value={h.bad_signatures_7d} sub={`${h.stale_leads} stale lead${h.stale_leads === 1 ? "" : "s"}`} tone={h.bad_signatures_7d ? "warning" : undefined} />
        </div>
        <div className="pt-4"><Daily days={h.daily} /></div>
      </Card>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)]">
        <Card className="min-w-0">
          <CardHeader
            title="SLA scorecard"
            description="Last 30 days, test leads left out. Clocks run in the partner's working hours."
            action={<Link href="?tab=settings" className="text-[12.5px] text-info hover:underline">Edit SLAs</Link>}
          />
          <div className="overflow-x-auto">
            <table className="w-full min-w-[560px] text-[13px]">
              <thead>
                <tr className="border-b border-border text-left text-[11.5px] text-muted">
                  <th className="px-5 py-2 font-medium">SLA</th>
                  <th className="px-3 py-2 text-right font-medium">On time</th>
                  <th className="px-3 py-2 text-right font-medium">Late</th>
                  <th className="px-3 py-2 text-right font-medium">Breached</th>
                  <th className="px-3 py-2 text-right font-medium">Running</th>
                  <th className="px-5 py-2 text-right font-medium">Median</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {rows.map((r) => {
                  const rate = onTimeRate(r);
                  return (
                    <tr key={r.sla}>
                      <td className="px-5 py-2.5">
                        <p className="font-medium text-fg">{SLA_LABEL[r.sla]}</p>
                        <p className="text-[12px] text-subtle">{target[r.sla]}</p>
                      </td>
                      <td className="tabular whitespace-nowrap px-3 py-2.5 text-right">
                        <span className={cn(rate === null ? "text-subtle" : rate >= 0.9 ? "text-success" : rate >= 0.7 ? "text-warning" : "text-danger")}>{pct(rate)}</span>
                        <span className="ml-1 text-[11.5px] text-subtle">({r.met})</span>
                      </td>
                      <td className="tabular px-3 py-2.5 text-right text-muted">{r.met_late}</td>
                      <td className={cn("tabular px-3 py-2.5 text-right", r.breached ? "text-danger" : "text-muted")}>{r.breached}</td>
                      <td className="tabular px-3 py-2.5 text-right text-muted">{r.pending}</td>
                      <td className="tabular whitespace-nowrap px-5 py-2.5 text-right text-muted">{formatWorkingMinutes(r.median_working_min)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <p className="border-t border-border px-5 py-3 text-[12px] text-subtle">
            A first-contact breach raises an alert; a missed status update flags the lead stale. Enrollment proof keeps commission
            expected until it arrives.
          </p>
        </Card>

        <Card className="min-w-0">
          <CardHeader title="Recent breaches" description="Late or missed clocks, newest first." />
          {s.breaches.length === 0 ? (
            <EmptyState icon={Timer} title="No breaches">Every SLA clock so far was met on time.</EmptyState>
          ) : (
            <ul className="max-h-[360px] divide-y divide-border overflow-y-auto">
              {s.breaches.map((b) => (
                <li key={b.id} className="flex items-start gap-3 px-5 py-2.5 text-[13px]">
                  <div className="min-w-0 flex-1">
                    <Link href={`/leads?lead=${b.lead_id}&tab=partner`} className="font-medium text-fg hover:underline">{b.name || `Lead #${b.lead_id}`}</Link>
                    <span className="ml-1.5 font-mono text-[11.5px] text-subtle">{b.reference}</span>
                    <p className="text-[12px] text-muted">
                      {SLA_LABEL[b.sla]} · due <span title={formatDateTime(b.due_at)}>{relativeTime(b.due_at)}</span>
                      {b.met_at && <> · met <span title={formatDateTime(b.met_at)}>{relativeTime(b.met_at)}</span></>}
                    </p>
                  </div>
                  <Badge tone={SLA_STATUS[b.status].tone}>{SLA_STATUS[b.status].label}</Badge>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <Card className="min-w-0">
        <CardHeader
          title="Dead letters"
          description="Events that failed or are held because nothing maps them. Retry after fixing the cause, or discard with a reason; the raw event is always kept."
        />
        {s.dead_letters.length === 0
          ? <EmptyState icon={CircleCheck} title="Nothing waiting">Every event from this partner was applied or deliberately ignored.</EmptyState>
          : <DeadLetters partnerId={s.partner.id} items={s.dead_letters} />}
      </Card>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)]">
        <Card className="min-w-0">
          <CardHeader
            title="Reconciliation"
            description="Mismatches between Eduwit's records and the partner's. Checked every night at 02:37; items close themselves once the mismatch is gone."
            action={<RunNow partnerId={s.partner.id} />}
          />
          {s.items.length === 0
            ? <EmptyState icon={Gauge} title="No open mismatches">{s.runs.length ? "The last comparison found nothing to fix." : "No comparison has run yet."}</EmptyState>
            : <ReconItems partnerId={s.partner.id} items={s.items} />}
        </Card>

        <div className="min-w-0 space-y-6">
          <Card className="min-w-0">
            <CardHeader title="Compare with the partner's export" description="Upload the partner's list of the leads it holds to find leads missing on either side and stages that disagree." />
            <ExportCompare partnerId={s.partner.id} />
          </Card>
          <Card className="min-w-0">
            <CardHeader title="Recent comparisons" />
            {s.runs.length === 0 ? <EmptyState icon={Activity} title="None yet" /> : (
              <ul className="divide-y divide-border">
                {s.runs.map((r) => (
                  <li key={r.id} className="flex items-center justify-between gap-3 px-5 py-2.5 text-[13px]">
                    <div className="min-w-0">
                      <p className="text-fg">{r.source === "nightly" ? "Nightly check" : r.source === "export" ? `Export of ${r.summary?.export_rows ?? 0} rows` : "Run by an Admin"}</p>
                      <p className="text-[12px] text-subtle"><span title={formatDateTime(r.started_at)}>{relativeTime(r.started_at)}</span></p>
                    </div>
                    <span className="tabular shrink-0 text-[12.5px] text-muted">{r.summary?.new ?? 0} new · {r.summary?.open ?? 0} open</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
