import { Fragment } from "react";
import Link from "next/link";
import { ChevronLeft, FlaskConical, Gauge, History, Layers, Scale, Sparkles, TrendingUp } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { dashboardsList } from "@/lib/analytics-data";
import { formatDateTime, relativeTime } from "@/lib/format";
import { decisionModeLabel, segmentLabel, STAGE_HINT, STAGE_LABEL } from "@/lib/routing";
import { settingsHistory, type SettingsHistoryRow } from "@/lib/routing-data";
import {
  EFFORT_METRIC_LABEL, EFFORT_METRICS, pct, SLA_KEYS, SLA_LABEL, STAGE_GATES, STAGE_RATE_LABEL, stageProgress, weeklyShares,
  type EngineParams, type RoutingSegments, type SegmentDetail, type SegmentModeInfo, type SegmentPartner, type Stage, type StageBProgress,
} from "@/lib/segments";
import { CpeCell, EffortCell, PCell, ScoreCell, SlaCell } from "./DecisionView";
import { PolicyForm, RefreshStatsButton, SegmentPolicySummary } from "./SegmentForms";

/** Segments tab (Addendum 3, PART 4): every segment's stage and its progress toward the next gate, and per segment the engine's
 *  own numbers per partner (CPE with its basis, P(enrol) with its source, effort and SLA factors, score). Read-only: the
 *  Admin's override tool is a routing rule (D24). Everything comes from b2b.routing_segments / routing_segment (m31l), which
 *  score the segment with the same stage_score the engine uses (C58, C59). */

const STAGE_TONE: Record<Stage, "neutral" | "info" | "success"> = { A: "neutral", B: "info", C: "success" };

function StageBadge({ m, compact = false }: { m: SegmentModeInfo; compact?: boolean }) {
  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      <Badge tone={STAGE_TONE[m.stage]} className="font-normal">Stage {m.stage}{!compact && <>: {STAGE_LABEL[m.stage]}</>}</Badge>
      {m.variant === "ai" && <Badge tone="info" className="font-normal"><Sparkles className="size-3" /> AI-steered</Badge>}
      {m.auto_stage && m.auto_stage !== m.stage && <span className="text-[11px] text-subtle" title="The stage stored at the last statistics refresh">stored {m.auto_stage}</span>}
    </span>
  );
}

function Bar({ share, label }: { share: number; label?: string }) {
  const s = Math.max(0, Math.min(1, Number.isFinite(share) ? share : 0));
  return (
    <span className="block" title={label}>
      <span className="block h-1.5 w-full overflow-hidden rounded-full bg-surface-2" aria-hidden>
        <span className={cn("block h-full rounded-full", s >= 1 ? "bg-success" : "bg-amber")} style={{ width: `${Math.round(s * 100)}%` }} />
      </span>
    </span>
  );
}

/** Progress toward Stage B (leads per partner out of 20, oldest lead out of 7 days) and Stage C (matured out of 30 × 2). */
function GateProgress({ b, c, stage }: { b: StageBProgress; c: number; stage: Stage }) {
  const g = STAGE_GATES;
  return (
    <div className="grid min-w-[220px] grid-cols-2 gap-x-3 gap-y-1 text-[11px] text-subtle">
      <span>{stage === "A" ? "Toward B" : "Stage B gate"}</span>
      <span>{stage === "C" ? "Stage C gate" : "Toward C"}</span>
      <span className="space-y-0.5">
        <Bar share={b.leads} label={`${Math.round(b.leads * g.stage_b_min_leads)} of ${g.stage_b_min_leads} leads for the partner with the fewest`} />
        <Bar share={b.age} label={`first lead ${Math.round(b.age * g.stage_b_min_age_days)} of ${g.stage_b_min_age_days} days old for the youngest partner`} />
        <span className="block tabular">leads {pct(b.leads, 0)} · age {pct(b.age, 0)}</span>
      </span>
      <span className="space-y-0.5">
        <Bar share={c} label={`${g.stage_c_min_partners} partners × ${g.stage_c_min_matured} matured leads`} />
        <span className="block tabular">matured {pct(c, 0)}</span>
      </span>
    </div>
  );
}

