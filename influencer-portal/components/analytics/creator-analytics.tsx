// Creator 360° analytics (spec 12): trends, content performance and lead-quality history for one creator, from the
// summary views (staff with analytics.read).
import { getTranslations } from "next-intl/server";
import { BreakdownTable, ECONOMICS_COLUMNS } from "@/components/analytics/breakdown-table";
import { LineChart } from "@/components/analytics/charts";
import { Freshness } from "@/components/analytics/freshness";
import { KpiCard } from "@/components/analytics/kpi-card";
import { ParamToggle } from "@/components/analytics/param-toggle";
import { RangeControl } from "@/components/analytics/range-control";
import { Card, CardHeader } from "@/components/ui/card";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { sortBreakdown, toBreakdown } from "@/lib/analytics/breakdown";
import { EMPTY_TOTALS, leadQuality, unitEconomics } from "@/lib/analytics/compute";
import { loadRefreshedAt, loadTotals } from "@/lib/analytics/data";
import { formatMetric } from "@/lib/analytics/format";
import { dimensionLabel } from "@/lib/analytics/labels";
import { fillSeries, parseRange } from "@/lib/analytics/ranges";
import type { Db } from "@/lib/contracts/data";
import { istToday } from "@/lib/format";

const shortDate = new Intl.DateTimeFormat("en-IN", { day: "2-digit", month: "short", timeZone: "UTC" });

export async function CreatorAnalytics({
  supabase,
  creatorId,
  search,
}: {
  supabase: Db;
  creatorId: string;
  search: Record<string, string | undefined>;
}) {
  const t = await getTranslations();
  const today = istToday();
  const range = parseRange(search, today);
  const includeTest = search.test === "1";
  const scope = { creatorId, includeTest };
  const data = await Promise.all([
    loadTotals(supabase, range, scope),
    range.compare ? loadTotals(supabase, range.previous, scope) : Promise.resolve(null),
    loadTotals(supabase, range, { ...scope, bucket: range.bucket }),
    range.compare ? loadTotals(supabase, range.previous, { ...scope, bucket: range.bucket }) : Promise.resolve(null),
    loadTotals(supabase, range, { ...scope, dim: "deal" }),
    loadTotals(supabase, range, { ...scope, dim: "content_type" }),
    loadRefreshedAt(supabase),
  ]).catch(() => null);
  const controls = (
    <div className="mb-4 flex flex-wrap items-end justify-between gap-2">
      <div className="flex flex-wrap items-end gap-3">
        <RangeControl preset={range.preset} from={range.from} to={range.to} compare={range.compare} today={today} />
        <ParamToggle name="test" label={t("analytics.includeTest")} checked={includeTest} />
      </div>
      <Freshness refreshedAt={data?.[6] ?? null} />
    </div>
  );
  if (!data)
    return (
      <>
        {controls}
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      </>
    );
  const [cur, prev, series, prevSeries, byDeal, byType] = data;
  const c = cur[0] ?? { ...EMPTY_TOTALS, key: "all", label: null };
  const p = prev ? (prev[0] ?? { ...EMPTY_TOTALS, key: "all", label: null }) : undefined;
  const e = unitEconomics(c);
  const pe = p ? unitEconomics(p) : undefined;
  const pts = fillSeries(
    series.map((r) => ({ at: r.key ?? range.from, value: r.leads })),
    range.from,
    range.to,
    range.bucket,
  );
  const prevPts = prevSeries
    ? fillSeries(
        prevSeries.map((r) => ({ at: r.key ?? range.previous.from, value: r.leads })),
        range.previous.from,
        range.previous.to,
        range.bucket,
      )
    : undefined;
  const history = series.filter((r) => r.attributions > 0);
  return (
    <>
      {controls}
      <div className="flex flex-col gap-4">
        <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
          <KpiCard id="leads" value={c.leads} previous={p?.leads} />
          <KpiCard id="enrollments" value={c.enrolled} previous={p?.enrolled} />
          <KpiCard id="accrued_spend" value={c.cost_paise} previous={p?.cost_paise} />
          <KpiCard id="revenue" value={c.revenue_paise} previous={p?.revenue_paise} />
          <KpiCard id="cost_per_lead" value={e.cost_per_lead_paise} previous={pe?.cost_per_lead_paise} />
          <KpiCard
            id="cost_per_enrollment"
            value={e.cost_per_enrollment_paise}
            previous={pe?.cost_per_enrollment_paise}
          />
          <KpiCard id="net_roi" value={e.net_roi} previous={pe?.net_roi} />
          <KpiCard id="roas" value={e.roas} previous={pe?.roas} />
        </div>
        <Card>
          <CardHeader title={t("analytics.creator.trend")} />
          <LineChart title={t("analytics.metrics.leads.label")} points={pts} previous={prevPts} />
        </Card>
        <div className="grid gap-4 xl:grid-cols-2">
          <Card>
            <CardHeader title={t("analytics.creator.byDeal")} />
            <BreakdownTable
              rows={sortBreakdown(toBreakdown(byDeal, (r) => dimensionLabel("deal", r.key, r.label, t)))}
              columns={ECONOMICS_COLUMNS}
              dimensionLabel={t("analytics.dimensions.deal")}
              href={(r) => (r.key ? `/admin/deals/${r.key}` : undefined)}
            />
          </Card>
          <Card>
            <CardHeader title={t("analytics.creator.byContent")} />
            <BreakdownTable
              rows={sortBreakdown(toBreakdown(byType, (r) => dimensionLabel("content_type", r.key, r.label, t)))}
              columns={ECONOMICS_COLUMNS}
              dimensionLabel={t("analytics.dimensions.content_type")}
            />
          </Card>
        </div>
        <Card>
          <CardHeader title={t("analytics.creator.quality")} description={t("analytics.creator.qualityHint")} />
          {history.length === 0 ? (
            <EmptyState title={t("analytics.noData")} />
          ) : (
            <Table className="min-w-[520px]">
              <thead>
                <tr>
                  <Th>{t("analytics.date")}</Th>
                  <Th className="text-right">{t("analytics.metrics.leads.label")}</Th>
                  <Th className="text-right">{t("analytics.metrics.qualification_rate.label")}</Th>
                  <Th className="text-right">{t("analytics.metrics.junk_rate.label")}</Th>
                  <Th className="text-right">{t("analytics.metrics.duplicate_rate.label")}</Th>
                  <Th className="text-right">{t("analytics.metrics.enrollment_rate.label")}</Th>
                </tr>
              </thead>
              <tbody>
                {history.map((r) => {
                  const q = leadQuality(r);
                  return (
                    <tr key={r.key ?? "none"}>
                      <Td>{r.key ? shortDate.format(new Date(`${r.key}T00:00:00Z`)) : "—"}</Td>
                      <Td className="text-right tabular-nums">{formatMetric("count", r.leads)}</Td>
                      <Td className="text-right tabular-nums">{formatMetric("percent", q.qualification_rate)}</Td>
                      <Td className="text-right tabular-nums">{formatMetric("percent", q.junk_rate)}</Td>
                      <Td className="text-right tabular-nums">{formatMetric("percent", q.duplicate_rate)}</Td>
                      <Td className="text-right tabular-nums">{formatMetric("percent", q.enrollment_rate)}</Td>
                    </tr>
                  );
                })}
              </tbody>
            </Table>
          )}
        </Card>
      </div>
    </>
  );
}
