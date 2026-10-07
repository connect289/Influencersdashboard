import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft, CircleCheck, CircleDashed, Clock3, History } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { humanize } from "@/lib/leads";
import {
  ADAPTER_LABEL, CHECKLIST_LABEL, DEDUPE_LABEL, partnerTitle, SLA_FIELDS, STATUS_LABEL, STATUS_TONE, summariseHours, type PartnerDetail,
} from "@/lib/partners";
import { partnerDetail } from "@/lib/partners-data";
import { partnerAdapterStatus, partnerConnection } from "@/lib/push-data";
import { isCrmAdapter } from "@/lib/adapters";
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
};

function Activity({ events }: { events: PartnerDetail["events"] }) {
  if (events.length === 0) return <EmptyState icon={History} title="No activity yet" />;
  return (
    <ol className="divide-y divide-border">
      {events.map((e, i) => {
        const p = e.payload as { fields?: string[]; from?: string; to?: string; reason?: string | null; slug?: string };
        const detail = e.type === "partner.updated" && p.fields ? p.fields.map((f) => humanize(f)).join(", ")
          : e.type === "partner.status_changed" ? `${humanize(p.from)} → ${humanize(p.to)}${p.reason ? ` · ${p.reason}` : ""}`
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

function Overview({ d }: { d: PartnerDetail }) {
  const p = d.partner;
  const c = p.lead_criteria ?? {};
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)]">
      <div className="space-y-6">
        <Card>
          <CardHeader title="Go-live checklist" description="Every item must be done before the live switch can turn on." />
          <ul className="divide-y divide-border">
            {d.checklist.map((item) => {
              const label = CHECKLIST_LABEL[item.key] ?? { title: humanize(item.key), pending: "" };
              return (
                <li key={item.key} className="flex items-start gap-3 px-5 py-3">
                  {item.done ? <CircleCheck className="mt-0.5 size-4 shrink-0 text-success" aria-label="Done" /> : <CircleDashed className="mt-0.5 size-4 shrink-0 text-subtle" aria-label="Not done" />}
                  <div className="min-w-0 flex-1">
                    <p className={cn("text-[13px]", item.done ? "text-fg" : "text-muted")}>{label.title}</p>
                    {!item.done && !item.available && label.pending && <p className="text-[12px] text-subtle">{label.pending}</p>}
                    {!item.done && item.available && (item.key === "programmes"
                      ? <Link href={`/programmes/${p.id}?tab=upload`} className="text-[12px] text-info hover:underline">Upload the programme file</Link>
                      : item.key === "credentials" ? <Link href="?tab=connection" className="text-[12px] text-info hover:underline">Set it up in Connection</Link>
                      : item.key === "test_leads" ? <Link href="/routing?tab=simulate" className="text-[12px] text-info hover:underline">Route a test lead to the sandbox</Link>
                      : item.key === "mapping" ? <Link href={`/mapping/${p.id}`} className="text-[12px] text-info hover:underline">Open the Mapping studio</Link>
                      : <Link href="?tab=settings" className="text-[12px] text-info hover:underline">Set it in Settings</Link>)}
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
        <Card>
          <CardHeader title="Coming to this page" />
          <p className="px-5 py-4 text-[13px] leading-6 text-muted">
            Commission per programme and the funnel arrive with the money build. Sync health, SLA scorecard and reconciliation
            are on <Link href="?tab=sync" className="text-info hover:underline">Sync &amp; SLAs</Link>; mapping in the{" "}
            <Link href={`/mapping/${p.id}`} className="text-info hover:underline">Mapping studio</Link>; programmes in the{" "}
            <Link href={`/programmes/${p.id}`} className="text-info hover:underline">Programme Repository</Link>.
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
            <Row label="Duplicates reported">{DEDUPE_LABEL[p.dedupe_mode]?.label ?? p.dedupe_mode}</Row>
            <Row label="Hold window">{p.dedupe_mode === "sync" ? "None" : `${p.hold_minutes} min`}</Row>
            <Row label="Caps">{p.daily_cap ?? "No"} / day · {p.monthly_cap ?? "no"} / month</Row>
            {p.contract_min_monthly !== null && <Row label="Contract minimum">{p.contract_min_monthly} / month</Row>}
            <Row label="Working hours">{summariseHours(p.working_hours)}</Row>
            <Row label="Holidays">{p.holidays.length ? `${p.holidays.length} set` : "None"}</Row>
            <Row label="Student notification">{p.notify_enabled ? "On" : "Off"}</Row>
          </dl>
        </Card>
        <Card>
          <CardHeader title="SLAs" />
          <dl className="divide-y divide-border">
            {SLA_FIELDS.map((f) => {
              const v = p.sla?.[f.key] ?? f.def;
              return <Row key={f.key} label={f.label}>{v} {v === 1 ? f.unit.slice(0, -1) : f.unit}</Row>;
            })}
          </dl>
        </Card>
        {(c.states_include?.length || c.states_exclude?.length || c.sources_exclude?.length || c.other) && (
          <Card>
            <CardHeader title="Lead criteria" />
            <dl className="divide-y divide-border">
              {c.states_include?.length ? <Row label="Only states">{c.states_include.join(", ")}</Row> : null}
              {c.states_exclude?.length ? <Row label="Never states">{c.states_exclude.join(", ")}</Row> : null}
              {c.sources_exclude?.length ? <Row label="Never sources">{c.sources_exclude.map(humanize).join(", ")}</Row> : null}
              {c.other ? <Row label="Other">{c.other}</Row> : null}
            </dl>
          </Card>
        )}
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
              <Badge tone={p.live ? "success" : "neutral"}>{p.live ? "Live" : "Live switch off"}</Badge>
            </div>
          </div>
        </div>
        <PartnerControls id={p.id} title={title} status={p.status} live={p.live} missing={missing} />
      </div>
      {p.status === "paused" && p.paused_reason && (
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
