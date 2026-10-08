import { describe, expect, it } from "vitest";
import {
  A3_FIXED_LABELS, a3FixedText, AttributionSchema, attributionPayload, CONSENT_STATE_LABEL, cpeBasisText, decisionModeLabel, decisionResultLabel, describeConditions,
  ENGINE_FIELDS, EngineSchema, enginePayload, fromStored, goliveBlocking, HandoffSchema, handoffPayload, HOLD_LABEL, notPassedLabel, OUTCOME_LABEL, OUTLOOK_LABEL,
  parseRuleForm, parseTiers, RateSchema, reasonLabel, REASON_LABEL, RuleSchema, segmentLabel, STAGE_LABEL, type Candidate, type GoliveItem, type StoredDecisionCore,
} from "./routing";

function form(entries: [string, string][]): FormData {
  const f = new FormData();
  for (const [k, v] of entries) f.append(k, v);
  return f;
}

describe("segmentLabel", () => {
  it("reads 3- and 4-part segments", () => {
    expect(segmentLabel("mba|PG|Online")).toBe("MBA · PG · Online");
    expect(segmentLabel("bcom|UG|*")).toBe("BCOM · UG · any");
    expect(segmentLabel("mba|PG|Online|u12")).toBe("MBA · PG · Online · university #12");
    expect(segmentLabel(null)).toBe("—");
  });
});

describe("labels (D47, CONTRACT 1.2–1.3)", () => {
  it("has the Addendum 3 reason codes and the changed texts", () => {
    for (const k of ["consent_no_answer", "partner_attempts_exhausted", "partner_barred", "test_lead", "test_handoff", "b2c_held", "manual_route_failed", "no_capacity",
                     "duplicate_cascade", "no_partner_consent", "partners_unreachable", "not_qualified", "partner_lost", "b2c_created", "import_choice", "rule", "manual"]) {
      expect(REASON_LABEL[k], k).toBeTruthy();
    }
    expect(REASON_LABEL.no_partner_consent).toBe("Student said NO to sharing");
    expect(REASON_LABEL.duplicate_cascade).toContain("partner-barred");
    expect(REASON_LABEL.paid_campaign).toContain("before 7 Oct 2026");
    expect(REASON_LABEL.consent_no_answer).toContain("48 h");
  });

  it("renders manual_route_failed and no_capacity with their cause", () => {
    expect(reasonLabel("no_capacity", "caps")).toBe("No eligible partner: every eligible partner is at its daily or monthly cap");
    expect(reasonLabel("manual_route_failed", "duplicate_cascade")).toBe("Sent to partners by hand, none could take it: duplicate at partners");
    expect(reasonLabel("manual_route_failed", null)).toBe("Sent to partners by hand, none could take it");
    expect(reasonLabel("partner_lost", "caps")).toBe("Partner marked it lost");
    expect(reasonLabel("something_new")).toBe("something new");
    expect(reasonLabel(null)).toBe("—");
  });

  it("reads the not-passed detail (spam rule, catalogue)", () => {
    expect(notPassedLabel("junk", "spam:disposable_email")).toBe("Junk (disposable email domain)");
    expect(notPassedLabel("junk", "spam:new_rule")).toBe("Junk (spam: new rule)");
    expect(notPassedLabel("program_mismatch", "course_not_in_catalogue")).toBe("Programme mismatch (course not in the catalogue)");
    expect(notPassedLabel("invalid_phone")).toBe("Invalid phone");
  });

  it("has the stage, hold, consent, outcome and outlook labels", () => {
    expect(STAGE_LABEL).toEqual({ A: "Commission", B: "Commission × effort × SLA", C: "Commission per lead" });
    expect(Object.keys(HOLD_LABEL).sort()).toEqual(["barred", "qualification_nurture", "selling"]);
    for (const k of ["given", "refused", "withdrawn", "stamp_uncovered", "none", "requested", "queued", "sent", "expired"]) expect(CONSENT_STATE_LABEL[k], k).toBeTruthy();
    for (const k of ["re-enquired", "with_partner", "consent_requested", "consent_pending"]) expect(OUTCOME_LABEL[k], k).toBeTruthy();
    for (const k of ["none", "not_passed", "b2c_sales", "b2c_nurture", "b2c", "b2c_held", "with_partner", "consent_pending", "consent_request", "partners"]) expect(OUTLOOK_LABEL[k], k).toBeTruthy();
  });

  it("labels every engine.a3_fixed key (D24) and formats the values", () => {
    const keys = ["stage_b_min_leads", "stage_b_min_age_days", "stage_c_min_matured", "stage_c_min_partners", "matured_days", "learn_leads", "exploration_share",
      "exact_segment_min_leads", "tier_projected_min_matured", "effort_range", "sla_range", "sla_step_range", "weight_range", "factor_window_days", "attempt_limit",
      "partner_limit", "hold_minutes_sync", "hold_minutes_async", "duplicate_window_hours", "push_retry_seconds", "lost_grace_days", "consent_wait_hours",
      "witty_idle_minutes", "auto_pause_breaches", "auto_pause_sync_minutes", "cpe_aggregate"];
    expect(Object.keys(A3_FIXED_LABELS).sort()).toEqual([...keys].sort());
    expect(A3_FIXED_LABELS).not.toHaveProperty("sla_step_per_10_points");
    expect(a3FixedText("exploration_share", 0.2)).toBe("20%");
    expect(a3FixedText("effort_range", [0.85, 1.15])).toBe("0.85 – 1.15");
    expect(a3FixedText("push_retry_seconds", [10, 60, 300])).toBe("10 s, 1 min, 5 min");
    expect(a3FixedText("cpe_aggregate", "median")).toBe("median");
  });

  it("describes a CPE basis", () => {
    expect(cpeBasisText({ tier_basis: "middle", fee_source: "partner", fee_basis: "first_year", offers_with_rate: 3, programme_id: 9 })).toBe("middle tier · partner fee (first year) · median of 3 programmes");
    expect(cpeBasisText({ tier_basis: "projected", fee_source: null, fee_basis: null, offers_with_rate: 1, programme_id: 9 })).toBe("projected tier");
    expect(cpeBasisText(null)).toBeNull();
  });
});

