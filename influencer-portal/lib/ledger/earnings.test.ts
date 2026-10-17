import { describe, expect, it } from "vitest";
import { earningTotals, monthStatement, nextPayoutDate, type EarningEntry } from "./earnings";
import { reconcile } from "./reconcile";

const e = (over: Partial<EarningEntry>): EarningEntry & { label: string } => ({
  type: "milestone",
  direction: "credit",
  amount_paise: 10_000,
  confirmed_paise: 0,
  paid_paise: 0,
  status: "accrued",
  period: "2026-11",
  posted_at: "2026-11-05T06:00:00.000Z",
  label: "x",
  ...over,
});

describe("earning totals", () => {
  it("splits earnings by stage and period", () => {
    const t = earningTotals(
      [
        e({}),
        e({ confirmed_paise: 10_000, status: "confirmed" }),
        e({ confirmed_paise: 10_000, status: "payable" }),
        e({ confirmed_paise: 10_000, status: "in_batch" }),
        e({ confirmed_paise: 10_000, paid_paise: 10_000, status: "paid", period: "2026-03" }),
        e({ type: "penalty", direction: "debit", amount_paise: 2_000, confirmed_paise: 2_000, status: "payable" }),
        e({
          type: "tds",
          direction: "debit",
          amount_paise: 1_000,
          confirmed_paise: 1_000,
          paid_paise: 1_000,
          status: "paid",
        }),
      ],
      "2026-11-20",
    );
    expect(t).toEqual({
      lifetime_paise: 48_000,
      fy_paise: 38_000,
      month_paise: 38_000,
      pending_paise: 10_000,
      confirmed_paise: 10_000,
      payable_paise: 18_000,
      paid_paise: 10_000,
    });
  });

  it("nets reversals to zero and shows recoveries as negative payable", () => {
    const t = earningTotals(
      [
        e({ confirmed_paise: 10_000, paid_paise: 10_000, status: "clawed_back" }),
        e({ type: "reversal", direction: "debit", confirmed_paise: 10_000, status: "payable" }),
        e({ confirmed_paise: 0, status: "reversed" }),
        e({ type: "reversal", direction: "debit", confirmed_paise: 0, status: "reversed" }),
      ],
      "2026-11-20",
    );
    expect(t.lifetime_paise).toBe(0);
    expect(t.payable_paise).toBe(-10_000);
    expect(t.pending_paise).toBe(0);
    expect(t.paid_paise).toBe(10_000);
  });
});

describe("next payout date", () => {
  it("monthly: this month's payout day if not passed, else next month's", () => {
    expect(nextPayoutDate("monthly", 10, "2026-11-05")).toBe("2026-11-10");
    expect(nextPayoutDate("monthly", 10, "2026-11-10")).toBe("2026-11-10");
    expect(nextPayoutDate("monthly", 10, "2026-11-11")).toBe("2026-12-10");
    expect(nextPayoutDate("monthly", 28, "2027-02-27")).toBe("2027-02-28");
  });
  it("fortnightly: the payout day and fourteen days later", () => {
    expect(nextPayoutDate("fortnightly", 10, "2026-11-11")).toBe("2026-11-24");
    expect(nextPayoutDate("fortnightly", 20, "2027-02-25")).toBe("2027-02-28");
    expect(nextPayoutDate("fortnightly", 10, "2026-12-25")).toBe("2027-01-10");
  });
  it("weekly: the next Monday (today if Monday)", () => {
    expect(nextPayoutDate("weekly", 1, "2026-11-16")).toBe("2026-11-16");
    expect(nextPayoutDate("weekly", 1, "2026-11-17")).toBe("2026-11-23");
  });
});

describe("monthly statement", () => {
  it("carries the opening balance and splits earnings, TDS, GST and payouts", () => {
    const s = monthStatement(
      [
        e({ posted_at: "2026-10-31T19:00:00.000Z", amount_paise: 50_000 }),
        e({ posted_at: "2026-10-31T17:00:00.000Z", amount_paise: 7_000 }),
        e({ type: "gst", amount_paise: 9_000, posted_at: "2026-11-10T06:00:00.000Z" }),
        e({ type: "tds", direction: "debit", amount_paise: 5_000, posted_at: "2026-11-10T06:00:00.000Z" }),
        e({ type: "payout", direction: "debit", amount_paise: 61_000, posted_at: "2026-11-10T06:00:00.000Z" }),
        e({ type: "penalty", direction: "debit", amount_paise: 1_000, posted_at: "2026-11-12T06:00:00.000Z" }),
        e({ posted_at: "2026-12-01T06:00:00.000Z" }),
      ],
      "2026-11",
    );
    expect(s.opening_paise).toBe(7_000);
    expect(s.lines.map((l) => l.amount_paise)).toEqual([50_000, 9_000, -5_000, -61_000, -1_000]);
    expect(s).toMatchObject({
      earned_paise: 49_000,
      tds_paise: 5_000,
      gst_paise: 9_000,
      paid_out_paise: 61_000,
      closing_paise: -1_000,
    });
  });
});

describe("reconciliation", () => {
  const entry = {
    subject: "enrol:b2b:9",
    direction: "credit" as const,
    amount_paise: 100_000,
    confirmed_paise: 0,
    reversed: false,
    at: "2026-08-01T00:00:00.000Z",
  };
  it("flags commission still waiting on Eduwit after N days", () => {
    const rows = reconcile(
      [entry],
      [{ enrollment_ref: "b2b:9", expected_paise: 1_180_000, received_paise: 0, status: "expected" }],
      90,
      "2026-11-15T00:00:00.000Z",
    );
    expect(rows[0]).toMatchObject({
      enrollment_ref: "b2b:9",
      flag: "overdue",
      accrued_paise: 100_000,
      confirmed_paise: 0,
    });
    expect(reconcile([entry], [], 120, "2026-11-15T00:00:00.000Z")[0]?.flag).toBeNull();
  });
  it("flags receipts the ledger has not confirmed yet, and ignores reversed and non-enrolment lines", () => {
    const rows = reconcile(
      [entry, { ...entry, subject: "lead:a1" }, { ...entry, subject: "enrol:b2b:10", reversed: true }],
      [{ enrollment_ref: "b2b:9", expected_paise: 1_180_000, received_paise: 1_180_000, status: "received" }],
      90,
      "2026-08-02T00:00:00.000Z",
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]?.flag).toBe("received_not_confirmed");
  });
  it("is clean once confirmed", () => {
    const rows = reconcile(
      [{ ...entry, confirmed_paise: 100_000 }],
      [{ enrollment_ref: "b2b:9", expected_paise: null, received_paise: 1_180_000, status: "received" }],
      90,
      "2026-11-15T00:00:00.000Z",
    );
    expect(rows[0]?.flag).toBeNull();
  });
});
