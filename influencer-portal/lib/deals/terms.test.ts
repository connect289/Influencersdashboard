import { describe, expect, it } from "vitest";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { compConfig, dealModel, fixedValue } from "@/lib/compensation/schema";
import { configFromTerms } from "./terms";

describe("configFromTerms", () => {
  it("uses the system preset for the deal type and applies the negotiated fee", () => {
    const c = configFromTerms(null, {
      deal_type: "hybrid",
      fixed_fee_paise: 12_000_00,
      deliverables: [],
    });
    expect(dealModel(c)).toBe("hybrid");
    expect(fixedValue(c)).toBe(12_000_00);
    expect(c.fixed[0]?.milestones.map((m) => m.id)).toEqual(["signing", "live"]);
    expect(c.commission).toHaveLength(1);
  });

  it("fixed with commission becomes hybrid; fixed alone has no commission", () => {
    expect(
      dealModel(
        configFromTerms(null, {
          deal_type: "fixed",
          fixed_fee_paise: 5_000_00,
          includes_commission: true,
          deliverables: [],
        }),
      ),
    ).toBe("hybrid");
    expect(
      dealModel(
        configFromTerms(null, { deal_type: "fixed", fixed_fee_paise: 5_000_00, deliverables: [] }),
      ),
    ).toBe("fixed_only");
  });

  it("commission only drops fixed fees and recoupment from a hybrid preset", () => {
    const preset = compConfig.parse({
      ...SYSTEM_PRESETS.fixed_plus_commission.config,
      recoupment: { mode: "full", fixed: [] },
    });
    const c = configFromTerms(preset, { deal_type: "commission", deliverables: [] });
    expect(c.fixed).toEqual([]);
    expect(c.recoupment).toEqual({ mode: "none" });
  });

  it("keeps the campaign preset's other components", () => {
    const preset = compConfig.parse({
      ...SYSTEM_PRESETS.fixed_plus_commission.config,
      bonuses: [
        {
          id: "b",
          label: "Bonus",
          conditions: {
            op: "and",
            items: [{ metric: "enrollments", comparator: "gte", value: 5 }],
          },
          window: { type: "deal" },
          amount: { type: "fixed", amount_paise: 1_000_00 },
        },
      ],
    });
    expect(
      configFromTerms(preset, { deal_type: "hybrid", fixed_fee_paise: 9_000_00, deliverables: [] })
        .bonuses,
    ).toHaveLength(1);
  });

  it("a retainer or amount-split preset falls back to the standard 50/50 schedule", () => {
    const preset = compConfig.parse({
      schema_version: 1,
      fixed: [
        {
          id: "ret",
          label: "Retainer",
          amount_paise: 10_000_00,
          basis: "retainer",
          retainer: { periods: 3, every: "month", pay_on: "period_end" },
        },
      ],
    });
    const c = configFromTerms(preset, {
      deal_type: "fixed",
      fixed_fee_paise: 30_000_00,
      deliverables: [],
    });
    expect(c.fixed[0]).toMatchObject({ basis: "lump_sum", amount_paise: 30_000_00 });
  });

  it("barter starts empty for staff to fill in", () => {
    expect(dealModel(configFromTerms(null, { deal_type: "barter", deliverables: [] }))).toBe(
      "custom",
    );
  });
});
