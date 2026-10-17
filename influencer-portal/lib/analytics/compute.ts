// Dashboard arithmetic (spec 12): the lead funnel, unit economics, lead quality, period-over-period deltas and
// leaderboards. Inputs are the totals the database aggregates; every ratio is null when its denominator is zero, so a
// dashboard shows "—" rather than a misleading 0 or infinity. Money stays in integer paise. Pure.

export interface Totals {
  clicks: number;
  /** Credited leads (what creators see in their pipeline). */
  leads: number;
  qualified: number;
  allocated: number;
  applied: number;
  enrolled: number;
  junk: number;
  /** Every attribution decision, credited or not (the duplicate rate's denominator). */
  attributions: number;
  duplicates: number;
  /** Earned by creators in the period (ledger, net of debits, before tax). */
  cost_paise: number;
  /** Eduwit's commission received in the period for credited leads' enrolments, excluding GST. */
  revenue_paise: number;
}

export const EMPTY_TOTALS: Totals = {
  clicks: 0,
  leads: 0,
  qualified: 0,
  allocated: 0,
  applied: 0,
  enrolled: 0,
  junk: 0,
  attributions: 0,
  duplicates: 0,
  cost_paise: 0,
  revenue_paise: 0,
};

/** n / d, or null when d is zero. */
export function ratio(n: number, d: number): number | null {
  return d === 0 ? null : n / d;
}

/** Whole paise per unit (half to even), or null without units. */
export function perUnit(paise: number, units: number): number | null {
  if (units === 0) return null;
  const q = paise / units;
  const f = Math.floor(q);
  const diff = q - f;
  if (Math.abs(diff - 0.5) < 1e-9) return f % 2 === 0 ? f : f + 1;
  return Math.round(q);
}

export const FUNNEL_STEPS = ["clicks", "leads", "qualified", "allocated", "applied", "enrolled"] as const;
export type FunnelStep = (typeof FUNNEL_STEPS)[number];

export interface FunnelRow {
  step: FunnelStep;
  count: number;
  /** Share of the previous step (null for the first step or an empty previous step). */
  from_previous: number | null;
  /** Share of the first step. */
  from_start: number | null;
}

/**
 * Clicks → leads → qualified → allocated → applied → enrolled. Stages are cumulative (a lead that applied also
 * counts as qualified and allocated), so each step is at most the one before; leads without a tracked click (a typed
 * code) can make leads exceed clicks, and the click-to-lead rate then reads above 100%.
 */
export function funnel(t: Pick<Totals, FunnelStep>): FunnelRow[] {
  return FUNNEL_STEPS.map((step, i) => {
    const prev = i === 0 ? null : t[FUNNEL_STEPS[i - 1] as FunnelStep];
    return {
      step,
      count: t[step],
      from_previous: prev === null ? null : ratio(t[step], prev),
      from_start: i === 0 ? null : ratio(t[step], t.clicks),
    };
  });
}

export interface UnitEconomics {
  cost_per_lead_paise: number | null;
  cost_per_qualified_paise: number | null;
  cost_per_enrollment_paise: number | null;
  revenue_paise: number;
  cost_paise: number;
  /** (revenue − cost) / cost. */
  net_roi: number | null;
  /** revenue / cost. */
  roas: number | null;
}

export function unitEconomics(t: Pick<Totals, "leads" | "qualified" | "enrolled" | "cost_paise" | "revenue_paise">) {
  const e: UnitEconomics = {
    cost_per_lead_paise: perUnit(t.cost_paise, t.leads),
    cost_per_qualified_paise: perUnit(t.cost_paise, t.qualified),
    cost_per_enrollment_paise: perUnit(t.cost_paise, t.enrolled),
    revenue_paise: t.revenue_paise,
    cost_paise: t.cost_paise,
    net_roi: t.cost_paise > 0 ? ratio(t.revenue_paise - t.cost_paise, t.cost_paise) : null,
    roas: t.cost_paise > 0 ? ratio(t.revenue_paise, t.cost_paise) : null,
  };
  return e;
}

export interface LeadQuality {
  qualification_rate: number | null;
  junk_rate: number | null;
  duplicate_rate: number | null;
  enrollment_rate: number | null;
}

export function leadQuality(
  t: Pick<Totals, "leads" | "qualified" | "junk" | "duplicates" | "attributions" | "enrolled">,
) {
  const q: LeadQuality = {
    qualification_rate: ratio(t.qualified, t.leads),
    junk_rate: ratio(t.junk, t.leads),
    duplicate_rate: ratio(t.duplicates, t.attributions),
    enrollment_rate: ratio(t.enrolled, t.leads),
  };
  return q;
}

export type Polarity = "up_is_good" | "down_is_good" | "neutral";

export interface Delta {
  /** current − previous. */
  change: number;
  /** Relative change, or null when the previous value is zero or missing. */
  pct: number | null;
  direction: "up" | "down" | "flat";
  /** Whether the change is good news for this metric. */
  tone: "good" | "bad" | "neutral";
}

export function delta(current: number | null, previous: number | null, polarity: Polarity): Delta | null {
  if (current === null || previous === null) return null;
  const change = current - previous;
  const direction = Math.abs(change) < 1e-9 ? "flat" : change > 0 ? "up" : "down";
  const tone =
    direction === "flat" || polarity === "neutral"
      ? "neutral"
      : (direction === "up") === (polarity === "up_is_good")
        ? "good"
        : "bad";
  return { change, pct: previous === 0 ? null : change / Math.abs(previous), direction, tone };
}

export interface RankRow<T> {
  rank: number;
  row: T;
  value: number;
}

/**
 * Standard competition ranking (1, 2, 2, 4): highest first unless `ascending`. Rows below `minSample` (for example
 * fewer than five leads for a rate) are left out so a single lucky lead cannot top a board; ties keep name order.
 */
export function leaderboard<T>(
  rows: readonly T[],
  value: (r: T) => number | null,
  opts: { sample?: (r: T) => number; minSample?: number; ascending?: boolean; limit?: number; name: (r: T) => string },
): RankRow<T>[] {
  const scored = rows
    .map((row) => ({ row, value: value(row) }))
    .filter((x): x is { row: T; value: number } => x.value !== null && Number.isFinite(x.value))
    .filter((x) => (opts.sample ? opts.sample(x.row) >= (opts.minSample ?? 0) : true))
    .sort(
      (a, b) =>
        (opts.ascending ? a.value - b.value : b.value - a.value) || opts.name(a.row).localeCompare(opts.name(b.row)),
    );
  const out: RankRow<T>[] = [];
  scored.forEach((x, i) => {
    const prev = out[i - 1];
    out.push({ rank: prev && Math.abs(prev.value - x.value) < 1e-12 ? prev.rank : i + 1, row: x.row, value: x.value });
  });
  return out.slice(0, opts.limit ?? out.length);
}

/** Sums rows of totals (for example the breakdown rows into an overall line). */
export function addTotals(rows: readonly Totals[]): Totals {
  const t = { ...EMPTY_TOTALS };
  for (const r of rows) for (const k of Object.keys(t) as (keyof Totals)[]) t[k] += r[k];
  return t;
}
