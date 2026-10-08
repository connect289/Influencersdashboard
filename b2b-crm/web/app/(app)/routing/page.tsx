import type { Metadata } from "next";
import Link from "next/link";
import Form from "next/form";
import { FlaskConical, History, Info, Search, ShieldOff, TriangleAlert } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { inr } from "@/lib/programmes";
import {
  ALLOCATION_LABEL, decisionModeLabel, LANE_LABEL, NOT_PASSED_DETAIL_LABEL, NOT_PASSED_LABEL, REASON_LABEL, reasonLabel, segmentLabel, STAGE_LABEL,
} from "@/lib/routing";
import {
  lostDelays, notPassedSummary, routingDecisions, routingOverview, routingSegment, routingSegments,
  type DecisionPage, type DecisionQuery, type NotPassedSummary, type RoutingOverview,
} from "@/lib/routing-data";
import { isSegment, type Stage } from "@/lib/segments";
import type { PushOverview } from "@/lib/push";
import { pushOverview } from "@/lib/push-data";
import { catalogueUniversities } from "@/lib/programmes-data";
import { DisputeList } from "../partners/[id]/ConnectionControls";
import { ChangeSimulator } from "./ChangeSimulator";
import { EngineForm } from "./EngineForm";
import { GoLiveChecklist } from "./GoLiveChecklist";
import { HandoffForm } from "./HandoffForm";
import { LostDelaysForm } from "./LostDelaysForm";
import { RatesPanel } from "./RatesPanel";
import { ReviewQueue } from "./ReviewQueue";
import { RoutingSwitch } from "./RoutingSwitch";
import { RulesPanel } from "./RulesPanel";
import { SegmentsPanel, SegmentView } from "./SegmentsPanel";
import { Simulator } from "./Simulator";

export const metadata: Metadata = { title: "Routing" };

const TABS = [
  { id: "overview", label: "Overview" },
  { id: "segments", label: "Segments" },
  { id: "simulate", label: "Simulate" },
  { id: "rules", label: "Rules" },
  { id: "rates", label: "Commission rates" },
  { id: "handoff", label: "Hand-off rules" },
  { id: "settings", label: "Engine settings" },
] as const;
type Tab = (typeof TABS)[number]["id"];

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const STAGES: readonly Stage[] = ["A", "B", "C"];
const HOLDER_LABEL: Record<string, string> = { partner: "with a partner (R3)", b2c_selling: "held by B2C (R4)", barred: "partner-barred (R2)", qualification_nurture: "in qualification nurture (R7)" };
/** route_decide's p_how, as stored in engine_decisions.how (CONTRACT 1.1): how the decision was asked for. */
const HOW_LABEL: Record<string, string> = {
  auto: "Automatic", pass: "Passed to CRM", to_partners: "Sent to partners by hand", requalify: "Re-qualified", reroute: "Re-routed by hand", cascade: "Cascade",
  sandbox: "Sandbox", grace: "Lost grace ended",
};
const str = (v: string | string[] | undefined) => (typeof v === "string" ? v.trim() : "");

function Stat({ label, value, tone, href, title }: { label: string; value: number; tone?: "success" | "warning" | "danger" | "info"; href?: string; title?: string }) {
  const cls = "min-w-0 rounded-lg border border-border bg-surface-2/50 px-3 py-2.5";
  const body = (
    <>
      <p className="truncate text-[11px] uppercase tracking-wider text-subtle" title={title ?? label}>{label}</p>
      <p className={cn("tabular mt-0.5 text-xl font-semibold", tone === "success" ? "text-success" : tone === "warning" ? "text-warning" : tone === "danger" ? "text-danger" : tone === "info" ? "text-info" : "text-fg")}>{value}</p>
    </>
  );
  return href ? <Link href={href} className={cn(cls, "block transition-colors hover:border-border-strong")}>{body}</Link> : <div className={cls}>{body}</div>;
}

