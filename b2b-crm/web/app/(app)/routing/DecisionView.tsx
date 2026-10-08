import { ArrowRight, Ban, CircleCheck, CircleDashed, FlaskConical, Gauge, Handshake, MessageSquare, Megaphone, Scale, ShieldOff } from "lucide-react";
import { Badge } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { Notice } from "@/components/ui/Notice";
import { formatDateTime } from "@/lib/format";
import { inr } from "@/lib/programmes";
import {
  CONSENT_CHANNEL_LABEL, CONSENT_REQUEST_STATUS_LABEL, CONSENT_STATE_LABEL, cpeBasisText, decisionModeLabel, decisionResultLabel, HOLD_LABEL, LANE_LABEL,
  notPassedLabel, reasonLabel, segmentLabel, STAGE_HINT, STAGE_LABEL, type Candidate, type Decision, type PartnerConsent,
} from "@/lib/routing";
import {
  EFFORT_METRIC_LABEL, EFFORT_METRICS, factorText, P_SOURCE_LABEL, pct, scoringSummary, segmentRollup, STAGE_FORMULA, untilText,
  type CpeBasis, type EffortDetail, type EffortMetricKey, type PSource, type Stage,
} from "@/lib/segments";

/** "Why this partner" (Addendum 3, PART 4 Step 3): every decision stores the stage, the CPE with its basis, P(enrol) with its
 *  source, both factors and the score, so the live preview and a stored decision show exactly the same thing (C112). The cell
 *  helpers below are shared with the Segments tab, which shows the same numbers per segment. */

// ---------- shared cells ----------

/** Effort metrics that are shares (shown as %); the others are minutes or counts. */
const EFFORT_PCT: readonly EffortMetricKey[] = ["connect_rate", "followup", "stale_share"];
const metricValue = (v: number | null | undefined, k: EffortMetricKey) =>
  v == null || !Number.isFinite(v) ? "—" : EFFORT_PCT.includes(k) ? pct(v, 0) : String(Math.round(v * 10) / 10);

/** The six effort metrics behind a factor, one line each (a hover text). */
export function effortDetailText(detail: EffortDetail | null | undefined, hasActivity?: boolean | null): string {
  if (!detail) return hasActivity === false ? "Capped: no activity data was synced for this partner." : "No effort detail was logged for this decision.";
  const lines = EFFORT_METRICS.flatMap((k) => {
    const m = detail.metrics[k];
    if (!m) return [];
    return [`${EFFORT_METRIC_LABEL[k]}: ${metricValue(m.v, k)} (median ${metricValue(m.median, k)}, n ${m.n}${m.r != null ? `, ratio ${m.r.toFixed(2)}` : ""}, weight ${m.w}${m.basis !== "segment" ? `, ${m.basis.replace(/_/g, " ")}` : ""})`];
  });
  if (lines.length === 0) lines.push("No metric had enough observations.");
  if (detail.capped_no_activity || !detail.has_activity) lines.push("Capped: no activity data, so the factor cannot go above 1.");
  lines.push(`Basis: ${detail.basis.replace(/_/g, " ")} · minimum sample ${detail.min_sample} · since ${formatDateTime(detail.since)}`);
  return lines.join("\n");
}

/** Short chip for an exclusion cause (CONTRACT 1.2); the full sentence is the row's Result cell. */
export const CAUSE_CHIP: Record<string, string> = {
  caps: "At cap", paused: "Paused", criteria: "Criteria", rule: "Rule", duplicate_history: "Had the student", tried: "Tried this cycle",
};

/** The CPE with its basis: "₹20,000" over "middle tier · partner fee · median of 3 programmes"; "No rate" scores 0. */
export function CpeCell({ cpe, hasRate, basis }: { cpe: number | null | undefined; hasRate: boolean | null | undefined; basis?: CpeBasis | null }) {
  if (!hasRate || cpe == null) return <span className="text-warning" title="No confirmed commission rate: this partner scores 0 until a rate is confirmed">No rate</span>;
  const b = cpeBasisText(basis);
  return (
    <span className="inline-flex flex-col items-end leading-tight">
      <span className="text-fg">{inr(cpe)}</span>
      {b && <span className="text-[11px] text-subtle">{b}</span>}
    </span>
  );
}

