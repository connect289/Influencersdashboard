import { describe, expect, it } from "vitest";
import {
  computeLedger,
  type DealVersion,
  type EngineContext,
  type EngineInput,
  type EngineResult,
  type LedgerLine,
} from "./engine";
import { engineEvent, type EngineEvent, type EngineEventInput } from "./events";
import { SYSTEM_PRESETS } from "./presets";
import { compConfig, type CompConfig, type CompConfigInput } from "./schema";

// ---------------------------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------------------------
type DistributiveOmit<T, K extends PropertyKey> = T extends unknown ? Omit<T, K> : never;

let seq = 0;
const ev = (x: DistributiveOmit<EngineEventInput, "id">): EngineEvent =>
  engineEvent.parse({ id: `e${String(++seq).padStart(4, "0")}`, ...x });
/** An IST instant: day of month (Nov 2026 by default) and hour. */
const at = (day: number, hour = 10, month = "2026-11") =>
  `${month}-${String(day).padStart(2, "0")}T${String(hour).padStart(2, "0")}:00:00+05:30`;

const CTX: EngineContext = {
  eduwit_gst_bps: 1800,
  hold_days: 30,
  refund_window_days: 30,
  penalty_cap_bps: 2000,
  confirm_partial_receipts: false,
};

// Configs are validated exactly as the deal builder validates them.
const cfg = (c: unknown): CompConfig => compConfig.parse(c);

function run(
  config: unknown,
  events: EngineEvent[],
  o: {
    as_of?: string;
    versions?: DealVersion[];
    deal?: Partial<EngineInput["deal"]>;
    ctx?: Partial<EngineContext>;
  } = {},
): EngineResult {
  return computeLedger({
    deal: { id: "deal-1", starts_on: "2026-11-01", ...o.deal },
    versions: o.versions ?? [{ id: "v1", effective_from: "2026-11-01T00:00:00+05:30", config: cfg(config) }],
    events,
    as_of: o.as_of ?? "2027-06-01T00:00:00+05:30",
    context: { ...CTX, ...o.ctx },
  });
}

const net = (lines: readonly LedgerLine[]) =>
  lines.reduce((s, l) => s + (l.direction === "credit" ? l.amount_paise : -l.amount_paise), 0);
const amounts = (lines: readonly LedgerLine[]) =>
  lines.map((l) => (l.direction === "credit" ? l.amount_paise : -l.amount_paise));
const ofType = (r: EngineResult, type: LedgerLine["type"]) => r.lines.filter((l) => l.type === type);
const keyed = (r: EngineResult, part: string) => r.lines.filter((l) => l.key.includes(part));

const flat = (id: string, amount: number, extra: Record<string, unknown> = {}) => ({
  id,
  label: id,
  basis: { type: "flat_per_enrollment" as const, amount_paise: amount },
  confirmation: { type: "immediate" as const },
  ...extra,
});
const enrol = (day: number, id: string, extra: Record<string, unknown> = {}, month = "2026-11") =>
  ev({ type: "enrolled", at: at(day, 10, month), lead: `lead-${id}`, enrollment: id, ...extra });
const ms = (id: string, pct: number, trigger: Record<string, unknown>, extra: Record<string, unknown> = {}) => ({
  id,
  label: id,
  share: { type: "pct" as const, pct },
  trigger,
  ...extra,
});

