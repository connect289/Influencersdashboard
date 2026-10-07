import type { Metadata } from "next";
import Link from "next/link";
import { ArrowDownLeft, ArrowUpRight, Check, CircleDashed, ExternalLink, History } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { CHECK_STEPS, actorText, describeActivity, describeChanges, lagText, linkHealth, type LinkOverview } from "@/lib/b2c-link";
import { b2cLinkOverview } from "@/lib/b2c-link-data";
import { LeadInspector } from "./LeadInspector";
import { LinkSettingsForm } from "./LinkSettingsForm";
import { ResyncAll } from "./ResyncAll";

export const metadata: Metadata = { title: "B2C CRM link" };

const TABS = [
  { id: "overview", label: "Overview" },
  { id: "fields", label: "Fields and access" },
  { id: "inspect", label: "Inspect a lead" },
  { id: "api", label: "API" },
] as const;
type Tab = (typeof TABS)[number]["id"];
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const OUT_TONE: Record<string, "success" | "info" | "warning" | "danger" | "neutral"> = {
  delivered: "success", sending: "info", pending: "neutral", failed: "warning", dead: "danger", cancelled: "neutral",
};
const IN_TONE: Record<string, "success" | "warning" | "danger" | "neutral"> = { applied: "success", unchanged: "neutral", conflict: "warning", rejected: "danger" };

const API: { method: string; path: string; what: string }[] = [
  { method: "WEBHOOK", path: "b2c.lead_upserted", what: "A lead B2C holds changed: its full record and version, within seconds" },
  { method: "WEBHOOK", path: "b2c.lead_released", what: "A lead left B2C (sent to a partner, deleted or merged): drop or archive it" },
  { method: "WEBHOOK", path: "b2c.lead_handed_off …", what: "Hand-off news (lane, reason, partners tried), as before" },
  { method: "GET", path: "/v1/b2c/leads?after=0&limit=500", what: "Change feed: build the copy, then catch up from next_after" },
  { method: "GET", path: "/v1/b2c/leads/{id}", what: "One lead's current record and version" },
  { method: "GET", path: "/v1/b2c/leads?phone=98…", what: "Find leads by phone or email" },
  { method: "PATCH", path: "/v1/b2c/leads/{id}", what: "Write B2C's fields (stage, owner, application, enrolment…) with the counsellor" },
  { method: "POST", path: "/v1/b2c/leads/{id}/activities", what: "Log a call, message, meeting or note" },
  { method: "POST", path: "/v1/leads", what: "Create a new student (lead_source b2c_created): the engine hands it straight back" },
  { method: "POST", path: "/v1/leads/{id}/route-to-partners", what: "Hand a lead to the engine to find a partner" },
  { method: "POST", path: "/v1/events/b2ccrm", what: "Opt-out and erasure requests (signed)" },
  { method: "GET", path: "/v1/b2c/schema", what: "Fields, which are writable now, stages and activity kinds" },
];

function Stat({ label, value, tone, hint }: { label: string; value: React.ReactNode; tone?: string; hint?: string }) {
  return (
    <div className="bg-surface px-5 py-3" title={hint}>
      <dt className="text-[12px] text-muted">{label}</dt>
      <dd className={cn("tabular mt-0.5 text-xl font-semibold text-fg", tone)}>{value}</dd>
    </div>
  );
}

