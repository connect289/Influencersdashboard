// The compensation engine (spec 6.3). Pure and deterministic: no I/O, no clock (time comes from `as_of`).
//
// It replays a deal's whole event stream against its versions and returns the complete ledger the deal should have
// as of `as_of`: every line with a stable key (deal version + rule + subject + event), its amount and how much of it
// is confirmed, plus penalty proposals for a person to approve. The runner (Phase 7) and the admin dry-run diff that
// result against what is already posted (diff.ts), so the engine never needs to know what was posted before.
//
// Conventions: integer paise, percentages as basis points, banker's rounding once per line, IST calendar for months
// and dates, ties in time processed in event order.
import {
  addDays,
  addMonths,
  addMs,
  DAY,
  istDate,
  istMidnight,
  istMonth,
  nextMonth,
  type EngineEvent,
} from "./events";
import { allocate, mulDiv, netOfGst, pctOf, sum, toBps, type Paise } from "./money";
import {
  FLAT_BASES,
  fixedValue,
  type AdditionalFee,
  type BonusRule,
  type CommissionRule,
  type CompConfig,
  type FixedComponent,
  type Milestone,
  type Trigger,
} from "./schema";

// ---------------------------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------------------------
export interface DealVersion {
  id: string;
  /** ISO instant the version takes effect (the first version should cover the whole deal). */
  effective_from: string;
  config: CompConfig;
}

export interface EngineContext {
  /** GST on Eduwit's partner commission (GST-inclusive receipts), in basis points. */
  eduwit_gst_bps: number;
  /** Default hold for "after hold days" confirmation (compensation.defaults.hold_days). */
  hold_days: number;
  /** Default clawback window (compensation.defaults.refund_window_days). */
  refund_window_days: number;
  /** Total penalties per deal are capped at this share of the deal's fixed value (compensation.defaults.penalty_cap_pct). */
  penalty_cap_bps: number;
  /** Confirm commission pro rata on partial receipts (compensation.defaults.confirm_partial_receipts). */
  confirm_partial_receipts: boolean;
}

export interface EngineInput {
  deal: {
    id: string;
    starts_on: string;
    ends_on?: string | null;
    campaign_ends_on?: string | null;
  };
  versions: DealVersion[];
  events: EngineEvent[];
  as_of: string;
  context: EngineContext;
}

export const ENTRY_TYPES = [
  "fixed_fee",
  "milestone",
  "commission",
  "bonus",
  "usage_fee",
  "exclusivity_fee",
  "reimbursement",
  "clawback",
  "adjustment",
] as const;
export type EntryType = (typeof ENTRY_TYPES)[number];

export interface LedgerLine {
  key: string;
  type: EntryType;
  direction: "credit" | "debit";
  amount_paise: Paise;
  confirmed_paise: Paise;
  rule_id: string;
  version_id: string;
  /** What the line is about: a milestone, enrolment, lead, period… */
  subject: string;
  at: string;
  /** IST month the line belongs to (YYYY-MM). */
  period: string;
  /** IST date it is due for payment, once confirmed. */
  due_on: string;
  note: string;
  /** Commission unit this line belongs to (lines of one unit confirm and claw back together). */
  unit?: string;
}

export interface PenaltyProposal {
  key: string;
  rule_id: string;
  version_id: string;
  subject: string;
  amount_paise: Paise;
  at: string;
  reason: string;
  /** Milestones that are forfeited instead of (or as well as) a charge. */
  forfeits: string[];
}

export interface EngineResult {
  lines: LedgerLine[];
  proposals: PenaltyProposal[];
  totals: {
    credits: Paise;
    debits: Paise;
    net: Paise;
    confirmed_net: Paise;
    recouped: Paise;
    non_cash: Paise;
  };
}

// ---------------------------------------------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------------------------------------------
interface Unit {
  key: string;
  rule: string;
  version: string;
  basis: CommissionRule["basis"]["type"];
  period: string;
  accruedAt: string;
  /** For percentage bases, the amount the percentage applies to (paise); for flat bases, 0. */
  base: Paise;
  /** Rate applied to the unit right now: paise (flat) or bps (percentage). */
  rate: number;
  active: boolean;
  lineKeys: string[];
  topups: number;
  confirmation: CommissionRule["confirmation"]["type"];
  holdDays: number;
  windowDays: number;
  confirmedFraction: [number, number]; // numerator / denominator
  enrollment?: string;
  lead?: string;
  expectedGross?: Paise;
  received: Paise;
  adjusted: boolean;
}

interface Timer {
  at: string;
  seq: number;
  kind:
    | "month_close"
    | "deal_close"
    | "campaign_close"
    | "date"
    | "after_live"
    | "hold"
    | "retainer"
    | "bonus_dates";
  data: Record<string, string | number>;
}

const PERIOD_DEAL = "deal";
const PERIOD_CAMPAIGN = "campaign";

function compareIso(a: string, b: string): number {
  const x = Date.parse(a);
  const y = Date.parse(b);
  return x < y ? -1 : x > y ? 1 : 0;
}

