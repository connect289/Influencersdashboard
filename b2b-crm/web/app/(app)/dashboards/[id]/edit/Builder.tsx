"use client";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ArrowDown, ArrowUp, GripVertical, LoaderCircle, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { cn } from "@/components/ui/cn";
import {
  DIM_LABEL, gaugeTargetInput, gaugeTargetValue, PERIOD_LABEL, PERIODS, WIDGET_LABEL, WIDGET_TYPES, widgetDims, widgetProblemIn,
  type CatalogueMetric, type Dashboard, type Period, type Widget, type WidgetType,
} from "@/lib/analytics";
import { saveDashboard } from "../../actions";

const field = "h-8 w-full rounded-lg border border-border bg-surface px-2 text-[12.5px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";
const MULTI: WidgetType[] = ["table", "funnel"];
const NO_METRIC: WidgetType[] = ["text", "sla_timers", "alerts"];

function L({ label, children }: { label: string; children: React.ReactNode }) {
  return <label className="block space-y-1"><span className="text-[11.5px] text-muted">{label}</span>{children}</label>;
}

function WidgetEditor({ w, metrics, onChange }: { w: Widget; metrics: CatalogueMetric[]; onChange: (w: Widget) => void }) {
  const m = metrics.find((x) => x.key === (w.metric ?? w.metrics?.[0]));
  // only the breakdowns every chosen metric has (the save checks the same)
  const dims = widgetDims(w, metrics);
  const byArea = useMemo(() => Object.entries(metrics.reduce<Record<string, CatalogueMetric[]>>((a, x) => { (a[x.area] ??= []).push(x); return a; }, {})), [metrics]);
  const metricSelect = (value: string | undefined, set: (v: string) => void) => (
    <select value={value ?? ""} onChange={(e) => set(e.target.value)} className={field}>
      <option value="">Choose a metric</option>
      {byArea.map(([area, ms]) => <optgroup key={area} label={area}>{ms.map((x) => <option key={x.key} value={x.key}>{x.label}</option>)}</optgroup>)}
    </select>
  );
  const dimSelect = (i: number, list = w.dims ?? [], key: "dims" | "steps" = "dims") => (
    <select value={list[i] ?? ""} onChange={(e) => { const next = [...list]; if (e.target.value) next[i] = e.target.value; else next.splice(i); onChange({ ...w, [key]: next.filter(Boolean) }); }} className={field}>
      <option value="">{i === 0 ? "None" : "None"}</option>
      {dims.map((d) => <option key={d} value={d}>{DIM_LABEL[d] ?? d}</option>)}
    </select>
  );
  const problem = widgetProblemIn(w, metrics);
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <L label="Type">
        <select value={w.type} onChange={(e) => onChange({ ...w, type: e.target.value as WidgetType })} className={field}>
          {WIDGET_TYPES.map((t) => <option key={t} value={t}>{WIDGET_LABEL[t]}</option>)}
        </select>
      </L>
      <L label="Title"><input value={w.title ?? ""} maxLength={80} onChange={(e) => onChange({ ...w, title: e.target.value })} className={field} /></L>
      <L label="Width (of 12)"><input type="number" min={1} max={12} value={w.w} onChange={(e) => onChange({ ...w, w: Math.min(12, Math.max(1, Number(e.target.value) || 1)) })} className={field} /></L>
      <L label="Height (rows)"><input type="number" min={1} max={4} value={w.h} onChange={(e) => onChange({ ...w, h: Math.min(4, Math.max(1, Number(e.target.value) || 1)) })} className={field} /></L>
      {w.type === "text" && <div className="sm:col-span-2 lg:col-span-4"><L label="Text"><textarea value={w.text ?? ""} maxLength={1000} rows={3} onChange={(e) => onChange({ ...w, text: e.target.value })} className={cn(field, "h-auto py-1.5")} /></L></div>}
      {!NO_METRIC.includes(w.type) && !MULTI.includes(w.type) && <L label="Metric">{metricSelect(w.metric, (v) => onChange({ ...w, metric: v || undefined }))}</L>}
      {MULTI.includes(w.type) && (
        <div className="sm:col-span-2 lg:col-span-4">
          <L label={w.type === "funnel" ? "Steps (metrics, in order)" : "Columns (metrics)"}>
            <div className="flex flex-wrap gap-2">
              {(w.metrics ?? []).map((k, i) => (
                <span key={k + i} className="inline-flex items-center gap-1 rounded-md border border-border bg-surface-2 px-2 py-0.5 text-[12px]">
                  {metrics.find((x) => x.key === k)?.label ?? k}
                  <button type="button" aria-label="Remove" onClick={() => onChange({ ...w, metrics: (w.metrics ?? []).filter((_, j) => j !== i) })} className="text-subtle hover:text-fg">×</button>
                </span>
              ))}
              <div className="w-56">{metricSelect(undefined, (v) => v && onChange({ ...w, metrics: [...(w.metrics ?? []), v].slice(0, 12) }))}</div>
            </div>
          </L>
        </div>
      )}
      {["bar", "line", "stacked", "heatmap", "leaderboard", "map", "table"].includes(w.type) && <L label="Breakdown">{dimSelect(0)}</L>}
      {["bar", "line", "stacked", "heatmap"].includes(w.type) && <L label="Second breakdown">{dimSelect(1)}</L>}
      {w.type === "sankey" && [0, 1, 2, 3].map((i) => <L key={i} label={`Step ${i + 1}`}>{dimSelect(i, w.steps ?? [], "steps")}</L>)}
      {w.type === "gauge" && <L label={m?.unit === "pct" ? "Target (%)" : "Target"}><input type="number" step="any" value={gaugeTargetInput(w.target, m?.unit)} onChange={(e) => onChange({ ...w, target: gaugeTargetValue(e.target.value, m?.unit) })} className={field} /></L>}
      {!NO_METRIC.includes(w.type) && (
        <L label="Period">
          <select value={w.period ?? ""} onChange={(e) => onChange({ ...w, period: (e.target.value || undefined) as Period | undefined })} className={field}>
            <option value="">The dashboard's</option>
            {PERIODS.map((p) => <option key={p} value={p}>{PERIOD_LABEL[p]}</option>)}
          </select>
        </L>
      )}
      {problem && <p className="text-[12px] text-warning sm:col-span-2 lg:col-span-4">{problem}</p>}
    </div>
  );
}