function Overview({ o }: { o: LinkOverview }) {
  const done = CHECK_STEPS.filter((s) => o.checks[s.key]).length;
  const w = o.writes.by_status;
  const writesOk = (w["update.applied"] ?? 0) + (w["update.unchanged"] ?? 0) + (w["activity.applied"] ?? 0);
  const writesBad = (w["update.rejected"] ?? 0) + (w["update.conflict"] ?? 0) + (w["activity.rejected"] ?? 0);
  return (
    <div className="space-y-6">
      <div className="grid gap-6 xl:grid-cols-[1fr_1.4fr]">
        <Card className="min-w-0 xl:self-start">
          <CardHeader title={`Connection checklist · ${done} of ${CHECK_STEPS.length}`}
            description="The B2C developer builds against docs/b2c-contract.md; you issue the secret and the key from System health." />
          <ol className="divide-y divide-border">
            {CHECK_STEPS.map((s) => {
              const ok = o.checks[s.key];
              return (
                <li key={s.key} className="flex gap-3 px-5 py-2.5 text-[12.5px]">
                  {ok ? <Check className="mt-0.5 size-4 shrink-0 text-success" /> : <CircleDashed className="mt-0.5 size-4 shrink-0 text-subtle" />}
                  <span className="min-w-0 flex-1">
                    <span className={cn("block font-medium", ok ? "text-fg" : "text-muted")}>{s.label}</span>
                    <span className="block text-subtle">{s.hint}</span>
                  </span>
                  {!ok && s.where && <Link href={s.where} className="shrink-0 self-center text-info hover:underline">Set up</Link>}
                </li>
              );
            })}
          </ol>
        </Card>
        <div className="min-w-0 space-y-6">
          <Card className="min-w-0">
            <CardHeader title="Real-time sync" description="Lead changes are picked up every 5 seconds and delivered at once, signed. The B2C CRM keeps the highest version of each lead." />
            <dl className="grid grid-cols-2 gap-px border-t border-border bg-border sm:grid-cols-4">
              <Stat label="Leads in B2C's copy" value={o.sync.in_scope} hint={`${o.sync.held_now} held by B2C now`} />
              <Stat label="Changes sent, 24 h" value={o.sync.changes_24h} />
              <Stat label="Delivery time (1 h)" value={lagText(o.deliveries.lag_seconds_avg)} hint={`slowest ${lagText(o.deliveries.lag_seconds_max)}`} />
              <Stat label="Waiting or retrying" value={o.deliveries.waiting} tone={o.deliveries.waiting > 20 ? "text-warning" : undefined} />
              <Stat label="Gave up, 24 h" value={o.deliveries.by_status.dead ?? 0} tone={(o.deliveries.by_status.dead ?? 0) > 0 ? "text-danger" : undefined} />
              <Stat label="B2C writes, 24 h" value={writesOk} />
              <Stat label="Refused or stale" value={writesBad} tone={writesBad > 0 ? "text-warning" : undefined} />
              <Stat label="Last change" value={<span className="text-[15px]">{o.sync.last_change_at ? relativeTime(o.sync.last_change_at) : "—"}</span>}
                hint={o.sync.tick?.last_run ? `last scan ${formatDateTime(o.sync.tick.last_run)}` : undefined} />
            </dl>
            <div className="flex flex-wrap items-center gap-3 border-t border-border px-5 py-3 text-[12.5px] text-muted">
              {o.endpoint ? <>Delivering to <code className="truncate font-mono text-[12px] text-fg">{o.endpoint.url}</code>
                {o.endpoint.last_error && <span className="text-danger" title={o.endpoint.last_error}>last error: {o.endpoint.last_error.slice(0, 80)}</span>}</>
                : <>No B2C CRM endpoint yet. <Link href="/system?tab=integrations" className="text-info hover:underline">Register it</Link></>}
              <span className="ml-auto"><ResyncAll count={o.sync.in_scope || o.sync.held_now} /></span>
            </div>
          </Card>
          <Card className="min-w-0">
            <CardHeader title="Rule in force" />
            <ul className="space-y-1.5 px-5 pb-4 text-[12.5px] text-muted">
              <li><span className="font-medium text-fg">The B2C CRM never reads or writes the lead table directly.</span> It keeps its own copy of the leads it
                {o.settings.scope === "all" ? " sees (all leads, read-only unless it holds them)" : " holds"}, updated by this link, and writes back only through the API.</li>
              <li>Routing, consent, source and Witty&apos;s qualification stay with the B2B CRM; the B2C CRM writes its pipeline: owner, stage, contact, application, enrolment and lost.</li>
              <li>Every write is checked, applied by the B2B CRM, kept with the counsellor who made it, and sent back as a new version.</li>
            </ul>
          </Card>
        </div>
      </div>

      <Card className="min-w-0">
        <CardHeader title="Activity" description="Latest lead versions sent to the B2C CRM and the latest writes it sent back." />
        {o.log.length === 0 ? (
          <EmptyState icon={History} title="Nothing yet">Leads appear here once the engine hands a lead to B2C, or the B2C CRM writes through the API.</EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] text-left text-[12.5px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-b border-border">
                  <th scope="col" className="w-10 px-5 py-2"><span className="sr-only">Direction</span></th>
                  <th scope="col" className="px-3 py-2 font-medium">When</th>
                  <th scope="col" className="px-3 py-2 font-medium">Lead</th>
                  <th scope="col" className="px-3 py-2 font-medium">What</th>
                  <th scope="col" className="px-3 py-2 font-medium">Detail</th>
                  <th scope="col" className="px-5 py-2 font-medium">Result</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {o.log.map((r, i) => (
                  <tr key={i} className="align-top">
                    <td className="px-5 py-2">{r.dir === "out"
                      ? <ArrowUpRight className="size-4 text-info" aria-label="to the B2C CRM" /> : <ArrowDownLeft className="size-4 text-amber" aria-label="from the B2C CRM" />}</td>
                    <td className="whitespace-nowrap px-3 py-2 text-muted" title={formatDateTime(r.at)}>{relativeTime(r.at)}</td>
                    <td className="px-3 py-2">{r.lead_id ? <Link href={`/b2c?tab=inspect&lead=${r.lead_id}`} className="text-fg hover:underline">{r.name ?? `#${r.lead_id}`}</Link> : "—"}</td>
                    <td className="px-3 py-2 text-fg">
                      {r.dir === "out" ? <>{r.type === "upserted" ? "Lead sent" : "Lead released"} <span className="text-subtle">v{r.version}</span></>
                        : <>{r.type === "update" ? "Update" : "Activity"} <span className="text-subtle">by {actorText(r.actor)}</span></>}
                    </td>
                    <td className="max-w-[340px] truncate px-3 py-2 text-muted">
                      {r.dir === "out" ? (r.origin?.startsWith("b2c:") ? "echo of a B2C write" : r.origin === "resync" ? "sent again by the Admin" : "changed in the B2B CRM")
                        : r.error ?? (r.type === "activity" ? describeActivity(r.changes) : describeChanges(r.changes))}
                    </td>
                    <td className="px-5 py-2">
                      {r.dir === "out"
                        ? r.delivery ? <Badge tone={OUT_TONE[r.delivery.status] ?? "neutral"}>{r.delivery.status}</Badge> : <span className="text-subtle">feed only</span>
                        : <Badge tone={IN_TONE[r.status] ?? "neutral"}>{r.status} · {r.http_status}</Badge>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}

export default async function B2cLinkPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "overview";
  const o = await b2cLinkOverview();
  const h = linkHealth(o);
  const lead = Number(sp.lead);

  return (
    <>
      <PageHeader title="B2C CRM link"
        description="Eduwit's B2C CRM works its leads through this link only: it receives every change to the leads it holds in real time and writes its counsellors' work back through the B2B CRM, which stays the only gateway to the lead table."
        actions={<Badge tone={h.tone}>{h.label}</Badge>} />
      <nav className="mb-6 flex gap-5 overflow-x-auto border-b border-border" aria-label="B2C CRM link sections">
        {TABS.map((t) => (
          <Link key={t.id} href={`/b2c?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 whitespace-nowrap border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}
          </Link>
        ))}
      </nav>
      {tab === "overview" && <Overview o={o} />}
      {tab === "fields" && (
        <Card className="min-w-0">
          <CardHeader title="Fields and access" description="What the B2C CRM receives and what it may change. Saved as a new settings version with your reason." />
          <LinkSettingsForm settings={o.settings} fields={o.fields} />
        </Card>
      )}
      {tab === "inspect" && (
        <Card className="min-w-0">
          <CardHeader title="Inspect a lead" description="Exactly what the B2C CRM has for one lead, every version delivered, and every write it made." />
          <LeadInspector initial={Number.isInteger(lead) && lead > 0 ? lead : null} />
        </Card>
      )}
      {tab === "api" && (
        <Card className="min-w-0">
          <CardHeader title="API for the B2C developer" description="Full contract with examples: docs/b2c-contract.md. Calls use an API key with the B2C CRM link scope; webhooks are signed with the endpoint's secret." />
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-left text-[12.5px]">
              <tbody className="divide-y divide-border">
                {API.map((a) => (
                  <tr key={a.method + a.path}>
                    <td className="w-24 px-5 py-2"><Badge tone={a.method === "WEBHOOK" ? "brand" : a.method === "GET" ? "info" : "warning"}>{a.method}</Badge></td>
                    <td className="px-3 py-2"><code className="font-mono text-[12px] text-fg">{a.path}</code></td>
                    <td className="px-5 py-2 text-muted">{a.what}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="flex items-center gap-1.5 border-t border-border px-5 py-3 text-[12px] text-muted">
            <ExternalLink className="size-3.5" /> Keys and the webhook address are managed on <Link href="/system?tab=integrations" className="text-info hover:underline">System health → Webhooks and API keys</Link>.
          </p>
        </Card>
      )}
    </>
  );
}