/** One version of a setting with its diff (b2b.settings_history, C62). */
function HistoryCard({ rows, title, description }: { rows: SettingsHistoryRow[] | null; title: string; description: string }) {
  const show = (v: unknown) => (v === undefined ? "—" : JSON.stringify(v));
  return (
    <Card className="min-w-0">
      <CardHeader title={title} description={description} />
      {rows === null ? <p className="px-5 py-4 text-[12.5px] text-muted">History is not available (b2b.settings_history missing or not granted).</p>
        : rows.length === 0 ? <p className="px-5 py-4 text-[12.5px] text-muted">No versions yet.</p>
        : (
          <ul className="divide-y divide-border text-[12.5px]">
            {rows.map((r) => (
              <li key={r.version} className="px-5 py-2.5">
                <p className="flex flex-wrap items-center gap-x-2 text-muted">
                  <History className="size-3.5 text-subtle" />
                  <span className="font-medium text-fg">v{r.version}</span>
                  <span>{formatDateTime(r.at)}</span>
                  <span>· {r.actor === "autopilot" ? "Autopilot" : r.actor === "engine" || r.actor === "system" ? "the system" : r.actor_id ? "an Admin" : r.actor ?? "—"}{r.ai_run_id ? ` · AI run #${r.ai_run_id}` : ""}</span>
                  {r.reason && <span className="basis-full text-fg">{r.reason}</span>}
                </p>
                {Object.keys(r.changed).length > 0 && (
                  <ul className="mt-1 space-y-0.5 font-mono text-[11.5px] text-subtle">
                    {Object.entries(r.changed).map(([k, v]) => <li key={k} className="break-all"><span className="text-muted">{k}</span>: {show(v.from)} → <span className="text-fg">{show(v.to)}</span></li>)}
                  </ul>
                )}
              </li>
            ))}
          </ul>
        )}
    </Card>
  );
}

async function history(key: "engine_policy"): Promise<SettingsHistoryRow[] | null> {
  try { return await settingsHistory(key, 20); } catch { return null; }
}

/** The routing-flow dashboard (m28a / m31o slug 'routing-flow') filtered by segment, or the dashboards list. */
async function flowDashboardHref(segment: string): Promise<string> {
  try {
    const d = (await dashboardsList()).dashboards.find((x) => x.slug === "routing-flow");
    if (!d) return "/dashboards";
    const p = new URLSearchParams({ period: "90d", filters: JSON.stringify({ segment: [segment] }) });
    return `/dashboards/${d.id}?${p.toString()}`;
  } catch {
    return "/dashboards";
  }
}

/** The parameters non-holdout leads get differ from the Admin's (an AI change is live). */
function steeredDiffers(a: EngineParams, b: EngineParams): boolean {
  const pick = (p: EngineParams) => JSON.stringify([p.half_life_days, p.prior_weight, p.effort.lo, p.effort.hi, p.effort.weights, p.sla.floor]);
  return pick(a) !== pick(b);
}

function paramLines(p: EngineParams, s: EngineParams | null): { label: string; value: string; steered?: string }[] {
  const w = (x: EngineParams) => EFFORT_METRICS.map((k) => `${EFFORT_METRIC_LABEL[k].split(" ")[0]} ${x.effort.weights[k]}`).join(", ");
  const diff = (a: string, b: string | undefined) => (b !== undefined && a !== b ? b : undefined);
  const sl = s ?? p;
  return [
    { label: "Recency half-life", value: `${p.half_life_days} days`, steered: diff(`${p.half_life_days} days`, s ? `${sl.half_life_days} days` : undefined) },
    { label: "Prior strength", value: `${p.prior_weight} leads`, steered: diff(`${p.prior_weight} leads`, s ? `${sl.prior_weight} leads` : undefined) },
    { label: "Default enrolment rate", value: pct(p.default_p_enroll) },
    { label: "Sales-effort factor", value: p.effort.enabled ? `on · ${p.effort.lo}–${p.effort.hi} · min. sample ${p.effort.min_sample}` : "off", steered: diff(`${p.effort.lo}–${p.effort.hi}`, s ? `${sl.effort.lo}–${sl.effort.hi}` : undefined) },
    { label: "Effort weights", value: w(p), steered: diff(w(p), s ? w(sl) : undefined) },
    { label: "SLA-adherence factor", value: p.sla.enabled ? `on · floor ${p.sla.floor} · ceiling ${p.sla.ceiling} · step ${p.sla.step} per 10 points` : "off", steered: diff(`floor ${p.sla.floor}`, s ? `floor ${sl.sla.floor}` : undefined) },
    { label: "SLA weights", value: SLA_KEYS.map((k) => `${SLA_LABEL[k]} ${p.sla.weights[k]}`).join(", ") },
  ];
}

