// A breakdown by creator, campaign, platform, content type, programme or deal model: counts, spend, revenue, unit
// economics and lead quality per row (definitions in the column headers' info buttons). Phones scroll the table.
import Link from "next/link";
import { useTranslations } from "next-intl";
import { Table, Td, Th } from "@/components/ui/table";
import { EmptyState } from "@/components/ui/states";
import type { BreakdownRow } from "@/lib/analytics/breakdown";
import { formatMetric } from "@/lib/analytics/format";
import { METRICS, type MetricId } from "@/lib/analytics/metrics";
import { MetricInfo } from "./metric-info";

type Column = { id: MetricId; value: (r: BreakdownRow) => number | null };

export const ECONOMICS_COLUMNS: Column[] = [
  { id: "leads", value: (r) => r.t.leads },
  { id: "enrollments", value: (r) => r.t.enrolled },
  { id: "accrued_spend", value: (r) => r.t.cost_paise },
  { id: "revenue", value: (r) => r.t.revenue_paise },
  { id: "cost_per_lead", value: (r) => r.cost_per_lead_paise },
  { id: "cost_per_qualified_lead", value: (r) => r.cost_per_qualified_paise },
  { id: "cost_per_enrollment", value: (r) => r.cost_per_enrollment_paise },
  { id: "net_roi", value: (r) => r.net_roi },
  { id: "roas", value: (r) => r.roas },
];

export const QUALITY_COLUMNS: Column[] = [
  { id: "leads", value: (r) => r.t.leads },
  { id: "qualification_rate", value: (r) => r.qualification_rate },
  { id: "junk_rate", value: (r) => r.junk_rate },
  { id: "duplicate_rate", value: (r) => r.duplicate_rate },
  { id: "enrollment_rate", value: (r) => r.enrollment_rate },
];

export function BreakdownTable({
  rows,
  columns,
  dimensionLabel,
  href,
  limit,
}: {
  rows: readonly BreakdownRow[];
  columns: readonly Column[];
  dimensionLabel: string;
  href?: (r: BreakdownRow) => string | undefined;
  limit?: number;
}) {
  const t = useTranslations();
  if (!rows.length) return <EmptyState title={t("analytics.noData")} description={t("analytics.noDataHint")} />;
  const shown = limit ? rows.slice(0, limit) : rows;
  return (
    <Table>
      <thead>
        <tr>
          <Th>{dimensionLabel}</Th>
          {columns.map((c) => {
            const label = t(`analytics.metrics.${c.id}.label`);
            return (
              <Th key={c.id} className="text-right">
                <span className="inline-flex items-center gap-1">
                  {label}
                  <MetricInfo
                    label={label}
                    definition={t(`analytics.metrics.${c.id}.definition`)}
                    about={t("analytics.about", { metric: label })}
                  />
                </span>
              </Th>
            );
          })}
        </tr>
      </thead>
      <tbody>
        {shown.map((r) => {
          const link = href?.(r);
          return (
            <tr key={r.key ?? "none"}>
              <Td className="max-w-56 truncate">
                {link ? (
                  <Link href={link} className="font-medium text-primary hover:underline">
                    {r.label}
                  </Link>
                ) : (
                  <span className={r.key === null ? "text-muted" : "font-medium"}>{r.label}</span>
                )}
              </Td>
              {columns.map((c) => (
                <Td key={c.id} className="text-right tabular-nums">
                  {formatMetric(METRICS[c.id].unit, c.value(r))}
                </Td>
              ))}
            </tr>
          );
        })}
      </tbody>
    </Table>
  );
}
