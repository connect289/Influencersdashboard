import { describe, expect, it } from "vitest";
import { actionSummary } from "./labels.ts";

describe("actionSummary (the Actions page's one line per row)", () => {
  it("tells held, did not hold and unverified apart (phase 7 review M5)", () => {
    expect(actionSummary("verify", "done", { held: true, why: "CAT-01 passed at 10:02" })).toBe(
      "Held: CAT-01 passed at 10:02.",
    );
    expect(actionSummary("verify", "failed", { held: false, escalated: true, from: "P2", to: "P1" })).toBe(
      "Did not hold: incident now P1.",
    );
    expect(actionSummary("verify", "skipped", { held: null, why: "no run of CAT-01 to judge it by" })).toBe(
      "Unverified: no run of CAT-01 to judge it by.",
    );
    expect(actionSummary("verify", "skipped", { held: null, error: "division by zero" })).toBe(
      "Unverified: division by zero.",
    );
  });

  it("says what a dry run would do and why it was dry", () => {
    expect(actionSummary("dry_run", "planned", { would: "run b2c.inbox_retry(50)", why_dry: "switched off" })).toBe(
      "Would run b2c.inbox_retry(50) (dry: switched off).",
    );
  });
});
