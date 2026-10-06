import Link from "next/link";
import { CircleCheck, CircleDashed, Megaphone, Route, ShieldOff, TriangleAlert } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, EmptyState } from "@/components/ui/Card";
import { formatDateTime, relativeTime } from "@/lib/format";
import { ALLOCATION_LABEL, LANE_LABEL, MODE_LABEL, NOT_PASSED_LABEL, REASON_LABEL, segmentLabel } from "@/lib/routing";
import type { LeadRouting } from "@/lib/routing-data";
import { RoutingActions } from "./RoutingActions";

/** The lead drawer's Routing tab: is the lead ready, what it is interested in, and every routing decision and allocation. */
export function RoutingTab({ leadId, r }: { leadId: number; r: LeadRouting | null }) {
  if (!r) return <EmptyState icon={Route} title="Routing is not available">The routing details could not be loaded.</EmptyState>;
  const ready = r.readiness.ready;
  const np = r.not_passed && !r.not_passed.passed_at ? r.not_passed : null;
  const open = ["queued", "pushing", "pushed", "accepted", "handed_off"];
  const b2c = r.allocations.find((a) => a.destination_type === "in_house" && a.status === "handed_off");
  const partner = r.allocations.find((a) => a.destination_type === "partner" && open.includes(a.status));
  const cls = r.readiness.class;
  const flag = r.flags.find((f) => !f.resolved_at);
  return (
    <div className="divide-y divide-border">
      {np && (
        <section className="flex gap-3 bg-danger-bg/60 px-5 py-3 text-[13px]">
          <ShieldOff className="mt-0.5 size-4 shrink-0 text-danger" />
          <p className="text-fg">
            <span className="font-medium">Not passed to any CRM:</span> {NOT_PASSED_LABEL[np.reason] ?? np.reason}
            {np.requested_course && <> · asked for {np.requested_course}</>} · <span title={formatDateTime(np.decided_at)}>{relativeTime(np.decided_at)}</span>.
            <span className="block text-[12px] text-muted">It stays in the master database. If Witty later classifies it differently, it is passed at the next hand-off point.</span>
          </p>
        </section>
      )}
      {flag && (
        <section className="flex gap-3 bg-warning-bg/60 px-5 py-3 text-[13px] text-fg">
          <TriangleAlert className="mt-0.5 size-4 shrink-0 text-warning" />
          <p>Witty now classifies this passed lead {flag.lead_status === "PROGRAM_MISMATCH" ? "programme mismatch" : "junk"}. It is in the review queue on the Routing screen; it is not moved.</p>
        </section>
      )}
      <section className="space-y-2 px-5 py-4">
        <div className="flex flex-wrap items-center gap-2">
          {ready
            ? <Badge tone="success"><CircleCheck className="size-3" /> At its decision point</Badge>
            : <Badge tone="warning"><CircleDashed className="size-3" /> Not ready</Badge>}
          {cls && <Badge tone={cls === "qualified" ? "success" : cls === "unqualified" ? "neutral" : "danger"}>{cls === "qualified" ? "Qualified" : cls === "unqualified" ? "Not qualified" : cls === "junk" ? "Junk" : "Programme mismatch"}</Badge>}
          {r.readiness.paid && <Badge tone="info"><Megaphone className="size-3" /> Paid: {r.readiness.paid}</Badge>}
          <Badge tone={r.consent ? "success" : "neutral"}>{r.consent ? "Partner-sharing consent given" : "No partner-sharing consent"}</Badge>
          <Badge>{segmentLabel(r.interest.segment)}</Badge>
          {!r.routing_live && <Badge>Automatic routing off</Badge>}
        </div>
        {!ready && r.readiness.missing.length > 0 && <p className="text-[12.5px] text-muted">Waiting for: {r.readiness.missing.join(", ")}.</p>}
        {cls === "unqualified" && (r.readiness.not_qualified ?? []).length > 0 && (
          <p className="text-[12.5px] text-muted">Not qualified yet ({(r.readiness.not_qualified ?? []).join(", ")}), so at its decision point it goes to B2C nurture.</p>
        )}
        <div className="flex flex-wrap gap-2">
          <Link href={`/routing?tab=simulate&lead=${leadId}`} className={buttonClass("secondary", "sm")}><Route className="size-3.5" /> Simulate routing</Link>
          <RoutingActions leadId={leadId} notPassed={Boolean(np)} b2cHeld={Boolean(b2c)} consent={r.consent}
            openPartnerAllocation={partner ? { id: partner.id, partner: partner.partner_name } : null} />
        </div>
      </section>

      {r.allocations.length > 0 && (
        <section className="px-5 py-4">
          <h3 className="mb-2 text-[11px] font-medium uppercase tracking-wider text-subtle">Allocations</h3>
          <ul className="space-y-2 text-[13px]">
            {r.allocations.map((a) => (
              <li key={a.id} className="flex flex-wrap items-center gap-x-2 gap-y-1">
                <span className="font-mono text-[12px] text-fg">{a.reference}</span>
                <span className="text-fg">{a.destination_type === "partner" ? a.partner_name : LANE_LABEL[a.b2c_lane ?? "sales"]}</span>
                <Badge tone={a.destination_type === "partner" ? "info" : "warning"}>{a.outcome === "lost" ? "Lost at partner" : ALLOCATION_LABEL[a.status] ?? a.status}</Badge>
                {a.reason && a.destination_type === "in_house" && <span className="text-[12px] text-muted">{REASON_LABEL[a.reason] ?? a.reason}</span>}
                <span className="text-[12px] text-subtle" title={formatDateTime(a.created_at)}>{relativeTime(a.created_at)}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="px-5 py-4">
        <h3 className="mb-2 text-[11px] font-medium uppercase tracking-wider text-subtle">Decisions</h3>
        {r.decisions.length === 0 ? (
          <p className="text-[13px] text-muted">Not routed yet.</p>
        ) : (
          <ul className="space-y-2 text-[13px]">
            {r.decisions.map((d) => (
              <li key={d.id}>
                <Link href={`/routing/decisions/${d.id}`} className="text-fg hover:underline">
                  {d.destination_type === "partner" ? `To ${d.partner_name} · ${MODE_LABEL[d.mode] ?? d.mode}` : `To ${LANE_LABEL[d.b2c_lane ?? "sales"]} · ${REASON_LABEL[d.reason ?? ""] ?? d.reason}`}
                </Link>
                <span className="block text-[12px] text-subtle">
                  <span title={formatDateTime(d.created_at)}>{relativeTime(d.created_at)}</span> · {d.actor_type === "engine" ? "automatic" : "by an Admin"} · {d.candidates.length} candidates
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
