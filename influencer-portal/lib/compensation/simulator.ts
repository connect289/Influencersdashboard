// The earnings simulator (spec 6.2). Pure: it turns a scenario ("20 leads, 3 enrolments, 50k views, delivered two
// days late") into a synthetic event stream, runs the real engine over it, and adds the tax estimate and, for staff
// only, Eduwit's economics. Creators get `forCreator(result)`, which carries no Eduwit figures.
import { z } from "zod";
import { computeLedger, type EngineContext, type LedgerLine } from "./engine";
import { addDays, addMonths, istMidnight, type EngineEvent } from "./events";
import { mulDiv, netOfGst, sum, type Paise } from "./money";
import type { CompConfig, Trigger } from "./schema";
import { estimateTax, type TaxEstimate, type TdsSection } from "./tax";

const count = (max: number) => z.coerce.number().int().min(0).max(max);
const money = z.coerce.number().int().min(0).max(10_000_000_000_00);

export const scenario = z
  .object({
    leads: count(100_000).default(0),
    qualified_leads: count(100_000).default(0),
    applications: count(100_000).default(0),
    enrollments: count(10_000).default(0),
    cancellations: count(10_000).default(0),
    views: count(10_000_000_000).default(0),
    days_late: count(365).default(0),
    disclosure_issues: count(20).default(0),
    leaderboard_rank: z.coerce.number().int().min(1).max(10_000).optional(),
    months: z.coerce.number().int().min(1).max(24).default(1),
    /** Average programme fee per enrolment (for % of fee rules). */
    avg_fee_paise: money.optional(),
    /** Eduwit's average commission per enrolment, GST-inclusive (staff input or catalogue average). */
    avg_commission_gross_paise: money.optional(),
    commission_received: z.boolean().default(true),
    has_pan: z.boolean().default(true),
    gst_registered: z.boolean().default(false),
  })
  .superRefine((s, ctx) => {
    if (s.qualified_leads > s.leads) ctx.addIssue({ code: "custom", path: ["qualified_leads"], message: "gt_leads" });
    if (s.applications > s.leads) ctx.addIssue({ code: "custom", path: ["applications"], message: "gt_leads" });
    if (s.cancellations > s.enrollments)
      ctx.addIssue({ code: "custom", path: ["cancellations"], message: "gt_enrollments" });
  });
export type Scenario = z.infer<typeof scenario>;
export type ScenarioInput = z.input<typeof scenario>;

export const BREAKDOWN_KEYS = [
  "fixed",
  "commission",
  "bonus",
  "fees",
  "reimbursement",
  "floor",
  "recoupment",
  "clawback",
] as const;
export type BreakdownKey = (typeof BREAKDOWN_KEYS)[number];

export interface SimulationOptions {
  starts_on: string;
  context: EngineContext;
  sections: readonly TdsSection[];
  gst_rate_bps: number;
}

export interface SimulationResult {
  breakdown: { key: BreakdownKey; amount_paise: Paise }[];
  lines: LedgerLine[];
  /** Penalties the scenario would trigger (proposals; a person approves them), deducted in the estimate. */
  penalties_paise: Paise;
  gross_paise: Paise;
  tax: TaxEstimate;
  net_payout_paise: Paise;
  non_cash_paise: Paise;
  eduwit: {
    /** Eduwit's commission on the scenario's enrolments (after cancellations), net of GST. */
    revenue_paise: Paise;
    /** What the deal costs Eduwit (creator earnings and GST before TDS, less penalties; barter excluded). */
    cost_paise: Paise;
    cost_per_enrollment_paise: Paise | null;
    margin_paise: Paise;
    margin_bps: number | null;
  };
}
export type CreatorSimulation = Omit<SimulationResult, "eduwit">;

const DAY_MS = 86_400_000;
type DistributiveOmit<T, K extends PropertyKey> = T extends unknown ? Omit<T, K> : never;

/** Deliverable ids a config refers to (milestone and fee triggers, deliverable scopes); at least one. */
export function configDeliverables(c: CompConfig): string[] {
  const ids = new Set<string>();
  const fromTrigger = (t: Trigger) => {
    if ("deliverable" in t && t.deliverable) ids.add(t.deliverable);
  };
  for (const f of c.fixed) for (const m of f.milestones) fromTrigger(m.trigger);
  for (const fee of c.fees) fromTrigger(fee.trigger);
  for (const r of c.commission) if (r.scope.type === "deliverables") for (const d of r.scope.ids) ids.add(d);
  return ids.size ? [...ids].sort() : ["d1"];
}

