import type { Metadata } from "next";
import Link from "next/link";
import { GitMerge } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { mappingOverview } from "@/lib/mapping-data";

export const metadata: Metadata = { title: "Mapping studio" };

export default async function MappingPage() {
  await requireAdmin();
  const rows = await mappingOverview();
  return (
    <>
      <PageHeader title="Mapping studio"
        description="Each partner's stages, fields, picklist values and activities mapped to Eduwit's model and back. Routing, SLAs, analytics and commission read only Eduwit's values; the partner's own wording is kept beside them." />
      <Card className="min-w-0">
        <CardHeader title="Partners" description="A partner cannot go live until every required item is mapped and its golden files pass." />
        {rows.length === 0 ? (
          <EmptyState icon={GitMerge} title="No partners yet" action={<Link href="/partners/new" className={buttonClass("primary", "sm")}>Add a partner</Link>} />
        ) : (
          <ul className="divide-y divide-border">
            {rows.map((p) => {
              const pct = p.coverage?.required_total ? Math.round((p.coverage.required_done / p.coverage.required_total) * 100) : 0;
              return (
                <li key={p.id} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3.5">
                  <Link href={`/mapping/${p.id}`} className="min-w-0 flex-1 hover:underline">
                    <span className="block truncate text-[13.5px] font-medium text-fg">{p.name}</span>
                    <span className="block text-[12px] text-subtle">
                      {p.adapter_type.replace("_", " ")} · {p.active_version ? <>v{p.active_version} since <span title={formatDateTime(p.active_at)}>{relativeTime(p.active_at)}</span></> : "no published mapping"}
                      {p.last_snapshot_at && <> · schema <span title={formatDateTime(p.last_snapshot_at)}>{relativeTime(p.last_snapshot_at)}</span></>}
                    </span>
                  </Link>
                  <div className="flex flex-wrap items-center gap-1.5">
                    {p.coverage && (
                      <span className="flex items-center gap-2">
                        <span className="h-1.5 w-16 overflow-hidden rounded-full bg-surface-2" aria-hidden><span className={cn("block h-full rounded-full", pct === 100 ? "bg-success" : "bg-amber")} style={{ width: `${pct}%` }} /></span>
                        <span className="tabular text-[12px] text-muted">{pct}%</span>
                      </span>
                    )}
                    {p.ready ? <Badge tone="success">Ready for go-live</Badge> : <Badge>Not ready</Badge>}
                    {p.has_draft && <Badge tone="info">Draft</Badge>}
                    {p.queue_open > 0 && <Badge tone="warning"><span className="tabular">{p.queue_open}</span> unmapped</Badge>}
                    {p.held_events > 0 && <Badge tone="warning"><span className="tabular">{p.held_events}</span> events held</Badge>}
                  </div>
                  <Link href={`/mapping/${p.id}`} className={buttonClass("secondary", "sm")}>Open</Link>
                </li>
              );
            })}
          </ul>
        )}
      </Card>
    </>
  );
}