export function computeLedger(input: EngineInput): EngineResult {
  const { context: ctx } = input;
  const asOf = input.as_of;
  const versions = [...input.versions].sort((a, b) =>
    compareIso(a.effective_from, b.effective_from),
  );
  if (versions.length === 0) throw new Error("a deal needs at least one version");
  const first = versions[0] as DealVersion;
  const versionAt = (at: string): DealVersion => {
    let v = first;
    for (const x of versions) if (compareIso(x.effective_from, at) <= 0) v = x;
    return v;
  };

  const lines = new Map<string, LedgerLine>();
  const proposals = new Map<string, PenaltyProposal>();
  const order: string[] = [];

  // Event log by type (for bonus metrics and scope lookups).
  const leads = new Map<string, Extract<EngineEvent, { type: "lead" }>>();
  const rejectedLeads = new Set<string>();
  const enrollments = new Map<string, Extract<EngineEvent, { type: "enrolled" }>>();
  const cancelledEnrollments = new Map<string, string>(); // enrollment → at
  const qualifiedAt = new Map<string, string>();
  const appliedAt = new Map<string, string>();
  const dueAt = new Map<string, string>();
  const liveAt = new Map<string, string>();
  const cancelledDeliverables = new Set<string>();
  const metricHistory: {
    at: string;
    deliverable: string;
    metric: "views" | "reach";
    value: number;
  }[] = [];
  const ranks = new Map<string, number>();
  const firedMilestones = new Set<string>(); // "<component>.<milestone>"
  const firedFees = new Set<string>();
  const firedBonuses = new Set<string>();
  const closedWindows = new Set<string>();
  const units = new Map<string, Unit>();
  const slabCounts = new Map<string, string[]>(); // rule|period → active unit keys in accrual order
  const capTotals = new Map<string, number>(); // rule|month or rule|life → paise
  let recoupBalance = 0; // recouped so far
  let commissionNet = 0;
  let penaltyTotal = 0;

  // -------------------------------------------------------------------------------------------------------------
  // Lines
  // -------------------------------------------------------------------------------------------------------------
  const addLine = (
    l: Omit<LedgerLine, "period" | "confirmed_paise"> & { confirmed?: boolean },
  ): LedgerLine | null => {
    if (l.amount_paise <= 0) return null;
    let key = l.key;
    for (let i = 2; lines.has(key); i++) key = `${l.key}#${String(i)}`;
    const line: LedgerLine = {
      key,
      type: l.type,
      direction: l.direction,
      amount_paise: l.amount_paise,
      confirmed_paise: l.confirmed === false ? 0 : l.amount_paise,
      rule_id: l.rule_id,
      version_id: l.version_id,
      subject: l.subject,
      at: l.at,
      period: istMonth(l.at),
      due_on: l.due_on,
      note: l.note,
      unit: l.unit,
    };
    lines.set(key, line);
    order.push(key);
    return line;
  };
  const signed = (l: LedgerLine) => (l.direction === "credit" ? l.amount_paise : -l.amount_paise);

  // -------------------------------------------------------------------------------------------------------------
  // Timers
  // -------------------------------------------------------------------------------------------------------------
  const timers: Timer[] = [];
  let timerSeq = 0;
  const schedule = (at: string, kind: Timer["kind"], data: Timer["data"] = {}) => {
    if (compareIso(at, asOf) > 0) return;
    timers.push({ at, seq: timerSeq++, kind, data });
  };
  const popTimer = (before: string | null): Timer | null => {
    let best = -1;
    for (let i = 0; i < timers.length; i++) {
      const t = timers[i] as Timer;
      if (before !== null && compareIso(t.at, before) >= 0) continue;
      const b = best === -1 ? null : (timers[best] as Timer);
      if (!b || compareIso(t.at, b.at) < 0 || (compareIso(t.at, b.at) === 0 && t.seq < b.seq))
        best = i;
    }
    if (best === -1) return null;
    return timers.splice(best, 1)[0] ?? null;
  };

  const events = [...input.events].sort(
    (a, b) => compareIso(a.at, b.at) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0),
  );
  const startDate = [
    input.deal.starts_on,
    ...(events[0] ? [istDate(events[0].at)] : []),
  ].sort()[0] as string;
  // Month closes from the first month to as_of.
  const lastMonth = input.deal.ends_on ? input.deal.ends_on.slice(0, 7) : null;
  for (
    let m = startDate.slice(0, 7);
    (lastMonth === null || m <= lastMonth) &&
    compareIso(istMidnight(`${nextMonth(m)}-01`), asOf) <= 0;
    m = nextMonth(m)
  )
    schedule(istMidnight(`${nextMonth(m)}-01`), "month_close", { month: m });
  if (input.deal.ends_on) schedule(istMidnight(addDays(input.deal.ends_on, 1)), "deal_close");
  if (input.deal.campaign_ends_on)
    schedule(istMidnight(addDays(input.deal.campaign_ends_on, 1)), "campaign_close");
  // Specific-date triggers, retainers and dated bonus windows (from every version; the version in force decides).
  const datedKeys = new Set<string>();
  for (const v of versions) {
    for (const f of v.config.fixed) {
      for (const m of f.milestones)
        if (m.trigger.type === "on_specific_date" && !datedKeys.has(`${f.id}.${m.id}`)) {
          datedKeys.add(`${f.id}.${m.id}`);
          schedule(istMidnight(m.trigger.date), "date", { ref: `${f.id}.${m.id}` });
        }
      if (f.basis === "retainer" && f.retainer && !datedKeys.has(`retainer:${f.id}`)) {
        datedKeys.add(`retainer:${f.id}`);
        for (let k = 0; k < f.retainer.periods; k++) {
          const startK =
            f.retainer.every === "month"
              ? addMonths(input.deal.starts_on, k)
              : addDays(input.deal.starts_on, 7 * k);
          const endK =
            f.retainer.every === "month"
              ? addMonths(input.deal.starts_on, k + 1)
              : addDays(input.deal.starts_on, 7 * (k + 1));
          schedule(istMidnight(f.retainer.pay_on === "period_start" ? startK : endK), "retainer", {
            component: f.id,
            k,
          });
        }
      }
    }
    for (const fee of v.config.fees)
      if (fee.trigger.type === "on_specific_date" && !datedKeys.has(`fee:${fee.id}`)) {
        datedKeys.add(`fee:${fee.id}`);
        schedule(istMidnight(fee.trigger.date), "date", { ref: `fee:${fee.id}` });
      }
    for (const b of v.config.bonuses)
      if (b.window.type === "dates" && !datedKeys.has(`bonus:${b.id}`)) {
        datedKeys.add(`bonus:${b.id}`);
        schedule(istMidnight(addDays(b.window.to, 1)), "bonus_dates", { bonus: b.id });
      }
  }

  // -------------------------------------------------------------------------------------------------------------
  // Fixed fees: milestones and additional fees
  // -------------------------------------------------------------------------------------------------------------
  const milestoneAmounts = (f: FixedComponent): Map<string, Paise> => {
    const total = f.amount_paise * f.units;
    const out = new Map<string, Paise>();
    if (f.milestones[0]?.share.type === "amount") {
      for (const m of f.milestones)
        out.set(m.id, m.share.type === "amount" ? m.share.amount_paise : 0);
    } else {
      const parts = allocate(
        total,
        f.milestones.map((m) => (m.share.type === "pct" ? toBps(m.share.pct) : 0)),
      );
      f.milestones.forEach((m, i) => out.set(m.id, parts[i] ?? 0));
    }
    return out;
  };

  const dueOn = (at: string, offset: number, terms: number) => addDays(istDate(at), offset + terms);

  const fireMilestone = (
    v: DealVersion,
    f: FixedComponent,
    m: Milestone,
    at: string,
    shareBps = 10_000,
    note = "",
  ) => {
    const ref = `${f.id}.${m.id}`;
    if (firedMilestones.has(ref)) return;
    firedMilestones.add(ref);
    const full = milestoneAmounts(f).get(m.id) ?? 0;
    const amount = shareBps === 10_000 ? full : pctOf(full, shareBps);
    addLine({
      key: `${v.id}:${f.id}:${m.id}:milestone`,
      type: "milestone",
      direction: "credit",
      amount_paise: amount,
      rule_id: ref,
      version_id: v.id,
      subject: ref,
      at,
      due_on: dueOn(at, m.due_offset_days, m.payment_terms_days),
      note: note || `${f.label}: ${m.label}`,
    });
  };

  const FEE_TYPE: Record<AdditionalFee["kind"], EntryType> = {
    usage_rights: "usage_fee",
    whitelisting: "usage_fee",
    exclusivity: "exclusivity_fee",
    reimbursement: "reimbursement",
  };
  const fireFee = (v: DealVersion, fee: AdditionalFee, at: string) => {
    if (firedFees.has(fee.id)) return;
    firedFees.add(fee.id);
    addLine({
      key: `${v.id}:${fee.id}:fee`,
      type: FEE_TYPE[fee.kind],
      direction: "credit",
      amount_paise: fee.amount_paise,
      rule_id: fee.id,
      version_id: v.id,
      subject: fee.id,
      at,
      due_on: dueOn(at, fee.due_offset_days, 0),
      note: fee.label,
    });
  };

  /** Metric value for triggers: views/reach (cumulative, per deliverable or summed) or leads (count). */
  const metricValue = (
    metric: "views" | "reach" | "leads",
    deliverable: string | undefined,
    at: string,
  ): number => {
    if (metric === "leads")
      return [...leads.values()].filter(
        (l) =>
          !l.junk &&
          !l.duplicate &&
          !rejectedLeads.has(l.lead) &&
          compareIso(l.at, at) <= 0 &&
          (!deliverable || l.deliverable === deliverable),
      ).length;
    const latest = new Map<string, number>();
    for (const h of metricHistory)
      if (
        h.metric === metric &&
        compareIso(h.at, at) <= 0 &&
        (!deliverable || h.deliverable === deliverable)
      )
        latest.set(h.deliverable, h.value);
    return sum([...latest.values()]);
  };

  /** Run every milestone and fee whose trigger matches this event. */
  const triggerFixed = (
    ev:
      | EngineEvent
      | { type: "date"; ref: string; at: string }
      | { type: "campaign_close"; at: string },
  ) => {
    const v = versionAt(ev.at);
    const matches = (t: Trigger, ref: string): boolean => {
      switch (t.type) {
        case "on_contract_signed":
          return ev.type === "contract_signed";
        case "on_brief_acknowledged":
          return ev.type === "brief_acknowledged";
        case "on_concept_approved":
          return (
            ev.type === "concept_approved" && (!t.deliverable || t.deliverable === ev.deliverable)
          );
        case "on_draft_approved":
          return (
            ev.type === "draft_approved" && (!t.deliverable || t.deliverable === ev.deliverable)
          );
        case "on_deliverable_live":
          return (
            ev.type === "deliverable_live" && (!t.deliverable || t.deliverable === ev.deliverable)
          );
        case "after_n_days_live":
          return false; // scheduled from the live event
        case "on_metric_threshold":
          return (
            ((ev.type === "metric" && t.metric === ev.metric) ||
              (ev.type === "lead" && t.metric === "leads")) &&
            metricValue(t.metric, t.deliverable, ev.at) >= t.threshold
          );
        case "on_campaign_end":
          return ev.type === "campaign_ended" || ev.type === "campaign_close";
        case "on_specific_date":
          return ev.type === "date" && ev.ref === ref;
        case "manual_release":
          return ev.type === "manual_release" && ev.milestone === ref;
      }
    };
    for (const f of v.config.fixed)
      for (const m of f.milestones) {
        const ref = `${f.id}.${m.id}`;
        if (firedMilestones.has(ref)) continue;
        if (
          m.trigger.type === "after_n_days_live" &&
          ev.type === "deliverable_live" &&
          (!m.trigger.deliverable || m.trigger.deliverable === ev.deliverable)
        ) {
          schedule(addMs(ev.at, m.trigger.days * DAY), "after_live", { ref });
          continue;
        }
        if (matches(m.trigger, ref)) fireMilestone(v, f, m, ev.at);
      }
    for (const fee of v.config.fees) {
      if (firedFees.has(fee.id)) continue;
      if (
        fee.trigger.type === "after_n_days_live" &&
        ev.type === "deliverable_live" &&
        (!fee.trigger.deliverable || fee.trigger.deliverable === ev.deliverable)
      ) {
        schedule(addMs(ev.at, fee.trigger.days * DAY), "after_live", { ref: `fee:${fee.id}` });
        continue;
      }
      if (matches(fee.trigger, `fee:${fee.id}`)) fireFee(v, fee, ev.at);
    }
  };

  const fireByRef = (ref: string, at: string) => {
    const v = versionAt(at);
    if (ref.startsWith("fee:")) {
      const fee = v.config.fees.find((x) => `fee:${x.id}` === ref);
      if (fee) fireFee(v, fee, at);
      return;
    }
    for (const f of v.config.fixed)
      for (const m of f.milestones) if (`${f.id}.${m.id}` === ref) fireMilestone(v, f, m, at);
  };

  // -------------------------------------------------------------------------------------------------------------
  // Commission
  // -------------------------------------------------------------------------------------------------------------
  const ruleActive = (r: CommissionRule, at: string) => {
    const d = istDate(at);
    return (!r.effective_from || d >= r.effective_from) && (!r.effective_to || d <= r.effective_to);
  };

  interface Subject {
    programme_id?: number;
    university_id?: number;
    level?: string;
    link?: string;
    deliverable?: string;
  }
  const inScope = (r: CommissionRule, s: Subject) => {
    const sc = r.scope;
    switch (sc.type) {
      case "all":
        return true;
      case "programmes":
        return s.programme_id !== undefined && sc.ids.includes(s.programme_id);
      case "universities":
        return s.university_id !== undefined && sc.ids.includes(s.university_id);
      case "levels":
        return (
          s.level !== undefined &&
          sc.levels.map((x) => x.toLowerCase()).includes(s.level.toLowerCase())
        );
      case "links":
        return s.link !== undefined && sc.codes.includes(s.link);
      case "deliverables":
        return s.deliverable !== undefined && sc.ids.includes(s.deliverable);
    }
  };

  const periodKey = (r: CommissionRule, at: string) =>
    !r.slabs
      ? PERIOD_DEAL
      : r.slabs.period === "month"
        ? istMonth(at)
        : r.slabs.period === "campaign"
          ? PERIOD_CAMPAIGN
          : PERIOD_DEAL;

  /** The rate (paise for flat bases, bps for percentages) of the tier that holds the n-th unit. */
  const rateFor = (r: CommissionRule, n: number): number => {
    const flat = FLAT_BASES.includes(r.basis.type);
    const baseRate = "amount_paise" in r.basis ? r.basis.amount_paise : toBps(r.basis.pct);
    if (!r.slabs) return baseRate;
    let rate = baseRate;
    for (const t of r.slabs.tiers)
      if (n >= t.from) rate = flat ? (t.amount_paise ?? 0) : toBps(t.pct ?? 0);
    return rate;
  };

  const amountAt = (u: Unit, rate: number) =>
    FLAT_BASES.includes(u.basis) ? rate : pctOf(u.base, rate);

  /** Apply per-unit, monthly and lifetime caps to a positive amount; returns the capped amount and books it. */
  const capped = (r: CommissionRule, at: string, amount: Paise, alreadyOnUnit: Paise): Paise => {
    let a = amount;
    if (r.caps.per_unit_paise !== undefined)
      a = Math.min(a, Math.max(r.caps.per_unit_paise - alreadyOnUnit, 0));
    const mKey = `${r.id}|m|${istMonth(at)}`;
    const lKey = `${r.id}|life`;
    if (r.caps.per_month_paise !== undefined)
      a = Math.min(a, Math.max(r.caps.per_month_paise - (capTotals.get(mKey) ?? 0), 0));
    if (r.caps.lifetime_paise !== undefined)
      a = Math.min(a, Math.max(r.caps.lifetime_paise - (capTotals.get(lKey) ?? 0), 0));
    return a;
  };
  const book = (rule: string, at: string, delta: Paise) => {
    for (const k of [`${rule}|m|${istMonth(at)}`, `${rule}|life`])
      capTotals.set(k, (capTotals.get(k) ?? 0) + delta);
  };

  const unitPaid = (u: Unit) =>
    sum(
      u.lineKeys
        .map((k) => lines.get(k))
        .filter((l): l is LedgerLine => !!l && l.type !== "adjustment")
        .map(signed),
    );

  const unitFractionPaise = (u: Unit, amount: Paise) =>
    u.confirmedFraction[1] === 0
      ? 0
      : mulDiv(amount, u.confirmedFraction[0], u.confirmedFraction[1]);
  const refreshUnitConfirmation = (u: Unit) => {
    for (const k of u.lineKeys) {
      const l = lines.get(k);
      if (l && l.type !== "clawback")
        l.confirmed_paise = Math.min(l.amount_paise, unitFractionPaise(u, l.amount_paise));
    }
  };

  /** After any change to net commission, keep the recouped amount = min(net commission, recoupable). */
  const recoup = (v: DealVersion, trigger: LedgerLine, u: Unit | null) => {
    const rc = v.config.recoupment;
    if (rc.mode === "none") return;
    const recoupable =
      rc.mode === "full"
        ? fixedValue(v.config, rc.fixed)
        : pctOf(fixedValue(v.config, rc.fixed), toBps(rc.pct));
    const target = Math.min(Math.max(commissionNet, 0), recoupable);
    const delta = target - recoupBalance;
    if (delta === 0) return;
    recoupBalance = target;
    const line = addLine({
      key: `${trigger.key}:recoup`,
      type: "adjustment",
      direction: delta > 0 ? "debit" : "credit",
      amount_paise: Math.abs(delta),
      rule_id: "recoupment",
      version_id: v.id,
      subject: trigger.subject,
      at: trigger.at,
      due_on: trigger.due_on,
      note: delta > 0 ? "Recouped against the fixed fee" : "Recoupment released",
      unit: u?.key,
      confirmed: trigger.confirmed_paise === trigger.amount_paise,
    });
    if (line && u) {
      u.lineKeys.push(line.key);
      refreshUnitConfirmation(u);
    }
  };

  const postUnitLine = (
    v: DealVersion,
    r: CommissionRule,
    u: Unit,
    kind: string,
    direction: "credit" | "debit",
    amount: Paise,
    at: string,
    note: string,
    type: EntryType = "commission",
  ) => {
    const line = addLine({
      key: `${u.version}:${r.id}:${u.key}:${kind}`,
      type,
      direction,
      amount_paise: amount,
      rule_id: r.id,
      version_id: v.id,
      subject: u.key,
      at,
      due_on: istDate(at),
      note,
      unit: u.key,
      confirmed: false,
    });
    if (!line) return;
    u.lineKeys.push(line.key);
    if (type === "clawback") line.confirmed_paise = line.amount_paise;
    else line.confirmed_paise = unitFractionPaise(u, line.amount_paise);
    book(r.id, at, direction === "credit" ? amount : -amount);
    commissionNet += direction === "credit" ? amount : -amount;
    recoup(v, line, u);
  };

  /** Re-rate every active unit in a retroactive period to the current tier. */
  const rerate = (v: DealVersion, r: CommissionRule, pk: string, at: string) => {
    const keys = slabCounts.get(`${r.id}|${pk}`) ?? [];
    const rate = rateFor(r, keys.length);
    for (const k of keys) {
      const u = units.get(k);
      if (!u?.active || u.rate === rate) continue;
      const target = amountAt(u, rate);
      const paid = unitPaid(u);
      let delta = target - paid;
      if (delta > 0) delta = capped(r, at, delta, paid);
      u.rate = rate;
      if (delta === 0) continue;
      u.topups += 1;
      postUnitLine(
        v,
        r,
        u,
        `topup${String(u.topups)}`,
        delta > 0 ? "credit" : "debit",
        Math.abs(delta),
        at,
        delta > 0 ? "Slab top-up (retroactive)" : "Slab reduced (retroactive)",
      );
    }
  };

  const accrue = (
    ev: EngineEvent,
    unitSubject: string,
    s: Subject,
    units_for: CommissionRule["basis"]["type"][],
    extra: Partial<Unit> = {},
  ) => {
    const v = versionAt(ev.at);
    for (const r of v.config.commission) {
      if (!units_for.includes(r.basis.type) || !ruleActive(r, ev.at) || !inScope(r, s)) continue;
      const key = `${r.id}:${unitSubject}`;
      if (units.has(key)) continue;
      let base = 0;
      if (r.basis.type === "pct_of_programme_fee") base = extra.base ?? 0;
      if (r.basis.type === "pct_of_eduwit_commission") {
        const gross = extra.expectedGross;
        if (gross === undefined) continue; // accrues when the commission is received
        base = r.basis.base === "net_of_gst" ? netOfGst(gross, ctx.eduwit_gst_bps) : gross;
      }
      const pk = periodKey(r, ev.at);
      const list = slabCounts.get(`${r.id}|${pk}`) ?? [];
      list.push(key);
      slabCounts.set(`${r.id}|${pk}`, list);
      const conf = r.confirmation;
      const u: Unit = {
        key,
        rule: r.id,
        version: v.id,
        basis: r.basis.type,
        period: pk,
        accruedAt: ev.at,
        base,
        rate: rateFor(r, list.length),
        active: true,
        lineKeys: [],
        topups: 0,
        confirmation: conf.type,
        holdDays: conf.type === "after_hold_days" ? (conf.days ?? ctx.hold_days) : 0,
        windowDays: r.clawback_window_days ?? ctx.refund_window_days,
        confirmedFraction: conf.type === "immediate" ? [1, 1] : [0, 1],
        received: 0,
        adjusted: false,
        ...extra,
      };
      units.set(key, u);
      // Marginal: the unit's position sets its tier for good. Retroactive: it gets the current tier and the others
      // are re-rated to match below.
      const amount = capped(r, ev.at, amountAt(u, u.rate), 0);
      postUnitLine(v, r, u, "accrue", "credit", amount, ev.at, r.label);
      if (r.slabs?.mode === "retroactive") rerate(v, r, pk, ev.at);
      if (conf.type === "after_hold_days")
        schedule(addMs(ev.at, u.holdDays * DAY), "hold", { unit: key });
    }
  };

  const clawback = (match: (u: Unit) => boolean, at: string, reason: string) => {
    for (const u of units.values()) {
      if (!u.active || !match(u)) continue;
      if (compareIso(at, addMs(u.accruedAt, u.windowDays * DAY)) > 0) continue; // outside the window: no clawback
      const v = versionAt(at);
      const r = versionRule(u);
      if (!r) continue;
      const paid = unitPaid(u);
      // A clawed-back unit is final: its accrual and the clawback confirm together and net to zero.
      confirmUnit(u, 1, 1);
      u.active = false;
      const list = slabCounts.get(`${r.id}|${u.period}`) ?? [];
      slabCounts.set(
        `${r.id}|${u.period}`,
        list.filter((k) => k !== u.key),
      );
      if (paid > 0) postUnitLine(v, r, u, "clawback", "debit", paid, at, reason, "clawback");
      if (r.slabs?.mode === "retroactive") rerate(v, r, u.period, at);
    }
  };

  const versionRule = (u: Unit): CommissionRule | undefined => {
    const own = versions
      .find((x) => x.id === u.version)
      ?.config.commission.find((r) => r.id === u.rule);
    return own ?? versionAt(u.accruedAt).config.commission.find((r) => r.id === u.rule);
  };

  const confirmUnit = (u: Unit, num: number, den: number) => {
    if (u.confirmedFraction[0] * den >= num * u.confirmedFraction[1]) return;
    u.confirmedFraction = [num, den];
    refreshUnitConfirmation(u);
  };

  // -------------------------------------------------------------------------------------------------------------
  // Windows: floors and bonuses
  // -------------------------------------------------------------------------------------------------------------
  const commissionIn = (rules: readonly string[], from: string | null, to: string): Paise =>
    sum(
      order
        .map((k) => lines.get(k))
        .filter(
          (l): l is LedgerLine =>
            !!l &&
            !!l.unit &&
            l.type !== "adjustment" &&
            (rules.length === 0 || rules.includes(l.rule_id)) &&
            (from === null || compareIso(l.at, from) >= 0) &&
            compareIso(l.at, to) < 0,
        )
        .map(signed),
    );

  const closeFloors = (scope: "month" | "deal", key: string, from: string | null, to: string) => {
    const v = versionAt(addMs(to, -1));
    for (const fl of v.config.floors) {
      if (fl.period !== scope) continue;
      const earned = commissionIn(fl.rules, from, to);
      const short = fl.amount_paise - earned;
      if (short > 0)
        addLine({
          key: `${v.id}:${fl.id}:${key}:floor`,
          type: "adjustment",
          direction: "credit",
          amount_paise: short,
          rule_id: fl.id,
          version_id: v.id,
          subject: key,
          at: addMs(to, -1),
          due_on: istDate(addMs(to, -1)),
          note: `${fl.label}: minimum guarantee top-up`,
        });
    }
  };

  const bonusMetric = (
    metric: BonusRule["conditions"]["items"][number]["metric"],
    from: string | null,
    to: string,
    windowKey: string,
  ): number | null => {
    const inWin = (at: string) =>
      (from === null || compareIso(at, from) >= 0) && compareIso(at, to) < 0;
    switch (metric) {
      case "enrollments":
        return [...enrollments.values()].filter(
          (e) => inWin(e.at) && !cancelledEnrollments.has(e.enrollment),
        ).length;
      case "qualified_leads":
        return [...qualifiedAt.entries()].filter(
          ([lead, at]) => inWin(at) && !rejectedLeads.has(lead),
        ).length;
      case "leads":
        return [...leads.values()].filter(
          (l) => inWin(l.at) && !l.junk && !l.duplicate && !rejectedLeads.has(l.lead),
        ).length;
      case "applications":
        return [...appliedAt.entries()].filter(
          ([lead, at]) => inWin(at) && !rejectedLeads.has(lead),
        ).length;
      case "views": {
        const end = metricValue("views", undefined, addMs(to, -1));
        const start = from === null ? 0 : metricValue("views", undefined, addMs(from, -1));
        return end - start;
      }
      case "on_time_all": {
        const due = [...dueAt.entries()].filter(
          ([d, at]) => inWin(at) && !cancelledDeliverables.has(d),
        );
        if (due.length === 0) return 0;
        return due.every(([d, at]) => {
          const live = liveAt.get(d);
          return live !== undefined && compareIso(live, at) <= 0;
        })
          ? 1
          : 0;
      }
      case "rank":
        return ranks.get(windowKey) ?? null;
    }
  };

  const closeBonuses = (
    type: BonusRule["window"]["type"],
    key: string,
    from: string | null,
    to: string,
    only?: string,
  ) => {
    const v = versionAt(addMs(to, -1));
    for (const b of v.config.bonuses) {
      if (b.window.type !== type || (only && b.id !== only)) continue;
      if (b.repeat === "once" && firedBonuses.has(b.id)) continue;
      const results = b.conditions.items.map((c) => {
        const val = bonusMetric(c.metric, from, to, key);
        if (val === null) return false;
        return c.comparator === "gte" ? val >= c.value : val <= c.value;
      });
      const ok = b.conditions.op === "and" ? results.every(Boolean) : results.some(Boolean);
      if (!ok) continue;
      firedBonuses.add(b.id);
      const amount =
        b.amount.type === "fixed"
          ? b.amount.amount_paise
          : b.amount.type === "pct_of_fixed"
            ? pctOf(fixedValue(v.config), toBps(b.amount.pct))
            : pctOf(Math.max(commissionIn([], from, to), 0), toBps(b.amount.pct));
      addLine({
        key: `${v.id}:${b.id}:${key}:bonus`,
        type: "bonus",
        direction: "credit",
        amount_paise: amount,
        rule_id: b.id,
        version_id: v.id,
        subject: key,
        at: addMs(to, -1),
        due_on: istDate(addMs(to, -1)),
        note: b.label,
      });
    }
  };

  // -------------------------------------------------------------------------------------------------------------
  // Penalties (proposals only)
  // -------------------------------------------------------------------------------------------------------------
  const propose = (
    v: DealVersion,
    ruleId: string,
    subject: string,
    amount: Paise,
    at: string,
    reason: string,
    forfeits: string[] = [],
  ) => {
    // The cap is a share of the deal's fixed value, or of everything earned so far when that is larger (so a
    // commission-only deal can still carry a penalty).
    const earned = sum(
      [...lines.values()].filter((l) => l.direction === "credit").map((l) => l.amount_paise),
    );
    const cap = pctOf(Math.max(fixedValue(v.config), earned), ctx.penalty_cap_bps);
    const allowed = Math.max(Math.min(amount, cap - penaltyTotal), 0);
    const key = `${v.id}:${ruleId}:${subject}:penalty`;
    if (proposals.has(key) || (allowed === 0 && forfeits.length === 0)) return;
    penaltyTotal += allowed;
    proposals.set(key, {
      key,
      rule_id: ruleId,
      version_id: v.id,
      subject,
      amount_paise: allowed,
      at,
      reason: allowed < amount ? `${reason} (reduced to the deal's penalty cap)` : reason,
      forfeits,
    });
  };

  const linkedMilestoneValue = (v: DealVersion, deliverable: string): Paise => {
    let total = 0;
    for (const f of v.config.fixed) {
      const amounts = milestoneAmounts(f);
      for (const m of f.milestones)
        if ("deliverable" in m.trigger && m.trigger.deliverable === deliverable)
          total += amounts.get(m.id) ?? 0;
    }
    return total;
  };

  const lateDelivery = (deliverable: string, at: string) => {
    const due = dueAt.get(deliverable);
    if (!due) return;
    const v = versionAt(at);
    for (const p of v.config.penalties) {
      if (p.type !== "late_delivery") continue;
      const lateMs = Date.parse(at) - Date.parse(due) - p.grace_days * DAY;
      if (lateMs <= 0) continue;
      const daysLate = Math.ceil(lateMs / DAY);
      const base = linkedMilestoneValue(v, deliverable) || fixedValue(v.config);
      let amount =
        p.per_day.type === "amount"
          ? p.per_day.amount_paise * daysLate
          : mulDiv(base, toBps(p.per_day.pct) * daysLate, 10_000);
      if (p.cap)
        amount = Math.min(
          amount,
          p.cap.type === "amount" ? p.cap.amount_paise : pctOf(base, toBps(p.cap.pct)),
        );
      propose(v, p.id, deliverable, amount, at, `${p.label}: ${String(daysLate)} day(s) late`);
    }
  };

  // -------------------------------------------------------------------------------------------------------------
  // The loop
  // -------------------------------------------------------------------------------------------------------------
  const handleTimer = (t: Timer) => {
    switch (t.kind) {
      case "month_close": {
        const month = String(t.data.month);
        closeFloors("month", month, istMidnight(`${month}-01`), t.at);
        closeBonuses("month", month, istMidnight(`${month}-01`), t.at);
        break;
      }
      case "deal_close":
        if (closedWindows.has(PERIOD_DEAL)) break;
        closedWindows.add(PERIOD_DEAL);
        closeFloors("deal", PERIOD_DEAL, null, t.at);
        closeBonuses("deal", PERIOD_DEAL, null, t.at);
        break;
      case "campaign_close":
        if (closedWindows.has(PERIOD_CAMPAIGN)) break;
        closedWindows.add(PERIOD_CAMPAIGN);
        closeBonuses("campaign", PERIOD_CAMPAIGN, null, t.at);
        triggerFixed({ type: "campaign_close", at: t.at });
        break;
      case "bonus_dates": {
        const v = versionAt(addMs(t.at, -1));
        const b = v.config.bonuses.find((x) => x.id === t.data.bonus);
        if (b?.window.type === "dates")
          closeBonuses(
            "dates",
            `${b.window.from}..${b.window.to}`,
            istMidnight(b.window.from),
            t.at,
            b.id,
          );
        break;
      }
      case "date":
      case "after_live":
        fireByRef(String(t.data.ref), t.at);
        break;
      case "hold": {
        const u = units.get(String(t.data.unit));
        if (u?.active) confirmUnit(u, 1, 1);
        break;
      }
      case "retainer": {
        const v = versionAt(t.at);
        const f = v.config.fixed.find((x) => x.id === t.data.component);
        if (f?.retainer)
          addLine({
            key: `${v.id}:${f.id}:p${String(t.data.k)}:retainer`,
            type: "fixed_fee",
            direction: "credit",
            amount_paise: f.amount_paise,
            rule_id: f.id,
            version_id: v.id,
            subject: `${f.id}#${String(Number(t.data.k) + 1)}`,
            at: t.at,
            due_on: dueOn(t.at, 0, f.retainer.payment_terms_days),
            note: `${f.label}: period ${String(Number(t.data.k) + 1)} of ${String(f.retainer.periods)}`,
          });
        break;
      }
    }
  };

  const handleEvent = (ev: EngineEvent) => {
    switch (ev.type) {
      case "deliverable_due":
        dueAt.set(ev.deliverable, ev.due_at);
        break;
      case "deliverable_live":
        if (!liveAt.has(ev.deliverable)) {
          liveAt.set(ev.deliverable, ev.at);
          lateDelivery(ev.deliverable, ev.at);
        }
        break;
      case "deliverable_cancelled": {
        cancelledDeliverables.add(ev.deliverable);
        const v = versionAt(ev.at);
        for (const f of v.config.fixed)
          for (const m of f.milestones) {
            const ref = `${f.id}.${m.id}`;
            if (
              firedMilestones.has(ref) ||
              !("deliverable" in m.trigger) ||
              m.trigger.deliverable !== ev.deliverable
            )
              continue;
            if (m.on_cancel.type === "pay_pct")
              fireMilestone(
                v,
                f,
                m,
                ev.at,
                toBps(m.on_cancel.pct),
                `${f.label}: ${m.label} (part-paid after cancellation)`,
              );
            else firedMilestones.add(ref); // forfeited
          }
        for (const p of v.config.penalties)
          if (p.type === "missed_deliverable") {
            const forfeits = v.config.fixed.flatMap((f) =>
              f.milestones
                .filter(
                  (m) =>
                    "deliverable" in m.trigger &&
                    m.trigger.deliverable === ev.deliverable &&
                    m.on_cancel.type === "forfeit",
                )
                .map((m) => `${f.id}.${m.id}`),
            );
            propose(
              v,
              p.id,
              ev.deliverable,
              p.action.type === "fixed" ? p.action.amount_paise : 0,
              ev.at,
              p.label,
              forfeits,
            );
          }
        break;
      }
      case "metric":
        metricHistory.push({
          at: ev.at,
          deliverable: ev.deliverable,
          metric: ev.metric,
          value: ev.value,
        });
        break;
      case "lead":
        leads.set(ev.lead, ev);
        if (!ev.junk && !ev.duplicate)
          accrue(ev, `lead:${ev.lead}`, ev, ["flat_per_lead"], { lead: ev.lead });
        break;
      case "lead_qualified": {
        const l = leads.get(ev.lead);
        qualifiedAt.set(ev.lead, ev.at);
        if (l && !l.junk && !l.duplicate)
          accrue(ev, `qualified:${ev.lead}`, l, ["flat_per_qualified_lead"], { lead: ev.lead });
        break;
      }
      case "lead_applied": {
        const l = leads.get(ev.lead);
        appliedAt.set(ev.lead, ev.at);
        if (l && !l.junk && !l.duplicate)
          accrue(ev, `applied:${ev.lead}`, l, ["flat_per_application"], { lead: ev.lead });
        break;
      }
      case "lead_rejected":
        rejectedLeads.add(ev.lead);
        clawback((u) => u.lead === ev.lead && !u.enrollment, ev.at, "Lead rejected");
        break;
      case "enrolled":
        enrollments.set(ev.enrollment, ev);
        accrue(ev, `enrol:${ev.enrollment}`, ev, ["flat_per_enrollment"], {
          enrollment: ev.enrollment,
        });
        accrue(ev, `enrol:${ev.enrollment}`, ev, ["pct_of_programme_fee"], {
          enrollment: ev.enrollment,
          base: ev.fee_paise ?? 0,
        });
        accrue(ev, `enrol:${ev.enrollment}`, ev, ["pct_of_eduwit_commission"], {
          enrollment: ev.enrollment,
          expectedGross: ev.expected_commission_gross_paise,
        });
        break;
      case "enrollment_cancelled":
        cancelledEnrollments.set(ev.enrollment, ev.at);
        clawback((u) => u.enrollment === ev.enrollment, ev.at, "Enrolment cancelled or refunded");
        break;
      case "commission_received": {
        const enr = enrollments.get(ev.enrollment);
        // Percentage-of-commission rules without an expected amount accrue on the first receipt.
        if (enr && !cancelledEnrollments.has(ev.enrollment))
          accrue(ev, `enrol:${ev.enrollment}`, enr, ["pct_of_eduwit_commission"], {
            enrollment: ev.enrollment,
            expectedGross: ev.gross_paise,
          });
        for (const u of units.values()) {
          if (u.enrollment !== ev.enrollment || !u.active) continue;
          u.received += ev.gross_paise;
          // Correct a percentage-of-commission unit to the amount actually received, once it's final.
          if (
            u.basis === "pct_of_eduwit_commission" &&
            ev.full &&
            !u.adjusted &&
            u.expectedGross !== undefined &&
            u.received !== u.expectedGross
          ) {
            const r = versionRule(u);
            if (r && r.basis.type === "pct_of_eduwit_commission") {
              u.adjusted = true;
              const newBase =
                r.basis.base === "net_of_gst"
                  ? netOfGst(u.received, ctx.eduwit_gst_bps)
                  : u.received;
              const delta = pctOf(newBase, u.rate) - pctOf(u.base, u.rate);
              u.base = newBase;
              if (delta !== 0)
                postUnitLine(
                  versionAt(ev.at),
                  r,
                  u,
                  "receipt-adjust",
                  delta > 0 ? "credit" : "debit",
                  Math.abs(delta),
                  ev.at,
                  "Adjusted to the commission actually received",
                );
            }
          }
          if (u.confirmation !== "on_eduwit_commission_received") continue;
          if (ev.full) confirmUnit(u, 1, 1);
          else if (ctx.confirm_partial_receipts && u.expectedGross)
            confirmUnit(u, Math.min(u.received, u.expectedGross), u.expectedGross);
        }
        break;
      }
      case "campaign_ended":
        if (!closedWindows.has(PERIOD_CAMPAIGN)) {
          closedWindows.add(PERIOD_CAMPAIGN);
          closeBonuses("campaign", PERIOD_CAMPAIGN, null, addMs(ev.at, 1));
        }
        break;
      case "deal_completed":
        if (!closedWindows.has(PERIOD_DEAL)) {
          closedWindows.add(PERIOD_DEAL);
          closeFloors("deal", PERIOD_DEAL, null, addMs(ev.at, 1));
          closeBonuses("deal", PERIOD_DEAL, null, addMs(ev.at, 1));
        }
        break;
      case "leaderboard_rank":
        ranks.set(ev.window, ev.rank);
        break;
      case "disclosure_flag": {
        const v = versionAt(ev.at);
        for (const p of v.config.penalties)
          if (p.type === "disclosure")
            propose(v, p.id, ev.deliverable, p.amount_paise, ev.at, p.label);
        break;
      }
      case "breach": {
        const v = versionAt(ev.at);
        const earnedFixed = sum(
          [...lines.values()]
            .filter((l) => l.type === "milestone" || l.type === "fixed_fee")
            .map(signed),
        );
        for (const p of v.config.penalties)
          if (p.type === "breach_clawback")
            propose(v, p.id, ev.id, pctOf(earnedFixed, toBps(p.pct)), ev.at, p.label);
        break;
      }
      case "contract_signed":
      case "brief_acknowledged":
      case "concept_approved":
      case "draft_approved":
      case "manual_release":
        break;
    }
    triggerFixed(ev);
  };

  for (const ev of events) {
    if (compareIso(ev.at, asOf) > 0) break;
    for (let t = popTimer(ev.at); t; t = popTimer(ev.at)) handleTimer(t);
    handleEvent(ev);
  }
  for (let t = popTimer(null); t; t = popTimer(null)) handleTimer(t);

  const out = order.map((k) => lines.get(k)).filter((l): l is LedgerLine => !!l);
  const credits = sum(out.filter((l) => l.direction === "credit").map((l) => l.amount_paise));
  const debits = sum(out.filter((l) => l.direction === "debit").map((l) => l.amount_paise));
  const confirmedNet = sum(
    out.map((l) => (l.direction === "credit" ? l.confirmed_paise : -l.confirmed_paise)),
  );
  const lastVersion = versionAt(asOf);
  return {
    lines: out,
    proposals: [...proposals.values()],
    totals: {
      credits,
      debits,
      net: credits - debits,
      confirmed_net: confirmedNet,
      recouped: recoupBalance,
      non_cash: sum(lastVersion.config.non_cash.map((n) => n.value_paise)),
    },
  };
}
