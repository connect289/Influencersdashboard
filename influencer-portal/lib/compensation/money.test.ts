import { describe, expect, it } from "vitest";
import { allocate, MoneyError, mulDiv, netOfGst, pctOf, sum, toBps } from "./money";

describe("mulDiv (banker's rounding)", () => {
  it.each([
    [5, 1, 2, 2], // 2.5 → 2 (even)
    [7, 1, 2, 4], // 3.5 → 4 (even)
    [9, 1, 2, 4], // 4.5 → 4
    [11, 1, 2, 6], // 5.5 → 6
    [10, 1, 3, 3], // 3.33 → 3
    [20, 1, 3, 7], // 6.67 → 7
    [-5, 1, 2, -2], // -2.5 → -2
    [-7, 1, 2, -4], // -3.5 → -4
    [-10, 1, 3, -3],
    [0, 5, 7, 0],
  ])("%i × %i / %i = %i", (a, n, d, out) => expect(mulDiv(a, n, d)).toBe(out));

  it("is exact for large amounts", () => {
    expect(mulDiv(9_000_000_000_000, 3, 7)).toBe(3_857_142_857_143);
  });

  it("rejects fractions and zero denominators", () => {
    expect(() => mulDiv(1.5, 1, 1)).toThrow(MoneyError);
    expect(() => mulDiv(1, 1, 0)).toThrow(MoneyError);
  });
});

describe("percentages and GST", () => {
  it("converts percentages to basis points", () => {
    expect(toBps(12.5)).toBe(1250);
    expect(toBps(0.01)).toBe(1);
    expect(toBps(100)).toBe(10000);
    expect(() => toBps(1.234)).toThrow(MoneyError);
  });
  it("takes a percentage of an amount with one rounding", () => {
    expect(pctOf(1_000_000, 1250)).toBe(125_000);
    expect(pctOf(333, 5000)).toBe(166); // 166.5 → 166
    expect(pctOf(335, 5000)).toBe(168); // 167.5 → 168
  });
  it("strips GST from a GST-inclusive amount", () => {
    expect(netOfGst(1_180_000, 1800)).toBe(1_000_000);
    expect(netOfGst(100, 1800)).toBe(85); // 84.75 → 85
  });
});

describe("allocate", () => {
  it("always adds up to the total", () => {
    expect(allocate(1000, [1, 1, 1])).toEqual([334, 333, 333]);
    expect(allocate(100_00, [3000, 3000, 4000])).toEqual([3000, 3000, 4000]);
    expect(allocate(1, [5000, 5000])).toEqual([1, 0]);
    expect(sum(allocate(999_999, [3333, 3333, 3334]))).toBe(999_999);
  });
  it("handles zero weights and totals", () => {
    expect(allocate(500, [0, 0])).toEqual([0, 0]);
    expect(allocate(0, [1, 2])).toEqual([0, 0]);
    expect(allocate(10, [0, 1])).toEqual([0, 10]);
  });
});