describe("decision labels (C128)", () => {
  it("names what decided", () => {
    expect(decisionModeLabel({ mode: "rule", scoring_mode: "kill_switch" })).toBe("Kill switch (fixed split, retired)");
    expect(decisionModeLabel({ mode: "performance", scoring_mode: "performance", stage: "B" })).toBe("Commission × effort × SLA");
    expect(decisionModeLabel({ mode: "commission_first", scoring_mode: "commission_first", stage: "A" })).toBe("Commission");
    expect(decisionModeLabel({ mode: "manual", scoring_mode: "commission_first", stage: "A" })).toBe("Manual");
    expect(decisionModeLabel({ mode: "exploration", scoring_mode: "commission_first", stage: "A" })).toBe("Exploration lane");
    expect(decisionModeLabel({ mode: "fallback" })).toBe("B2C fallback");
  });

  it("explains each loser", () => {
    const eligible = { partner_id: 7, eligible: true };
    expect(decisionResultLabel({ mode: "rule", scoring_mode: "kill_switch", stage: null, partner_id: 3 }, eligible)).toBe("Eligible, not drawn in the fixed split");
    expect(decisionResultLabel({ mode: "exploration", stage: "A", partner_id: 3 }, { ...eligible, tie_rank: 1 })).toBe("Highest score; the lead went to the exploration lane");
    expect(decisionResultLabel({ mode: "exploration", stage: "A", partner_id: 3 }, { ...eligible, tie_rank: 2 })).toBe("Eligible, not the exploration pick");
    expect(decisionResultLabel({ mode: "manual", scoring_mode: "performance", stage: null, partner_id: 3 }, eligible)).toBe("Eligible, lost the draw");
    expect(decisionResultLabel({ mode: "performance", scoring_mode: "performance", stage: "B", partner_id: 3 }, eligible)).toBe("Eligible, lower score");
    expect(decisionResultLabel({ mode: "performance", scoring_mode: "performance", stage: "C", partner_id: 3 }, eligible)).toBe("Eligible, lower score");
    expect(decisionResultLabel({ mode: "commission_first", scoring_mode: "commission_first", stage: "A", partner_id: 3 }, eligible)).toBe("Eligible, lower commission");
    expect(decisionResultLabel({ mode: "commission_first", stage: "A", partner_id: 7 }, eligible)).toBe("Chosen");
    expect(decisionResultLabel({ mode: "commission_first", stage: "A", partner_id: 3 }, { partner_id: 7, eligible: false, why: "paused", cause: "paused" })).toBe("paused");
    expect(decisionResultLabel({ mode: "commission_first", stage: "A", partner_id: 3 }, { partner_id: 7, eligible: false, cause: "caps" })).toContain("cap");
  });
});

