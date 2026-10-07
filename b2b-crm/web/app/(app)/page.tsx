import type { Metadata } from "next";
import Link from "next/link";
import { Activity, ArrowRight, BellRing, BookOpen, Building2, Check, CircleDot, Inbox, Radio, ShieldCheck, TriangleAlert, UserCheck } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import { ALERT_LABEL, STREAM_LABEL, STREAM_TONE, delta, flowByDestination, slaShare, type CommandCenter as CC } from "@/lib/overview";
import { commandCenter } from "@/lib/overview-data";
import { inr } from "@/lib/programmes";
import { homeDashboardId } from "@/lib/analytics-data";
import { DashboardView } from "./dashboards/DashboardView";

export const metadata: Metadata = { title: "Command Center" };

const SWITCH_LABELS: Record<string, string> = {
  routing: "Automatic routing",
  whatsapp: "Student WhatsApp",
  email: "Student email",
  capi_meta: "Meta conversions",
  capi_google: "Google conversions",
};

function Kpi({ label, value, hint, d }: { label: string; value: string; hint: string; d?: ReturnType<typeof delta> }) {
  return (
    <Card className="p-4">
      <p className="text-[12px] font-medium text-muted">{label}</p>
      <p className="tabular mt-2 text-2xl font-semibold text-fg">{value}</p>
      <p className="mt-1 text-[11.5px] text-subtle">
        {d ? <span className={cn(d.tone === "up" ? "text-success" : d.tone === "down" ? "text-danger" : "text-muted")}>{d.text}</span> : hint}
      </p>
    </Card>
  );
}

function Road({ c }: { c: CC }) {
  const steps = [
    { done: true, icon: ShieldCheck, title: "Admin access secured", text: "Allowlist, two-step verification and sign-in logging are on." },
    { done: c.has_partners, icon: Building2, title: "Add the first partner", text: "Partner record, CRM connection, SLAs and working hours.", href: "/partners" },
    { done: c.has_offers, icon: BookOpen, title: "Publish its programme file", text: "Excel or CSV, matched to the catalogue.", href: "/programmes" },
    { done: false, icon: UserCheck, title: "Capture partner-sharing consent", text: "Witty and the forms must record it, or every qualified lead goes to B2C." },
    { done: c.live_partners > 0, icon: Radio, title: "Test leads, then go live", text: "Sandbox first; the partner's live switch unlocks when its checklist is complete.", href: "/partners" },
    { done: Boolean(c.switches.routing), icon: Activity, title: "Turn on automatic routing", text: "Every minute, ready leads go to a partner or B2C.", href: "/routing" },
  ];
  return (
    <ol className="divide-y divide-border">
      {steps.map((s, i) => {
        const body = (
          <div className="flex items-start gap-3.5 px-5 py-3.5">
            <span className={cn("mt-0.5 grid size-6 shrink-0 place-items-center rounded-full border text-[11px] font-semibold",
              s.done ? "border-success/30 bg-success-bg text-success" : "border-border bg-surface-2 text-subtle")}>
              {s.done ? <Check className="size-3.5" /> : i + 1}
            </span>
            <div className="min-w-0 flex-1">
              <p className={cn("text-[13.5px] font-medium", s.done ? "text-muted line-through decoration-subtle/50" : "text-fg")}>{s.title}</p>
              <p className="mt-0.5 text-[12.5px] text-muted">{s.text}</p>
            </div>
            {s.href && !s.done && <ArrowRight className="mt-1 size-4 text-subtle transition-transform group-hover:translate-x-0.5" />}
          </div>
        );
        return <li key={s.title}>{s.href && !s.done ? <Link href={s.href} className="group block hover:bg-surface-hover">{body}</Link> : body}</li>;
      })}
    </ol>
  );
}

function Flow({ c }: { c: CC }) {
  const rows = flowByDestination(c.flow);
  const total = rows.reduce((s, r) => s + r.n, 0);
  if (total === 0) return <EmptyState icon={Activity} title="No leads in the last 7 days">Test leads are left out.</EmptyState>;
  return (
    <ul className="space-y-3 px-5 py-4">
      {rows.map((r) => (
        <li key={r.destination}>
          <div className="flex items-baseline justify-between gap-3 text-[13px]">
            <span className="truncate font-medium text-fg">{r.destination}</span>
            <span className="tabular shrink-0 text-muted">{r.n} · {Math.round((r.n / total) * 100)}%</span>
          </div>
          <div className="mt-1 h-2 overflow-hidden rounded-full bg-surface-2">
            <div className={cn("h-full rounded-full", r.destination === "Waiting" ? "bg-subtle/60" : r.destination.startsWith("B2C") ? "bg-info/70"
              : r.destination === "Not passed" ? "bg-subtle" : "bg-primary/80")} style={{ width: `${Math.max(2, (r.n / total) * 100)}%` }} />
          </div>
          <p className="mt-0.5 truncate text-[11.5px] text-subtle">{r.sources.map((s) => `${s.source} ${s.n}`).join(" · ")}</p>
        </li>
      ))}
    </ul>
  );
}

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

