import { describe, expect, it } from "vitest";
import { compConfig, type CompConfigInput } from "@/lib/compensation/schema";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { applyCounter, counterItems, counterTerms, describeCounter } from "./counter";

const cfg = (c: CompConfigInput) => compConfig.parse(c);
const hybrid = SYSTEM_PRESETS.fixed_plus_commission.config;

const rich = cfg({
  schema_version: 1,
  fixed: [
    {
      id: "posts",
      label: "Reels",
      amount_paise: 10_000_00,
      basis: "per_deliverable",
      units: 3,
      milestones: [
        {
          id: "a",
          label: "Signing",
          share: { type: "amount", amount_paise: 10_000_00 },
          trigger: { type: "on_contract_signed" },
        },
        {
          id: "b",
          label: "Live",
          share: { type: "amount", amount_paise: 20_000_00 },
          trigger: { type: "on_deliverable_live" },
        },
      ],
    },
    {
      id: "ret",
      label: "Retainer",
      amount_paise: 5_000_00,
      basis: "retainer",
      retainer: { periods: 3, every: "month", pay_on: "period_end", payment_terms_days: 0 },
    },
  ],
  commission: [
    {
      id: "slab",
      label: "Per enrolment",
      basis: { type: "flat_per_enrollment", amount_paise: 1_000_00 },
      slabs: {
        period: "deal",
        mode: "marginal",
        tiers: [
          { from: 1, amount_paise: 1_000_00 },
          { from: 11, amount_paise: 1_500_00 },
        ],
      },
    },
    { id: "pf", label: "Programme fee share", basis: { type: "pct_of_programme_fee", pct: 2.5 } },
  ],
  floors: [{ id: "min", label: "Monthly minimum", amount_paise: 3_000_00, period: "month" }],
  bonuses: [
    {
      id: "b10",
      label: "10 enrolments",
      conditions: { op: "and", items: [{ metric: "enrollments", comparator: "gte", value: 10 }] },
      window: { type: "deal" },
      amount: { type: "pct_of_fixed", pct: 10 },
    },
  ],
  fees: [{ id: "usage", kind: "usage_rights", label: "Usage rights", amount_paise: 2_000_00 }],
});

describe("counterItems", () => {
  it("lists every negotiable number with a stable key", () => {
    expect(counterItems(hybrid)).toEqual([
      { key: "fixed.fee", label: "Content fee", kind: "amount", value: 15_000_00 },
      { key: "commission.commission", label: "Commission per enrolment", kind: "pct", value: 10 },
    ]);
    expect(counterItems(rich).map((i) => `${i.key}:${i.kind}:${String(i.value)}`)).toEqual([
      "fixed.posts:amount:1000000",
      "fixed.ret:amount:500000",
      "commission.slab.tier.0:amount:100000",
      "commission.slab.tier.1:amount:150000",
      "commission.pf:pct:2.5",
      "floor.min:amount:300000",
      "bonus.b10:pct:10",
      "fee.usage:amount:200000",
    ]);
  });
  it("labels per-unit and per-period amounts", () => {
    const labels = counterItems(rich).map((i) => i.label);
    expect(labels).toContain("Reels (per unit)");
    expect(labels).toContain("Retainer (per period)");
  });
  it("is empty for a barter deal", () => {
    expect(
      counterItems(cfg({ schema_version: 1, non_cash: [{ id: "kit", label: "Laptop", value_paise: 1 }] })),
    ).toEqual([]);
  });
});

