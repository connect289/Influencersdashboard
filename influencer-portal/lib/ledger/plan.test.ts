import { describe, expect, it } from "vitest";
import type { EngineContext, LedgerLine } from "@/lib/compensation/engine";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import type { DealFacts } from "./facts";
import { planDeal, type PostedEntry } from "./plan";

const context: EngineContext = {
  eduwit_gst_bps: 1800,
  hold_days: 30,
  refund_window_days: 30,
  penalty_cap_bps: 2000,
  confirm_partial_receipts: false,
};
const deal = { id: "d1", starts_on: "2026-11-01", ends_on: null, campaign_ends_on: null };
const versions = [
  { id: "v1", effective_from: "2026-10-31T18:30:00.000Z", config: SYSTEM_PRESETS.fixed_plus_commission.config },
];
const facts: DealFacts = {
  contract_signed_at: "2026-11-02T06:00:00.000Z",
  brief_acknowledged_at: null,
  deliverables: [],
  leads: [
    {
      id: "a1",
      at: "2026-11-03T10:00:00.000Z",
      link_id: "l1",
      deliverable_ref: null,
      programme_id: 7,
      university_id: 3,
      level: "PG",
      qualified_at: null,
      applied_at: null,
      rejected_at: null,
      junk: false,
    },
  ],
  enrollments: [
    {
      ref: "b2b:9",
      lead_id: "a1",
      at: "2026-11-20T00:00:00.000Z",
      programme_id: 7,
      university_id: 3,
      level: "PG",
      fee_paise: 15_000_000,
      expected_commission_gross_paise: 1_180_000,
      cancelled_at: null,
    },
  ],
  receipts: [],
  manual: [],
  campaign_ended_at: null,
  deal_completed_at: null,
};
const asOf = "2026-12-01T00:00:00.000Z";
const posted = (l: LedgerLine, over: Partial<PostedEntry> = {}): PostedEntry => ({
  key: l.key,
  type: l.type,
  direction: l.direction,
  amount_paise: l.amount_paise,
  confirmed_paise: l.confirmed_paise,
  reversed: false,
  paid_paise: 0,
  in_open_batch: false,
  ...over,
});

function must<T>(v: T | undefined): T {
  if (v === undefined) throw new Error("missing fixture");
  return v;
}

describe("planDeal", () => {
  const first = planDeal({ deal, versions, facts, posted: [], as_of: asOf, context });

  it("posts the signing milestone and the commission on the enrolment", () => {
    const types = first.create.map((c) => c.type).sort();
    expect(types).toEqual(["commission", "milestone"]);
    const commission = first.create.find((c) => c.type === "commission");
    // 10% of Eduwit's commission net of 18% GST: 11,800 → 10,000 → 1,000 rupees.
    expect(commission?.amount_paise).toBe(100_000);
    expect(commission?.confirmed_paise).toBe(0);
    expect(commission?.tds_component).toBe("commission");
    expect(first.create.find((c) => c.type === "milestone")?.tds_component).toBe("milestone");
  });

  it("changes nothing when run again on what it posted", () => {
    const again = planDeal({ deal, versions, facts, posted: first.create.map((l) => posted(l)), as_of: asOf, context });
    expect(again.create).toEqual([]);
    expect(again.confirm).toEqual([]);
    expect(again.reverse).toEqual([]);
    expect(again.unchanged).toBe(first.create.length);
  });

  it("confirms the commission once Eduwit is paid in full", () => {
    const paid = planDeal({
      deal,
      versions,
      facts: {
        ...facts,
        receipts: [
          { enrollment_ref: "b2b:9", received_paise: 1_180_000, received_on: "2026-11-25T00:00:00.000Z", full: true },
        ],
      },
      posted: first.create.map((l) => posted(l)),
      as_of: asOf,
      context,
    });
    const commissionKey = first.create.find((c) => c.type === "commission")?.key;
    expect(paid.confirm).toEqual([{ key: commissionKey, confirmed_paise: 100_000 }]);
  });

  it("claws back a cancelled enrolment: the commission confirms and a matching debit is posted", () => {
    const cancelled = {
      ...facts,
      enrollments: [{ ...must(facts.enrollments[0]), cancelled_at: "2026-11-22T00:00:00.000Z" }],
    };
    const commission = must(first.create.find((c) => c.type === "commission"));
    const res = planDeal({
      deal,
      versions,
      facts: cancelled,
      posted: first.create.map((l) => posted(l)),
      as_of: asOf,
      context,
    });
    expect(res.confirm).toEqual([{ key: commission.key, confirmed_paise: 100_000 }]);
    const clawback = res.create.find((c) => c.type === "clawback");
    expect(clawback).toMatchObject({ direction: "debit", amount_paise: 100_000, confirmed_paise: 100_000 });
    expect(clawback?.tds_component).toBe("commission");
    expect(res.reverse).toEqual([]);
  });

  it("reverses a posted line whose amount changed, recording what was already paid", () => {
    const commission = must(first.create.find((c) => c.type === "commission"));
    const res = planDeal({
      deal,
      versions,
      facts,
      posted: first.create.map((l) =>
        l.key === commission.key ? posted(l, { amount_paise: 90_000, paid_paise: 40_000 }) : posted(l),
      ),
      as_of: asOf,
      context,
    });
    expect(res.reverse).toEqual([{ key: commission.key, reason: "changed", recover_paise: 40_000 }]);
    expect(res.create.map((c) => c.key)).toEqual([`${commission.key}~2`]);
  });

  it("waits to reverse an entry an open payout batch holds, and holds back its re-post", () => {
    const commission = must(first.create.find((c) => c.type === "commission"));
    const res = planDeal({
      deal,
      versions,
      facts,
      posted: first.create.map((l) =>
        l.key === commission.key ? posted(l, { amount_paise: 90_000, in_open_batch: true }) : posted(l),
      ),
      as_of: asOf,
      context,
    });
    expect(res.deferred).toEqual([commission.key]);
    expect(res.reverse).toEqual([]);
    expect(res.create).toEqual([]);
  });

  it("reverses lines the engine no longer wants", () => {
    const res = planDeal({
      deal,
      versions,
      facts: { ...facts, enrollments: [] },
      posted: first.create.map((l) => posted(l)),
      as_of: asOf,
      context,
    });
    const commission = must(first.create.find((c) => c.type === "commission"));
    expect(res.reverse).toEqual([{ key: commission.key, reason: "obsolete", recover_paise: 0 }]);
  });
});