/** The home screen: the Command Center, or the dashboard the Admin set as home (B13.3), unless ?view=command. */
export default async function CommandCenter({ searchParams }: Props) {
  const sp = await searchParams;
  if (sp.view !== "command") {
    const home = await homeDashboardId().catch(() => null);
    if (home) return <DashboardView id={home} sp={sp} home />;
  }
  const c = await commandCenter();
  const k = c.kpis;
  const sla = slaShare(k.sla_met_7d, k.sla_due_7d);
  const switches = Object.keys(SWITCH_LABELS).map((scope) => [scope, Boolean(c.switches[scope])] as const);
  const allLive = c.live_partners > 0 && Boolean(c.switches.routing);

  return (
    <>
      <PageHeader title="Command Center" description="Today's leads, where they went, partner health and what needs you. Test leads are left out." />

      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <Kpi label="Leads today" value={String(k.leads_today)} hint="From every source" d={delta(k.leads_today, k.leads_yday)} />
        <Kpi label="To partners today" value={String(k.to_partners_today)} hint={`${k.to_b2c_today} to B2C`} d={delta(k.to_partners_today, k.to_partners_yday)} />
        <Kpi label="Accepted today" value={String(k.accepted_today)} hint="Hold window passed" d={delta(k.accepted_today, k.accepted_yday)} />
        <Kpi label="Duplicate rate" value={k.duplicate_rate_7d === null ? "—" : `${Math.round(k.duplicate_rate_7d * 100)}%`} hint="Last 7 days, of leads sent" />
        <Kpi label="SLA compliance" value={sla === null ? "—" : `${Math.round(sla * 100)}%`} hint={k.sla_due_7d ? `First contact on time, ${k.sla_met_7d} of ${k.sla_due_7d}` : "No first-contact deadline passed yet"} />
        <Kpi label="Commission (month)" value={inr(k.commission_expected_month)} hint={`Expected, net of GST · ${k.accepted_month} accepted`} />
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <div className="min-w-0 space-y-6">
          <Card className="min-w-0">
            <CardHeader title="Partner health" description="Live partners first. Pushes failing now, failures and duplicates are the ones to watch." />
            {c.partners.length === 0 ? (
              <EmptyState icon={Building2} title="No partners yet" action={<Link href="/partners/new" className="text-[13px] text-info hover:underline">Add a partner</Link>}>Until a partner is live, every lead goes to B2C.</EmptyState>
            ) : (
              <ul className="grid gap-3 p-4 sm:grid-cols-2 2xl:grid-cols-3">
                {c.partners.map((p) => {
                  const bad = p.failing > 0 || p.failed_24h > 0;
                  return (
                    <li key={p.id}>
                      <Link href={`/partners/${p.id}?tab=connection`} className={cn("block rounded-lg border p-3 transition-colors hover:border-border-strong",
                        bad ? "border-danger/30 bg-danger-bg/40" : p.live ? "border-success/25" : "border-border")}>
                        <div className="flex items-center justify-between gap-2">
                          <p className="truncate text-[13px] font-semibold text-fg">{p.name}</p>
                          <Badge tone={p.live ? "success" : "neutral"}>{p.live ? "Live" : p.status}</Badge>
                        </div>
                        <dl className="mt-2 grid grid-cols-3 gap-2 text-[11.5px]">
                          <div><dt className="text-subtle">Today</dt><dd className="tabular text-fg">{p.today}{p.daily_cap ? <span className="text-subtle">/{p.daily_cap}</span> : null}</dd></div>
                          <div><dt className="text-subtle">Accepted 7d</dt><dd className="tabular text-fg">{p.accepted_7d}</dd></div>
                          <div><dt className="text-subtle">Duplicates 7d</dt><dd className="tabular text-fg">{p.duplicates_7d}</dd></div>
                        </dl>
                        <p className={cn("mt-2 text-[11.5px]", bad ? "text-danger" : "text-subtle")}>
                          {p.failing > 0 ? `${p.failing} push${p.failing === 1 ? "" : "es"} retrying` : p.failed_24h > 0 ? `${p.failed_24h} failed in 24 h`
                            : p.last_event_at ? `Last event ${relativeTime(p.last_event_at)}` : "No events from the partner yet"}
                        </p>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            )}
          </Card>

          <Card className="min-w-0">
            <CardHeader title="Where leads went" description="Last 7 days, by destination, with their sources." />
            <Flow c={c} />
          </Card>

          <Card className="min-w-0">
            <CardHeader title="Lead stream" description="The latest routing, push and acceptance events." />
            {c.stream.length === 0 ? (
              <EmptyState icon={Activity} title="Quiet so far">Routing decisions, pushes and acceptances stream here.</EmptyState>
            ) : (
              <ul className="divide-y divide-border">
                {c.stream.map((e) => (
                  <li key={e.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5 text-[13px]">
                    <Badge tone={STREAM_TONE[e.type] ?? "neutral"}>{STREAM_LABEL[e.type] ?? e.type}</Badge>
                    {e.lead_id ? <Link href={`/leads?lead=${e.lead_id}`} className="font-medium text-fg hover:underline">{e.lead_name || `Lead #${e.lead_id}`}</Link> : null}
                    {e.partner_name && <span className="text-muted">{e.partner_name}</span>}
                    {e.detail && <span className="min-w-0 truncate text-[12px] text-subtle">{e.detail}</span>}
                    <span className="ml-auto shrink-0 text-[12px] text-subtle" title={formatDateTime(e.at)}>{relativeTime(e.at)}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>

        <div className="min-w-0 space-y-6">
          <Card>
            <CardHeader title="Alerts" description="Last 7 days." />
            {c.alerts.length === 0 ? (
              <EmptyState icon={BellRing} title="No alerts">Push failures, partner rejections, bad signatures, disputes and failed student messages appear here.</EmptyState>
            ) : (
              <ul className="divide-y divide-border">
                {c.alerts.map((a) => (
                  <li key={a.id} className="px-5 py-2.5 text-[13px]">
                    <div className="flex items-center justify-between gap-3">
                      <span className="flex min-w-0 items-center gap-2 font-medium text-fg"><TriangleAlert className="size-3.5 shrink-0 text-danger" /><span className="truncate">{ALERT_LABEL[a.type] ?? a.type}</span></span>
                      <span className="shrink-0 text-[12px] text-subtle" title={formatDateTime(a.at)}>{relativeTime(a.at)}</span>
                    </div>
                    <p className="mt-0.5 truncate text-[12px] text-muted">
                      {a.partner_name && <>{a.partner_name} · </>}
                      {a.lead_id && <Link href={`/leads?lead=${a.lead_id}`} className="hover:underline">Lead #{a.lead_id}</Link>}
                      {a.detail && a.detail !== "{}" && <> · {a.detail}</>}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card>
            <CardHeader title="Pre-routing pool" description="Leads with no destination yet." action={<Link href="/pool" className="shrink-0 text-[13px] text-info hover:underline">Open</Link>} />
            <div className="flex items-center gap-4 px-5 py-4">
              <Inbox className="size-5 text-muted" />
              <p className="text-[13px] text-muted"><span className="tabular text-xl font-semibold text-fg">{c.pool.total}</span> waiting{c.pool.chatting > 0 && <>, {c.pool.chatting} still chatting with Witty</>}</p>
            </div>
          </Card>

          <Card>
            <CardHeader title="Live switches" description="Nothing reaches a real partner, student or ad platform while these are off." />
            <ul className="divide-y divide-border">
              <li className="flex items-center justify-between px-5 py-3">
                <Link href="/partners" className="text-[13px] text-fg hover:underline">Live partners</Link>
                {c.live_partners > 0 ? <Badge tone="success"><CircleDot className="size-3" /> {c.live_partners}</Badge> : <Badge>None</Badge>}
              </li>
              {switches.map(([scope, live]) => (
                <li key={scope} className="flex items-center justify-between px-5 py-3">
                  <Link href={scope === "routing" ? "/routing" : scope === "whatsapp" || scope === "email" ? "/notifications" : "/capi"} className="text-[13px] text-fg hover:underline">{SWITCH_LABELS[scope] ?? scope}</Link>
                  {live ? <Badge tone="success"><CircleDot className="size-3" /> Live</Badge> : <Badge>Off</Badge>}
                </li>
              ))}
            </ul>
          </Card>

          {!allLive && (
            <Card>
              <CardHeader title="Road to the first routed lead" description="What has to be in place before the engine allocates a real lead." />
              <Road c={c} />
            </Card>
          )}
        </div>
      </div>
    </>
  );
}
