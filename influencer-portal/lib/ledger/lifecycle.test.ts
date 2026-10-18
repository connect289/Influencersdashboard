import { describe, expect, it } from "vitest";
import {
  ALLOWED_TRANSITIONS,
  canTransition,
  ENTRY_STATUSES,
  remainingPayable,
  STATUS_CASES,
  STATUS_TODAY,
  statusOf,
} from "./lifecycle";

describe("ledger entry status", () => {
  it.each(STATUS_CASES)("$name → $status", ({ state, status }) => {
    expect(statusOf(state, STATUS_TODAY)).toBe(status);
  });

  it("covers every status in the shared cases", () => {
    expect(new Set(STATUS_CASES.map((c) => c.status))).toEqual(new Set(ENTRY_STATUSES));
  });

  it("only payable entries have anything a payout can take", () => {
    for (const c of STATUS_CASES) {
      const r = remainingPayable(c.state, STATUS_TODAY);
      if (c.status === "payable") expect(r).toBe(c.state.confirmed_paise - c.state.paid_paise);
      else expect(r).toBe(0);
    }
  });

  it("allows staying put and the listed moves only", () => {
    expect(canTransition("accrued", "accrued")).toBe(true);
    expect(canTransition("accrued", "payable")).toBe(true);
    expect(canTransition("payable", "paid")).toBe(false);
    expect(canTransition("in_batch", "paid")).toBe(true);
    expect(canTransition("paid", "clawed_back")).toBe(true);
    expect(canTransition("reversed", "payable")).toBe(false);
    expect(canTransition("clawed_back", "paid")).toBe(false);
  });

  it("never lets a final status move", () => {
    expect(ALLOWED_TRANSITIONS.reversed).toEqual([]);
    expect(ALLOWED_TRANSITIONS.clawed_back).toEqual([]);
  });

  it("every transition the derivation can produce along a normal life is allowed", () => {
    const base = {
      amount_paise: 1000,
      confirmed_paise: 0,
      paid_paise: 0,
      in_open_batch: false,
      held: false,
      reversed: false,
      is_reversal: false,
      due_on: "2026-11-01",
    };
    const life = [
      base,
      { ...base, confirmed_paise: 1000, due_on: "2026-12-01" },
      { ...base, confirmed_paise: 1000 },
      { ...base, confirmed_paise: 1000, held: true },
      { ...base, confirmed_paise: 1000 },
      { ...base, confirmed_paise: 1000, in_open_batch: true },
      { ...base, confirmed_paise: 1000, paid_paise: 1000 },
      { ...base, confirmed_paise: 1000, paid_paise: 1000, reversed: true },
    ];
    const statuses = life.map((s) => statusOf(s, STATUS_TODAY));
    expect(statuses).toEqual([
      "accrued",
      "confirmed",
      "payable",
      "on_hold",
      "payable",
      "in_batch",
      "paid",
      "clawed_back",
    ]);
    for (let i = 1; i < statuses.length; i++)
      expect(
        canTransition(statuses[i - 1] as never, statuses[i] as never),
        `${String(statuses[i - 1])}→${String(statuses[i])}`,
      ).toBe(true);
  });
});