describe("applyCounter", () => {
  it("changes a lump-sum fee with percentage milestones", () => {
    const r = applyCounter(hybrid, [{ key: "fixed.fee", value: 20_000_00 }]);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.config.fixed[0]?.amount_paise).toBe(20_000_00);
    expect(r.config.fixed[0]?.milestones.map((m) => m.share)).toEqual(hybrid.fixed[0]?.milestones.map((m) => m.share));
    expect(hybrid.fixed[0]?.amount_paise).toBe(15_000_00);
  });
  it("rescales amount milestones in proportion, remainder on the last", () => {
    const r = applyCounter(rich, [{ key: "fixed.posts", value: 10_000_01 }]);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const shares = r.config.fixed[0]?.milestones.map((m) => (m.share.type === "amount" ? m.share.amount_paise : -1));
    expect(shares).toEqual([10_000_01, 20_000_02]);
    expect((shares ?? []).reduce((s, x) => s + x, 0)).toBe(10_000_01 * 3);
  });
  it("splits evenly when every old share was zero", () => {
    const zero = cfg({
      schema_version: 1,
      fixed: [
        {
          id: "f",
          label: "Fee",
          amount_paise: 0,
          basis: "lump_sum",
          milestones: [
            {
              id: "a",
              label: "A",
              share: { type: "amount", amount_paise: 0 },
              trigger: { type: "on_contract_signed" },
            },
            { id: "b", label: "B", share: { type: "amount", amount_paise: 0 }, trigger: { type: "manual_release" } },
            { id: "c", label: "C", share: { type: "amount", amount_paise: 0 }, trigger: { type: "manual_release" } },
          ],
        },
      ],
    });
    const r = applyCounter(zero, [{ key: "fixed.f", value: 100 }]);
    expect(
      r.ok && r.config.fixed[0]?.milestones.map((m) => (m.share.type === "amount" ? m.share.amount_paise : 0)),
    ).toEqual([33, 33, 34]);
  });
  it("changes retainers, tiers, percentages, floors, bonuses and fees", () => {
    const r = applyCounter(rich, [
      { key: "fixed.ret", value: 6_000_00 },
      { key: "commission.slab.tier.1", value: 2_000_00 },
      { key: "commission.pf", value: 3.25 },
      { key: "floor.min", value: 4_000_00 },
      { key: "bonus.b10", value: 12.5 },
      { key: "fee.usage", value: 0 },
    ]);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const c = r.config;
    expect(c.fixed[1]?.amount_paise).toBe(6_000_00);
    expect(c.commission[0]?.slabs?.tiers[1]?.amount_paise).toBe(2_000_00);
    expect(c.commission[1]?.basis).toEqual({ type: "pct_of_programme_fee", pct: 3.25 });
    expect(c.floors[0]?.amount_paise).toBe(4_000_00);
    expect(c.bonuses[0]?.amount).toEqual({ type: "pct_of_fixed", pct: 12.5 });
    expect(c.fees[0]?.amount_paise).toBe(0);
  });
  it("changes a flat commission and a fixed bonus", () => {
    const c = cfg({
      schema_version: 1,
      commission: [{ id: "flat", label: "Flat", basis: { type: "flat_per_lead", amount_paise: 100 } }],
      bonuses: [
        {
          id: "b",
          label: "B",
          conditions: { op: "or", items: [{ metric: "leads", comparator: "gte", value: 1 }] },
          window: { type: "month" },
          amount: { type: "fixed", amount_paise: 500 },
        },
      ],
    });
    const r = applyCounter(c, [
      { key: "commission.flat", value: 150 },
      { key: "bonus.b", value: 700 },
    ]);
    expect(r.ok && [r.config.commission[0]?.basis, r.config.bonuses[0]?.amount]).toEqual([
      { type: "flat_per_lead", amount_paise: 150 },
      { type: "fixed", amount_paise: 700 },
    ]);
  });
  it("refuses unknown items, bad values and no-ops", () => {
    expect(applyCounter(hybrid, [{ key: "fixed.nope", value: 1 }])).toEqual({
      ok: false,
      error: "unknown_item",
      key: "fixed.nope",
    });
    expect(applyCounter(hybrid, [{ key: "fixed.fee", value: 1.5 }])).toMatchObject({ error: "invalid_value" });
    expect(applyCounter(hybrid, [{ key: "commission.commission", value: 100.5 }])).toMatchObject({
      error: "invalid_value",
    });
    expect(applyCounter(hybrid, [{ key: "commission.commission", value: 10.123 }])).toMatchObject({
      error: "invalid_value",
    });
    expect(applyCounter(hybrid, [{ key: "commission.commission", value: -1 }])).toMatchObject({
      error: "invalid_value",
    });
    expect(applyCounter(hybrid, [{ key: "fixed.fee", value: 15_000_00 }])).toEqual({ ok: false, error: "no_change" });
    expect(applyCounter(rich, [{ key: "commission.slab.tier.5", value: 1 }])).toMatchObject({ error: "unknown_item" });
  });
});

describe("counterTerms and describeCounter", () => {
  it("validates the stored shape", () => {
    expect(counterTerms.safeParse({ changes: [{ key: "fixed.fee", value: 1 }] }).success).toBe(true);
    expect(counterTerms.safeParse({ changes: [] }).success).toBe(false);
    expect(counterTerms.safeParse({ changes: [{ key: "evil", value: 1 }] }).success).toBe(false);
    expect(
      counterTerms.safeParse({
        changes: [
          { key: "fixed.fee", value: 1 },
          { key: "fixed.fee", value: 2 },
        ],
      }).success,
    ).toBe(false);
  });
  it("describes changes against the terms", () => {
    expect(
      describeCounter(hybrid, [
        { key: "fixed.fee", value: 20_000_00 },
        { key: "fee.gone", value: 1 },
      ]),
    ).toEqual([
      { key: "fixed.fee", label: "Content fee", kind: "amount", from: 15_000_00, to: 20_000_00 },
      { key: "fee.gone", label: "fee.gone", kind: "amount", from: null, to: 1 },
    ]);
  });
});
