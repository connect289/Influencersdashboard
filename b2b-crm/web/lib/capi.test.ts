import { describe, expect, it } from "vitest";
import {
  ATTRIBUTION_LIST_FIELDS, ATTRIBUTION_SIGNALS, NOT_PAID_HINT, SIGNAL_LABEL, STAGES, STAGE_LABEL, attributionDefaults, attributionLabel, attributionProblems,
  formatInr, keyShare, originLabel, platformTotals, rate, settingsProblems, valuesProblems, type GoogleMap, type MetaMap,
} from "./capi";
import { AttributionSchema, attributionPayload } from "./routing";

const metaMap = Object.fromEntries(STAGES.map((s) => [s, { event: "Event", enabled: true }])) as MetaMap;
const googleMap = Object.fromEntries(STAGES.map((s) => [s, { action: null, enabled: true }])) as GoogleMap;

describe("capi", () => {
  it("adds up a platform's statuses", () => {
    expect(platformTotals({ "meta.sent": 4, "meta.held": 2, "meta.pending": 1, "meta.rejected": 1, "meta.dead": 1, "google.sent": 9 }, "meta"))
      .toEqual({ sent: 4, waiting: 3, problems: 2, dry_run: 0, skipped: 0 });
  });
  it("computes match-key shares", () => {
    expect(keyShare({ events: 8, keys: { email: 6 } }, "email")).toBe(75);
    expect(keyShare({ events: 8, keys: {} }, "phone")).toBe(0);
    expect(keyShare(undefined, "phone")).toBe(0);
  });
  it("checks the settings form", () => {
    expect(settingsProblems({ meta: { dataset_id: "", api_version: "", map: metaMap }, google: { customer_id: "", login_customer_id: "", api_version: "", map: googleMap } })).toEqual({});
    const e = settingsProblems({
      meta: { dataset_id: "pixel1", api_version: "21", map: { ...metaMap, applied: { event: " ", enabled: true } } },
      google: { customer_id: "123-456-789", login_customer_id: "1234567890", api_version: "v21", map: { ...googleMap, enrolled: { action: "5", enabled: true } } },
    });
    expect(Object.keys(e).sort()).toEqual(["google.customer_id", "google.map.enrolled", "meta.api_version", "meta.dataset_id", "meta.map.applied"]);
  });
  it("formats rupees", () => {
    expect(formatInr(150000)).toBe("₹1,50,000");
    expect(formatInr(null)).toBe("—");
  });
});

describe("signal ladder", () => {
  it("lists the strongest signals first", () => {
    expect(STAGES.slice(0, 5)).toEqual(["verified", "enrolled", "applied", "interested", "qualified"]);
    expect(STAGE_LABEL.applied.label).toBe("Applicant");
  });
  it("explains the qualified milestone by class, not by hand-off (m31g capi_milestones)", () => {
    expect(STAGE_LABEL.qualified.hint).toMatch(/Classed as qualified/);
    expect(STAGE_LABEL.qualified.hint).toMatch(/consent/);
    expect(STAGE_LABEL.qualified.hint).toMatch(/nurture hand-off alone does not count/);
  });
  it("checks the values form", () => {
    const ok = { pct: { applied: "40", interested: "15", qualified: "5" }, base: "15000" };
    expect(valuesProblems(ok)).toEqual({});
    expect(valuesProblems({ ...ok, pct: { ...ok.pct, applied: "140" } })).toHaveProperty("values.applied");
    expect(valuesProblems({ ...ok, pct: { ...ok.pct, qualified: "" } })).toHaveProperty("values.qualified");
    expect(valuesProblems({ ...ok, base: "-1" })).toHaveProperty("base");
    expect(valuesProblems({ ...ok, pct: { applied: "10", interested: "15", qualified: "5" } })).toHaveProperty("order");
  });
  it("computes rates", () => {
    expect(rate(1, 4)).toBe(25);
    expect(rate(1, 0)).toBeNull();
  });
});

