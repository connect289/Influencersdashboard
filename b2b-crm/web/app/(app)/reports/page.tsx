import type { Metadata } from "next";
import Link from "next/link";
import { FileText } from "lucide-react";
import { Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { metricCatalogue, reportsList } from "@/lib/analytics-data";
import { relativeTime } from "@/lib/format";
import { KIND_LABEL, type ReportKind } from "@/lib/reports";
import { ReportBuilder } from "./ReportBuilder";

export const metadata: Metadata = { title: "Reports" };
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

/** Reports (B14.3): tabular, summary and matrix; save, schedule, export. They read the same facts as the dashboards. */
export default async function ReportsPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const [l, cat] = await Promise.all([reportsList(), metricCatalogue()]);
  const open = typeof sp.id === "string" ? l.reports.find((r) => String(r.id) === sp.id) ?? null : null;
  return (
    <>
      <PageHeader title="Reports" description="Lists, summaries and matrices from the same data as the dashboards (no names, phones or e-mails). Save them, export CSV, or have them e-mailed on a schedule." />
      <div className="grid gap-6 xl:grid-cols-[280px_minmax(0,1fr)]">
        <Card className="min-w-0 self-start">
          <CardHeader title="Saved reports" />
          {l.reports.length === 0 ? <EmptyState icon={FileText} title="None yet">Build one on the right and save it.</EmptyState> : (
            <ul className="divide-y divide-border text-[13px]">
              <li><Link href="/reports" className="block px-5 py-2.5 text-info hover:underline">+ New report</Link></li>
              {l.reports.map((r) => (
                <li key={r.id}><Link href={`/reports?id=${r.id}`} className={`block px-5 py-2.5 hover:bg-surface-hover/60 ${open?.id === r.id ? "bg-surface-2" : ""}`}>
                  <span className="font-medium text-fg">{r.name}</span>
                  <span className="block text-[11.5px] text-subtle">{KIND_LABEL[r.kind as ReportKind].split(":")[0]} · {relativeTime(r.updated_at)}</span></Link></li>
              ))}
            </ul>
          )}
        </Card>
        <Card className="min-w-0">
          <CardHeader title={open ? open.name : "New report"} />
          <div className="px-5 pb-5"><ReportBuilder key={open?.id ?? "new"} metrics={cat.metrics} facts={l.facts} initial={open ? { id: open.id, name: open.name, kind: open.kind, definition: open.definition } : null} /></div>
        </Card>
      </div>
    </>
  );
}
