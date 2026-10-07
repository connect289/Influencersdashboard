import Link from "next/link";
import { ArrowDownRight, ArrowUpRight, Clock, TriangleAlert } from "lucide-react";
import { cn } from "@/components/ui/cn";
import {
  delta, DIM_LABEL, dimLabel, drillHref, formatValue, pivot, rowFilters, sankeyLayout, STATE_TILES, TIME_DIMS,
  type MetricResult, type Widget, type WidgetData,
} from "@/lib/analytics";
import { relativeTime } from "@/lib/format";

/** One dashboard widget (B13.3). Server-rendered SVG; every number links to the rows behind it. */

const PALETTE = ["var(--primary)", "#F5A800", "#0EA5E9", "#10B981", "#A855F7", "#EF4444", "#64748B", "#14B8A6", "#F97316", "#6366F1"];
const color = (i: number) => PALETTE[i % PALETTE.length]!;

function Empty({ text = "No data in this period" }: { text?: string }) {
  return <p className="flex h-full min-h-16 items-center justify-center text-[12.5px] text-subtle">{text}</p>;
}

function Kpi({ s, filters, compact }: { s: MetricResult; filters: Record<string, string[]>; compact?: boolean }) {
  const d = delta(s.total.value, s.total.prev, s.metric.higher_is_better, s.metric.unit);
  return (
    <div className="flex h-full flex-col justify-between">
      <Link href={drillHref(s.metric.key, filters, s.from, s.to)} className={cn("tabular font-semibold tracking-tight text-fg hover:underline", compact ? "text-xl" : "text-[28px] leading-9")}>
        {formatValue(s.total.value, s.metric.unit, true)}
      </Link>
      {d ? (
        <p className={cn("flex min-w-0 items-center gap-1 whitespace-nowrap text-[12px]", d.tone === "good" ? "text-success" : d.tone === "bad" ? "text-danger" : "text-subtle")}
           title="Against the previous period of the same length">
          {d.tone === "flat" ? null : d.text.startsWith("+") ? <ArrowUpRight className="size-3.5 shrink-0" /> : <ArrowDownRight className="size-3.5 shrink-0" />}
          {d.text} <span className="truncate text-subtle">vs before</span>
        </p>
      ) : <p className="text-[12px] text-subtle">&nbsp;</p>}
    </div>
  );
}

function Gauge({ s, target }: { s: MetricResult; target?: number }) {
  const v = s.total.value ?? 0;
  const max = target && target > 0 ? target : s.metric.unit === "pct" ? 1 : Math.max(v, 1);
  const frac = Math.max(0, Math.min(1, v / max));
  const a = Math.PI * (1 - frac);
  const x = 50 + 40 * Math.cos(a), y = 50 - 40 * Math.sin(a);
  return (
    <div className="flex h-full flex-col items-center justify-center">
      <svg viewBox="0 0 100 58" className="w-full max-w-[180px]" role="img" aria-label={`${formatValue(v, s.metric.unit)} of ${formatValue(max, s.metric.unit)}`}>
        <path d="M10 50 A40 40 0 0 1 90 50" fill="none" stroke="var(--border)" strokeWidth="8" strokeLinecap="round" />
        {frac > 0 && <path d={`M10 50 A40 40 0 0 1 ${x.toFixed(2)} ${y.toFixed(2)}`} fill="none" stroke={frac >= 1 ? "var(--success)" : "var(--primary)"} strokeWidth="8" strokeLinecap="round" />}
      </svg>
      <p className="tabular -mt-3 text-lg font-semibold text-fg">{formatValue(v, s.metric.unit)}</p>
      {target !== undefined && <p className="text-[11.5px] text-subtle">target {formatValue(target, s.metric.unit)}</p>}
    </div>
  );
}

