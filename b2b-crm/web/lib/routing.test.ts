import { describe, expect, it } from "vitest";
import { describeConditions, EngineSchema, fromStored, HandoffSchema, handoffPayload, parseRuleForm, parseTiers, RateSchema, segmentLabel } from "./routing";

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
    expect(r).toEqual({ ok: true, data: { id: null, name: "Meta MBA to Acme", priority: 10, action: "fix_partner", partner_ids: [3], b2c_lane: null,
      conditions: { sources: ["meta_lead_ad"], course_keys: ["mba"], modes: ["Online"] } } });
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

describe("rules that send to B2C", () => {
  it("needs a lane and drops partners", () => {
    const base: [string, string][] = [["id", ""], ["name", "Goa to nurture"], ["priority", "5"], ["action", "to_b2c"], ["states", "Goa"], ["partner_ids", "3"]];
    expect(parseRuleForm(form(base))).toMatchObject({ ok: false, errors: { b2c_lane: "Choose sales or nurture" } });
    const r = parseRuleForm(form([...base, ["b2c_lane", "nurture"]]));
    expect(r).toMatchObject({ ok: true, data: { action: "to_b2c", b2c_lane: "nurture", partner_ids: [], conditions: { states: ["Goa"] } } });
  });
  it("still needs partners for partner rules", () => {
    const r = parseRuleForm(form([["id", ""], ["name", "x"], ["priority", "5"], ["action", "narrow"], ["b2c_lane", "sales"]]));
    expect(r).toMatchObject({ ok: false, errors: { partner_ids: "Choose at least one partner" } });
  });
});

describe("hand-off settings", () => {
  const ok = { sources: "meta_lead_ad, google_lead_form", click_ids: "gclid\nfbclid", utm_mediums: "cpc", include_campaigns: "", exclude_campaigns: "brand",
    b2c_sources: "b2c_created", blocked_phones: "+91 98111 00009", reason: "paid rule for Google" };
  it("builds the payload", () => {
    const p = HandoffSchema.safeParse(ok);
    expect(p.success).toBe(true);
    if (!p.success) return;
    expect(handoffPayload(p.data)).toEqual({
      paid_rule: { sources: ["meta_lead_ad", "google_lead_form"], click_ids: ["gclid", "fbclid"], utm_mediums: ["cpc"], include_campaigns: [], exclude_campaigns: ["brand"] },
      b2c_sources: ["b2c_created"], blocked_phones: ["+91 98111 00009"], junk_capi_signal: false,
    });
  });
  it("rejects short phones and a missing reason", () => {
    expect(HandoffSchema.safeParse({ ...ok, blocked_phones: "12345" }).success).toBe(false);
    expect(HandoffSchema.safeParse({ ...ok, reason: "" }).success).toBe(false);
  });
});
