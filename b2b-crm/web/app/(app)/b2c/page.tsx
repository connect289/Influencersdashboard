import type { Metadata } from "next";
import Link from "next/link";
import { ArrowDownLeft, ArrowUpRight, Check, CircleDashed, ExternalLink, History } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import {
  ALWAYS_WRITABLE_FIELDS, CHECK_STEPS, CONTRACT_DOC, SCOPE_LABEL, actorText, contractVersion, describeActivity, describeChanges, lagText, linkHealth,
  resyncNote, type LinkOverview, type SyncCadence,
} from "@/lib/b2c-link";
import { B2C_REQUIRED_EVENTS, eventSubscribed } from "@/lib/integrations";
import { b2cLinkOverview, syncCadence } from "@/lib/b2c-link-data";
import { CadenceCard } from "./CadenceCard";
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

type ApiRow = { method: "WEBHOOK" | "EVENT" | "GET" | "POST" | "PATCH"; path: string; what: string; v3?: boolean };
const METHOD_TONE: Record<ApiRow["method"], "brand" | "success" | "info" | "warning"> = { WEBHOOK: "brand", EVENT: "success", GET: "info", POST: "warning", PATCH: "warning" };

/** The contract in one table (docs/b2c-contract.md has the details and examples). v3 marks what Addendum 3 added. */
const API_GROUPS: { title: string; rows: ApiRow[] }[] = [
  { title: "Webhooks we send: signed with the endpoint's secret; every b2c.* envelope carries contract_version 3", rows: [
    { method: "WEBHOOK", path: "b2c.lead_upserted", what: "A lead in B2C's scope changed: its full version-3 record and version, within seconds. Apply it only when the version is higher" },
    { method: "WEBHOOK", path: "b2c.lead_released", what: "A lead left B2C's scope (to a partner under scope held, deleted, merged, anonymised or Not passed): close the pipeline for it" },
    { method: "WEBHOOK", path: "b2c.leads_batch", what: "Production cadence: every changed lead since the last batch, once, at its newest version (up to 100 per call)" },
    { method: "WEBHOOK", path: "b2c.lead_handed_off", what: "The engine gives a lead to B2C: lane, reason and cause, handling (job, assignment, first-contact script), hold, partner bar, already-with-providers, partners tried, missing details, b2c_actions (the explore-programmes welcome), consent, lost, attribution" },
    { method: "WEBHOOK", path: "b2c.lead_reenquired", what: "A lead B2C holds enquired again (a new form, Witty, a message); reactivation: true on a lost lead means assign a counsellor by round robin" },
    { method: "WEBHOOK", path: "b2c.lead_requalified", what: "A qualification-nurture lead qualified and went back through routing: close the nurture pipeline; a new hand-off follows if it ends with B2C again", v3: true },
    { method: "WEBHOOK", path: "b2c.lead_reengaged", what: "A nurture lead re-engaged but is still unqualified (at most once a day per lead), with what is still missing", v3: true },
    { method: "WEBHOOK", path: "b2c.consent_requested", what: "Send the student the one-tap partner-sharing request from the B2C number: text, text_version, expires_at, student", v3: true },
    { method: "WEBHOOK", path: "b2c.consent_closed", what: "A consent request ended: answered (yes / no), expired or cancelled", v3: true },
    { method: "WEBHOOK", path: "b2b.lead_routed_to_partner", what: "A lead B2C sent to partners, or a requalified lead, was accepted by one: close the pipeline for it" },
    { method: "WEBHOOK", path: "b2c.lead_flagged · b2c.lead_close_agreed · ping", what: "Attention flags, a partner's agreed close, and the Admin's test ping" },
  ] },
  { title: "Signed events the B2C CRM sends us: POST /v1/events/b2ccrm, same secret", rows: [
    { method: "EVENT", path: "b2ccrm.consent_request_sent", what: "The consent request went out: request_id, sent_at, message_id. The 48 hours count from the send", v3: true },
    { method: "EVENT", path: "b2ccrm.partner_consent", what: "The student's answer: yes / no, answered_at, message_id (required for a YES), text_version. YES → the lead goes through routing; NO → it stays with B2C (no_partner_consent)", v3: true },
    { method: "EVENT", path: "b2ccrm.opted_out · b2ccrm.erasure_requested", what: "Opt-out and erasure requests" },
    { method: "EVENT", path: "b2ccrm.lead_assigned · stage_changed · enrolled", what: "Timeline only, kept for compatibility: the pipeline is written with PATCH" },
  ] },
  { title: "Calls: API key with the b2c scope (events and intake scopes where noted)", rows: [
    { method: "GET", path: "/v1/b2c/leads?after=0&limit=500", what: "Change feed: build the copy, then catch up from next_after" },
    { method: "GET", path: "/v1/b2c/leads/{id}", what: "One lead's current record and version" },
    { method: "GET", path: "/v1/b2c/leads?phone=98…", what: "Find leads by phone or email" },
    { method: "PATCH", path: "/v1/b2c/leads/{id}", what: "Write B2C's fields (stage, owner, application, enrolment, other_courses…) with the counsellor; completing a nurture lead's details is what requalifies it" },
    { method: "POST", path: "/v1/b2c/leads/{id}/activities", what: "Log a call, message, meeting or note" },
    { method: "POST", path: "/v1/b2c/leads/batch", what: "Up to 200 updates and activities in one call (the B2C CRM's own 15-minute sync)" },
    { method: "POST", path: "/v1/leads", what: "Create a new student (lead_source b2c_created; scope intake): the engine hands it straight back" },
    { method: "POST", path: "/v1/leads/{id}/route-to-partners", what: "Hand a held lead to the engine to find a partner (scope events). Refused with 422 and error_code partner_barred, no_consent, not_held or invalid", v3: true },
    { method: "GET", path: "/v1/handoffs", what: "Hand-off news feed: the same envelopes as the webhooks, for catch-up (scope events)" },
    { method: "GET", path: "/v1/b2c/schema", what: "Fields and which are writable now, stages, activity kinds, and the version-3 vocabulary: reasons by lane, causes, handling, hold kinds, consent states, events, inbound types, error codes" },
  ] },
];

