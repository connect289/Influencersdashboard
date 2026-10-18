// Small server-rendered charts for the dashboards, drawn as SVG and plain bars so they need no chart library, work
// without JavaScript and print well. Each has a text summary for screen readers and a "Show data" table.
import Link from "next/link";
import { useTranslations } from "next-intl";
import type { FunnelRow } from "@/lib/analytics/compute";
import { formatMetric } from "@/lib/analytics/format";
import type { MetricUnit } from "@/lib/analytics/metrics";
import { cn } from "@/lib/utils";

const shortDate = new Intl.DateTimeFormat("en-IN", { day: "2-digit", month: "short", timeZone: "UTC" });
const dayLabel = (d: string) => shortDate.format(new Date(`${d}T00:00:00Z`));

function DataTable({ head, rows }: { head: readonly string[]; rows: readonly (readonly string[])[] }) {
  const t = useTranslations();
  return (
    <details className="mt-2 text-xs">
      <summary className="cursor-pointer text-muted hover:text-ink">{t("analytics.showData")}</summary>
      <div className="mt-1 max-h-64 overflow-auto">
        <table className="w-full border-collapse">
          <thead>
            <tr>
              {head.map((h) => (
                <th key={h} scope="col" className="border-b border-line px-2 py-1 text-left font-medium text-muted">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={i}>
                {r.map((c, j) => (
                  <td key={j} className="border-b border-line px-2 py-1 tabular-nums">
                    {c}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </details>
  );
}

/** A line over time, with the previous period as a dashed line when given (aligned by position). */
export function LineChart({
  title,
  points,
  previous,
  unit = "count",
}: {
  title: string;
  points: readonly { at: string; value: number }[];
  previous?: readonly { at: string; value: number }[];
  unit?: MetricUnit;
}) {
  const t = useTranslations();
  const W = 600;
  const H = 180;
  const P = { l: 8, r: 8, t: 12, b: 22 };
  const all = [...points.map((p) => p.value), ...(previous ?? []).map((p) => p.value)];
  const max = Math.max(1, ...all);
  const n = Math.max(points.length, 1);
  const x = (i: number) => P.l + (n === 1 ? (W - P.l - P.r) / 2 : (i * (W - P.l - P.r)) / (n - 1));
  const y = (v: number) => P.t + (H - P.t - P.b) * (1 - v / max);
  const path = (ps: readonly { value: number }[]) =>
    ps.map((p, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(p.value).toFixed(1)}`).join(" ");
  const total = points.reduce((s, p) => s + p.value, 0);
  const summary = t("analytics.chartSummary", {
    title,
    total: formatMetric(unit, total),
    from: points[0] ? dayLabel(points[0].at) : "",
    to: points.at(-1) ? dayLabel(points.at(-1)?.at ?? "") : "",
    max: formatMetric(unit, Math.max(0, ...points.map((p) => p.value))),
  });
  return (
    <figure>
      <figcaption className="sr-only">{summary}</figcaption>
      <svg viewBox={`0 0 ${W} ${H}`} className="h-44 w-full text-primary" role="img" aria-label={summary}>
        <line x1={P.l} x2={W - P.r} y1={H - P.b} y2={H - P.b} className="stroke-[var(--line-strong)]" strokeWidth={1} />
        <line x1={P.l} x2={W - P.r} y1={P.t} y2={P.t} className="stroke-[var(--line)]" strokeDasharray="2 4" />
        <text x={W - P.r} y={P.t - 2} textAnchor="end" className="fill-[var(--faint)] text-[10px]">
          {formatMetric(unit, max)}
        </text>
        {previous && previous.length > 1 ? (
          <path
            d={path(previous.slice(0, n))}
            fill="none"
            className="stroke-[var(--faint)]"
            strokeWidth={1.5}
            strokeDasharray="4 4"
          />
        ) : null}
        {points.length > 1 ? (
          <path d={path(points)} fill="none" stroke="currentColor" strokeWidth={2.5} strokeLinejoin="round" />
        ) : null}
        {points.length <= 31
          ? points.map((p, i) => <circle key={p.at} cx={x(i)} cy={y(p.value)} r={2.5} fill="currentColor" />)
          : null}
        {points[0] ? (
          <text x={P.l} y={H - 6} className="fill-[var(--faint)] text-[10px]">
            {dayLabel(points[0].at)}
          </text>
        ) : null}
        {points.length > 1 ? (
          <text x={W - P.r} y={H - 6} textAnchor="end" className="fill-[var(--faint)] text-[10px]">
            {dayLabel(points.at(-1)?.at ?? "")}
          </text>
        ) : null}
      </svg>
      {previous ? (
        <p className="flex gap-4 text-xs text-muted">
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-0.5 w-4 bg-primary" aria-hidden /> {t("analytics.thisPeriod")}
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="inline-block w-4 border-t border-dashed border-faint" aria-hidden />{" "}
            {t("analytics.previousPeriod")}
          </span>
        </p>
      ) : null}
      <DataTable
        head={[t("analytics.date"), title, ...(previous ? [t("analytics.previousPeriod")] : [])]}
        rows={points.map((p, i) => [
          dayLabel(p.at),
          formatMetric(unit, p.value),
          ...(previous ? [formatMetric(unit, previous[i]?.value ?? null)] : []),
        ])}
      />
    </figure>
  );
}

export interface BarRow {
  key: string;
  label: string;
  value: number;
  /** A second figure shown after the bar (for example enrolments next to leads). */
  note?: string;
  href?: string;
}

/** Horizontal bars, largest first, for a breakdown (programmes, platforms, campaigns …). */
export function BarList({
  rows,
  unit = "count",
  empty,
  limit = 8,
}: {
  rows: readonly BarRow[];
  unit?: MetricUnit;
  empty: string;
  limit?: number;
}) {
  if (!rows.length) return <p className="text-sm text-muted">{empty}</p>;
  const sorted = [...rows].sort((a, b) => b.value - a.value).slice(0, limit);
  const max = Math.max(1, ...sorted.map((r) => Math.abs(r.value)));
  return (
    <ul className="flex flex-col gap-2">
      {sorted.map((r) => {
        const label = r.href ? (
          <Link href={r.href} className="truncate hover:text-primary hover:underline">
            {r.label}
          </Link>
        ) : (
          <span className="truncate">{r.label}</span>
        );
        return (
          <li key={r.key} className="text-sm">
            <div className="flex items-baseline justify-between gap-3">
              {label}
              <span className="shrink-0 tabular-nums">
                {formatMetric(unit, r.value)}
                {r.note ? <span className="ml-2 text-xs text-muted">{r.note}</span> : null}
              </span>
            </div>
            <div className="mt-1 h-2 rounded-full bg-surface-2" aria-hidden>
              <div
                className={cn("h-2 rounded-full", r.value < 0 ? "bg-danger" : "bg-primary")}
                style={{ width: `${Math.max(2, (Math.abs(r.value) / max) * 100)}%` }}
              />
            </div>
          </li>
        );
      })}
    </ul>
  );
}

/** The lead funnel: each step's count, its share of the previous step and of clicks. */
export function Funnel({ rows, labels }: { rows: readonly FunnelRow[]; labels: Record<string, string> }) {
  const t = useTranslations();
  const max = Math.max(1, ...rows.map((r) => r.count));
  return (
    <ol className="flex flex-col gap-2">
      {rows.map((r) => (
        <li key={r.step} className="text-sm">
          <div className="flex items-baseline justify-between gap-3">
            <span>{labels[r.step] ?? r.step}</span>
            <span className="shrink-0 tabular-nums">
              {formatMetric("count", r.count)}
              {r.from_previous !== null ? (
                <span className="ml-2 text-xs text-muted">
                  {t("analytics.ofPrevious", { pct: formatMetric("percent", r.from_previous) })}
                </span>
              ) : null}
            </span>
          </div>
          <div className="mt-1 h-3 rounded-md bg-surface-2" aria-hidden>
            <div className="h-3 rounded-md bg-accent" style={{ width: `${Math.max(1, (r.count / max) * 100)}%` }} />
          </div>
        </li>
      ))}
    </ol>
  );
}
