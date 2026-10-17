import { describe, expect, it } from "vitest";
import { eligibility } from "./eligibility";

// Same truth table as supabase/tests/30_web_taxonomy.test.sql (keep in sync).
describe("eligibility (mirror of web_eligibility)", () => {
  it.each([
    ["graduation", "pg", "BACHELOR", "eligible"],
    ["12th", "pg", "BACHELOR", "not_eligible"],
    ["12th", "ug", "BACHELOR", "check"],
    ["diploma", "ug", "12TH", "check"],
    ["diploma", "diploma", "DIPLOMA", "eligible"],
    ["12th", "ug", null, "check"],
    ["10th", "certificate", "12TH", "not_eligible"],
    ["postgraduation", "pg", "MASTER", "eligible"],
    ["graduation", "pg", "MASTER", "not_eligible"],
    ["12th", "ug", "12TH", "eligible"],
  ] as const)("%s → %s (%s) = %s", (q, level, min, want) => {
    expect(eligibility(q, level, min)).toBe(want);
  });
  it("is not shown when the student's qualification is unknown", () => {
    expect(eligibility(undefined, "ug", "12TH")).toBeNull();
  });
});
