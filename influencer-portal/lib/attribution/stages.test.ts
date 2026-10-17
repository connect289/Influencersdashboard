import { describe, expect, it } from "vitest";
import { DEFAULT_STAGE_RULES } from "./stage-rules";
import { evaluate, mapStage, matches, type StageInputs } from "./stages";

const map = (x: StageInputs) => evaluate(x, DEFAULT_STAGE_RULES);

describe("stage rules (STAGE_MAPPING.md §3)", () => {
  it.each([
    [{ stage: "new" }, "new", null],
    [{ stage: "" }, "new", null],
    [{ stage: "qualifying" }, "qualifying", null],
    [{ stage: "qualifying", is_sales_ready: true }, "qualified", null],
    [{ stage: "allocated" }, "allocated", null],
    [{ stage: "duplicate_at_partner" }, "allocated", null],
    [{ stage: "nurture" }, "allocated", null],
    [{ b2c_stage: "assigned", stage: "routed_to_partner" }, "allocated", null],
    [{ stage: "counselled" }, "counselling", null],
    [{ b2c_stage: "contacted" }, "counselling", null],
    [{ stage: "applied" }, "applied", null],
    [{ applied_at: "2026-11-01T00:00:00Z", stage: "contacted" }, "applied", null],
    [{ stage: "enrolled" }, "enrolled", null],
    [{ stage: "commission_booked" }, "enrolled", null],
    [{ enrollment_status: "reported", stage: "applied" }, "enrolled", null],
    [{ b2c_stage: "enrolled" }, "enrolled", null],
    [{ stage: "lost", lost_reason: "duplicate" }, "duplicate", "duplicate enquiry"],
    [{ stage: "lost", lost_reason: "junk or test" }, "junk", "invalid or test"],
    [{ stage: "lost", lost_reason: "Wrong Number" }, "junk", "wrong number"],
    [{ stage: "lost", lost_reason: "not reachable" }, "lost", "not reachable"],
    [{ stage: "lost", lost_reason: "over budget" }, "lost", "budget"],
    [{ stage: "lost", lost_reason: "enrolled elsewhere" }, "lost", "chose another option"],
    [{ stage: "lost", lost_reason: "cannot be served" }, "lost", "programme not available"],
    [{ stage: "lost", lost_reason: null }, "lost", "other"],
    [{ b2c_stage: "lost", stage: "assigned" }, "lost", "other"],
    [{ attribution_status: "duplicate", stage: "enrolled" }, "duplicate", "already enquired before your link"],
    [{ attribution_status: "outside_window", stage: "applied" }, "not_attributed", "outside the attribution window"],
    [{ attribution_status: "self_referral" }, "not_attributed", "self-referral"],
    [{ attribution_status: "manually_rejected" }, "not_attributed", "rejected after review"],
  ] as [StageInputs, string, string | null][])("%j → %s", (x, stage, reason) => {
    const r = map(x);
    expect(r.stage).toBe(stage);
    expect(r.reason).toBe(reason);
    expect(r.unmapped).toBe(false);
  });

  it("fraud review keeps the CRM stage and adds the under-review flag", () => {
    expect(map({ attribution_status: "fraud_suspected", stage: "counselled" })).toEqual({
      stage: "counselling",
      reason: null,
      flags: ["under_review"],
      unmapped: false,
    });
  });

  it("a refunded enrolment shows as enrolled, cancelled", () => {
    expect(map({ enrollment_status: "refunded", stage: "enrolled" })).toMatchObject({ stage: "enrolled", flags: ["cancelled"] });
  });

  it("an unknown CRM stage is unmapped", () => {
    expect(map({ stage: "something_new" })).toMatchObject({ unmapped: true });
  });

  it("conditions", () => {
    expect(matches({ field: "stage", in: ["Lost"] }, { stage: "LOST" })).toBe(true);
    expect(matches({ field: "applied_at", present: true }, { applied_at: "" })).toBe(false);
    expect(matches({ field: "lost_reason", empty: true }, {})).toBe(true);
    expect(matches({ field: "is_sales_ready", is_true: true }, { is_sales_ready: "true" })).toBe(false);
  });
});

describe("never backwards", () => {
  const prev = (stage: Parameters<typeof mapStage>[2] extends infer P ? NonNullable<P>["stage"] : never) => ({ stage, reason: null });
  it("ignores a lower open stage", () => {
    expect(mapStage({ stage: "qualifying" }, DEFAULT_STAGE_RULES, prev("counselling")).stage).toBe("counselling");
  });
  it("moves forward", () => {
    expect(mapStage({ stage: "applied" }, DEFAULT_STAGE_RULES, prev("counselling")).stage).toBe("applied");
  });
  it("closed outcomes can always follow, and a closed lead can come back", () => {
    expect(mapStage({ stage: "lost", lost_reason: "not interested" }, DEFAULT_STAGE_RULES, prev("applied")).stage).toBe("lost");
    expect(mapStage({ stage: "qualifying" }, DEFAULT_STAGE_RULES, prev("lost")).stage).toBe("qualifying");
  });
  it("an enrolment stays enrolled", () => {
    expect(mapStage({ stage: "lost", lost_reason: "not interested" }, DEFAULT_STAGE_RULES, prev("enrolled")).stage).toBe("enrolled");
    expect(mapStage({ enrollment_status: "refunded" }, DEFAULT_STAGE_RULES, prev("enrolled"))).toMatchObject({ stage: "enrolled", flags: ["cancelled"] });
  });
  it("an unmapped value keeps the last known stage", () => {
    expect(mapStage({ stage: "mystery" }, DEFAULT_STAGE_RULES, prev("allocated"))).toMatchObject({ stage: "allocated", unmapped: true });
  });
  it("no previous stage: the rules decide", () => {
    expect(mapStage({ stage: "applied" }, DEFAULT_STAGE_RULES, null).stage).toBe("applied");
  });
});