let seq = 0;
const newId = () => `w${Date.now().toString(36).slice(-4)}${(seq++).toString(36)}`;

export function Builder({ initial, metrics }: { initial: Dashboard | null; metrics: CatalogueMetric[] }) {
  const router = useRouter();
  const [name, setName] = useState(initial?.name ?? "");
  const [description, setDescription] = useState(initial?.description ?? "");
  const [period, setPeriod] = useState<Period>(initial?.period ?? "30d");
  const [widgets, setWidgets] = useState<Widget[]>(initial?.widgets ?? []);
  const [open, setOpen] = useState<string | null>(widgets[0]?.id ?? null);
  const [drag, setDrag] = useState<number | null>(null);
  const [busy, start] = useTransition();
  const move = (from: number, to: number) => setWidgets((ws) => { if (to < 0 || to >= ws.length) return ws; const n = [...ws]; const [x] = n.splice(from, 1); n.splice(to, 0, x!); return n; });
  const add = () => { const w: Widget = { id: newId(), type: "kpi", title: "", w: 3, h: 1 }; setWidgets((ws) => [...ws, w]); setOpen(w.id); };
  const problems = widgets.map((w) => widgetProblemIn(w, metrics)).filter(Boolean);
  const save = () => start(async () => {
    if (problems.length) { toast.error("Some widgets are not complete yet"); return; }
    const r = await saveDashboard({ id: initial?.id ?? null, name, description, period, filters: initial?.filters ?? {}, widgets });
    if (!r.ok) { toast.error(r.error); return; }
    toast.success("Dashboard saved");
    router.push(`/dashboards/${r.id}`);
  });
  return (
    <div className="space-y-5">
      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,2fr)_180px]">
        <L label="Name"><input value={name} maxLength={80} onChange={(e) => setName(e.target.value)} className={field} /></L>
        <L label="Description"><input value={description ?? ""} maxLength={300} onChange={(e) => setDescription(e.target.value)} className={field} /></L>
        <L label="Default period">
          <select value={period} onChange={(e) => setPeriod(e.target.value as Period)} className={field}>{PERIODS.map((p) => <option key={p} value={p}>{PERIOD_LABEL[p]}</option>)}</select>
        </L>
      </div>

      <div>
        <p className="mb-2 text-[11px] uppercase tracking-wider text-subtle">Layout (12 columns): drag to reorder</p>
        <div className="grid grid-cols-12 gap-1.5 rounded-lg border border-dashed border-border p-2">
          {widgets.map((w, i) => (
            <button key={w.id} type="button" draggable onDragStart={() => setDrag(i)} onDragOver={(e) => e.preventDefault()} onDrop={() => { if (drag !== null) move(drag, i); setDrag(null); }}
              onClick={() => setOpen(w.id)} style={{ gridColumn: `span ${w.w} / span ${w.w}`, minHeight: `${w.h * 22}px` }}
              className={cn("truncate rounded-md border px-2 py-1 text-left text-[11px]", open === w.id ? "border-amber bg-amber/10 text-fg" : "border-border bg-surface-2 text-muted",
                widgetProblemIn(w, metrics) && "border-warning/50")}>
              {w.title || WIDGET_LABEL[w.type]}
            </button>
          ))}
          {widgets.length === 0 && <p className="col-span-12 py-4 text-center text-[12.5px] text-subtle">No widgets yet</p>}
        </div>
      </div>

      <ul className="space-y-2">
        {widgets.map((w, i) => (
          <li key={w.id} className={cn("rounded-lg border bg-surface", open === w.id ? "border-ring/50" : "border-border")}>
            <div className="flex items-center gap-2 px-3 py-2">
              <GripVertical className="size-4 text-subtle" />
              <button type="button" className="min-w-0 flex-1 truncate text-left text-[13px] font-medium text-fg" onClick={() => setOpen(open === w.id ? null : w.id)}>
                {w.title || WIDGET_LABEL[w.type]} <span className="hidden font-normal text-subtle sm:inline">· {WIDGET_LABEL[w.type]} · {w.w}×{w.h}</span>
              </button>
              <Button size="sm" variant="ghost" className="px-2" aria-label="Move up" onClick={() => move(i, i - 1)} disabled={i === 0}><ArrowUp className="size-3.5" /></Button>
              <Button size="sm" variant="ghost" className="px-2" aria-label="Move down" onClick={() => move(i, i + 1)} disabled={i === widgets.length - 1}><ArrowDown className="size-3.5" /></Button>
              <Button size="sm" variant="ghost" className="px-2" aria-label="Remove" onClick={() => setWidgets((ws) => ws.filter((x) => x.id !== w.id))}><Trash2 className="size-3.5" /></Button>
            </div>
            {open === w.id && <div className="border-t border-border px-3 py-3"><WidgetEditor w={w} metrics={metrics} onChange={(nw) => setWidgets((ws) => ws.map((x) => (x.id === w.id ? nw : x)))} /></div>}
          </li>
        ))}
      </ul>

      <div className="flex flex-wrap items-center gap-2 border-t border-border pt-4">
        <Button size="sm" variant="secondary" onClick={add} disabled={widgets.length >= 40}><Plus className="size-3.5" /> Add widget</Button>
        {problems.length > 0 && <span className="text-[12.5px] text-warning">{problems.length} widget{problems.length > 1 ? "s" : ""} to finish</span>}
        <div className="ml-auto flex gap-2">
          <Button size="sm" variant="secondary" onClick={() => router.back()}>Cancel</Button>
          <Button size="sm" onClick={save} disabled={busy || !name.trim()}>{busy && <LoaderCircle className="size-3.5 animate-spin" />} Save dashboard</Button>
        </div>
      </div>
    </div>
  );
}
