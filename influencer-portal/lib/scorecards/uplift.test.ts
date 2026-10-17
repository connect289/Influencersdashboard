import { describe, expect, it } from "vitest";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { compConfig } from "@/lib/compensation/schema";
import { applyCommissionUplift } from "./uplift";

describe("commission uplift", () => {
  const base = SYSTEM_PRESETS.fixed_plus_commission.config;

  it("raises commission amounts and percentages, leaves fixed fees alone", () => {
    const up = applyCommissionUplift(base, 10);
    expect(compConfig.safeParse(up).success).toBe(true);
    for (const [i, r] of up.commission.entries()) {
      const before = base.commission[i];
      if (!before) throw new Error("rule");
      if ("amount_paise" in r.basis && "amount_paise" in before.basis)
        expect(r.basis.amount_paise).toBe(Math.round(before.basis.amount_paise * 1.1));
      if ("pct" in r.basis && "pct" in before.basis) expect(r.basis.pct).toBeCloseTo(before.basis.pct * 1.1, 2);
    }
    expect(up.fixed).toEqual(base.fixed);
  });

  it("uses banker's rounding, caps percentages at 100 and keeps two decimals", () => {
    const cfg = compConfig.parse({
      ...base,
      commission: [
        {
          id: "c1",
          label: "Per enrolment",
          basis: { type: "flat_per_enrollment", amount_paise: 25 },
          slabs: {
            period: "deal",
            mode: "marginal",
            tiers: [
              { from: 1, amount_paise: 25 },
              { from: 10, amount_paise: 35 },
            ],
          },
        },
        { id: "c2", label: "Share", basis: { type: "pct_of_programme_fee", pct: 95 } },
        { id: "c3", label: "Small", basis: { type: "pct_of_programme_fee", pct: 3.33 } },
      ],
    });
    const up = applyCommissionUplift(cfg, 10);
    const [c1, c2, c3] = up.commission;
    expect(c1?.basis).toMatchObject({ amount_paise: 28 }); // 27.5 → 28 (half to even)
    expect(c1?.slabs?.tiers.map((t) => t.amount_paise)).toEqual([28, 38]); // 38.5 → 38
    expect(c2?.basis).toMatchObject({ pct: 100 });
    expect(c3?.basis).toMatchObject({ pct: 3.66 }); // 366.3 bps → 366
    expect(compConfig.safeParse(up).success).toBe(true);
  });

  it("does nothing without an uplift", () => {
    expect(applyCommissionUplift(base, 0)).toBe(base);
  });
});
