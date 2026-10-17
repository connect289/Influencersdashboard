import { describe, expect, it } from "vitest";
import type { EngineContext } from "./engine";
import { SYSTEM_PRESETS } from "./presets";
import { compConfig } from "./schema";
import { configDeliverables, forCreator, scenario, scenarioEvents, simulate, type ScenarioInput } from "./simulator";
import { DEFAULT_TDS_SECTIONS } from "./tax";

const context: EngineContext = {
  eduwit_gst_bps: 1800,
  hold_days: 30,
  refund_window_days: 30,
  penalty_cap_bps: 2000,
  confirm_partial_receipts: false,
};
const opts = {
  starts_on: "2026-11-01",
  context,
  sections: DEFAULT_TDS_SECTIONS,
  gst_rate_bps: 1800,
};
const sim = (config: unknown, s: ScenarioInput) => simulate(compConfig.parse(config), scenario.parse(s), opts);
const amount = (r: ReturnType<typeof simulate>, key: string) => r.breakdown.find((b) => b.key === key)?.amount_paise;

describe("simulate", () => {
  it("fixed + commission: breakdown, tax, net and Eduwit economics", () => {
    const r = sim(SYSTEM_PRESETS.fixed_plus_commission.config, {
      leads: 20,
      qualified_leads: 8,
      enrollments: 3,
      views: 50_000,
      avg_commission_gross_paise: 11_800_00,
    });
    expect(amount(r, "fixed")).toBe(15_000_00);
    expect(amount(r, "commission")).toBe(3_000_00);
    expect(r).toMatchObject({
      gross_paise: 18_000_00,
      penalties_paise: 0,
      net_payout_paise: 18_000_00,
    });
    expect(r.tax.tds_paise).toBe(0);
    expect(r.eduwit).toEqual({
      revenue_paise: 30_000_00,
      cost_paise: 18_000_00,
      cost_per_enrollment_paise: 6_000_00,
      margin_paise: 12_000_00,
      margin_bps: 4000,
    });
  });

  it("late delivery, cancellations, GST and no PAN all flow into the estimate", () => {
    const config = {
      ...SYSTEM_PRESETS.fixed_plus_commission.config,
      penalties: [
        {
          id: "late",
          type: "late_delivery",
          label: "Late",
          per_day: { type: "amount", amount_paise: 500_00 },
        },
      ],
    };
    const r = sim(config, {
      enrollments: 4,
      cancellations: 1,
      days_late: 2,
      avg_commission_gross_paise: 11_800_00,
      gst_registered: true,
      has_pan: false,
    });
    expect(r.penalties_paise).toBe(1_000_00);
    expect(amount(r, "clawback")).toBe(-1_000_00);
    expect(r.gross_paise).toBe(18_000_00);
    expect(r.tax.gst_paise).toBe(3_240_00);
    expect(r.tax.tds_paise).toBe(0); // under both FY thresholds
    expect(r.net_payout_paise).toBe(18_000_00 + 3_240_00 - 1_000_00);
    expect(r.eduwit.revenue_paise).toBe(30_000_00);
  });

  it("treats every lead and enrolment as in scope and fires view bonuses", () => {
    const r = sim(
      {
        schema_version: 1,
        commission: [
          {
            id: "prog",
            label: "Programme 9",
            scope: { type: "programmes", ids: [9] },
            basis: { type: "flat_per_enrollment", amount_paise: 2_000_00 },
          },
        ],
        bonuses: [
          {
            id: "views",
            label: "Views",
            conditions: {
              op: "and",
              items: [{ metric: "views", comparator: "gte", value: 40_000 }],
            },
            window: { type: "deal" },
            amount: { type: "fixed", amount_paise: 1_000_00 },
          },
        ],
      },
      { enrollments: 2, views: 50_000, months: 2 },
    );
    expect(amount(r, "commission")).toBe(4_000_00);
    expect(amount(r, "bonus")).toBe(1_000_00);
  });

  it("is deterministic", () => {
    const s = { leads: 50, qualified_leads: 20, applications: 10, enrollments: 5, months: 3 };
    expect(sim(SYSTEM_PRESETS.commission_only.config, s)).toEqual(sim(SYSTEM_PRESETS.commission_only.config, s));
  });

  it("the creator view carries no Eduwit figures", () => {
    const r = forCreator(
      sim(SYSTEM_PRESETS.commission_only.config, {
        enrollments: 1,
        avg_commission_gross_paise: 11_800_00,
      }),
    );
    expect(r).not.toHaveProperty("eduwit");
    expect(JSON.stringify(r)).not.toContain("margin");
    expect(JSON.stringify(r)).not.toContain("revenue");
  });
});

describe("scenario", () => {
  it("rejects impossible combinations", () => {
    const r = scenario.safeParse({
      leads: 2,
      qualified_leads: 3,
      enrollments: 1,
      cancellations: 2,
    });
    expect(r.success ? [] : r.error.issues.map((i) => i.message)).toEqual(["gt_leads", "gt_enrollments"]);
  });

  it("generates events within the scenario's months, ending with completion", () => {
    const c = compConfig.parse(SYSTEM_PRESETS.fixed_only.config);
    const { events, ends_on } = scenarioEvents(
      c,
      scenario.parse({ leads: 10, enrollments: 2, months: 2 }),
      "2026-11-01",
    );
    expect(ends_on).toBe("2026-12-31");
    expect(events.filter((e) => e.type === "lead")).toHaveLength(10);
    expect(events.at(-1)?.type).toBe("deal_completed");
    expect(new Set(events.map((e) => e.id)).size).toBe(events.length);
  });

  it("finds the deliverables a config refers to", () => {
    const c = compConfig.parse({
      schema_version: 1,
      fixed: [
        {
          id: "f",
          label: "f",
          amount_paise: 100,
          basis: "lump_sum",
          milestones: [
            {
              id: "m",
              label: "m",
              share: { type: "pct", pct: 100 },
              trigger: { type: "on_deliverable_live", deliverable: "reel" },
            },
          ],
        },
      ],
      commission: [
        {
          id: "c",
          label: "c",
          scope: { type: "deliverables", ids: ["story"] },
          basis: { type: "flat_per_lead", amount_paise: 1 },
        },
      ],
    });
    expect(configDeliverables(c)).toEqual(["reel", "story"]);
    expect(configDeliverables(compConfig.parse({ schema_version: 1 }))).toEqual(["d1"]);
  });
});
