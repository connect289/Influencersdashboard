import Link from "next/link";
import { ChevronLeft, FlaskConical, Gauge, Layers, Pin, Power } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { formatDateTime, relativeTime } from "@/lib/format";
import { inr } from "@/lib/programmes";
import { MODE_LABEL, segmentLabel } from "@/lib/routing";
import { maturityProgress, pct, SCORING_HINT, SCORING_LABEL, STAGE_LABEL, untilText, type RoutingSegments, type SegmentDetail, type SegmentModeInfo } from "@/lib/segments";
import { PartnerWeightForm, PolicyForm, RefreshStatsButton, SegmentPolicyForm } from "./SegmentForms";

function ModeBadge({ m }: { m: SegmentModeInfo }) {
  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      <Badge tone={m.mode === "performance" ? "success" : m.mode === "kill_switch" ? "danger" : "neutral"}>
        {m.mode === "kill_switch" && <Power className="size-3" />}{SCORING_LABEL[m.mode]}
      </Badge>
      {m.pin && m.mode !== "kill_switch" && <Badge tone={m.pin.source === "ai" ? "info" : "brand"}><Pin className="size-3" /> {m.pin.source === "ai" ? "AI pin" : "Pinned"}</Badge>}
    </span>
  );
}

function Bar({ share }: { share: number }) {
  return (
    <span className="block h-1.5 w-full overflow-hidden rounded-full bg-surface-2" aria-hidden>
      <span className={cn("block h-full rounded-full", share >= 1 ? "bg-success" : "bg-amber")} style={{ width: `${Math.round(share * 100)}%` }} />
    </span>
  );
}

