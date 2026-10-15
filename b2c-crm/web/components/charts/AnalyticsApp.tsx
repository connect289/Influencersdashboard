"use client";
import { useEffect, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ArrowDown, ArrowUp, Bell, CalendarClock, Copy, Download, Home, Pencil, Plus, Send, Sparkles, Trash2, X } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { Chart, type Defs } from "@/components/charts/Chart";
import { Insights } from "@/components/charts/Insights";
import { alertSave, ask, dashboardAct, dashboardPublish, dashboardSave, drill, explain, runSpec, scheduleSave } from "@/app/analytics-actions";
import { toCsv } from "@/lib/csv";
import { effectiveSpec, RANGES, resolveRange, resultTable, VIZ, type Catalog, type Dashboard, type DashFilters, type Result, type Spec, type Viz, type Widget } from "@/lib/analytics";

export type DashList = { home: number | null; standard: { id: number; name: string; description: string | null; roles: string[] }[]; mine: { id: number; name: string }[] };
export type Insight = { id: number; day: string; kind: string; items: { title: string; body: string; metric?: string; spec?: Spec }[] };
export type Schedule = { id: number; dashboard_id: number; dashboard: string; freq: string; format: string; hour_ist: number; weekday: number | null; monthday: number | null; active: boolean; next_at: string; last_error: string | null };
export type Alert = { id: number; name: string; label: string; metric: string; kind: string; op: string | null; threshold: number | null; win: string; channels: string[]; active: boolean; last_value: number | null; last_fired_at: string | null };

const VIZ_LABEL: Record<Viz, string> = { kpi: "Number", line: "Line over time", bar: "Bars", stacked: "Stacked columns", funnel: "Funnel", cohort: "Cohort grid", table: "Table",
  pivot: "Pivot", leaderboard: "Leaderboard", gauge: "Gauge", map: "Map tiles", text: "Text note" };
const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
type Slot = { loading: boolean; result?: Result; error?: string; explain?: { summary: string; points: string[] } };

