// The compensation config of one deal version (spec 6.1, D-05). One validated document; every element carries a
// stable id so ledger entries can be keyed on (deal version, rule, subject, event) and amendments can carry rules over.
// Amounts are integer paise; percentages are numbers with up to two decimals (converted to basis points by the engine).
import { z } from "zod";

const id = z
  .string()
  .regex(/^[a-z0-9][a-z0-9_-]{0,39}$/, "id")
  .describe("Stable id: lower-case letters, digits, '-' or '_', up to 40 characters");
const paise = z.number().int().min(0).max(10_000_000_000_00);
const pct = z
  .number()
  .min(0)
  .max(100)
  .refine((v) => Math.abs(Math.round(v * 100) - v * 100) < 1e-9, "two_decimals");
const days = z.number().int().min(0).max(3650);
const isoDate = z.iso.date();

// ---------------------------------------------------------------------------------------------------------------
// Triggers (fixed-fee milestones and additional fees)
// ---------------------------------------------------------------------------------------------------------------
export const TRIGGER_TYPES = [
  "on_contract_signed",
  "on_brief_acknowledged",
  "on_concept_approved",
  "on_draft_approved",
  "on_deliverable_live",
  "after_n_days_live",
  "on_metric_threshold",
  "on_campaign_end",
  "on_specific_date",
  "manual_release",
] as const;
export type TriggerType = (typeof TRIGGER_TYPES)[number];
export const METRICS = ["views", "reach", "leads"] as const;

export const trigger = z.discriminatedUnion("type", [
  z.object({ type: z.literal("on_contract_signed") }),
  z.object({ type: z.literal("on_brief_acknowledged") }),
  z.object({ type: z.literal("on_concept_approved"), deliverable: id.optional() }),
  z.object({ type: z.literal("on_draft_approved"), deliverable: id.optional() }),
  z.object({ type: z.literal("on_deliverable_live"), deliverable: id.optional() }),
  z.object({
    type: z.literal("after_n_days_live"),
    days: z.number().int().min(1).max(365),
    deliverable: id.optional(),
  }),
  z.object({
    type: z.literal("on_metric_threshold"),
    metric: z.enum(METRICS),
    threshold: z.number().int().min(1).max(10_000_000_000),
    deliverable: id.optional(),
  }),
  z.object({ type: z.literal("on_campaign_end") }),
  z.object({ type: z.literal("on_specific_date"), date: isoDate }),
  z.object({ type: z.literal("manual_release") }),
]);
export type Trigger = z.infer<typeof trigger>;

// ---------------------------------------------------------------------------------------------------------------
// A. Fixed fees with milestone schedules
// ---------------------------------------------------------------------------------------------------------------
export const milestone = z.object({
  id,
  label: z.string().trim().min(1).max(80),
  share: z.discriminatedUnion("type", [
    z.object({ type: z.literal("pct"), pct }),
    z.object({ type: z.literal("amount"), amount_paise: paise }),
  ]),
  trigger,
  due_offset_days: days.default(0),
  payment_terms_days: days.default(0),
  /** What happens to this milestone if its deliverable is cancelled before it is reached. */
  on_cancel: z
    .discriminatedUnion("type", [
      z.object({ type: z.literal("forfeit") }),
      z.object({ type: z.literal("pay_pct"), pct }),
    ])
    .default({ type: "forfeit" }),
});
export type Milestone = z.infer<typeof milestone>;

export const FIXED_BASES = ["lump_sum", "per_deliverable", "per_unit", "retainer"] as const;

export const fixedComponent = z
  .object({
    id,
    label: z.string().trim().min(1).max(80),
    amount_paise: paise,
    basis: z.enum(FIXED_BASES),
    /** per_deliverable / per_unit: how many (the component's value is amount × units). */
    units: z.number().int().min(1).max(1000).default(1),
    unit_label: z.string().trim().max(40).optional(),
    /** retainer: number of periods, their length and when each is paid. */
    retainer: z
      .object({
        periods: z.number().int().min(1).max(120),
        every: z.enum(["week", "month"]),
        pay_on: z.enum(["period_start", "period_end"]),
        payment_terms_days: days.default(0),
      })
      .optional(),
    milestones: z.array(milestone).max(50).default([]),
  })
  .superRefine((c, ctx) => {
    if (c.basis === "retainer") {
      if (!c.retainer) ctx.addIssue({ code: "custom", path: ["retainer"], message: "retainer_required" });
      return;
    }
    if (c.milestones.length === 0) {
      ctx.addIssue({ code: "custom", path: ["milestones"], message: "milestones_required" });
      return;
    }
    const kinds = new Set(c.milestones.map((m) => m.share.type));
    if (kinds.size > 1) {
      ctx.addIssue({ code: "custom", path: ["milestones"], message: "milestones_mixed" });
      return;
    }
    const total = c.amount_paise * c.units;
    if (kinds.has("pct")) {
      const bps = c.milestones.reduce((s, m) => s + (m.share.type === "pct" ? Math.round(m.share.pct * 100) : 0), 0);
      if (bps !== 10_000) ctx.addIssue({ code: "custom", path: ["milestones"], message: "milestones_not_100" });
    } else {
      const amt = c.milestones.reduce((s, m) => s + (m.share.type === "amount" ? m.share.amount_paise : 0), 0);
      if (amt !== total) ctx.addIssue({ code: "custom", path: ["milestones"], message: "milestones_not_total" });
    }
  });
