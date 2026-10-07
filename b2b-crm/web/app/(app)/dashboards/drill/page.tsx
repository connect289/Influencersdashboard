import type { Metadata } from "next";
import Link from "next/link";
import { ChevronLeft, SearchX } from "lucide-react";
import { Card, EmptyState } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { DIM_LABEL, dimLabel, formatValue } from "@/lib/analytics";
import { metricCatalogue, metricDrill, metricQuery } from "@/lib/analytics-data";
import { formatDateTime } from "@/lib/format";
import { SaveViewButton } from "../DashboardClient";

export const metadata: Metadata = { title: "Behind the number" };
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const SHOW: Record<string, string[]> = {
  fact_leads: ["lead_id", "created_at", "source", "campaign", "state", "course", "lead_status", "stage", "destination", "partner_id"],
  fact_allocations: ["allocation_id", "lead_id", "created_at", "partner_id", "segment", "routing_mode", "status", "first_attempt_hours", "stage_reached", "enrolled", "reward"],
  fact_enrollments: ["enrollment_id", "lead_id", "enrolled_on", "partner_id", "course", "university", "status", "fee", "expected_inr", "realised_inr"],
  fact_sla: ["sla_id", "allocation_id", "partner_id", "sla", "due_at", "status", "hours"],
  fact_money: ["line_id", "lead_id", "partner_id", "period", "kind", "status", "net_inr", "created_at"],
  fact_invoices: ["invoice_id", "number", "partner_id", "status", "issue_date", "total_inr", "outstanding_inr", "ageing"],
  fact_notifications: ["notification_id", "partner_id", "channel", "kind", "status", "created_at", "minutes_to_send"],
  fact_capi: ["event_id", "platform", "stage", "status", "created_at"],
  fact_sync: ["event_id", "partner_id", "status", "created_at", "lag_minutes"],
  fact_ai: ["ai_id", "kind", "run_kind", "status", "rec_status", "cost_usd", "created_at"],
};

function cell(col: string, v: unknown, partners: Record<string, string>) {
  if (v === null || v === undefined || v === "") return <span className="text-subtle">—</span>;
  if (col === "lead_id") return <Link href={`/leads?lead=${v}`} className="text-info hover:underline">#{String(v)}</Link>;
  if (col === "partner_id") return partners[String(v)] ?? `#${v}`;
  if (col === "segment") return dimLabel("segment", String(v));
  if (typeof v === "boolean") return v ? "yes" : "no";
  if (/_at$|^due_at$/.test(col) && typeof v === "string") return formatDateTime(v);
  if (/(_inr|^fee|^reward)$/.test(col) && typeof v === "number") return formatValue(v, "inr");
  return String(v).replace(/_/g, " ");
}

/** The rows behind any number on a dashboard (B13: "every number answers: show me the leads behind this"). */
export default async function DrillPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const metric = typeof sp.metric === "string" ? sp.metric : "";
  let filters: Record<string, string[]> = {};
  try { if (typeof sp.filters === "string") filters = JSON.parse(sp.filters); } catch { filters = {}; }
  const from = typeof sp.from === "string" ? sp.from : undefined;
  const to = typeof sp.to === "string" ? sp.to : undefined;
  const cat = await metricCatalogue();
  const m = cat.metrics.find((x) => x.key === metric);
  if (!m) return <EmptyState icon={SearchX} title="Unknown metric">Open a number on a dashboard to see the rows behind it.</EmptyState>;
  const [drill, total] = await Promise.all([metricDrill({ metric, filters, from, to, limit: 500 }), metricQuery({ metric, filters, from, to, compare: "none" })]);
  const cols = SHOW[drill.fact] ?? Object.keys(drill.rows[0] ?? {});
  return (
    <>
      <Link href="/dashboards" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Dashboards</Link>
      <div className="mb-4 flex flex-wrap items-start gap-4">
        <div className="min-w-0 flex-1">
          <h1 className="text-xl font-semibold tracking-tight text-fg">{m.label}: {formatValue(total.total.value, m.unit)}</h1>
          <p className="text-[13px] text-muted">
            {formatDateTime(total.from)} to {formatDateTime(total.to)}
            {Object.entries(filters).map(([k, v]) => <span key={k}> · {DIM_LABEL[k] ?? k}: {v.map((x) => dimLabel(k, x, drill.labels)).join(", ")}</span>)}
          </p>
          <p className="text-[12px] text-subtle">{drill.shown} rows{drill.shown >= drill.limit ? ` (first ${drill.limit})` : ""}. {m.description}</p>
        </div>
        <SaveViewButton metric={metric} filters={filters} period="30d" />
      </div>
      <Card className="min-w-0 overflow-hidden">
        {drill.rows.length === 0 ? <EmptyState icon={SearchX} title="Nothing behind this number">No rows match in this period.</EmptyState> : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-left text-[12.5px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-b border-border">{cols.map((c) => <th key={c} scope="col" className="px-3 py-2.5 font-medium">{c.replace(/_/g, " ")}</th>)}</tr>
              </thead>
              <tbody className="divide-y divide-border">
                {drill.rows.map((r, i) => <tr key={i}>{cols.map((c) => <td key={c} className="whitespace-nowrap px-3 py-2 text-muted">{cell(c, r[c], drill.labels.partner)}</td>)}</tr>)}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