function download(name: string, text: string) {
  const url = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url; a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/**
 * Analytics (spec B13): one dashboard at a time with filters that apply to every widget, an editor, Ask in plain words,
 * Explain on any chart, schedules and alerts. Every number opens its leads on the Leads page.
 */
export function AnalyticsApp({ base, catalog, list, dash, insights, schedules, alerts, admin }: {
  base: "/w" | "/s"; catalog: Catalog; list: DashList; dash: Dashboard; insights: Insight[]; schedules: Schedule[]; alerts: Alert[]; admin: boolean;
}) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [filters, setFilters] = useState<DashFilters>({ range: "30d", compare: "previous", ...dash.filters });
  const [test, setTest] = useState(false);
  const [editing, setEditing] = useState(false);
  const [widgets, setWidgets] = useState<Widget[]>(dash.widgets);
  const [name, setName] = useState(dash.name);
  const [slots, setSlots] = useState<Record<string, Slot>>({});
  const [builder, setBuilder] = useState<Widget | null>(null);
  const [sheet, setSheet] = useState<"schedule" | "alert" | "publish" | null>(null);

  const defs: Defs = useMemo(() => Object.fromEntries(catalog.metrics.map((m) => [m.key, { label: m.label, fmt: m.fmt, higher_is_better: m.higher_is_better, counts_leads: m.counts_leads }])), [catalog]);
  const dimLabels = useMemo(() => Object.fromEntries(catalog.dims.map((d) => [d.key, d.label])), [catalog]);
  const labels = useMemo(() => ({ ...dimLabels, ...Object.fromEntries(catalog.metrics.map((m) => [m.key, m.label])) }), [catalog, dimLabels]);
  const range = resolveRange(filters.range, new Date(), filters);

  useEffect(() => { setWidgets(dash.widgets); setName(dash.name); setFilters({ range: "30d", compare: "previous", ...dash.filters }); setEditing(false); }, [dash]);

  // run every widget whenever the widgets, the filters or test mode change
  const key = JSON.stringify([widgets.map((w) => [w.id, w.spec, w.viz]), filters, test]);
  useEffect(() => {
    let live = true;
    const todo = widgets.filter((w) => w.viz !== "text");
    setSlots((s) => Object.fromEntries(todo.map((w) => [w.id, { ...s[w.id], loading: true, explain: undefined }])));
    for (const w of todo) {
      runSpec(effectiveSpec(w, filters, test)).then((r) => {
        if (!live) return;
        setSlots((s) => ({ ...s, [w.id]: r.ok ? { loading: false, result: r.data } : { loading: false, error: r.error } }));
      });
    }
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const openLeads = (w: Widget | null, spec: Spec, metric: string, cell: Record<string, string | null>) => start(async () => {
    const r = await drill(spec, metric, cell);
    if (!r.ok || !r.data) return void toast.error(r.ok ? "Could not open the leads." : r.error);
    if (r.data.count === 0) return void toast.info("No leads behind this number.");
    const lbl = `${defs[metric]?.label ?? metric}${Object.values(cell).filter(Boolean).length ? ` · ${Object.values(cell).filter(Boolean).join(" · ")}` : ""}${w ? ` (${w.title})` : ""}`;
    router.push(`${base}/leads?drill=${r.data.drill_id}&dl=${encodeURIComponent(lbl.slice(0, 120))}`);
  });

  const save = (ws = widgets, after?: (id: number) => void) => start(async () => {
    const r = await dashboardSave({ id: dash.id, name, widgets: ws, filters: { range: filters.range, from: filters.from, to: filters.to, compare: filters.compare ?? null, filters: filters.filters ?? [] } });
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.data !== dash.id ? "Saved as your own copy." : r.notice ?? "Saved.");
    setEditing(false);
    after?.(r.data!);
    if (r.data !== dash.id) router.push(`${base}/analytics?d=${r.data}`); else router.refresh();
  });
  const doAct = (action: "duplicate" | "home" | "archive") => start(async () => {
    const r = await dashboardAct(dash.id, action);
    if (!r.ok) return void toast.error(r.error);
    if (r.notice) toast.success(r.notice);
    if (action === "duplicate") router.push(`${base}/analytics?d=${r.data}`);
    else if (action === "archive") router.push(`${base}/analytics`);
    else router.refresh();
  });
  const doExplain = (w: Widget) => start(async () => {
    const r = await explain(w.title, effectiveSpec(w, filters, test), labels);
    if (!r.ok) return void toast.error(r.error);
    setSlots((s) => ({ ...s, [w.id]: { ...s[w.id]!, explain: r.data } }));
  });
  const move = (i: number, d: -1 | 1) => { const ws = [...widgets]; const [x] = ws.splice(i, 1); ws.splice(i + d, 0, x!); setWidgets(ws); };
  const editable = dash.mine || (dash.standard && admin);

  return (
    <div className="stack">
      <div className="row wrap" style={{ gap: 6 }}>
        <select className="input" style={{ width: "auto", maxWidth: 280 }} value={dash.id} aria-label="Dashboard" onChange={(e) => router.push(`${base}/analytics?d=${e.target.value}`)}>
          <optgroup label="Standard">{list.standard.map((d) => <option key={d.id} value={d.id}>{d.name}{list.home === d.id ? " (home)" : ""}</option>)}</optgroup>
          {list.mine.length > 0 && <optgroup label="Mine">{list.mine.map((d) => <option key={d.id} value={d.id}>{d.name}{list.home === d.id ? " (home)" : ""}</option>)}</optgroup>}
        </select>
        <span className="grow" />
        {!editing && <>
          {editable || dash.standard ? <button type="button" className="btn ghost sm" onClick={() => setEditing(true)}><Pencil className="icon s" aria-hidden />Edit</button> : null}
          <button type="button" className="btn quiet sm" disabled={busy} onClick={() => doAct("duplicate")}><Copy className="icon s" aria-hidden />Copy</button>
          {!dash.home && <button type="button" className="btn quiet sm" disabled={busy} onClick={() => doAct("home")}><Home className="icon s" aria-hidden />Make home</button>}
          <button type="button" className="btn quiet sm" onClick={() => setSheet("schedule")}><CalendarClock className="icon s" aria-hidden />Email it</button>
          <button type="button" className="btn quiet sm" onClick={() => setSheet("alert")}><Bell className="icon s" aria-hidden />Alerts</button>
          {admin && <button type="button" className="btn quiet sm" onClick={() => setSheet("publish")}><Send className="icon s" aria-hidden />Publish</button>}
          {dash.mine && <button type="button" className="btn quiet sm" disabled={busy} onClick={() => confirm("Archive this dashboard?") && doAct("archive")}><Trash2 className="icon s" aria-hidden />Archive</button>}
        </>}
      </div>
      {dash.description && !editing && <p className="note">{dash.description}</p>}

      <FilterBar filters={filters} setFilters={setFilters} catalog={catalog} range={range} test={test} setTest={admin ? setTest : undefined} />

      {!editing && <AskBox catalog={catalog} defs={defs} dimLabels={dimLabels} onDrill={(spec, m, c) => openLeads(null, spec, m, c)}
        onAdd={(w) => save([...widgets, w])} scope={catalog.scope} />}

      {!editing && (insights.length > 0 || base === "/w") && <Insights insights={insights} defs={defs} dimLabels={dimLabels} canWrite={base === "/w"} />}

      {editing && (
        <div className="banner info">
          <div className="grow stack" style={{ gap: 6 }}>
            <label className="field"><span>Dashboard name</span><input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={120} /></label>
            <span className="small">{dash.standard && !admin ? "This is a standard dashboard: saving makes your own copy." : dash.standard ? "You are editing the standard dashboard everyone in its roles sees." : "Your dashboard."}
              {" "}The current filters are saved with it.</span>
          </div>
          <div className="stack" style={{ gap: 4 }}>
            <button type="button" className="btn primary sm" disabled={busy} onClick={() => save()}>Save</button>
            <button type="button" className="btn ghost sm" onClick={() => setBuilder({ id: `w${Date.now().toString(36)}`, title: "", viz: "kpi", w: 1, spec: { metrics: [catalog.metrics[0]?.key ?? "leads_new"] } })}><Plus className="icon s" aria-hidden />Add widget</button>
            <button type="button" className="btn quiet sm" onClick={() => { setWidgets(dash.widgets); setEditing(false); }}>Cancel</button>
          </div>
        </div>
      )}

      {widgets.length === 0 ? <div className="empty">No widgets yet. {editing ? "Add one." : "Edit the dashboard to add one, or ask a question above."}</div> : (
        <div className="dash-grid">
          {widgets.map((w, i) => {
            const slot = slots[w.id];
            const spec = effectiveSpec(w, filters, test);
            return (
              <section key={w.id} className="card pad stack" style={{ ["--w" as string]: w.w ?? (w.viz === "kpi" || w.viz === "gauge" ? 1 : 2), gap: 8 }}>
                <div className="row" style={{ gap: 4, alignItems: "flex-start" }}>
                  <h3 className="grow" style={{ fontSize: 13 }}>{w.title}</h3>
                  {editing ? <>
                    <button type="button" className="btn quiet sm" aria-label="Move up" disabled={i === 0} onClick={() => move(i, -1)}><ArrowUp className="icon s" aria-hidden /></button>
                    <button type="button" className="btn quiet sm" aria-label="Move down" disabled={i === widgets.length - 1} onClick={() => move(i, 1)}><ArrowDown className="icon s" aria-hidden /></button>
                    <button type="button" className="btn quiet sm" onClick={() => setBuilder(w)}>Edit</button>
                    <button type="button" className="btn quiet sm" aria-label="Remove" onClick={() => setWidgets(widgets.filter((x) => x.id !== w.id))}><X className="icon s" aria-hidden /></button>
                  </> : w.viz !== "text" && slot?.result && <>
                    <button type="button" className="btn quiet sm" title="Explain this chart" disabled={busy} onClick={() => doExplain(w)}><Sparkles className="icon s" aria-hidden /></button>
                    <button type="button" className="btn quiet sm" title="Download CSV" onClick={() => { const t = resultTable(slot.result!, labels); download(`${w.title}.csv`, toCsv(t.columns, t.rows)); }}><Download className="icon s" aria-hidden /></button>
                  </>}
                </div>
                {w.viz === "text" ? <Chart viz="text" result={{ rows: [], metrics: [], dims: [], from: "", to: "", compare: null, test: false, scope: "", sql: [], defs: null }} defs={defs} dimLabels={dimLabels} note={w.note} />
                  : !slot || slot.loading ? <p className="note">Loading…</p>
                  : slot.error ? <p className="small" style={{ color: "var(--red)" }}>{slot.error}</p>
                  : <Chart viz={w.viz} result={slot.result!} defs={defs} dimLabels={dimLabels} onDrill={editing ? undefined : (m, c) => openLeads(w, spec, m, c)} />}
                {slot?.explain && (
                  <div className="brief"><b className="small"><Sparkles className="icon s" aria-hidden /> Explained by Claude</b><p>{slot.explain.summary}</p>
                    {slot.explain.points.length > 0 && <ul>{slot.explain.points.map((p, j) => <li key={j}>{p}</li>)}</ul>}</div>
                )}
              </section>
            );
          })}
        </div>
      )}

      {builder && <WidgetBuilder initial={builder} catalog={catalog} onClose={() => setBuilder(null)}
        onSave={(w) => { setWidgets(widgets.some((x) => x.id === w.id) ? widgets.map((x) => (x.id === w.id ? w : x)) : [...widgets, w]); setBuilder(null); }} />}
      {sheet === "schedule" && <ScheduleSheet dashboard={dash} schedules={schedules} onClose={() => setSheet(null)} />}
      {sheet === "alert" && <AlertSheet catalog={catalog} alerts={alerts} onClose={() => setSheet(null)} />}
      {sheet === "publish" && <PublishSheet dashboard={dash} onClose={() => setSheet(null)} />}
    </div>
  );
}

function FilterBar({ filters, setFilters, catalog, range, test, setTest }: {
  filters: DashFilters; setFilters: (f: DashFilters) => void; catalog: Catalog; range: { from: string; to: string }; test: boolean; setTest?: (v: boolean) => void;
}) {
  const [dim, setDim] = useState("");
  const [val, setVal] = useState("");
  const fs = filters.filters ?? [];
  const dimLabel = (k: string) => catalog.dims.find((d) => d.key === k)?.label ?? k;
  return (
    <div className="card pad row wrap" style={{ gap: 8 }} role="group" aria-label="Filters for every widget">
      <select className="input" style={{ width: "auto" }} value={filters.range ?? "30d"} aria-label="Period" onChange={(e) => setFilters({ ...filters, range: e.target.value, ...(e.target.value === "custom" ? range : {}) })}>
        {RANGES.map((r) => <option key={r.key} value={r.key}>{r.label}</option>)}
      </select>
      {filters.range === "custom" && <>
        <input className="input" type="date" style={{ width: "auto" }} value={filters.from ?? range.from} aria-label="From" onChange={(e) => setFilters({ ...filters, from: e.target.value })} />
        <input className="input" type="date" style={{ width: "auto" }} value={filters.to ?? range.to} aria-label="To" onChange={(e) => setFilters({ ...filters, to: e.target.value })} />
      </>}
      <select className="input" style={{ width: "auto" }} value={filters.compare ?? ""} aria-label="Compare with" onChange={(e) => setFilters({ ...filters, compare: (e.target.value || null) as DashFilters["compare"] })}>
        <option value="">No comparison</option><option value="previous">vs previous period</option><option value="year">vs a year before</option>
      </select>
      <span className="small muted">{range.from} – {range.to} (IST)</span>
      {fs.map((f, i) => (
        <span key={i} className="chip soft">{dimLabel(f.dim)} = {Array.isArray(f.value) ? f.value.join(", ") : f.value}
          <button type="button" className="btn quiet sm" style={{ padding: 0 }} aria-label="Remove filter" onClick={() => setFilters({ ...filters, filters: fs.filter((_, j) => j !== i) })}><X className="icon s" aria-hidden /></button></span>
      ))}
      <span className="row" style={{ gap: 4 }}>
        <select className="input" style={{ width: "auto" }} value={dim} aria-label="Filter by" onChange={(e) => setDim(e.target.value)}>
          <option value="">Filter by…</option>{catalog.dims.filter((d) => !["day", "week", "month"].includes(d.key)).map((d) => <option key={d.key} value={d.key}>{d.label}</option>)}
        </select>
        {dim && <>
          <input className="input" style={{ width: 140 }} value={val} onChange={(e) => setVal(e.target.value)} placeholder="value" aria-label="Value" />
          <button type="button" className="btn ghost sm" disabled={!val.trim()} onClick={() => { setFilters({ ...filters, filters: [...fs, { dim, op: "eq", value: val.trim() }] }); setDim(""); setVal(""); }}>Add</button>
        </>}
      </span>
      {setTest && <label className="row small" style={{ marginLeft: "auto" }}><input type="checkbox" checked={test} onChange={(e) => setTest(e.target.checked)} /> Test leads only</label>}
    </div>
  );
}

function AskBox({ catalog, defs, dimLabels, onDrill, onAdd, scope }: {
  catalog: Catalog; defs: Defs; dimLabels: Record<string, string>; onDrill: (spec: Spec, m: string, c: Record<string, string | null>) => void; onAdd: (w: Widget) => void; scope: string;
}) {
  const [q, setQ] = useState("");
  const [busy, start] = useTransition();
  const [answer, setAnswer] = useState<{ title: string; viz: Viz; spec: Spec; result: Result } | null>(null);
  const go = () => start(async () => {
    const r = await ask(q);
    if (!r.ok) return void toast.error(r.error);
    setAnswer(r.data ?? null);
  });
  return (
    <section className="card pad stack" style={{ gap: 8 }}>
      <form className="row" style={{ gap: 6 }} onSubmit={(e) => { e.preventDefault(); if (q.trim().length > 3) go(); }}>
        <Sparkles className="icon" aria-hidden />
        <input className="input grow" value={q} onChange={(e) => setQ(e.target.value)} maxLength={500} aria-label="Ask a question about your numbers"
          placeholder={catalog.group === "sales" ? "e.g. How many of my leads moved to Applicant this month, by source?" : "e.g. Which source brought the most enrolments in the last 90 days?"} />
        <button type="submit" className="btn primary sm" disabled={busy || q.trim().length < 4}>{busy ? "Thinking…" : "Ask"}</button>
      </form>
      <p className="note">Claude turns the question into a query from the metric catalogue; the CRM runs it with your access ({scope}). It never sees a phone number or email.</p>
      {answer && (
        <div className="stack" style={{ gap: 6 }}>
          <div className="row"><h3 className="grow">{answer.title}</h3>
            <button type="button" className="btn ghost sm" onClick={() => { onAdd({ id: `w${Date.now().toString(36)}`, title: answer.title.slice(0, 120), viz: answer.viz, w: answer.viz === "kpi" ? 1 : 2,
              spec: { ...answer.spec, from: undefined, to: undefined, compare: undefined } }); setAnswer(null); }}><Plus className="icon s" aria-hidden />Add to dashboard</button>
            <button type="button" className="btn quiet sm" aria-label="Close" onClick={() => setAnswer(null)}><X className="icon s" aria-hidden /></button></div>
          <Chart viz={answer.viz} result={answer.result} defs={defs} dimLabels={dimLabels} onDrill={(m, c) => onDrill(answer.spec, m, c)} />
          <details><summary className="small">The query that ran ({answer.result.from} – {answer.result.to}{answer.result.compare ? ", with comparison" : ""})</summary>
            <pre className="small mono" style={{ whiteSpace: "pre-wrap", margin: "6px 0 0" }}>{JSON.stringify({ metrics: answer.spec.metrics, dims: answer.spec.dims, filters: answer.spec.filters }, null, 1)}{"\n\n"}{answer.result.sql.map((s) => `-- ${s.metric}\n${s.sql}`).join("\n\n")}</pre></details>
        </div>
      )}
    </section>
  );
}

function WidgetBuilder({ initial, catalog, onClose, onSave }: { initial: Widget; catalog: Catalog; onClose: () => void; onSave: (w: Widget) => void }) {
  const [w, setW] = useState<Widget>(initial);
  const [area, setArea] = useState("");
  const areas = [...new Set(catalog.metrics.map((m) => m.area))];
  const metrics = w.spec.metrics;
  const dims = w.spec.dims ?? [];
  const toggleMetric = (k: string) => setW({ ...w, spec: { ...w.spec, metrics: metrics.includes(k) ? metrics.filter((x) => x !== k) : [...metrics, k].slice(0, 6) } });
  const setDim = (i: number, k: string) => { const d = [...dims]; if (k) d[i] = k; else d.splice(i, 1); setW({ ...w, spec: { ...w.spec, dims: d.filter(Boolean).slice(0, 2) } }); };
  const valid = w.title.trim() && (w.viz === "text" ? !!w.note?.trim() : metrics.length > 0);
  return (
    <Sheet title={initial.title ? "Edit widget" : "New widget"} onClose={onClose}>
      <div className="stack">
        <label className="field"><span>Title</span><input className="input" value={w.title} onChange={(e) => setW({ ...w, title: e.target.value })} maxLength={120} /></label>
        <div className="grid g2">
          <label className="field"><span>Chart</span><select className="input" value={w.viz} onChange={(e) => setW({ ...w, viz: e.target.value as Viz })}>{VIZ.map((v) => <option key={v} value={v}>{VIZ_LABEL[v]}</option>)}</select></label>
          <label className="field"><span>Width</span><select className="input" value={w.w ?? 2} onChange={(e) => setW({ ...w, w: Number(e.target.value) })}>{[1, 2, 3, 4].map((n) => <option key={n} value={n}>{n} of 4</option>)}</select></label>
        </div>
        {w.viz === "text" ? (
          <label className="field"><span>Note</span><textarea className="input" rows={5} value={w.note ?? ""} onChange={(e) => setW({ ...w, note: e.target.value })} maxLength={2000} /></label>
        ) : <>
          <div className="field"><span>Metrics ({metrics.length} of 6){w.viz === "funnel" ? ", in funnel order" : ""}</span>
            <select className="input" value={area} onChange={(e) => setArea(e.target.value)} aria-label="Area"><option value="">Every area</option>{areas.map((a) => <option key={a} value={a}>{a}</option>)}</select>
            <div className="stack" style={{ maxHeight: 220, overflow: "auto", gap: 2, marginTop: 4 }}>
              {catalog.metrics.filter((m) => !area || m.area === area).map((m) => (
                <label key={m.key} className="row small" title={m.description ?? undefined}><input type="checkbox" checked={metrics.includes(m.key)} onChange={() => toggleMetric(m.key)} />{m.label}<span className="muted">{m.as_of_now ? " · as of now" : ""}</span></label>
              ))}
            </div>
          </div>
          <div className="grid g2">
            {[0, 1].map((i) => (
              <label key={i} className="field"><span>{i === 0 ? "Split by" : "Then by"}</span>
                <select className="input" value={dims[i] ?? ""} onChange={(e) => setDim(i, e.target.value)} disabled={i === 1 && !dims[0]}>
                  <option value="">{i === 0 ? "Nothing (one number)" : "Nothing"}</option>{catalog.dims.map((d) => <option key={d.key} value={d.key}>{d.label}</option>)}
                </select></label>
            ))}
          </div>
          <p className="note">The dashboard's period and filters apply. Line charts want a day, week or month split; stacked and pivot want two splits.</p>
        </>}
        <button type="button" className="btn primary block" disabled={!valid} onClick={() => onSave({ ...w, title: w.title.trim() })}>Done</button>
      </div>
    </Sheet>
  );
}

function ScheduleSheet({ dashboard, schedules, onClose }: { dashboard: Dashboard; schedules: Schedule[]; onClose: () => void }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [f, setF] = useState({ freq: "weekly", format: "pdf", hour_ist: 8, weekday: 1, monthday: 1 });
  const run = (p: Parameters<typeof scheduleSave>[0]) => start(async () => {
    const r = await scheduleSave(p);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Saved.");
    router.refresh();
  });
  const mine = schedules.filter((s) => s.dashboard_id === dashboard.id);
  return (
    <Sheet title={`Email “${dashboard.name}”`} onClose={onClose}>
      <div className="stack">
        {mine.map((s) => (
          <div key={s.id} className="row small" style={{ gap: 6 }}>
            <span className="grow">{s.freq} at {s.hour_ist}:00 IST as {s.format.toUpperCase()}{s.freq === "weekly" && s.weekday ? ` on ${WEEKDAYS[s.weekday - 1]}` : ""}{s.freq === "monthly" && s.monthday ? ` on day ${s.monthday}` : ""}
              {s.active ? "" : " (stopped)"}{s.last_error ? <span style={{ color: "var(--red)" }}> · last error: {s.last_error}</span> : null}</span>
            <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run({ id: s.id, dashboard_id: s.dashboard_id, freq: s.freq, format: s.format, hour_ist: s.hour_ist, weekday: s.weekday, monthday: s.monthday, active: !s.active })}>{s.active ? "Stop" : "Start"}</button>
          </div>
        ))}
        <div className="grid g2">
          <label className="field"><span>How often</span><select className="input" value={f.freq} onChange={(e) => setF({ ...f, freq: e.target.value })}><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="monthly">Monthly</option></select></label>
          <label className="field"><span>As</span><select className="input" value={f.format} onChange={(e) => setF({ ...f, format: e.target.value })}><option value="pdf">PDF</option><option value="csv">CSV</option></select></label>
          <label className="field"><span>Hour (IST)</span><select className="input" value={f.hour_ist} onChange={(e) => setF({ ...f, hour_ist: Number(e.target.value) })}>{Array.from({ length: 24 }, (_, h) => <option key={h} value={h}>{String(h).padStart(2, "0")}:00</option>)}</select></label>
          {f.freq === "weekly" && <label className="field"><span>Day</span><select className="input" value={f.weekday} onChange={(e) => setF({ ...f, weekday: Number(e.target.value) })}>{WEEKDAYS.map((d, i) => <option key={d} value={i + 1}>{d}</option>)}</select></label>}
          {f.freq === "monthly" && <label className="field"><span>Day of month</span><input className="input num" type="number" min={1} max={28} value={f.monthday} onChange={(e) => setF({ ...f, monthday: Number(e.target.value) })} /></label>}
        </div>
        <p className="note">Sent to your own email address with the dashboard's saved filters, as you see it.</p>
        <button type="button" className="btn primary block" disabled={busy} onClick={() => run({ dashboard_id: dashboard.id, freq: f.freq, format: f.format, hour_ist: f.hour_ist,
          weekday: f.freq === "weekly" ? f.weekday : null, monthday: f.freq === "monthly" ? f.monthday : null })}>Add schedule</button>
      </div>
    </Sheet>
  );
}