/** P(enrol) as used, with where it came from (D29): the model (with its version), the segment P̂ or the prior. */
export function PCell({ pUsed, pHat, source, modelVersion }: { pUsed: number | null | undefined; pHat?: number | null; source: PSource | null | undefined; modelVersion?: string | null }) {
  if (pUsed == null) return <span className="text-subtle" title="P(enrol) is used from Stage C only">—</span>;
  const title = source === "model" ? `Model P; the segment P̂ is ${pct(pHat)}${modelVersion ? ` · model ${modelVersion}` : ""}` : source === "prior" ? "Too few matured leads here: the segment's prior" : "Recency-weighted enrolments in this segment";
  return (
    <span className="inline-flex flex-col items-end leading-tight" title={title}>
      <span className="text-fg">{pct(pUsed)}</span>
      <span className="text-[11px] text-subtle">{source ? P_SOURCE_LABEL[source] : "—"}{source === "model" && modelVersion ? <span className="font-mono"> {modelVersion}</span> : null}</span>
    </span>
  );
}

/** The sales-effort factor with its six metrics on hover; "capped" when the partner syncs no activity (D27). */
export function EffortCell({ factor, raw, detail, hasActivity }: { factor: number | null | undefined; raw?: number | null; detail?: EffortDetail | null; hasActivity?: boolean | null }) {
  if (factor == null) return <span className="text-subtle">—</span>;
  const capped = detail?.capped_no_activity || hasActivity === false;
  const rawDiffers = raw != null && Math.abs(raw - factor) > 0.004;
  return (
    <span className="inline-flex cursor-help flex-col items-end leading-tight underline decoration-dotted decoration-border underline-offset-2" title={effortDetailText(detail, hasActivity)}>
      <span className="text-fg">{factorText(factor)}</span>
      {capped ? <span className="text-[11px] text-warning">capped: no activity data</span>
        : rawDiffers ? <span className="text-[11px] text-subtle">raw {factorText(raw)}, not applied</span> : null}
    </span>
  );
}

/** The SLA-adherence factor with the adherence it came from (D27: a stepped factor from the floor to 1). */
export function SlaCell({ factor, adherence, total, raw }: { factor: number | null | undefined; adherence: number | null | undefined; total?: number | null; raw?: number | null }) {
  if (factor == null && adherence == null) return <span className="text-subtle">—</span>;
  const rawDiffers = raw != null && factor != null && Math.abs(raw - factor) > 0.004;
  return (
    <span className="inline-flex flex-col items-end leading-tight" title={total ? `${total} SLA checks in the window` : "No SLA checks in the window yet"}>
      <span className="text-fg">{factorText(factor)}</span>
      <span className="text-[11px] text-subtle">{adherence == null ? "no checks yet" : `${pct(adherence, 0)} adherence`}{rawDiffers ? ` · raw ${factorText(raw)}` : ""}</span>
    </span>
  );
}

/** The A3 score with the stage formula; Stage C appends the refund term when it bites (C61). */
export function ScoreCell({ score, stage, hasRate, refundRate }: { score: number | null | undefined; stage: Stage | null | undefined; hasRate: boolean | null | undefined; refundRate?: number | null }) {
  if (score == null) return <span className="text-subtle">—</span>;
  return (
    <span className="inline-flex flex-col items-end leading-tight" title={stage ? `Stage ${stage}: ${STAGE_FORMULA[stage]}` : undefined}>
      <span className={cn("font-medium", hasRate === false ? "text-warning" : "text-fg")}>{inr(score)}</span>
      {stage === "C" && refundRate != null && refundRate > 0 && <span className="text-[11px] text-subtle">× (1 − refunds {pct(refundRate, 0)})</span>}
      {hasRate === false && <span className="text-[11px] text-warning">no rate</span>}
    </span>
  );
}

