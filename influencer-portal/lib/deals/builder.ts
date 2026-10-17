// Pure helpers for the compensation builder: option lists (also used as message keys), stable ids for new items,
// factories with valid defaults, and validation messages.
import type { z } from "zod";
import {
  compConfig,
  type AdditionalFee,
  type BonusRule,
  type CommissionRule,
  type CompConfig,
  type FixedComponent,
  type FloorRule,
  type Milestone,
  type PenaltyRule,
  type Trigger,
  type TriggerType,
} from "@/lib/compensation/schema";

export const SCOPE_TYPES = ["all", "programmes", "universities", "levels", "links", "deliverables"] as const;
export const SLAB_PERIODS = ["deal", "month", "campaign"] as const;
export const SLAB_MODES = ["marginal", "retroactive"] as const;
export const RECOUP_MODES = ["none", "full", "partial"] as const;
export const BONUS_WINDOWS = ["deal", "month", "campaign", "dates"] as const;
export const BONUS_AMOUNTS = ["fixed", "pct_of_fixed", "pct_of_commission"] as const;
export const PENALTY_TYPES = ["late_delivery", "missed_deliverable", "disclosure", "breach_clawback"] as const;
export const SECTIONS = [
  "fixed",
  "commission",
  "floors",
  "recoupment",
  "bonuses",
  "penalties",
  "fees",
  "non_cash",
] as const;

/** Validation codes raised by compConfig (and inf.comp_config_errors) that have their own message. */
export const VALIDATION_CODES = [
  "milestones_not_100",
  "milestones_not_total",
  "milestones_mixed",
  "milestones_required",
  "retainer_required",
  "tiers_start_at_1",
  "tiers_ascending",
  "tier_amount",
  "tier_pct",
  "dates",
  "two_decimals",
  "duplicate_id",
  "unknown_fixed",
  "unknown_rule",
  "recoupment_needs_commission",
] as const;
export type ValidationCode = (typeof VALIDATION_CODES)[number];

export type NonCash = CompConfig["non_cash"][number];

/** Every id in a config (milestones as "<component>.<milestone>"). */
export function allIds(c: CompConfig): Set<string> {
  return new Set([
    ...c.fixed.flatMap((f) => [f.id, ...f.milestones.map((m) => `${f.id}.${m.id}`)]),
    ...c.commission.map((r) => r.id),
    ...c.floors.map((r) => r.id),
    ...c.bonuses.map((r) => r.id),
    ...c.penalties.map((r) => r.id),
    ...c.fees.map((r) => r.id),
    ...c.non_cash.map((r) => r.id),
  ]);
}

/** The first free "<prefix><n>" (n ≥ 1). Ids never change once created, so ledger keys stay stable. */
export function nextId(prefix: string, taken: ReadonlySet<string>): string {
  for (let n = 1; ; n++) if (!taken.has(`${prefix}${String(n)}`)) return `${prefix}${String(n)}`;
}

export function defaultTrigger(type: TriggerType): Trigger {
  switch (type) {
    case "after_n_days_live":
      return { type, days: 7 };
    case "on_metric_threshold":
      return { type, metric: "views", threshold: 10_000 };
    case "on_specific_date":
      return { type, date: new Date().toISOString().slice(0, 10) };
    default:
      return { type };
  }
}

export function newMilestone(f: FixedComponent, label: string): Milestone {
  const amount = f.milestones[0]?.share.type === "amount";
  return {
    id: nextId("m", new Set(f.milestones.map((m) => m.id))),
    label,
    share: amount ? { type: "amount", amount_paise: 0 } : { type: "pct", pct: 0 },
    trigger: { type: "on_deliverable_live" },
    due_offset_days: 0,
    payment_terms_days: 7,
    on_cancel: { type: "forfeit" },
  };
}

