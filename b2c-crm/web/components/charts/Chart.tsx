"use client";
import { useMemo, useState } from "react";
import { Table2, BarChart3 } from "lucide-react";
import { delta, fmtValue, num, resultTable, type Fmt, type Result, type ResultRow, type Viz } from "@/lib/analytics";

/**
 * One analytics widget (spec B13.3). Marks follow the data-viz rules: thin bars capped at 24px with a rounded end, 2px
 * lines, a recessive grid, categorical colours in a fixed order that follow the entity (never its rank), a legend for
 * two or more series, text in text colours. Every chart has a table view, and every number opens the leads behind it
 * (onDrill) - for metrics that count leads that list has exactly as many leads as the number.
 */
export type Defs = Record<string, { label: string; fmt: Fmt; higher_is_better: boolean; counts_leads: boolean }>;
type DrillFn = (metric: string, cell: Record<string, string | null>) => void;
type Props = { viz: Viz; result: Result; defs: Defs; dimLabels: Record<string, string>; onDrill?: DrillFn; note?: string };

const SERIES = 8;
const label = (defs: Defs, m: string) => defs[m]?.label ?? m;

export function Chart(p: Props) {
  const [asTable, setAsTable] = useState(false);
  if (p.viz === "text") return <p className="small" style={{ whiteSpace: "pre-wrap" }}>{p.note}</p>;
  const empty = p.result.rows.length === 0;
  const body = empty ? <p className="note">No data in this period.</p>
    : asTable || p.viz === "table" ? <TableView {...p} />
    : p.viz === "kpi" ? <Kpi {...p} />
    : p.viz === "gauge" ? <Gauge {...p} />
    : p.viz === "funnel" ? <Funnel {...p} />
    : p.viz === "line" ? <Line {...p} />
    : p.viz === "stacked" ? <Stacked {...p} />
    : p.viz === "pivot" ? <Pivot {...p} />
    : p.viz === "cohort" ? <Cohort {...p} />
    : p.viz === "leaderboard" ? <Leaderboard {...p} />
    : p.viz === "map" ? <TileMap {...p} />
    : <Bars {...p} />;
  return (
    <div className="viz-root">
      {body}
      {!empty && p.viz !== "table" && p.viz !== "kpi" && (
        <button type="button" className="btn quiet sm viz-toggle" onClick={() => setAsTable(!asTable)} aria-pressed={asTable}>
          {asTable ? <><BarChart3 className="icon s" aria-hidden />Chart</> : <><Table2 className="icon s" aria-hidden />Table</>}
        </button>
      )}
    </div>
  );
}

function cellOf(r: Result, row: ResultRow): Record<string, string | null> {
  return Object.fromEntries(r.dims.map((d, i) => [d, row.k[i] ?? null]));
}
function Num({ v, fmt, m, cell, onDrill, compact }: { v: unknown; fmt: Fmt; m: string; cell: Record<string, string | null>; onDrill?: DrillFn; compact?: boolean }) {
  const text = fmtValue(v, fmt, compact);
  if (!onDrill || num(v) === null || num(v) === 0) return <>{text}</>;
  return <button type="button" className="linkish num" onClick={() => onDrill(m, cell)} title="Open the leads behind this number">{text}</button>;
}

function TableView({ result, defs, dimLabels, onDrill }: Props) {
  const t = resultTable(result, { ...dimLabels, ...Object.fromEntries(Object.entries(defs).map(([k, d]) => [k, d.label])) });
  return (
    <div className="table-wrap"><table>
      <thead><tr>{t.columns.map((c, i) => <th key={c} className={i >= result.dims.length ? "right" : undefined}>{c}</th>)}</tr></thead>
      <tbody>{result.rows.map((row, ri) => (
        <tr key={ri}>
          {result.dims.map((_, i) => <td key={i}>{row.k[i] ?? "(none)"}</td>)}
          {result.metrics.flatMap((m) => [
            <td key={m} className="right num"><Num v={row[m]} fmt={defs[m]?.fmt ?? "count"} m={m} cell={cellOf(result, row)} onDrill={onDrill} /></td>,
            ...(result.compare ? [<td key={m + "c"} className="right num muted">{fmtValue(row[`${m}__cmp`], defs[m]?.fmt ?? "count")}</td>] : []),
          ])}
        </tr>
      ))}</tbody>
    </table></div>
  );
}

