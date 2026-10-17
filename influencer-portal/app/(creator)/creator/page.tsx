import Link from "next/link";
import { ChevronRight, Download, FileCheck2, Trophy } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { BarList, Funnel, LineChart } from "@/components/analytics/charts";
import { KpiCard } from "@/components/analytics/kpi-card";
import { RangeControl } from "@/components/analytics/range-control";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { funnel } from "@/lib/analytics/compute";
import { loadCreatorDashboard, type CreatorDashboard } from "@/lib/analytics/data";
import { formatMetric } from "@/lib/analytics/format";
import { fillSeries, parseRange, rangeParams } from "@/lib/analytics/ranges";
import { requireCreator } from "@/lib/auth/guards";
import { onboardingState, progressPct } from "@/lib/creators/onboarding";
import { loadEarnings } from "@/lib/ledger/data";
import { earningTotals, nextPayoutDate } from "@/lib/ledger/earnings";
import { istToday } from "@/lib/format";

interface Action {
  key: string;
  title: string;
  hint: string;
  href: string;
}

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.home") };
}

function dashboardActions(d: CreatorDashboard, t: Awaited<ReturnType<typeof getTranslations>>): Action[] {
  const a = d.actions;
  const out: Action[] = [];
  const add = (key: string, count: number, href: string) => {
    if (count > 0)
      out.push({ key, title: t(`home.actions.${key}`, { count }), hint: t(`home.actions.${key}Hint`), href });
  };
  add("contracts", a.contracts, "/creator/contracts");
  add("briefs", a.briefs, "/creator/briefs");
  add("overdue", a.overdue, "/creator/deliverables");
  add("changesRequested", a.changes_requested, "/creator/deliverables");
  add("dueSoon", a.due_soon, "/creator/deliverables");
  add("metricsDue", a.metrics_due, "/creator/deliverables");
  add("invoices", a.invoices, "/creator/earnings");
  if (a.kyc)
    out.push({ key: "kyc", title: t("home.actions.kyc"), hint: t("home.actions.kycHint"), href: "/creator/kyc" });
  return out;
}