describe("goliveBlocking", () => {
  const item = (o: Partial<GoliveItem>): GoliveItem => ({ key: "k", ok: false, blocking: true, why: null, acknowledgeable: false, acked: false, ack: null, ...o });
  it("keeps the blocking items that neither pass nor are acknowledged", () => {
    const items = [
      item({ key: "consent_texts_approved", ok: true }),
      item({ key: "witty_w1_consent_line", acknowledgeable: true, acked: true, ack: { reason: "Witty W1 is live", by: "u1", at: "2026-10-07T00:00:00Z" } }),
      item({ key: "b2c_endpoint_subscribed", why: "no endpoint subscribes to b2c.consent_requested" }),
      item({ key: "witty_w2_consent_request", acknowledgeable: true }),
      item({ key: "live_partner", blocking: false }),
    ];
    expect(goliveBlocking(items).map((i) => i.key)).toEqual(["b2c_endpoint_subscribed", "witty_w2_consent_request"]);
    expect(goliveBlocking([])).toEqual([]);
    expect(goliveBlocking(null)).toEqual([]);
  });
  it("treats an ack object as an acknowledgement when the flags are missing", () => {
    expect(goliveBlocking([{ key: "witty_w1_consent_line", ok: false, blocking: true, why: "x", ack: { reason: "ok", by: null, at: "2026-10-07T00:00:00Z" } }])).toEqual([]);
    expect(goliveBlocking([{ key: "witty_w1_consent_line", ok: false, blocking: true, why: "x", ack: null }]).length).toBe(1);
  });
});

describe("parseRuleForm", () => {
  it("builds the payload and drops empty conditions", () => {
    const r = parseRuleForm(form([["id", ""], ["name", " Meta MBA to Acme "], ["priority", "10"], ["action", "fix_partner"], ["partner_ids", "3"],
      ["sources", "meta_lead_ad, meta_lead_ad"], ["course_keys", "M.B.A."], ["states", ""], ["modes", "Online"], ["campaign_contains", ""]]));
    expect(r).toEqual({ ok: true, data: { id: null, name: "Meta MBA to Acme", priority: 10, action: "fix_partner", partner_ids: [3], b2c_lane: null,
      conditions: { sources: ["meta_lead_ad"], course_keys: ["mba"], modes: ["Online"] } } });
  });
  it("adds specializations, universities and the paid label (D38)", () => {
    const r = parseRuleForm(form([["id", "4"], ["name", "Finance MBA at Amity"], ["priority", "5"], ["action", "narrow"], ["partner_ids", "3"], ["partner_ids", "5"],
      ["specializations", "Finance, Marketing"], ["university_ids", "12"], ["university_ids", ""], ["paid", "yes"]]));
    expect(r).toMatchObject({ ok: true, data: { id: 4, partner_ids: [3, 5], conditions: { specializations: ["Finance", "Marketing"], university_ids: [12], paid: true } } });
    const organic = parseRuleForm(form([["id", ""], ["name", "Organic to B2C"], ["priority", "5"], ["action", "to_b2c"], ["b2c_lane", "sales"], ["paid", "no"]]));
    expect(organic).toMatchObject({ ok: true, data: { conditions: { paid: false } } });
    const any = parseRuleForm(form([["id", ""], ["name", "x"], ["priority", "5"], ["action", "exclude"], ["partner_ids", "3"], ["paid", "any"]]));
    expect(any.ok && any.data.conditions).toEqual({});
    expect(RuleSchema.safeParse({ id: "", name: "x", priority: "1", action: "exclude", partner_ids: ["3"], b2c_lane: null, sources: "", course_keys: "", specializations: "",
      states: "", university_ids: [], modes: [], levels: [], campaign_contains: "", paid: "maybe" }).success).toBe(false);
  });
  it("reports errors", () => {
    const r = parseRuleForm(form([["name", ""], ["action", "send_to_b2c"], ["priority", "x"]]));
    expect(r.ok).toBe(false);
    if (!r.ok) expect(Object.keys(r.errors).sort()).toEqual(["action", "name", "priority"]);
  });
});