/** "university segment" / "course roll-up" for the segment the scores were evaluated in (D25). */
export function evalSegmentText(evalSegment: string | null | undefined, segmentExact?: string | null): string | null {
  if (!evalSegment) return null;
  const parts = evalSegment.split("|");
  if (parts.length >= 4) return `${segmentLabel(evalSegment)} (university segment)`;
  return `${segmentLabel(evalSegment)}${segmentExact && segmentRollup(segmentExact) === evalSegment ? " (roll-up: the university segment has too few leads)" : ""}`;
}

/** The consent state in one line, for the banners. */
function consentLine(c: PartnerConsent | null | undefined): string | null {
  if (!c) return null;
  if (c.given) return `${CONSENT_STATE_LABEL.given}${c.at ? ` on ${formatDateTime(c.at)}` : ""}${c.version ? ` (${c.version})` : ""}`;
  if (c.refused) return `${CONSENT_STATE_LABEL[c.last_state === "withdrawn" ? "withdrawn" : "refused"]}${c.refused_at ? ` on ${formatDateTime(c.refused_at)}` : ""}`;
  if (c.open_request) {
    const r = c.open_request;
    const ends = untilText(r.expires_at);
    return `${CONSENT_REQUEST_STATUS_LABEL[r.status] ?? r.status} via ${CONSENT_CHANNEL_LABEL[r.channel] ?? r.channel}${r.programme ? ` for ${r.programme}` : ""}${ends ? ` · ${ends}` : r.status === "queued" ? " · waits for the hourly budget" : ""}`;
  }
  if (c.expired_request) return `${CONSENT_STATE_LABEL.expired}${c.expired_request.expires_at ? ` on ${formatDateTime(c.expired_request.expires_at)}` : ""}`;
  if (c.stamp_uncovered) return CONSENT_STATE_LABEL.stamp_uncovered ?? "stamp uncovered";
  return CONSENT_STATE_LABEL.none ?? "none";
}

function Chip({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <span className="inline-flex items-center gap-1 rounded-md border border-border bg-surface-2 px-2 py-0.5 text-[12px]">
      <span className="text-subtle">{label}</span> <span className="text-fg">{value || "any"}</span>
    </span>
  );
}

const INTEREST_OUTCOME: Record<string, { label: string; tone: "success" | "neutral" | "warning" }> = {
  routed: { label: "routed", tone: "success" }, offered: { label: "offered", tone: "neutral" }, no_offer: { label: "no partner offers it", tone: "warning" },
};

type Kind = "partner" | "in_house" | "not_passed" | "none" | "consent_requested" | "consent_pending" | "consent_request" | "with_partner" | "reenquired";

const TONE: Record<Kind, { box: string; text: string; icon: React.ReactNode }> = {
  partner: { box: "border-success/25 bg-success-bg", text: "text-success", icon: <CircleCheck className="size-5 text-success" /> },
  in_house: { box: "border-warning/25 bg-warning-bg", text: "text-warning", icon: <Ban className="size-5 text-warning" /> },
  not_passed: { box: "border-danger/25 bg-danger-bg", text: "text-danger", icon: <ShieldOff className="size-5 text-danger" /> },
  none: { box: "border-border bg-surface-2", text: "text-fg", icon: <FlaskConical className="size-5 text-muted" /> },
  consent_requested: { box: "border-info/25 bg-info-bg", text: "text-info", icon: <MessageSquare className="size-5 text-info" /> },
  consent_pending: { box: "border-info/25 bg-info-bg", text: "text-info", icon: <MessageSquare className="size-5 text-info" /> },
  consent_request: { box: "border-info/25 bg-info-bg", text: "text-info", icon: <MessageSquare className="size-5 text-info" /> },
  with_partner: { box: "border-info/25 bg-info-bg", text: "text-info", icon: <Handshake className="size-5 text-info" /> },
  reenquired: { box: "border-info/25 bg-info-bg", text: "text-info", icon: <Handshake className="size-5 text-info" /> },
};

