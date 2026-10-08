import type { Metadata } from "next";
import Link from "next/link";
import { Building2, Plus } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, Card, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatInr } from "@/lib/money";
import { ADAPTER_LABEL, partnerTitle, STATUS_LABEL, STATUS_TONE } from "@/lib/partners";
import { listPartners } from "@/lib/partners-data";
import { PartnerLogo } from "./PartnerLogo";

export const metadata: Metadata = { title: "Partners" };

function Stat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="text-[11px] uppercase tracking-wider text-subtle">{label}</dt>
      <dd className="tabular mt-0.5 truncate text-[13px] text-fg">{value}</dd>
    </div>
  );
}

export default async function PartnersPage() {
  await requireAdmin();
  const partners = await listPartners();
  const add = (
    <Link href="/partners/new" className={buttonClass("primary", "sm")}>
      <Plus className="size-3.5" /> Add partner
    </Link>
  );

  return (
    <>
      <PageHeader
        title="Partners"
        description="The edtech partners Eduwit routes leads to. A partner receives real leads only when its live switch is on."
        actions={partners.length > 0 ? add : undefined}
      />

      {partners.length === 0 ? (
        <Card>
          <EmptyState icon={Building2} title="No partners yet" action={add}>
            <p>Add each partner with its CRM type, duplicate handling, working hours, SLAs and caps. Every partner starts in onboarding with its live switch off; nothing is sent to it until it passes the go-live checklist and you switch it on.</p>
          </EmptyState>
        </Card>
      ) : (
        <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {partners.map((p) => {
            const pct = p.checklist_total ? Math.round((p.checklist_done / p.checklist_total) * 100) : 0;
            return (
              <li key={p.id}>
                <Link
                  href={`/partners/${p.id}`}
                  className={cn(
                    "group block h-full rounded-[var(--radius-card)] border border-border bg-surface p-5 transition-colors hover:border-border-strong hover:bg-surface-hover/40",
                    p.status === "closed" && "opacity-60",
                  )}
                >
                  <div className="flex items-start gap-3">
                    <PartnerLogo partner={p} />
                    <div className="min-w-0 flex-1">
                      <h2 className="truncate text-[15px] font-semibold text-fg group-hover:underline">{partnerTitle(p)}</h2>
                      <p className="truncate text-[12.5px] text-subtle">{p.display_name ? `${p.name} · ` : ""}{p.slug}</p>
                    </div>
                    <span
                      className={cn("inline-flex shrink-0 items-center gap-1.5 rounded-full border px-2 py-0.5 text-[11px] font-medium",
                        p.live ? "border-success/25 bg-success-bg text-success" : "border-border text-muted")}
                    >
                      <span className={cn("size-1.5 rounded-full", p.live ? "bg-success" : "bg-subtle")} aria-hidden /> {p.live ? "Live" : "Off"}
                    </span>
                  </div>

                  <div className="mt-3 flex flex-wrap gap-1.5">
                    <Badge tone={STATUS_TONE[p.status]}>{STATUS_LABEL[p.status]}</Badge>
                    <Badge>{ADAPTER_LABEL[p.adapter_type] ?? p.adapter_type}</Badge>
                  </div>
                  {p.status === "paused" && p.paused_reason && <p className="mt-2 line-clamp-2 text-[12px] text-warning">{p.paused_reason}</p>}

                  <dl className="mt-4 grid grid-cols-4 gap-3 border-t border-border pt-3">
                    <Stat label="Today" value={p.leads_today} />
                    <Stat label="This month" value={p.leads_month} />
                    <Stat
                      label="NCPL (month)"
                      value={<span title="Expected net commission per lead for this month's leads: P̂ × commission × (1 − refunds), from the latest segment statistics">{formatInr(p.ncpl_month)}</span>}
                    />
                    <Stat label="Daily cap" value={p.daily_cap ?? "None"} />
                  </dl>

                  {!p.live && p.status !== "closed" && (
                    <div className="mt-4">
                      <div className="flex justify-between text-[11.5px] text-muted">
                        <span>Go-live checklist</span>
                        <span className="tabular">{p.checklist_done} of {p.checklist_total}</span>
                      </div>
                      <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-surface-2" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100} aria-label="Go-live checklist">
                        <div className="h-full rounded-full bg-amber" style={{ width: `${pct}%` }} />
                      </div>
                    </div>
                  )}
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </>
  );
}