describe("paid labels (Addendum 3, D38)", () => {
  it("labels paid leads with b2b.lead_attribution's label", () => {
    expect(attributionLabel({ paid: true, platform: "google", label: "Google ad click", signal: "gclid" })).toBe("Paid: Google ad click");
    expect(attributionLabel({ paid: true, platform: "meta", label: "Meta click-to-WhatsApp", signal: "ctwa_clid" })).toBe("Paid: Meta click-to-WhatsApp");
    expect(attributionLabel({ paid: true, platform: "meta", label: "Meta Lead Ads", signal: "meta_lead_form" })).toBe("Paid: Meta Lead Ads");
    expect(attributionLabel({ paid: true, platform: "meta", label: null, signal: "fbclid" })).toBe("Paid: Meta ad");
  });
  it("says why a lead is not paid", () => {
    expect(attributionLabel({ paid: false, platform: "other", label: null, signal: "utm_only" })).toBe("Not paid: UTM only");
    expect(attributionLabel({ paid: false, platform: "none", label: null, signal: "influencer_referral" })).toBe("Not paid: influencer or referral");
    expect(attributionLabel({ paid: false, platform: "meta", label: null, signal: "organic_form" })).toBe("Not paid: organic");
    expect(attributionLabel({ paid: false, platform: "meta", label: null, signal: "excluded_campaign" })).toBe("Not paid: excluded campaign");
    expect(attributionLabel({ paid: false, platform: "none", label: null, signal: "none" })).toBe("Not paid: no ad");
    expect(attributionLabel({ paid: false, platform: "none" })).toBe("Not paid: no ad");
  });
  it("names every signal and explains every not-paid one", () => {
    for (const s of ATTRIBUTION_SIGNALS) expect(SIGNAL_LABEL[s]).toBeTruthy();
    for (const s of ["influencer_referral", "excluded_campaign", "organic_form", "utm_only", "none"] as const) expect(NOT_PAID_HINT[s]).toBeTruthy();
    expect(NOT_PAID_HINT.gclid).toBeUndefined();
  });
  it("reads the origin", () => {
    expect(originLabel("meta_lead_form")).toBe("Meta lead form intake");
    expect(originLabel("google_lead_form")).toBe("Google lead form intake");
    expect(originLabel("lead")).toBe("the lead record");
    expect(originLabel("witty")).toBe("a Witty touchpoint");
    expect(originLabel("website")).toBe("a website touchpoint");
    expect(originLabel(null)).toBe("—");
  });
});

describe("Attribution card", () => {
  const ok = { influencer_lead_sources: "Influencer, referral\naffiliate", influencer_utm_values: "", exclude_campaigns: "brand", meta_ad_params: "ad_id, utm_id", reason: "October influencer codes" };

  it("fills the card from the stored setting", () => {
    expect(attributionDefaults({ influencer_markers: { lead_sources: ["influencer", "referral"], utm_values: ["affiliate"] }, exclude_campaigns: [], meta_ad_params: ["ad_id", "utm_id"] }))
      .toEqual({ influencer_lead_sources: "influencer, referral", influencer_utm_values: "affiliate", exclude_campaigns: "", meta_ad_params: "ad_id, utm_id" });
    expect(attributionDefaults(null)).toEqual({ influencer_lead_sources: "", influencer_utm_values: "", exclude_campaigns: "", meta_ad_params: "" });
    expect(Object.keys(attributionDefaults({})).sort()).toEqual([...ATTRIBUTION_LIST_FIELDS].sort());
  });
  it("accepts a valid card and builds attribution_settings_save's payload", () => {
    expect(attributionProblems(ok)).toEqual({});
    const p = AttributionSchema.safeParse(ok);
    expect(p.success).toBe(true);
    if (p.success) {
      expect(attributionPayload(p.data)).toEqual({
        influencer_markers: { lead_sources: ["influencer", "referral", "affiliate"], utm_values: [] },
        exclude_campaigns: ["brand"],
        meta_ad_params: ["ad_id", "utm_id"],
      });
    }
  });
  it("reports problems field by field", () => {
    expect(attributionProblems({ ...ok, reason: "" })).toHaveProperty("reason");
    expect(attributionProblems({ ...ok, meta_ad_params: "ad id" })).toHaveProperty("meta_ad_params");
    expect(attributionProblems({ ...ok, exclude_campaigns: "x".repeat(61) })).toHaveProperty("exclude_campaigns");
    expect(attributionProblems({ ...ok, influencer_utm_values: "y".repeat(61) })).toHaveProperty("influencer_utm_values");
    expect(Object.keys(attributionProblems({ ...ok, reason: "", meta_ad_params: "ad id" })).sort()).toEqual(["meta_ad_params", "reason"]);
  });
});
