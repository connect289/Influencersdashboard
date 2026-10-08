import type { Metadata } from "next";
import Link from "next/link";
import { ChevronLeft, SearchX } from "lucide-react";
import { Card, EmptyState } from "@/components/ui/Card";
import { requireAdmin } from "@/lib/auth";
import { periodBounds } from "@/lib/ai/ask";
import {
  applicableFilters, DATE_BASIS_COLUMN, DATE_BASIS_LABEL, dateBasisParam, DIM_LABEL, dimLabel, drillHref, formatValue, PERIODS, viewParams, type MetricResult, type Period,
} from "@/lib/analytics";
import { metricCatalogue, metricDrill, metricQuery, type Drill } from "@/lib/analytics-data";
import { formatDateTime } from "@/lib/format";
import { SaveViewButton } from "../DashboardClient";

export const metadata: Metadata = { title: "Behind the number" };
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const SHOW: Record<string, string[]> = {
  fact_leads: ["lead_id", "created_at", "source", "campaign", "state", "course", "lead_status", "stage", "destination", "b2c_reason", "partner_id"],
  fact_allocations: ["allocation_id", "lead_id", "created_at", "partner_id", "segment", "origin", "stage", "routing_mode", "status", "first_attempt_hours", "stage_reached", "enrolled", "reward"],
  fact_enrollments: ["enrollment_id", "lead_id", "enrolled_on", "verified_at", "partner_id", "course", "university", "status", "fee", "expected_inr", "realised_inr"],
  fact_sla: ["sla_id", "allocation_id", "partner_id", "sla", "due_at", "status", "hours"],
  fact_money: ["line_id", "lead_id", "partner_id", "period", "kind", "status", "net_inr", "realised_at", "created_at"],
  fact_invoices: ["invoice_id", "number", "partner_id", "status", "issue_date", "total_inr", "outstanding_inr", "ageing"],
  fact_notifications: ["notification_id", "partner_id", "channel", "kind", "status", "created_at", "minutes_to_send"],
  fact_capi: ["event_id", "platform", "stage", "status", "created_at"],
  fact_sync: ["event_id", "partner_id", "status", "created_at", "lag_minutes"],
  fact_ai: ["ai_id", "kind", "run_kind", "status", "rec_status", "cost_usd", "created_at"],
};

/** Fact columns whose name differs from the breakdown key that filters them (so a filtered column can be shown). */
const DIM_COLUMN: Record<string, string> = { partner: "partner_id", score_stage: "stage" };
/** Column headers where the column name alone misleads: on allocations `stage` is the A/B/C scoring stage, not the stage reached (C90). */
const COL_LABEL: Record<string, Record<string, string>> = {
  fact_allocations: { stage: "scoring stage", stage_reached: "stage reached", origin: "how routed" },
  fact_leads: { b2c_reason: "why sent to B2C" },
};
/** Columns whose values are breakdown values with their own wording. */
const COL_DIM: Record<string, Record<string, string>> = {
  fact_allocations: { stage: "score_stage", origin: "origin" },
  fact_leads: { b2c_reason: "b2c_reason", hold_kind: "hold_kind", consent_state: "consent_state" },
};

function cell(fact: string, col: string, v: unknown, partners: Record<string, string>) {
  if (v === null || v === undefined || v === "") return <span className="text-subtle">—</span>;
  if (col === "lead_id") return <Link href={`/leads?lead=${v}`} className="text-info hover:underline">#{String(v)}</Link>;
  if (col === "partner_id") return partners[String(v)] ?? `#${v}`;
  if (col === "segment") return dimLabel("segment", String(v));
  const dim = COL_DIM[fact]?.[col];
  if (dim) return dimLabel(dim, String(v));
  if (typeof v === "boolean") return v ? "yes" : "no";
  if (/_at$|^due_at$/.test(col) && typeof v === "string") return formatDateTime(v);
  if (/(_inr|^fee|^reward)$/.test(col) && typeof v === "number") return formatValue(v, "inr");
  return String(v).replace(/_/g, " ");
}

/** The columns to show: the fact's usual ones, then the date the list is counted by and every filtered column, when the rows have them. */
function columns(drill: Drill, filters: Record<string, string[]>, dateBasis: ReturnType<typeof dateBasisParam>): string[] {
  const first = drill.rows[0] ?? {};
  const base = SHOW[drill.fact] ?? Object.keys(first);
  const wanted = [dateBasis ? DATE_BASIS_COLUMN[drill.fact]?.[dateBasis] : undefined, ...Object.keys(filters).map((k) => DIM_COLUMN[k] ?? k)];
  const extra = wanted.filter((c): c is string => !!c && c in first && !base.includes(c));
  return [...base, ...new Set(extra)];
}