export type FixedComponent = z.infer<typeof fixedComponent>;

// ---------------------------------------------------------------------------------------------------------------
// B. Commission rules
// ---------------------------------------------------------------------------------------------------------------
export const scope = z.discriminatedUnion("type", [
  z.object({ type: z.literal("all") }),
  z.object({ type: z.literal("programmes"), ids: z.array(z.number().int().positive()).min(1).max(200) }),
  z.object({ type: z.literal("universities"), ids: z.array(z.number().int().positive()).min(1).max(100) }),
  z.object({ type: z.literal("levels"), levels: z.array(z.string().trim().min(1).max(20)).min(1).max(10) }),
  z.object({ type: z.literal("links"), codes: z.array(z.string().trim().min(2).max(40)).min(1).max(100) }),
  z.object({ type: z.literal("deliverables"), ids: z.array(id).min(1).max(100) }),
]);
export type Scope = z.infer<typeof scope>;

export const BASIS_TYPES = [
  "flat_per_enrollment",
  "pct_of_eduwit_commission",
  "pct_of_programme_fee",
  "flat_per_qualified_lead",
  "flat_per_lead",
  "flat_per_application",
] as const;
export type BasisType = (typeof BASIS_TYPES)[number];
/** Bases paid as a flat amount per unit (the rest are percentages). */
export const FLAT_BASES: readonly BasisType[] = [
  "flat_per_enrollment",
  "flat_per_qualified_lead",
  "flat_per_lead",
  "flat_per_application",
];

export const basis = z.discriminatedUnion("type", [
  z.object({ type: z.literal("flat_per_enrollment"), amount_paise: paise }),
  z.object({
    type: z.literal("pct_of_eduwit_commission"),
    pct,
    /** Eduwit's commission is GST-inclusive; pay on the gross amount or on the amount net of GST. */
    base: z.enum(["gross_incl_gst", "net_of_gst"]),
  }),
  z.object({ type: z.literal("pct_of_programme_fee"), pct }),
  z.object({ type: z.literal("flat_per_qualified_lead"), amount_paise: paise }),
  z.object({ type: z.literal("flat_per_lead"), amount_paise: paise }),
  z.object({ type: z.literal("flat_per_application"), amount_paise: paise }),
]);
export type Basis = z.infer<typeof basis>;

/** A tier starts at the `from`-th unit in the period. Its rate is an amount (flat bases) or a percentage. */
export const tier = z.object({
  from: z.number().int().min(1).max(1_000_000),
  amount_paise: paise.optional(),
  pct: pct.optional(),
});

export const slabs = z
  .object({
    period: z.enum(["deal", "month", "campaign"]),
    mode: z.enum(["marginal", "retroactive"]),
    tiers: z.array(tier).min(2).max(20),
  })
  .superRefine((s, ctx) => {
    if (s.tiers[0]?.from !== 1) ctx.addIssue({ code: "custom", path: ["tiers"], message: "tiers_start_at_1" });
    for (let i = 1; i < s.tiers.length; i++)
      if ((s.tiers[i]?.from ?? 0) <= (s.tiers[i - 1]?.from ?? 0))
        ctx.addIssue({ code: "custom", path: ["tiers", i, "from"], message: "tiers_ascending" });
  });

export const CONFIRMATIONS = ["immediate", "after_hold_days", "on_eduwit_commission_received"] as const;

