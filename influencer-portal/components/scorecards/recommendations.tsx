import { Lightbulb, ShieldAlert, Info } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Card, CardHeader } from "@/components/ui/card";
import type { CreatorScorecards, TierRow } from "@/lib/scorecards/data";
import { recommend } from "@/lib/scorecards/recommend";
import type { Scorecard } from "@/lib/scorecards/score";

/** Renewal suggestions from the latest monthly scorecard (spec 15); staff decide, nothing is applied. */
export async function Recommendations({ data, tiers }: { data: CreatorScorecards; tiers: TierRow[] }) {
  const t = await getTranslations();
  const latest = data.cards.find((c) => c.kind === "monthly") ?? null;
  const card: Scorecard | null = latest
    ? {
        composite: latest.composite,
        scores: {
          delivery: latest.scores.delivery ?? null,
          content: latest.scores.content ?? null,
          lead_quality: latest.scores.lead_quality ?? null,
          economics: latest.scores.economics ?? null,
          compliance: latest.scores.compliance ?? null,
        },
        figures: {
          on_time_rate: latest.figures.on_time_rate ?? null,
          avg_revisions: latest.figures.avg_revisions ?? null,
          views_vs_baseline: latest.figures.views_vs_baseline ?? null,
          qualification_rate: latest.figures.qualification_rate ?? null,
          junk_rate: latest.figures.junk_rate ?? null,
          duplicate_rate: latest.figures.duplicate_rate ?? null,
          enrollment_rate: latest.figures.enrollment_rate ?? null,
          cost_per_enrollment_paise: latest.figures.cost_per_enrollment_paise ?? null,
          net_roi: latest.figures.net_roi ?? null,
        },
      }
    : null;
  const num = (k: string) => {
    const v = latest?.facts[k];
    return typeof v === "number" ? v : 0;
  };
  const items = recommend({
    latest: card,
    leads: num("leads"),
    deliverables_due: num("due"),
    tier: tiers.find((x) => x.id === data.tier_id) ?? null,
  });
  const icon = { suggest: Lightbulb, caution: ShieldAlert, info: Info } as const;
  return (
    <Card>
      <CardHeader
        title={t("insight.recommend.title")}
        description={latest ? t("insight.recommend.basis", { period: latest.period }) : t("insight.recommend.hint")}
      />
      <ul className="flex flex-col gap-2">
        {items.map((r) => {
          const Icon = icon[r.kind];
          return (
            <li key={r.code} className="flex gap-2 rounded-xl bg-surface-2 p-3 text-sm">
              <Icon className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden />
              <span>
                <span className="block font-medium">{t(`insight.recommend.codes.${r.code}.title`)}</span>
                <span className="block text-muted">{t(`insight.recommend.codes.${r.code}.why`, r.because)}</span>
              </span>
            </li>
          );
        })}
      </ul>
    </Card>
  );
}