/** One milestone paying 100% when the content is live, Net 7. */
export function defaultMilestones(label: string): Milestone[] {
  return [
    {
      id: "m1",
      label,
      share: { type: "pct", pct: 100 },
      trigger: { type: "on_deliverable_live" },
      due_offset_days: 0,
      payment_terms_days: 7,
      on_cancel: { type: "forfeit" },
    },
  ];
}

export function newFixed(c: CompConfig, label: string, milestoneLabel: string): FixedComponent {
  return {
    id: nextId("fee", allIds(c)),
    label,
    amount_paise: 10_000_00,
    basis: "lump_sum",
    units: 1,
    milestones: defaultMilestones(milestoneLabel),
  };
}

export function newRule(c: CompConfig, label: string): CommissionRule {
  return {
    id: nextId("rule", allIds(c)),
    label,
    scope: { type: "all" },
    basis: { type: "flat_per_enrollment", amount_paise: 1_000_00 },
    caps: {},
    confirmation: { type: "on_eduwit_commission_received" },
  };
}

export function newFloor(c: CompConfig, label: string): FloorRule {
  return { id: nextId("floor", allIds(c)), label, amount_paise: 5_000_00, period: "month", rules: [] };
}

export function newBonus(c: CompConfig, label: string): BonusRule {
  return {
    id: nextId("bonus", allIds(c)),
    label,
    conditions: { op: "and", items: [{ metric: "enrollments", comparator: "gte", value: 5 }] },
    window: { type: "deal" },
    amount: { type: "fixed", amount_paise: 2_000_00 },
    repeat: "once",
  };
}

export function newPenalty(c: CompConfig, type: PenaltyRule["type"], label: string): PenaltyRule {
  const id = nextId("pen", allIds(c));
  switch (type) {
    case "late_delivery":
      return { id, type, label, grace_days: 1, per_day: { type: "pct", pct: 1 } };
    case "missed_deliverable":
      return { id, type, label, action: { type: "forfeit_milestones" } };
    case "disclosure":
      return { id, type, label, amount_paise: 1_000_00 };
    case "breach_clawback":
      return { id, type, label, pct: 100 };
  }
}

export function newFee(c: CompConfig, label: string): AdditionalFee {
  return {
    id: nextId("extra", allIds(c)),
    kind: "usage_rights",
    label,
    amount_paise: 2_000_00,
    platforms: [],
    trigger: { type: "on_contract_signed" },
    due_offset_days: 0,
  };
}

export function newNonCash(c: CompConfig, label: string): NonCash {
  return { id: nextId("item", allIds(c)), label, value_paise: 0 };
}

export interface BuilderIssue {
  /** Section of the builder the issue belongs to (for highlighting). */
  section: (typeof SECTIONS)[number] | "general";
  /** A known validation code, or null for a field-level problem. */
  code: ValidationCode | null;
  /** The id or value after "code:" (duplicate_id:x), if any. */
  detail?: string;
  /** Field path for field-level problems, e.g. ["fixed", 0, "label"]. */
  path: PropertyKey[];
}

export function builderIssues(c: unknown): BuilderIssue[] {
  const r = compConfig.safeParse(c);
  if (r.success) return [];
  return dedupe(r.error.issues.map(toIssue));
}

function toIssue(i: z.core.$ZodIssue): BuilderIssue {
  const [code, detail] = i.message.split(":") as [string, string | undefined];
  const known = (VALIDATION_CODES as readonly string[]).includes(code) ? (code as ValidationCode) : null;
  const head = i.path[0];
  const section = (SECTIONS as readonly unknown[]).includes(head) ? (head as BuilderIssue["section"]) : "general";
  return { section, code: known, detail: known ? detail : undefined, path: i.path };
}

function dedupe(xs: BuilderIssue[]): BuilderIssue[] {
  const seen = new Set<string>();
  return xs.filter((x) => {
    const k = `${x.section}|${x.code ?? ""}|${x.detail ?? ""}|${x.code ? "" : x.path.join(".")}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}
