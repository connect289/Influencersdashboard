import { describe, expect, it } from "vitest";
import type { EngineContext } from "@/lib/compensation/engine";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { compConfig } from "@/lib/compensation/schema";
import { scenario } from "@/lib/compensation/simulator";
import { dryRun } from "./dry-run";

const context: EngineContext = {
  eduwit_gst_bps: 1800,
  hold_days: 30,
  refund_window_days: 30,
  penalty_cap_bps: 2000,
  confirm_partial_receipts: false,
};
const current = SYSTEM_PRESETS.fixed_plus_commission.config;
const base = {
  deal: { id: "d", starts_on: "2026-11-01", ends_on: "2027-01-31" },
  versions: [{ id: "v1", effective_from: "2026-10-31T18:30:00.000Z", config: current }],
  scenario: scenario.parse({ leads: 30, enrollments: 6, avg_commission_gross_paise: 11_800_00 }),
  context,
};

describe("dryRun", () => {
  it("no change when the draft equals the current terms", () => {
    const r = dryRun({ ...base, draft: { config: current, effective_from: "2026-12-01T00:00:00+05:30" } });
    expect(r.delta_paise).toBe(0);
    expect(r.changes).toEqual([]);
  });

  it("a higher commission from mid-deal changes only later enrolments", () => {
    const raised = compConfig.parse({
      ...current,
      commission: [
        { ...current.commission[0], basis: { type: "pct_of_eduwit_commission", pct: 20, base: "net_of_gst" } },
      ],
    });
    const r = dryRun({ ...base, draft: { config: raised, effective_from: "2026-12-01T00:00:00+05:30" } });
    expect(r.delta_paise).toBeGreaterThan(0);
    expect(r.delta_paise % 1_000_00).toBe(0); // whole enrolments at +₹1,000 each
    expect(
      r.changes.every((c) => c.type === "commission" && (c.after_paise ?? 0) - (c.before_paise ?? 0) === 1_000_00),
    ).toBe(true);
    expect(r.changes.length).toBe(r.delta_paise / 1_000_00);
    expect(r.after.net_paise - r.before.net_paise).toBe(r.delta_paise);
  });

  it("removing commission entirely from the start reverses those lines", () => {
    const fixedOnly = compConfig.parse({ ...current, commission: [] });
    const r = dryRun({ ...base, draft: { config: fixedOnly, effective_from: "2026-11-01T00:00:01+05:30" } });
    expect(r.changes.every((c) => c.after_paise === null && c.type === "commission")).toBe(true);
    expect(r.delta_paise).toBe(-6_000_00);
  });

  it("needs the current terms", () => {
    expect(() =>
      dryRun({ ...base, versions: [], draft: { config: current, effective_from: "2026-12-01T00:00:00+05:30" } }),
    ).toThrow();
  });
});
