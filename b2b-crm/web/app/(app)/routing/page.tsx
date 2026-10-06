import type { Metadata } from "next";
import Link from "next/link";
import { FlaskConical, History, ShieldOff, TriangleAlert } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { formatDateTime, relativeTime } from "@/lib/format";
import { inr } from "@/lib/programmes";
import { ALLOCATION_LABEL, LANE_LABEL, MODE_LABEL, NOT_PASSED_LABEL, REASON_LABEL, segmentLabel } from "@/lib/routing";
import { notPassedSummary, routingOverview, type NotPassedSummary, type RoutingOverview } from "@/lib/routing-data";
import type { PushOverview } from "@/lib/push";
import { pushOverview } from "@/lib/push-data";
import { DisputeList } from "../partners/[id]/ConnectionControls";
import { EngineForm } from "./EngineForm";
import { HandoffForm } from "./HandoffForm";
import { RatesPanel } from "./RatesPanel";
import { ReviewQueue } from "./ReviewQueue";
import { RoutingSwitch } from "./RoutingSwitch";
import { RulesPanel } from "./RulesPanel";
import { Simulator } from "./Simulator";

export const metadata: Metadata = { title: "Routing" };

const TABS = [
  { id: "overview", label: "Overview" },
  { id: "simulate", label: "Simulate" },
  { id: "rules", label: "Rules" },
  { id: "rates", label: "Commission rates" },
  { id: "handoff", label: "Hand-off rules" },
  { id: "settings", label: "Engine settings" },
] as const;
type Tab = (typeof TABS)[number]["id"];

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

function Stat({ label, value, tone }: { label: string; value: number; tone?: "success" | "warning" | "danger" }) {
  return (
    <div className="min-w-0 rounded-lg border border-border bg-surface-2/50 px-3 py-2.5">
      <p className="text-[11px] uppercase tracking-wider text-subtle">{label}</p>
      <p className={cn("tabular mt-0.5 text-xl font-semibold", tone === "success" ? "text-success" : tone === "warning" ? "text-warning" : tone === "danger" ? "text-danger" : "text-fg")}>{value}</p>
    </div>
  );
}

