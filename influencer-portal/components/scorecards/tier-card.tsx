import { Award, Check, Circle } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Card, CardHeader } from "@/components/ui/card";
import type { TierStatus } from "@/lib/scorecards/data";
import { nextTierProgress, type TierBenefits } from "@/lib/scorecards/tiers";

/** The creator's tier, its benefits and what the next tier needs (hidden until Eduwit sets up tiers). */
export async function TierCard({ status }: { status: TierStatus | null }) {
  if (!status || status.tiers.length === 0) return null;
  const t = await getTranslations();
  const current = status.tiers.find((x) => x.id === status.tier_id) ?? null;
  const progress = nextTierProgress(status.tiers, current, {
    score: status.score,
    compliance: status.compliance,
    enrollments_90d: status.enrollments_90d,
    months_active: status.months_active,
  });
  const benefits = (b: TierBenefits) =>
    [
      b.commission_uplift_pct ? t("insight.benefitsShort.uplift", { pct: b.commission_uplift_pct }) : null,
      b.early_access_days ? t("insight.benefitsShort.early", { days: b.early_access_days }) : null,
      b.payout_cycle ? t("insight.benefitsShort.cycle", { cycle: t(`insight.cycles.${b.payout_cycle}`) }) : null,
      b.note ?? null,
    ].filter((x): x is string => !!x);
  const mine = current ? benefits(current.benefits) : [];
  return (
    <Card>
      <CardHeader
        title={
          <span className="inline-flex items-center gap-2">
            <Award className="size-4 text-accent-ink" aria-hidden />
            {current ? t("insight.home.tier", { tier: current.name }) : t("insight.home.noTier")}
          </span>
        }
        description={
          status.score !== null
            ? t("insight.home.score", { score: status.score, period: status.period ?? "" })
            : t("insight.home.noScore")
        }
      />
      {mine.length ? (
        <ul className="mb-3 flex flex-col gap-1 text-sm">
          {mine.map((b) => (
            <li key={b} className="flex items-center gap-2">
              <Check className="size-4 text-success" aria-hidden /> {b}
            </li>
          ))}
        </ul>
      ) : null}
      {progress ? (
        <div className="rounded-xl bg-surface-2 p-3">
          <p className="mb-2 text-sm font-medium">{t("insight.home.next", { tier: progress.tier.name })}</p>
          <ul className="flex flex-col gap-1 text-sm">
            {progress.checks.map((c) => (
              <li key={c.rule} className="flex items-center gap-2">
                {c.met ? (
                  <Check className="size-4 text-success" aria-hidden />
                ) : (
                  <Circle className="size-4 text-muted" aria-hidden />
                )}
                <span className={c.met ? "text-muted" : undefined}>
                  {t(`insight.home.rules.${c.rule}`, { required: c.required, actual: c.actual ?? 0 })}
                </span>
              </li>
            ))}
          </ul>
          {benefits(progress.tier.benefits).length ? (
            <p className="mt-2 text-xs text-muted">
              {t("insight.home.unlocks", { list: benefits(progress.tier.benefits).join(" · ") })}
            </p>
          ) : null}
        </div>
      ) : current ? (
        <p className="text-sm text-muted">{t("insight.home.top")}</p>
      ) : null}
    </Card>
  );
}
