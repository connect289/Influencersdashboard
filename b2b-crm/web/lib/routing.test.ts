import { describe, expect, it } from "vitest";
import { describeConditions, EngineSchema, fromStored, parseRuleForm, RateSchema, segmentLabel } from "./routing";

function form(entries: [string, string][]): FormData {
  const f = new FormData();
  for (const [k, v] of entries) f.append(k, v);
  return f;
}

describe("segmentLabel", () => {
  it("reads segments", () => {
    expect(segmentLabel("mba|PG|Online")).toBe("MBA · PG · Online");
    expect(segmentLabel("bcom|UG|*")).toBe("BCOM · UG · any");
    expect(segmentLabel(null)).toBe("—");
  });
});

describe("parseRuleForm", () => {
  it("builds the payload and drops empty conditions", () => {
    const r = parseRuleForm(form([["id", ""], ["name", " Meta MBA to Acme "], ["priority", "10"], ["action", "fix_partner"], ["partner_ids", "3"],
      ["sources", "meta_lead_ad, meta_lead_ad"], ["course_keys", "M.B.A."], ["states", ""], ["modes", "Online"], ["campaign_contains", ""]]));
    expect(r).toEqual({ ok: true, data: { id: null, name: "Meta MBA to Acme", priority: 10, action: "fix_partner", partner_ids: [3],
      conditions: { sources: ["meta_lead_ad"], course_keys: ["mba"], modes: ["Online"] } } });
  });
  it("reports errors", () => {
    const r = parseRuleForm(form([["name", ""], ["action", "send_to_b2c"], ["priority", "x"]]));
    expect(r.ok).toBe(false);
    if (!r.ok) expect(Object.keys(r.errors).sort()).toEqual(["action", "name", "partner_ids", "priority"]);
  });
});

describe("describeConditions", () => {
  it("summarises", () => {
    expect(describeConditions({})).toBe("Every lead");
    expect(describeConditions({ course_keys: ["mba"], modes: ["Online"], states: ["Delhi"] })).toBe("Leads for MBA, Online, in Delhi");
  });
});

describe("EngineSchema", () => {
  it("turns a percentage into a share and checks bounds", () => {
    const ok = EngineSchema.safeParse({ exploration_share: "20", cpe_aggregate: "median", min_learning_leads: "30", attempt_limit: "2", partner_limit: "3",
      witty_idle_minutes: "30", require_partner_consent: "on", trusted_sources: "whatsapp_direct, meta_lead_ad", reason: "Tuning" });
    expect(ok.success && ok.data).toMatchObject({ exploration_share: 0.2, require_partner_consent: true, trusted_sources: ["whatsapp_direct", "meta_lead_ad"] });
    expect(EngineSchema.safeParse({ exploration_share: "60", cpe_aggregate: "median", min_learning_leads: "30", attempt_limit: "2", partner_limit: "3",
      witty_idle_minutes: "30", trusted_sources: "", reason: "x" }).success).toBe(false);
  });
});

describe("RateSchema", () => {
  it("validates percent and fixed rates", () => {
    expect(RateSchema.safeParse({ partner_id: "4", rate_type: "percent", value: "20", fee_base: "first_year", valid_from: "", note: "" }).success).toBe(true);
    expect(RateSchema.safeParse({ partner_id: "4", rate_type: "percent", value: "120", fee_base: "first_year", valid_from: "", note: "" }).success).toBe(false);
    expect(RateSchema.safeParse({ partner_id: "4", rate_type: "fixed", value: "35000", fee_base: "total", gst_inclusive: "on", valid_from: "2026-11-01", note: "" }).success).toBe(true);
    expect(RateSchema.safeParse({ partner_id: "", rate_type: "fixed", value: "0", fee_base: "total", valid_from: "", note: "" }).success).toBe(false);
  });
});

describe("fromStored", () => {
  it("rebuilds the view of a stored decision", () => {
    const interest = { course_key: "mba", specialization: null, level: "PG", mode: "Online", university_id: null, university_text: null, segment: "mba|PG|Online" };
    const cand = { partner_id: 3, name: "Acme", status: "active", offers: 4, cpe: 16200, has_rate: true, ncpl: null, daily_cap: null, monthly_cap: null,
      leads_today: 0, leads_month: 0, leads_week: 0, segment_leads: 0, eligible: true };
    const d = fromStored({ lead_id: 9, is_test: false, interest, destination_type: "partner", reason: null, mode: "commission_first", winner_partner_id: 3,
      partner_name: "Acme", candidates: [cand], excluded: null, rules: null, selection_probability: 0.8, allocation: { reference: "EDW-5", cpe_net_inr: 16200 } });
    expect(d).toMatchObject({ destination: "partner", partner_id: 3, cpe: 16200, has_rate: true, committed: true, reference: "EDW-5", draw: null, excluded: [] });
    expect(d.selection_probability).toBe(0.8);
    const b = fromStored({ lead_id: 9, is_test: false, interest, destination_type: "in_house", reason: "no_partner_consent", mode: "fallback",
      winner_partner_id: null, partner_name: null, candidates: null, excluded: null, rules: null, selection_probability: null, allocation: null });
    expect(b).toMatchObject({ destination: "in_house", cpe: null, candidates: [], selection_probability: 1, reference: undefined });
  });
});
