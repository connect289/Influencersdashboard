// One dashboard number: its label with the definition behind an info button, the value, and the change against the
// previous period coloured by whether it is good news for this metric. Optional link to the underlying records.
import Link from "next/link";
import { ArrowDownRight, ArrowRight, ArrowUpRight } from "lucide-react";
import { useTranslations } from "next-intl";
import { delta } from "@/lib/analytics/compute";
import { formatChange, formatMetric } from "@/lib/analytics/format";
import { METRICS, type MetricId } from "@/lib/analytics/metrics";
import { cn } from "@/lib/utils";
import { MetricInfo } from "./metric-info";

export function KpiCard({
  id,
  value,
  previous,
  href,
  hint,
  className,
}: {
  id: MetricId;
  value: number | string | null;
  /** The comparison period's value; leave undefined to hide the comparison. */
  previous?: number | null;
  href?: string;
  hint?: string;
  className?: string;
}) {
  const t = useTranslations();
  const def = METRICS[id];
  const label = t(`analytics.metrics.${id}.label`);
  const d = previous === undefined || typeof value === "string" ? null : delta(value, previous, def.polarity);
  const change = d ? formatChange(d.pct) : null;
  const Arrow = d?.direction === "up" ? ArrowUpRight : d?.direction === "down" ? ArrowDownRight : ArrowRight;
  const heading = (
    <p className="flex items-center gap-1 text-xs text-muted">
      <span>{label}</span>
      <MetricInfo
        label={label}
        definition={t(`analytics.metrics.${id}.definition`)}
        about={t("analytics.about", { metric: label })}
      />
    </p>
  );
  const figures = (
    <>
      <p className="mt-0.5 text-xl font-semibold tabular-nums">{formatMetric(def.unit, value)}</p>
      {d ? (
        <p
          className={cn(
            "mt-0.5 inline-flex items-center gap-0.5 text-xs",
            d.tone === "good" ? "text-success" : d.tone === "bad" ? "text-danger" : "text-muted",
          )}
        >
          <Arrow className="size-3.5" aria-hidden />
          {change ?? `${d.change > 0 ? "+" : ""}${formatMetric(def.unit, d.change)}`}
          <span className="sr-only">
            {t("analytics.vsPrevious", { value: formatMetric(def.unit, previous ?? null) })}
          </span>
          <span aria-hidden className="text-muted">
            {" "}
            {t("analytics.vsPreviousShort")}
          </span>
        </p>
      ) : hint ? (
        <p className="mt-0.5 text-xs text-muted">{hint}</p>
      ) : null}
    </>
  );
  return (
    <div role="group" aria-label={label} className={cn("rounded-xl border border-line bg-surface p-3", className)}>
      {heading}
      {href ? (
        <Link href={href} className="block hover:opacity-80" aria-label={t("analytics.open", { metric: label })}>
          {figures}
        </Link>
      ) : (
        figures
      )}
    </div>
  );
}
