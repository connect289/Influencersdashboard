import type { Metadata } from "next";
import Link from "next/link";
import { CircleCheck, CircleX, Inbox, ShieldAlert, Timer } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { JOB_LABEL, PRODUCT_EVENT_TONE, type SystemOverview } from "@/lib/integrations";
import { openErasureRequests, systemOverview } from "@/lib/system-data";
import { ApiKeys } from "./ApiKeys";
import { Deliveries } from "./Deliveries";
import { Endpoints } from "./Endpoints";
import { Erasures } from "./Erasures";

export const metadata: Metadata = { title: "System health" };

const TABS = [
  { id: "health", label: "Health" },
  { id: "integrations", label: "Webhooks and API keys" },
  { id: "deliveries", label: "Deliveries" },
] as const;
type Tab = (typeof TABS)[number]["id"];

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

function Stat({ label, value, tone, href }: { label: string; value: number; tone?: "danger" | "warning"; href?: string }) {
  const body = (
    <>
      <p className="text-[12px] font-medium text-muted">{label}</p>
      <p className={cn("tabular mt-1 text-2xl font-semibold", value > 0 && tone === "danger" ? "text-danger" : value > 0 && tone === "warning" ? "text-warning" : "text-fg")}>{value}</p>
    </>
  );
  const cls = "block rounded-[var(--radius-card)] border border-border bg-surface p-4";
  return href ? <Link href={href} className={cn(cls, "transition-colors hover:border-border-strong")}>{body}</Link> : <div className={cls}>{body}</div>;
}

function Jobs({ s }: { s: SystemOverview }) {
  return (
    <ul className="divide-y divide-border">
      {s.jobs.map((j) => {
        const ok = j.active && j.last_status !== "failed";
        return (
          <li key={j.name} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-3 text-[13px]">
            {ok ? <CircleCheck className="size-4 shrink-0 text-success" /> : <CircleX className="size-4 shrink-0 text-danger" />}
            <div className="min-w-0 flex-1">
              <p className="font-medium text-fg">{JOB_LABEL[j.name] ?? j.name} <span className="font-mono text-[11.5px] font-normal text-subtle">{j.name} · {j.schedule}</span></p>
              {j.last_error && <p className="truncate text-[12px] text-danger" title={j.last_error}>{j.last_error}</p>}
            </div>
            <span className="text-[12px] text-muted" title={formatDateTime(j.last_run)}>{j.active ? (j.last_run ? `ran ${relativeTime(j.last_run)}` : "not run yet") : "switched off"}</span>
            {j.failed_24h > 0 && <Badge tone="danger">{j.failed_24h} failed in 24 h</Badge>}
          </li>
        );
      })}
    </ul>
  );
}