/** Creator home (spec 12): the action centre, earnings, fixed fees, the lead funnel and what is working best. */
export default async function CreatorHome({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const today = istToday();
  const range = parseRange(await searchParams, today);
  const [terms, onboarding, dash, earnings] = await Promise.all([
    supabase.rpc("terms_pending"),
    supabase.rpc("onboarding_state"),
    loadCreatorDashboard(supabase, me.creatorId, range).catch(() => null),
    loadEarnings(supabase, me.creatorId).catch(() => null),
  ]);
  const state = onboardingState.safeParse(onboarding.data);
  const approved = !(state.success && !state.data.approved);
  const actions: Action[] = [];
  if (state.success && !state.data.approved)
    actions.push(
      state.data.submitted_at
        ? {
            key: "onboarding",
            title: t("home.actions.onboardingReview"),
            hint: t("home.actions.onboardingReviewHint"),
            href: "/creator/onboarding?step=submit",
          }
        : {
            key: "onboarding",
            title: t("home.actions.onboarding"),
            hint: t("home.actions.onboardingHint", { pct: progressPct(state.data) }),
            href: "/creator/onboarding",
          },
    );
  if ((terms.data ?? []).length > 0 && approved)
    actions.push({
      key: "terms",
      title: t("home.actions.terms"),
      hint: t("home.actions.termsHint"),
      href: "/creator/terms",
    });
  if (dash && approved) actions.push(...dashboardActions(dash, t));

  const totals = earnings ? earningTotals(earnings.entries, today) : null;
  const next = earnings ? nextPayoutDate(earnings.settings.cycle, earnings.settings.payout_day_of_month, today) : null;
  const fixedRemaining = dash ? Math.max(dash.fixed.committed_paise - dash.fixed.earned_paise, 0) : 0;
  const prev = range.compare && dash ? dash.previous : undefined;
  const series = dash
    ? fillSeries(
        dash.series.map((s) => ({ at: s.at, value: s.leads })),
        range.from,
        range.to,
        range.bucket,
      )
    : [];
  const funnelLabels = Object.fromEntries(
    (["clicks", "leads", "qualified", "allocated", "applied", "enrolled"] as const).map((s) => [
      s,
      t(
        `analytics.metrics.${s === "qualified" ? "qualified_leads" : s === "allocated" ? "allocated_leads" : s === "applied" ? "applications" : s === "enrolled" ? "enrollments" : s}.label`,
      ),
    ]),
  );

  return (
    <>
      <PageHeader
        title={t("home.title", { name: me.displayName.split(" ")[0] ?? me.displayName })}
        description={t("home.subtitle")}
        help="/creator/help/creator#home"
      />
      <div className="flex flex-col gap-4">
        <Card>
          <CardHeader
            title={t("home.actionCentre")}
            description={actions.length ? t("home.actionsCount", { count: actions.length }) : undefined}
          />
          {terms.error ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
          {!terms.error && actions.length === 0 ? (
            <EmptyState title={t("home.noActions")} description={t("home.noActionsHint")} />
          ) : null}
          <ul className="flex flex-col gap-2">
            {actions.map((a) => (
              <li key={a.key}>
                <Link
                  href={a.href}
                  className="flex items-center gap-3 rounded-xl bg-accent-soft px-3 py-3 text-accent-ink hover:opacity-90"
                >
                  <FileCheck2 className="size-5 shrink-0" aria-hidden />
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm font-medium">{a.title}</span>
                    <span className="block text-xs">{a.hint}</span>
                  </span>
                  <ChevronRight className="size-4" aria-hidden />
                </Link>
              </li>
            ))}
          </ul>
        </Card>

        {totals && next ? (
          <section aria-labelledby="home-earnings">
            <div className="mb-2 flex items-baseline justify-between">
              <h2 id="home-earnings" className="text-base font-semibold">
                {t("home.earnings")}
              </h2>
              <Link href="/creator/earnings" className="text-sm text-primary hover:underline">
                {t("home.allEarnings")}
              </Link>
            </div>
            <div className="grid grid-cols-2 gap-2 lg:grid-cols-5">
              <KpiCard id="earned_total" value={totals.lifetime_paise} />
              <KpiCard id="earnings_pending" value={totals.pending_paise} />
              <KpiCard id="earnings_payable" value={totals.payable_paise} />
              <KpiCard id="earnings_paid" value={totals.paid_paise} />
              <KpiCard id="next_payout" value={next} className="col-span-2 lg:col-span-1" />
            </div>
          </section>
        ) : null}

        {dash && dash.fixed.committed_paise > 0 ? (
          <Card>
            <CardHeader title={t("home.fixed")} description={t("home.fixedHint")} />
            <div className="flex justify-between text-sm">
              <span>
                {t("analytics.metrics.fixed_received.label")}:{" "}
                <strong className="tabular-nums">{formatMetric("money", dash.fixed.earned_paise)}</strong>
              </span>
              <span>
                {t("analytics.metrics.fixed_remaining.label")}:{" "}
                <strong className="tabular-nums">{formatMetric("money", fixedRemaining)}</strong>
              </span>
            </div>
            <div
              className="mt-2 h-3 rounded-full bg-surface-2"
              role="progressbar"
              aria-label={t("home.fixed")}
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={Math.round(Math.min(dash.fixed.earned_paise / dash.fixed.committed_paise, 1) * 100)}
            >
              <div
                className="h-3 rounded-full bg-success"
                style={{ width: `${Math.min(dash.fixed.earned_paise / dash.fixed.committed_paise, 1) * 100}%` }}
              />
            </div>
          </Card>
        ) : null}

        <section aria-labelledby="home-performance" className="flex flex-col gap-4">
          <div className="flex flex-wrap items-end justify-between gap-2">
            <h2 id="home-performance" className="text-base font-semibold">
              {t("home.performance")}
            </h2>
            <div className="flex flex-wrap items-end gap-2">
              <RangeControl
                preset={range.preset}
                from={range.from}
                to={range.to}
                compare={range.compare}
                today={today}
              />
              <Button asChild size="sm" variant="ghost">
                <a
                  href={`/api/analytics/creator-export?${new URLSearchParams({ ...rangeParams(range), creator: me.creatorId })}`}
                >
                  <Download /> {t("analytics.export")}
                </a>
              </Button>
            </div>
          </div>
          {!dash ? (
            <Card>
              <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
            </Card>
          ) : (
            <>
              <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
                <KpiCard id="clicks" value={dash.current.clicks} previous={prev?.clicks} />
                <KpiCard id="leads" value={dash.current.leads} previous={prev?.leads} href="/creator/leads" />
                <KpiCard id="qualified_leads" value={dash.current.qualified} previous={prev?.qualified} />
                <KpiCard id="enrollments" value={dash.current.enrolled} previous={prev?.enrolled} />
              </div>
              <div className="grid gap-4 lg:grid-cols-2">
                <Card>
                  <CardHeader title={t("home.funnel")} description={t("home.funnelHint")} />
                  <Funnel rows={funnel(dash.current)} labels={funnelLabels} />
                </Card>
                <Card>
                  <CardHeader title={t("home.leadsOverTime")} />
                  {dash.current.leads === 0 ? (
                    <EmptyState title={t("home.noLeads")} description={t("home.noLeadsHint")} />
                  ) : (
                    <LineChart title={t("analytics.metrics.leads.label")} points={series} />
                  )}
                </Card>
              </div>
              <div className="grid gap-4 lg:grid-cols-3">
                <Card>
                  <CardHeader title={t("home.topContent")} description={t("home.topContentHint")} />
                  <BarList
                    empty={t("home.noLeads")}
                    rows={dash.content.map((c, i) => ({
                      key: c.deliverable_id ?? c.link_id ?? String(i),
                      label: c.title ?? t("home.unknownContent"),
                      value: c.leads,
                      note: t("home.enrolledNote", { count: c.enrolled }),
                      href: c.deliverable_id ? `/creator/deliverables/${c.deliverable_id}` : undefined,
                    }))}
                  />
                </Card>
                <Card>
                  <CardHeader title={t("home.programmes")} />
                  <BarList
                    empty={t("home.noLeads")}
                    rows={dash.programmes.map((p) => ({
                      key: String(p.key ?? "none"),
                      label: p.label ?? t("home.noProgramme"),
                      value: p.leads,
                      note: t("home.enrolledNote", { count: p.enrolled }),
                    }))}
                  />
                </Card>
                <Card>
                  <CardHeader title={t("home.platforms")} />
                  <BarList
                    empty={t("home.noLeads")}
                    rows={dash.platforms.map((p) => ({
                      key: p.key ?? "none",
                      label: p.key ? t(`platforms.${p.key}`) : t("home.noPlatform"),
                      value: p.leads,
                      note: t("home.enrolledNote", { count: p.enrolled }),
                    }))}
                  />
                </Card>
              </div>
              <div className="grid gap-4 lg:grid-cols-2">
                <Card>
                  <CardHeader title={t("home.activeDeals")} />
                  {dash.deals.length === 0 ? (
                    <EmptyState title={t("home.noDeals")} description={t("home.noDealsHint")} />
                  ) : (
                    <ul className="flex flex-col divide-y divide-line">
                      {dash.deals.map((d) => (
                        <li key={d.id} className="flex items-center justify-between gap-3 py-2 text-sm">
                          <span className="min-w-0">
                            <Link
                              href={`/creator/deals/${d.id}`}
                              className="font-medium hover:text-primary hover:underline"
                            >
                              {d.title}
                            </Link>
                            {d.campaign_name ? (
                              <span className="block text-xs text-muted">{d.campaign_name}</span>
                            ) : null}
                          </span>
                          <Badge>{t(`deals.statuses.${d.status}`)}</Badge>
                        </li>
                      ))}
                    </ul>
                  )}
                </Card>
                <Card>
                  <CardHeader title={t("home.leaderboard")} />
                  {dash.leaderboard ? (
                    <p className="flex items-center gap-3 text-sm">
                      <Trophy className="size-8 text-accent" aria-hidden />
                      <span>
                        <strong className="text-lg">
                          {t("home.rank", { rank: dash.leaderboard.rank, of: dash.leaderboard.of })}
                        </strong>
                        <span className="block text-muted">
                          {t("home.rankHint", { count: dash.leaderboard.enrolled })}
                        </span>
                      </span>
                    </p>
                  ) : (
                    <p className="text-sm text-muted">
                      {dash.opt_in ? t("home.rankNone") : t("home.leaderboardOptIn")}{" "}
                      {dash.opt_in ? null : (
                        <Link href="/creator/profile" className="text-primary hover:underline">
                          {t("home.openProfile")}
                        </Link>
                      )}
                    </p>
                  )}
                </Card>
              </div>
            </>
          )}
        </section>
      </div>
    </>
  );
}
