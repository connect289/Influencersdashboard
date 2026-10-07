"use client";
import { useMemo, useState, useTransition } from "react";
import { Download, LoaderCircle, Play, Save } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { DIM_LABEL, dimLabel, formatValue, PERIOD_LABEL, PERIODS, type CatalogueMetric, type Period } from "@/lib/analytics";
import type { ReportResult } from "@/lib/analytics-data";
import { FACT_LABEL, KIND_LABEL, type ReportDef, type ReportKind } from "@/lib/reports";
import { runReport, saveReport } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";
function L({ label, children }: { label: string; children: React.ReactNode }) {
  return <label className="block space-y-1"><span className="text-[12px] text-muted">{label}</span>{children}</label>;
}
const b64url = (s: string) => btoa(unescape(encodeURIComponent(s))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

function ResultTable({ r }: { r: ReportResult }) {
  if (r.kind === "tabular") {
    return (
      <table className="w-full min-w-[640px] text-left text-[12.5px]">
        <thead className="text-[11px] uppercase tracking-wider text-subtle"><tr className="border-b border-border">{r.columns.map((c) => <th key={c} className="px-3 py-2 font-medium">{c.replace(/_/g, " ")}</th>)}</tr></thead>
        <tbody className="divide-y divide-border">
          {r.rows.slice(0, 500).map((row, i) => <tr key={i}>{r.columns.map((c) => <td key={c} className="whitespace-nowrap px-3 py-1.5 text-muted">
            {c === "partner_id" && row[c] != null ? (r.labels.partner_id[String(row[c])] ?? String(row[c])) : row[c] == null ? "—" : String(row[c])}</td>)}</tr>)}
        </tbody>
      </table>
    );
  }
  if (r.kind === "summary") {
    return (
      <table className="w-full min-w-[640px] text-left text-[12.5px]">
        <thead className="text-[11px] uppercase tracking-wider text-subtle"><tr className="border-b border-border">
          {r.dims.map((d) => <th key={d} className="px-3 py-2 font-medium">{DIM_LABEL[d] ?? d}</th>)}{r.metrics.map((m) => <th key={m.key} className="px-3 py-2 text-right font-medium">{m.label}</th>)}</tr></thead>
        <tbody className="divide-y divide-border">
          {r.rows.map((row, i) => <tr key={i}>{r.dims.map((d, j) => <td key={d} className="px-3 py-1.5 text-fg">{dimLabel(d, row.d[j], r.labels)}</td>)}
            {row.values.map((v, j) => <td key={j} className="tabular px-3 py-1.5 text-right text-muted">{formatValue(v, r.metrics[j]!.unit)}</td>)}</tr>)}
          <tr className="font-medium"><td colSpan={r.dims.length} className="px-3 py-1.5 text-fg">Total</td>{r.totals.map((v, j) => <td key={j} className="tabular px-3 py-1.5 text-right text-fg">{formatValue(v, r.metrics[j]!.unit)}</td>)}</tr>
        </tbody>
      </table>
    );
  }
  const get = (a: string | null, b: string | null) => r.cells.find((c) => c.d?.[0] === a && c.d?.[1] === b)?.value ?? null;
  return (
    <table className="w-full min-w-[640px] text-left text-[12.5px]">
      <thead className="text-[11px] uppercase tracking-wider text-subtle"><tr className="border-b border-border"><th className="px-3 py-2 font-medium">{DIM_LABEL[r.row_dim] ?? r.row_dim} \ {DIM_LABEL[r.col_dim] ?? r.col_dim}</th>
        {r.cols.map((c) => <th key={String(c)} className="px-3 py-2 text-right font-medium">{dimLabel(r.col_dim, c, r.labels)}</th>)}</tr></thead>
      <tbody className="divide-y divide-border">
        {r.rows.map((row) => <tr key={String(row)}><td className="px-3 py-1.5 text-fg">{dimLabel(r.row_dim, row, r.labels)}</td>
          {r.cols.map((c) => <td key={String(c)} className="tabular px-3 py-1.5 text-right text-muted">{formatValue(get(row, c), r.metric.unit)}</td>)}</tr>)}
      </tbody>
    </table>
  );
}

export function ReportBuilder({ metrics, facts, initial }: { metrics: CatalogueMetric[]; facts: Record<string, { name: string; type: string }[]>;
                                                             initial?: { id: number; name: string; kind: ReportKind; definition: Record<string, unknown> } | null }) {
  const d0 = (initial?.definition ?? {}) as Record<string, unknown>;
  const [id, setId] = useState<number | null>(initial?.id ?? null);
  const [name, setName] = useState(initial?.name ?? "");
  const [kind, setKind] = useState<ReportKind>(initial?.kind ?? "summary");
  const [period, setPeriod] = useState<Period>((d0.period as Period) ?? "30d");
  const [fact, setFact] = useState<string>((d0.fact as string) ?? "fact_allocations");
  const [columns, setColumns] = useState<string[]>((d0.columns as string[]) ?? []);
  const [sel, setSel] = useState<string[]>((d0.metrics as string[]) ?? []);
  const [dims, setDims] = useState<string[]>((d0.dims as string[]) ?? ["partner"]);
  const [metric, setMetric] = useState<string>((d0.metric as string) ?? "allocations");
  const [rowDim, setRowDim] = useState<string>((d0.row_dim as string) ?? "partner");
  const [colDim, setColDim] = useState<string>((d0.col_dim as string) ?? "month");
  const [fdim, setFdim] = useState<string>(Object.keys((d0.filters as object) ?? {})[0] ?? "");
  const [fval, setFval] = useState<string>(Object.values((d0.filters as Record<string, string[]>) ?? {})[0]?.join(", ") ?? "");
  const [result, setResult] = useState<ReportResult | null>(null);
  const [busy, start] = useTransition();
  const filters = fdim && fval.trim() ? { [fdim]: fval.split(",").map((x) => x.trim()).filter(Boolean) } : {};
  const def: ReportDef = kind === "tabular" ? { kind, definition: { fact, columns, filters, period } }
    : kind === "summary" ? { kind, definition: { metrics: sel, dims, filters, period } }
    : { kind, definition: { metric, row_dim: rowDim, col_dim: colDim, filters, period } };
  const dimsFor = useMemo(() => {
    const keys = kind === "tabular" ? [] : kind === "summary" ? sel : [metric];
    const ms = metrics.filter((m) => keys.includes(m.key));
    return ms.length ? ms.map((m) => m.dims).reduce((a, b) => a.filter((x) => b.includes(x))) : [];
  }, [kind, sel, metric, metrics]);
  const run = () => start(async () => { const r = await runReport(def); if (!r.ok) { toast.error(r.error); return; } setResult(r.result); });
  const save = () => start(async () => { const r = await saveReport(id, name, def); if (!r.ok) { toast.error(r.error); return; } setId(r.id); toast.success("Report saved"); });
  const exportHref = id ? `/reports/export?id=${id}&name=${encodeURIComponent(name || "report")}` : `/reports/export?def=${b64url(JSON.stringify(def))}&name=${encodeURIComponent(name || "report")}`;

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-3">
        <L label="Name"><input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} className={field} placeholder="e.g. Partner effort, monthly" /></L>
        <L label="Kind"><select value={kind} onChange={(e) => { setKind(e.target.value as ReportKind); setResult(null); }} className={field}>{Object.entries(KIND_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></L>
        <L label="Period"><select value={period} onChange={(e) => setPeriod(e.target.value as Period)} className={field}>{PERIODS.map((p) => <option key={p} value={p}>{PERIOD_LABEL[p]}</option>)}</select></L>
      </div>
      {kind === "tabular" && (
        <div className="space-y-3">
          <L label="List of"><select value={fact} onChange={(e) => { setFact(e.target.value); setColumns([]); }} className={field}>{Object.keys(facts).map((f) => <option key={f} value={f}>{FACT_LABEL[f] ?? f}</option>)}</select></L>
          <fieldset><legend className="mb-1 text-[12px] text-muted">Columns ({columns.length}/30)</legend>
            <div className="flex flex-wrap gap-x-4 gap-y-1.5 text-[12.5px]">
              {(facts[fact] ?? []).map((c) => (
                <label key={c.name} className="flex items-center gap-1.5"><input type="checkbox" checked={columns.includes(c.name)} className="size-3.5 accent-[var(--primary)]"
                  onChange={(e) => setColumns(e.target.checked ? [...columns, c.name].slice(0, 30) : columns.filter((x) => x !== c.name))} />{c.name.replace(/_/g, " ")}</label>
              ))}
            </div>
          </fieldset>
        </div>
      )}
      {kind === "summary" && (
        <div className="space-y-3">
          <fieldset><legend className="mb-1 text-[12px] text-muted">Metrics ({sel.length}/12)</legend>
            <div className="grid gap-x-4 gap-y-1 text-[12.5px] sm:grid-cols-2 lg:grid-cols-3">
              {metrics.map((m) => <label key={m.key} className="flex items-center gap-1.5"><input type="checkbox" checked={sel.includes(m.key)} className="size-3.5 accent-[var(--primary)]"
                onChange={(e) => setSel(e.target.checked ? [...sel, m.key].slice(0, 12) : sel.filter((x) => x !== m.key))} /><span className="text-subtle">{m.area}:</span> {m.label}</label>)}
            </div>
          </fieldset>
          <div className="grid gap-3 sm:grid-cols-2">
            {[0, 1].map((i) => <L key={i} label={i === 0 ? "Breakdown" : "Second breakdown (optional)"}>
              <select value={dims[i] ?? ""} onChange={(e) => { const n = [...dims]; if (e.target.value) n[i] = e.target.value; else n.splice(i); setDims(n.filter(Boolean)); }} className={field}>
                <option value="">{i === 0 ? "Choose" : "None"}</option>{dimsFor.map((d) => <option key={d} value={d}>{DIM_LABEL[d] ?? d}</option>)}</select></L>)}
          </div>
          {sel.length > 0 && dimsFor.length === 0 && <p className="text-[12px] text-warning">These metrics share no breakdown; choose metrics from the same area.</p>}
        </div>
      )}
      {kind === "matrix" && (
        <div className="grid gap-3 sm:grid-cols-3">
          <L label="Metric"><select value={metric} onChange={(e) => setMetric(e.target.value)} className={field}>{metrics.map((m) => <option key={m.key} value={m.key}>{m.area}: {m.label}</option>)}</select></L>
          <L label="Rows"><select value={rowDim} onChange={(e) => setRowDim(e.target.value)} className={field}>{dimsFor.map((d) => <option key={d} value={d}>{DIM_LABEL[d] ?? d}</option>)}</select></L>
          <L label="Columns"><select value={colDim} onChange={(e) => setColDim(e.target.value)} className={field}>{dimsFor.map((d) => <option key={d} value={d}>{DIM_LABEL[d] ?? d}</option>)}</select></L>
        </div>
      )}
      <div className="grid gap-3 sm:grid-cols-2">
        <L label="Only for (optional)"><select value={fdim} onChange={(e) => setFdim(e.target.value)} className={field}><option value="">Everything</option>
          {(kind === "tabular" ? Object.keys(DIM_LABEL) : dimsFor).filter((d) => !["day", "week", "month"].includes(d)).map((d) => <option key={d} value={d}>{DIM_LABEL[d] ?? d}</option>)}</select></L>
        <L label="Values (comma-separated)"><input value={fval} onChange={(e) => setFval(e.target.value)} disabled={!fdim} className={field} placeholder={fdim === "partner" ? "partner IDs" : ""} /></L>
      </div>
      <div className="flex flex-wrap gap-2 border-t border-border pt-4">
        <Button size="sm" onClick={run} disabled={busy}>{busy ? <LoaderCircle className="size-3.5 animate-spin" /> : <Play className="size-3.5" />} Run</Button>
        <Button size="sm" variant="secondary" onClick={save} disabled={busy || !name.trim()}><Save className="size-3.5" /> {id ? "Save changes" : "Save report"}</Button>
        <a href={exportHref} className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-border bg-surface px-3 text-[13px] text-fg hover:bg-surface-hover"><Download className="size-3.5" /> Export CSV</a>
        {id && <a href={`/dashboards?tab=alerts&schedule=r:${id}`} className="inline-flex h-8 items-center rounded-lg px-3 text-[13px] text-info hover:underline">Schedule by e-mail</a>}
      </div>
      {result && (
        <div className="overflow-x-auto rounded-lg border border-border">
          <p className="border-b border-border bg-surface-2 px-3 py-2 text-[12px] text-muted">{result.kind === "tabular" ? `${result.rows.length} rows${result.rows.length >= result.limit ? ` (first ${result.limit})` : ""}` : `${result.rows.length} rows`} · {new Date(result.from).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })} to {new Date(result.to).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}</p>
          <ResultTable r={result} />
        </div>
      )}
    </div>
  );
}
