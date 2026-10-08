import type { Metadata } from "next";
import Link from "next/link";
import {
  Activity, ArrowRight, BellRing, BookOpen, Building2, Check, CircleAlert, CircleDot, Inbox, Radio, ShieldCheck, Sparkles, TriangleAlert, UserCheck,
} from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import {
  ALERT_LABEL, STREAM_LABEL, STREAM_TONE, delta, flowByDestination, gainText, insightHref, insightTitle, slaShare, type CommandCenter as CC,
} from "@/lib/overview";
import { commandCenter } from "@/lib/overview-data";
import { inr } from "@/lib/programmes";
import { GOLIVE_LABEL, golivePasses, goliveBlocking, type GoliveItem } from "@/lib/routing";
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

const tile = "block rounded-[var(--radius-card)] border border-border bg-surface p-4";

function Kpi({ label, value, hint, d, href, alert }: { label: string; value: string; hint: string; d?: ReturnType<typeof delta>; href?: string; alert?: boolean }) {
  const body = (
    <>
      <p className="text-[12px] font-medium text-muted">{label}</p>
      <p className={cn("tabular mt-2 text-2xl font-semibold", alert ? "text-warning" : "text-fg")}>{value}</p>
      <p className="mt-1 text-[11.5px] text-subtle">
        {d ? <span className={cn(d.tone === "up" ? "text-success" : d.tone === "down" ? "text-danger" : "text-muted")}>{d.text}</span> : hint}
      </p>
    </>
  );
  return href ? <Link href={href} className={cn(tile, "transition-colors hover:border-border-strong")}>{body}</Link> : <Card className="p-4">{body}</Card>;
}

/** The three most valuable current AI recommendations or anomalies (C91). */
function Insights({ c }: { c: CC }) {
  if (c.insights.length === 0) return null;
  return (
    <div className="mb-6 grid gap-3 md:grid-cols-3" aria-label="AI insights">
      {c.insights.map((i) => (
        <Link key={`${i.source}-${i.id}`} href={insightHref(i)} className={cn(tile, "transition-colors hover:border-border-strong")}>
          <div className="flex items-center justify-between gap-2">
            {i.source === "recommendation"
              ? <Badge tone="info"><Sparkles className="size-3" /> AI recommendation</Badge>
              : <Badge tone="warning"><CircleAlert className="size-3" /> Anomaly</Badge>}
            <span className="shrink-0 text-[11.5px] text-subtle" title={formatDateTime(i.occurred_at)}>{relativeTime(i.occurred_at)}</span>
          </div>
          <p className="mt-2 line-clamp-2 text-[13.5px] font-medium text-fg">{insightTitle(i)}</p>
          <p className="mt-1 text-[12px] text-muted">
            {i.gain_pct !== null ? <span className={i.gain_pct >= 0 ? "text-success" : "text-danger"}>Simulated {gainText(i.gain_pct)} net commission per lead</span>
              : i.source === "recommendation" ? "Open on the AI Optimiser to review"
              : i.partner_id ? "Open the partner" : "Open the AI Optimiser"}
          </p>
        </Link>
      ))}
    </div>
  );
}

/** The routing go-live checklist (routing_golive_check, D10 / PART 7): what set_live_switch('routing') insists on. */
function Golive({ items, routingLive }: { items: GoliveItem[]; routingLive: boolean }) {
  const blocking = goliveBlocking(items);
  return (
    <Card>
      <CardHeader title="Routing go-live checklist"
        description={routingLive
          ? "Routing is live. These were checked when it went live; a red item means something has changed since."
          : "Automatic routing cannot be switched on while a blocking item is open. Acknowledgeable items can be waived with a reason on the Routing screen."}
        action={blocking.length === 0
          ? <Badge tone="success"><Check className="size-3" /> Ready</Badge>
          : <Badge tone="danger">{blocking.length} blocking</Badge>} />
      <ul className="divide-y divide-border">
        {items.map((i) => {
          const pass = golivePasses(i);
          const state = i.ok ? "ok" : pass ? "acked" : i.blocking ? "blocking" : "warning";
          return (
            <li key={i.key} className="flex items-start gap-3 px-5 py-3">
              <span className={cn("mt-0.5 grid size-5 shrink-0 place-items-center rounded-full border",
                state === "ok" ? "border-success/30 bg-success-bg text-success" : state === "acked" ? "border-info/30 bg-info-bg text-info"
                : state === "blocking" ? "border-danger/30 bg-danger-bg text-danger" : "border-warning/30 bg-warning-bg text-warning")}>
                {state === "ok" || state === "acked" ? <Check className="size-3" /> : <TriangleAlert className="size-3" />}
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                  <p className="text-[13px] font-medium text-fg">{GOLIVE_LABEL[i.key] ?? i.key}</p>
                  <Badge tone={state === "ok" ? "success" : state === "acked" ? "info" : state === "blocking" ? "danger" : "warning"}>
                    {state === "ok" ? "Done" : state === "acked" ? "Acknowledged" : state === "blocking" ? "Blocking" : "Warning"}
                  </Badge>
                </div>
                {!i.ok && i.why && <p className="mt-0.5 text-[12px] text-muted">{i.why}</p>}
                {state === "acked" && i.ack && (
                  <p className="mt-0.5 text-[12px] text-subtle">Waived{i.ack.by ? ` by ${i.ack.by}` : ""} {relativeTime(i.ack.at)}: {i.ack.reason}</p>
                )}
              </div>
            </li>
          );
        })}
      </ul>
      <p className="border-t border-border px-5 py-3 text-[12px] text-muted">
        Consent texts: <Link href="/intake" className="text-info hover:underline">Intake</Link> · Switch and acknowledgements:{" "}
        <Link href="/routing" className="text-info hover:underline">Routing</Link> · B2C endpoint: <Link href="/b2c" className="text-info hover:underline">B2C CRM</Link>
      </p>
    </Card>
  );
}