/** Segments list (B7.2: the current mode per segment is shown, and the Admin can pin it). */
export function SegmentsPanel({ s }: { s: RoutingSegments }) {
  const p = s.params;
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
      <Card className="min-w-0">
        <CardHeader
          title="Segments"
          description={`Course × level × mode. A segment moves from highest commission to performance once 2 partners each have ${p.min_matured_leads} leads older than ${p.maturity_days} days. Statistics refresh hourly${s.stats_at ? `; last ${relativeTime(s.stats_at)}` : ""}.`}
          action={<RefreshStatsButton />}
        />
        {s.segments.length === 0 ? (
          <EmptyState icon={Layers} title="No segments yet">A segment appears once a lead is routed to a partner in it.</EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-left text-[13px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-b border-border">
                  <th scope="col" className="px-5 py-2.5 font-medium">Segment</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Mode</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Toward performance</th>
                  <th scope="col" className="px-3 py-2.5 text-right font-medium">Leads (30 d)</th>
                  <th scope="col" className="px-5 py-2.5 text-right font-medium">Avg. enrolment</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {s.segments.map((g) => {
                  // half the bar for the best-sampled partner reaching the threshold, the rest once a second one does
                  const share = g.partners_matured >= 2 ? 1 : Math.min(g.best_partner_matured, p.min_matured_leads) / Math.max(p.min_matured_leads, 1) / 2;
                  return (
                    <tr key={g.segment} className="hover:bg-surface-hover/60">
                      <td className="px-5 py-2.5">
                        <Link href={`/routing?tab=segments&segment=${encodeURIComponent(g.segment)}`} className="font-medium text-fg hover:underline">{segmentLabel(g.segment)}</Link>
                        {g.rollup && <span className="ml-1.5 text-[11px] text-subtle">course roll-up</span>}
                      </td>
                      <td className="px-3 py-2.5"><ModeBadge m={g.mode} /></td>
                      <td className="w-48 px-3 py-2.5">
                        <Bar share={share} />
                        <span className="mt-1 block text-[11.5px] text-subtle">{g.partners_matured} of 2 partners · {g.matured} matured</span>
                      </td>
                      <td className="tabular px-3 py-2.5 text-right">{g.leads_30d}</td>
                      <td className="tabular px-5 py-2.5 text-right text-muted">{g.matured ? pct(g.prior) : "—"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <div className="min-w-0 space-y-6">
        <Card className="min-w-0">
          <CardHeader title="How performance is estimated" description="P̂(enrol) per partner and segment: matured leads weighted by recency, young leads through their stage, around the segment's average." />
          <dl className="grid grid-cols-2 gap-x-4 gap-y-2 px-5 pb-4 text-[12.5px]">
            <dt className="text-muted">Maturity</dt><dd className="tabular text-right text-fg">{p.maturity_days} days</dd>
            <dt className="text-muted">Recency half-life</dt><dd className="tabular text-right text-fg">{p.half_life_days} days</dd>
            <dt className="text-muted">Prior strength</dt><dd className="tabular text-right text-fg">{p.prior_weight} leads</dd>
            <dt className="text-muted">Default enrolment rate</dt><dd className="tabular text-right text-fg">{pct(p.default_p_enroll)}</dd>
            <dt className="text-muted">Speed / reliability</dt><dd className="text-right text-fg">{p.speed_on ? "on" : "off"} / {p.reliability_on ? "on" : "off"}</dd>
          </dl>
          <div className="border-t border-border px-5 py-3">
            <p className="mb-1.5 text-[11px] uppercase tracking-wider text-subtle">Enrolment by stage reached (matured leads)</p>
            <ul className="space-y-1 text-[12.5px]">
              {s.stage_rates.map((r) => (
                <li key={r.stage} className="flex justify-between gap-3"><span className="text-muted">{STAGE_LABEL[r.stage]}</span>
                  <span className="tabular text-fg">{pct(r.rate)} <span className="text-subtle">· {r.enrolled}/{r.n}</span></span></li>
              ))}
              {s.stage_rates.length === 0 && <li className="text-muted">Computed at the first refresh.</li>}
            </ul>
          </div>
          <p className="border-t border-border px-5 py-3 text-[12px] text-muted">Change these in <Link href="/routing?tab=settings" className="text-info hover:underline">Engine settings</Link>.</p>
        </Card>
        <Card className="min-w-0">
          <CardHeader title="Holdout and sampling" description={`Policy version ${s.policy_version}. Every change is kept with its reason.`} />
          <div className="px-5 pb-4"><PolicyForm key={s.policy_version} policy={s.policy} version={s.policy_version} /></div>
        </Card>
      </div>
    </div>
  );
}

/** One segment: each partner's estimate with its interval, the flow by mode, the latest decisions and the segment's policy. */
export function SegmentView({ d, policyVersion }: { d: SegmentDetail; policyVersion: number }) {
  const minM = d.params.min_matured_leads;
  const prog = maturityProgress(d.partners.map((x) => ({ matured: x.exact?.matured ?? 0 })), minM);
  const flowTotal = d.flow_30d.reduce((a, f) => a + f.n, 0);
  return (
    <>
      <Link href="/routing?tab=segments" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> All segments</Link>
      <div className="mb-5 flex flex-wrap items-center gap-3">
        <h2 className="text-lg font-semibold tracking-tight text-fg">{segmentLabel(d.segment)}</h2>
        <ModeBadge m={d.mode} />
        {d.mode.pin?.until && <span className="text-[12px] text-subtle">pin {untilText(d.mode.pin.until)}</span>}
      </div>
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
        <div className="min-w-0 space-y-6">
          <Card className="min-w-0">
            <CardHeader title="Partners in this segment" description={`${SCORING_HINT[d.mode.mode]} ${prog.text}.`} />
            <div className="px-5 pb-3"><Bar share={prog.share} /></div>
            {d.partners.length === 0 ? (
              <EmptyState icon={Gauge} title="No partner data yet">Partners that offer this course appear here once leads reach them.</EmptyState>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[760px] text-left text-[12.5px]">
                  <thead className="text-[11px] uppercase tracking-wider text-subtle">
                    <tr className="border-b border-border">
                      <th scope="col" className="px-5 py-2.5 font-medium">Partner</th>
                      <th scope="col" className="px-3 py-2.5 text-right font-medium">Commission</th>
                      <th scope="col" className="px-3 py-2.5 text-right font-medium">Leads / matured / enrolled</th>
                      <th scope="col" className="px-3 py-2.5 text-right font-medium">P̂ enrol (90%)</th>
                      <th scope="col" className="px-3 py-2.5 text-right font-medium">Refunds</th>
                      <th scope="col" className="px-3 py-2.5 text-right font-medium">SLA met</th>
                      <th scope="col" className="px-5 py-2.5 text-right font-medium">NCPL</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border">
                    {[...d.partners].sort((a, b) => b.ncpl - a.ncpl).map((x) => {
                      const est = x.uses === "segment" ? x.exact : x.rollup;
                      return (
                        <tr key={x.partner_id}>
                          <td className="px-5 py-2.5">
                            <Link href={`/partners/${x.partner_id}`} className="font-medium text-fg hover:underline">{x.name}</Link>
                            {x.status !== "active" && <Badge className="ml-1.5">{x.status}</Badge>}
                            {x.weight && <Badge tone={x.weight.source === "ai" ? "info" : "brand"} className="ml-1.5">×{x.weight.weight} {untilText(x.weight.until)}</Badge>}
                          </td>
                          <td className="tabular px-3 py-2.5 text-right">{x.cpe != null ? inr(x.cpe) : <span className="text-warning">No rate</span>}</td>
                          <td className="tabular px-3 py-2.5 text-right text-muted">{x.exact ? `${x.exact.leads} / ${x.exact.matured} / ${x.exact.enrolled}` : "0 / 0 / 0"}</td>
                          <td className="tabular px-3 py-2.5 text-right">
                            {est ? <><span className="text-fg">{pct(est.p_hat)}</span> <span className="text-subtle">{pct(est.interval.low)}–{pct(est.interval.high)}</span></> : "prior"}
                            {x.uses === "course" && <span className="block text-[11px] text-subtle">from the course (under 30 leads here)</span>}
                          </td>
                          <td className="tabular px-3 py-2.5 text-right text-muted">{pct(x.refund_rate)}</td>
                          <td className="tabular px-3 py-2.5 text-right text-muted">{pct(x.sla_compliance, 0)}</td>
                          <td className="tabular px-5 py-2.5 text-right font-medium text-fg">{inr(x.ncpl)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </Card>

          <Card className="min-w-0">
            <CardHeader title="Latest decisions" description={flowTotal ? `Last 30 days: ${d.flow_30d.map((f) => `${f.n} ${(MODE_LABEL[f.mode] ?? f.mode).toLowerCase()}${f.holdout ? " (holdout)" : ""}`).join(", ")}.` : "No real leads routed in this segment in 30 days."} />
            {d.decisions.length === 0 ? (
              <EmptyState icon={Gauge} title="No decisions yet">Decisions in this segment appear here.</EmptyState>
            ) : (
              <ul className="divide-y divide-border text-[12.5px]">
                {d.decisions.map((x) => (
                  <li key={x.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2">
                    <Link href={`/routing/decisions/${x.id}`} className="text-info hover:underline" title={formatDateTime(x.at)}>{relativeTime(x.at)}</Link>
                    <span className="font-medium text-fg">{x.partner_name ?? "—"}</span>
                    <span className="text-subtle">{MODE_LABEL[x.mode] ?? x.mode}{x.selection_probability != null && x.selection_probability < 1 ? ` · p ${pct(x.selection_probability, 0)}` : ""}</span>
                    {x.holdout && <Badge tone="info">Holdout</Badge>}
                    {x.is_test && <FlaskConical className="size-3 text-subtle" aria-label="Test lead" />}
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>

        <div className="min-w-0 space-y-6">
          <Card className="min-w-0">
            <CardHeader title="Segment policy" description="Pin the mode, set its own exploration share or share cap, or switch scoring off for it. AI changes show as AI and never apply to holdout leads." />
            <div className="px-5 pb-4"><SegmentPolicyForm key={policyVersion} segment={d.segment} policy={d.policy} mode={d.mode} /></div>
          </Card>
          <Card className="min-w-0">
            <CardHeader title="Temporary partner weight" description="Nudges a partner's net commission per lead by up to 10% for up to 14 days (performance mode only), e.g. while a new counsellor team settles in." />
            <div className="px-5 pb-4"><PartnerWeightForm key={policyVersion} partners={d.partners} /></div>
          </Card>
        </div>
      </div>
    </>
  );
}
