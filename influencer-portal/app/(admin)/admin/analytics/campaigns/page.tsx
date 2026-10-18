import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { AnalyticsNav } from "@/components/analytics/analytics-nav";
import { Freshness } from "@/components/analytics/freshness";
import { ParamToggle } from "@/components/analytics/param-toggle";
import { RangeControl } from "@/components/analytics/range-control";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { EMPTY_TOTALS, ratio, unitEconomics } from "@/lib/analytics/compute";
import { loadRefreshedAt, loadSpend, loadTotals } from "@/lib/analytics/data";
import { formatMetric } from "@/lib/analytics/format";
import { parseRange, rangeParams } from "@/lib/analytics/ranges";
import { istToday } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("analytics.areas.campaigns") };
}

/** Every campaign's results side by side, with budget against actual spend (spec 12). */
export default async function CampaignAnalyticsList({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase, me } = await requireStaff("analytics.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const today = istToday();
  const range = parseRange(sp, today);
  const includeTest = sp.test === "1";
  const keep = new URLSearchParams({ ...rangeParams(range), ...(includeTest ? { test: "1" } : {}) }).toString();
  const data = await Promise.all([
    loadTotals(supabase, range, { dim: "campaign", includeTest }),
    loadSpend(supabase, range, "campaign"),
    loadRefreshedAt(supabase),
  ]).catch(() => null);
  const rows = data
    ? [...new Set([...data[0], ...data[1]].map((r) => r.key).filter((k): k is string => k !== null))].map((key) => {
        const tot = data[0].find((r) => r.key === key) ?? { ...EMPTY_TOTALS, key, label: null };
        const sp2 = data[1].find((r) => r.key === key);
        return { key, name: tot.label ?? sp2?.label ?? key, tot, spend: sp2, econ: unitEconomics(tot) };
      })
    : [];
  rows.sort((a, b) => b.tot.leads - a.tot.leads || (b.spend?.accrued_paise ?? 0) - (a.spend?.accrued_paise ?? 0));
  return (
    <>
      <PageHeader
        title={t("nav.admin.analytics")}
        description={t("analytics.campaigns.subtitle")}
        help="/admin/help/getting-started#analytics-campaigns"
      />
      <AnalyticsNav current="campaigns" permissions={me.permissions} search={keep} />
      <div className="mb-4 flex flex-wrap items-end justify-between gap-2">
        <div className="flex flex-wrap items-end gap-3">
          <RangeControl preset={range.preset} from={range.from} to={range.to} compare={range.compare} today={today} />
          <ParamToggle name="test" label={t("analytics.includeTest")} checked={includeTest} />
        </div>
        <Freshness refreshedAt={data?.[2] ?? null} />
      </div>
      <Card>
        {!data ? (
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        ) : rows.length === 0 ? (
          <EmptyState title={t("analytics.noData")} description={t("analytics.noDataHint")} />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("analytics.dimensions.campaign")}</Th>
                <Th className="text-right">{t("analytics.metrics.leads.label")}</Th>
                <Th className="text-right">{t("analytics.metrics.enrollments.label")}</Th>
                <Th className="text-right">{t("analytics.metrics.accrued_spend.label")}</Th>
                <Th className="text-right">{t("analytics.metrics.revenue.label")}</Th>
                <Th className="text-right">{t("analytics.metrics.cost_per_enrollment.label")}</Th>
                <Th className="text-right">{t("analytics.metrics.net_roi.label")}</Th>
                <Th className="text-right">{t("analytics.metrics.budget.label")}</Th>
                <Th className="text-right">{t("analytics.metrics.budget_used.label")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.key}>
                  <Td>
                    <Link
                      href={`/admin/analytics/campaigns/${r.key}${keep ? `?${keep}` : ""}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {r.name}
                    </Link>
                  </Td>
                  <Td className="text-right tabular-nums">{formatMetric("count", r.tot.leads)}</Td>
                  <Td className="text-right tabular-nums">{formatMetric("count", r.tot.enrolled)}</Td>
                  <Td className="text-right tabular-nums">{formatMetric("money", r.tot.cost_paise)}</Td>
                  <Td className="text-right tabular-nums">{formatMetric("money", r.tot.revenue_paise)}</Td>
                  <Td className="text-right tabular-nums">{formatMetric("money", r.econ.cost_per_enrollment_paise)}</Td>
                  <Td className="text-right tabular-nums">{formatMetric("percent", r.econ.net_roi)}</Td>
                  <Td className="text-right tabular-nums">{formatMetric("money", r.spend?.budget_paise ?? null)}</Td>
                  <Td className="text-right tabular-nums">
                    {formatMetric(
                      "percent",
                      r.spend?.budget_paise ? ratio(r.spend.accrued_to_date_paise, r.spend.budget_paise) : null,
                    )}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </>
  );
}