/** IST instant: `day` days after a date, at `minute` minutes past 10:00. */
const istAt = (date: string, day: number, minute = 0) =>
  new Date(Date.parse(istMidnight(addDays(date, day))) + 10 * 3_600_000 + minute * 60_000).toISOString();

/** The synthetic event stream for a scenario. Units are spread evenly over the months; the deal ends after them. */
export function scenarioEvents(
  c: CompConfig,
  s: Scenario,
  startsOn: string,
): { events: EngineEvent[]; ends_on: string } {
  const endsOn = addDays(addMonths(startsOn, s.months), -1);
  const span = Math.max(Math.round((Date.parse(endsOn) - Date.parse(startsOn)) / DAY_MS) - 30, 1);
  const out: EngineEvent[] = [];
  let n = 0;
  const push = (e: DistributiveOmit<EngineEvent, "id">) => {
    out.push({ ...e, id: `sim-${String(++n).padStart(6, "0")}` });
  };
  const dayOf = (i: number, total: number) => 3 + Math.floor((i * span) / Math.max(total, 1));

  push({ type: "contract_signed", at: istAt(startsOn, 0) });
  push({ type: "brief_acknowledged", at: istAt(startsOn, 1) });
  const deliverables = configDeliverables(c);
  deliverables.forEach((d, i) => {
    push({ type: "concept_approved", at: istAt(startsOn, 5, i), deliverable: d });
    push({ type: "draft_approved", at: istAt(startsOn, 10, i), deliverable: d });
    const due = new Date(Date.parse(istAt(startsOn, 14)) + 8 * 3_600_000).toISOString(); // 18:00 IST on day 14
    push({ type: "deliverable_due", at: istAt(startsOn, 2, i), deliverable: d, due_at: due });
    push({ type: "deliverable_live", at: istAt(startsOn, 14 + s.days_late, i), deliverable: d });
    for (let k = 0; k < s.disclosure_issues; k++)
      push({ type: "disclosure_flag", at: istAt(startsOn, 15 + s.days_late, k), deliverable: d });
  });
  // Views: cumulative readings at the end of each month, split evenly across deliverables.
  for (let m = 1; m <= s.months; m++)
    deliverables.forEach((d, i) => {
      const share = Math.floor(s.views / deliverables.length) + (i < s.views % deliverables.length ? 1 : 0);
      push({
        type: "metric",
        at: istAt(addDays(addMonths(startsOn, m), -1), 0, 30 + i),
        deliverable: d,
        metric: "views",
        value: Math.floor((share * m) / s.months),
      });
    });
  for (let i = 0; i < s.leads; i++) {
    const day = dayOf(i, s.leads);
    push({
      type: "lead",
      at: istAt(startsOn, day, i % 600),
      lead: `L${String(i)}`,
      deliverable: deliverables[0],
      junk: false,
      duplicate: false,
    });
    if (i < s.qualified_leads)
      push({ type: "lead_qualified", at: istAt(startsOn, day + 1, i % 600), lead: `L${String(i)}` });
    if (i < s.applications)
      push({ type: "lead_applied", at: istAt(startsOn, day + 2, i % 600), lead: `L${String(i)}` });
  }
  for (let i = 0; i < s.enrollments; i++) {
    const day = dayOf(i, s.enrollments) + 3;
    const enrollment = `E${String(i)}`;
    push({
      type: "enrolled",
      at: istAt(startsOn, day, 600 + (i % 600)),
      lead: i < s.leads ? `L${String(i)}` : `X${String(i)}`,
      enrollment,
      deliverable: deliverables[0],
      fee_paise: s.avg_fee_paise,
      expected_commission_gross_paise: s.avg_commission_gross_paise,
    });
    const cancelled = i >= s.enrollments - s.cancellations;
    if (cancelled) push({ type: "enrollment_cancelled", at: istAt(startsOn, day + 5, 600 + (i % 600)), enrollment });
    else if (s.commission_received && s.avg_commission_gross_paise !== undefined)
      push({
        type: "commission_received",
        at: istAt(startsOn, day + 20, 600 + (i % 600)),
        enrollment,
        gross_paise: s.avg_commission_gross_paise,
        full: true,
      });
  }
  if (s.leaderboard_rank !== undefined) {
    for (let m = 0; m < s.months; m++)
      push({
        type: "leaderboard_rank",
        at: istAt(addDays(addMonths(startsOn, m + 1), -1), 0, 200),
        window: addMonths(startsOn, m).slice(0, 7),
        rank: s.leaderboard_rank,
      });
    for (const w of ["deal", "campaign"])
      push({ type: "leaderboard_rank", at: istAt(endsOn, 0, 201), window: w, rank: s.leaderboard_rank });
  }
  for (const f of c.fixed)
    for (const m of f.milestones)
      if (m.trigger.type === "manual_release")
        push({ type: "manual_release", at: istAt(endsOn, 0, 300), milestone: `${f.id}.${m.id}` });
  push({ type: "campaign_ended", at: istAt(endsOn, 0, 400) });
  push({ type: "deal_completed", at: istAt(endsOn, 0, 401) });
  return { events: out, ends_on: endsOn };
}

