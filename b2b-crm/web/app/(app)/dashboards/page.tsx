import type { Metadata } from "next";
import Link from "next/link";
import { BellRing, ChartColumn, Home, Plus, Sigma } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { DIM_LABEL, drillHref, formatValue, formulaText, PERIOD_LABEL, type Period, type Token, type Unit } from "@/lib/analytics";
import { alertsOverview, dashboardsList, metricCatalogue, reportsList } from "@/lib/analytics-data";
import { formatDateTime, relativeTime } from "@/lib/format";
import { ActiveToggle, AlertSettingsForm, MetricAlertForm, MetricForm, ScheduleForm } from "./DeliveryClient";

export const metadata: Metadata = { title: "Dashboards" };
const TABS = [{ id: "gallery", label: "Dashboards" }, { id: "metrics", label: "Metrics" }, { id: "alerts", label: "Alerts & delivery" }] as const;
type Tab = (typeof TABS)[number]["id"];
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

async function Gallery() {
  const l = await dashboardsList();
  const defaults = l.dashboards.filter((d) => d.is_default), mine = l.dashboards.filter((d) => !d.is_default);
  const Tile = ({ d }: { d: (typeof l.dashboards)[number] }) => (
    <Link href={`/dashboards/${d.id}`} className="group flex min-h-[120px] flex-col rounded-[var(--radius-card)] border border-border bg-surface p-4 transition-colors hover:border-ring/50">
      <span className="flex items-center gap-2 text-[14px] font-semibold text-fg group-hover:underline">{d.name}
        {l.home_dashboard_id === d.id && <Badge tone="brand"><Home className="size-3" /> Home</Badge>}</span>
      <span className="mt-1 line-clamp-3 flex-1 text-[12.5px] text-muted">{d.description}</span>
      <span className="mt-2 text-[11.5px] text-subtle">{d.widgets} widgets{!d.is_default && ` · changed ${relativeTime(d.updated_at)}`}</span>
    </Link>
  );
  return (
    <div className="space-y-8">
      <section>
        <h2 className="mb-3 text-[13px] font-semibold text-fg">Built in</h2>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{defaults.map((d) => <Tile key={d.id} d={d} />)}</div>
      </section>
      <section>
        <div className="mb-3 flex items-center gap-3"><h2 className="text-[13px] font-semibold text-fg">Yours</h2>
          <Link href="/dashboards/new/edit" className={buttonClass("secondary", "sm")}><Plus className="size-3.5" /> New dashboard</Link></div>
        {mine.length === 0 ? <p className="text-[13px] text-muted">None yet. Duplicate a built-in one, or start from scratch.</p>
          : <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{mine.map((d) => <Tile key={d.id} d={d} />)}</div>}
      </section>
      {l.views.length > 0 && (
        <section>
          <h2 className="mb-3 text-[13px] font-semibold text-fg">Saved views</h2>
          <ul className="divide-y divide-border rounded-[var(--radius-card)] border border-border bg-surface text-[13px]">
            {l.views.map((v) => <li key={v.id} className="flex items-center gap-3 px-4 py-2.5"><Link href={drillHref(v.metric, v.filters, undefined, undefined, v.period)} className="text-info hover:underline">{v.name}</Link>
              <span className="text-subtle">{v.metric} · {PERIOD_LABEL[v.period as Period] ?? v.period} {Object.keys(v.filters).map((k) => `· ${DIM_LABEL[k] ?? k}`).join(" ")}</span></li>)}
          </ul>
        </section>
      )}
    </div>
  );
}