function Bars({ s, filters, horizontal }: { s: MetricResult; filters: Record<string, string[]>; horizontal?: boolean }) {
  const rows = s.rows.slice(0, horizontal ? 12 : 31);
  if (!rows.length) return <Empty />;
  const max = Math.max(...rows.map((r) => r.value ?? 0), 0) || 1;
  const dim = s.dims[0]!;
  return (
    <ul className="space-y-1.5">
      {rows.map((r, i) => (
        <li key={i} className="grid grid-cols-[minmax(0,40%)_minmax(0,1fr)_auto] items-center gap-2 text-[12px]">
          <span className="truncate text-muted" title={dimLabel(dim, r.d?.[0], s.labels)}>{dimLabel(dim, r.d?.[0], s.labels)}</span>
          <span className="h-2 overflow-hidden rounded-full bg-surface-2"><span className="block h-full rounded-full" style={{ width: `${Math.max(1, ((r.value ?? 0) / max) * 100)}%`, background: color(0) }} /></span>
          <Link href={drillHref(s.metric.key, rowFilters(filters, s.dims, r.d), s.from, s.to)} className="tabular text-right text-fg hover:underline">{formatValue(r.value, s.metric.unit, true)}</Link>
        </li>
      ))}
    </ul>
  );
}

/** Vertical bars over time or categories; grouped/stacked by a second breakdown. */
function Columns({ s, stacked }: { s: MetricResult; stacked?: boolean }) {
  if (!s.rows.length) return <Empty />;
  const two = s.dims.length === 2;
  const p = two ? pivot(s) : { rows: s.rows.map((r) => r.d?.[0] ?? ""), cols: [""], get: (r: string) => s.rows.find((x) => (x.d?.[0] ?? "") === r)?.value ?? null, max: 0 };
  const xs = TIME_DIMS.has(s.dims[0]!) ? [...p.rows].sort() : p.rows;
  const series = p.cols;
  const totals = xs.map((x) => series.reduce((a, c) => a + (p.get(x, c) ?? 0), 0));
  const max = Math.max(1e-9, ...(stacked ? totals : xs.flatMap((x) => series.map((c) => p.get(x, c) ?? 0))));
  const W = 600, H = 160, bw = W / Math.max(xs.length, 1);
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H + 18}`} className="h-auto w-full" role="img" aria-label={s.metric.label}>
        {xs.map((x, i) => {
          let acc = 0;
          return series.map((c, j) => {
            const v = p.get(x, c) ?? 0;
            const h = (v / max) * H;
            const gw = stacked || !two ? bw * 0.7 : (bw * 0.8) / series.length;
            const gx = i * bw + (stacked || !two ? bw * 0.15 : bw * 0.1 + j * gw);
            const y = stacked ? H - acc - h : H - h;
            acc += stacked ? h : 0;
            return <rect key={`${i}-${j}`} x={gx} y={y} width={Math.max(gw - 1, 1)} height={Math.max(h, 0)} fill={color(two ? j : 0)} rx="1.5">
              <title>{`${dimLabel(s.dims[0]!, x, s.labels)}${two ? ` · ${dimLabel(s.dims[1]!, c, s.labels)}` : ""}: ${formatValue(v, s.metric.unit)}`}</title></rect>;
          });
        })}
        {xs.map((x, i) => (xs.length <= 12 || i % Math.ceil(xs.length / 12) === 0) && (
          <text key={x} x={i * bw + bw / 2} y={H + 13} textAnchor="middle" className="fill-[var(--subtle)] text-[10px]">{dimLabel(s.dims[0]!, x, s.labels).slice(0, 12)}</text>
        ))}
      </svg>
      {two && <Legend items={series.map((c) => dimLabel(s.dims[1]!, c, s.labels))} />}
    </div>
  );
}

function Legend({ items }: { items: string[] }) {
  return (
    <ul className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-[11px] text-muted">
      {items.slice(0, 10).map((x, i) => <li key={x + i} className="flex items-center gap-1"><span className="size-2 rounded-sm" style={{ background: color(i) }} />{x}</li>)}
    </ul>
  );
}

function Line({ s }: { s: MetricResult }) {
  if (!s.rows.length) return <Empty />;
  const two = s.dims.length === 2;
  const p = two ? pivot(s) : null;
  const xs = (p ? [...p.rows] : s.rows.map((r) => r.d?.[0] ?? "")).sort();
  const series = p ? p.cols : [""];
  const val = (x: string, c: string) => (p ? p.get(x, c) : s.rows.find((r) => (r.d?.[0] ?? "") === x)?.value ?? null);
  const max = Math.max(1e-9, ...xs.flatMap((x) => series.map((c) => val(x, c) ?? 0)));
  const W = 600, H = 150;
  const px = (i: number) => (xs.length === 1 ? W / 2 : (i / (xs.length - 1)) * (W - 20) + 10);
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H + 18}`} className="h-auto w-full" role="img" aria-label={s.metric.label}>
        <line x1="0" x2={W} y1={H} y2={H} stroke="var(--border)" />
        {series.map((c, j) => (
          <g key={c || "one"}>
            <polyline fill="none" stroke={color(j)} strokeWidth="2" points={xs.map((x, i) => `${px(i)},${H - ((val(x, c) ?? 0) / max) * (H - 10)}`).join(" ")} />
            {xs.map((x, i) => <circle key={x} cx={px(i)} cy={H - ((val(x, c) ?? 0) / max) * (H - 10)} r="2.5" fill={color(j)}><title>{`${dimLabel(s.dims[0]!, x, s.labels)}: ${formatValue(val(x, c), s.metric.unit)}`}</title></circle>)}
          </g>
        ))}
        {xs.map((x, i) => (xs.length <= 10 || i % Math.ceil(xs.length / 10) === 0) && (
          <text key={x} x={px(i)} y={H + 13} textAnchor={i === 0 && xs.length > 1 ? "start" : i === xs.length - 1 && xs.length > 1 ? "end" : "middle"} className="fill-[var(--subtle)] text-[10px]">{dimLabel(s.dims[0]!, x, s.labels)}</text>
        ))}
      </svg>
      {two && <Legend items={series.map((c) => dimLabel(s.dims[1]!, c, s.labels))} />}
    </div>
  );
}

