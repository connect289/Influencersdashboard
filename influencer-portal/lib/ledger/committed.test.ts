import { describe, expect, it } from "vitest";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { compConfig } from "@/lib/compensation/schema";
import { committedPaise, termMonths } from "./committed";

const context = {
  eduwit_gst_bps: 1800,
  hold_days: 30,
  refund_window_days: 30,
  penalty_cap_bps: 2000,
  confirm_partial_receipts: false,
};

describe("term months", () => {
  it("counts whole months, at least one and at most 24", () => {
    expect(termMonths("2026-10-01", "2026-12-31")).toBe(3);
    expect(termMonths("2026-10-15", "2026-11-14")).toBe(1);
    expect(termMonths("2026-10-15", "2026-10-20")).toBe(1);
    expect(termMonths("2026-01-01", "2029-12-31")).toBe(24);
    expect(termMonths("2026-10-01", null)).toBe(12);
  });
});

describe("committed spend", () => {
  it("is the fixed fee for fixed presets and nothing for commission only", () => {
    expect(committedPaise(SYSTEM_PRESETS.fixed_only.config, "2026-10-01", "2026-12-31", context)).toBe(15_000_00);
    expect(committedPaise(SYSTEM_PRESETS.fixed_plus_commission.config, "2026-10-01", null, context)).toBe(15_000_00);
    expect(committedPaise(SYSTEM_PRESETS.commission_only.config, "2026-10-01", null, context)).toBe(0);
  });

  it("includes a monthly guarantee over the term", () => {
    const config = compConfig.parse({
      schema_version: 1,
      commission: SYSTEM_PRESETS.commission_only.config.commission,
      floors: [{ id: "floor", label: "Floor", amount_paise: 5_000_00, period: "month" }],
    });
    expect(committedPaise(config, "2026-10-01", "2026-12-31", context)).toBe(15_000_00);
  });
});