function Overview({ o, np, push }: { o: RoutingOverview; np: NotPassedSummary; push: PushOverview }) {
  const engine = o.engine.value;
  const consentRequired = engine.require_partner_consent ?? true;
  const reasons = Object.entries(o.today.b2c_reasons).sort((a, b) => b[1] - a[1]);
  const partners = o.partners.filter((p) => p.status !== "closed");
  const rated = new Set(o.rates.filter((r) => r.valid_to === null).map((r) => r.partner_id));
  const warnings = [
    engine.enabled === false && "The engine is disabled in its settings, so nothing routes even with the switch on.",
    engine.kill_switch && "The engine's kill switch is on, so nothing routes.",
    o.live_partners === 0 && "No partner is live yet: every qualified lead routed now goes to B2C sales.",
    consentRequired && "Partner-sharing consent is required and Witty does not ask for it yet, so qualified Witty leads go to B2C sales (reason: no consent).",
    "Witty stops chatting with any routed lead, B2C nurture included. Addendum 1 asks Witty to keep talking to nurture leads; that needs a change on Witty's side (w2_crm_owned).",
  ].filter(Boolean) as string[];

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <Card className="min-w-0">
        <CardHeader
          title="Automatic routing"
          description="Every minute, leads at their decision point (not test leads) go to a partner or B2C, or are marked not passed."
          action={<RoutingSwitch live={o.switch.live} livePartners={o.live_partners} consentRequired={consentRequired} />}
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
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            <Stat label="To partners today" value={o.today.to_partners} tone="success" />
            <Stat label="B2C sales today" value={o.today.sales} tone={o.today.sales ? "warning" : undefined} />
            <Stat label="B2C nurture today" value={o.today.nurture} />
            <Stat label="Not passed today" value={o.today.not_passed} />
            <Stat label="Test leads" value={o.today.tests} />
            <Stat label="Errors" value={o.today.errors} tone={o.today.errors ? "danger" : undefined} />
          </div>
          {reasons.length > 0 && (
            <ul className="space-y-1 text-[12.5px]">
              {reasons.map(([r, n]) => <li key={r} className="flex justify-between gap-3"><span className="text-muted">{REASON_LABEL[r] ?? r}</span><span className="tabular text-fg">{n}</span></li>)}
            </ul>
          )}
        </div>
      </Card>

      <Card className="min-w-0">
        <CardHeader title="Partner readiness" description="A partner receives leads once it is active, live and has a published programme file. Confirmed rates rank it by commission." />
        {partners.length === 0 ? (
          <EmptyState icon={TriangleAlert} title="No partners yet" action={<Link href="/partners/new" className="text-[13px] text-info hover:underline">Add a partner</Link>}>Until a partner is live, every lead goes to B2C.</EmptyState>
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
        <CardHeader title="Not passed" description="Junk and programme-mismatch leads stay in the master database; no CRM works them."
          action={<Link href="/leads?dest=not_passed" className="shrink-0 text-[13px] text-info hover:underline">Open the list</Link>} />
        {o.not_passed_open === 0 ? (
          <EmptyState icon={ShieldOff} title="Nothing held back">Leads Witty classifies junk or programme mismatch, and invalid or blocked numbers, appear here.</EmptyState>
        ) : (
          <div className="grid gap-4 px-5 py-4 sm:grid-cols-2">
            <ul className="space-y-1 text-[12.5px]">
              {Object.entries(np.by_reason).map(([k, n]) => <li key={k} className="flex justify-between gap-3"><span className="text-muted">{NOT_PASSED_LABEL[k] ?? k}</span><span className="tabular text-fg">{n}</span></li>)}
            </ul>
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
        <CardHeader title="Pushes to partners" description="Last 30 days. A pushed lead waits out the partner's hold window before it is accepted and the student is told." />
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
        <CardHeader title="Commission disputes" description="Duplicate claims after acceptance. The lead stays with the partner; you decide the commission." />
        {push.disputes.length === 0
          ? <EmptyState icon={History} title="No open disputes">A partner&apos;s late duplicate claim appears here with its proof.</EmptyState>
          : <DisputeList disputes={push.disputes} />}
      </Card>

      <Card className="min-w-0 xl:col-span-2">
        <CardHeader title="Decision log" description="The latest 50 routing decisions, automatic and by hand. Open one to see why." />
        {o.decisions.length === 0 ? (
          <EmptyState icon={History} title="No routing decisions yet">Simulate a lead and route it by hand, or turn on automatic routing.</EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-left text-[13px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-b border-border">
                  <th scope="col" className="px-5 py-2.5 font-medium">When</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Lead</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Segment</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Outcome</th>
                  <th scope="col" className="px-3 py-2.5 text-right font-medium">Commission</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Allocation</th>
                  <th scope="col" className="px-5 py-2.5 font-medium">By</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {o.decisions.map((d) => (
                  <tr key={d.id} className="hover:bg-surface-hover/60">
                    <td className="whitespace-nowrap px-5 py-2.5"><Link href={`/routing/decisions/${d.id}`} className="text-info hover:underline" title={formatDateTime(d.created_at)}>{relativeTime(d.created_at)}</Link></td>
                    <td className="max-w-[180px] truncate px-3 py-2.5">
                      <Link href={`/leads?lead=${d.lead_id}`} className="text-fg hover:underline">{d.lead_name || `#${d.lead_id}`}</Link>
                      {d.is_test && <FlaskConical className="ml-1 inline size-3 text-subtle" aria-label="Test lead" />}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-muted">{segmentLabel(d.segment)}</td>
                    <td className="px-3 py-2.5">
                      {d.destination_type === "partner"
                        ? <><span className="font-medium text-fg">{d.partner_name}</span> <span className="text-[12px] text-subtle">· {MODE_LABEL[d.mode] ?? d.mode}</span></>
                        : <span className="text-warning">{LANE_LABEL[d.b2c_lane ?? d.allocation?.b2c_lane ?? "sales"]} · {REASON_LABEL[d.reason ?? ""] ?? d.reason}</span>}
                    </td>
                    <td className="tabular px-3 py-2.5 text-right text-muted">{d.allocation?.cpe_net_inr != null ? inr(d.allocation.cpe_net_inr) : "—"}</td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-[12.5px]">
                      {d.allocation ? <><span className="font-mono text-fg">{d.allocation.reference}</span> <span className="text-subtle">· {ALLOCATION_LABEL[d.allocation.status] ?? d.allocation.status}</span></> : "—"}
                    </td>
                    <td className="px-5 py-2.5 text-muted">{d.actor_type === "engine" ? "Engine" : "Admin"}</td>
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

export default async function RoutingPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? (typeof sp.lead === "string" ? "simulate" : "overview");
  const leadParam = typeof sp.lead === "string" && /^\d{1,15}$/.test(sp.lead) ? Number(sp.lead) : null;
  const [o, np, push] = await Promise.all([routingOverview(), notPassedSummary(), pushOverview()]);
  const partners = o.partners.map((p) => ({ id: p.id, name: p.name, status: p.status }));

  return (
    <>
      <PageHeader
        title="Routing"
        description="Where each lead goes, and why. Junk and mismatch are not passed; paid-campaign and unqualified leads go to Eduwit's B2C CRM (sales or nurture); qualified leads go to the eligible partner with the highest commission, net of GST."
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

      {tab === "overview" && <Overview o={o} np={np} push={push} />}
      {tab === "simulate" && (
        <Card className="min-w-0 p-5">
          <Simulator key={leadParam ?? "none"} initialLead={leadParam} />
        </Card>
      )}
      {tab === "rules" && <Card className="min-w-0 overflow-hidden"><RulesPanel rules={o.rules} partners={partners.filter((p) => p.status !== "closed")} /></Card>}
      {tab === "rates" && <Card className="min-w-0 overflow-hidden"><RatesPanel rates={o.rates} partners={o.partners} /></Card>}
      {tab === "handoff" && (
        <Card className="min-w-0">
          <CardHeader title="Hand-off rules" description="Addenda 1 and 2: every lead is passed to a CRM except junk and programme mismatch. These lists decide which leads are paid campaigns (B2C sales), which came from the B2C CRM, and which numbers are junk." />
          <HandoffForm key={o.engine.version} v={o.engine.value} version={o.engine.version} />
        </Card>
      )}
      {tab === "settings" && (
        <Card className="min-w-0">
          <CardHeader title="Engine settings" description={`Version ${o.engine.version}, changed ${relativeTime(o.engine.updated_at)}. Every change is kept with its reason.`} />
          <EngineForm key={o.engine.version} v={o.engine.value} version={o.engine.version} />
        </Card>
      )}
    </>
  );
}