describe("describeConditions", () => {
  it("summarises", () => {
    expect(describeConditions({})).toBe("Every lead");
    expect(describeConditions({ course_keys: ["mba"], modes: ["Online"], states: ["Delhi"] })).toBe("Leads for MBA, Online, in Delhi");
    expect(describeConditions({ course_keys: ["mba"], specializations: ["Finance"], university_ids: [12], paid: true }, { "12": "Amity" })).toBe("Leads for MBA, Finance, at Amity, from paid Meta / Google ads");
    expect(describeConditions({ university_ids: [12], paid: false })).toBe("Leads for at university #12, not from paid ads");
  });
});

const engineOk = {
  consent_policy: "ask", consent_admin_yes: undefined, consent_requests_per_hour: "100", witty_unqualified_idle_hours: "18", reenquiry_quiet_hours: "24",
  max_interests: "5", criteria_unknown: "fail", welcome_for_all_nurture: undefined, require_verified_phone_sources: "Website_Agent, web_agent",
  effort_enabled: "on", effort_lo: "0.85", effort_hi: "1.15",
  effort_w_first_call: "1", effort_w_attempts_72h: "1", effort_w_connect_rate: "1", effort_w_followup: "1", effort_w_acts_per_open: "1", effort_w_stale_share: "1",
  effort_min_sample: "10",
  sla_enabled: "on", sla_floor: "0.8", sla_ceiling: "1", sla_step: "0.05", sla_w_first_attempt: "1", sla_w_status_update: "1", sla_w_enrollment_proof: "1",
  requalify_enabled: "on", requalify_wait_for_chat_gate: "on", requalify_max_per_run: "25", guard_duplicate_rate_pause: undefined,
  half_life_days: "30", prior_weight: "20", default_p_enroll: "5", reason: "Addendum 3 defaults",
};

describe("EngineSchema (Addendum 3)", () => {
  it("has the editable keys and none of the fixed or retired ones (C6, D24)", () => {
    const keys = Object.keys(EngineSchema.shape);
    for (const k of ["consent_policy", "consent_admin_yes", "consent_requests_per_hour", "witty_unqualified_idle_hours", "reenquiry_quiet_hours", "max_interests",
                     "criteria_unknown", "welcome_for_all_nurture", "require_verified_phone_sources", "effort_enabled", "effort_lo", "effort_hi", "effort_min_sample",
                     "sla_enabled", "sla_floor", "sla_ceiling", "sla_step", "requalify_enabled", "requalify_max_per_run", "guard_duplicate_rate_pause",
                     "half_life_days", "prior_weight", "default_p_enroll", "reason"]) expect(keys, k).toContain(k);
    for (const k of ["kill_switch", "fixed_split", "exploration_share", "min_learning_leads", "attempt_limit", "partner_limit", "witty_idle_minutes", "cpe_aggregate",
                     "require_partner_consent", "speed_factor", "reliability_factor", "trusted_sources", "maturity_days", "a3_fixed", "mc_draws"]) expect(keys, k).not.toContain(k);
    expect(ENGINE_FIELDS).toEqual(keys);
  });

  it("parses the form into engine_settings_save's payload", () => {
    const p = EngineSchema.safeParse(engineOk);
    expect(p.success).toBe(true);
    if (!p.success) return;
    expect(enginePayload(p.data)).toEqual({
      consent_policy: "ask", consent_admin_yes: false, consent_requests_per_hour: 100, witty_unqualified_idle_hours: 18, reenquiry_quiet_hours: 24, max_interests: 5,
      criteria_unknown: "fail", welcome_for_all_nurture: false, require_verified_phone_sources: ["website_agent", "web_agent"],
      effort_factor: { enabled: true, bounds: [0.85, 1.15], weights: { first_call: 1, attempts_72h: 1, connect_rate: 1, followup: 1, acts_per_open: 1, stale_share: 1 }, min_sample: 10 },
      sla_factor: { enabled: true, floor: 0.8, ceiling: 1, step: 0.05, weights: { first_attempt: 1, status_update: 1, enrollment_proof: 1 } },
      requalify: { enabled: true, wait_for_chat_gate: true, max_per_run: 25 }, guard: { duplicate_rate_pause: false },
      half_life_days: 30, prior_weight: 20, default_p_enroll: 0.05,
    });
    expect(enginePayload(p.data)).not.toHaveProperty("reason");
  });

  it("knows no 'off' consent policy and the 18-hour idle range", () => {
    expect(EngineSchema.safeParse({ ...engineOk, consent_policy: "off" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, consent_policy: "b2c_sales" }).success).toBe(true);
    expect(EngineSchema.safeParse({ ...engineOk, witty_unqualified_idle_hours: "0" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, witty_unqualified_idle_hours: "73" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, consent_requests_per_hour: "5" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, reenquiry_quiet_hours: "200" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, max_interests: "11" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, criteria_unknown: "maybe" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, requalify_max_per_run: "5" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, half_life_days: "6" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, prior_weight: "101" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, default_p_enroll: "60" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, reason: "x" }).success).toBe(false);
  });

  it("fails a blank effort weight on that field, parses '0', fails a blank SLA floor (C63)", () => {
    const blank = EngineSchema.safeParse({ ...engineOk, effort_w_connect_rate: "" });
    expect(blank.success).toBe(false);
    if (!blank.success) expect(blank.error.issues.map((i) => String(i.path[0]))).toEqual(["effort_w_connect_rate"]);
    const zero = EngineSchema.safeParse({ ...engineOk, effort_w_connect_rate: "0" });
    expect(zero.success && zero.data.effort_w_connect_rate).toBe(0);
    const floor = EngineSchema.safeParse({ ...engineOk, sla_floor: "" });
    expect(floor.success).toBe(false);
    if (!floor.success) expect(floor.error.issues.map((i) => String(i.path[0]))).toEqual(["sla_floor"]);
    expect(EngineSchema.safeParse({ ...engineOk, effort_lo: "0.8" }).success).toBe(false);
    expect(EngineSchema.safeParse({ ...engineOk, sla_floor: "0.7" }).success).toBe(false);
  });
});

