import { describe, expect, it } from "vitest";
import { actionSummary, awaitingVerdict } from "./labels.ts";

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

describe("proof before power (0020)", () => {
  it("marks a real run that acted on one row as a trial, from its result or its plan", () => {
    expect(actionSummary("after", "done", { trial: true })).toBe("Done (trial: one row).");
    expect(actionSummary("after", "done", {}, { trial: true, rows: [1] })).toBe("Done (trial: one row).");
    expect(actionSummary("before", "planned", { waiting: "n8n" }, { trial: true })).toBe(
      "Waiting for n8n (trial: one row).",
    );
    expect(actionSummary("after", "done", {}, {})).toBe("Done.");
    expect(actionSummary("verify", "done", { held: true, trial: true })).toBe("Held.");
    expect(actionSummary("dry_run", "planned", { would: "act", trial: true })).toBe("Would act.");
  });

  it("says which incidents await a verdict", () => {
    expect(awaitingVerdict([])).toBe("");
    expect(awaitingVerdict([12])).toBe("awaiting the verdict on incident #12");
    expect(awaitingVerdict([12, 13])).toBe("awaiting the verdict on incidents #12, #13");
  });
});