function ProductEvents({ s }: { s: SystemOverview }) {
  if (s.product_events.length === 0) {
    return <EmptyState icon={Inbox} title="Nothing received yet">Events the B2C CRM sends to POST /v1/events/b2ccrm appear here: counsellor assigned, stage changes, enrolments, opt-outs and erasure requests.</EmptyState>;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] text-left text-[12.5px]">
        <thead className="text-[11px] uppercase tracking-wider text-subtle">
          <tr className="border-b border-border">
            <th scope="col" className="px-5 py-2 font-medium">When</th>
            <th scope="col" className="px-3 py-2 font-medium">Event</th>
            <th scope="col" className="px-3 py-2 font-medium">Lead</th>
            <th scope="col" className="px-5 py-2 font-medium">Result</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {s.product_events.map((e) => (
            <tr key={e.id}>
              <td className="whitespace-nowrap px-5 py-2 text-muted" title={formatDateTime(e.received_at)}>{relativeTime(e.received_at)}</td>
              <td className="px-3 py-2 font-mono text-[12px] text-fg">{e.event_type}</td>
              <td className="px-3 py-2">{e.lead_id ? <Link href={`/leads?lead=${e.lead_id}`} className="text-fg hover:underline">#{e.lead_id}</Link> : "—"}</td>
              <td className="px-5 py-2"><span className="flex items-center gap-1.5"><Badge tone={PRODUCT_EVENT_TONE[e.status]}>{e.status}</Badge>
                {e.result && <span className="truncate text-subtle">{e.result}</span>}</span></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default async function SystemPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "health";
  const [s, erasures] = await Promise.all([systemOverview(), openErasureRequests()]);
  const deadDeliveries = s.endpoints.reduce((n, e) => n + e.dead, 0);
  const waiting = s.endpoints.reduce((n, e) => n + e.pending, 0);
  const jobsFailing = s.jobs.filter((j) => !j.active || j.last_status === "failed").length;
  const activeKeys = s.api_keys.filter((k) => !k.revoked_at).length;

  return (
    <>
      <PageHeader title="System health" description="Background jobs, connections to other Eduwit products (the B2C CRM first), webhook deliveries and API keys." />
      <nav className="mb-6 flex gap-5 overflow-x-auto border-b border-border" aria-label="System sections">
        {TABS.map((t) => (
          <Link key={t.id} href={`/system?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}
          </Link>
        ))}
      </nav>

      {tab === "health" && (
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat label="Jobs failing or off" value={jobsFailing} tone="danger" />
            <Stat label="Deliveries waiting" value={waiting} tone="warning" href="/system?tab=deliveries" />
            <Stat label="Deliveries that gave up" value={deadDeliveries} tone="danger" href="/system?tab=deliveries" />
            <Stat label="Erasure requests open" value={erasures.length} tone="warning" />
          </div>
          {erasures.length > 0 && (
            <Card className="min-w-0 border-warning/40">
              <CardHeader title="Erasure requests" description="Students who asked, through the B2C CRM, for their data to be deleted. Carry it out, then close the request." />
              <Erasures rows={erasures} />
            </Card>
          )}
          <Card className="min-w-0">
            <CardHeader title="Background jobs" description="Scheduled in the database (pg_cron). Failures in the last 24 hours are counted here." />
            {s.jobs.length === 0 ? <EmptyState icon={Timer} title="No jobs scheduled" /> : <Jobs s={s} />}
          </Card>
          <Card className="min-w-0">
            <CardHeader title="Events from the B2C CRM" description="The latest 50, stored as received; a repeated event_id is ignored." />
            <ProductEvents s={s} />
          </Card>
        </div>
      )}

      {tab === "integrations" && (
        <div className="space-y-6">
          <Card className="min-w-0">
            <CardHeader title="Webhook endpoints" description="Where Eduwit sends events, signed with HMAC-SHA256 and retried for about 11 hours. The B2C CRM's endpoint receives every lead handed to B2C." />
            <Endpoints endpoints={s.endpoints} />
          </Card>
          <Card className="min-w-0">
            <CardHeader title={`API keys (${activeKeys} active)`} description="For systems that call Eduwit: the B2C CRM (hand-off feed, sending a lead to partners) and lead intake. Shown once, stored as a hash." />
            <ApiKeys keys={s.api_keys} />
          </Card>
          <Card className="min-w-0">
            <CardHeader title="For the B2C CRM developer" />
            <ul className="space-y-1.5 px-5 py-4 text-[13px] text-muted">
              <li><ShieldAlert className="mr-1.5 inline size-4 text-subtle" />Contract: <span className="font-mono text-fg">docs/b2c-contract.md</span> in the repository. Give them the endpoint&apos;s signing secret and an API key with the product-integrations scope, each once, through a secure channel.</li>
              <li>Webhooks to them: <span className="font-mono">b2c.lead_handed_off</span>, <span className="font-mono">b2c.lead_reenquired</span>, <span className="font-mono">b2c.lead_flagged</span>, <span className="font-mono">b2c.lead_close_agreed</span>, <span className="font-mono">b2b.lead_routed_to_partner</span>.</li>
              <li>Calls to us: <span className="font-mono">GET /v1/handoffs</span>, <span className="font-mono">POST /v1/leads/&#123;id&#125;/route-to-partners</span>, <span className="font-mono">POST /v1/events/b2ccrm</span>.</li>
            </ul>
          </Card>
        </div>
      )}

      {tab === "deliveries" && (
        <Card className="min-w-0">
          <CardHeader title="Webhook deliveries" description="The latest 100. Retried after 30 s, 2 min, 10 min, 30 min, 1 h, 3 h and 6 h, then given up with an alert." />
          {s.deliveries.length === 0
            ? <EmptyState icon={Inbox} title="No deliveries yet">They start once an endpoint is switched on, or when you send it a test event.</EmptyState>
            : <Deliveries rows={s.deliveries} />}
        </Card>
      )}
    </>
  );
}