describe("RateSchema", () => {
  it("validates percent and fixed rates", () => {
    expect(RateSchema.safeParse({ partner_id: "4", rate_type: "percent", value: "20", fee_base: "first_year", valid_from: "", note: "" }).success).toBe(true);
    expect(RateSchema.safeParse({ partner_id: "4", rate_type: "percent", value: "120", fee_base: "first_year", valid_from: "", note: "" }).success).toBe(false);
    expect(RateSchema.safeParse({ partner_id: "4", rate_type: "fixed", value: "35000", fee_base: "total", gst_inclusive: "on", valid_from: "2026-11-01", note: "" }).success).toBe(true);
    expect(RateSchema.safeParse({ partner_id: "", rate_type: "fixed", value: "0", fee_base: "total", valid_from: "", note: "" }).success).toBe(false);
  });
  it("validates tiered rates by conversion", () => {
    const ok = RateSchema.safeParse({ partner_id: "4", rate_type: "tiered", tiers: "7: 20.42, 0: 22.42, 9%: 18.42%", fee_base: "first_year", valid_from: "", note: "" });
    expect(ok.success && ok.data.tiers).toEqual([{ from_pct: 0, pct: 22.42 }, { from_pct: 7, pct: 20.42 }, { from_pct: 9, pct: 18.42 }]);
    expect(ok.success && ok.data.value).toBe(null);
    expect(parseTiers("5: 20, 9: 18")).toBe("The first tier starts at 0% conversion");
    expect(parseTiers("0: 20")).toMatch(/2 to 10 tiers/);
    expect(parseTiers("0: 20, 7 20")).toMatch(/should look like/);
  });
});

