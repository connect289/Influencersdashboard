import { describe, expect, it } from "vitest";
import * as segments from "./segments";
import {
  isSegment, PerformanceSchema, performanceDefaults, performancePayload, PolicySchema, pct, reqNum, scoringSummary, SEGMENT_RE, segmentRollup, segmentUniversity,
  splitText, stageProgress, untilText, weeklyShares,
} from "./segments";

const perfOk = {
  effort_enabled: "on", effort_lo: "0.9", effort_hi: "1.1",
  effort_w_first_call: "1", effort_w_attempts_72h: "1", effort_w_connect_rate: "1", effort_w_followup: "1", effort_w_acts_per_open: "1", effort_w_stale_share: "1",
  effort_min_sample: "10",
  sla_enabled: "on", sla_floor: "0.85", sla_ceiling: "1", sla_step: "0.05",
  sla_w_first_attempt: "1", sla_w_status_update: "1", sla_w_enrollment_proof: "1",
};

describe("segment keys", () => {
  it("recognises 3- and 4-part keys and rejects 5 (D25)", () => {
    expect(isSegment("mba|PG|Online")).toBe(true);
    expect(isSegment("mba|*|*")).toBe(true);
    expect(isSegment("mba|PG|Online|u12")).toBe(true);
    expect(isSegment("mba|PG|Online|12")).toBe(false);
    expect(isSegment("mba|PG")).toBe(false);
    expect(isSegment("a|b|c|u1|e")).toBe(false);
    expect(isSegment(undefined)).toBe(false);
    expect(SEGMENT_RE.test("")).toBe(false);
  });

  it("rolls a university key up and reads its university", () => {
    expect(segmentRollup("mba|PG|Online|u12")).toBe("mba|PG|Online");
    expect(segmentRollup("mba|PG|Online")).toBe("mba|PG|Online");
    expect(segmentUniversity("mba|PG|Online|u12")).toBe(12);
    expect(segmentUniversity("mba|PG|Online")).toBeNull();
  });

  it("no longer exports the retired segment policy, pin or weight schemas (C7, C29, C57)", () => {
    const mod = segments as Record<string, unknown>;
    for (const k of ["SegmentPolicySchema", "segmentPolicyPayload", "PartnerWeightSchema", "maturityProgress"]) expect(mod[k]).toBeUndefined();
  });
});

describe("formatting", () => {
  it("formats percentages", () => {
    expect(pct(0.1447)).toBe("14.5%");
    expect(pct(0.2, 0)).toBe("20%");
    expect(pct(null)).toBe("—");
  });

  it("describes when something ends", () => {
    const now = new Date("2026-10-07T10:00:00Z");
    expect(untilText(null, now)).toBeNull();
    expect(untilText("2026-10-10T10:00:00Z", now)).toBe("ends in 3 days");
    expect(untilText("2026-10-07T13:00:00Z", now)).toBe("ends in 3 h");
    expect(untilText("2026-10-01T00:00:00Z", now)).toBe("expired");
  });

  it("keeps splitText for legacy rows", () => {
    expect(splitText({ "12": 60, "14": 40 })).toBe("12: 60, 14: 40");
    expect(splitText(undefined)).toBe("");
  });
});

describe("stageProgress", () => {
  const now = new Date("2026-10-07T10:00:00Z");
  const old = "2026-09-01T00:00:00Z", young = "2026-10-05T00:00:00Z";

  it("reports Stage B as ready when every competing partner has 20 leads at least 7 days old", () => {
    const p = stageProgress([{ n_received: 25, first_lead_at: old, n_matured_c: 0 }, { n_received: 20, first_lead_at: old, n_matured_c: 0 }], undefined, now);
    expect(p.b).toMatchObject({ ready: true, leads: 1, age: 1, share: 1 });
    expect(p.b.text).toContain("Stage B");
  });

  it("measures the fewest leads and the youngest partner", () => {
    const p = stageProgress([{ n_received: 30, first_lead_at: old, n_matured_c: 0 }, { n_received: 10, first_lead_at: young, n_matured_c: 0 }], undefined, now);
    const youngestDays = (now.getTime() - new Date(young).getTime()) / 86_400_000; // 2 days 10 hours
    expect(p.b.ready).toBe(false);
    expect(p.b.leads).toBeCloseTo(0.5);
    expect(p.b.age).toBeCloseTo(youngestDays / 7, 6);
    expect(p.b.share).toBeCloseTo(youngestDays / 7, 6);
    expect(p.b.text).toContain("fewest: 10");
    const q = stageProgress([{ n_received: 30, first_lead_at: young, n_matured_c: 0 }], undefined, now);
    expect(q.b.text).toContain("days old");
  });

  it("measures Stage C over the two best partners (30 matured each)", () => {
    expect(stageProgress([{ n_received: 0, first_lead_at: null, n_matured_c: 30 }, { n_received: 0, first_lead_at: null, n_matured_c: 31 }]).c).toMatchObject({ ready: true, share: 1 });
    const half = stageProgress([{ n_received: 0, first_lead_at: null, n_matured_c: 30 }]).c;
    expect(half).toMatchObject({ ready: false, share: 0.5 });
    const some = stageProgress([{ n_received: 0, first_lead_at: null, n_matured_c: 15 }, { n_received: 0, first_lead_at: null, n_matured_c: 0 }, { n_received: 0, first_lead_at: null, n_matured_c: 3 }]).c;
    expect(some.text).toContain("best: 15, next: 3");
    expect(some.share).toBeCloseTo(18 / 60);
  });

  it("ignores non-competing partners and copes with none", () => {
    const p = stageProgress([{ n_received: 1, first_lead_at: young, n_matured_c: 0, competing: false }, { n_received: 20, first_lead_at: old, n_matured_c: 0 }], undefined, now);
    expect(p.b.ready).toBe(true);
    expect(stageProgress([]).b).toMatchObject({ ready: false, share: 0 });
  });
});