function ReasonList({ title, reasons }: { title: string; reasons: Record<string, number> }) {
  const rows = Object.entries(reasons).sort((a, b) => b[1] - a[1]);
  return (
    <div className="min-w-0">
      <p className="mb-1 text-[11px] uppercase tracking-wider text-subtle">{title}</p>
      {rows.length === 0
        ? <p className="text-[12.5px] text-subtle">None today</p>
        : <ul className="space-y-1 text-[12.5px]">{rows.map(([r, n]) => <li key={r} className="flex justify-between gap-3"><span className="text-muted">{REASON_LABEL[r] ?? r.replace(/_/g, " ")}</span><span className="tabular text-fg">{n}</span></li>)}</ul>}
    </div>
  );
}

/** The decision log's filters, read from the URL (C62). */
type LogFilters = { q: string; partner: number | null; reason: string; stage: Stage | null; dest: "partner" | "in_house" | null; hideTest: boolean; before: number | null };

function readLogFilters(sp: Record<string, string | string[] | undefined>): LogFilters {
  const stage = str(sp.stage);
  const dest = str(sp.dest);
  return {
    q: str(sp.q).slice(0, 100),
    partner: /^\d{1,12}$/.test(str(sp.partner)) ? Number(str(sp.partner)) : null,
    reason: /^[a-z_]{1,40}$/.test(str(sp.reason)) ? str(sp.reason) : "",
    stage: STAGES.includes(stage as Stage) ? (stage as Stage) : null,
    dest: dest === "partner" || dest === "in_house" ? dest : null,
    hideTest: str(sp.hide_test) === "1",
    before: /^\d{1,15}$/.test(str(sp.before)) ? Number(str(sp.before)) : null,
  };
}

function logHref(f: LogFilters, before: number | null): string {
  const p = new URLSearchParams({ tab: "overview" });
  if (f.q) p.set("q", f.q);
  if (f.partner) p.set("partner", String(f.partner));
  if (f.reason) p.set("reason", f.reason);
  if (f.stage) p.set("stage", f.stage);
  if (f.dest) p.set("dest", f.dest);
  if (f.hideTest) p.set("hide_test", "1");
  if (before) p.set("before", String(before));
  return `/routing?${p.toString()}#decisions`;
}

function logQuery(f: LogFilters): DecisionQuery {
  return {
    q: f.q || undefined, partner_id: f.partner ?? undefined, reason: f.reason || undefined, stage: f.stage ?? undefined, destination: f.dest ?? undefined,
    hide_test: f.hideTest || undefined, before_id: f.before ?? undefined, limit: 50,
  };
}

const hasFilters = (f: LogFilters) => Boolean(f.q || f.partner || f.reason || f.stage || f.dest || f.hideTest);

