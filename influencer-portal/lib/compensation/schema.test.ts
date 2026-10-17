import { describe, expect, it } from "vitest";
import { SYSTEM_PRESETS } from "./presets";
import { compConfig, dealModel, fixedValue } from "./schema";

const ms = (id: string, pct: number, type = "on_contract_signed") => ({
  id,
  label: id,
  share: { type: "pct" as const, pct },
  trigger: { type },
});
const errs = (input: unknown) => {
  const r = compConfig.safeParse(input);
  return r.success ? [] : r.error.issues.map((i) => i.message);
};

describe("compConfig validation", () => {
  it("accepts the presets and classifies them", () => {
    expect(dealModel(SYSTEM_PRESETS.commission_only.config)).toBe("commission_only");
    expect(dealModel(SYSTEM_PRESETS.fixed_plus_commission.config)).toBe("hybrid");
    expect(dealModel(SYSTEM_PRESETS.fixed_only.config)).toBe("fixed_only");
    expect(fixedValue(SYSTEM_PRESETS.fixed_only.config)).toBe(15_000_00);
  });

  it("requires milestones to add up to 100% or to the full amount, without mixing", () => {
    const base = { id: "fee", label: "Fee", amount_paise: 1000_00, basis: "lump_sum" };
    expect(
      errs({ schema_version: 1, fixed: [{ ...base, milestones: [ms("a", 50), ms("b", 40)] }] }),
    ).toContain("milestones_not_100");
    expect(
      errs({
        schema_version: 1,
        fixed: [{ ...base, milestones: [ms("a", 33.33), ms("b", 33.33), ms("c", 33.34)] }],
      }),
    ).toEqual([]);
    expect(
      errs({
        schema_version: 1,
        fixed: [
          {
            ...base,
            units: 2,
            milestones: [
              {
                id: "a",
                label: "a",
                share: { type: "amount", amount_paise: 1000_00 },
                trigger: { type: "on_contract_signed" },
              },
            ],
          },
        ],
      }),
    ).toContain("milestones_not_total");
    expect(
      errs({
        schema_version: 1,
        fixed: [
          {
            ...base,
            milestones: [
              ms("a", 50),
              {
                id: "b",
                label: "b",
                share: { type: "amount", amount_paise: 500_00 },
                trigger: { type: "on_contract_signed" },
              },
            ],
          },
        ],
      }),
    ).toContain("milestones_mixed");
    expect(errs({ schema_version: 1, fixed: [{ ...base, milestones: [] }] })).toContain(
      "milestones_required",
    );
  });

  it("requires retainer settings for retainers", () => {
    expect(
      errs({
        schema_version: 1,
        fixed: [{ id: "r", label: "r", amount_paise: 100, basis: "retainer" }],
      }),
    ).toContain("retainer_required");
  });

  it("checks slab tiers: start at 1, ascending, rate kind matches the basis", () => {
    const rule = (
      slabs: unknown,
      basis: unknown = { type: "flat_per_enrollment", amount_paise: 500_00 },
    ) => ({
      schema_version: 1,
      commission: [{ id: "c", label: "c", basis, slabs }],
    });
    expect(
      errs(
        rule({
          period: "month",
          mode: "marginal",
          tiers: [
            { from: 2, amount_paise: 1 },
            { from: 5, amount_paise: 2 },
          ],
        }),
      ),
    ).toContain("tiers_start_at_1");
    expect(
      errs(
        rule({
          period: "month",
          mode: "marginal",
          tiers: [
            { from: 1, amount_paise: 1 },
            { from: 1, amount_paise: 2 },
          ],
        }),
      ),
    ).toContain("tiers_ascending");
    expect(
      errs(
        rule({
          period: "month",
          mode: "marginal",
          tiers: [
            { from: 1, pct: 5 },
            { from: 5, pct: 6 },
          ],
        }),
      ),
    ).toContain("tier_amount");
    expect(
      errs(
        rule(
          {
            period: "month",
            mode: "retroactive",
            tiers: [
              { from: 1, amount_paise: 1 },
              { from: 5, amount_paise: 2 },
            ],
          },
          { type: "pct_of_programme_fee", pct: 2 },
        ),
      ),
    ).toContain("tier_pct");
  });

  it("rejects duplicate ids, unknown references and percentages with three decimals", () => {
    const c = { id: "x", label: "x", basis: { type: "flat_per_lead", amount_paise: 1 } };
    expect(errs({ schema_version: 1, commission: [c, c] })).toContain("duplicate_id:x");
    expect(
      errs({
        schema_version: 1,
        commission: [c],
        floors: [{ id: "f", label: "f", amount_paise: 1, period: "month", rules: ["nope"] }],
      }),
    ).toContain("unknown_rule:nope");
    expect(
      errs({ schema_version: 1, commission: [c], recoupment: { mode: "full", fixed: ["nope"] } }),
    ).toContain("unknown_fixed:nope");
    expect(errs({ schema_version: 1, recoupment: { mode: "full" } })).toContain(
      "recoupment_needs_commission",
    );
    expect(
      errs({
        schema_version: 1,
        commission: [{ ...c, basis: { type: "pct_of_programme_fee", pct: 1.234 } }],
      }),
    ).toContain("two_decimals");
  });

  it("rejects fractional paise and unknown triggers", () => {
    expect(
      errs({
        schema_version: 1,
        commission: [{ id: "c", label: "c", basis: { type: "flat_per_lead", amount_paise: 10.5 } }],
      }).length,
    ).toBeGreaterThan(0);
    expect(
      errs({
        schema_version: 1,
        fixed: [
          {
            id: "f",
            label: "f",
            amount_paise: 100,
            basis: "lump_sum",
            milestones: [ms("a", 100, "on_whim")],
          },
        ],
      }).length,
    ).toBeGreaterThan(0);
  });
});