describe("weeklyShares", () => {
  it("sums to 1 per week, weeks ascending", () => {
    const w = weeklyShares([
      { week: "2026-09-28", partner_id: 3, n: 6 }, { week: "2026-09-28", partner_id: 4, n: 2 },
      { week: "2026-09-21", partner_id: 3, n: 1 }, { week: "2026-09-21", partner_id: 5, n: 3 },
    ]);
    expect(w.map((x) => x.week)).toEqual(["2026-09-21", "2026-09-28"]);
    for (const x of w) expect(x.shares.reduce((s, y) => s + y.share, 0)).toBeCloseTo(1);
    expect(w[1]!.shares[0]).toEqual({ partner_id: 3, n: 6, share: 0.75 });
    expect(weeklyShares([])).toEqual([]);
  });
});

describe("scoringSummary", () => {
  it("is null for an unscored legacy decision", () => {
    expect(scoringSummary({ scoring_mode: null, mode: "fallback", selection_probability: 1 })).toBeNull();
  });

  it("describes A3 decisions by stage, from stored fields only (C112, C123)", () => {
    const b = scoringSummary({ stage: "B", mode: "performance", scoring_mode: "performance", holdout: false, holdout_share: 0.1, selection_probability: 1 });
    expect(b).toBe("Stage B: commission × effort × SLA");
    const c = scoringSummary({ stage: "C", mode: "performance", scoring_mode: "performance", holdout: true, holdout_share: 0.1, selection_probability: 1, model_version: "v3" });
    expect(c).toBe("Stage C: commission per lead · holdout lead (10%): the Admin's settings only, no AI changes · model v3");
    const x = scoringSummary({ stage: "A", mode: "exploration", scoring_mode: "commission_first", selection_probability: 0.2, draw: 0.031 });
    expect(x).toContain("Stage A: commission");
    expect(x).toContain("exploration lane");
    expect(x).toContain("20%");
    expect(scoringSummary({ stage: "A", mode: "rule", scoring_mode: "commission_first", selection_probability: 1 })).toContain("routing rule");
    expect(scoringSummary({ stage: "B", mode: "minimum", scoring_mode: "performance", selection_probability: 1 })).toContain("contractual minimum");
    expect(scoringSummary({ stage: "A", mode: "manual", scoring_mode: "commission_first", selection_probability: 1 })).toContain("by hand");
    for (const s of [b, c, x]) {
      expect(s).not.toContain("pinned");
      expect(s).not.toContain("seeded draws");
    }
  });

  it("keeps the legacy wording, with the draw sentence keyed on scoring_mode alone (C128)", () => {
    expect(scoringSummary({ scoring_mode: "performance", mode: "manual", selection_probability: 0.62 })).toBe("Performance · chosen in 62% of the seeded draws");
    expect(scoringSummary({ scoring_mode: "performance", mode: "performance", selection_probability: 0.62, holdout: true }))
      .toBe("Performance · holdout lead: the Admin's settings only, no AI changes · chosen in 62% of the seeded draws");
    expect(scoringSummary({ scoring_mode: "commission_first", mode: "commission_first", selection_probability: 1 })).toBe("Commission first");
    expect(scoringSummary({ scoring_mode: "kill_switch", mode: "rule", selection_probability: 1 })).toBe("Kill switch (fixed split, retired)");
  });
});

