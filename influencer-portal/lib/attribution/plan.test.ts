import { describe, expect, it } from "vitest";
import { planLead, type CandidateLead, type ExistingRow } from "./plan";
import type { Rules } from "./rules";
import { DEFAULT_STAGE_RULES } from "./stage-rules";

const rules: Rules = {
  window_days: 90,
  model: "first_touch_with_assisted",
  duplicate_grace_minutes: 10,
  reenquiry_credit_after_days: null,
};
const touch = (creator: string, at: string) => ({
  code: `${creator.toUpperCase()}-IG-AA`,
  link_id: `l-${creator}`,
  creator_id: creator,
  deal_id: null,
  deliverable_id: null,
  campaign_id: null,
  at,
  source: "click" as const,
});
const lead = (over: Partial<CandidateLead> = {}): CandidateLead => ({
  id: 1,
  created_at: "2026-11-01T10:05:00.000Z",
  reopened_at: null,
  is_test: false,
  touches: [touch("riya", "2026-11-01T10:00:00.000Z")],
  self_referral_creators: [],
  existing: [],
  stage: { stage: "qualifying", is_sales_ready: true },
  stage_changed_at: "2026-11-01T11:00:00.000Z",
  ...over,
});
const row = (over: Partial<ExistingRow>): ExistingRow => ({
  creator_id: "riya",
  status: "credited",
  stage: "qualified",
  reason: null,
  link_id: "l-riya",
  code: "RIYA-IG-AA",
  deal_id: null,
  deliverable_id: null,
  campaign_id: null,
  touch: "first",
  attribution_reason: null,
  touch_at: "2026-11-01T10:00:00.000Z",
  evidence_source: "click",
  ...over,
});

describe("planLead", () => {
  it("decides the attribution and maps the stage for the credited creator", () => {
    const p = planLead(lead(), rules, DEFAULT_STAGE_RULES);
    expect(p.decisions).toHaveLength(1);
    expect(p.decisions[0]).toMatchObject({
      creator_id: "riya",
      status: "credited",
      touch: "first",
      stage: { stage: "qualified", flags: [] },
    });
    expect(p.occurred_at).toBe("2026-11-01T11:00:00.000Z");
  });

  it("maps the attribution outcome into the stage (duplicate, self-referral)", () => {
    const dup = planLead(
      lead({ created_at: "2026-10-01T00:00:00.000Z" }),
      rules,
      DEFAULT_STAGE_RULES,
    );
    expect(dup.decisions[0]?.stage).toEqual({
      stage: "duplicate",
      reason: "already enquired before your link",
      flags: [],
    });
    const self = planLead(lead({ self_referral_creators: ["riya"] }), rules, DEFAULT_STAGE_RULES);
    expect(self.decisions[0]?.stage.stage).toBe("not_attributed");
  });

  it("keeps stages from moving backwards", () => {
    const p = planLead(
      lead({ existing: [row({ stage: "applied" })], stage: { stage: "qualifying" } }),
      rules,
      DEFAULT_STAGE_RULES,
    );
    expect(p.decisions[0]?.stage.stage).toBe("applied");
  });

  it("carries forward a manual credit that has no touch in the evidence", () => {
    const p = planLead(
      lead({
        existing: [
          row({
            creator_id: "arjun",
            status: "manually_credited",
            code: "MANUAL-AR",
            evidence_source: "manual",
            link_id: null,
            stage: "new",
          }),
        ],
      }),
      rules,
      DEFAULT_STAGE_RULES,
    );
    const arjun = p.decisions.find((d) => d.creator_id === "arjun");
    expect(arjun).toMatchObject({
      status: "manually_credited",
      evidence_source: "manual",
      stage: { stage: "qualified" },
    });
    // The manual credit takes the lead from the computed winner.
    expect(p.decisions.find((d) => d.creator_id === "riya")).toMatchObject({
      status: "duplicate",
      reason: "another_creator",
    });
  });

  it("flags stages no rule maps", () => {
    const p = planLead(
      lead({ existing: [row({ stage: "allocated" })], stage: { stage: "brand_new_crm_stage" } }),
      rules,
      DEFAULT_STAGE_RULES,
    );
    expect(p.unmapped).toBe(1);
    expect(p.decisions[0]?.stage).toMatchObject({ stage: "allocated", flags: ["unmapped"] });
  });

  it("an under-review attribution keeps the CRM stage with the flag", () => {
    const p = planLead(
      lead({ existing: [row({ status: "fraud_suspected" })] }),
      rules,
      DEFAULT_STAGE_RULES,
    );
    expect(p.decisions[0]).toMatchObject({
      status: "fraud_suspected",
      stage: { stage: "qualified", flags: ["under_review"] },
    });
  });
});
