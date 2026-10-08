import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft, CircleCheck, CircleDashed, Clock3, Gauge, History } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { humanize } from "@/lib/leads";
import {
  ADAPTER_LABEL, CHECKLIST_LABEL, CRITERIA_UNKNOWN_LABEL, DEDUPE_LABEL, duplicateWindowText, hasCriteria, holdWindowText, partnerTitle, SLA_FIELDS,
  STATUS_LABEL, STATUS_TONE, summariseHours, type PartnerDetail, type PartnerFactors,
} from "@/lib/partners";
import { partnerDetail } from "@/lib/partners-data";
import { partnerAdapterStatus, partnerConnection } from "@/lib/push-data";
import { isCrmAdapter } from "@/lib/adapters";
import { segmentLabel, STAGE_LABEL } from "@/lib/routing";
import { factorText, pct } from "@/lib/segments";
import { partnerSync } from "@/lib/sync-data";
import { PartnerForm } from "../PartnerForm";
import { PartnerLogo } from "../PartnerLogo";
import { ConnectionTab } from "./ConnectionTab";
import { SyncTab } from "./SyncTab";
import { PartnerControls } from "./PartnerControls";

type Props = { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };
const TABS = [
  { id: "overview", label: "Overview" },
  { id: "settings", label: "Settings" },
  { id: "connection", label: "Connection" },
  { id: "sync", label: "Sync & SLAs" },
  { id: "activity", label: "Activity" },
] as const;

const parseId = (v: string) => (/^\d{1,15}$/.test(v) && Number(v) > 0 ? Number(v) : null);

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const id = parseId((await params).id);
  const d = id ? await partnerDetail(id).catch(() => null) : null;
  return { title: d ? partnerTitle(d.partner) : "Partner" };
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-4 px-5 py-2.5 text-[13px]">
      <dt className="shrink-0 text-muted">{label}</dt>
      <dd className="min-w-0 text-right text-fg">{children}</dd>
    </div>
  );
}

const EVENT_LABEL: Record<string, string> = {
  "partner.created": "Partner added",
  "partner.updated": "Settings changed",
  "partner.status_changed": "Status changed",
  "partner.adapter_saved": "CRM connection saved",
  "alert.partner_auto_paused": "Paused automatically by the engine",
};

