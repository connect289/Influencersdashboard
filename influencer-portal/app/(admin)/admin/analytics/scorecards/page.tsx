import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { AnalyticsNav } from "@/components/analytics/analytics-nav";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadProgrammeScorecards, loadScorecardPeriods } from "@/lib/scorecards/data";
import { SCORE_PARTS } from "@/lib/scorecards/score";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("insight.programme.title") };
}

/** Every creator's monthly scorecard for a month, best first (spec 15). */
export default async function ProgrammeScorecardsPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>;
}) {
  const { supabase, me } = await requireStaff("analytics.read");
  const t = await getTranslations();
  const periods = await loadScorecardPeriods(supabase);
  const sp = await searchParams;
  const period = periods.find((p) => p === sp.period) ?? periods[0] ?? null;
  const rows = period ? await loadProgrammeScorecards(supabase, period).catch(() => null) : [];
  return (
    <>
      <PageHeader
        title={t("insight.programme.title")}
        description={t("insight.programme.subtitle")}
        help="/admin/help/influencer-manager#scorecards"
      />
      <AnalyticsNav current="scorecards" permissions={me.permissions} search="" />
      {periods.length > 1 ? (
        <nav className="mb-3 flex flex-wrap gap-1" aria-label={t("insight.programme.periods")}>
          {periods.slice(0, 12).map((p) => (
            <Link
              key={p}
              href={`/admin/analytics/scorecards?period=${p}`}
              aria-current={p === period ? "page" : undefined}
              className={cn(
                "rounded-lg px-2.5 py-1 text-sm",
                p === period ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
              )}
            >
              {p}
            </Link>
          ))}
        </nav>
      ) : null}
      {rows === null ? (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      ) : rows.length === 0 ? (
        <EmptyState title={t("insight.programme.empty")} description={t("insight.programme.emptyHint")} />
      ) : (
        <Card className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-muted">
                <th className="py-2 pr-3 font-medium">{t("insight.programme.creator")}</th>
                <th className="py-2 pr-3 font-medium">{t("insight.tier.title")}</th>
                <th className="py-2 pr-3 text-right font-medium">{t("insight.scorecard.composite")}</th>
                {SCORE_PARTS.map((p) => (
                  <th key={p} className="py-2 pr-3 text-right font-medium">
                    {t(`insight.parts.${p}`)}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {rows.map((r) => (
                <tr key={r.creator_id}>
                  <td className="py-2 pr-3">
                    <Link
                      href={`/admin/creators/${r.creator_id}?tab=scorecard`}
                      className="font-medium hover:underline"
                    >
                      {r.display_name}
                    </Link>
                    {r.handle ? <span className="block text-xs text-muted">@{r.handle}</span> : null}
                  </td>
                  <td className="py-2 pr-3">
                    {r.tier ? <Badge family="progress">{r.tier}</Badge> : <span className="text-muted">–</span>}
                    {r.changed ? (
                      <span className="ml-1 text-xs text-muted">{t("insight.programme.changed")}</span>
                    ) : null}
                  </td>
                  <td className="py-2 pr-3 text-right font-semibold tabular-nums">{r.composite ?? "–"}</td>
                  {SCORE_PARTS.map((p) => (
                    <td key={p} className="py-2 pr-3 text-right tabular-nums">
                      {r.scores[p] ?? "–"}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}
    </>
  );
}