function Kpi({ result, defs, onDrill }: Props) {
  const m = result.metrics[0] ?? "";
  const row = result.rows[0];
  const d = defs[m];
  const ch = result.compare ? delta(row?.[m], row?.[`${m}__cmp`], d?.higher_is_better ?? true) : null;
  return (
    <div className="viz-kpi">
      <b className="kpi-value"><Num v={row?.[m]} fmt={d?.fmt ?? "count"} m={m} cell={{}} onDrill={onDrill} compact /></b>
      {ch && <span className={`delta ${ch.good === null ? "" : ch.good ? "good" : "bad"}`}>{ch.text} <span className="muted">vs previous period ({fmtValue(row?.[`${m}__cmp`], d?.fmt ?? "count", true)})</span></span>}
    </div>
  );
}

function Gauge({ result, defs, onDrill }: Props) {
  const m = result.metrics[0] ?? "";
  const v = num(result.rows[0]?.[m]) ?? 0;
  const pct = defs[m]?.fmt === "pct" ? Math.max(0, Math.min(100, v)) : 0;
  return (
    <div className="stack" style={{ gap: 6 }}>
      <b className="kpi-value"><Num v={v} fmt={defs[m]?.fmt ?? "pct"} m={m} cell={{}} onDrill={onDrill} /></b>
      <div className="meter" role="meter" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100} aria-label={label(defs, m)}><div style={{ width: `${pct}%` }} /></div>
    </div>
  );
}

/** Horizontal bars: one category per row, the first metric; value at the bar's tip. */
function Bars({ result, defs, onDrill }: Props) {
  const m = result.metrics[0] ?? "";
  const rows = [...result.rows].sort((a, b) => (num(b[m]) ?? 0) - (num(a[m]) ?? 0)).slice(0, 15);
  const max = Math.max(1, ...rows.map((r) => Math.abs(num(r[m]) ?? 0)));
  return (
    <div className="hbars" role="list" aria-label={label(defs, m)}>
      {rows.map((r, i) => (
        <div key={i} className="hbar" role="listitem">
          <span className="ellipsis small" title={String(r.k[0] ?? "(none)")}>{r.k[0] ?? "(none)"}</span>
          <div className="hbar-track"><div className="hbar-fill" style={{ width: `${(Math.abs(num(r[m]) ?? 0) / max) * 100}%` }} title={`${r.k[0] ?? "(none)"}: ${fmtValue(r[m], defs[m]?.fmt ?? "count")}`} /></div>
          <span className="small right"><Num v={r[m]} fmt={defs[m]?.fmt ?? "count"} m={m} cell={cellOf(result, r)} onDrill={onDrill} compact /></span>
        </div>
      ))}
      {result.rows.length > 15 && <p className="note">Top 15 of {result.rows.length}. The table view has all.</p>}
    </div>
  );
}

/** Ordinal steps in one hue (light to dark), conversion between steps. */
function Funnel({ result, defs, onDrill }: Props) {
  const row = result.rows[0];
  const vals = result.metrics.map((m) => num(row?.[m]) ?? 0);
  const at = (i: number) => vals[i] ?? 0;
  const max = Math.max(1, ...vals);
  return (
    <div className="hbars">
      {result.metrics.map((m, i) => (
        <div key={m} className="hbar">
          <span className="small ellipsis">{label(defs, m)}</span>
          <div className="hbar-track"><div className={`hbar-fill step${Math.min(i, 4)}`} style={{ width: `${(at(i) / max) * 100}%` }} /></div>
          <span className="small right"><Num v={at(i)} fmt="count" m={m} cell={{}} onDrill={onDrill} />{i > 0 && at(i - 1) > 0 && <span className="muted"> · {Math.round((at(i) / at(i - 1)) * 100)}%</span>}</span>
        </div>
      ))}
    </div>
  );
}