describe("forms", () => {
  it("reqNum refuses a blank field and parses numbers", () => {
    const s = reqNum("needed");
    expect(s.safeParse("").success).toBe(false);
    expect(s.safeParse(" ").success).toBe(false);
    expect(s.safeParse("abc").success).toBe(false);
    expect(s.parse("0")).toBe(0);
    expect(s.parse(" 2.5 ")).toBe(2.5);
  });

  it("parses the holdout policy: blank fails, '0' is 0, '10' is 0.1, '60' fails (C63)", () => {
    expect(PolicySchema.safeParse({ holdout_share: "", reason: "new policy" }).success).toBe(false);
    expect(PolicySchema.safeParse({ holdout_share: " ", reason: "new policy" }).success).toBe(false);
    expect(PolicySchema.parse({ holdout_share: "0", reason: "new policy" })).toEqual({ holdout_share: 0, reason: "new policy" });
    expect(PolicySchema.parse({ holdout_share: "10", reason: "new policy" })).toEqual({ holdout_share: 0.1, reason: "new policy" });
    expect(PolicySchema.safeParse({ holdout_share: "60", reason: "new policy" }).success).toBe(false);
    expect(PolicySchema.safeParse({ holdout_share: "10", mc_draws: "200", reason: "new policy" }).success && "mc_draws" in PolicySchema.shape).toBe(false);
  });

  it("parses the effort and SLA settings into the stored shapes", () => {
    const d = PerformanceSchema.parse(perfOk);
    expect(performancePayload(d)).toEqual({
      effort_factor: { enabled: true, bounds: [0.9, 1.1], weights: { first_call: 1, attempts_72h: 1, connect_rate: 1, followup: 1, acts_per_open: 1, stale_share: 1 }, min_sample: 10 },
      sla_factor: { enabled: true, floor: 0.85, ceiling: 1, step: 0.05, weights: { first_attempt: 1, status_update: 1, enrollment_proof: 1 } },
    });
    expect(PerformanceSchema.parse({ ...perfOk, effort_enabled: undefined, sla_enabled: undefined })).toMatchObject({ effort_enabled: false, sla_enabled: false });
  });

  it("refuses a blank weight, accepts '0', refuses a blank floor and values outside the rulebook ranges", () => {
    const blank = PerformanceSchema.safeParse({ ...perfOk, effort_w_followup: "" });
    expect(blank.success).toBe(false);
    if (!blank.success) expect(blank.error.issues.map((i) => String(i.path[0]))).toContain("effort_w_followup");
    expect(PerformanceSchema.parse({ ...perfOk, effort_w_followup: "0" }).effort_w_followup).toBe(0);
    expect(PerformanceSchema.safeParse({ ...perfOk, sla_floor: "" }).success).toBe(false);
    expect(PerformanceSchema.safeParse({ ...perfOk, effort_lo: "0.8" }).success).toBe(false);
    expect(PerformanceSchema.safeParse({ ...perfOk, effort_hi: "1.2" }).success).toBe(false);
    expect(PerformanceSchema.safeParse({ ...perfOk, sla_floor: "0.75" }).success).toBe(false);
    expect(PerformanceSchema.safeParse({ ...perfOk, sla_step: "0.5" }).success).toBe(false);
    expect(PerformanceSchema.safeParse({ ...perfOk, effort_w_first_call: "6" }).success).toBe(false);
    expect(PerformanceSchema.safeParse({ ...perfOk, effort_min_sample: "2" }).success).toBe(false);
    expect(PerformanceSchema.safeParse({ ...perfOk, effort_min_sample: "10.5" }).success).toBe(false);
  });

  it("needs a positive weight sum and a ceiling at or above the floor", () => {
    const zero = PerformanceSchema.safeParse({ ...perfOk, effort_w_first_call: "0", effort_w_attempts_72h: "0", effort_w_connect_rate: "0", effort_w_followup: "0", effort_w_acts_per_open: "0", effort_w_stale_share: "0" });
    expect(zero.success).toBe(false);
    if (!zero.success) expect(zero.error.issues.map((i) => String(i.path[0]))).toContain("effort_weights");
    const ceil = PerformanceSchema.safeParse({ ...perfOk, sla_floor: "0.95", sla_ceiling: "0.9" });
    expect(ceil.success).toBe(false);
    if (!ceil.success) expect(ceil.error.issues.map((i) => String(i.path[0]))).toContain("sla_ceiling");
  });

  it("builds the form defaults from the stored setting", () => {
    const d = performanceDefaults({ effort_factor: { enabled: true, bounds: [0.9, 1.1], weights: { first_call: 2 }, min_sample: 12 }, sla_factor: { enabled: false, floor: 0.85 } });
    expect(d).toMatchObject({ effort_enabled: "on", effort_lo: "0.9", effort_hi: "1.1", effort_w_first_call: "2", effort_w_followup: "1", effort_min_sample: "12", sla_enabled: "", sla_floor: "0.85", sla_ceiling: "1", sla_step: "0.05" });
    expect(PerformanceSchema.safeParse(performanceDefaults({})).success).toBe(true);
  });
});