/** Every rule in scope: the simulator models leads and enrolments generically, not per programme or link. */
export function simulationConfig(c: CompConfig): CompConfig {
  return {
    ...c,
    commission: c.commission.map((r) => ({ ...r, scope: { type: "all" as const } })),
    // Manual-release fees fire like milestones in a simulation (released at the end).
    fees: c.fees.map((f) =>
      f.trigger.type === "manual_release" ? { ...f, trigger: { type: "on_campaign_end" as const } } : f,
    ),
  };
}

function bucket(l: LedgerLine): BreakdownKey {
  if (l.rule_id === "recoupment") return "recoupment";
  if (l.type === "clawback") return "clawback";
  if (l.type === "adjustment") return "floor";
  if (l.type === "milestone" || l.type === "fixed_fee") return "fixed";
  if (l.type === "usage_fee" || l.type === "exclusivity_fee") return "fees";
  if (l.type === "bonus") return "bonus";
  if (l.type === "reimbursement") return "reimbursement";
  return "commission";
}

export function simulate(config: CompConfig, input: Scenario, o: SimulationOptions): SimulationResult {
  const c = simulationConfig(config);
  const { events, ends_on } = scenarioEvents(c, input, o.starts_on);
  // Run far enough past the end for holds, timers and dated milestones to settle.
  const dated = c.fixed.flatMap((f) =>
    f.milestones.flatMap((m) => (m.trigger.type === "on_specific_date" ? [m.trigger.date] : [])),
  );
  const holds = c.commission.map((r) =>
    r.confirmation.type === "after_hold_days" ? (r.confirmation.days ?? o.context.hold_days) : 0,
  );
  const settle =
    [addDays(ends_on, 40 + Math.max(0, ...holds)), ...dated.map((d) => addDays(d, 1))].sort().at(-1) ?? ends_on;
  const result = computeLedger({
    deal: { id: "simulation", starts_on: o.starts_on, ends_on, campaign_ends_on: ends_on },
    versions: [{ id: "sim", effective_from: istMidnight(o.starts_on), config: c }],
    events,
    as_of: istMidnight(settle),
    context: o.context,
  });
  const breakdown = BREAKDOWN_KEYS.map((key) => ({
    key,
    amount_paise: sum(
      result.lines
        .filter((l) => bucket(l) === key)
        .map((l) => (l.direction === "credit" ? l.amount_paise : -l.amount_paise)),
    ),
  })).filter((b) => b.amount_paise !== 0);
  const tax = estimateTax({
    lines: result.lines,
    non_cash_paise: result.totals.non_cash,
    sections: o.sections,
    has_pan: input.has_pan,
    gst: { registered: input.gst_registered, rate_bps: o.gst_rate_bps },
  });
  const penalties = sum(result.proposals.map((p) => p.amount_paise));
  const enrolled = input.enrollments - input.cancellations;
  const revenue =
    input.avg_commission_gross_paise === undefined
      ? 0
      : netOfGst(input.avg_commission_gross_paise, o.context.eduwit_gst_bps) * enrolled;
  const cost = result.totals.net + tax.gst_paise - penalties;
  const margin = revenue - cost;
  return {
    breakdown,
    lines: result.lines,
    penalties_paise: penalties,
    gross_paise: result.totals.net,
    tax,
    net_payout_paise: tax.net_paise - penalties,
    non_cash_paise: result.totals.non_cash,
    eduwit: {
      revenue_paise: revenue,
      cost_paise: cost,
      cost_per_enrollment_paise: enrolled > 0 ? mulDiv(cost, 1, enrolled) : null,
      margin_paise: margin,
      margin_bps: revenue > 0 ? mulDiv(margin, 10_000, revenue) : null,
    },
  };
}

/** The creator's read-only view: their own earnings only, never Eduwit's margin or commission amounts (spec 6.2). */
export function forCreator(r: SimulationResult): CreatorSimulation {
  return {
    breakdown: r.breakdown,
    lines: r.lines,
    penalties_paise: r.penalties_paise,
    gross_paise: r.gross_paise,
    tax: r.tax,
    net_payout_paise: r.net_payout_paise,
    non_cash_paise: r.non_cash_paise,
  };
}