function AlertSheet({ catalog, alerts, onClose }: { catalog: Catalog; alerts: Alert[]; onClose: () => void }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [f, setF] = useState({ name: "", metric: catalog.metrics[0]?.key ?? "", kind: "threshold", op: "above", threshold: "", win: "today", push: true, email: false, whatsapp: false });
  const run = (p: Parameters<typeof alertSave>[0]) => start(async () => {
    const r = await alertSave(p);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Saved.");
    router.refresh();
  });
  return (
    <Sheet title="Alerts" onClose={onClose}>
      <div className="stack">
        {alerts.map((a) => (
          <div key={a.id} className="row small" style={{ gap: 6 }}>
            <span className="grow"><b>{a.name}</b>: {a.label} {a.kind === "anomaly" ? "moves unusually" : `${a.op} ${a.threshold}`} ({a.win === "7d" ? "last 7 days" : "today"}){a.active ? "" : " · stopped"}
              {a.last_value !== null ? <span className="muted"> · now {a.last_value}</span> : null}</span>
            <button type="button" className="btn quiet sm" disabled={busy} onClick={() => run({ id: a.id, name: a.name, metric: a.metric, kind: a.kind, op: a.op, threshold: a.threshold, win: a.win, channels: a.channels, active: !a.active })}>{a.active ? "Stop" : "Start"}</button>
          </div>
        ))}
        <label className="field"><span>Name</span><input className="input" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} placeholder="e.g. SLA breaches today" /></label>
        <label className="field"><span>Metric</span><select className="input" value={f.metric} onChange={(e) => setF({ ...f, metric: e.target.value })}>{catalog.metrics.map((m) => <option key={m.key} value={m.key}>{m.label}</option>)}</select></label>
        <div className="grid g2">
          <label className="field"><span>When</span><select className="input" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}><option value="threshold">It crosses a number</option><option value="anomaly">It moves unusually (vs 28 days)</option></select></label>
          <label className="field"><span>Over</span><select className="input" value={f.win} onChange={(e) => setF({ ...f, win: e.target.value })}><option value="today">Today</option><option value="7d">The last 7 days</option></select></label>
          {f.kind === "threshold" && <>
            <label className="field"><span>Goes</span><select className="input" value={f.op} onChange={(e) => setF({ ...f, op: e.target.value })}><option value="above">Above</option><option value="below">Below</option></select></label>
            <label className="field"><span>Number</span><input className="input num" inputMode="decimal" value={f.threshold} onChange={(e) => setF({ ...f, threshold: e.target.value })} /></label>
          </>}
        </div>
        <div className="row small" style={{ gap: 12 }}>
          <label className="row"><input type="checkbox" checked={f.push} onChange={(e) => setF({ ...f, push: e.target.checked })} /> Phone alert</label>
          <label className="row"><input type="checkbox" checked={f.email} onChange={(e) => setF({ ...f, email: e.target.checked })} /> Email</label>
          <label className="row"><input type="checkbox" checked={f.whatsapp} onChange={(e) => setF({ ...f, whatsapp: e.target.checked })} /> WhatsApp to my number</label>
        </div>
        {f.whatsapp && <p className="note">Goes to your own mobile number in Teams, from the Eduwit B2C number, once the staff_alert template is approved by Meta.</p>}
        <p className="note">Checked every 15 minutes, in your own scope; at most one alert a day each.</p>
        <button type="button" className="btn primary block" disabled={busy} onClick={() => run({ name: f.name, metric: f.metric, kind: f.kind, op: f.kind === "threshold" ? f.op : null,
          threshold: f.kind === "threshold" && f.threshold !== "" ? Number(f.threshold) : null, win: f.win, channels: [...(f.push ? ["push"] : []), ...(f.email ? ["email"] : []), ...(f.whatsapp ? ["whatsapp"] : [])] })}>Add alert</button>
      </div>
    </Sheet>
  );
}

