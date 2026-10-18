import Link from "next/link";
import { Download } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { AnalyticsNav } from "@/components/analytics/analytics-nav";
import { BreakdownTable, ECONOMICS_COLUMNS, QUALITY_COLUMNS } from "@/components/analytics/breakdown-table";
import { BarList, Funnel, LineChart } from "@/components/analytics/charts";
import { Freshness } from "@/components/analytics/freshness";
import { KpiCard } from "@/components/analytics/kpi-card";
import { ParamToggle } from "@/components/analytics/param-toggle";
import { RangeControl } from "@/components/analytics/range-control";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { sortBreakdown, toBreakdown } from "@/lib/analytics/breakdown";
import { EMPTY_TOTALS, funnel, leaderboard, leadQuality, ratio, unitEconomics } from "@/lib/analytics/compute";
import {
  DIMENSIONS,
  loadCreatorRows,
  loadHealth,
  loadOperations,
  loadRefreshedAt,
  loadSpend,
  loadTotals,
  type Dimension,
  type SpendRow,
} from "@/lib/analytics/data";
import { formatMetric } from "@/lib/analytics/format";
import { dimensionHref, dimensionLabel } from "@/lib/analytics/labels";
import { fillSeries, parseRange, rangeParams } from "@/lib/analytics/ranges";
import { istToday } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.analytics") };
}

const FUNNEL_LABEL_IDS = {
  clicks: "clicks",
  leads: "leads",
  qualified: "qualified_leads",
  allocated: "allocated_leads",
  applied: "applications",
  enrolled: "enrollments",
} as const;

