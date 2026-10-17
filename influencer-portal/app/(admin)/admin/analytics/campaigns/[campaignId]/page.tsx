import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, Download } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { BreakdownTable, ECONOMICS_COLUMNS, QUALITY_COLUMNS } from "@/components/analytics/breakdown-table";
import { Funnel, LineChart } from "@/components/analytics/charts";
import { Freshness } from "@/components/analytics/freshness";
import { KpiCard } from "@/components/analytics/kpi-card";
import { ParamToggle } from "@/components/analytics/param-toggle";
import { RangeControl } from "@/components/analytics/range-control";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { sortBreakdown, toBreakdown } from "@/lib/analytics/breakdown";
import { EMPTY_TOTALS, funnel, leadQuality, ratio, unitEconomics } from "@/lib/analytics/compute";
import { loadOperations, loadRefreshedAt, loadSpend, loadTotals } from "@/lib/analytics/data";
import { dimensionHref, dimensionLabel } from "@/lib/analytics/labels";
import { fillSeries, parseRange, rangeParams } from "@/lib/analytics/ranges";
import { istToday } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("analytics.campaigns.title") };
}

const POST_DIMENSIONS = ["platform", "content_type", "programme"] as const;

/** One campaign (spec 12): the overview's figures scoped to it, with a per-creator comparison. */
export default async function CampaignDashboard({
  params,
  searchParams,
}: {
  params: Promise<{ campaignId: string }>;
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { campaignId } = await params;
  if (!z.uuid().safeParse(campaignId).success) notFound();
  const { supabase, me } = await requireStaff("analytics.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const today = istToday();
  const range = parseRange(sp, today);
  const includeTest = sp.test === "1";
  const post = (POST_DIMENSIONS as readonly string[]).includes(sp.dim ?? "")
    ? (sp.dim as (typeof POST_DIMENSIONS)[number])
    : "platform";
  const scope = { campaignId, includeTest };
  const keep = new URLSearchParams({ ...rangeParams(range), ...(includeTest ? { test: "1" } : {}) }).toString();
  const data = await Promise.all([
    loadTotals(supabase, range, scope),
    range.compare ? loadTotals(supabase, range.previous, scope) : Promise.resolve(null),
    loadTotals(supabase, range, { ...scope, bucket: range.bucket }),
    loadTotals(supabase, range, { ...scope, dim: "creator" }),
    loadTotals(supabase, range, { ...scope, dim: post }),
    loadSpend(supabase, range, "campaign", campaignId),
    loadOperations(supabase, campaignId),
    loadRefreshedAt(supabase),
  ]).catch(() => null);
  const spend = data?.[5].find((r) => r.key === campaignId);
  const name = spend?.label ?? null;
  if (data && !name) notFound();

  const back = (
    <Link
      href={`/admin/analytics/campaigns${keep ? `?${keep}` : ""}`}
      className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
    >
      <ArrowLeft className="size-4" aria-hidden /> {t("analytics.areas.campaigns")}
    </Link>
  );
  if (!data) {
    return (
      <>
        {back}
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      </>
    );
  }
  const [cur, prev, series, byCreator, byPost, , ops, refreshedAt] = data;
  const c = cur[0] ?? { ...EMPTY_TOTALS, key: "all", label: null };
  const p = prev ? (prev[0] ?? { ...EMPTY_TOTALS, key: "all", label: null }) : undefined;
  const e = unitEconomics(c);
  const pe = p ? unitEconomics(p) : undefined;
  const q = leadQuality(c);
  const creators = sortBreakdown(toBreakdown(byCreator, (r) => dimensionLabel("creator", r.key, r.label, t)));
  const posts = sortBreakdown(toBreakdown(byPost, (r) => dimensionLabel(post, r.key, r.label, t)));
  const pts = fillSeries(
    series.map((r) => ({ at: r.key ?? range.from, value: r.leads })),
    range.from,
    range.to,
    range.bucket,
  );

  return (
    <>
      {back}
      <PageHeader
        title={name ?? ""}
        description={t("analytics.campaigns.dashboardSubtitle")}
        help="/admin/help/analytics#campaigns"
        actions={
          <Button asChild size="sm" variant="secondary">
            <a
              href={`/api/analytics/export?${new URLSearchParams({ ...Object.fromEntries(new URLSearchParams(keep)), dim: "creator", campaign: campaignId })}`}
            >
              <Download /> {t("analytics.export")}
            </a>
          </Button>
        }
      />
      <div className="mb-4 flex flex-wrap items-end justify-between gap-2">
        <div className="flex flex-wrap items-end gap-3">
          <RangeControl preset={range.preset} from={range.from} to={range.to} compare={range.compare} today={today} />
          <ParamToggle name="test" label={t("analytics.includeTest")} checked={includeTest} />
        </div>
        <Freshness refreshedAt={refreshedAt} />
      </div>
      <div className="flex flex-col gap-4">
        <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
          <KpiCard id="leads" value={c.leads} previous={p?.leads} href={`/admin/leads?campaign=${campaignId}`} />
          <KpiCard id="enrollments" value={c.enrolled} previous={p?.enrolled} />
          <KpiCard id="accrued_spend" value={c.cost_paise} previous={p?.cost_paise} />
          <KpiCard id="revenue" value={c.revenue_paise} previous={p?.revenue_paise} />
          <KpiCard id="committed_spend" value={spend?.committed_paise ?? 0} />
          <KpiCard id="budget" value={spend?.budget_paise ?? null} />
          <KpiCard
            id="budget_used"
            value={spend?.budget_paise ? ratio(spend.accrued_to_date_paise, spend.budget_paise) : null}
          />
          <KpiCard
            id="cost_per_enrollment"
            value={e.cost_per_enrollment_paise}
            previous={pe?.cost_per_enrollment_paise}
          />
          <KpiCard id="cost_per_lead" value={e.cost_per_lead_paise} previous={pe?.cost_per_lead_paise} />
          <KpiCard id="net_roi" value={e.net_roi} previous={pe?.net_roi} />
          <KpiCard id="qualification_rate" value={q.qualification_rate} />
          <KpiCard id="overdue_deliverables" value={ops?.overdue_deliverables ?? null} />
        </div>
        <div className="grid gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader title={t("home.funnel")} />
            <Funnel
              rows={funnel(c)}
              labels={{
                clicks: t("analytics.metrics.clicks.label"),
                leads: t("analytics.metrics.leads.label"),
                qualified: t("analytics.metrics.qualified_leads.label"),
                allocated: t("analytics.metrics.allocated_leads.label"),
                applied: t("analytics.metrics.applications.label"),
                enrolled: t("analytics.metrics.enrollments.label"),
              }}
            />
          </Card>
          <Card>
            <CardHeader title={t("home.leadsOverTime")} />
            <LineChart title={t("analytics.metrics.leads.label")} points={pts} />
          </Card>
        </div>
        <Card>
          <CardHeader title={t("analytics.campaigns.creators")} description={t("analytics.campaigns.creatorsHint")} />
          <BreakdownTable
            rows={creators}
            columns={ECONOMICS_COLUMNS}
            dimensionLabel={t("analytics.dimensions.creator")}
            href={(r) => dimensionHref("creator", r.key, keep)}
          />
        </Card>
        <Card>
          <CardHeader title={t("analytics.qualityByCreator")} />
          <BreakdownTable
            rows={creators.filter((r) => r.t.leads > 0)}
            columns={QUALITY_COLUMNS}
            dimensionLabel={t("analytics.dimensions.creator")}
          />
        </Card>
        <Card>
          <CardHeader title={t("analytics.breakdownBy", { dimension: t(`analytics.dimensions.${post}`) })} />
          <nav className="mb-3 flex flex-wrap gap-1" aria-label={t("analytics.dimensionNav")}>
            {POST_DIMENSIONS.map((d) => (
              <Link
                key={d}
                href={`/admin/analytics/campaigns/${campaignId}?${new URLSearchParams({ ...Object.fromEntries(new URLSearchParams(keep)), dim: d })}`}
                aria-current={d === post ? "page" : undefined}
                className={
                  d === post
                    ? "rounded-lg bg-primary-soft px-2.5 py-1 text-sm font-medium text-primary"
                    : "rounded-lg px-2.5 py-1 text-sm text-muted hover:bg-surface-2"
                }
                scroll={false}
              >
                {t(`analytics.dimensions.${d}`)}
              </Link>
            ))}
          </nav>
          <BreakdownTable rows={posts} columns={ECONOMICS_COLUMNS} dimensionLabel={t(`analytics.dimensions.${post}`)} />
        </Card>
        {me.permissions.has("campaign.read") ? (
          <p className="text-sm">
            <Link href={`/admin/campaigns/${campaignId}`} className="text-primary hover:underline">
              {t("analytics.campaigns.open")}
            </Link>
          </p>
        ) : null}
      </div>
    </>
  );
}