async function Metrics() {
  const cat = await metricCatalogue();
  const areas = Object.entries(cat.metrics.reduce<Record<string, typeof cat.metrics>>((a, m) => { (a[m.area] ??= []).push(m); return a; }, {}));
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)]">
      <Card className="min-w-0">
        <CardHeader title="Metric catalogue" description={`Every number on every dashboard, report and alert comes from these. Data refreshed ${cat.facts_at ? relativeTime(cat.facts_at) : "every minute"}.`} />
        <div className="divide-y divide-border">
          {areas.map(([area, ms]) => (
            <section key={area} className="px-5 py-3">
              <h3 className="mb-1.5 text-[11px] uppercase tracking-wider text-subtle">{area}</h3>
              <ul className="space-y-1 text-[12.5px]">
                {ms.map((m) => (
                  <li key={m.key} className="flex flex-wrap items-baseline gap-x-2">
                    <Link href={drillHref(m.key, {})} className="font-medium text-fg hover:underline">{m.label}</Link>
                    <span className="font-mono text-[11px] text-subtle">{m.key}</span>
                    {m.calculated && <Badge tone="info">= {formulaText(m.formula as Token[])}</Badge>}
                    {m.description && <span className="text-muted">· {m.description}</span>}
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
      </Card>
      <Card className="min-w-0">
        <CardHeader title="Calculated metric" description="Define it once, use it on any dashboard, report or alert (B13.3)." />
        <div className="px-5 pb-5"><MetricForm metrics={cat.metrics} /></div>
      </Card>
    </div>
  );
}

async function Alerts({ preset }: { preset?: string }) {
  const [a, cat, l, rl] = await Promise.all([alertsOverview(), metricCatalogue(), dashboardsList(), reportsList()]);
  const metricLabel = (key: string) => cat.metrics.find((m) => m.key === key)?.label ?? key;
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <div className="min-w-0 space-y-6">
        <Card className="min-w-0"><CardHeader title="Where alerts go" description="Guardrail alerts (auto-pauses, NCPL drops, SLA breaches, model fallbacks…) as a digest, metric alerts and scheduled reports." />
          <div className="px-5 pb-5"><AlertSettingsForm key={a.settings_version} s={a.settings} emailReady={a.email_ready} /></div></Card>
        <Card className="min-w-0"><CardHeader title="Metric alerts" description="A threshold on any metric, checked every 5 minutes." />
          {a.alerts.length > 0 && (
            <ul className="divide-y divide-border border-b border-border text-[12.5px]">
              {a.alerts.map((x) => (
                <li key={x.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5">
                  <span className="font-medium text-fg">{x.name}</span>
                  <span className="text-muted">{x.metric_label} {x.op} {formatValue(x.threshold, x.unit as Unit)} · {x.window_hours} h{Object.keys(x.filters).length ? ` · ${Object.entries(x.filters).map(([k, v]) => `${DIM_LABEL[k] ?? k}: ${v.join(", ")}`).join("; ")}` : ""}
                    {x.min_volume > 0 && ` · at least ${x.min_volume}${x.volume_metric ? ` ${metricLabel(x.volume_metric)}` : ""}`}</span>
                  <span className="ml-auto text-subtle">{x.active ? (x.last_value !== null ? `now ${formatValue(x.last_value, x.unit as Unit)}` : "not checked yet") : "off"}{x.last_fired_at && ` · fired ${relativeTime(x.last_fired_at)}`}</span>
                  <ActiveToggle kind="alert" id={x.id} active={x.active} />
                </li>
              ))}
            </ul>
          )}
          <div className="px-5 py-4"><MetricAlertForm metrics={cat.metrics} /></div></Card>
      </div>
      <div className="min-w-0 space-y-6">
        <Card className="min-w-0"><CardHeader title="Scheduled delivery" description="A dashboard or report by e-mail, daily, weekly or monthly. For a PDF, open the dashboard and use Print / PDF." />
          {a.schedules.length > 0 && (
            <ul className="divide-y divide-border border-b border-border text-[12.5px]">
              {a.schedules.map((s) => (
                <li key={s.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5">
                  <span className="font-medium text-fg">{s.name}</span>
                  <span className="text-muted">{s.dashboard ?? `Report #${s.report_id}`} · {s.frequency} at {String(s.hour_ist).padStart(2, "0")}:00 · {s.recipients.length} recipient{s.recipients.length > 1 ? "s" : ""}</span>
                  <span className="ml-auto text-subtle">{s.active ? (s.next_due_at ? `next ${formatDateTime(s.next_due_at)}` : "") : s.failures >= 5 ? "off after 5 failures" : "off"}</span>
                  <ActiveToggle kind="schedule" id={s.id} active={s.active} />
                </li>
              ))}
            </ul>
          )}
          <div className="px-5 py-4"><ScheduleForm dashboards={l.dashboards.map((d) => ({ id: d.id, name: d.name }))} reports={rl.reports.map((r) => ({ id: r.id, name: r.name }))} preset={preset} /></div></Card>
        <Card className="min-w-0"><CardHeader title="Messages to you" description="The last 30 alerts and reports queued or sent." />
          {a.messages.length === 0 ? <EmptyState icon={BellRing} title="Nothing sent yet" /> : (
            <ul className="divide-y divide-border text-[12.5px]">
              {a.messages.map((m) => (
                <li key={m.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5">
                  <Badge tone={m.status === "sent" ? "success" : m.status === "failed" ? "danger" : "neutral"}>{m.status}</Badge>
                  <span className="min-w-0 flex-1 truncate text-fg">{m.subject}</span>
                  <span className="text-subtle">{m.channel}{m.attachments ? ` · ${m.attachments} CSV` : ""} · {relativeTime(m.created_at)}</span>
                  {m.error && <p className="w-full text-[12px] text-danger">{m.error}</p>}
                </li>
              ))}
            </ul>
          )}</Card>
      </div>
    </div>
  );
}

export default async function DashboardsPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "gallery";
  return (
    <>
      <PageHeader title="Dashboards" description="Every number answers “show me the leads behind this” with one click. Built-in dashboards for each area, your own, calculated metrics, alerts and scheduled delivery." />
      <nav aria-label="Dashboard sections" className="mb-6 flex gap-5 overflow-x-auto border-b border-border">
        {TABS.map((t) => (
          <Link key={t.id} href={`/dashboards?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px flex shrink-0 items-center gap-1.5 border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.id === "gallery" ? <ChartColumn className="size-3.5" /> : t.id === "metrics" ? <Sigma className="size-3.5" /> : <BellRing className="size-3.5" />}{t.label}
          </Link>
        ))}
      </nav>
      {tab === "gallery" && <Gallery />}
      {tab === "metrics" && <Metrics />}
      {tab === "alerts" && <Alerts preset={typeof sp.schedule === "string" ? sp.schedule : undefined} />}
    </>
  );
}
