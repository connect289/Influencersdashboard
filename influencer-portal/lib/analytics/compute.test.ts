import { describe, expect, it } from "vitest";
import {
  addTotals,
  delta,
  EMPTY_TOTALS,
  funnel,
  leaderboard,
  leadQuality,
  perUnit,
  ratio,
  unitEconomics,
  type Totals,
} from "./compute";

const t: Totals = {
  clicks: 1_000,
  leads: 200,
  qualified: 80,
  allocated: 60,
  applied: 30,
  enrolled: 10,
  junk: 20,
  attributions: 250,
  duplicates: 25,
  cost_paise: 50_000_00,
  revenue_paise: 120_000_00,
};

describe("ratios", () => {
  it("is null when the denominator is zero", () => {
    expect(ratio(1, 0)).toBeNull();
    expect(ratio(0, 5)).toBe(0);
    expect(perUnit(100, 0)).toBeNull();
  });

  it("rounds per-unit paise half to even", () => {
    expect(perUnit(5, 2)).toBe(2);
    expect(perUnit(7, 2)).toBe(4);
    expect(perUnit(10, 3)).toBe(3);
    expect(perUnit(-5, 2)).toBe(-2);
  });
});

describe("funnel", () => {
  it("gives each step's share of the previous step and of clicks", () => {
    const f = funnel(t);
    expect(f.map((r) => r.count)).toEqual([1_000, 200, 80, 60, 30, 10]);
    expect(f[0]).toMatchObject({ from_previous: null, from_start: null });
    expect(f[1]).toMatchObject({ from_previous: 0.2, from_start: 0.2 });
    expect(f[5]?.from_previous).toBeCloseTo(1 / 3);
    expect(f[5]?.from_start).toBe(0.01);
  });

  it("copes with no clicks (typed codes) and empty steps", () => {
    const f = funnel({ ...EMPTY_TOTALS, leads: 3 });
    expect(f[1]).toMatchObject({ count: 3, from_previous: null, from_start: null });
    expect(f[2]?.from_previous).toBe(0);
  });
});

describe("unit economics", () => {
  it("computes cost per lead, qualified lead and enrolment, ROI and ROAS", () => {
    expect(unitEconomics(t)).toEqual({
      cost_per_lead_paise: 250_00,
      cost_per_qualified_paise: 625_00,
      cost_per_enrollment_paise: 5_000_00,
      revenue_paise: 120_000_00,
      cost_paise: 50_000_00,
      net_roi: 1.4,
      roas: 2.4,
    });
  });

  it("leaves ROI and ROAS empty without spend", () => {
    expect(unitEconomics({ ...t, cost_paise: 0 })).toMatchObject({ net_roi: null, roas: null, cost_per_lead_paise: 0 });
  });

  it("shows a loss as negative ROI", () => {
    expect(unitEconomics({ ...t, revenue_paise: 25_000_00 }).net_roi).toBe(-0.5);
  });
});

describe("lead quality", () => {
  it("uses leads for most rates and all attributions for duplicates", () => {
    expect(leadQuality(t)).toEqual({
      qualification_rate: 0.4,
      junk_rate: 0.1,
      duplicate_rate: 0.1,
      enrollment_rate: 0.05,
    });
    expect(leadQuality(EMPTY_TOTALS)).toEqual({
      qualification_rate: null,
      junk_rate: null,
      duplicate_rate: null,
      enrollment_rate: null,
    });
  });
});

describe("deltas", () => {
  it("knows whether up is good news", () => {
    expect(delta(120, 100, "up_is_good")).toEqual({ change: 20, pct: 0.2, direction: "up", tone: "good" });
    expect(delta(120, 100, "down_is_good")).toMatchObject({ tone: "bad" });
    expect(delta(80, 100, "down_is_good")).toMatchObject({ direction: "down", tone: "good", pct: -0.2 });
    expect(delta(5, 5, "up_is_good")).toMatchObject({ direction: "flat", tone: "neutral" });
    expect(delta(5, 1, "neutral")).toMatchObject({ tone: "neutral" });
  });

  it("has no percentage from zero and no delta without both values", () => {
    expect(delta(5, 0, "up_is_good")).toMatchObject({ change: 5, pct: null });
    expect(delta(null, 1, "up_is_good")).toBeNull();
    expect(delta(-2, -4, "up_is_good")).toMatchObject({ pct: 0.5, tone: "good" });
  });
});

describe("leaderboards", () => {
  const rows = [
    { name: "Asha", enrolled: 5, leads: 40, ontime: 0.9 },
    { name: "Bina", enrolled: 7, leads: 50, ontime: 1 },
    { name: "Chet", enrolled: 5, leads: 3, ontime: 1 },
    { name: "Dev", enrolled: 2, leads: 20, ontime: null },
  ];

  it("ranks with ties sharing a place", () => {
    expect(leaderboard(rows, (r) => r.enrolled, { name: (r) => r.name }).map((x) => [x.rank, x.row.name])).toEqual([
      [1, "Bina"],
      [2, "Asha"],
      [2, "Chet"],
      [4, "Dev"],
    ]);
  });

  it("skips small samples and missing values, and can rank ascending", () => {
    const rate = leaderboard(rows, (r) => r.ontime, {
      name: (r) => r.name,
      sample: (r) => r.leads,
      minSample: 5,
    });
    expect(rate.map((x) => x.row.name)).toEqual(["Bina", "Asha"]);
    const asc = leaderboard(rows, (r) => r.enrolled, { name: (r) => r.name, ascending: true, limit: 2 });
    expect(asc.map((x) => [x.rank, x.row.name])).toEqual([
      [1, "Dev"],
      [2, "Asha"],
    ]);
  });
});

describe("addTotals", () => {
  it("adds every field", () => {
    expect(addTotals([t, t]).leads).toBe(400);
    expect(addTotals([])).toEqual(EMPTY_TOTALS);
  });
});