function Funnel({ series, filters }: { series: MetricResult[]; filters: Record<string, string[]> }) {
  const max = Math.max(1e-9, ...series.map((s) => s.total.value ?? 0));
  return (
    <ul className="space-y-1.5">
      {series.map((s, i) => (
        <li key={s.metric.key} className="text-[12px]">
          <div className="mx-auto flex items-center justify-between rounded-md px-2 py-1.5 text-white" style={{ width: `${Math.max(30, ((s.total.value ?? 0) / max) * 100)}%`, background: color(i) }}>
            <span className="truncate">{s.metric.label}</span>
            <Link href={drillHref(s.metric.key, filters, s.from, s.to)} className="tabular font-semibold hover:underline">{formatValue(s.total.value, s.metric.unit)}</Link>
          </div>
        </li>
      ))}
    </ul>
  );
}

function Heatmap({ s, filters }: { s: MetricResult; filters: Record<string, string[]> }) {
  if (!s.rows.length) return <Empty />;
  const p = pivot(s);
  const rows = TIME_DIMS.has(s.dims[0]!) ? [...p.rows].sort() : p.rows;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-[11.5px]">
        <thead><tr><th />{p.cols.map((c) => <th key={c} className="whitespace-nowrap px-1 pb-1 text-left font-medium text-subtle">{dimLabel(s.dims[1]!, c, s.labels)}</th>)}</tr></thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r}>
              <th scope="row" className="whitespace-nowrap pr-2 text-left font-normal text-muted">{dimLabel(s.dims[0]!, r, s.labels)}</th>
              {p.cols.map((c) => {
                const v = p.get(r, c);
                const a = v === null || p.max === 0 ? 0 : 0.12 + 0.75 * (v / p.max);
                return (
                  <td key={c} className="p-0.5">
                    {v === null ? <span className="block rounded bg-surface-2 px-1.5 py-1 text-center text-subtle">·</span>
                      : <Link href={drillHref(s.metric.key, rowFilters(filters, s.dims, [r, c]), s.from, s.to)} className="tabular block rounded px-1.5 py-1 text-center text-fg hover:ring-1 hover:ring-[var(--ring)]"
                              style={{ background: `color-mix(in srgb, var(--primary) ${Math.round(a * 100)}%, transparent)` }}>{formatValue(v, s.metric.unit, true)}</Link>}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Several metrics side by side for one breakdown, with conditional colouring against each column's best value. */
function MultiTable({ series, filters, sort }: { series: MetricResult[]; filters: Record<string, string[]>; sort?: string }) {
  const s0 = series[0];
  if (!s0 || series.every((s) => !s.rows.length)) return <Empty />;
  const dim = s0.dims[0]!;
  const keys = [...new Set(series.flatMap((s) => s.rows.map((r) => r.d?.[0] ?? "")))];
  const val = (s: MetricResult, k: string) => s.rows.find((r) => (r.d?.[0] ?? "") === k)?.value ?? null;
  const sortS = series.find((s) => s.metric.key === sort) ?? s0;
  keys.sort((a, b) => (val(sortS, b) ?? -Infinity) - (val(sortS, a) ?? -Infinity));
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[480px] text-left text-[12px]">
        <thead className="text-[10.5px] uppercase tracking-wider text-subtle">
          <tr className="border-b border-border"><th className="py-1.5 pr-2 font-medium">{DIM_LABEL[dim] ?? dim}</th>
            {series.map((s) => <th key={s.metric.key} className="px-2 py-1.5 text-right font-medium">{s.metric.label}</th>)}</tr>
        </thead>
        <tbody className="divide-y divide-border">
          {keys.slice(0, 25).map((k) => (
            <tr key={k}>
              <td className="max-w-[200px] truncate py-1.5 pr-2 text-fg">{dimLabel(dim, k, s0.labels)}</td>
              {series.map((s) => {
                const vals = keys.map((x) => val(s, x)).filter((x): x is number => x !== null);
                const best = s.metric.higher_is_better ? Math.max(...vals) : Math.min(...vals);
                const v = val(s, k);
                return (
                  <td key={s.metric.key} className={cn("tabular px-2 py-1.5 text-right", v !== null && v === best && vals.length > 1 ? "font-semibold text-success" : "text-muted")}>
                    {v === null ? "—" : <Link href={drillHref(s.metric.key, rowFilters(filters, s.dims, [k]), s.from, s.to)} className="hover:underline">{formatValue(v, s.metric.unit, true)}</Link>}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Sankey({ series }: { series: MetricResult[] }) {
  if (series.every((s) => !s.rows.length)) return <Empty />;
  const H = 200, W = 600;
  const { nodes, links, steps } = sankeyLayout(series, H);
  const colX = (step: number) => (steps === 1 ? 0 : (step / (steps - 1)) * (W - 130));
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const dims = [series[0]!.dims[0]!, ...series.map((s) => s.dims[1]!)];
  const labels = series[0]!.labels;
  return (
    <div className="overflow-x-auto">
    <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full min-w-[540px]" role="img" aria-label="Flow">
      {links.map((l, i) => {
        const a = byId.get(l.from)!, b = byId.get(l.to)!;
        const x0 = colX(a.step) + 10, x1 = colX(b.step);
        const mx = (x0 + x1) / 2;
        return <path key={i} d={`M${x0},${l.y0 + l.h / 2} C${mx},${l.y0 + l.h / 2} ${mx},${l.y1 + l.h / 2} ${x1},${l.y1 + l.h / 2}`}
                     fill="none" stroke={color(nodes.filter((n) => n.step === 0).findIndex((n) => n.id === l.from) >= 0 ? nodes.filter((n) => n.step === 0).findIndex((n) => n.id === l.from) : i)}
                     strokeOpacity="0.28" strokeWidth={Math.max(l.h, 1)}><title>{`${dimLabel(dims[a.step]!, a.label, labels)} → ${dimLabel(dims[b.step]!, b.label, labels)}: ${l.value}`}</title></path>;
      })}
      {nodes.map((n) => (
        <g key={n.id}>
          <rect x={colX(n.step)} y={n.y} width="10" height={n.h} rx="2" fill="var(--primary)" />
          <text x={colX(n.step) + 14} y={n.y + n.h / 2 + 3} className="fill-[var(--fg)] text-[10px]">{dimLabel(dims[n.step]!, n.label, labels).slice(0, 18)} · {Math.round(n.value)}</text>
        </g>
      ))}
    </svg>
    </div>
  );
}

function IndiaMap({ s, filters }: { s: MetricResult; filters: Record<string, string[]> }) {
  const byState = new Map(s.rows.map((r) => [r.d?.[0] ?? "", r.value ?? 0]));
  const max = Math.max(1e-9, ...byState.values());
  const other = s.rows.filter((r) => !STATE_TILES[r.d?.[0] ?? ""]).reduce((a, r) => a + (r.value ?? 0), 0);
  return (
    <div>
      <svg viewBox="0 0 330 250" className="h-auto w-full max-w-[360px]" role="img" aria-label={`${s.metric.label} by state`}>
        {Object.entries(STATE_TILES).map(([name, [cx, cy, code]]) => {
          const v = byState.get(name) ?? 0;
          return (
            <a key={name} href={v ? drillHref(s.metric.key, { ...filters, state: [name] }, s.from, s.to) : undefined}>
              <rect x={cx * 30} y={cy * 30} width="27" height="27" rx="4" fill={v ? `color-mix(in srgb, var(--primary) ${Math.round(15 + 80 * (v / max))}%, transparent)` : "var(--surface-2)"} />
              <text x={cx * 30 + 13.5} y={cy * 30 + 17} textAnchor="middle" className={cn("text-[8.5px]", v / max > 0.5 ? "fill-white" : "fill-[var(--muted)]")}>{code}</text>
              <title>{`${name}: ${formatValue(v, s.metric.unit)}`}</title>
            </a>
          );
        })}
      </svg>
      {other > 0 && <p className="text-[11px] text-subtle">Unknown or other: {formatValue(other, s.metric.unit)}</p>}
    </div>
  );
}

function SlaTimers({ rows }: { rows: Record<string, unknown>[] }) {
  if (!rows.length) return <Empty text="No open SLAs" />;
  return (
    <ul className="divide-y divide-border text-[12px]">
      {rows.map((r) => {
        const due = new Date(String(r.due_at));
        const late = due.getTime() < Date.now();
        return (
          <li key={String(r.id)} className="flex flex-wrap items-center gap-x-2 gap-y-0.5 py-1.5">
            <Clock className={cn("size-3.5 shrink-0", late ? "text-danger" : "text-subtle")} />
            <Link href={`/leads?lead=${r.lead_id}`} className="text-info hover:underline">Lead #{String(r.lead_id)}</Link>
            <span className="text-muted">{String(r.partner)} · {String(r.sla).replace(/_/g, " ")}</span>
            <span className={cn("tabular ml-auto whitespace-nowrap", late ? "text-danger" : "text-fg")}>{late ? `overdue ${relativeTime(due.toISOString())}` : `due in ${untilShort(due)}`}</span>
          </li>
        );
      })}
    </ul>
  );
}

function untilShort(d: Date): string {
  const m = Math.max(1, Math.round((d.getTime() - Date.now()) / 60000));
  return m < 60 ? `${m} min` : m < 48 * 60 ? `${Math.round(m / 60)} h` : `${Math.round(m / 1440)} days`;
}

const ALERT_LABEL: Record<string, string> = {
  "alert.partner_auto_paused": "Partner paused automatically", "alert.sla_breach": "SLA breach", "alert.ncpl_drop": "NCPL drop",
  "alert.model_fallback": "ML model fell back", "alert.reconciliation_items": "Reconciliation items", "alert.partner_bad_signature": "Bad webhook signature",
  "alert.notification_failed": "Notification failed", "alert.ai_budget": "AI budget reached", "alert.ai_run_failed": "AI run failed",
  "alert.schedule_failed": "Scheduled report failed", "alert.metric_invalid": "Metric alert broken", "routing.error": "Routing error",
};
function alertLabel(r: Record<string, unknown>): string {
  const type = String(r.type);
  const name = (r.payload as { name?: unknown } | null)?.name;
  if (type === "alert.metric") return typeof name === "string" && name ? `Metric alert: ${name}` : "Metric alert";
  const t = ALERT_LABEL[type] ?? type.replace(/^alert\./, "").replace(/_/g, " ");
  return t.charAt(0).toUpperCase() + t.slice(1);
}

function Alerts({ rows }: { rows: Record<string, unknown>[] }) {
  if (!rows.length) return <Empty text="No alerts" />;
  return (
    <ul className="divide-y divide-border text-[12px]">
      {rows.map((r, i) => (
        <li key={i} className="flex gap-2 py-1.5">
          <TriangleAlert className="mt-0.5 size-3.5 shrink-0 text-warning" />
          <span className="min-w-0 flex-1"><span className="text-fg">{alertLabel(r)}</span>
            {r.partner ? <span className="text-muted"> · {String(r.partner)}</span> : null}</span>
          <span className="shrink-0 text-subtle">{relativeTime(String(r.at))}</span>
        </li>
      ))}
    </ul>
  );
}

export function WidgetBody({ w, data, filters }: { w: Widget; data: WidgetData | undefined; filters: Record<string, string[]> }) {
  if (w.type === "text") return <p className="whitespace-pre-line text-[13px] text-muted">{w.text}</p>;
  if (!data) return <Empty text="Loading…" />;
  if (data.error) return <p className="text-[12.5px] text-danger">{data.error}</p>;
  if (w.type === "sla_timers") return <SlaTimers rows={data.rows ?? []} />;
  if (w.type === "alerts") return <Alerts rows={data.rows ?? []} />;
  const series = data.series ?? [];
  const s = series[0];
  if (!s) return <Empty />;
  const f = { ...filters, ...(w.filters ?? {}) };
  switch (w.type) {
    case "kpi": return <Kpi s={s} filters={f} compact={w.h === 1 && w.w <= 2} />;
    case "gauge": return <Gauge s={s} target={w.target} />;
    case "leaderboard": return <Bars s={s} filters={f} horizontal />;
    case "bar": return s.dims.length === 1 && !TIME_DIMS.has(s.dims[0]!) ? <Bars s={s} filters={f} horizontal /> : <Columns s={s} />;
    case "stacked": return <Columns s={s} stacked />;
    case "line": return <Line s={s} />;
    case "funnel": return <Funnel series={series} filters={f} />;
    case "heatmap": return <Heatmap s={s} filters={f} />;
    case "table": return <MultiTable series={series} filters={f} sort={w.sort} />;
    case "sankey": return <Sankey series={series} />;
    case "map": return <IndiaMap s={s} filters={f} />;
    default: return <Empty />;
  }
}

const SPAN: Record<number, string> = {
  1: "md:col-span-1", 2: "md:col-span-2", 3: "md:col-span-3", 4: "md:col-span-4", 5: "md:col-span-5", 6: "md:col-span-6",
  7: "md:col-span-7", 8: "md:col-span-8", 9: "md:col-span-9", 10: "md:col-span-10", 11: "md:col-span-11", 12: "md:col-span-12",
};
const ROWS: Record<number, string> = { 1: "md:min-h-[118px]", 2: "md:min-h-[250px]", 3: "md:min-h-[360px]", 4: "md:min-h-[470px]" };

export function WidgetCard({ w, data, filters, children }: { w: Widget; data: WidgetData | undefined; filters: Record<string, string[]>; children?: React.ReactNode }) {
  return (
    <section className={cn(w.type === "kpi" && w.w <= 4 ? "col-span-6" : "col-span-12", "flex min-w-0 flex-col rounded-[var(--radius-card)] border border-border bg-surface p-4", SPAN[w.w], ROWS[w.h])} aria-label={w.title}>
      <header className="mb-2 flex items-start gap-2">
        <h3 className="min-w-0 flex-1 truncate text-[12.5px] font-medium text-muted" title={w.title}>{w.title || data?.series?.[0]?.metric.label}</h3>
        {children}
      </header>
      <div className="min-h-0 flex-1"><WidgetBody w={w} data={data} filters={filters} /></div>
    </section>
  );
}
