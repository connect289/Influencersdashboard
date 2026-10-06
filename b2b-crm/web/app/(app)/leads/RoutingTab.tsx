import Link from "next/link";
import { CircleCheck, CircleDashed, Route } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, EmptyState } from "@/components/ui/Card";
import { formatDateTime, relativeTime } from "@/lib/format";
import { ALLOCATION_LABEL, MODE_LABEL, REASON_LABEL, segmentLabel } from "@/lib/routing";
import type { LeadRouting } from "@/lib/routing-data";

/** The lead drawer's Routing tab: is the lead ready, what it is interested in, and every routing decision and allocation. */
export function RoutingTab({ leadId, r }: { leadId: number; r: LeadRouting | null }) {
  if (!r) return <EmptyState icon={Route} title="Routing is not available">The routing details could not be loaded.</EmptyState>;
  const ready = r.readiness.ready;
  return (
    <div className="divide-y divide-border">
      <section className="space-y-2 px-5 py-4">
        <div className="flex flex-wrap items-center gap-2">
          {ready
            ? <Badge tone="success"><CircleCheck className="size-3" /> Ready to route</Badge>
            : <Badge tone="warning"><CircleDashed className="size-3" /> Not ready</Badge>}
          <Badge tone={r.consent ? "success" : "neutral"}>{r.consent ? "Partner-sharing consent given" : "No partner-sharing consent"}</Badge>
          <Badge>{segmentLabel(r.interest.segment)}</Badge>
          {!r.routing_live && <Badge>Automatic routing off</Badge>}
        </div>
        {!ready && r.readiness.missing.length > 0 && <p className="text-[12.5px] text-muted">Waiting for: {r.readiness.missing.join(", ")}.</p>}
        <Link href={`/routing?tab=simulate&lead=${leadId}`} className={buttonClass("secondary", "sm")}><Route className="size-3.5" /> Simulate routing</Link>
      </section>

      {r.allocations.length > 0 && (
        <section className="px-5 py-4">
          <h3 className="mb-2 text-[11px] font-medium uppercase tracking-wider text-subtle">Allocations</h3>
          <ul className="space-y-2 text-[13px]">
            {r.allocations.map((a) => (
              <li key={a.id} className="flex flex-wrap items-center gap-x-2 gap-y-1">
                <span className="font-mono text-[12px] text-fg">{a.reference}</span>
                <span className="text-fg">{a.destination_type === "partner" ? a.partner_name : "Eduwit B2C"}</span>
                <Badge tone={a.destination_type === "partner" ? "info" : "warning"}>{ALLOCATION_LABEL[a.status] ?? a.status}</Badge>
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
                  {d.destination_type === "partner" ? `To ${d.partner_name} · ${MODE_LABEL[d.mode] ?? d.mode}` : `To B2C · ${REASON_LABEL[d.reason ?? ""] ?? d.reason}`}
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