/** Lines over days, weeks or months: 2px lines, one hairline grid, a crosshair with every series' value. */
function Line({ result, defs, onDrill }: Props) {
  const [hover, setHover] = useState<number | null>(null);
  const xs = useMemo(() => [...new Set(result.rows.map((r) => r.k[0] ?? ""))].sort(), [result]);
  const metrics = result.metrics.slice(0, SERIES);
  const val = (x: string, m: string) => num(result.rows.find((r) => (r.k[0] ?? "") === x)?.[m]) ?? 0;
  const max = Math.max(1, ...xs.flatMap((x) => metrics.map((m) => val(x, m))));
  const W = 640, H = 200, L = 40, B = 22, T = 8;
  const px = (i: number) => L + (xs.length <= 1 ? (W - L) / 2 : (i * (W - L - 8)) / (xs.length - 1));
  const py = (v: number) => T + (H - T - B) * (1 - v / max);
  const ticks = [0, max / 2, max];
  return (
    <div className="stack" style={{ gap: 6 }}>
      {metrics.length > 1 && <Legend items={metrics.map((m, i) => ({ key: m, label: label(defs, m), slot: i }))} />}
      <div className="linechart">
        <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={metrics.map((m) => label(defs, m)).join(", ")} onMouseLeave={() => setHover(null)}
          onMouseMove={(e) => {
            const box = (e.currentTarget as SVGSVGElement).getBoundingClientRect();
            const x = ((e.clientX - box.left) / box.width) * W;
            let best = 0; xs.forEach((_, i) => { if (Math.abs(px(i) - x) < Math.abs(px(best) - x)) best = i; });
            setHover(best);
          }}>
          {ticks.map((t) => <g key={t}><line x1={L} x2={W} y1={py(t)} y2={py(t)} className="gridline" /><text x={L - 6} y={py(t) + 3} className="axis" textAnchor="end">{fmtValue(t, defs[metrics[0] ?? ""]?.fmt ?? "count", true)}</text></g>)}
          {xs.length > 0 && [0, Math.floor((xs.length - 1) / 2), xs.length - 1].filter((v, i, a) => a.indexOf(v) === i).map((i) => <text key={i} x={px(i)} y={H - 6} className="axis" textAnchor="middle">{String(xs[i]).slice(5)}</text>)}
          {metrics.map((m, si) => (
            <polyline key={m} className={`series s${si + 1}`} fill="none" points={xs.map((x, i) => `${px(i)},${py(val(x, m))}`).join(" ")} />
          ))}
          {hover !== null && <line x1={px(hover)} x2={px(hover)} y1={T} y2={H - B} className="crosshair" />}
          {hover !== null && metrics.map((m, si) => <circle key={m} cx={px(hover)} cy={py(val(xs[hover] ?? "", m))} r={4} className={`dot s${si + 1}`} />)}
        </svg>
        {hover !== null && (
          <div className="viz-tip" style={{ left: `${(px(hover) / W) * 100}%` }} role="status">
            <b>{xs[hover]}</b>
            {metrics.map((m, si) => <span key={m}><i className={`key s${si + 1}`} />{label(defs, m)}: {fmtValue(val(xs[hover] ?? "", m), defs[m]?.fmt ?? "count")}</span>)}
          </div>
        )}
      </div>
      {onDrill && <p className="note">Point at a day for its values; the table view opens the leads behind each number.</p>}
    </div>
  );
}