function PublishSheet({ dashboard, onClose }: { dashboard: Dashboard; onClose: () => void }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [roles, setRoles] = useState<string[]>(dashboard.standard ? dashboard.roles : ["admin"]);
  const toggle = (r: string) => setRoles(roles.includes(r) ? roles.filter((x) => x !== r) : [...roles, r]);
  return (
    <Sheet title="Publish as a standard dashboard" onClose={onClose}>
      <div className="stack">
        <p className="note">{dashboard.standard ? "Changes who sees this standard dashboard." : "Copies this dashboard as a standard one for the roles you choose. Each person still sees only their own scope."}</p>
        {[["admin", "Admin"], ["marketing", "Marketing"], ["sales", "Sales (counsellors and the sales head)"]].map(([k, l]) => (
          <label key={k} className="row small"><input type="checkbox" checked={roles.includes(k!)} onChange={() => toggle(k!)} /> {l}</label>
        ))}
        <button type="button" className="btn primary block" disabled={busy || roles.length === 0} onClick={() => start(async () => {
          const r = await dashboardPublish(dashboard.id, roles);
          if (!r.ok) return void toast.error(r.error);
          toast.success(r.notice ?? "Published.");
          onClose();
          router.push(`/w/analytics?d=${r.data}`);
        })}>Publish</button>
      </div>
    </Sheet>
  );
}