export const commissionRule = z
  .object({
    id,
    label: z.string().trim().min(1).max(80),
    scope: scope.default({ type: "all" }),
    basis,
    slabs: slabs.optional(),
    caps: z
      .object({
        per_unit_paise: paise.optional(),
        per_month_paise: paise.optional(),
        lifetime_paise: paise.optional(),
      })
      .default({}),
    effective_from: isoDate.optional(),
    effective_to: isoDate.optional(),
    confirmation: z
      .discriminatedUnion("type", [
        z.object({ type: z.literal("immediate") }),
        z.object({ type: z.literal("after_hold_days"), days: days.optional() }),
        z.object({ type: z.literal("on_eduwit_commission_received") }),
      ])
      .default({ type: "on_eduwit_commission_received" }),
    /** Days after accrual in which a cancellation or refund claws the commission back (default: setting). */
    clawback_window_days: days.optional(),
  })
  .superRefine((r, ctx) => {
    const flat = FLAT_BASES.includes(r.basis.type);
    for (const [i, t] of (r.slabs?.tiers ?? []).entries()) {
      if (flat && t.amount_paise === undefined)
        ctx.addIssue({ code: "custom", path: ["slabs", "tiers", i], message: "tier_amount" });
      if (!flat && t.pct === undefined)
        ctx.addIssue({ code: "custom", path: ["slabs", "tiers", i], message: "tier_pct" });
    }
    if (r.effective_from && r.effective_to && r.effective_to < r.effective_from)
      ctx.addIssue({ code: "custom", path: ["effective_to"], message: "dates" });
  });
export type CommissionRule = z.infer<typeof commissionRule>;

/** Minimum guarantee: "at least ₹X per period, settled against commission" (a top-up when commission falls short). */
export const floorRule = z.object({
  id,
  label: z.string().trim().min(1).max(80),
  amount_paise: paise,
  period: z.enum(["month", "deal"]),
  /** Commission rules counted towards the floor (empty = all). */
  rules: z.array(id).max(50).default([]),
});
export type FloorRule = z.infer<typeof floorRule>;

/** Commission accrues to the creator only after it exceeds the recoupable part of the fixed fees. */
export const recoupment = z.discriminatedUnion("mode", [
  z.object({ mode: z.literal("none") }),
  z.object({ mode: z.literal("full"), fixed: z.array(id).max(50).default([]) }),
  z.object({ mode: z.literal("partial"), pct, fixed: z.array(id).max(50).default([]) }),
]);
export type Recoupment = z.infer<typeof recoupment>;

// ---------------------------------------------------------------------------------------------------------------
// C. Bonuses
// ---------------------------------------------------------------------------------------------------------------
export const BONUS_METRICS = [
  "enrollments",
  "qualified_leads",
  "leads",
  "applications",
  "views",
  "on_time_all",
  "rank",
] as const;

export const bonusRule = z.object({
  id,
  label: z.string().trim().min(1).max(80),
  conditions: z.object({
    op: z.enum(["and", "or"]),
    items: z
      .array(
        z.object({
          metric: z.enum(BONUS_METRICS),
          comparator: z.enum(["gte", "lte"]),
          value: z.number().int().min(0).max(10_000_000_000),
        }),
      )
      .min(1)
      .max(10),
  }),
  window: z.discriminatedUnion("type", [
    z.object({ type: z.literal("deal") }),
    z.object({ type: z.literal("month") }),
    z.object({ type: z.literal("campaign") }),
    z.object({ type: z.literal("dates"), from: isoDate, to: isoDate }),
  ]),
  amount: z.discriminatedUnion("type", [
    z.object({ type: z.literal("fixed"), amount_paise: paise }),
    z.object({ type: z.literal("pct_of_fixed"), pct }),
    z.object({ type: z.literal("pct_of_commission"), pct }),
  ]),
  /** once: the first window that qualifies; every: each qualifying window (monthly windows). */
  repeat: z.enum(["once", "every"]).default("once"),
});
export type BonusRule = z.infer<typeof bonusRule>;

// ---------------------------------------------------------------------------------------------------------------
// D. Penalties (always proposed; a person approves before anything posts)
// ---------------------------------------------------------------------------------------------------------------
export const penaltyRule = z.discriminatedUnion("type", [
  z.object({
    id,
    type: z.literal("late_delivery"),
    label: z.string().trim().min(1).max(80),
    grace_days: days.default(0),
    per_day: z.discriminatedUnion("type", [
      z.object({ type: z.literal("amount"), amount_paise: paise }),
      /** % per day of the deliverable's linked milestones (or of the deal's fixed value when none are linked). */
      z.object({ type: z.literal("pct"), pct }),
    ]),
    cap: z
      .discriminatedUnion("type", [
        z.object({ type: z.literal("amount"), amount_paise: paise }),
        z.object({ type: z.literal("pct"), pct }),
      ])
      .optional(),
  }),
  z.object({
    id,
    type: z.literal("missed_deliverable"),
    label: z.string().trim().min(1).max(80),
    action: z.discriminatedUnion("type", [
      z.object({ type: z.literal("forfeit_milestones") }),
      z.object({ type: z.literal("fixed"), amount_paise: paise }),
    ]),
  }),
  z.object({ id, type: z.literal("disclosure"), label: z.string().trim().min(1).max(80), amount_paise: paise }),
  z.object({
    id,
    type: z.literal("breach_clawback"),
    label: z.string().trim().min(1).max(80),
    /** % of fixed fees already earned that is clawed back on a breach. */
    pct,
  }),
]);
export type PenaltyRule = z.infer<typeof penaltyRule>;