// ---------------------------------------------------------------------------------------------------------------
// The system presets (spec 6.2)
// ---------------------------------------------------------------------------------------------------------------
describe("system presets", () => {
  it("commission only: 10% of Eduwit's commission net of GST, confirmed when Eduwit is paid", () => {
    const events = [enrol(5, "en1", { expected_commission_gross_paise: 11_800_00 })];
    const before = run(SYSTEM_PRESETS.commission_only.config, events);
    expect(before.lines).toHaveLength(1);
    expect(before.lines[0]).toMatchObject({
      key: "v1:commission:commission:enrol:en1:accrue",
      type: "commission",
      direction: "credit",
      amount_paise: 1_000_00,
      confirmed_paise: 0,
      period: "2026-11",
    });
    const after = run(SYSTEM_PRESETS.commission_only.config, [
      ...events,
      ev({ type: "commission_received", at: at(20), enrollment: "en1", gross_paise: 11_800_00, full: true }),
    ]);
    expect(after.lines).toHaveLength(1);
    expect(after.lines[0]?.confirmed_paise).toBe(1_000_00);
    expect(after.totals).toMatchObject({ net: 1_000_00, confirmed_net: 1_000_00 });
  });

  it("fixed only: ₹15,000 paid half on signing and half when live, Net 7", () => {
    const r = run(SYSTEM_PRESETS.fixed_only.config, [
      ev({ type: "contract_signed", at: at(2) }),
      ev({ type: "deliverable_live", at: at(12), deliverable: "reel" }),
    ]);
    expect(r.lines.map((l) => [l.key, l.type, l.amount_paise, l.confirmed_paise, l.due_on])).toEqual([
      ["v1:fee:signing:milestone", "milestone", 7_500_00, 7_500_00, "2026-11-09"],
      ["v1:fee:live:milestone", "milestone", 7_500_00, 7_500_00, "2026-11-19"],
    ]);
    expect(r.totals.net).toBe(15_000_00);
  });

  it("fixed + commission: both components together", () => {
    const r = run(SYSTEM_PRESETS.fixed_plus_commission.config, [
      ev({ type: "contract_signed", at: at(2) }),
      enrol(8, "en1", { expected_commission_gross_paise: 23_600_00 }),
      ev({ type: "deliverable_live", at: at(12), deliverable: "reel" }),
    ]);
    expect(amounts(r.lines)).toEqual([7_500_00, 2_000_00, 7_500_00]);
    expect(r.totals.confirmed_net).toBe(15_000_00);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Commission bases
// ---------------------------------------------------------------------------------------------------------------
describe("commission bases", () => {
  it("flat per enrolment", () => {
    const r = run({ schema_version: 1, commission: [flat("per", 2_500_00)] }, [enrol(3, "a"), enrol(4, "b")]);
    expect(amounts(r.lines)).toEqual([2_500_00, 2_500_00]);
    expect(r.lines.every((l) => l.confirmed_paise === l.amount_paise)).toBe(true);
  });

  it("percentage of Eduwit's commission, gross including GST", () => {
    const r = run(
      {
        schema_version: 1,
        commission: [
          {
            id: "c",
            label: "c",
            basis: { type: "pct_of_eduwit_commission", pct: 10, base: "gross_incl_gst" },
            confirmation: { type: "immediate" },
          },
        ],
      },
      [enrol(3, "a", { expected_commission_gross_paise: 11_800_00 })],
    );
    expect(amounts(r.lines)).toEqual([1_180_00]);
  });

  it("percentage of the programme fee", () => {
    const r = run(
      {
        schema_version: 1,
        commission: [
          { id: "p", label: "p", basis: { type: "pct_of_programme_fee", pct: 2 }, confirmation: { type: "immediate" } },
        ],
      },
      [enrol(3, "a", { fee_paise: 1_50_000_00 })],
    );
    expect(amounts(r.lines)).toEqual([3_000_00]);
  });

  it("flat per lead, per qualified lead and per application; junk and duplicate leads earn nothing", () => {
    const rule = (id: string, type: string, amount: number) => ({
      id,
      label: id,
      basis: { type, amount_paise: amount },
      confirmation: { type: "immediate" },
    });
    const r = run(
      {
        schema_version: 1,
        commission: [
          rule("lead", "flat_per_lead", 50_00),
          rule("ql", "flat_per_qualified_lead", 200_00),
          rule("app", "flat_per_application", 300_00),
        ],
      },
      [
        ev({ type: "lead", at: at(2), lead: "L1" }),
        ev({ type: "lead", at: at(2, 11), lead: "L2", junk: true }),
        ev({ type: "lead", at: at(2, 12), lead: "L3", duplicate: true }),
        ev({ type: "lead_qualified", at: at(4), lead: "L1" }),
        ev({ type: "lead_qualified", at: at(4), lead: "L2" }),
        ev({ type: "lead_applied", at: at(6), lead: "L1" }),
      ],
    );
    expect(r.lines.map((l) => [l.rule_id, l.subject, l.amount_paise])).toEqual([
      ["lead", "lead:lead:L1", 50_00],
      ["ql", "ql:qualified:L1", 200_00],
      ["app", "app:applied:L1", 300_00],
    ]);
  });

  it("percentage of commission without an expected amount accrues on the first receipt", () => {
    const config = SYSTEM_PRESETS.commission_only.config;
    const enrolled = enrol(3, "a");
    expect(run(config, [enrolled]).lines).toEqual([]);
    const r = run(config, [
      enrolled,
      ev({ type: "commission_received", at: at(25), enrollment: "a", gross_paise: 11_800_00, full: true }),
    ]);
    expect(r.lines).toHaveLength(1);
    expect(r.lines[0]).toMatchObject({ amount_paise: 1_000_00, confirmed_paise: 1_000_00, at: at(25) });
  });

  it("a partial first receipt accrues on what arrived, and the final receipt tops it up", () => {
    const r = run(SYSTEM_PRESETS.commission_only.config, [
      enrol(3, "a"),
      ev({ type: "commission_received", at: at(10), enrollment: "a", gross_paise: 5_900_00, full: false }),
      ev({ type: "commission_received", at: at(20), enrollment: "a", gross_paise: 5_900_00, full: true }),
    ]);
    expect(r.lines.map((l) => [l.key.split(":").pop(), l.amount_paise, l.confirmed_paise])).toEqual([
      ["accrue", 500_00, 500_00],
      ["receipt-adjust", 500_00, 500_00],
    ]);
  });

  it("adjusts to the commission actually received when it differs from the expected amount", () => {
    const r = run(SYSTEM_PRESETS.commission_only.config, [
      enrol(3, "a", { expected_commission_gross_paise: 11_800_00 }),
      ev({ type: "commission_received", at: at(20), enrollment: "a", gross_paise: 9_440_00, full: true }),
    ]);
    expect(r.lines.map((l) => [l.direction, l.amount_paise, l.confirmed_paise])).toEqual([
      ["credit", 1_000_00, 1_000_00],
      ["debit", 200_00, 200_00],
    ]);
    expect(r.totals).toMatchObject({ net: 800_00, confirmed_net: 800_00 });
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Confirmation
// ---------------------------------------------------------------------------------------------------------------
describe("confirmation", () => {
  const partial = [
    enrol(3, "a", { expected_commission_gross_paise: 11_800_00 }),
    ev({ type: "commission_received", at: at(10), enrollment: "a", gross_paise: 5_900_00, full: false }),
  ];

  it("partial receipts confirm nothing by default", () => {
    expect(run(SYSTEM_PRESETS.commission_only.config, partial).totals.confirmed_net).toBe(0);
  });

  it("partial receipts confirm pro rata when the setting is on", () => {
    const opts = { ctx: { confirm_partial_receipts: true } };
    expect(run(SYSTEM_PRESETS.commission_only.config, partial, opts).totals.confirmed_net).toBe(500_00);
    const full = run(
      SYSTEM_PRESETS.commission_only.config,
      [...partial, ev({ type: "commission_received", at: at(20), enrollment: "a", gross_paise: 5_900_00, full: true })],
      opts,
    );
    expect(full.lines).toHaveLength(1);
    expect(full.totals.confirmed_net).toBe(1_000_00);
  });

  it("after hold days: unconfirmed until the hold ends (rule days, else the setting)", () => {
    const rule = (days?: number) => ({
      schema_version: 1 as const,
      commission: [flat("per", 1_000_00, { confirmation: { type: "after_hold_days", days } })],
    });
    const events = [enrol(1, "a")];
    expect(run(rule(14), events, { as_of: at(10) }).totals.confirmed_net).toBe(0);
    expect(run(rule(14), events, { as_of: at(15) }).totals.confirmed_net).toBe(1_000_00);
    expect(run(rule(), events, { as_of: at(30) }).totals.confirmed_net).toBe(0);
    expect(run(rule(), events, { as_of: at(1, 10, "2026-12") }).totals.confirmed_net).toBe(1_000_00);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Slabs
// ---------------------------------------------------------------------------------------------------------------
describe("slabs", () => {
  const tiers = [
    { from: 1, amount_paise: 1_000_00 },
    { from: 3, amount_paise: 2_000_00 },
  ];
  const slabbed = (mode: "marginal" | "retroactive", period: "deal" | "month" = "deal") => ({
    schema_version: 1 as const,
    commission: [flat("per", 1_000_00, { slabs: { period, mode, tiers } })],
  });

  it("marginal: only units from the threshold on get the higher rate", () => {
    const r = run(slabbed("marginal"), [enrol(1, "a"), enrol(2, "b"), enrol(3, "c"), enrol(4, "d")]);
    expect(amounts(r.lines)).toEqual([1_000_00, 1_000_00, 2_000_00, 2_000_00]);
  });

  it("retroactive: crossing the threshold tops up every earlier unit", () => {
    const r = run(slabbed("retroactive"), [enrol(1, "a"), enrol(2, "b"), enrol(3, "c")]);
    expect(r.lines.map((l) => [l.subject, l.key.split(":").pop(), l.amount_paise])).toEqual([
      ["per:enrol:a", "accrue", 1_000_00],
      ["per:enrol:b", "accrue", 1_000_00],
      ["per:enrol:c", "accrue", 2_000_00],
      ["per:enrol:a", "topup1", 1_000_00],
      ["per:enrol:b", "topup1", 1_000_00],
    ]);
    expect(r.totals.net).toBe(6_000_00);
  });

  it("retroactive: a clawback that drops below the threshold reverses the top-ups", () => {
    const r = run(slabbed("retroactive"), [
      enrol(1, "a"),
      enrol(2, "b"),
      enrol(3, "c"),
      ev({ type: "enrollment_cancelled", at: at(10), enrollment: "c" }),
    ]);
    expect(keyed(r, "topup2").map((l) => [l.subject, l.direction, l.amount_paise])).toEqual([
      ["per:enrol:a", "debit", 1_000_00],
      ["per:enrol:b", "debit", 1_000_00],
    ]);
    expect(ofType(r, "clawback").map((l) => l.amount_paise)).toEqual([2_000_00]);
    expect(r.totals.net).toBe(2_000_00);
  });

  it("monthly slabs restart each calendar month (IST)", () => {
    const r = run(slabbed("marginal", "month"), [
      enrol(1, "a"),
      enrol(2, "b"),
      enrol(3, "c"),
      enrol(1, "d", {}, "2026-12"),
    ]);
    expect(amounts(r.lines)).toEqual([1_000_00, 1_000_00, 2_000_00, 1_000_00]);
  });

  it("percentage tiers", () => {
    const r = run(
      {
        schema_version: 1,
        commission: [
          {
            id: "p",
            label: "p",
            basis: { type: "pct_of_programme_fee", pct: 2 },
            slabs: {
              period: "deal",
              mode: "marginal",
              tiers: [
                { from: 1, pct: 2 },
                { from: 2, pct: 3 },
              ],
            },
            confirmation: { type: "immediate" },
          },
        ],
      },
      [enrol(1, "a", { fee_paise: 1_00_000_00 }), enrol(2, "b", { fee_paise: 1_00_000_00 })],
    );
    expect(amounts(r.lines)).toEqual([2_000_00, 3_000_00]);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Caps, floors, recoupment
// ---------------------------------------------------------------------------------------------------------------
describe("caps", () => {
  const pctRule = (caps: Record<string, number>) => ({
    schema_version: 1 as const,
    commission: [
      {
        id: "p",
        label: "p",
        basis: { type: "pct_of_programme_fee" as const, pct: 10 },
        caps,
        confirmation: { type: "immediate" as const },
      },
    ],
  });

  it("per unit", () => {
    const r = run(pctRule({ per_unit_paise: 5_000_00 }), [enrol(1, "a", { fee_paise: 1_00_000_00 })]);
    expect(amounts(r.lines)).toEqual([5_000_00]);
  });

  it("per month and lifetime", () => {
    const fee = { fee_paise: 50_000_00 };
    const r = run(pctRule({ per_month_paise: 8_000_00, lifetime_paise: 12_000_00 }), [
      enrol(1, "a", fee),
      enrol(2, "b", fee),
      enrol(1, "c", fee, "2026-12"),
      enrol(2, "d", fee, "2026-12"),
    ]);
    expect(amounts(r.lines)).toEqual([5_000_00, 3_000_00, 4_000_00]);
  });

  it("a clawback frees room under the cap", () => {
    const fee = { fee_paise: 50_000_00 };
    const r = run(pctRule({ lifetime_paise: 5_000_00 }), [
      enrol(1, "a", fee),
      ev({ type: "enrollment_cancelled", at: at(5), enrollment: "a" }),
      enrol(6, "b", fee),
    ]);
    expect(amounts(r.lines)).toEqual([5_000_00, -5_000_00, 5_000_00]);
  });
});

describe("floors", () => {
  const config = {
    schema_version: 1 as const,
    commission: [flat("per", 2_000_00)],
    floors: [{ id: "min", label: "Minimum", amount_paise: 5_000_00, period: "month" as const }],
  };

  it("tops up a short month at month end, but not a month that beat the floor or one outside the deal", () => {
    const r = run(
      config,
      [enrol(5, "a"), enrol(1, "b", {}, "2026-12"), enrol(2, "c", {}, "2026-12"), enrol(3, "d", {}, "2026-12")],
      {
        deal: { ends_on: "2026-12-31" },
        as_of: "2027-03-01T00:00:00+05:30",
      },
    );
    const floors = r.lines.filter((l) => l.rule_id === "min");
    expect(floors.map((l) => [l.key, l.amount_paise, l.period])).toEqual([
      ["v1:min:2026-11:floor", 3_000_00, "2026-11"],
    ]);
  });

  it("does not top up a month that has not closed yet", () => {
    expect(run(config, [enrol(5, "a")], { as_of: at(30) }).lines.filter((l) => l.rule_id === "min")).toEqual([]);
  });

  it("a deal floor settles on deal completion", () => {
    const r = run(
      { ...config, floors: [{ id: "min", label: "Minimum", amount_paise: 10_000_00, period: "deal" as const }] },
      [enrol(5, "a"), ev({ type: "deal_completed", at: at(20) })],
    );
    expect(r.lines.filter((l) => l.rule_id === "min").map((l) => l.amount_paise)).toEqual([8_000_00]);
  });
});

describe("recoupment against fixed fees", () => {
  const config = (recoupment: CompConfigInput["recoupment"]) => ({
    schema_version: 1 as const,
    fixed: [
      {
        id: "advance",
        label: "Advance",
        amount_paise: 10_000_00,
        basis: "lump_sum" as const,
        milestones: [ms("sign", 100, { type: "on_contract_signed" })],
      },
    ],
    commission: [flat("per", 1_000_00)],
    recoupment,
  });
  const enrolments = (n: number) => Array.from({ length: n }, (_, i) => enrol(i + 2, `n${String(i + 1)}`));

  it("full: commission pays out only once it exceeds the advance", () => {
    const r = run(config({ mode: "full" }), [ev({ type: "contract_signed", at: at(1) }), ...enrolments(12)]);
    const recoup = r.lines.filter((l) => l.rule_id === "recoupment");
    expect(recoup).toHaveLength(10);
    expect(recoup.every((l) => l.direction === "debit" && l.amount_paise === 1_000_00)).toBe(true);
    expect(r.totals).toMatchObject({ credits: 22_000_00, debits: 10_000_00, net: 12_000_00, recouped: 10_000_00 });
  });

  it("partial %: only that share of the advance is recouped", () => {
    const r = run(config({ mode: "partial", pct: 50 }), [ev({ type: "contract_signed", at: at(1) }), ...enrolments(7)]);
    expect(r.totals.recouped).toBe(5_000_00);
    expect(r.totals.net).toBe(10_000_00 + 7_000_00 - 5_000_00);
  });

  it("clawbacks release recoupment once commission falls below the advance", () => {
    const r = run(config({ mode: "full" }), [
      ev({ type: "contract_signed", at: at(1) }),
      ...enrolments(10),
      ev({ type: "enrollment_cancelled", at: at(20), enrollment: "n1" }),
    ]);
    const release = r.lines.filter((l) => l.rule_id === "recoupment" && l.direction === "credit");
    expect(release.map((l) => l.amount_paise)).toEqual([1_000_00]);
    expect(r.totals).toMatchObject({ recouped: 9_000_00, net: 10_000_00 });
  });

  it("none: commission is paid on top of the fixed fee", () => {
    const r = run(config({ mode: "none" }), [ev({ type: "contract_signed", at: at(1) }), ...enrolments(3)]);
    expect(r.totals.net).toBe(13_000_00);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Milestones
// ---------------------------------------------------------------------------------------------------------------
describe("milestones per trigger", () => {
  const config = {
    schema_version: 1 as const,
    fixed: [
      {
        id: "fee",
        label: "Fee",
        amount_paise: 10_000_00,
        basis: "lump_sum" as const,
        milestones: [
          ms("m1", 10, { type: "on_contract_signed" }),
          ms("m2", 10, { type: "on_brief_acknowledged" }),
          ms("m3", 10, { type: "on_concept_approved", deliverable: "reel" }),
          ms("m4", 10, { type: "on_draft_approved", deliverable: "reel" }),
          ms("m5", 10, { type: "on_deliverable_live", deliverable: "reel" }),
          ms("m6", 10, { type: "after_n_days_live", days: 7, deliverable: "reel" }),
          ms("m7", 10, { type: "on_metric_threshold", metric: "views", threshold: 10_000, deliverable: "reel" }),
          ms("m8", 10, { type: "on_campaign_end" }),
          ms("m9", 10, { type: "on_specific_date", date: "2026-12-15" }),
          ms("m10", 10, { type: "manual_release" }),
        ],
      },
    ],
  };
  const events = [
    ev({ type: "contract_signed", at: at(2) }),
    ev({ type: "brief_acknowledged", at: at(3) }),
    ev({ type: "concept_approved", at: at(4), deliverable: "story" }),
    ev({ type: "concept_approved", at: at(5), deliverable: "reel" }),
    ev({ type: "draft_approved", at: at(6), deliverable: "reel" }),
    ev({ type: "deliverable_live", at: at(8), deliverable: "reel" }),
    ev({ type: "metric", at: at(9), deliverable: "reel", metric: "views", value: 4_000 }),
    ev({ type: "metric", at: at(12), deliverable: "reel", metric: "views", value: 12_000 }),
    ev({ type: "campaign_ended", at: at(30) }),
    ev({ type: "manual_release", at: at(20, 10, "2026-12"), milestone: "fee.m10" }),
  ];

  it("fires each milestone on its own trigger, at the right time", () => {
    const r = run(config, events, { as_of: at(1, 10, "2026-12") });
    expect(r.lines.map((l) => [l.subject, l.at])).toEqual([
      ["fee.m1", at(2)],
      ["fee.m2", at(3)],
      ["fee.m3", at(5)],
      ["fee.m4", at(6)],
      ["fee.m5", at(8)],
      ["fee.m7", at(12)],
      ["fee.m6", "2026-11-15T04:30:00.000Z"],
      ["fee.m8", at(30)],
    ]);
    expect(r.lines.every((l) => l.amount_paise === 1_000_00 && l.type === "milestone")).toBe(true);
  });

  it("specific dates and manual releases fire when reached", () => {
    const r = run(config, events, { as_of: "2027-01-01T00:00:00+05:30" });
    expect(r.lines.map((l) => l.subject).slice(-2)).toEqual(["fee.m9", "fee.m10"]);
    expect(r.totals.net).toBe(10_000_00);
  });

  it("a lead-count threshold ignores junk leads", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [
          {
            id: "fee",
            label: "Fee",
            amount_paise: 5_000_00,
            basis: "lump_sum",
            milestones: [ms("leads", 100, { type: "on_metric_threshold", metric: "leads", threshold: 2 })],
          },
        ],
      },
      [
        ev({ type: "lead", at: at(2), lead: "a" }),
        ev({ type: "lead", at: at(3), lead: "b", junk: true }),
        ev({ type: "lead", at: at(4), lead: "c" }),
      ],
    );
    expect(r.lines.map((l) => l.at)).toEqual([at(4)]);
  });

  it("the campaign end date fires end-of-campaign milestones without an explicit event", () => {
    const r = run(config, [], { deal: { campaign_ends_on: "2026-11-30" }, as_of: at(5, 10, "2026-12") });
    expect(r.lines.map((l) => [l.subject, l.at])).toEqual([["fee.m8", "2026-11-30T18:30:00.000Z"]]);
  });

  it("due dates add the offset and payment terms to the trigger date", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [
          {
            id: "fee",
            label: "Fee",
            amount_paise: 1_000_00,
            basis: "lump_sum",
            milestones: [ms("m", 100, { type: "on_contract_signed" }, { due_offset_days: 3, payment_terms_days: 7 })],
          },
        ],
      },
      [ev({ type: "contract_signed", at: at(28) })],
    );
    expect(r.lines[0]?.due_on).toBe("2026-12-08");
  });

  it("amount-based milestones pay their exact amounts", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [
          {
            id: "fee",
            label: "Fee",
            amount_paise: 3_000_00,
            basis: "per_deliverable",
            units: 2,
            milestones: [
              {
                id: "a",
                label: "a",
                share: { type: "amount", amount_paise: 1_000_00 },
                trigger: { type: "on_contract_signed" },
              },
              {
                id: "b",
                label: "b",
                share: { type: "amount", amount_paise: 5_000_00 },
                trigger: { type: "on_deliverable_live" },
              },
            ],
          },
        ],
      },
      [ev({ type: "contract_signed", at: at(2) }), ev({ type: "deliverable_live", at: at(9), deliverable: "x" })],
    );
    expect(amounts(r.lines)).toEqual([1_000_00, 5_000_00]);
  });

  it("deliverable cancellation forfeits a milestone or pays the agreed share, and proposes the missed-deliverable rule", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [
          {
            id: "fee",
            label: "Fee",
            amount_paise: 10_000_00,
            basis: "lump_sum",
            milestones: [
              ms("draft", 40, { type: "on_draft_approved", deliverable: "reel" }),
              ms(
                "live",
                60,
                { type: "on_deliverable_live", deliverable: "reel" },
                { on_cancel: { type: "pay_pct", pct: 25 } },
              ),
            ],
          },
        ],
        penalties: [
          { id: "missed", type: "missed_deliverable", label: "Missed", action: { type: "forfeit_milestones" } },
        ],
      },
      [
        ev({ type: "deliverable_cancelled", at: at(10), deliverable: "reel" }),
        ev({ type: "draft_approved", at: at(11), deliverable: "reel" }),
      ],
    );
    expect(r.lines.map((l) => [l.subject, l.amount_paise])).toEqual([["fee.live", 1_500_00]]);
    expect(r.proposals).toEqual([
      expect.objectContaining({ rule_id: "missed", subject: "reel", amount_paise: 0, forfeits: ["fee.draft"] }),
    ]);
  });

  it("retainers pay each period on its schedule", () => {
    const retainer = (pay_on: "period_start" | "period_end") => ({
      schema_version: 1 as const,
      fixed: [
        {
          id: "ret",
          label: "Retainer",
          amount_paise: 20_000_00,
          basis: "retainer" as const,
          retainer: { periods: 3, every: "month" as const, pay_on, payment_terms_days: 5 },
        },
      ],
    });
    const asOf = { as_of: at(15, 10, "2027-01") };
    expect(run(retainer("period_end"), [], asOf).lines.map((l) => [l.subject, l.due_on])).toEqual([
      ["ret#1", "2026-12-06"],
      ["ret#2", "2027-01-06"],
    ]);
    expect(run(retainer("period_start"), [], asOf).lines.map((l) => l.subject)).toEqual(["ret#1", "ret#2", "ret#3"]);
  });

  it("additional fees post with their own entry types", () => {
    const r = run(
      {
        schema_version: 1,
        fees: [
          { id: "usage", kind: "usage_rights", label: "Usage 90 days", amount_paise: 3_000_00, duration_days: 90 },
          {
            id: "excl",
            kind: "exclusivity",
            label: "Exclusivity",
            amount_paise: 2_000_00,
            trigger: { type: "after_n_days_live", days: 3 },
          },
          {
            id: "travel",
            kind: "reimbursement",
            label: "Travel",
            amount_paise: 800_00,
            trigger: { type: "manual_release" },
          },
        ],
      },
      [ev({ type: "contract_signed", at: at(2) }), ev({ type: "deliverable_live", at: at(5), deliverable: "reel" })],
    );
    expect(r.lines.map((l) => [l.type, l.amount_paise])).toEqual([
      ["usage_fee", 3_000_00],
      ["exclusivity_fee", 2_000_00],
    ]);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Clawbacks
// ---------------------------------------------------------------------------------------------------------------
describe("clawbacks", () => {
  const leadRule = {
    schema_version: 1 as const,
    commission: [
      {
        id: "lead",
        label: "Per lead",
        basis: { type: "flat_per_lead" as const, amount_paise: 100_00 },
        confirmation: { type: "immediate" as const },
        clawback_window_days: 10,
      },
    ],
  };

  it("a lead rejected inside the window is clawed back", () => {
    const r = run(leadRule, [
      ev({ type: "lead", at: at(1), lead: "L" }),
      ev({ type: "lead_rejected", at: at(5), lead: "L" }),
    ]);
    expect(r.lines.map((l) => [l.type, l.direction, l.amount_paise])).toEqual([
      ["commission", "credit", 100_00],
      ["clawback", "debit", 100_00],
    ]);
    expect(r.totals.net).toBe(0);
  });

  it("a lead rejected outside the window is not", () => {
    const r = run(leadRule, [
      ev({ type: "lead", at: at(1), lead: "L" }),
      ev({ type: "lead_rejected", at: at(20), lead: "L" }),
    ]);
    expect(ofType(r, "clawback")).toEqual([]);
  });

  it("an enrolment cancelled inside the default refund window is clawed back; outside it is not", () => {
    const config = { schema_version: 1 as const, commission: [flat("per", 1_000_00)] };
    const inside = run(config, [enrol(1, "a"), ev({ type: "enrollment_cancelled", at: at(30, 9), enrollment: "a" })]);
    expect(ofType(inside, "clawback").map((l) => l.amount_paise)).toEqual([1_000_00]);
    const outside = run(config, [
      enrol(1, "a"),
      ev({ type: "enrollment_cancelled", at: at(2, 10, "2026-12"), enrollment: "a" }),
    ]);
    expect(ofType(outside, "clawback")).toEqual([]);
  });

  it("clawing back an unconfirmed unit settles it: confirmed amounts net to zero", () => {
    const r = run(SYSTEM_PRESETS.commission_only.config, [
      enrol(1, "a", { expected_commission_gross_paise: 11_800_00 }),
      ev({ type: "enrollment_cancelled", at: at(5), enrollment: "a" }),
    ]);
    expect(r.totals).toMatchObject({ net: 0, confirmed_net: 0 });
    expect(r.lines.every((l) => l.confirmed_paise === l.amount_paise)).toBe(true);
  });

  it("a rejected lead claws back its qualified-lead and application units too, and only once", () => {
    const r = run(
      {
        schema_version: 1,
        commission: [
          {
            id: "ql",
            label: "ql",
            basis: { type: "flat_per_qualified_lead", amount_paise: 200_00 },
            confirmation: { type: "immediate" },
          },
          {
            id: "app",
            label: "app",
            basis: { type: "flat_per_application", amount_paise: 300_00 },
            confirmation: { type: "immediate" },
          },
        ],
      },
      [
        ev({ type: "lead", at: at(1), lead: "L" }),
        ev({ type: "lead_qualified", at: at(2), lead: "L" }),
        ev({ type: "lead_applied", at: at(3), lead: "L" }),
        ev({ type: "lead_rejected", at: at(4), lead: "L" }),
        ev({ type: "lead_rejected", at: at(5), lead: "L" }),
      ],
    );
    expect(ofType(r, "clawback").map((l) => l.amount_paise)).toEqual([200_00, 300_00]);
    expect(r.totals.net).toBe(0);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Scope and effective dates
// ---------------------------------------------------------------------------------------------------------------
describe("scope and effective dates", () => {
  it("matches programmes, universities, levels, links and deliverables", () => {
    const r = run(
      {
        schema_version: 1,
        commission: [
          flat("prog", 100_00, { scope: { type: "programmes", ids: [101] } }),
          flat("level", 200_00, { scope: { type: "levels", levels: ["PG"] } }),
          flat("link", 300_00, { scope: { type: "links", codes: ["ABC"] } }),
          flat("uni", 400_00, { scope: { type: "universities", ids: [7] } }),
          flat("deliv", 500_00, { scope: { type: "deliverables", ids: ["reel"] } }),
        ],
      },
      [enrol(1, "a", { programme_id: 101, level: "pg", link: "ABC", university_id: 8, deliverable: "story" })],
    );
    expect(r.lines.map((l) => l.rule_id)).toEqual(["prog", "level", "link"]);
  });

  it("applies a rule only between its effective dates (IST)", () => {
    const r = run(
      {
        schema_version: 1,
        commission: [flat("per", 100_00, { effective_from: "2026-11-15", effective_to: "2026-11-30" })],
      },
      [enrol(10, "a"), enrol(20, "b"), enrol(30, "c", {}), enrol(1, "d", {}, "2026-12")],
    );
    expect(r.lines.map((l) => l.subject)).toEqual(["per:enrol:b", "per:enrol:c"]);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Amendments
// ---------------------------------------------------------------------------------------------------------------
describe("amendments mid-period", () => {
  const v = (id: string, from: string, c: unknown): DealVersion => ({
    id,
    effective_from: from,
    config: cfg(c),
  });

  it("events use the version in force at their time; earlier lines keep their version key", () => {
    const versions = [
      v("v1", "2026-11-01T00:00:00+05:30", { schema_version: 1, commission: [flat("per", 1_000_00)] }),
      v("v2", "2026-11-16T00:00:00+05:30", { schema_version: 1, commission: [flat("per", 2_000_00)] }),
    ];
    const r = run({ schema_version: 1 }, [enrol(10, "a"), enrol(20, "b")], { versions });
    expect(r.lines.map((l) => [l.key, l.amount_paise])).toEqual([
      ["v1:per:per:enrol:a:accrue", 1_000_00],
      ["v2:per:per:enrol:b:accrue", 2_000_00],
    ]);
  });

  it("milestones already paid are not paid again after an amendment", () => {
    const fee = (amount: number) => ({
      schema_version: 1,
      fixed: [
        {
          id: "fee",
          label: "Fee",
          amount_paise: amount,
          basis: "lump_sum",
          milestones: [ms("sign", 50, { type: "on_contract_signed" }), ms("live", 50, { type: "on_deliverable_live" })],
        },
      ],
    });
    const versions = [
      v("v1", "2026-11-01T00:00:00+05:30", fee(10_000_00)),
      v("v2", "2026-11-10T00:00:00+05:30", fee(12_000_00)),
    ];
    const r = run(
      { schema_version: 1 },
      [
        ev({ type: "contract_signed", at: at(2) }),
        ev({ type: "contract_signed", at: at(11) }),
        ev({ type: "deliverable_live", at: at(15), deliverable: "x" }),
      ],
      { versions },
    );
    expect(r.lines.map((l) => [l.key, l.amount_paise])).toEqual([
      ["v1:fee:sign:milestone", 5_000_00],
      ["v2:fee:live:milestone", 6_000_00],
    ]);
  });

  it("slab counts carry across versions of the same rule", () => {
    const tiers = [
      { from: 1, amount_paise: 1_000_00 },
      { from: 2, amount_paise: 3_000_00 },
    ];
    const versions = [
      v("v1", "2026-11-01T00:00:00+05:30", {
        schema_version: 1,
        commission: [flat("per", 1_000_00, { slabs: { period: "deal", mode: "marginal", tiers } })],
      }),
      v("v2", "2026-11-16T00:00:00+05:30", {
        schema_version: 1,
        commission: [flat("per", 1_000_00, { slabs: { period: "deal", mode: "marginal", tiers } })],
      }),
    ];
    expect(amounts(run({ schema_version: 1 }, [enrol(10, "a"), enrol(20, "b")], { versions }).lines)).toEqual([
      1_000_00, 3_000_00,
    ]);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Bonuses
// ---------------------------------------------------------------------------------------------------------------
describe("bonuses", () => {
  const bonus = (b: Record<string, unknown>) => ({ id: "b", label: "Bonus", ...b });

  it("monthly, repeating: each month that qualifies", () => {
    const config = {
      schema_version: 1 as const,
      bonuses: [
        bonus({
          conditions: { op: "and", items: [{ metric: "enrollments", comparator: "gte", value: 2 }] },
          window: { type: "month" },
          amount: { type: "fixed", amount_paise: 500_00 },
          repeat: "every",
        }),
      ],
    };
    const events = [
      enrol(1, "a"),
      enrol(2, "b"),
      enrol(1, "c", {}, "2026-12"),
      enrol(1, "d", {}, "2027-01"),
      enrol(2, "e", {}, "2027-01"),
      ev({ type: "enrollment_cancelled", at: at(3, 10, "2027-01"), enrollment: "e" }),
    ];
    const r = run(config, events, { as_of: "2027-02-02T00:00:00+05:30" });
    expect(r.lines.map((l) => [l.key, l.amount_paise])).toEqual([["v1:b:2026-11:bonus", 500_00]]);
  });

  it("once: only the first qualifying window", () => {
    const config = {
      schema_version: 1 as const,
      bonuses: [
        bonus({
          conditions: { op: "and", items: [{ metric: "enrollments", comparator: "gte", value: 1 }] },
          window: { type: "month" },
          amount: { type: "fixed", amount_paise: 500_00 },
        }),
      ],
    };
    const r = run(config, [enrol(1, "a"), enrol(1, "b", {}, "2026-12")], { as_of: "2027-02-01T00:00:00+05:30" });
    expect(r.lines.map((l) => l.subject)).toEqual(["2026-11"]);
  });

  it("percentage of the fixed fee on a deal-window views target", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [
          {
            id: "fee",
            label: "Fee",
            amount_paise: 10_000_00,
            basis: "lump_sum",
            milestones: [ms("s", 100, { type: "on_contract_signed" })],
          },
        ],
        bonuses: [
          bonus({
            conditions: { op: "and", items: [{ metric: "views", comparator: "gte", value: 100_000 }] },
            window: { type: "deal" },
            amount: { type: "pct_of_fixed", pct: 10 },
          }),
        ],
      },
      [
        ev({ type: "contract_signed", at: at(1) }),
        ev({ type: "metric", at: at(10), deliverable: "reel", metric: "views", value: 60_000 }),
        ev({ type: "metric", at: at(11), deliverable: "short", metric: "views", value: 50_000 }),
        ev({ type: "deal_completed", at: at(20) }),
      ],
    );
    expect(ofType(r, "bonus").map((l) => l.amount_paise)).toEqual([1_000_00]);
  });

  it("percentage of the month's commission, and views counted as the month's increase", () => {
    const r = run(
      {
        schema_version: 1,
        commission: [flat("per", 1_000_00)],
        bonuses: [
          bonus({
            conditions: { op: "and", items: [{ metric: "views", comparator: "gte", value: 7_000 }] },
            window: { type: "month" },
            amount: { type: "pct_of_commission", pct: 20 },
            repeat: "every",
          }),
        ],
      },
      [
        ev({ type: "metric", at: at(30), deliverable: "reel", metric: "views", value: 5_000 }),
        enrol(5, "a", {}, "2026-12"),
        enrol(6, "b", {}, "2026-12"),
        ev({ type: "metric", at: at(31, 10, "2026-12"), deliverable: "reel", metric: "views", value: 12_000 }),
      ],
      { as_of: "2027-01-02T00:00:00+05:30" },
    );
    expect(ofType(r, "bonus").map((l) => [l.subject, l.amount_paise])).toEqual([["2026-12", 400_00]]);
  });

  it("on time: every deliverable due in the window went live by its due date", () => {
    const config = {
      schema_version: 1 as const,
      bonuses: [
        bonus({
          conditions: { op: "and", items: [{ metric: "on_time_all", comparator: "gte", value: 1 }] },
          window: { type: "campaign" },
          amount: { type: "fixed", amount_paise: 1_000_00 },
        }),
      ],
    };
    const due = [
      ev({ type: "deliverable_due", at: at(1), deliverable: "a", due_at: at(10, 18) }),
      ev({ type: "deliverable_due", at: at(1), deliverable: "b", due_at: at(12, 18) }),
    ];
    const onTime = run(config, [
      ...due,
      ev({ type: "deliverable_live", at: at(9), deliverable: "a" }),
      ev({ type: "deliverable_live", at: at(12), deliverable: "b" }),
      ev({ type: "campaign_ended", at: at(20) }),
    ]);
    expect(ofType(onTime, "bonus")).toHaveLength(1);
    const late = run(config, [
      ...due,
      ev({ type: "deliverable_live", at: at(9), deliverable: "a" }),
      ev({ type: "deliverable_live", at: at(13), deliverable: "b" }),
      ev({ type: "campaign_ended", at: at(20) }),
    ]);
    expect(ofType(late, "bonus")).toHaveLength(0);
  });

  it("leaderboard rank, a dated window, and either-or conditions", () => {
    const r = run(
      {
        schema_version: 1,
        bonuses: [
          bonus({
            id: "rank",
            conditions: { op: "and", items: [{ metric: "rank", comparator: "lte", value: 3 }] },
            window: { type: "month" },
            amount: { type: "fixed", amount_paise: 2_000_00 },
            repeat: "every",
          }),
          bonus({
            id: "sprint",
            conditions: {
              op: "or",
              items: [
                { metric: "enrollments", comparator: "gte", value: 5 },
                { metric: "leads", comparator: "gte", value: 2 },
              ],
            },
            window: { type: "dates", from: "2026-11-10", to: "2026-11-20" },
            amount: { type: "fixed", amount_paise: 700_00 },
          }),
        ],
      },
      [
        ev({ type: "lead", at: at(9), lead: "x" }),
        ev({ type: "lead", at: at(12), lead: "y" }),
        ev({ type: "lead", at: at(15), lead: "z" }),
        ev({ type: "leaderboard_rank", at: at(30, 20), window: "2026-11", rank: 2 }),
        ev({ type: "leaderboard_rank", at: at(31, 20, "2026-12"), window: "2026-12", rank: 9 }),
      ],
      { as_of: "2027-01-05T00:00:00+05:30" },
    );
    expect(ofType(r, "bonus").map((l) => [l.rule_id, l.subject, l.at])).toEqual([
      ["sprint", "2026-11-10..2026-11-20", "2026-11-20T18:29:59.999Z"],
      ["rank", "2026-11", "2026-11-30T18:29:59.999Z"],
    ]);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Penalties (proposals only)
// ---------------------------------------------------------------------------------------------------------------
describe("penalties", () => {
  const fee = {
    id: "fee",
    label: "Fee",
    amount_paise: 15_000_00,
    basis: "lump_sum" as const,
    milestones: [
      ms("s", 50, { type: "on_contract_signed" }),
      ms("live", 50, { type: "on_deliverable_live", deliverable: "reel" }),
    ],
  };

  it("late delivery: per day after the grace period, capped, and never posted to the ledger", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [fee],
        penalties: [
          {
            id: "late",
            type: "late_delivery",
            label: "Late",
            grace_days: 1,
            per_day: { type: "amount", amount_paise: 500_00 },
            cap: { type: "amount", amount_paise: 800_00 },
          },
        ],
      },
      [
        ev({ type: "deliverable_due", at: at(1), deliverable: "reel", due_at: at(10, 18) }),
        ev({ type: "deliverable_live", at: at(13), deliverable: "reel" }),
      ],
    );
    expect(r.proposals).toEqual([expect.objectContaining({ rule_id: "late", subject: "reel", amount_paise: 800_00 })]);
    expect(r.lines.some((l) => l.rule_id === "late")).toBe(false);
  });

  it("late delivery counts whole days after the grace period", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [fee],
        penalties: [
          {
            id: "late",
            type: "late_delivery",
            label: "Late",
            grace_days: 1,
            per_day: { type: "amount", amount_paise: 500_00 },
          },
        ],
      },
      [
        ev({ type: "deliverable_due", at: at(1), deliverable: "reel", due_at: at(10, 18) }),
        ev({ type: "deliverable_live", at: at(13), deliverable: "reel" }),
      ],
    );
    expect(r.proposals[0]?.amount_paise).toBe(1_000_00); // 2 days 16 hours late, 1 day grace → 2 days
  });

  it("late delivery as a percentage per day of the linked milestone", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [fee],
        penalties: [{ id: "late", type: "late_delivery", label: "Late", per_day: { type: "pct", pct: 1 } }],
      },
      [
        ev({ type: "deliverable_due", at: at(1), deliverable: "reel", due_at: at(10, 10) }),
        ev({ type: "deliverable_live", at: at(13, 10), deliverable: "reel" }),
      ],
    );
    expect(r.proposals[0]?.amount_paise).toBe(225_00); // 3 days × 1% of ₹7,500
  });

  it("on time: no proposal", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [fee],
        penalties: [{ id: "late", type: "late_delivery", label: "Late", per_day: { type: "pct", pct: 1 } }],
      },
      [
        ev({ type: "deliverable_due", at: at(1), deliverable: "reel", due_at: at(10, 18) }),
        ev({ type: "deliverable_live", at: at(10, 17), deliverable: "reel" }),
      ],
    );
    expect(r.proposals).toEqual([]);
  });

  it("disclosure penalties are limited by the deal's penalty cap", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [fee],
        penalties: [{ id: "disc", type: "disclosure", label: "Disclosure", amount_paise: 5_000_00 }],
      },
      [ev({ type: "disclosure_flag", at: at(5), deliverable: "reel" })],
    );
    expect(r.proposals[0]).toMatchObject({ amount_paise: 3_000_00 });
    expect(r.proposals[0]?.reason).toContain("cap");
  });

  it("breach claws back a share of fixed fees already earned", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [fee],
        penalties: [{ id: "breach", type: "breach_clawback", label: "Breach", pct: 50 }],
      },
      [ev({ type: "contract_signed", at: at(1) }), ev({ type: "breach", at: at(5) })],
      { ctx: { penalty_cap_bps: 10_000 } },
    );
    expect(r.proposals[0]).toMatchObject({ rule_id: "breach", amount_paise: 3_750_00 });
  });

  it("the cap applies to all penalties of the deal together", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [fee],
        penalties: [
          { id: "disc", type: "disclosure", label: "Disclosure", amount_paise: 2_000_00 },
          {
            id: "missed",
            type: "missed_deliverable",
            label: "Missed",
            action: { type: "fixed", amount_paise: 2_000_00 },
          },
        ],
      },
      [
        ev({ type: "disclosure_flag", at: at(5), deliverable: "reel" }),
        ev({ type: "deliverable_cancelled", at: at(6), deliverable: "reel" }),
      ],
    );
    expect(r.proposals.map((p) => p.amount_paise)).toEqual([2_000_00, 1_000_00]);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Rounding and determinism
// ---------------------------------------------------------------------------------------------------------------
describe("rounding", () => {
  const pctRule = (pct: number) => ({
    schema_version: 1 as const,
    commission: [
      {
        id: "p",
        label: "p",
        basis: { type: "pct_of_programme_fee" as const, pct },
        confirmation: { type: "immediate" as const },
      },
    ],
  });

  it("rounds half to even once per line", () => {
    expect(
      amounts(run(pctRule(2.5), [enrol(1, "a", { fee_paise: 100 }), enrol(2, "b", { fee_paise: 300 })]).lines),
    ).toEqual([2, 8]);
    expect(amounts(run(pctRule(7.5), [enrol(1, "a", { fee_paise: 33_333 })]).lines)).toEqual([2_500]);
  });

  it("percentage milestones always add up to the fee exactly", () => {
    const r = run(
      {
        schema_version: 1,
        fixed: [
          {
            id: "fee",
            label: "Fee",
            amount_paise: 10_001,
            basis: "lump_sum",
            milestones: [
              ms("a", 33.33, { type: "on_contract_signed" }),
              ms("b", 33.33, { type: "on_brief_acknowledged" }),
              ms("c", 33.34, { type: "on_deliverable_live" }),
            ],
          },
        ],
      },
      [
        ev({ type: "contract_signed", at: at(1) }),
        ev({ type: "brief_acknowledged", at: at(2) }),
        ev({ type: "deliverable_live", at: at(3), deliverable: "x" }),
      ],
    );
    expect(net(r.lines)).toBe(10_001);
    for (const l of r.lines) expect(Math.abs(l.amount_paise - 3_334)).toBeLessThanOrEqual(1);
  });
});

describe("determinism", () => {
  const config = {
    schema_version: 1 as const,
    fixed: [
      {
        id: "fee",
        label: "Fee",
        amount_paise: 10_000_00,
        basis: "lump_sum" as const,
        milestones: [ms("s", 100, { type: "on_contract_signed" })],
      },
    ],
    commission: [
      flat("per", 1_000_00, {
        slabs: {
          period: "month",
          mode: "retroactive",
          tiers: [
            { from: 1, amount_paise: 1_000_00 },
            { from: 2, amount_paise: 1_500_00 },
          ],
        },
      }),
    ],
    recoupment: { mode: "partial" as const, pct: 10 },
  };
  const events = [
    ev({ type: "contract_signed", at: at(1) }),
    enrol(2, "a"),
    enrol(3, "b"),
    ev({ type: "enrollment_cancelled", at: at(4), enrollment: "a" }),
    enrol(5, "c"),
  ];

  it("the same inputs in any order give the same ledger", () => {
    const a = run(config, events);
    const b = run(config, [...events].reverse());
    expect(b).toEqual(a);
    expect(run(config, events)).toEqual(a);
  });

  it("keys are unique and stable as time moves on", () => {
    const early = run(config, events, { as_of: at(3, 12) });
    const late = run(config, events);
    expect(new Set(late.lines.map((l) => l.key)).size).toBe(late.lines.length);
    const lateByKey = new Map(late.lines.map((l) => [l.key, l]));
    for (const l of early.lines) expect(lateByKey.get(l.key)?.amount_paise).toBe(l.amount_paise);
  });

  it("ignores events after as_of", () => {
    expect(run(config, events, { as_of: at(1, 12) }).lines.map((l) => l.subject)).toEqual(["fee.s"]);
  });

  it("reports non-cash value separately from money", () => {
    const r = run({ schema_version: 1, non_cash: [{ id: "laptop", label: "Laptop", value_paise: 60_000_00 }] }, []);
    expect(r.totals).toMatchObject({ net: 0, non_cash: 60_000_00 });
  });

  it("needs at least one version", () => {
    expect(() =>
      computeLedger({
        deal: { id: "d", starts_on: "2026-11-01" },
        versions: [],
        events: [],
        as_of: at(1),
        context: CTX,
      }),
    ).toThrow();
  });
});