/** Segments list: stage per segment with its progress toward the next gate, partners, leads and active rules. */
export async function SegmentsPanel({ s }: { s: RoutingSegments }) {
  const p = s.params;
  const g = STAGE_GATES;
  const steered = steeredDiffers(s.params, s.steered_params);
  const policyHistory = await history("engine_policy");
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
      <Card className="min-w-0">
        <CardHeader
          title="Segments"
          description={`Course × level × mode, and a university segment once a partner has ${p.stages.exact_segment_min_leads} leads there. Stage A (highest commission) moves to B once every competing partner has ${g.stage_b_min_leads} leads at least ${g.stage_b_min_age_days} days old, and to C once ${g.stage_c_min_partners} partners have ${g.stage_c_min_matured} leads older than ${g.matured_days} days. Statistics refresh hourly${s.stats_at ? `; last ${relativeTime(s.stats_at)}` : ""}.`}
          action={<RefreshStatsButton />}
        />
        {s.segments.length === 0 ? (
          <EmptyState icon={Layers} title="No segments yet">A segment appears once a lead is routed to a partner in it, or once partners offer its programme.</EmptyState>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-left text-[13px]">
              <thead className="text-[11px] uppercase tracking-wider text-subtle">
                <tr className="border-b border-border">
                  <th scope="col" className="px-5 py-2.5 font-medium">Segment</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Stage</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Progress to the next stage</th>
                  <th scope="col" className="px-3 py-2.5 text-right font-medium" title="Active partners offering the programme / every partner with leads here">Partners</th>
                  <th scope="col" className="px-3 py-2.5 text-right font-medium">Leads (30 d)</th>
                  <th scope="col" className="px-3 py-2.5 text-right font-medium" title="Matured leads and their enrolment rate (the segment's prior)">Matured</th>
                  <th scope="col" className="px-5 py-2.5 text-right font-medium">Last routed</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {s.segments.map((seg) => (
                  <tr key={seg.segment} className="hover:bg-surface-hover/60">
                    <td className="px-5 py-2.5">
                      <Link href={`/routing?tab=segments&segment=${encodeURIComponent(seg.segment)}`} className="font-medium text-fg hover:underline">{segmentLabel(seg.segment)}</Link>
                      {seg.exact && <span className="ml-1.5 text-[11px] text-subtle" title={`Roll-up: ${segmentLabel(seg.rollup)}`}>university segment</span>}
                      {seg.rules_active > 0 && (
                        <Link href="/routing?tab=rules" className="ml-1.5 inline-flex align-middle" title="Active routing rules on this course, level or mode">
                          <Badge tone="brand" className="font-normal"><Scale className="size-3" /> Rules: {seg.rules_active}</Badge>
                        </Link>
                      )}
                    </td>
                    <td className="px-3 py-2.5"><StageBadge m={seg.mode} compact /></td>
                    <td className="px-3 py-2.5"><GateProgress b={seg.progress_b} c={seg.progress_c} stage={seg.mode.stage} /></td>
                    <td className="tabular px-3 py-2.5 text-right text-muted">{seg.competing} <span className="text-subtle">/ {seg.partners}</span></td>
                    <td className="tabular px-3 py-2.5 text-right">{seg.leads_30d}</td>
                    <td className="tabular px-3 py-2.5 text-right text-muted">{seg.matured}{seg.matured ? <span className="text-subtle"> · {pct(seg.prior)}</span> : null}</td>
                    <td className="tabular px-5 py-2.5 text-right text-muted" title={seg.last_routed_at ? formatDateTime(seg.last_routed_at) : undefined}>{seg.last_routed_at ? relativeTime(seg.last_routed_at) : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <div className="min-w-0 space-y-6">
        <Card className="min-w-0">
          <CardHeader title="How partners are scored" description="Stage A: highest commission, with 20% of leads to an under-tested partner. Stage B: × sales-effort × SLA-adherence. Stage C: × P(enrol) × (1 − refunds), the commission per lead. The gates are fixed by Addendum 3; these parameters are yours." />
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 px-5 pb-4 text-[12.5px]">
            <dt className="text-muted">Stage B gate</dt><dd className="text-right text-fg">{g.stage_b_min_leads} leads per partner, first lead {g.stage_b_min_age_days} days old</dd>
            <dt className="text-muted">Stage C gate</dt><dd className="text-right text-fg">{g.stage_c_min_partners} partners with {g.stage_c_min_matured} leads older than {g.matured_days} days</dd>
            <dt className="text-muted">Exploration lane</dt><dd className="text-right text-fg">{pct(g.exploration_share, 0)} while a partner has under {g.learn_leads} leads</dd>
            {paramLines(s.params, steered ? s.steered_params : null).map((l) => (
              <Fragment key={l.label}>
                <dt className="text-muted">{l.label}</dt>
                <dd className="text-right text-fg">{l.value}{l.steered && <span className="block text-[11px] text-info"><Sparkles className="mr-0.5 inline size-3" /> AI-steered now: {l.steered}</span>}</dd>
              </Fragment>
            ))}
          </dl>
          {steered && <p className="border-t border-border px-5 py-3 text-[12px] text-info">An AI change is live: non-holdout leads use the steered values above; holdout leads ({pct(s.policy.holdout_share ?? 0.1, 0)}) use yours.</p>}
          <div className="border-t border-border px-5 py-3">
            <p className="mb-1.5 text-[11px] uppercase tracking-wider text-subtle">Enrolment by stage reached (matured leads)</p>
            <ul className="space-y-1 text-[12.5px]">
              {s.stage_rates.map((r) => (
                <li key={r.stage} className="flex justify-between gap-3"><span className="text-muted">{STAGE_RATE_LABEL[r.stage]}</span>
                  <span className="tabular text-fg">{pct(r.rate)} <span className="text-subtle">· {r.enrolled}/{r.n}</span></span></li>
              ))}
              {s.stage_rates.length === 0 && <li className="text-muted">Computed at the first refresh.</li>}
            </ul>
          </div>
          <p className="border-t border-border px-5 py-3 text-[12px] text-muted">Change the parameters in <Link href="/routing?tab=settings" className="text-info hover:underline">Engine settings</Link>; steer a segment with a <Link href="/routing?tab=rules" className="text-info hover:underline">routing rule</Link>.</p>
        </Card>
        <Card className="min-w-0">
          <CardHeader title="AI holdout" description={`Policy version ${s.policy_version}. Every change is kept with its reason.`} />
          <div className="px-5 pb-4"><PolicyForm key={s.policy_version} policy={s.policy} version={s.policy_version} /></div>
        </Card>
        <HistoryCard rows={policyHistory} title="Policy history" description="Versions of the routing policy (holdout share and the AI's levers), newest first." />
      </div>
    </div>
  );
}

const sortPartners = (a: SegmentPartner, b: SegmentPartner) => {
  if (a.competing !== b.competing) return a.competing ? -1 : 1;
  if (a.tie_rank != null && b.tie_rank != null) return a.tie_rank - b.tie_rank;
  if (a.tie_rank != null) return -1;
  if (b.tie_rank != null) return 1;
  return (b.cpe ?? -1) - (a.cpe ?? -1) || a.partner_id - b.partner_id;
};

/** One segment: the engine's ranking of its partners with every factor, the flow by week, the latest decisions. */
export async function SegmentView({ d, policyVersion }: { d: SegmentDetail; policyVersion: number }) {
  const stage = d.stage;
  const prog = stageProgress(d.partners);
  const steered = d.variant === "ai" || steeredDiffers(d.params, d.steered_params);
  const showFactors = stage === "B" || stage === "C";
  const showP = stage === "C" || d.partners.some((x) => x.p_used != null);
  const partners = [...d.partners].sort(sortPartners);
  const names = Object.fromEntries(d.partners.map((x) => [x.partner_id, x.name]));
  const weeks = weeklyShares(d.flow_weekly ?? []);
  const weekPartners = [...new Set(weeks.flatMap((w) => w.shares.map((x) => x.partner_id)))].sort((a, b) => a - b);
  const flowTotal = d.flow_30d.reduce((a, f) => a + f.n, 0);
  const flowHref = await flowDashboardHref(d.rollup);
  const ai = steered ? <Badge tone="info" className="ml-1 font-normal normal-case tracking-normal"><Sparkles className="size-3" /> AI-steered</Badge> : null;
  return (
    <>
      <Link href="/routing?tab=segments" className="mb-3 inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> All segments</Link>
      <div className="mb-5 flex flex-wrap items-center gap-3">
        <h2 className="text-lg font-semibold tracking-tight text-fg">{segmentLabel(d.segment)}</h2>
        <StageBadge m={d.mode} />
        {d.exact && <span className="text-[12.5px] text-muted">university segment · roll-up <Link href={`/routing?tab=segments&segment=${encodeURIComponent(d.rollup)}`} className="text-info hover:underline">{segmentLabel(d.rollup)}</Link></span>}
        {d.eval_segment && d.eval_segment !== d.segment && <span className="text-[12.5px] text-muted" title="Fewer than 30 leads per partner here: the scores are evaluated in the roll-up">scored in {segmentLabel(d.eval_segment)}</span>}
      </div>
      <div className="space-y-6">
        <Card className="min-w-0">
          <CardHeader title="Partners in this segment" description={`${STAGE_HINT[stage]} ${prog.b.text}. ${prog.c.text}.`} action={<RefreshStatsButton />} />
          <div className="grid gap-3 px-5 pb-3 sm:grid-cols-2">
            <div><Bar share={prog.b.share} label={prog.b.text} /><span className="mt-1 block text-[11.5px] text-subtle">Stage B gate: leads {pct(prog.b.leads, 0)} · age {pct(prog.b.age, 0)}</span></div>
            <div><Bar share={prog.c.share} label={prog.c.text} /><span className="mt-1 block text-[11.5px] text-subtle">Stage C gate: matured {pct(prog.c.share, 0)}</span></div>
          </div>
          {partners.length === 0 ? (
            <EmptyState icon={Gauge} title="No partner offers this programme">Partners appear here once an active offer matches the segment.</EmptyState>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[860px] text-left text-[12.5px]">
                <thead className="text-[11px] uppercase tracking-wider text-subtle">
                  <tr className="border-b border-border">
                    <th scope="col" className="px-5 py-2.5 font-medium">Partner</th>
                    <th scope="col" className="px-3 py-2.5 text-right font-medium" title="Commission per enrolment, net of GST: median over the programmes with a rate">Commission</th>
                    {showP && <th scope="col" className="px-3 py-2.5 text-right font-medium" title="P(enrol) as used, and its source">P(enrol){ai}</th>}
                    {showFactors && <th scope="col" className="px-3 py-2.5 text-right font-medium" title="Sales-effort factor; hover a value for its six metrics">Effort{ai}</th>}
                    {showFactors && <th scope="col" className="px-3 py-2.5 text-right font-medium" title="SLA-adherence factor and the adherence behind it">SLA{ai}</th>}
                    <th scope="col" className="px-3 py-2.5 text-right font-medium" title={`Stage ${stage}: ${STAGE_LABEL[stage]}`}>Score ({STAGE_LABEL[stage].toLowerCase()})</th>
                    <th scope="col" className="px-3 py-2.5 text-right font-medium" title="Leads received here, the first of them, and matured leads (older than 60 days)">Received · first · matured</th>
                    <th scope="col" className="px-5 py-2.5 text-right font-medium">Refunds</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {partners.map((x) => (
                    <tr key={x.partner_id} className={cn(!x.competing && "text-muted")}>
                      <td className="px-5 py-2.5">
                        {x.tie_rank != null && <span className="mr-1.5 tabular text-[11px] text-subtle">#{x.tie_rank}</span>}
                        <Link href={`/partners/${x.partner_id}`} className="font-medium text-fg hover:underline">{x.name}</Link>
                        {!x.competing && <Badge className="ml-1.5 font-normal">{x.status === "active" ? "not competing" : x.status}</Badge>}
                        {x.under_tested && x.competing && <Badge tone="info" className="ml-1.5 font-normal">under-tested</Badge>}
                      </td>
                      <td className="tabular px-3 py-2.5 text-right"><CpeCell cpe={x.cpe} hasRate={x.has_rate} basis={x.cpe_basis} /></td>
                      {showP && <td className="tabular px-3 py-2.5 text-right">
                        <PCell pUsed={x.p_used} pHat={x.p_hat} source={x.p_source} />
                        {x.holdout && x.holdout.p_used != null && x.holdout.p_used !== x.p_used && <span className="block text-[11px] text-subtle">holdout {pct(x.holdout.p_used)}</span>}
                      </td>}
                      {showFactors && <td className="tabular px-3 py-2.5 text-right">
                        <EffortCell factor={x.effort_factor} raw={x.effort_raw} detail={x.effort_detail} hasActivity={x.has_activity} />
                        {x.holdout && x.holdout.effort_factor != null && x.holdout.effort_factor !== x.effort_factor && <span className="block text-[11px] text-subtle">holdout ×{x.holdout.effort_factor.toFixed(2)}</span>}
                      </td>}
                      {showFactors && <td className="tabular px-3 py-2.5 text-right">
                        <SlaCell factor={x.sla_factor} adherence={x.sla_adherence} raw={x.sla_raw} />
                        {x.holdout && x.holdout.sla_factor != null && x.holdout.sla_factor !== x.sla_factor && <span className="block text-[11px] text-subtle">holdout ×{x.holdout.sla_factor.toFixed(2)}</span>}
                      </td>}
                      <td className="tabular px-3 py-2.5 text-right">
                        {x.competing ? <ScoreCell score={x.score} stage={stage} hasRate={x.has_rate} refundRate={x.refund_rate} /> : <span className="text-subtle" title="Paused or onboarding partners are not scored">—</span>}
                        {x.holdout && x.holdout.score != null && x.holdout.score !== x.score && <span className="block text-[11px] text-subtle">holdout ₹{Math.round(x.holdout.score).toLocaleString("en-IN")}</span>}
                      </td>
                      <td className="tabular whitespace-nowrap px-3 py-2.5 text-right text-muted" title={x.first_lead_at ? `First lead ${formatDateTime(x.first_lead_at)}` : "No lead yet"}>
                        {x.n_received} · {x.first_lead_at ? relativeTime(x.first_lead_at) : "—"} · {x.n_matured_c}
                      </td>
                      <td className="tabular px-5 py-2.5 text-right text-muted">{pct(x.refund_rate)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="space-y-1 border-t border-border px-5 py-3 text-[12px] text-muted">
            <p>Segment-level ranking: lead-specific checks (criteria, caps, duplicate history, partners already tried) and the per-lead ML P are applied at decision time. Ties: score, then commission, SLA adherence, fewer leads this week, partner id.</p>
            {steered && <p className="text-info"><Sparkles className="mr-0.5 inline size-3" /> AI-steered: non-holdout leads use the AI&apos;s effort weights and bounds, SLA floor or P(enrol) parameters; the &ldquo;holdout&rdquo; sub-values are what holdout leads ({pct(d.holdout_share, 0)}) get with your settings.</p>}
            {d.not_offering.length > 0 && <p>Not offering this programme now: {d.not_offering.map((x) => `${x.name}${x.n_received ? ` (${x.n_received} leads here)` : ""}`).join(", ")}.</p>}
          </div>
        </Card>

        <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
          <div className="min-w-0 space-y-6">
            <Card className="min-w-0">
              <CardHeader
                title="Partner shares by week"
                description={flowTotal ? `Last 30 days: ${d.flow_30d.map((f) => `${f.n} ${decisionModeLabel({ mode: f.mode, stage: f.stage }).toLowerCase()}${f.holdout ? " (holdout)" : ""}`).join(", ")}.` : "No real leads routed in this segment in 30 days."}
                action={<Link href={flowHref} className="inline-flex items-center gap-1 text-[12.5px] text-info hover:underline"><TrendingUp className="size-3.5" /> Shares over time</Link>}
              />
              {weeks.length === 0 ? (
                <p className="px-5 py-4 text-[12.5px] text-muted">No partner allocations in the last 12 weeks.</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-[12.5px]">
                    <thead className="text-[11px] uppercase tracking-wider text-subtle">
                      <tr className="border-b border-border">
                        <th scope="col" className="px-5 py-2 font-medium">Week (IST)</th>
                        {weekPartners.map((pid) => <th key={pid} scope="col" className="px-3 py-2 text-right font-medium">{names[pid] ?? `#${pid}`}</th>)}
                        <th scope="col" className="px-5 py-2 text-right font-medium">Leads</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border">
                      {weeks.map((w) => (
                        <tr key={w.week}>
                          <td className="px-5 py-1.5 text-muted">{new Date(w.week).toLocaleDateString("en-IN", { day: "numeric", month: "short", timeZone: "Asia/Kolkata" })}</td>
                          {weekPartners.map((pid) => {
                            const x = w.shares.find((s) => s.partner_id === pid);
                            return <td key={pid} className="tabular px-3 py-1.5 text-right">{x ? <>{pct(x.share, 0)} <span className="text-subtle">({x.n})</span></> : <span className="text-subtle">—</span>}</td>;
                          })}
                          <td className="tabular px-5 py-1.5 text-right text-fg">{w.total}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </Card>
            <Card className="min-w-0">
              <CardHeader title="Latest decisions" description="The last 15 decisions in this segment; open one to see why." />
              {d.decisions.length === 0 ? (
                <EmptyState icon={Gauge} title="No decisions yet">Decisions in this segment appear here.</EmptyState>
              ) : (
                <ul className="divide-y divide-border text-[12.5px]">
                  {d.decisions.map((x) => (
                    <li key={x.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2">
                      <Link href={`/routing/decisions/${x.id}`} className="text-info hover:underline" title={formatDateTime(x.at)}>{relativeTime(x.at)}</Link>
                      <span className="font-medium text-fg">{x.partner_name ?? "—"}</span>
                      <span className="text-subtle">{decisionModeLabel(x)}{x.stage && (x.mode === "commission_first" || x.mode === "performance") ? "" : x.stage ? ` · Stage ${x.stage}` : ""}{x.selection_probability != null && x.selection_probability < 1 ? ` · chosen with probability ${pct(x.selection_probability, 0)}` : ""}</span>
                      {x.holdout && <Badge tone="info" className="font-normal">Holdout</Badge>}
                      {x.is_test && <FlaskConical className="size-3 text-subtle" aria-label="Test lead" />}
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          </div>
          <Card className="min-w-0">
            <CardHeader title="Segment policy" description={`Policy version ${policyVersion}. Read-only: Addendum 3 fixed the lane, the limits and the stage gates.`} />
            <div className="px-5 pb-4"><SegmentPolicySummary mode={d.mode} /></div>
          </Card>
        </div>
      </div>
    </>
  );
}