/** Admin overview (spec 12): programme health, spend, unit economics, lead quality, operations and leaderboards. */
export default async function AnalyticsOverview({
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
  const dim: Dimension = (DIMENSIONS as readonly string[]).includes(sp.dim ?? "") ? (sp.dim as Dimension) : "creator";
  const scope = { includeTest };
  const keep = new URLSearchParams({ ...rangeParams(range), ...(includeTest ? { test: "1" } : {}) }).toString();

  const results = await Promise.all([
    loadTotals(supabase, range, scope),
    range.compare ? loadTotals(supabase, range.previous, scope) : Promise.resolve(null),
    loadTotals(supabase, range, { ...scope, bucket: range.bucket }),
    range.compare ? loadTotals(supabase, range.previous, { ...scope, bucket: range.bucket }) : Promise.resolve(null),
    loadTotals(supabase, range, { ...scope, dim }),
    loadSpend(supabase, range, "all"),
    loadSpend(supabase, range, "deal_model"),
    loadSpend(supabase, range, "campaign"),
    loadHealth(supabase, range, includeTest),
    loadOperations(supabase),
    loadCreatorRows(supabase, range, scope),
    range.compare ? loadSpend(supabase, range.previous, "all") : Promise.resolve(null),
    loadRefreshedAt(supabase),
  ]).catch(() => null);

  const header = (
    <>
      <PageHeader
        title={t("nav.admin.analytics")}
        description={t("analytics.overview.subtitle")}
        help="/admin/help/getting-started#analytics"
        actions={
          <Button asChild size="sm" variant="secondary">
            <a
              href={`/api/analytics/export?${new URLSearchParams({ ...Object.fromEntries(new URLSearchParams(keep)), dim })}`}
            >
              <Download /> {t("analytics.export")}
            </a>
          </Button>
        }
      />
      <AnalyticsNav current="overview" permissions={me.permissions} search={keep} />
      <div className="mb-4 flex flex-wrap items-end justify-between gap-2">
        <div className="flex flex-wrap items-end gap-3">
          <RangeControl preset={range.preset} from={range.from} to={range.to} compare={range.compare} today={today} />
          <ParamToggle name="test" label={t("analytics.includeTest")} checked={includeTest} />
        </div>
        <Freshness refreshedAt={results?.[12] ?? null} />
      </div>
    </>
  );
  if (!results) {
    return (
      <>
        {header}
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      </>
    );
  }
  const [cur, prev, series, prevSeries, byDim, spendAll, spendModel, spendCampaign, health, ops, creators, prevSpend] =
    results;
  const c = cur[0] ?? { ...EMPTY_TOTALS, key: "all", label: null };
  const p = prev?.[0] ?? (range.compare ? { ...EMPTY_TOTALS, key: "all", label: null } : undefined);
  const e = unitEconomics(c);
  const pe = p ? unitEconomics(p) : undefined;
  const q = leadQuality(c);
  const pq = p ? leadQuality(p) : undefined;
  const s = spendAll[0];
  const ps = prevSpend?.[0];
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
  const breakdown = sortBreakdown(toBreakdown(byDim, (r) => dimensionLabel(dim, r.key, r.label, t)));
  const name = (r: { name: string }) => r.name;
  const boards = {
    enrolled: leaderboard(creators, (r) => r.enrolled, { name, limit: 5 }).filter((x) => x.value > 0),
    roi: leaderboard(creators, (r) => (r.cost_paise > 0 ? ratio(r.revenue_paise - r.cost_paise, r.cost_paise) : null), {
      name,
      sample: (r) => r.leads,
      minSample: 5,
      limit: 5,
    }),
    on_time: leaderboard(creators, (r) => ratio(r.on_time, r.due), {
      name,
      sample: (r) => r.due,
      minSample: 2,
      limit: 5,
    }),
  };
  const spendLabel = (r: SpendRow, kind: "deal_model" | "campaign") =>
    r.key === null ? t("analytics.notSplit") : kind === "deal_model" ? t(`deals.models.${r.key}`) : (r.label ?? r.key);

  return (
    <>
      {header}
      <div className="flex flex-col gap-4">
        <section aria-labelledby="an-health">
          <h2 id="an-health" className="mb-2 text-base font-semibold">
            {t("analytics.groups.health")}
          </h2>
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
            <KpiCard id="active_creators" value={health?.active ?? null} href="/admin/creators" />
            <KpiCard
              id="new_creators"
              value={health?.new ?? null}
              previous={range.compare ? (health?.new_previous ?? null) : undefined}
            />
            <KpiCard id="dormant_creators" value={health?.dormant ?? null} href="/admin/creators?stage=dormant" />
            <Card className="col-span-2 p-3 lg:col-span-1">
              <p className="mb-2 text-xs text-muted">{t("analytics.pipeline")}</p>
              <BarList
                empty={t("analytics.noData")}
                rows={Object.entries(health?.pipeline ?? {}).map(([k, v]) => ({
                  key: k,
                  label: t(`creators.stages.${k}`),
                  value: v,
                }))}
              />
            </Card>
          </div>
        </section>

        <section aria-labelledby="an-funnel" className="flex flex-col gap-2">
          <h2 id="an-funnel" className="text-base font-semibold">
            {t("analytics.groups.funnel")}
          </h2>
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
            <KpiCard id="clicks" value={c.clicks} previous={p?.clicks} />
            <KpiCard id="leads" value={c.leads} previous={p?.leads} href="/admin/leads" />
            <KpiCard id="qualified_leads" value={c.qualified} previous={p?.qualified} />
            <KpiCard id="enrollments" value={c.enrolled} previous={p?.enrolled} />
          </div>
          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <CardHeader title={t("home.funnel")} />
              <Funnel
                rows={funnel(c)}
                labels={Object.fromEntries(
                  Object.entries(FUNNEL_LABEL_IDS).map(([k, id]) => [k, t(`analytics.metrics.${id}.label`)]),
                )}
              />
            </Card>
            <Card>
              <CardHeader title={t("home.leadsOverTime")} />
              <LineChart title={t("analytics.metrics.leads.label")} points={pts} previous={prevPts} />
            </Card>
          </div>
        </section>

        <section aria-labelledby="an-spend" className="flex flex-col gap-2">
          <h2 id="an-spend" className="text-base font-semibold">
            {t("analytics.groups.spend")}
          </h2>
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-3">
            <KpiCard id="committed_spend" value={s?.committed_paise ?? 0} />
            <KpiCard id="accrued_spend" value={s?.accrued_paise ?? 0} previous={ps ? ps.accrued_paise : undefined} />
            <KpiCard
              id="paid_spend"
              value={s?.paid_paise ?? 0}
              previous={ps ? ps.paid_paise : undefined}
              href={me.permissions.has("payout.read") ? "/admin/finance/payouts" : undefined}
            />
          </div>
          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <CardHeader title={t("analytics.spend.byModel")} description={t("analytics.spend.byModelHint")} />
              <SpendTable rows={spendModel} label={(r) => spendLabel(r, "deal_model")} budget={false} />
            </Card>
            <Card>
              <CardHeader title={t("analytics.spend.byCampaign")} description={t("analytics.spend.byCampaignHint")} />
              <SpendTable
                rows={spendCampaign.filter((r) => r.key !== null)}
                label={(r) => spendLabel(r, "campaign")}
                href={(r) => (r.key ? `/admin/analytics/campaigns/${r.key}?${keep}` : undefined)}
                budget
              />
            </Card>
          </div>
        </section>

        <section aria-labelledby="an-econ" className="flex flex-col gap-2">
          <h2 id="an-econ" className="text-base font-semibold">
            {t("analytics.groups.economics")}
          </h2>
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-6">
            <KpiCard id="cost_per_lead" value={e.cost_per_lead_paise} previous={pe?.cost_per_lead_paise} />
            <KpiCard
              id="cost_per_qualified_lead"
              value={e.cost_per_qualified_paise}
              previous={pe?.cost_per_qualified_paise}
            />
            <KpiCard
              id="cost_per_enrollment"
              value={e.cost_per_enrollment_paise}
              previous={pe?.cost_per_enrollment_paise}
            />
            <KpiCard id="revenue" value={e.revenue_paise} previous={pe?.revenue_paise} />
            <KpiCard id="net_roi" value={e.net_roi} previous={pe?.net_roi} />
            <KpiCard id="roas" value={e.roas} previous={pe?.roas} />
          </div>
          <Card>
            <CardHeader
              title={t("analytics.breakdownBy", { dimension: t(`analytics.dimensions.${dim}`) })}
              description={t("analytics.breakdownHint")}
            />
            <nav className="mb-3 flex flex-wrap gap-1" aria-label={t("analytics.dimensionNav")}>
              {DIMENSIONS.map((d) => (
                <Link
                  key={d}
                  href={`/admin/analytics?${new URLSearchParams({ ...Object.fromEntries(new URLSearchParams(keep)), dim: d })}`}
                  aria-current={d === dim ? "page" : undefined}
                  className={
                    d === dim
                      ? "rounded-lg bg-primary-soft px-2.5 py-1 text-sm font-medium text-primary"
                      : "rounded-lg px-2.5 py-1 text-sm text-muted hover:bg-surface-2"
                  }
                  scroll={false}
                >
                  {t(`analytics.dimensions.${d}`)}
                </Link>
              ))}
            </nav>
            <BreakdownTable
              rows={breakdown}
              columns={ECONOMICS_COLUMNS}
              dimensionLabel={t(`analytics.dimensions.${dim}`)}
              href={(r) => dimensionHref(dim, r.key, keep)}
            />
          </Card>
        </section>

        <section aria-labelledby="an-quality" className="flex flex-col gap-2">
          <h2 id="an-quality" className="text-base font-semibold">
            {t("analytics.groups.quality")}
          </h2>
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
            <KpiCard id="qualification_rate" value={q.qualification_rate} previous={pq?.qualification_rate} />
            <KpiCard id="junk_rate" value={q.junk_rate} previous={pq?.junk_rate} />
            <KpiCard id="duplicate_rate" value={q.duplicate_rate} previous={pq?.duplicate_rate} />
            <KpiCard id="enrollment_rate" value={q.enrollment_rate} previous={pq?.enrollment_rate} />
          </div>
          {dim === "creator" ? (
            <Card>
              <CardHeader title={t("analytics.qualityByCreator")} />
              <BreakdownTable
                rows={breakdown.filter((r) => r.t.leads > 0)}
                columns={QUALITY_COLUMNS}
                dimensionLabel={t("analytics.dimensions.creator")}
                href={(r) => dimensionHref("creator", r.key, keep)}
                limit={20}
              />
            </Card>
          ) : null}
        </section>

        <section aria-labelledby="an-ops" className="flex flex-col gap-2">
          <h2 id="an-ops" className="text-base font-semibold">
            {t("analytics.groups.operations")}
          </h2>
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
            <KpiCard id="overdue_deliverables" value={ops?.overdue_deliverables ?? null} href="/admin/content" />
            <KpiCard id="pending_reviews" value={ops?.pending_reviews ?? null} href="/admin/content" />
            <KpiCard id="pending_negotiations" value={ops?.pending_negotiations ?? null} href="/admin/deals" />
            <KpiCard id="contracts_expiring" value={ops?.contracts_expiring ?? null} href="/admin/contracts" />
            <KpiCard
              id="payouts_due"
              value={ops?.payouts_due_paise ?? null}
              href={me.permissions.has("payout.read") ? "/admin/finance/payouts" : undefined}
            />
            <KpiCard
              id="kyc_pending"
              value={ops?.kyc_pending ?? null}
              href={me.permissions.has("kyc.read_masked") ? "/admin/kyc" : undefined}
            />
            <KpiCard id="fraud_flags" value={ops?.fraud_flags ?? null} href="/admin/leads/fraud" />
          </div>
        </section>

        <section aria-labelledby="an-boards">
          <h2 id="an-boards" className="mb-2 text-base font-semibold">
            {t("analytics.leaderboards")}
          </h2>
          <div className="grid gap-4 lg:grid-cols-3">
            {(
              [
                ["enrolled", "enrollments", (v: number) => formatMetric("count", v)],
                ["roi", "net_roi", (v: number) => formatMetric("percent", v)],
                ["on_time", "on_time_rate", (v: number) => formatMetric("percent", v)],
              ] as const
            ).map(([key, metric, fmt]) => (
              <Card key={key}>
                <CardHeader title={t(`analytics.boards.${key}`)} description={t(`analytics.boards.${key}Hint`)} />
                {boards[key].length === 0 ? (
                  <p className="text-sm text-muted">{t("analytics.noData")}</p>
                ) : (
                  <ol
                    className="flex flex-col divide-y divide-line"
                    aria-label={t(`analytics.metrics.${metric}.label`)}
                  >
                    {boards[key].map((b) => (
                      <li key={b.row.creator_id} className="flex items-center justify-between gap-3 py-2 text-sm">
                        <span className="flex min-w-0 items-center gap-2">
                          <span className="w-6 shrink-0 text-right font-semibold tabular-nums">{b.rank}</span>
                          <Link
                            href={`/admin/creators/${b.row.creator_id}?tab=analytics&${keep}`}
                            className="truncate hover:text-primary hover:underline"
                          >
                            {b.row.name}
                          </Link>
                        </span>
                        <span className="tabular-nums">{fmt(b.value)}</span>
                      </li>
                    ))}
                  </ol>
                )}
              </Card>
            ))}
          </div>
        </section>
      </div>
    </>
  );
}

async function SpendTable({
  rows,
  label,
  href,
  budget,
}: {
  rows: readonly SpendRow[];
  label: (r: SpendRow) => string;
  href?: (r: SpendRow) => string | undefined;
  budget: boolean;
}) {
  const t = await getTranslations();
  if (!rows.length) return <p className="text-sm text-muted">{t("analytics.noData")}</p>;
  return (
    <Table className="min-w-[480px]">
      <thead>
        <tr>
          <Th>{t("analytics.name")}</Th>
          <Th className="text-right">{t("analytics.metrics.committed_spend.label")}</Th>
          <Th className="text-right">{t("analytics.metrics.accrued_spend.label")}</Th>
          <Th className="text-right">{t("analytics.metrics.paid_spend.label")}</Th>
          {budget ? (
            <>
              <Th className="text-right">{t("analytics.metrics.budget.label")}</Th>
              <Th className="text-right">{t("analytics.metrics.budget_used.label")}</Th>
            </>
          ) : null}
        </tr>
      </thead>
      <tbody>
        {[...rows]
          .sort((a, b) => b.accrued_paise - a.accrued_paise || b.committed_paise - a.committed_paise)
          .map((r) => {
            const link = href?.(r);
            return (
              <tr key={r.key ?? "none"}>
                <Td>
                  {link ? (
                    <Link href={link} className="font-medium text-primary hover:underline">
                      {label(r)}
                    </Link>
                  ) : (
                    label(r)
                  )}
                </Td>
                <Td className="text-right tabular-nums">{formatMetric("money", r.committed_paise)}</Td>
                <Td className="text-right tabular-nums">{formatMetric("money", r.accrued_paise)}</Td>
                <Td className="text-right tabular-nums">{formatMetric("money", r.paid_paise)}</Td>
                {budget ? (
                  <>
                    <Td className="text-right tabular-nums">{formatMetric("money", r.budget_paise)}</Td>
                    <Td className="text-right tabular-nums">
                      {formatMetric("percent", r.budget_paise ? ratio(r.accrued_to_date_paise, r.budget_paise) : null)}
                    </Td>
                  </>
                ) : null}
              </tr>
            );
          })}
      </tbody>
    </Table>
  );
}