describe("fromStored", () => {
  const interest = { course_key: "mba", specialization: null, level: "PG", mode: "Online", university_id: null, university_text: null, segment: "mba|PG|Online" };
  const cand: Candidate = { partner_id: 3, name: "Acme", status: "active", offers_count: 4, cpe: 16200, has_rate: true, daily_cap: null, monthly_cap: null,
    leads_today: 0, leads_month: 0, leads_week: 0, eligible: true, p_used: 0.071, p_source: "model", p_hat: 0.064, refund_rate: 0.02, score: 1127.2, tie_rank: 1,
    effort_factor: 1.04, sla_factor: 0.95, n_received: 44, first_lead_at: "2026-07-01T00:00:00Z", n_matured_c: 31, under_tested: false };
  const stored: StoredDecisionCore = {
    lead_id: 9, is_test: false, interest, destination_type: "partner", reason: null, mode: "performance", winner_partner_id: 3, partner_name: "Acme",
    candidates: [cand], excluded: null, rules: null, selection_probability: 1,
    allocation: { id: 5, reference: "EDW-5", status: "accepted", cpe_net_inr: 16200, b2c_lane: null, outcome: null, stage: "C", score_inr: 1127.2, origin: "auto",
                  effort_factor: 1.04, sla_factor: 0.95, p_enroll: 0.071, model_version: "v3", cause: null, ncpl_inr: 1150.5 },
    scoring_mode: "performance", holdout: false, seed: 0.31, policy_version: 2, settings_version: 7, stats_at: "2026-10-07T00:00:00Z",
    stage: "C", score: 1127.2, eval_segment: "mba|PG|Online", segment_exact: "mba|PG|Online|u12", class: "qualified", interest_rank: 1,
    interests: [{ rank: 1, course_key: "mba", course_text: "MBA", segment: "mba|PG|Online", outcome: "routed" }],
    attribution: { paid: true, platform: "meta", signal: "leadgen", label: "Meta Lead Ads", campaign_id: "c1", origin: "meta_lead_ad" },
    hold: null, bar: null, how: "auto", holdout_share: 0.1, draw: null, model_version: "v3", feature_hash: "0123456789abcdef0123456789abcdef", shadow: { v4: { "3": 0.07 } },
  };

  it("rebuilds the view of an A3 decision (C61, C112)", () => {
    const d = fromStored(stored);
    expect(d).toMatchObject({
      destination: "partner", partner_id: 3, cpe: 16200, ncpl: 1150.5, has_rate: true, committed: true, already_routed: true, reference: "EDW-5", allocation_id: 5,
      stage: "C", score: 1127.2, eval_segment: "mba|PG|Online", segment_exact: "mba|PG|Online|u12", draw: null, exploration_share: 0, holdout: false, holdout_share: 0.1,
      model_version: "v3", feature_hash: "0123456789abcdef0123456789abcdef", shadow: { v4: { "3": 0.07 } }, how: "auto", origin: "auto", interest_rank: 1,
      paid: "Meta Lead Ads", outcome: "decided", seed: 0.31, policy_version: 2, settings_version: 7, scoring_mode: "performance",
    });
    expect(d.lane).toEqual({ applied: false, x_partner_id: null });
    expect(d.candidates[0]).toMatchObject({ p_used: 0.071, p_source: "model", score: 1127.2, tie_rank: 1 });
    expect(d.readiness).toMatchObject({ ready: true, class: "qualified", paid: "Meta Lead Ads", paid_platform: "meta" });
    expect(d.interests).toHaveLength(1);
    expect(d.selection_probability).toBe(1);
    expect(d).not.toHaveProperty("pinned");
    expect(d).not.toHaveProperty("mc_draws");
  });

  it("marks the exploration lane from the stored draw", () => {
    const d = fromStored({ ...stored, mode: "exploration", draw: 0.031, stage: "A", scoring_mode: "commission_first" });
    expect(d).toMatchObject({ draw: 0.031, exploration_share: 0.2, lane: { applied: true, x_partner_id: 3 } });
  });

  it("rebuilds a B2C decision and a legacy row", () => {
    const b = fromStored({ lead_id: 9, is_test: false, interest, destination_type: "in_house", reason: "no_partner_consent", mode: "fallback",
      winner_partner_id: null, partner_name: null, candidates: null, excluded: null, rules: null, selection_probability: null, allocation: null });
    expect(b).toMatchObject({ destination: "in_house", cpe: null, ncpl: null, candidates: [], selection_probability: 1, reference: undefined, stage: null, score: null,
      draw: null, exploration_share: 0, holdout_share: null, model_version: null, feature_hash: null, paid: null, cause: null });
    const legacy = fromStored({ ...stored, stage: undefined, score: undefined, draw: undefined, holdout_share: undefined, allocation: { ...stored.allocation!, stage: null, score_inr: null, cause: "caps" } });
    expect(legacy).toMatchObject({ stage: null, score: 1127.2, cause: "caps" });
  });
});