function DecisionLog({ page, filters, partners }: { page: DecisionPage; filters: LogFilters; partners: { id: number; name: string }[] }) {
  const select = "h-8 rounded-lg border border-border bg-surface px-2 text-[12.5px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";
  const reasonOptions = Object.entries(REASON_LABEL).sort((a, b) => a[1].localeCompare(b[1]));
  return (
    <Card id="decisions" className="min-w-0 xl:col-span-2">
      <CardHeader title="Decision log" description="Every routing decision, automatic and by hand, newest first. Search by lead ID, phone or name, then open a decision to see why. Each one stores the stage, commission, P(enrol), both factors and the score." />
      <Form action="/routing" scroll={false} className="flex flex-wrap items-end gap-2 border-b border-border bg-surface-2/40 px-5 py-3">
        <input type="hidden" name="tab" value="overview" />
        <label className="min-w-0 flex-1 basis-56">
          <span className="sr-only">Lead ID, phone or name</span>
          <span className="relative block">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-subtle" aria-hidden />
            <input name="q" defaultValue={filters.q} maxLength={100} placeholder="Lead ID, phone or name" autoComplete="off"
              className="h-8 w-full rounded-lg border border-border bg-surface pl-8 pr-2 text-[12.5px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30" />
          </span>
        </label>
        <label><span className="sr-only">Partner</span>
          <select name="partner" defaultValue={filters.partner ?? ""} className={select}>
            <option value="">Any partner</option>
            {partners.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select></label>
        <label><span className="sr-only">Reason</span>
          <select name="reason" defaultValue={filters.reason} className={cn(select, "max-w-[220px]")}>
            <option value="">Any reason</option>
            {reasonOptions.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select></label>
        <label><span className="sr-only">Stage</span>
          <select name="stage" defaultValue={filters.stage ?? ""} className={select}>
            <option value="">Any stage</option>
            {STAGES.map((s) => <option key={s} value={s}>Stage {s}: {STAGE_LABEL[s]}</option>)}
          </select></label>
        <label><span className="sr-only">Destination</span>
          <select name="dest" defaultValue={filters.dest ?? ""} className={select}>
            <option value="">Partner or B2C</option>
            <option value="partner">To a partner</option>
            <option value="in_house">To B2C</option>
          </select></label>
        <label className="flex h-8 items-center gap-1.5 text-[12.5px] text-muted">
          <input type="checkbox" name="hide_test" value="1" defaultChecked={filters.hideTest} className="accent-[var(--primary)]" /> Hide test leads
        </label>
        <button type="submit" className={buttonClass("secondary", "sm")}>Filter</button>
        {(hasFilters(filters) || filters.before) && <Link href="/routing?tab=overview#decisions" scroll={false} className="text-[12.5px] text-info hover:underline">Clear</Link>}
      </Form>
      {page.rows.length === 0 ? (
        <EmptyState icon={History} title={hasFilters(filters) || filters.before ? "No decision matches" : "No routing decisions yet"}>
          {hasFilters(filters) || filters.before ? "Loosen the filters, or clear them." : "Simulate a lead and route it by hand, or turn on automatic routing."}
        </EmptyState>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[960px] text-left text-[13px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="px-5 py-2.5 font-medium">When</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Lead</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Segment</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Decided by</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Outcome</th>
                <th scope="col" className="px-3 py-2.5 text-right font-medium">Score / commission</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Allocation</th>
                <th scope="col" className="px-5 py-2.5 font-medium">Asked by</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {page.rows.map((d) => {
                const how = d.how && d.how !== "auto" ? HOW_LABEL[d.how] ?? d.how : null;
                const amount = d.destination_type === "partner" ? (d.allocation?.score_inr ?? d.score ?? d.allocation?.cpe_net_inr ?? null) : null;
                return (
                  <tr key={d.id} className="hover:bg-surface-hover/60">
                    <td className="whitespace-nowrap px-5 py-2.5"><Link href={`/routing/decisions/${d.id}`} className="text-info hover:underline" title={formatDateTime(d.created_at)}>{relativeTime(d.created_at)}</Link></td>
                    <td className="max-w-[180px] truncate px-3 py-2.5">
                      <Link href={`/leads?lead=${d.lead_id}`} className="text-fg hover:underline">{d.lead_name || `#${d.lead_id}`}</Link>
                      {d.is_test && <FlaskConical className="ml-1 inline size-3 text-subtle" aria-label="Test lead" />}
                      {d.attribution?.paid && <Badge tone="brand" className="ml-1.5 align-middle">Paid</Badge>}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-muted" title={d.eval_segment && d.eval_segment !== d.segment ? `Evaluated as ${segmentLabel(d.eval_segment)}` : undefined}>{segmentLabel(d.segment)}</td>
                    <td className="whitespace-nowrap px-3 py-2.5">
                      {d.stage && <Badge tone="info" className="mr-1.5">Stage {d.stage}</Badge>}
                      <span className="text-fg">{decisionModeLabel(d)}</span>
                      {d.holdout && <span className="ml-1.5 text-[11px] text-subtle">holdout</span>}
                    </td>
                    <td className="px-3 py-2.5">
                      {d.destination_type === "partner"
                        ? <span className="font-medium text-fg">{d.partner_name}</span>
                        : <span className="text-warning">{LANE_LABEL[d.b2c_lane ?? d.allocation?.b2c_lane ?? "sales"]} · {reasonLabel(d.reason, d.allocation?.cause)}</span>}
                    </td>
                    <td className="tabular px-3 py-2.5 text-right text-muted" title={d.allocation?.score_inr != null ? "Score in ₹ (the stage formula)" : "Commission per enrolment, net of GST"}>{amount != null ? inr(amount) : "—"}</td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-[12.5px]">
                      {d.allocation ? <><span className="font-mono text-fg">{d.allocation.reference}</span> <span className="text-subtle">· {ALLOCATION_LABEL[d.allocation.status] ?? d.allocation.status}</span></> : "—"}
                    </td>
                    <td className="whitespace-nowrap px-5 py-2.5 text-muted">{d.actor_type === "engine" ? "Engine" : "Admin"}{how && <span className="text-[11.5px] text-subtle"> · {how}</span>}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      {(page.next_before_id || filters.before) && (
        <div className="flex items-center justify-between gap-3 border-t border-border px-5 py-3 text-[12.5px]">
          <span className="text-muted">{page.rows.length} decision{page.rows.length === 1 ? "" : "s"} on this page{filters.before ? `, older than #${filters.before}` : ""}</span>
          <span className="flex gap-4">
            {filters.before && <Link href={logHref(filters, null)} scroll={false} className="text-info hover:underline">Newest</Link>}
            {page.next_before_id && <Link href={logHref(filters, page.next_before_id)} scroll={false} className="text-info hover:underline">Older →</Link>}
          </span>
        </div>
      )}
    </Card>
  );
}

function Overview({ o, np, push, log, filters }: { o: RoutingOverview; np: NotPassedSummary; push: PushOverview; log: DecisionPage; filters: LogFilters }) {
  const engine = o.engine.value;
  const golive = o.golive ?? [];
  const t = o.today;
  const partners = o.partners.filter((p) => p.status !== "closed");
  const rated = new Set(o.rates.filter((r) => r.valid_to === null).map((r) => r.partner_id));
  const reenquiries = Object.values(t.reenquiries ?? {}).reduce((a, b) => a + b, 0);
  const consent = t.consent ?? { requested: 0, queued: 0, yes: 0, no: 0, expired: 0 };
  const stages = t.stages ?? { A: 0, B: 0, C: 0 };
  // not_passed_summary groups by reason today; a by_detail block (spam rule / catalogue) is read when the function adds it.
  const byDetail = (np as NotPassedSummary & { by_detail?: Record<string, number> }).by_detail ?? {};
  const warnings = [
    engine.enabled === false && "The engine is disabled in its settings, so nothing routes even with the switch on.",
    o.live_partners === 0 && "No partner is live yet: every qualified lead routed now goes to B2C sales (no partner offers the programme).",
    engine.consent_policy === "b2c_sales" && "Consent policy 'B2C sales': qualified leads without recorded partner-sharing consent go to B2C sales instead of being asked (R8 says ask).",
  ].filter(Boolean) as string[];

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <GoLiveChecklist items={golive} live={o.switch.live} />

      <Card className="min-w-0">
        <CardHeader
          title="Automatic routing"
          description="Every minute, leads at their decision point are decided in the rulebook's order, R1 to R9: partners get the bulk, paid Meta and Google leads included."
          action={<RoutingSwitch live={o.switch.live} livePartners={o.live_partners} golive={golive} />}
        />
        <div className="space-y-3 px-5 pb-5">
          <p className="flex flex-wrap items-center gap-2 text-[13px]">
            <Badge tone={o.switch.live ? "success" : "neutral"}>{o.switch.live ? "On" : "Off"}</Badge>
            {o.switch.switched_at
              ? <span className="text-muted">since <span title={formatDateTime(o.switch.switched_at)}>{relativeTime(o.switch.switched_at)}</span>{o.switch.reason && <> · {o.switch.reason}</>}</span>
              : <span className="text-muted">Never turned on. Single leads can still be routed by hand from Simulate.</span>}
          </p>
          {warnings.length > 0 && (
            <ul className="space-y-1.5 rounded-lg border border-warning/25 bg-warning-bg px-3 py-2 text-[12.5px] text-warning">
              {warnings.map((w) => <li key={w} className="flex gap-2"><TriangleAlert className="mt-0.5 size-3.5 shrink-0" /> {w}</li>)}
            </ul>
          )}
          <ul className="space-y-1 text-[12.5px] text-muted">
            <li className="flex gap-2"><Info className="mt-0.5 size-3.5 shrink-0 text-info" /> Qualified leads without recorded partner-sharing consent are asked for it, from Witty&apos;s number once Witty W2 is live, otherwise from the B2C number; YES routes them, NO sends them to B2C sales, no answer in 48 hours to B2C nurture, where the request repeats.</li>
            <li className="flex gap-2"><Info className="mt-0.5 size-3.5 shrink-0 text-info" /> Unqualified leads go to B2C qualification nurture and come back to partner routing the moment they qualify. Duplicate-cascade and partner-lost leads are partner-barred for ever.</li>
            <li className="flex gap-2"><Info className="mt-0.5 size-3.5 shrink-0 text-info" /> Witty stops chatting with a student only when a partner accepts the lead or a B2C counsellor is assigned. The rulebook&apos;s numbers (stage gates, limits, grace, consent wait) are fixed; see Engine settings.</li>
          </ul>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            <Stat label="To partners today" value={t.to_partners} tone="success" />
            <Stat label="B2C sales today" value={t.sales} tone={t.sales ? "warning" : undefined} />
            <Stat label="B2C nurture today" value={t.nurture} />
            <Stat label="Not passed today" value={t.not_passed} href="/leads?dest=not_passed" />
            <Stat label="Test leads" value={t.tests} />
            <Stat label="Errors" value={t.errors} tone={t.errors ? "danger" : undefined} />
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <ReasonList title="B2C sales, by reason" reasons={t.b2c_reasons_by_lane?.sales ?? {}} />
            <ReasonList title="B2C nurture, by reason" reasons={t.b2c_reasons_by_lane?.nurture ?? {}} />
          </div>
        </div>
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Movements today" description="Later movements and the Addendum 3 rules at work: re-qualification (R7 → R9), consent requests (R8), re-enquiries (R2–R4), the partner bar and the lost grace." />
        <div className="space-y-4 px-5 py-4">
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <Stat label="Requalified → partners" value={t.requalified_to_partners ?? 0} tone="success" title="Qualification-nurture leads that qualified and went to a partner" />
            <Stat label="Sent by hand → partners" value={t.manual_to_partners ?? 0} title="Route-to-partners and re-routes by the Admin" />
            <Stat label="Partner-barred today" value={t.barred ?? 0} tone={t.barred ? "warning" : undefined} href="/leads?dest=barred" title="Leads barred from partners for ever (duplicate cascade or partner lost)" />
            <Stat label="Lost, in grace" value={t.lost_in_grace ?? 0} tone={t.lost_in_grace ? "info" : undefined} href="/leads?dest=lost_grace" title="Marked lost by the partner; with the partner for 7 days, then B2C nurture" />
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="min-w-0">
              <p className="mb-1 text-[11px] uppercase tracking-wider text-subtle">Consent requests</p>
              <ul className="space-y-1 text-[12.5px]">
                <li className="flex justify-between gap-3"><span className="text-muted">Asked today</span><span className="tabular text-fg">{consent.requested}</span></li>
                <li className="flex justify-between gap-3"><span className="text-muted">Waiting in the hourly queue</span><span className={cn("tabular", consent.queued ? "text-warning" : "text-fg")}>{consent.queued}</span></li>
                <li className="flex justify-between gap-3"><span className="text-muted">Said YES today</span><span className="tabular text-success">{consent.yes}</span></li>
                <li className="flex justify-between gap-3"><span className="text-muted">Said NO today (B2C sales)</span><span className="tabular text-fg">{consent.no}</span></li>
                <li className="flex justify-between gap-3"><span className="text-muted">Expired today, 48 h (B2C nurture)</span><span className="tabular text-fg">{consent.expired}</span></li>
              </ul>
              <Link href="/leads?dest=awaiting_consent" className="mt-1 inline-block text-[12px] text-info hover:underline">Leads awaiting consent</Link>
            </div>
            <div className="min-w-0 space-y-3">
              <div>
                <p className="mb-1 text-[11px] uppercase tracking-wider text-subtle">Re-enquiries today ({reenquiries})</p>
                <ul className="space-y-1 text-[12.5px]">
                  {(["partner", "b2c_selling", "qualification_nurture", "barred"] as const).map((h) => (
                    <li key={h} className="flex justify-between gap-3"><span className="text-muted">Lead {HOLDER_LABEL[h]}</span><span className="tabular text-fg">{t.reenquiries?.[h] ?? 0}</span></li>
                  ))}
                </ul>
                <Link href="/leads?dest=reenquired" className="mt-1 inline-block text-[12px] text-info hover:underline">Unacknowledged re-enquiries</Link>
              </div>
              <div>
                <p className="mb-1 text-[11px] uppercase tracking-wider text-subtle">Partner decisions by stage</p>
                <ul className="space-y-1 text-[12.5px]">
                  {STAGES.map((s) => <li key={s} className="flex justify-between gap-3"><span className="text-muted">Stage {s}: {STAGE_LABEL[s]}</span><span className="tabular text-fg">{stages[s] ?? 0}</span></li>)}
                </ul>
              </div>
            </div>
          </div>
        </div>
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Partner readiness" description="A partner receives leads once it is active, live, not paused and has a published programme file. Confirmed commission rates rank it in Stage A; sales effort and SLA adherence join in Stages B and C." />
        {partners.length === 0 ? (
          <EmptyState icon={TriangleAlert} title="No partners yet" action={<Link href="/partners/new" className="text-[13px] text-info hover:underline">Add a partner</Link>}>Until a partner is live, every qualified lead goes to B2C sales.</EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[480px] text-left text-[13px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-b border-border">
                  <th scope="col" className="px-5 py-2.5 font-medium">Partner</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Status</th>
                  <th scope="col" className="px-3 py-2.5 text-right font-medium">Programmes</th>
                  <th scope="col" className="px-5 py-2.5 font-medium">Rates</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {partners.map((p) => (
                  <tr key={p.id}>
                    <td className="px-5 py-2.5"><Link href={`/partners/${p.id}`} className="font-medium text-fg hover:underline">{p.name}</Link></td>
                    <td className="px-3 py-2.5">
                      <span className="flex flex-wrap gap-1">
                        <Badge tone={p.live ? "success" : p.status === "active" ? "warning" : "neutral"}>{p.live ? "Live" : p.status === "active" ? "Active, not live" : p.status}</Badge>
                        {p.paused_reason && <Badge tone="warning" className="whitespace-nowrap" >{p.auto_paused_at ? "Auto-paused" : "Paused"}: {p.paused_reason}</Badge>}
                        {p.test_endpoint && <Badge tone="brand"><FlaskConical className="size-3" /> Sandbox</Badge>}
                      </span>
                    </td>
                    <td className="tabular px-3 py-2.5 text-right">{p.offers ? p.offers : <Link href={`/programmes/${p.id}?tab=upload`} className="text-warning hover:underline">None</Link>}</td>
                    <td className="px-5 py-2.5 text-[12.5px]">
                      {p.proposed
                        ? <Link href="/routing?tab=rates" className="text-warning hover:underline">{p.proposed} from the file to confirm</Link>
                        : rated.has(p.id) ? <span className="text-muted">Confirmed</span> : <Link href="/routing?tab=rates" className="text-warning hover:underline">No rate</Link>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Not passed (R5)" description="Junk, programme mismatch, spam, blocked and invalid numbers stay in the master database; no CRM works them. Each lead shows the spam rule or catalogue check behind the verdict; Pass to CRM overrides it by hand."
          action={<Link href="/leads?dest=not_passed" className="shrink-0 text-[13px] text-info hover:underline">Open the list</Link>} />
        {o.not_passed_open === 0 ? (
          <EmptyState icon={ShieldOff} title="Nothing held back">Leads Witty classifies junk or programme mismatch, spam (Witty blocks, disposable email domains, bursts from one IP address or device), courses not in the catalogue, and invalid or blocked numbers appear here.</EmptyState>
        ) : (
          <div className="grid gap-4 px-5 py-4 sm:grid-cols-2">
            <div>
              <ul className="space-y-1 text-[12.5px]">
                {Object.entries(np.by_reason).sort((a, b) => b[1] - a[1]).map(([k, n]) => <li key={k} className="flex justify-between gap-3"><span className="text-muted">{NOT_PASSED_LABEL[k] ?? k.replace(/_/g, " ")}</span><span className="tabular text-fg">{n}</span></li>)}
              </ul>
              {Object.keys(byDetail).length > 0 && (
                <ul className="mt-2 space-y-1 border-t border-border pt-2 text-[12px]">
                  {Object.entries(byDetail).sort((a, b) => b[1] - a[1]).map(([k, n]) => <li key={k} className="flex justify-between gap-3"><span className="text-subtle">{NOT_PASSED_DETAIL_LABEL[k] ?? k.replace(/^spam:/, "spam: ").replace(/_/g, " ")}</span><span className="tabular text-muted">{n}</span></li>)}
                </ul>
              )}
            </div>
            {np.mismatch_courses.length > 0 && (
              <div>
                <p className="mb-1 text-[11px] uppercase tracking-wider text-subtle">Asked for, not offered</p>
                <ul className="space-y-1 text-[12.5px]">
                  {np.mismatch_courses.slice(0, 6).map((c) => <li key={c.course} className="flex justify-between gap-3"><span className="truncate text-fg">{c.course}</span><span className="tabular text-muted">{c.n}</span></li>)}
                </ul>
              </div>
            )}
          </div>
        )}
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Review queue" description="Passed leads that Witty later classified junk or mismatch. They are never pulled back automatically." />
        {o.flags_open.length === 0
          ? <EmptyState icon={TriangleAlert} title="Nothing to review">A passed lead that Witty later reclassifies appears here.</EmptyState>
          : <ReviewQueue flags={o.flags_open} />}
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Pushes to partners" description="Last 30 days. A pushed lead waits out the partner's hold window (0 or 30 minutes) before it is accepted and the student is told. A duplicate or rejection moves it to the next partner: 2 attempts and 3 partners at most, then B2C sales." />
        <div className="grid grid-cols-2 gap-2 px-5 py-4 sm:grid-cols-4">
          <Stat label="Queued or sending" value={(push.by_status.queued ?? 0) + (push.by_status.pushing ?? 0)} />
          <Stat label="In hold window" value={push.by_status.pushed ?? 0} />
          <Stat label="Accepted" value={push.by_status.accepted ?? 0} tone="success" />
          <Stat label="Duplicate / rejected / failed" value={(push.by_status.duplicate ?? 0) + (push.by_status.rejected ?? 0) + (push.by_status.failed ?? 0)}
            tone={(push.by_status.failed ?? 0) > 0 ? "danger" : undefined} />
        </div>
        {push.retrying.length > 0 && (
          <ul className="space-y-1 border-t border-border px-5 py-3 text-[12.5px] text-warning">
            {push.retrying.map((r) => <li key={r.id}><span className="font-mono">{r.reference}</span> to {r.partner_name}: attempt {r.attempts} failed ({r.last_error})</li>)}
          </ul>
        )}
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Commission disputes" description="Duplicate claims within 24 hours of acceptance, and partner activity reported after a lost lead's grace ended. The lead stays where it is; you decide the commission." />
        {push.disputes.length === 0
          ? <EmptyState icon={History} title="No open disputes">A partner&apos;s late duplicate claim, or activity after the lost grace, appears here with its proof.</EmptyState>
          : <DisputeList disputes={push.disputes} />}
      </Card>

      <DecisionLog page={log} filters={filters} partners={o.partners.filter((p) => p.status !== "closed").map((p) => ({ id: p.id, name: p.name }))} />
    </div>
  );
}

export default async function RoutingPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? (typeof sp.lead === "string" ? "simulate" : "overview");
  const leadParam = typeof sp.lead === "string" && /^\d{1,15}$/.test(sp.lead) ? Number(sp.lead) : null;
  const filters = readLogFilters(sp);
  const [o, np, push, log, universities] = await Promise.all([
    routingOverview(),
    notPassedSummary(),
    pushOverview(),
    tab === "overview" ? routingDecisions(logQuery(filters)) : Promise.resolve<DecisionPage>({ rows: [], next_before_id: null }),
    tab === "rules" || tab === "rates" ? catalogueUniversities() : Promise.resolve([]),
  ]);
  const partners = o.partners.map((p) => ({ id: p.id, name: p.name, status: p.status }));

  return (
    <>
      <PageHeader
        title="Routing"
        description="Where each lead goes, and why (Addendum 3). Partners get the bulk: every qualified lead, paid Meta and Google leads included, goes to the eligible partner with the best score: commission per enrolment net of GST first, sales effort and SLA adherence once there is data. Junk and mismatch are not passed; unqualified leads go to B2C qualification nurture and return once qualified; duplicate-cascade and partner-lost leads are partner-barred for ever."
      />

      <nav aria-label="Routing sections" className="mb-6 flex gap-5 overflow-x-auto border-b border-border">
        {TABS.map((t) => (
          <Link key={t.id} href={`/routing?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}
            {t.id === "rules" && <span className="tabular ml-1.5 text-[11px] text-subtle">{o.rules.filter((r) => r.active).length}</span>}
            {t.id === "overview" && <span className={cn("ml-1.5 inline-block size-1.5 rounded-full align-middle", o.switch.live ? "bg-success" : "bg-subtle")} aria-label={o.switch.live ? "on" : "off"} />}
          </Link>
        ))}
      </nav>

      {tab === "overview" && <Overview o={o} np={np} push={push} log={log} filters={filters} />}
      {tab === "segments" && (isSegment(sp.segment)
        ? <SegmentView d={await routingSegment(sp.segment)} policyVersion={(await routingSegments()).policy_version} />
        : <SegmentsPanel s={await routingSegments()} />)}
      {tab === "simulate" && (
        <div className="space-y-6">
          <Card className="min-w-0 p-5">
            <Simulator key={leadParam ?? "none"} initialLead={leadParam} />
          </Card>
          <Card className="min-w-0">
            <CardHeader title="What if: replay a change" description="Estimates net commission per lead under a proposed setting (effort weights and bounds, SLA floor, P̂ half-life and prior), from logged decisions and their selection probabilities (inverse propensity), with a 95% interval. Nothing is changed by a simulation." />
            <div className="px-5 pb-5"><ChangeSimulator partners={partners.filter((p) => p.status === "active")} /></div>
          </Card>
        </div>
      )}
      {tab === "rules" && <Card className="min-w-0 overflow-hidden"><RulesPanel rules={o.rules} partners={partners.filter((p) => p.status !== "closed")} universities={universities} /></Card>}
      {tab === "rates" && <Card className="min-w-0 overflow-hidden"><RatesPanel rates={o.rates} partners={o.partners} universities={universities} /></Card>}
      {tab === "handoff" && (
        <Card className="min-w-0">
          <CardHeader title="Hand-off rules" description="Addenda 1 to 3: every lead is passed to a CRM except junk, programme mismatch, spam and blocked or invalid numbers (R5). These lists decide which sources were created in the B2C CRM (R6), which numbers are blocked, and the spam rules. Paid is an attribution label only: it no longer changes routing." />
          <HandoffForm key={o.engine.version} v={o.engine.value} version={o.engine.version} />
        </Card>
      )}
      {tab === "settings" && (
        <SettingsTab o={o} />
      )}
    </>
  );
}

async function SettingsTab({ o }: { o: RoutingOverview }) {
  const delays = await lostDelays();
  return (
    <div className="space-y-6">
      <Card className="min-w-0">
        <CardHeader title="Engine settings" description={`Version ${o.engine.version}, changed ${relativeTime(o.engine.updated_at)}. Every change is kept with its reason. The rulebook's numbers are fixed by Addendum 3 and listed read-only below the editable settings; routing rules are the only override.`} />
        <EngineForm key={o.engine.version} v={o.engine.value} version={o.engine.version} />
      </Card>
      <Card className="min-w-0">
        <CardHeader title="First nurture message after a partner loss" description="When a partner marks a lead lost and the 7-day grace ends, the lead goes to B2C nurture, unassigned. The lost reason sets how many days pass before B2C's first nurture message (3 to 90)." />
        <LostDelaysForm key={delays.version ?? 0} v={delays.value} version={delays.version} />
      </Card>
    </div>
  );
}