/** The rows behind any number on a dashboard (B13: "every number answers: show me the leads behind this"). */
export default async function DrillPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const metric = typeof sp.metric === "string" ? sp.metric : "";
  // malformed filters (not an object of string lists) read as none, like the dashboards do
  const raw = viewParams(sp, "30d").filters ?? {};
  // a link from a widget carries its period: explicit from/to win, the period alone gives its window, and a saved view keeps it
  const period = PERIODS.includes(sp.period as Period) ? (sp.period as Period) : undefined;
  const b = period && typeof sp.from !== "string" ? periodBounds(period) : undefined;
  const from = typeof sp.from === "string" ? sp.from : b?.from;
  const to = typeof sp.to === "string" ? sp.to : b?.to;
  // a widget counted by another date (created / routed / accepted / enrolled, C70) lists its rows by that date too
  const dateBasis = dateBasisParam(sp.date_basis);
  const cat = await metricCatalogue();
  const m = cat.metrics.find((x) => x.key === metric);
  if (!m) return <EmptyState icon={SearchX} title="Unknown metric">Open a number on a dashboard to see the rows behind it.</EmptyState>;
  // only the filters the number on the widget used: dashboard filters on keys this metric lacks are dropped (as widget_data does)
  const filters = applicableFilters(raw, m.dims);
  const q: Record<string, unknown> = { metric, filters, from, to, ...(dateBasis ? { date_basis: dateBasis } : {}) };
  let drill: Drill, total: MetricResult;
  try {
    [drill, total] = await Promise.all([metricDrill({ ...q, limit: 500 }), metricQuery({ ...q, compare: "none" })]);
  } catch (e) {
    // the SQL refuses a basis or filter this metric cannot use (22023 '<label> cannot be dated by <basis>', 'cannot filter by <key>'): say so instead of failing the page
    const why = /22023: (.+)\)$/.exec(e instanceof Error ? e.message : String(e))?.[1];
    if (!why) throw e;
    return (
      <>
        <Link href="/dashboards" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Dashboards</Link>
        <EmptyState icon={SearchX} title="This list cannot be built" action={dateBasis ? <Link href={drillHref(metric, filters, from, to, period)} className="text-[13px] text-info hover:underline">Show it by the metric&apos;s own date</Link> : undefined}>
          {why.charAt(0).toUpperCase() + why.slice(1)}.
        </EmptyState>
      </>
    );
  }
  const cols = columns(drill, filters, dateBasis);
  return (
    <>
      <Link href="/dashboards" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Dashboards</Link>
      <div className="mb-4 flex flex-wrap items-start gap-4">
        <div className="min-w-0 flex-1">
          <h1 className="text-xl font-semibold tracking-tight text-fg">{m.label}: {formatValue(total.total.value, m.unit)}</h1>
          <p className="text-[13px] text-muted">
            {formatDateTime(total.from)} to {formatDateTime(total.to)}
            {dateBasis && <span> · counted by the {DATE_BASIS_LABEL[dateBasis].toLowerCase()} date</span>}
            {Object.entries(filters).map(([k, v]) => <span key={k}> · {DIM_LABEL[k] ?? k}: {v.map((x) => dimLabel(k, x, drill.labels)).join(", ")}</span>)}
          </p>
          <p className="text-[12px] text-subtle">{drill.shown} rows{drill.shown >= drill.limit ? ` (first ${drill.limit})` : ""}. {m.description}</p>
        </div>
        {/* a saved view keeps the metric, filters and period (saved_view_save, m28a); the date basis is not part of a view */}
        <SaveViewButton metric={metric} filters={filters} period={period ?? "30d"} />
      </div>
      <Card className="min-w-0 overflow-hidden">
        {drill.rows.length === 0 ? <EmptyState icon={SearchX} title="Nothing behind this number">No rows match in this period.</EmptyState> : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-left text-[12.5px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-b border-border">{cols.map((c) => <th key={c} scope="col" className="px-3 py-2.5 font-medium">{COL_LABEL[drill.fact]?.[c] ?? c.replace(/_/g, " ")}</th>)}</tr>
              </thead>
              <tbody className="divide-y divide-border">
                {drill.rows.map((r, i) => <tr key={i}>{cols.map((c) => <td key={c} className="whitespace-nowrap px-3 py-2 text-muted">{cell(drill.fact, c, r[c], drill.labels.partner)}</td>)}</tr>)}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