/** "Why this partner": the outcome, the lead's interests, every candidate with its numbers, exclusions and rules. */
export function DecisionView({ d }: { d: Decision }) {
  const kind: Kind = d.outcome === "with_partner" ? "with_partner" : d.outcome === "re-enquired" ? "reenquired" : d.destination;
  const toPartner = kind === "partner";
  const tone = TONE[kind] ?? TONE.in_house;
  const missing = d.class?.missing ?? d.readiness.not_qualified ?? [];
  /** C128: legacy M24 Thompson decisions keep their Won column; A3 decisions sort by score (tie_rank). */
  const legacyThompson = !d.stage && d.scoring_mode === "performance";
  const legacyScored = !d.stage && d.candidates.some((c) => c.p_hat !== undefined);
  const stage = d.stage ?? null;
  const showFactors = stage === "B" || stage === "C";
  const showP = stage === "C" || legacyScored || d.candidates.some((c) => c.p_used != null);
  const showChance = d.candidates.some((c) => c.propensity != null);
  const summary = toPartner ? scoringSummary(d) : null;
  const interestsTried = d.interests ?? [];
  const interestNote = d.interest_rank != null && interestsTried.length > 1 ? `routed on interest ${d.interest_rank} of ${interestsTried.length}` : null;
  const evalText = toPartner ? evalSegmentText(d.eval_segment, d.segment_exact ?? d.interest.segment_exact) : null;
  const verb = d.committed ? "Goes to" : "Would go to";

  const rows = [...d.candidates].sort((a, b) => {
    if (a.eligible !== b.eligible) return a.eligible ? -1 : 1;
    if (legacyThompson) return (b.ncpl ?? -1) - (a.ncpl ?? -1);
    if (stage) {
      if (a.tie_rank != null && b.tie_rank != null) return a.tie_rank - b.tie_rank;
      return (b.score ?? -1) - (a.score ?? -1);
    }
    return (b.cpe ?? -1) - (a.cpe ?? -1);
  });
  /** Excluded partners not listed among the candidates (legacy rows): shown after the table. */
  const extraExcluded = d.excluded.filter((x) => !d.candidates.some((c) => c.partner_id === Number(x.partner_id)));
  const programmes = (c: Candidate) => c.offers_count ?? c.offers ?? c.programmes?.length ?? 0;
  const consent = consentLine(d.consent);
  const consentMatters = kind.startsWith("consent") || d.reason === "no_partner_consent" || d.reason === "consent_no_answer" || d.cause === "no_partner_consent";

  let title: React.ReactNode;
  let sub: React.ReactNode;
  switch (kind) {
    case "partner":
      title = <>{verb} {d.partner_name}</>;
      sub = <>{stage && (d.mode === "commission_first" || d.mode === "performance") ? `Stage ${stage}: ${STAGE_LABEL[stage]}` : <>{decisionModeLabel(d)}{stage && <> (Stage {stage})</>}</>}
        {d.cpe != null && d.has_rate !== false ? <> · commission {inr(d.cpe)} net of GST</> : <> · no confirmed commission rate</>}
        {stage && stage !== "A" && d.score != null && <> · score {inr(d.score)}</>}
        {d.selection_probability < 1 && <> · chosen with probability {pct(d.selection_probability, 0)}</>}
        {interestNote && <> · {interestNote}</>}</>;
      break;
    case "with_partner":
      title = <>Already with {d.partner_name ?? "a partner"}: nothing new is decided</>;
      sub = <>An open partner allocation holds this lead (R3){d.reference && <>, {d.reference}</>}. A new enquiry is recorded for the partner, not re-routed.</>;
      break;
    case "reenquired":
      title = <>Re-enquired while held by B2C: nothing new is decided</>;
      sub = <>{d.hold ? HOLD_LABEL[d.hold.kind] ?? d.hold.kind : "Held by B2C"}{d.hold?.reason && <> ({reasonLabel(d.hold.reason).toLowerCase()})</>}. The enquiry is recorded for the B2C counsellor (R2 / R4); B2B sends nothing to partners.</>;
      break;
    case "not_passed":
      title = <>Not passed to any CRM</>;
      sub = <>{notPassedLabel(d.reason, d.class?.detail)}. It stays in the master database; no CRM works it. Pass it from the lead if this is wrong.</>;
      break;
    case "none":
      title = d.reason === "test_lead" ? <>Test lead: nothing is routed</> : d.reason === "no_sandbox_partner" ? <>No partner has a sandbox endpoint</> : <>Nothing is routed</>;
      sub = d.reason === "test_lead"
        ? <>Test leads never reach a real partner or B2C (R1). From the lead you can route it to a partner sandbox or send a test hand-off to B2C.</>
        : d.reason === "no_sandbox_partner" ? <>Give a partner a test endpoint (Partners › Connection) to try the sandbox.</> : <>{reasonLabel(d.reason, d.cause)}</>;
      break;
    case "consent_requested": {
      const r = d.consent_request;
      title = <>Consent requested from the student</>;
      sub = r && (r.created || r.existing)
        ? <>{r.existing ? "An open request already waits" : "A one-tap request goes out"} via {r.channel ? CONSENT_CHANNEL_LABEL[r.channel] ?? r.channel : "the B2C number"}
            {r.programme && <> for {r.programme}</>}{r.status && <> · {CONSENT_REQUEST_STATUS_LABEL[r.status] ?? r.status}</>}
            {r.expires_at ? <> · {untilText(r.expires_at) ?? `until ${formatDateTime(r.expires_at)}`}</> : r.status === "queued" ? <> · waits for the hourly budget</> : null}. The lead is routed once the student answers YES; no answer in 48 h sends it to B2C nurture.</>
        : <>The request could not be created{r?.why && <>: {r.why}</>}.</>;
      break;
    }
    case "consent_pending":
      title = <>Waiting for the student&apos;s partner-sharing answer</>;
      sub = <>{consent ?? "A consent request is open"}. Nothing is routed until the student answers; no answer in 48 h sends the lead to B2C nurture.</>;
      break;
    case "consent_request":
      title = <>Would ask the student for partner-sharing consent first</>;
      sub = <>No partner-sharing consent is recorded (R8). Routing this lead sends a one-tap request from Witty&apos;s or the B2C number and waits up to 48 h; partners see the lead only after a YES.</>;
      break;
    default:
      title = <>{verb} Eduwit&apos;s {LANE_LABEL[d.b2c_lane ?? "sales"] ?? "B2C CRM"}</>;
      sub = <>{reasonLabel(d.reason, d.cause)}{d.paid && <> · {d.paid}</>}
        {d.reason === "not_qualified" && missing.length > 0 && <> · missing: {missing.join(", ")}</>}
        {d.mode === "manual" && <> · by hand</>}</>;
  }

  return (
    <div className="space-y-5">
      <div className={cn("flex flex-wrap items-center gap-3 rounded-[var(--radius-card)] border px-4 py-3", tone.box)}>
        {tone.icon}
        <div className="min-w-0 flex-1">
          <p className={cn("text-[14px] font-semibold", tone.text)}>
            {title}
            {d.reference && <span className="ml-2 font-mono text-[12px] font-normal">{d.reference}</span>}
          </p>
          <p className="text-[12.5px] text-muted">{sub}</p>
          {toPartner && stage && <p className="mt-1 text-[12px] text-subtle">{STAGE_HINT[stage]}</p>}
        </div>
        <div className="flex flex-wrap gap-1.5">
          {d.is_test && <Badge tone="brand"><FlaskConical className="size-3" /> Test lead: partner sandboxes only</Badge>}
          {stage && toPartner && <Badge tone="info" className="font-normal">Stage {stage}</Badge>}
          {d.paid && d.reason !== "paid_campaign" && <Badge tone="info"><Megaphone className="size-3" /> Paid: {d.paid}</Badge>}
          {d.holdout && toPartner && <Badge tone="info" className="font-normal">Holdout{d.holdout_share != null ? ` (${pct(d.holdout_share, 0)})` : ""}</Badge>}
          {d.model_version && toPartner && <span title={d.feature_hash ? `feature snapshot ${d.feature_hash}` : undefined}><Badge className="font-mono font-normal">model {d.model_version}</Badge></span>}
          {d.committed ? <Badge tone="success">{kind === "consent_requested" ? "Request sent" : "Routed"}</Badge> : <Badge>Simulation: nothing was sent</Badge>}
          {d.already_routed && !d.committed && kind !== "with_partner" && <Badge tone="warning">Already routed</Badge>}
        </div>
      </div>

      {(d.bar || (d.hold?.open && kind !== "partner" && kind !== "reenquired") || (consent && consentMatters)) && (
        <div className="space-y-2">
          {d.bar && (
            <Notice tone="error">
              <span className="font-medium">Partner-barred</span> since {formatDateTime(d.bar.barred_at)} ({d.bar.reason === "duplicate" ? "a partner already had this student" : "a partner marked it lost and the 7-day grace ended"}):
              this lead can never be sent to partners; B2C works it.
              {d.bar.providers.length > 0 && <> Already with: {d.bar.providers.map((p) => `${p.partner_name ?? `partner #${p.partner_id ?? "?"}`}${p.first_had_at ? ` since ${formatDateTime(p.first_had_at)}` : " (date not given)"}`).join(", ")}.</>}
            </Notice>
          )}
          {d.hold?.open && kind !== "partner" && kind !== "reenquired" && (
            <Notice tone="warning">{HOLD_LABEL[d.hold.kind] ?? d.hold.kind}{d.hold.reason && <> · {reasonLabel(d.hold.reason)}</>}{d.hold.lane && <> · {LANE_LABEL[d.hold.lane]}</>}. A held lead reaches partners only when the Admin or the B2C CRM sends it (R4).</Notice>
          )}
          {consent && consentMatters && <Notice tone="info">{consent}.</Notice>}
        </div>
      )}

      <div>
        <h4 className="mb-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle">Interest</h4>
        <div className="flex flex-wrap gap-1.5">
          <Chip label="Course" value={d.interest.course_text ?? d.interest.course_key?.toUpperCase()} />
          <Chip label="Specialization" value={d.interest.specialization} />
          <Chip label="Level" value={d.interest.level} />
          <Chip label="Mode" value={d.interest.mode} />
          <Chip label="University" value={d.interest.university_id ? (d.interest.university_text ?? `#${d.interest.university_id}`) : null} />
          <Chip label="Segment" value={segmentLabel(d.interest.segment_exact ?? d.interest.segment)} />
          {evalText && <Chip label="Scored in" value={evalText} />}
        </div>
        {interestsTried.length > 1 && (
          <ol className="mt-2 space-y-0.5 text-[12.5px]">
            {interestsTried.map((i) => {
              const o = INTEREST_OUTCOME[i.outcome] ?? { label: i.outcome, tone: "neutral" as const };
              return (
                <li key={i.rank} className="flex flex-wrap items-center gap-2">
                  <span className="text-subtle">{i.rank}.</span>
                  <span className={cn(i.rank === d.interest_rank ? "font-medium text-fg" : "text-muted")}>{i.course_text ?? i.course_key?.toUpperCase() ?? "—"}</span>
                  <span className="text-subtle">{segmentLabel(i.segment)}</span>
                  <Badge tone={o.tone} className="font-normal">{o.label}</Badge>
                </li>
              );
            })}
          </ol>
        )}
        {!d.readiness.ready && d.readiness.missing.length > 0 && (
          <p className="mt-2 text-[12.5px] text-warning">Not ready for automatic routing: {d.readiness.missing.join(", ")}.</p>
        )}
      </div>

      {rows.length > 0 && (
        <div>
          <h4 className="mb-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle">Candidates{stage && <span className="ml-1 normal-case tracking-normal text-subtle">· Stage {stage}: {STAGE_FORMULA[stage]}; highest score wins</span>}</h4>
          <div className="overflow-x-auto rounded-lg border border-border">
            <table className="w-full min-w-[760px] text-left text-[12.5px]">
              <thead className="bg-surface-2 text-[11px] uppercase tracking-wider text-subtle">
                <tr>
                  <th scope="col" className="px-3 py-2 font-medium">Partner</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">Programmes</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium" title="Commission per enrolment, net of GST, with how it was built">Commission</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium">Today / cap</th>
                  <th scope="col" className="px-3 py-2 text-right font-medium" title="Leads this partner received in the evaluation segment; under-tested below 30">Leads</th>
                  {showP && <th scope="col" className="px-3 py-2 text-right font-medium" title="Chance this partner enrols the lead, and where the estimate comes from">P(enrol)</th>}
                  {showFactors && <th scope="col" className="px-3 py-2 text-right font-medium" title="Sales-effort factor (0.85–1.15) from the six activity metrics; hover a value for them">Effort</th>}
                  {showFactors && <th scope="col" className="px-3 py-2 text-right font-medium" title="SLA-adherence factor (0.80–1.00), stepped from the adherence share">SLA</th>}
                  {stage && <th scope="col" className="px-3 py-2 text-right font-medium" title={`Stage ${stage}: ${STAGE_FORMULA[stage]}`}>Score</th>}
                  {legacyScored && <th scope="col" className="px-3 py-2 text-right font-medium" title="Legacy: expected net commission per lead">NCPL</th>}
                  {showChance && <th scope="col" className="px-3 py-2 text-right font-medium" title="Chance of being chosen: 100% for the top score, or 80% / 20% when the exploration lane applied">Chance</th>}
                  {legacyThompson && <th scope="col" className="px-3 py-2 text-right font-medium" title="Share of the seeded draws this partner won (legacy)">Won</th>}
                  <th scope="col" className="px-3 py-2 font-medium">Result</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {rows.map((c) => {
                  const won = toPartner && c.partner_id === d.partner_id;
                  const legacyWhy = !c.eligible && !c.why ? d.excluded.find((x) => Number(x.partner_id) === c.partner_id)?.why : undefined;
                  const result = decisionResultLabel(d, { ...c, why: c.why ?? legacyWhy ?? null });
                  const received = c.n_received ?? c.segment_leads;
                  return (
                    <tr key={c.partner_id} className={cn(won && "bg-success-bg/60", !c.eligible && "text-muted")}>
                      <td className="px-3 py-2 font-medium text-fg">
                        {won && <ArrowRight className="mr-1 inline size-3.5 text-success" />}{c.name}
                        {c.status && c.status !== "active" && <Badge className="ml-1.5 font-normal">{c.status}</Badge>}
                        {c.tie_rank != null && c.eligible && <span className="ml-1.5 text-[11px] font-normal text-subtle">#{c.tie_rank}</span>}
                      </td>
                      <td className="tabular px-3 py-2 text-right text-muted">{programmes(c)}</td>
                      <td className="tabular px-3 py-2 text-right"><CpeCell cpe={c.cpe} hasRate={c.has_rate} basis={c.cpe_basis} /></td>
                      <td className="tabular px-3 py-2 text-right text-muted">{c.leads_today} / {c.daily_cap ?? "∞"}</td>
                      <td className="tabular px-3 py-2 text-right text-muted">
                        {received ?? "—"}
                        {c.under_tested && <span className="block text-[11px] text-info">under-tested</span>}
                        {c.stats_rollup && <span className="text-subtle" title="From the course roll-up (fewer than 30 leads in this segment)">*</span>}
                      </td>
                      {showP && <td className="tabular px-3 py-2 text-right">
                        {stage ? <PCell pUsed={c.p_used} pHat={c.p_hat} source={c.p_source} modelVersion={d.model_version} />
                          : c.p_hat !== undefined ? <>{pct(c.p_hat)}{c.stats_rollup && <span className="text-subtle">*</span>}</> : "—"}</td>}
                      {showFactors && <td className="tabular px-3 py-2 text-right"><EffortCell factor={c.effort_factor} raw={c.effort_raw} detail={c.effort_detail} hasActivity={c.has_activity} /></td>}
                      {showFactors && <td className="tabular px-3 py-2 text-right"><SlaCell factor={c.sla_factor} adherence={c.sla_adherence} total={c.sla_total} raw={c.sla_raw} /></td>}
                      {stage && <td className="tabular px-3 py-2 text-right">{c.eligible ? <ScoreCell score={c.score} stage={stage} hasRate={c.has_rate} refundRate={c.refund_rate} /> : <span className="text-subtle">—</span>}</td>}
                      {legacyScored && <td className="tabular px-3 py-2 text-right text-fg">{c.p_hat !== undefined && c.ncpl != null ? inr(c.ncpl) : "—"}
                        {c.weight !== undefined && c.weight !== 1 && <span className="ml-1 text-[11px] text-info">×{c.weight}</span>}</td>}
                      {showChance && <td className="tabular px-3 py-2 text-right text-muted">{c.eligible && c.propensity != null ? pct(c.propensity, 0) : "—"}</td>}
                      {legacyThompson && <td className="tabular px-3 py-2 text-right text-muted">{c.win_share !== undefined ? pct(c.win_share, 0) : "—"}</td>}
                      <td className="px-3 py-2 text-muted">
                        {won ? <span className="font-medium text-success">Chosen</span> : (
                          <span className="inline-flex flex-wrap items-center gap-1.5">
                            {!c.eligible && c.cause && <Badge tone="warning" className="font-normal">{CAUSE_CHIP[c.cause] ?? c.cause.replace(/_/g, " ")}</Badge>}
                            <span>{result}</span>
                          </span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          {d.candidates.some((c) => c.stats_rollup) && <p className="mt-1 text-[11.5px] text-subtle">* from the course roll-up</p>}
        </div>
      )}

      {(extraExcluded.length > 0 || (rows.length === 0 && d.excluded.length > 0)) && (
        <div>
          <h4 className="mb-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle">Excluded partners</h4>
          <ul className="space-y-1 text-[12.5px]">
            {(rows.length === 0 ? d.excluded : extraExcluded).map((x) => (
              <li key={String(x.partner_id)} className="flex flex-wrap items-center gap-2">
                <span className="font-medium text-fg">{x.name}</span>
                {x.cause && <Badge tone="warning" className="font-normal">{CAUSE_CHIP[x.cause] ?? x.cause.replace(/_/g, " ")}</Badge>}
                <span className="text-muted">{x.why}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {d.rules.length > 0 && (
        <div>
          <h4 className="mb-1.5 text-[11px] font-medium uppercase tracking-wider text-subtle">Rules applied</h4>
          <ul className="space-y-1 text-[12.5px]">
            {d.rules.map((r) => <li key={r.id} className="flex items-center gap-2"><Scale className="size-3.5 text-subtle" /> <span className="text-fg">{r.name}</span> <span className="text-subtle">· {r.effect}</span></li>)}
          </ul>
        </div>
      )}

      {(summary || d.why) && (
        <p className="flex flex-wrap items-center gap-1.5 text-[12px] text-subtle">
          <Gauge className="size-3.5" /> {summary}
          {d.why && <> · {d.why}</>}
          {d.seed != null && <> · seed <span className="font-mono">{Number(d.seed).toFixed(6)}</span>{d.seed_source === "forced" && " (forced)"}</>}
          {d.policy_version != null && <> · policy v{d.policy_version}</>}
          {d.settings_version != null && <> · engine settings v{d.settings_version}</>}
          {d.params_variant === "ai" && <> · AI-steered parameters</>}
          {d.shadow && Object.keys(d.shadow).length > 0 && (
            <span className="cursor-help underline decoration-dotted underline-offset-2" title={Object.entries(d.shadow).map(([v, ps]) => `${v}: ${Object.entries(ps).map(([pid, p]) => `${d.candidates.find((c) => String(c.partner_id) === pid)?.name ?? `#${pid}`} ${pct(p)}`).join(", ")}`).join("\n")}>
              · {Object.keys(d.shadow).length} shadow model{Object.keys(d.shadow).length === 1 ? "" : "s"}
            </span>
          )}
        </p>
      )}

      {toPartner && d.draw !== null && d.draw !== undefined && (
        <p className="flex items-center gap-1.5 text-[12px] text-subtle">
          <CircleDashed className="size-3.5" /> Exploration draw {d.draw.toFixed(3)} against a {Math.round((d.exploration_share || 0.2) * 100)}% lane
          {d.mode === "exploration" ? ": the lead went to an under-tested partner so its results can be learned." : ": the highest score kept the lead."}
        </p>
      )}
    </div>
  );
}