// ---------------------------------------------------------------------------------------------------------------
// E. Additional fees, F. non-cash
// ---------------------------------------------------------------------------------------------------------------
export const FEE_KINDS = ["usage_rights", "exclusivity", "whitelisting", "reimbursement"] as const;

export const additionalFee = z.object({
  id,
  kind: z.enum(FEE_KINDS),
  label: z.string().trim().min(1).max(80),
  amount_paise: paise,
  platforms: z.array(z.string().trim().min(1).max(20)).max(8).default([]),
  duration_days: days.optional(),
  category: z.string().trim().max(80).optional(),
  trigger: trigger.default({ type: "on_contract_signed" }),
  due_offset_days: days.default(0),
});
export type AdditionalFee = z.infer<typeof additionalFee>;

export const nonCash = z.object({ id, label: z.string().trim().min(1).max(80), value_paise: paise });

// ---------------------------------------------------------------------------------------------------------------
// The document
// ---------------------------------------------------------------------------------------------------------------
export const compConfig = z
  .object({
    schema_version: z.literal(1),
    fixed: z.array(fixedComponent).max(20).default([]),
    commission: z.array(commissionRule).max(20).default([]),
    floors: z.array(floorRule).max(10).default([]),
    recoupment: recoupment.default({ mode: "none" }),
    bonuses: z.array(bonusRule).max(20).default([]),
    penalties: z.array(penaltyRule).max(20).default([]),
    fees: z.array(additionalFee).max(20).default([]),
    non_cash: z.array(nonCash).max(20).default([]),
  })
  .superRefine((c, ctx) => {
    const ids = [
      ...c.fixed.flatMap((f) => [f.id, ...f.milestones.map((m) => `${f.id}.${m.id}`)]),
      ...c.commission.map((r) => r.id),
      ...c.floors.map((r) => r.id),
      ...c.bonuses.map((r) => r.id),
      ...c.penalties.map((r) => r.id),
      ...c.fees.map((r) => r.id),
      ...c.non_cash.map((r) => r.id),
    ];
    const seen = new Set<string>();
    for (const x of ids) {
      if (seen.has(x)) ctx.addIssue({ code: "custom", path: [], message: `duplicate_id:${x}` });
      seen.add(x);
    }
    const fixedIds = new Set(c.fixed.map((f) => f.id));
    if (c.recoupment.mode !== "none")
      for (const f of c.recoupment.fixed)
        if (!fixedIds.has(f))
          ctx.addIssue({ code: "custom", path: ["recoupment", "fixed"], message: `unknown_fixed:${f}` });
    const commissionIds = new Set(c.commission.map((r) => r.id));
    for (const fl of c.floors)
      for (const r of fl.rules)
        if (!commissionIds.has(r)) ctx.addIssue({ code: "custom", path: ["floors"], message: `unknown_rule:${r}` });
    if (c.recoupment.mode !== "none" && c.commission.length === 0)
      ctx.addIssue({ code: "custom", path: ["recoupment"], message: "recoupment_needs_commission" });
  });
export type CompConfig = z.infer<typeof compConfig>;
export type CompConfigInput = z.input<typeof compConfig>;

/** What kind of deal this is, for lists and reports (generated column `deal_model`). */
export function dealModel(c: CompConfig): "commission_only" | "fixed_only" | "hybrid" | "barter" | "custom" {
  const hasFixed = c.fixed.length > 0;
  const hasCommission = c.commission.length > 0;
  if (hasFixed && hasCommission) return "hybrid";
  if (hasFixed) return "fixed_only";
  if (hasCommission) return "commission_only";
  if (c.non_cash.length > 0 && c.fees.length === 0) return "barter";
  return "custom";
}

/** Total fixed value of a version (fixed components, retainers in full), used for % bonuses and penalty caps. */
export function fixedValue(c: CompConfig, only?: readonly string[]): number {
  return c.fixed
    .filter((f) => !only || only.length === 0 || only.includes(f.id))
    .reduce(
      (s, f) => s + (f.basis === "retainer" ? f.amount_paise * (f.retainer?.periods ?? 0) : f.amount_paise * f.units),
      0,
    );
}