/** Stacked columns: the first dimension along the axis, the second (or the metrics) as segments, 2px gaps between. */
function Stacked({ result, defs, onDrill }: Props) {
  const twoDims = result.dims.length >= 2;
  const d0 = result.dims[0] ?? "", d1 = result.dims[1] ?? "";
  const m0 = result.metrics[0] ?? "";
  const xs = [...new Set(result.rows.map((r) => r.k[0] ?? "(none)"))].sort();
  const seriesAll = twoDims ? [...new Set(result.rows.map((r) => r.k[1] ?? "(none)"))].sort() : result.metrics;
  const series = seriesAll.length > SERIES ? [...seriesAll.slice(0, SERIES - 1), "Other"] : seriesAll;
  const value = (x: string, s: string) => twoDims
    ? (s === "Other" ? result.rows.filter((r) => (r.k[0] ?? "(none)") === x && !series.slice(0, -1).includes(r.k[1] ?? "(none)")).reduce((a, r) => a + (num(r[m0]) ?? 0), 0)
                     : num(result.rows.find((r) => (r.k[0] ?? "(none)") === x && (r.k[1] ?? "(none)") === s)?.[m0]) ?? 0)
    : num(result.rows.find((r) => (r.k[0] ?? "(none)") === x)?.[s]) ?? 0;
  const totals = xs.map((x) => series.reduce((a, s) => a + Math.max(0, value(x, s)), 0));
  const max = Math.max(1, ...totals);
  const lbl = (s: string) => (twoDims ? s : label(defs, s));
  return (
    <div className="stack" style={{ gap: 6 }}>
      <Legend items={series.map((s, i) => ({ key: s, label: lbl(s), slot: i }))} />
      <div className="cols" role="list">
        {xs.map((x, xi) => (
          <div key={x} className="col" role="listitem" title={`${x}: ${series.map((s) => `${lbl(s)} ${fmtValue(value(x, s), defs[twoDims ? m0 : s]?.fmt ?? "count")}`).join(", ")}`}>
            <div className="col-stack" style={{ height: `${((totals[xi] ?? 0) / max) * 100}%` }}>
              {series.map((s, si) => value(x, s) > 0 && (
                <button key={s} type="button" className={`seg s${si + 1}`} style={{ flexGrow: value(x, s) }} aria-label={`${x}, ${lbl(s)}: ${fmtValue(value(x, s), "count")}`}
                  onClick={() => onDrill?.(twoDims ? m0 : s, twoDims ? { [d0]: x === "(none)" ? null : x, ...(s === "Other" ? {} : { [d1]: s === "(none)" ? null : s }) } : { [d0]: x === "(none)" ? null : x })} />
              ))}
            </div>
            <span className="col-label">{x.length > 7 && /^\d{4}-/.test(x) ? x.slice(5) : x}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function Legend({ items }: { items: { key: string; label: string; slot: number }[] }) {
  return <div className="legend">{items.map((i) => <span key={i.key}><i className={`key s${i.slot + 1}`} />{i.label}</span>)}</div>;
}

/** Rows by the first dimension, columns by the second, the first metric in the cells. */
function Pivot({ result, defs, onDrill, dimLabels }: Props) {
  if (result.dims.length < 2) return <TableView {...{ result, defs, onDrill, dimLabels, viz: "table" }} />;
  const m = result.metrics[0] ?? "";
  const rs = [...new Set(result.rows.map((r) => r.k[0] ?? "(none)"))].sort();
  const cs = [...new Set(result.rows.map((r) => r.k[1] ?? "(none)"))].sort().slice(0, 12);
  const get = (a: string, b: string) => result.rows.find((r) => (r.k[0] ?? "(none)") === a && (r.k[1] ?? "(none)") === b);
  return (
    <div className="table-wrap"><table>
      <thead><tr><th>{dimLabels[result.dims[0] ?? ""] ?? result.dims[0]}</th>{cs.map((c) => <th key={c} className="right">{c}</th>)}</tr></thead>
      <tbody>{rs.map((a) => (
        <tr key={a}><td>{a}</td>{cs.map((b) => { const row = get(a, b); return <td key={b} className="right num">{row ? <Num v={row[m]} fmt={defs[m]?.fmt ?? "count"} m={m} cell={cellOf(result, row)} onDrill={onDrill} /> : "–"}</td>; })}</tr>
      ))}</tbody>
    </table></div>
  );
}

/** Cohort grid: one row per period, each later metric as a share of the first, shaded by share (one hue). */
function Cohort({ result, defs, onDrill }: Props) {
  const first = result.metrics[0] ?? "", rest = result.metrics.slice(1);
  const rows = [...result.rows].sort((a, b) => String(a.k[0]).localeCompare(String(b.k[0])));
  return (
    <div className="table-wrap"><table className="cohort">
      <thead><tr><th>Cohort</th><th className="right">{label(defs, first)}</th>{rest.map((m) => <th key={m} className="right">{label(defs, m)}</th>)}</tr></thead>
      <tbody>{rows.map((r, i) => {
        const base = num(r[first]) ?? 0;
        return (
          <tr key={i}><td>{r.k[0] ?? "(none)"}</td><td className="right num"><Num v={r[first]} fmt="count" m={first} cell={cellOf(result, r)} onDrill={onDrill} /></td>
            {rest.map((m) => { const share = base ? (num(r[m]) ?? 0) / base : 0; return (
              <td key={m} className="right num cohort-cell" style={{ ["--share" as string]: share.toFixed(3) }}>
                <Num v={r[m]} fmt="count" m={m} cell={cellOf(result, r)} onDrill={onDrill} /> <span className="muted small">{Math.round(share * 100)}%</span>
              </td>); })}
          </tr>);
      })}</tbody>
    </table></div>
  );
}

function Leaderboard({ result, defs, onDrill }: Props) {
  const m = result.metrics[0] ?? "";
  const rows = [...result.rows].sort((a, b) => (num(b[m]) ?? 0) - (num(a[m]) ?? 0));
  return (
    <div className="table-wrap"><table>
      <thead><tr><th>#</th><th>Name</th>{result.metrics.map((x) => <th key={x} className="right">{label(defs, x)}</th>)}</tr></thead>
      <tbody>{rows.map((r, i) => (
        <tr key={i}><td className="num">{i + 1}</td><td>{r.k[0] ?? "(none)"}</td>
          {result.metrics.map((x) => <td key={x} className="right num"><Num v={r[x]} fmt={defs[x]?.fmt ?? "count"} m={x} cell={cellOf(result, r)} onDrill={onDrill} compact /></td>)}</tr>
      ))}</tbody>
    </table></div>
  );
}

/** States as tiles shaded in one hue by value (a map without a map file); the value is written on each tile. */
function TileMap({ result, defs, onDrill }: Props) {
  const m = result.metrics[0] ?? "";
  const rows = [...result.rows].sort((a, b) => (num(b[m]) ?? 0) - (num(a[m]) ?? 0));
  const max = Math.max(1, ...rows.map((r) => num(r[m]) ?? 0));
  return (
    <div className="tiles">
      {rows.map((r, i) => {
        const share = (num(r[m]) ?? 0) / max;
        return (
          <button key={i} type="button" className={`tile ${share > 0.55 ? "dark" : ""}`} style={{ ["--share" as string]: share.toFixed(3) }}
            onClick={() => onDrill?.(m, cellOf(result, r))} title={`${r.k[0] ?? "(none)"}: ${fmtValue(r[m], defs[m]?.fmt ?? "count")}`}>
            <span className="ellipsis">{r.k[0] ?? "(none)"}</span><b>{fmtValue(r[m], defs[m]?.fmt ?? "count", true)}</b>
          </button>
        );
      })}
    </div>
  );
}
