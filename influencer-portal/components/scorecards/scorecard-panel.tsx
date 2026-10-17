import { getTranslations } from "next-intl/server";
import { Badge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { EmptyState, ErrorState } from "@/components/ui/states";
import type { Db } from "@/lib/contracts/data";
import { formatDate, formatDateTime, formatPaise, istToday } from "@/lib/format";
import { loadCreatorScorecards, loadTiers } from "@/lib/scorecards/data";
import { Recommendations } from "./recommendations";
import { ManualTier, RunScorecardButton } from "./scorecard-actions";
import { ScoreBars } from "./score-bars";

const pct = (v: number | null | undefined) => (v === null || v === undefined ? "–" : `${Math.round(v * 1000) / 10}%`);

/** The creator 360 Scorecard tab (spec 15): latest card, monthly trend, tier and its history, renewal suggestions. */
export async function ScorecardPanel({
  db,
  creatorId,
  canRun,
  canManageTier,
}: {
  db: Db;
  creatorId: string;
  canRun: boolean;
  canManageTier: boolean;
}) {
  const t = await getTranslations();
  const [data, tiers] = await Promise.all([
    loadCreatorScorecards(db, creatorId).catch(() => undefined),
    loadTiers(db).catch(() => []),
  ]);
  if (data === undefined)
    return (
      <Card>
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      </Card>
    );
  if (data === null) return null;
  const latest = data.cards[0] ?? null;
  const tier = tiers.find((x) => x.id === data.tier_id) ?? null;
  const monthly = data.cards.filter((c) => c.kind === "monthly");
  const f = latest?.figures ?? {};
  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_340px]">
      <div className="flex flex-col gap-4">
        <Card>
          <CardHeader
            title={t("insight.scorecard.title")}
            description={
              latest
                ? t(latest.kind === "monthly" ? "insight.scorecard.monthly" : "insight.scorecard.onDemand", {
                    period: latest.period,
                    date: formatDateTime(latest.created_at),
                  })
                : t("insight.scorecard.none")
            }
            actions={canRun ? <RunScorecardButton creatorId={creatorId} /> : null}
          />
          {latest ? (
            <div className="grid gap-4 md:grid-cols-[8rem_1fr] md:items-center">
              <div className="text-center">
                <p className="text-4xl font-semibold tabular-nums">{latest.composite ?? "–"}</p>
                <p className="text-xs text-muted">{t("insight.scorecard.composite")}</p>
              </div>
              <ScoreBars scores={latest.scores} />
            </div>
          ) : (
            <EmptyState title={t("insight.scorecard.none")} description={t("insight.scorecard.noneHint")} />
          )}
          {latest ? (
            <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-3">
              <div>
                <dt className="text-xs text-muted">{t("insight.figures.on_time")}</dt>
                <dd>{pct(f.on_time_rate)}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted">{t("insight.figures.revisions")}</dt>
                <dd>{f.avg_revisions ?? "–"}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted">{t("insight.figures.views")}</dt>
                <dd>{f.views_vs_baseline ? `${Math.round(f.views_vs_baseline * 100) / 100}×` : "–"}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted">{t("insight.figures.qualification")}</dt>
                <dd>{pct(f.qualification_rate)}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted">{t("insight.figures.enrolment")}</dt>
                <dd>{pct(f.enrollment_rate)}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted">{t("insight.figures.cpe")}</dt>
                <dd>{f.cost_per_enrollment_paise ? formatPaise(f.cost_per_enrollment_paise) : "–"}</dd>
              </div>
            </dl>
          ) : null}
        </Card>
        <Card>
          <CardHeader title={t("insight.scorecard.trend")} />
          {monthly.length === 0 ? (
            <p className="text-sm text-muted">{t("insight.scorecard.noMonthly")}</p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-muted">
                  <th className="py-1 font-medium">{t("insight.scorecard.period")}</th>
                  <th className="py-1 text-right font-medium">{t("insight.scorecard.composite")}</th>
                  <th className="py-1 pl-3 font-medium">{t("insight.scorecard.tierChange")}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {monthly.map((c) => (
                  <tr key={c.id}>
                    <td className="py-1.5">{c.period}</td>
                    <td className="py-1.5 text-right tabular-nums">{c.composite ?? "–"}</td>
                    <td className="py-1.5 pl-3 text-muted">
                      {c.tier_before !== c.tier_after
                        ? `${tiers.find((x) => x.id === c.tier_before)?.name ?? t("insight.noTier")} → ${tiers.find((x) => x.id === c.tier_after)?.name ?? t("insight.noTier")}`
                        : ""}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
      </div>
      <div className="flex flex-col gap-4">
        <Card>
          <CardHeader
            title={t("insight.tier.title")}
            actions={tier ? <Badge family="progress">{tier.name}</Badge> : <Badge>{t("insight.noTier")}</Badge>}
          />
          {data.state?.manual_until ? (
            <p className="mb-2 text-sm">
              {t("insight.manual.active", {
                date: formatDate(data.state.manual_until),
                reason: data.state.manual_reason ?? "",
              })}
            </p>
          ) : data.state && data.state.months_below > 0 ? (
            <p className="mb-2 text-sm text-muted">
              {t("insight.tier.monthsBelow", { count: data.state.months_below })}
            </p>
          ) : null}
          {canManageTier ? (
            <ManualTier
              creatorId={creatorId}
              tiers={tiers.filter((x) => x.active !== false).map((x) => ({ id: x.id, name: x.name }))}
              manualUntil={data.state?.manual_until ?? null}
              today={istToday()}
            />
          ) : null}
          {data.history.length ? (
            <ul className="mt-3 flex flex-col gap-1 text-xs text-muted">
              {data.history.slice(0, 8).map((h) => (
                <li key={h.id}>
                  {formatDate(h.created_at)} ·{" "}
                  {t(`insight.history.${h.reason}`, {
                    from: h.from_tier ?? t("insight.noTier"),
                    to: h.to_tier ?? t("insight.noTier"),
                  })}
                  {h.note ? ` (${h.note})` : ""}
                  {h.by ? ` · ${h.by}` : ""}
                </li>
              ))}
            </ul>
          ) : null}
        </Card>
        <Recommendations data={data} tiers={tiers} />
      </div>
    </div>
  );
}
