import { describe, expect, it } from "vitest";
import { addYears, anonymiseBefore, deletionPlan, EXPORT_SECTIONS } from "./plan";

describe("deletion requests", () => {
  const base = {
    last_record_on: "2026-10-01",
    open_deals: 0,
    balance_paise: 0,
    retention_years: 8,
    today: "2026-10-17",
  };

  it("keeps financial and contract records for the retention period", () => {
    const p = deletionPlan(base);
    expect(p.blocked).toBeNull();
    expect(p.purge_on).toBe("2034-10-01");
    expect(p.retain).toContain("ledger");
    expect(p.erase).toContain("profile");
  });

  it("with no financial records nothing is retained", () => {
    expect(deletionPlan({ ...base, last_record_on: null })).toMatchObject({ retain: [], purge_on: null });
  });

  it("waits for open deals and money owed either way", () => {
    expect(deletionPlan({ ...base, open_deals: 1 }).blocked).toBe("open_deals");
    expect(deletionPlan({ ...base, balance_paise: 5000 }).blocked).toBe("balance_due");
    expect(deletionPlan({ ...base, balance_paise: -5000 }).blocked).toBe("balance_due");
  });

  it("adds years without rolling 29 February into March", () => {
    expect(addYears("2028-02-29", 8)).toBe("2036-02-29");
    expect(addYears("2028-02-29", 1)).toBe("2029-02-28");
    expect(addYears("2026-12-31", 8)).toBe("2034-12-31");
  });

  it("export sections are unique", () => {
    expect(new Set(EXPORT_SECTIONS).size).toBe(EXPORT_SECTIONS.length);
  });

  it("click anonymisation cut-off", () => {
    expect(anonymiseBefore(new Date("2026-10-17T00:00:00Z"), 90)).toBe("2026-07-19T00:00:00.000Z");
  });
});