function Road({ c }: { c: CC }) {
  const blocking = goliveBlocking(c.golive);
  const steps = [
    { done: true, icon: ShieldCheck, title: "Admin access secured", text: "Allowlist, two-step verification and sign-in logging are on." },
    { done: c.has_partners, icon: Building2, title: "Add the first partner", text: "Partner record, CRM connection, SLAs and working hours.", href: "/partners" },
    { done: c.has_offers, icon: BookOpen, title: "Publish its programme file", text: "Excel or CSV, matched to the catalogue.", href: "/programmes" },
    { done: blocking.length === 0, icon: UserCheck, title: "Pass the go-live checklist",
      text: blocking.length > 0
        ? `${blocking.length} blocking item${blocking.length === 1 ? "" : "s"}: ${blocking.map((i) => GOLIVE_LABEL[i.key] ?? i.key).join("; ")}.`
        : "Consent texts approved by the lawyer, Witty asks for partner-sharing consent, the B2C CRM is subscribed.", href: "/routing" },
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

/** One partner tile's status line: pushes failing now, failures, auto-pause, lost in grace, else the last event. */
function partnerNote(p: CC["partners"][number]): { text: string; bad: boolean } {
  const parts: string[] = [];
  if (p.failing > 0) parts.push(`${p.failing} push${p.failing === 1 ? "" : "es"} retrying`);
  if (p.failed_24h > 0) parts.push(`${p.failed_24h} failed in 24 h`);
  if (p.status === "paused" && p.paused_reason) parts.push(p.auto_paused_at ? `paused automatically: ${p.paused_reason}` : `paused: ${p.paused_reason}`);
  if (p.lost_in_grace > 0) parts.push(`${p.lost_in_grace} lost, in grace`);
  if (parts.length > 0) return { text: parts.join(" · "), bad: p.failing > 0 || p.failed_24h > 0 || Boolean(p.auto_paused_at) };
  return { text: p.last_event_at ? `Last event ${relativeTime(p.last_event_at)}` : "No events from the partner yet", bad: false };
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
  const n = c.counts;
  const sla = slaShare(k.sla_met_7d, k.sla_due_7d);
  const switches = Object.keys(SWITCH_LABELS).map((scope) => [scope, Boolean(c.switches[scope])] as const);
  const routingLive = Boolean(c.switches.routing);
  const allLive = c.live_partners > 0 && routingLive;
  const golive = c.golive ?? [];
  const showGolive = golive.length > 0 && (!routingLive || goliveBlocking(golive).length > 0);

  return (
    <>
      <PageHeader title="Command Center" description="Today's leads, where they went, partner health and what needs you. Test leads are left out." />

      <Insights c={c} />

      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <Kpi label="Leads today" value={String(k.leads_today)} hint="From every source" d={delta(k.leads_today, k.leads_yday)} />
        <Kpi label="To partners today" value={String(k.to_partners_today)} hint={`${k.to_b2c_today} to B2C`} d={delta(k.to_partners_today, k.to_partners_yday)} />
        <Kpi label="Accepted today" value={String(k.accepted_today)} hint="Hold window passed" d={delta(k.accepted_today, k.accepted_yday)} />
        <Kpi label="Duplicate rate" value={k.duplicate_rate_7d === null ? "—" : `${Math.round(k.duplicate_rate_7d * 100)}%`} hint="Last 7 days, of leads sent" />
        <Kpi label="SLA compliance" value={sla === null ? "—" : `${Math.round(sla * 100)}%`} hint={k.sla_due_7d ? `First contact on time, ${k.sla_met_7d} of ${k.sla_due_7d}` : "No first-contact deadline passed yet"} />
        <Kpi label="Commission (month)" value={inr(k.commission_expected_month)} hint={`Expected, net of GST · ${inr(k.commission_realised_month)} realised`} />
      </div>

      <h2 className="mb-2 mt-6 text-[12px] font-medium uppercase tracking-wider text-subtle">Needs you</h2>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <Kpi label="Re-enquiries to acknowledge" value={String(n.reenquiries_open)} hint="Students with a partner who enquired again" href="/leads?dest=reenquired" alert={n.reenquiries_open > 0} />
        <Kpi label="Consent requests open" value={String(n.consent_pending)}
          hint={n.consent_queued > 0 ? `${n.consent_queued} more queued for the hourly budget` : "Asked, no answer yet (48 h)"} href="/leads?dest=awaiting_consent" />
        <Kpi label="Lost, in grace" value={String(n.lost_in_grace)} hint="Back to the partner on activity; B2C nurture after 7 days" href="/leads?dest=lost_grace" />
        <Kpi label="Partner-barred today" value={String(n.barred_today)} hint={`${n.barred_total} barred in all (B2C only, for ever)`} href="/leads?dest=barred" />
        <Kpi label="Not passed, open" value={String(n.not_passed_open)} hint="Junk, mismatch or a bad phone; pass by hand if wrong" href="/leads?dest=not_passed" />
        <Kpi label="Review flags" value={String(n.flags_open)} hint="Decisions held for your review" href="/routing" alert={n.flags_open > 0} />
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <div className="min-w-0 space-y-6">
          <Card className="min-w-0">
            <CardHeader title="Partner health" description="Live partners first. Pushes failing now, failures, automatic pauses and leads lost in grace are the ones to watch." />
            {c.partners.length === 0 ? (
              <EmptyState icon={Building2} title="No partners yet" action={<Link href="/partners/new" className="text-[13px] text-info hover:underline">Add a partner</Link>}>Until a partner is live, every lead goes to B2C.</EmptyState>
            ) : (
              <ul className="grid gap-3 p-4 sm:grid-cols-2 2xl:grid-cols-3">
                {c.partners.map((p) => {
                  const note = partnerNote(p);
                  return (
                    <li key={p.id}>
                      <Link href={`/partners/${p.id}?tab=connection`} className={cn("block rounded-lg border p-3 transition-colors hover:border-border-strong",
                        note.bad ? "border-danger/30 bg-danger-bg/40" : p.live ? "border-success/25" : "border-border")}>
                        <div className="flex items-center justify-between gap-2">
                          <p className="truncate text-[13px] font-semibold text-fg">{p.name}</p>
                          <Badge tone={p.live ? "success" : p.auto_paused_at ? "warning" : "neutral"}>{p.live ? "Live" : p.status}</Badge>
                        </div>
                        <dl className="mt-2 grid grid-cols-3 gap-2 text-[11.5px]">
                          <div><dt className="text-subtle">Today</dt><dd className="tabular text-fg">{p.today}{p.daily_cap ? <span className="text-subtle">/{p.daily_cap}</span> : null}</dd></div>
                          <div><dt className="text-subtle">Accepted 7d</dt><dd className="tabular text-fg">{p.accepted_7d}</dd></div>
                          <div><dt className="text-subtle">Duplicates 7d</dt><dd className="tabular text-fg">{p.duplicates_7d}</dd></div>
                        </dl>
                        <p className={cn("mt-2 text-[11.5px]", note.bad ? "text-danger" : "text-subtle")}>{note.text}</p>
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
            <CardHeader title="Lead stream" description="The latest routing, push, acceptance, consent and re-enquiry events." />
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
          {showGolive && <Golive items={golive} routingLive={routingLive} />}

          <Card>
            <CardHeader title="Alerts" description="Last 7 days. Which of these reach you by e-mail or WhatsApp is set under Dashboards → Alerts."
              action={<Link href="/dashboards?tab=alerts" className="shrink-0 text-[13px] text-info hover:underline">Digest</Link>} />
            {c.alerts.length === 0 ? (
              <EmptyState icon={BellRing} title="No alerts">Push failures, partner rejections, bad signatures, disputes, failed student messages, unsendable consent requests and withdrawn consent appear here.</EmptyState>
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
            <div className="flex items-start gap-4 px-5 py-4">
              <Inbox className="mt-1 size-5 shrink-0 text-muted" />
              <div className="min-w-0 text-[13px] text-muted">
                <p><span className="tabular text-xl font-semibold text-fg">{c.pool.total}</span> waiting</p>
                {(c.pool.chatting > 0 || c.pool.waiting_inactivity > 0 || c.pool.awaiting_consent > 0) && (
                  <ul className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-[12px]">
                    {c.pool.chatting > 0 && <li><Link href="/pool?group=chatting" className="hover:underline">{c.pool.chatting} still chatting</Link></li>}
                    {c.pool.waiting_inactivity > 0 && <li><Link href="/pool?group=waiting_inactivity" className="hover:underline">{c.pool.waiting_inactivity} waiting for inactivity</Link></li>}
                    {c.pool.awaiting_consent > 0 && <li><Link href="/pool?group=awaiting_consent" className="hover:underline">{c.pool.awaiting_consent} awaiting consent</Link></li>}
                  </ul>
                )}
              </div>
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
                  {live ? (
                    scope === "routing" && !c.routing_on
                      ? <Badge tone="warning">Live, engine disabled</Badge>
                      : <Badge tone="success"><CircleDot className="size-3" /> Live</Badge>
                  ) : <Badge>Off</Badge>}
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