describe("rules that send to B2C", () => {
  it("needs a lane and drops partners", () => {
    const base: [string, string][] = [["id", ""], ["name", "Goa to nurture"], ["priority", "5"], ["action", "to_b2c"], ["states", "Goa"], ["partner_ids", "3"]];
    expect(parseRuleForm(form(base))).toMatchObject({ ok: false, errors: { b2c_lane: "Choose sales or nurture" } });
    const r = parseRuleForm(form([...base, ["b2c_lane", "nurture"]]));
    expect(r).toMatchObject({ ok: true, data: { action: "to_b2c", b2c_lane: "nurture", partner_ids: [], conditions: { states: ["Goa"] } } });
    const s = parseRuleForm(form([...base, ["b2c_lane", "sales"]]));
    expect(s).toMatchObject({ ok: true, data: { b2c_lane: "sales" } });
  });
  it("still needs partners for partner rules", () => {
    const r = parseRuleForm(form([["id", ""], ["name", "x"], ["priority", "5"], ["action", "narrow"], ["b2c_lane", "sales"]]));
    expect(r).toMatchObject({ ok: false, errors: { partner_ids: "Choose at least one partner" } });
  });
});

describe("hand-off settings (D38, R5)", () => {
  const ok = { b2c_sources: "b2c_created", blocked_phones: "+91 98111 00009", junk_capi_signal: undefined, spam_use_witty_blocks: "on",
    spam_disposable_email_domains: "Mailinator.com\nyopmail.com", spam_max_leads_per_ip_hour: "5", spam_max_leads_per_fingerprint_hour: "5", reason: "spam rules" };
  it("builds the payload without a paid rule", () => {
    const p = HandoffSchema.safeParse(ok);
    expect(p.success).toBe(true);
    if (!p.success) return;
    expect(handoffPayload(p.data)).toEqual({
      b2c_sources: ["b2c_created"], blocked_phones: ["+91 98111 00009"], junk_capi_signal: false,
      spam: { use_witty_blocks: true, disposable_email_domains: ["mailinator.com", "yopmail.com"], max_leads_per_ip_hour: 5, max_leads_per_fingerprint_hour: 5 },
    });
    expect(handoffPayload(p.data)).not.toHaveProperty("paid_rule");
    expect(Object.keys(HandoffSchema.shape)).not.toContain("sources");
  });
  it("rejects short phones, bad domains, a blank or out-of-range burst limit and a missing reason", () => {
    expect(HandoffSchema.safeParse({ ...ok, blocked_phones: "12345" }).success).toBe(false);
    expect(HandoffSchema.safeParse({ ...ok, spam_disposable_email_domains: "not a domain" }).success).toBe(false);
    expect(HandoffSchema.safeParse({ ...ok, spam_max_leads_per_ip_hour: "" }).success).toBe(false);
    expect(HandoffSchema.safeParse({ ...ok, spam_max_leads_per_ip_hour: "0" }).success).toBe(false);
    expect(HandoffSchema.safeParse({ ...ok, spam_max_leads_per_fingerprint_hour: "101" }).success).toBe(false);
    expect(HandoffSchema.safeParse({ ...ok, reason: "" }).success).toBe(false);
  });
});

describe("attribution settings (D38)", () => {
  const ok = { influencer_lead_sources: "Influencer, referral", influencer_utm_values: "influencer", exclude_campaigns: "Brand", meta_ad_params: "ad_id, adset_id", reason: "influencers are organic" };
  it("builds attribution_settings_save's payload, lower-cased", () => {
    const p = AttributionSchema.safeParse(ok);
    expect(p.success).toBe(true);
    if (!p.success) return;
    expect(attributionPayload(p.data)).toEqual({
      influencer_markers: { lead_sources: ["influencer", "referral"], utm_values: ["influencer"] }, exclude_campaigns: ["brand"], meta_ad_params: ["ad_id", "adset_id"],
    });
  });
  it("refuses bad Meta parameter names, long entries and a missing reason", () => {
    expect(AttributionSchema.safeParse({ ...ok, meta_ad_params: "ad id" }).success).toBe(false);
    expect(AttributionSchema.safeParse({ ...ok, exclude_campaigns: "x".repeat(61) }).success).toBe(false);
    expect(AttributionSchema.safeParse({ ...ok, reason: "" }).success).toBe(false);
    expect(AttributionSchema.safeParse({ ...ok, influencer_lead_sources: "" }).success).toBe(true);
  });
});