function Stat({ label, value, tone, hint }: { label: string; value: React.ReactNode; tone?: string; hint?: string }) {
  return (
    <div className="bg-surface px-5 py-3" title={hint}>
      <dt className="text-[12px] text-muted">{label}</dt>
      <dd className={cn("tabular mt-0.5 text-xl font-semibold text-fg", tone)}>{value}</dd>
    </div>
  );
}

function Overview({ o, c }: { o: LinkOverview; c: SyncCadence }) {
  const checks = {
    ...o.checks,
    production: c.b2c.delivery === "batched",
    golive_events: Boolean(o.endpoint) && B2C_REQUIRED_EVENTS.every((t) => eventSubscribed(o.endpoint?.events ?? [], t)),
  };
  const done = CHECK_STEPS.filter((s) => checks[s.key]).length;
  const w = o.writes.by_status;
  const writesOk = (w["update.applied"] ?? 0) + (w["update.unchanged"] ?? 0) + (w["activity.applied"] ?? 0);
  const writesBad = (w["update.rejected"] ?? 0) + (w["update.conflict"] ?? 0) + (w["activity.rejected"] ?? 0);
  const note = resyncNote(o, c.b2c.delivery);
  const version = contractVersion(o);
  return (
    <div className="space-y-6">
      {note && (note.batched ? (
        <Notice tone="info">
          <span className="font-medium">After the Addendum 3 deploy, run <em>Resend every lead</em> once, now, while the link delivers in batches.</span>{" "}
          Every shared lead then reaches the B2C CRM at contract version {version} in one batch (origin <code className="font-mono">resync</code>), and its copies gain the new
          fields (partner bar, providers, hold, handling, consent state, other courses) with no action on its side.
        </Notice>
      ) : (
        <Notice tone="warning">
          <span className="font-medium">After the Addendum 3 deploy, every shared lead must be re-sent once at contract version {version}.</span>{" "}
          Switch the sync cadence to batched first (below), then run <em>Resend every lead</em>: in real time a resend sends one webhook per lead.
        </Notice>
      ))}
      <div className="grid gap-6 xl:grid-cols-[1fr_1.4fr]">
        <Card className="min-w-0 xl:self-start">
          <CardHeader title={`Connection checklist · ${done} of ${CHECK_STEPS.length}`}
            description={`The B2C developer builds against ${CONTRACT_DOC} (contract version ${version}); you issue the secret and the key from System health.`} />
          <ol className="divide-y divide-border">
            {CHECK_STEPS.map((s) => {
              const ok = checks[s.key];
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
            <CardHeader title="Sync" description={c.b2c.delivery === "batched"
              ? `Lead changes are picked up every 5 seconds inside the database and delivered in one signed batch every ${c.interval_minutes} minutes. The B2C CRM keeps the highest version of each lead.`
              : "Lead changes are picked up every 5 seconds and delivered at once, signed. The B2C CRM keeps the highest version of each lead."} />
            <dl className="grid grid-cols-2 gap-px border-t border-border bg-border sm:grid-cols-4">
              <Stat label="Leads in B2C's copy" value={o.sync.in_scope}
                hint={`${o.sync.held_now} held by B2C now${o.settings.scope === "all" ? "; scope: every lead except Not passed and test leads" : ""}`} />
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
          <CadenceCard c={c} />
          <Card className="min-w-0">
            <CardHeader title="Rule in force" />
            <ul className="space-y-1.5 px-5 pb-4 text-[12.5px] text-muted">
              <li><span className="font-medium text-fg">The B2C CRM never reads or writes the lead table directly.</span> It keeps its own copy of
                {o.settings.scope === "all"
                  ? " every lead except Not passed and test leads (read-only unless it holds the lead)"
                  : " the leads it holds (a lead that goes to a partner is released)"}, updated by this link, and writes back only through the API.</li>
              <li>Routing, the partner bar, consent, source and qualification stay with the B2B CRM; the B2C CRM writes its pipeline (owner, stage, contact, application, enrolment, lost)
                and the student&apos;s details and other courses. It sends a lead to partners only through the route-to-partners call, never a partner-barred one.</li>
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
                        ? r.delivery ? <Badge tone={OUT_TONE[r.delivery.status] ?? "neutral"}>{r.delivery.status}</Badge> : <span className="text-subtle">{c.b2c.delivery === "batched" ? "in the next batch" : "feed only"}</span>
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
  const [o, c] = await Promise.all([b2cLinkOverview(), syncCadence()]);
  const h = linkHealth(o);
  const version = contractVersion(o);
  const lead = Number(sp.lead);
  const scope = SCOPE_LABEL[o.settings.scope];

  return (
    <>
      <PageHeader title="B2C CRM link"
        description="Eduwit's B2C CRM works its leads through this link only: it receives every change to the leads in its scope, the hand-offs with their reason and handling, and the consent requests to send, and writes its counsellors' work back through the B2B CRM, which stays the only gateway to the lead table."
        actions={<><Badge tone="brand" className="whitespace-nowrap">Contract version {version}</Badge><Badge tone={h.tone}>{h.label}</Badge></>} />
      <nav className="mb-6 flex gap-5 overflow-x-auto border-b border-border" aria-label="B2C CRM link sections">
        {TABS.map((t) => (
          <Link key={t.id} href={`/b2c?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 whitespace-nowrap border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}
          </Link>
        ))}
      </nav>
      {tab === "overview" && <Overview o={o} c={c} />}
      {tab === "fields" && (
        <Card className="min-w-0">
          <CardHeader title="Fields and access"
            description={`What the B2C CRM receives and what it may change. Scope now: ${scope.label.toLowerCase()} — ${scope.hint} Saved as a new settings version with your reason.`} />
          <LinkSettingsForm settings={o.settings} fields={o.fields} />
          <p className="border-t border-border px-5 py-3 text-[12px] text-muted">
            Always writable while the B2C CRM holds the lead, whatever is ticked above: <code className="font-mono text-fg">interest.{ALWAYS_WRITABLE_FIELDS.join(", interest.")}</code> (the
            student&apos;s other courses, up to 9; completing them on a nurture lead is what requalifies it). The version-{version} additions to the record (partner bar, providers,
            hold and handling, qualification class and missing details, consent state and request) belong to the B2B CRM and are read-only.
          </p>
        </Card>
      )}
      {tab === "inspect" && (
        <Card className="min-w-0">
          <CardHeader title="Inspect a lead" description="Exactly what the B2C CRM has for one lead: the version-3 facts it acts on, the record, every version delivered, and every write it made." />
          <LeadInspector initial={Number.isInteger(lead) && lead > 0 ? lead : null} />
        </Card>
      )}
      {tab === "api" && (
        <Card className="min-w-0">
          <CardHeader title="API for the B2C developer"
            description={`Contract version ${version} (Addendum 3), with examples: ${CONTRACT_DOC}. Calls use an API key with the B2C CRM link scope; webhooks are signed with the endpoint's secret. GET /v1/b2c/schema returns every vocabulary as data.`} />
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-left text-[12.5px]">
              {API_GROUPS.map((g) => (
                <tbody key={g.title} className="divide-y divide-border border-b border-border">
                  <tr className="bg-surface-2/60">
                    <th scope="colgroup" colSpan={3} className="px-5 py-2 text-left text-[11px] font-medium uppercase tracking-wider text-subtle">{g.title}</th>
                  </tr>
                  {g.rows.map((a) => (
                    <tr key={a.method + a.path}>
                      <td className="w-24 px-5 py-2"><Badge tone={METHOD_TONE[a.method]}>{a.method}</Badge></td>
                      <td className="px-3 py-2">
                        <code className="font-mono text-[12px] text-fg">{a.path}</code>
                        {a.v3 && <Badge className="ml-2">v{version}</Badge>}
                      </td>
                      <td className="px-5 py-2 text-muted">{a.what}</td>
                    </tr>
                  ))}
                </tbody>
              ))}
            </table>
          </div>
          <p className="flex items-center gap-1.5 border-t border-border px-5 py-3 text-[12px] text-muted">
            <ExternalLink className="size-3.5" /> Keys and the webhook address are managed on <Link href="/system?tab=integrations" className="text-info hover:underline">System health → Webhooks and API keys</Link>;
            routing cannot go live until the B2C endpoint subscribes to{" "}
            {B2C_REQUIRED_EVENTS.map((t, i) => <span key={t}>{i > 0 && " and "}<code className="font-mono">{t}</code></span>)}.
          </p>
        </Card>
      )}
    </>
  );
}
