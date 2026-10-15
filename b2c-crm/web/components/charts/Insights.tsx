"use client";
import { useState, useTransition } from "react";
import { BarChart3, Sparkles } from "lucide-react";
import { toast } from "sonner";
import { Chart, type Defs } from "@/components/charts/Chart";
import { runSpec } from "@/app/analytics-actions";
import { insightsNow, type InsightRow } from "@/app/w/admin-actions";
import type { Result, Spec, Viz } from "@/lib/analytics";

const TIME_DIMS = new Set(["day", "week", "month"]);
const vizFor = (s: Spec): Viz => (!s.dims?.length ? "kpi" : TIME_DIMS.has(s.dims[0]!) ? "line" : "bar");

/**
 * What changed (spec B13.4): the morning feed, and on demand for the Admin and Marketing. Each insight opens the chart
 * behind it, run again as the person so it shows only what they may see.
 */
export function Insights({ insights: initial, defs, dimLabels, canWrite }: { insights: InsightRow[]; defs: Defs; dimLabels: Record<string, string>; canWrite: boolean }) {
  const [insights, setInsights] = useState(initial);
  const [busy, start] = useTransition();
  const latest = insights[0];
  const items = insights.flatMap((i) => i.items.map((it, j) => ({ ...it, key: `${i.id}-${j}`, anomaly: i.kind === "anomaly" }))).slice(0, 8);
  const write = () => start(async () => {
    const r = await insightsNow();
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Done.");
    setInsights(r.data ?? []);
  });
  if (!latest && !canWrite) return null;
  return (
    <details className="card pad" open>
      <summary><b>What changed</b> <span className="small muted">{latest ? `insights for ${latest.day}, written by Claude from last week's numbers` : "no insights yet"}</span></summary>
      {canWrite && <div className="row" style={{ marginTop: 8 }}>
        <button type="button" className="btn ghost sm" disabled={busy} onClick={write}><Sparkles className="icon s" aria-hidden />{busy ? "Writing… (up to a minute)" : "Write insights now"}</button>
        <span className="small muted">From the last 7 days against the 7 before; uses the Claude budget.</span>
      </div>}
      <ul className="stack small" style={{ margin: "8px 0 0", paddingLeft: 18, gap: 6 }}>
        {items.map((it) => <Item key={it.key} title={it.title} body={it.body} spec={it.spec} anomaly={it.anomaly} defs={defs} dimLabels={dimLabels} />)}
      </ul>
    </details>
  );
}

function Item({ title, body, spec, anomaly, defs, dimLabels }: { title: string; body: string; spec?: Spec; anomaly: boolean; defs: Defs; dimLabels: Record<string, string> }) {
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const known = spec?.metrics.every((m) => defs[m]);
  const show = () => start(async () => {
    if (result) return setResult(null);
    const r = await runSpec(spec!);
    if (!r.ok) return setError(r.error);
    setError(null);
    setResult(r.data ?? null);
  });
  return (
    <li>
      <b>{title}</b> {body}{anomaly ? <span className="chip warm" style={{ marginLeft: 4 }}>unusual</span> : null}
      {spec && known && <button type="button" className="btn quiet sm" style={{ marginLeft: 4 }} disabled={busy} onClick={show}><BarChart3 className="icon s" aria-hidden />{result ? "Hide chart" : busy ? "Loading…" : "Chart"}</button>}
      {error && <div className="error">{error}</div>}
      {result && <div className="card pad" style={{ marginTop: 6 }}><Chart viz={vizFor(spec!)} result={result} defs={defs} dimLabels={dimLabels} /></div>}
    </li>
  );
}
