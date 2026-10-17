import { getTranslations } from "next-intl/server";
import { SCORE_PARTS } from "@/lib/scorecards/score";
import { cn } from "@/lib/utils";

/** The five sub-scores as labelled bars (a part without data says so). */
export async function ScoreBars({ scores }: { scores: Record<string, number | null> }) {
  const t = await getTranslations();
  return (
    <ul className="flex flex-col gap-2">
      {SCORE_PARTS.map((p) => {
        const v = scores[p] ?? null;
        return (
          <li key={p} className="grid grid-cols-[9rem_1fr_3rem] items-center gap-2 text-sm">
            <span>{t(`insight.parts.${p}`)}</span>
            <span className="h-2 overflow-hidden rounded-full bg-surface-2" aria-hidden>
              {v !== null ? (
                <span
                  className={cn(
                    "block h-full rounded-full",
                    v >= 70 ? "bg-success" : v >= 40 ? "bg-accent" : "bg-danger",
                  )}
                  style={{ width: `${v}%` }}
                />
              ) : null}
            </span>
            <span className="text-right tabular-nums">{v === null ? t("insight.noData") : v}</span>
          </li>
        );
      })}
    </ul>
  );
}