function Activity({ events }: { events: PartnerDetail["events"] }) {
  if (events.length === 0) return <EmptyState icon={History} title="No activity yet" />;
  return (
    <ol className="divide-y divide-border">
      {events.map((e, i) => {
        const p = e.payload as { fields?: string[]; from?: string; to?: string; reason?: string | null; slug?: string; auto?: boolean; dedupe_confirmed?: boolean };
        const detail = e.type === "partner.updated" && p.fields ? p.fields.map((f) => humanize(f)).join(", ")
          : e.type === "partner.status_changed" ? `${humanize(p.from)} → ${humanize(p.to)}${p.auto ? " · automatic" : ""}${p.reason ? ` · ${p.reason}` : ""}`
          : e.type === "alert.partner_auto_paused" ? p.reason ?? null
          : e.type === "partner.adapter_saved" ? (p.dedupe_confirmed ? "CRM confirmed to block duplicates on create: no hold window" : "30-minute hold window")
          : null;
        return (
          <li key={i} className="flex gap-3 px-5 py-3">
            <Clock3 className="mt-0.5 size-4 shrink-0 text-subtle" aria-hidden />
            <div className="min-w-0">
              <p className="text-[13px] font-medium text-fg">{EVENT_LABEL[e.type] ?? humanize(e.type.replace(/\./g, " "))}</p>
              {detail && <p className="text-[12.5px] text-muted">{detail}</p>}
              <p className="text-[12px] text-subtle"><time dateTime={e.at} title={formatDateTime(e.at)}>{relativeTime(e.at)}</time> · {humanize(e.actor)}</p>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

function Stat({ label, value, sub, badge }: { label: string; value: React.ReactNode; sub?: React.ReactNode; badge?: React.ReactNode }) {
  return (
    <div className="min-w-0 px-5 py-3">
      <p className="text-[11.5px] text-muted">{label}</p>
      <p className="tabular flex flex-wrap items-center gap-2 text-lg font-semibold text-fg">{value}{badge}</p>
      {sub && <p className="text-[11.5px] text-subtle">{sub}</p>}
    </div>
  );
}

/**
 * The Stage B/C factors the engine applies to this partner (m31l partner_detail.factors, from partner_segment_stats 'base'): the
 * sales-effort factor (0.85–1.15, capped at 1.0 without synced activity) and the SLA-adherence factor (0.80–1.00), partner-wide and
 * per segment. D27; rulebook PART 4 Step 3.
 */
function RoutingFactors({ f }: { f: PartnerFactors | null | undefined }) {
  const empty = !f || (f.n_received === 0 && f.effort_factor == null && f.sla_total == null);
  return (
    <Card>
      <CardHeader
        title="Routing factors"
        description="In Stage B and C the engine multiplies this partner's commission by its sales-effort and SLA-adherence factors, over the last 30 days."
        action={f?.stats_at ? <span className="shrink-0 text-[11.5px] text-subtle">Refreshed <time dateTime={f.stats_at} title={formatDateTime(f.stats_at)}>{relativeTime(f.stats_at)}</time></span> : undefined}
      />
      {empty || !f ? (
        <EmptyState icon={Gauge} title="No factors yet">
          Both factors start at ×1.00. They are measured once the partner has received leads and the stats refresh has run.
        </EmptyState>
      ) : (
        <>
          <dl className="grid divide-y divide-border sm:grid-cols-3 sm:divide-x sm:divide-y-0">
            <Stat
              label="Sales-effort factor"
              value={factorText(f.effort_factor ?? 1)}
              badge={!f.has_activity && <Badge tone="warning">Capped: no activity synced</Badge>}
              sub={f.has_activity ? "Calls, connects, follow-ups and activity per open lead against the other partners" : "No call or activity data in 30 days: the factor can never exceed ×1.00 (D27)"}
            />
            <Stat
              label="SLA adherence"
              value={f.sla_adherence == null ? "—" : pct(f.sla_adherence, 0)}
              sub={f.sla_total ? `${f.sla_met ?? 0} of ${f.sla_total} checks met (first call, status updates, enrolment proof)` : "No SLA checks decided yet"}
            />
            <Stat label="SLA factor" value={factorText(f.sla_factor ?? 1)} sub="1.00 at full adherence; every 10 points below subtracts the step, down to 0.80" />
          </dl>
          {f.segments.length > 0 && (
            <div className="overflow-x-auto border-t border-border">
              <table className="w-full text-[12.5px]">
                <thead>
                  <tr className="text-left text-[11px] uppercase tracking-wider text-subtle">
                    <th className="px-5 py-2 font-medium">Segment</th>
                    <th className="px-3 py-2 font-medium">Stage</th>
                    <th className="px-3 py-2 text-right font-medium">Leads</th>
                    <th className="px-3 py-2 text-right font-medium">Effort</th>
                    <th className="px-5 py-2 text-right font-medium">SLA</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {f.segments.map((s) => (
                    <tr key={s.segment}>
                      <td className="px-5 py-2 text-fg">{segmentLabel(s.segment)}</td>
                      <td className="px-3 py-2 text-muted" title={s.auto_stage ? STAGE_LABEL[s.auto_stage] : undefined}>{s.auto_stage ? `Stage ${s.auto_stage}` : "—"}</td>
                      <td className="tabular px-3 py-2 text-right text-fg">{s.n_received}<span className="text-subtle"> · {s.leads_30d} in 30 d</span></td>
                      <td className="tabular px-3 py-2 text-right text-fg">
                        {factorText(s.effort_factor ?? 1)}
                        {s.has_activity === false && <span className="ml-1 text-[11px] text-warning" title="No activity synced in this segment: capped at ×1.00">capped</span>}
                      </td>
                      <td className="tabular px-5 py-2 text-right text-fg">{factorText(s.sla_factor ?? 1)}{s.sla_adherence != null && <span className="text-subtle"> · {pct(s.sla_adherence, 0)}</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <p className="px-5 py-2 text-[11.5px] text-subtle">{f.n_received} leads received in all · Stage A uses commission alone; the factors apply from Stage B. Open a segment on Routing → Segments for every competing partner.</p>
            </div>
          )}
        </>
      )}
    </Card>
  );
}

function Overview({ d }: { d: PartnerDetail }) {
  const p = d.partner;
  const c = p.lead_criteria ?? {};
  const checklistLink = (key: string) => {
    if (key === "programmes") return { href: `/programmes/${p.id}?tab=upload`, text: "Upload the programme file" };
    if (key === "credentials") return { href: "?tab=connection", text: "Set it up in Connection" };
    if (key === "dedupe") return isCrmAdapter(p.adapter_type)
      ? { href: "?tab=connection", text: "Confirm it in Connection (CRM adapter settings)" }
      : { href: "?tab=settings", text: "Choose when the partner reports duplicates in Settings" };
    if (key === "test_leads") return { href: "/routing?tab=simulate", text: "Route a test lead to the sandbox" };
    if (key === "mapping") return { href: `/mapping/${p.id}`, text: "Open the Mapping studio" };
    return { href: "?tab=settings", text: "Set it in Settings" };
  };
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)]">
      <div className="space-y-6">
        <Card>
          <CardHeader title="Go-live checklist" description="Every item must be done before the live switch can turn on." />
          <ul className="divide-y divide-border">
            {d.checklist.map((item) => {
              const label = CHECKLIST_LABEL[item.key] ?? { title: humanize(item.key), pending: "" };
              const link = checklistLink(item.key);
              return (
                <li key={item.key} className="flex items-start gap-3 px-5 py-3">
                  {item.done ? <CircleCheck className="mt-0.5 size-4 shrink-0 text-success" aria-label="Done" /> : <CircleDashed className="mt-0.5 size-4 shrink-0 text-subtle" aria-label="Not done" />}
                  <div className="min-w-0 flex-1">
                    <p className={cn("text-[13px]", item.done ? "text-fg" : "text-muted")}>{label.title}</p>
                    {!item.done && !item.available && label.pending && <p className="text-[12px] text-subtle">{label.pending}</p>}
                    {!item.done && item.available && <Link href={link.href} className="text-[12px] text-info hover:underline">{link.text}</Link>}
                  </div>
                </li>
              );
            })}
            <li className="flex items-start gap-3 px-5 py-3">
              {p.live ? <CircleCheck className="mt-0.5 size-4 shrink-0 text-success" aria-label="Done" /> : <CircleDashed className="mt-0.5 size-4 shrink-0 text-subtle" aria-label="Not done" />}
              <p className={cn("text-[13px]", p.live ? "text-fg" : "text-muted")}>Live switch turned on by the Admin</p>
            </li>
          </ul>
        </Card>
        <RoutingFactors f={d.factors} />
        <Card>
          <CardHeader title="Elsewhere for this partner" />
          <p className="px-5 py-4 text-[13px] leading-6 text-muted">
            Sync health, the SLA scorecard and reconciliation are on <Link href="?tab=sync" className="text-info hover:underline">Sync &amp; SLAs</Link>;
            stage and field mapping in the <Link href={`/mapping/${p.id}`} className="text-info hover:underline">Mapping studio</Link>; programmes and
            commission in the <Link href={`/programmes/${p.id}`} className="text-info hover:underline">Programme Repository</Link>; enrolments, earnings
            and invoices under <Link href="/money" className="text-info hover:underline">Money</Link>; every decision that chose or skipped this partner
            in the <Link href={`/routing?tab=overview&partner=${p.id}`} className="text-info hover:underline">Routing decision log</Link>.
          </p>
        </Card>
      </div>

      <div className="space-y-6">
        <Card>
          <CardHeader title="At a glance" action={<Link href="?tab=settings" className="text-[12.5px] text-info hover:underline">Edit</Link>} />
          <dl className="divide-y divide-border">
            <Row label="Leads this month"><span className="tabular">{d.leads_month}</span> <span className="text-subtle">· {d.leads_total} in total</span></Row>
            <Row label="CRM">{ADAPTER_LABEL[p.adapter_type] ?? p.adapter_type}</Row>
            <Row label="Test endpoint">{p.test_endpoint ? <span className="break-all font-mono text-[12px]">{p.test_endpoint}</span> : <span className="text-subtle">Not set</span>}</Row>
            <Row label="Duplicates reported">
              {DEDUPE_LABEL[p.dedupe_mode]?.label ?? p.dedupe_mode}
              {p.dedupe_mode === "sync" && isCrmAdapter(p.adapter_type) && !p.dedupe_confirmed_at && (
                <span className="block text-[12px] text-warning">Not yet confirmed to block duplicates on create</span>
              )}
            </Row>
            <Row label="Hold window">
              {holdWindowText(p)}
              <span className="block text-[12px] text-subtle">Derived from duplicate handling (Addendum 3)</span>
            </Row>
            <Row label="Duplicate claim window">{duplicateWindowText()}</Row>
            <Row label="Caps">{p.daily_cap ?? "No"} / day · {p.monthly_cap ?? "no"} / month</Row>
            {p.contract_min_monthly !== null && <Row label="Contract minimum">{p.contract_min_monthly} / month</Row>}
            <Row label="Working hours">{summariseHours(p.working_hours)}</Row>
            <Row label="Holidays">{p.holidays.length ? `${p.holidays.length} set` : "None"}</Row>
            <Row label="Push">{p.push_options?.interests_array ? <>Interests as a list (<span className="font-mono text-[12px]">interests[]</span>) and in the note</> : "Interests in the push note"}</Row>
            <Row label="Student notification">{p.notify_enabled ? "On" : "Off"}</Row>
          </dl>
        </Card>
        <Card>
          <CardHeader title="SLAs" description="The first call, status update and enrolment proof can be promised tighter than the rulebook, never looser." />
          <dl className="divide-y divide-border">
            {SLA_FIELDS.map((f) => {
              const v = f.fixed ?? p.sla?.[f.key] ?? f.def;
              return (
                <Row key={f.key} label={f.label}>
                  {v} {v === 1 ? f.unit.slice(0, -1) : f.unit}
                  {f.fixed !== undefined ? <span className="text-subtle"> · fixed</span> : f.rulebook !== undefined ? <span className="text-subtle"> · rulebook {f.rulebook}</span> : null}
                </Row>
              );
            })}
          </dl>
        </Card>
        <Card>
          <CardHeader title="Lead criteria" description="A lead that fails these never routes to this partner (PART 4, Step 1)." />
          <dl className="divide-y divide-border">
            {hasCriteria(c) ? (
              <>
                {c.states_include?.length ? <Row label="Only states">{c.states_include.join(", ")}</Row> : null}
                {c.states_exclude?.length ? <Row label="Never states">{c.states_exclude.join(", ")}</Row> : null}
                {c.cities_include?.length ? <Row label="Only cities">{c.cities_include.join(", ")}</Row> : null}
                {c.cities_exclude?.length ? <Row label="Never cities">{c.cities_exclude.join(", ")}</Row> : null}
                {c.qualifications_include?.length ? <Row label="Only qualifications">{c.qualifications_include.join(", ")}</Row> : null}
                {c.min_academic_pct != null ? <Row label="Minimum academic score">{c.min_academic_pct}%</Row> : null}
                {c.min_work_experience_years != null ? <Row label="Minimum work experience">{c.min_work_experience_years} {c.min_work_experience_years === 1 ? "year" : "years"}</Row> : null}
                {c.sources_exclude?.length ? <Row label="Never sources">{c.sources_exclude.map(humanize).join(", ")}</Row> : null}
                {c.other ? <Row label="Other">{c.other}</Row> : null}
              </>
            ) : (
              <Row label="Restrictions"><span className="text-subtle">None: every eligible lead may route here</span></Row>
            )}
            <Row label="When the lead's data is unknown">
              {c.unknown ? CRITERIA_UNKNOWN_LABEL[c.unknown].label : <>Engine setting <span className="text-subtle">(rulebook default: do not send)</span></>}
            </Row>
          </dl>
        </Card>
        {p.notes && (
          <Card>
            <CardHeader title="Notes" />
            <p className="whitespace-pre-wrap break-words px-5 py-4 text-[13px] text-fg">{p.notes}</p>
          </Card>
        )}
      </div>
    </div>
  );
}

export default async function PartnerPage({ params, searchParams }: Props) {
  await requireAdmin();
  const id = parseId((await params).id);
  if (!id) notFound();
  const d = await partnerDetail(id);
  if (!d) notFound();
  const sp = await searchParams;
  const tab = TABS.find((t) => t.id === sp.tab)?.id ?? "overview";
  const p = d.partner;
  const title = partnerTitle(p);
  const missing = d.checklist.filter((c) => !c.done).length;
  const connection = tab === "connection" ? await partnerConnection(p.id) : null;
  const adapter = tab === "connection" && isCrmAdapter(p.adapter_type) ? await partnerAdapterStatus(p.id) : null;
  const sync = tab === "sync" ? await partnerSync(p.id) : null;
  // m31l's partner_detail reports the engine's pause as auto_pause; the partner row's auto_paused_at is the fallback for an older read.
  const autoPause = d.auto_pause ?? (p.auto_paused_at ? { reason: p.paused_reason, at: p.auto_paused_at, active: p.status === "paused" } : null);
  const autoPaused = autoPause?.active ? autoPause : null;

  return (
    <>
      <Link href="/partners" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Partners</Link>

      <div className="mb-5 flex flex-wrap items-start justify-between gap-4">
        <div className="flex min-w-0 items-center gap-4">
          <PartnerLogo partner={p} size="lg" />
          <div className="min-w-0">
            <h1 className="truncate text-xl font-semibold tracking-tight text-fg">{title}</h1>
            <p className="truncate text-[13px] text-muted">{p.display_name ? `${p.name} · ` : ""}<span className="font-mono">{p.slug}</span></p>
            <div className="mt-1.5 flex flex-wrap gap-1.5">
              <Badge tone={STATUS_TONE[p.status]}>{STATUS_LABEL[p.status]}</Badge>
              {autoPaused && <Badge tone="warning">Paused automatically</Badge>}
              <Badge tone={p.live ? "success" : "neutral"}>{p.live ? "Live" : "Live switch off"}</Badge>
            </div>
          </div>
        </div>
        <PartnerControls id={p.id} title={title} status={p.status} live={p.live} missing={missing} />
      </div>
      {autoPaused ? (
        <p role="status" className="mb-5 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2 text-[13px] text-warning">
          Paused automatically: {autoPaused.reason?.replace(/^auto-paused:\s*/i, "") || "the engine's guard fired"} ·{" "}
          <time dateTime={autoPaused.at} title={formatDateTime(autoPaused.at)}>{relativeTime(autoPaused.at)}</time>.
          New leads skip this partner until you resume it (PART 6.4: five first-contact SLA breaches in a row, failing pushes or a 30-minute sync failure).
        </p>
      ) : p.status === "paused" && p.paused_reason && (
        <p className="mb-5 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2 text-[13px] text-warning">Paused: {p.paused_reason}</p>
      )}
      {sp.created === "1" && (
        <p role="status" className="mb-5 rounded-lg border border-success/25 bg-success-bg px-3 py-2 text-[13px] text-success">
          Partner added. It is in onboarding with its live switch off; work through the go-live checklist below.
        </p>
      )}

      <nav aria-label="Partner sections" className="mb-6 flex gap-5 overflow-x-auto border-b border-border">
        {TABS.map((t) => (
          <Link
            key={t.id}
            href={t.id === "overview" ? `/partners/${p.id}` : `/partners/${p.id}?tab=${t.id}`}
            aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 whitespace-nowrap border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}
          >
            {t.label}
            {t.id === "activity" && <span className="tabular ml-1.5 text-[11px] text-subtle">{d.events.length}</span>}
          </Link>
        ))}
      </nav>

      {tab === "overview" && <Overview d={d} />}
      {tab === "settings" && <PartnerForm partner={p} />}
      {tab === "connection" && connection && <ConnectionTab id={p.id} c={connection} adapter={adapter} />}
      {tab === "sync" && sync && <SyncTab s={sync} />}
      {tab === "activity" && <Card><Activity events={d.events} /></Card>}
    </>
  );
}
