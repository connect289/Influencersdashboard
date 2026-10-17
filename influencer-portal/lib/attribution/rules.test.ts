import { describe, expect, it } from "vitest";
import { creditHolder, decide, type LeadFacts, type Rules, type Touch } from "./rules";

const rules: Rules = { window_days: 90, model: "first_touch_with_assisted", duplicate_grace_minutes: 10, reenquiry_credit_after_days: null };
const t = (creator: string, at: string, over: Partial<Touch> = {}): Touch => ({
  code: `${creator.toUpperCase()}-IG-AA`,
  link_id: `link-${creator}`,
  creator_id: creator,
  deal_id: null,
  deliverable_id: null,
  campaign_id: null,
  at,
  source: "click",
  ...over,
});
const lead = (created_at: string, touches: Touch[], over: Partial<LeadFacts> = {}): LeadFacts => ({
  created_at,
  reopened_at: null,
  touches,
  self_referral_creators: [],
  ...over,
});
const summary = (l: LeadFacts, r: Rules = rules, existing = []) =>
  decide(l, r, existing).map((d) => `${d.creator_id}:${d.touch}:${d.status}${d.reason ? `:${d.reason}` : ""}`);

describe("attribution: single touch", () => {
  it("credits a click shortly before the lead appeared", () => {
    expect(summary(lead("2026-11-01T10:05:00Z", [t("riya", "2026-11-01T10:00:00Z")]))).toEqual(["riya:first:credited"]);
  });
  it("credits a typed code that arrives with the first message (Route B)", () => {
    expect(summary(lead("2026-11-01T10:00:00Z", [t("riya", "2026-11-01T10:03:00Z", { source: "referral_code" })]))).toEqual(["riya:first:credited"]);
  });
  it("a lead that existed before the touch is a duplicate", () => {
    expect(summary(lead("2026-10-01T10:00:00Z", [t("riya", "2026-11-01T10:00:00Z")]))).toEqual(["riya:none:duplicate:existing_lead"]);
  });
  it("the duplicate grace covers small clock differences", () => {
    expect(summary(lead("2026-11-01T09:51:00Z", [t("riya", "2026-11-01T10:00:00Z")]))).toEqual(["riya:first:credited"]);
    expect(summary(lead("2026-11-01T09:49:00Z", [t("riya", "2026-11-01T10:00:00Z")]))).toEqual(["riya:none:duplicate:existing_lead"]);
  });
  it("the window is measured from the touch to the lead", () => {
    expect(summary(lead("2027-01-30T10:00:00Z", [t("riya", "2026-11-01T10:00:00Z")]))).toEqual(["riya:first:credited"]);
    expect(summary(lead("2027-01-30T10:00:01Z", [t("riya", "2026-11-01T10:00:00Z")]))).toEqual(["riya:none:outside_window:outside_window"]);
    expect(summary(lead("2026-11-08T10:00:00Z", [t("riya", "2026-11-01T10:00:00Z")]), { ...rules, window_days: 7 })).toEqual(["riya:first:credited"]);
  });
  it("self-referral wins over every other outcome", () => {
    expect(summary(lead("2026-10-01T00:00:00Z", [t("riya", "2026-11-01T10:00:00Z")], { self_referral_creators: ["riya"] }))).toEqual([
      "riya:none:self_referral:self_referral",
    ]);
  });
  it("no touches, no decisions", () => {
    expect(decide(lead("2026-11-01T00:00:00Z", []), rules)).toEqual([]);
  });
});

describe("attribution: several creators", () => {
  const l = lead("2026-11-03T12:00:00Z", [t("arjun", "2026-11-02T09:00:00Z"), t("riya", "2026-11-01T09:00:00Z"), t("neha", "2026-11-03T11:00:00Z")]);
  it("first touch with assisted: the earliest is credited, the others assisted", () => {
    expect(summary(l)).toEqual(["riya:first:credited", "arjun:assisted:credited", "neha:assisted:credited"]);
  });
  it("first touch: the others are told another creator came first", () => {
    expect(summary(l, { ...rules, model: "first_touch" })).toEqual([
      "riya:first:credited",
      "arjun:none:duplicate:another_creator",
      "neha:none:duplicate:another_creator",
    ]);
  });
  it("last touch: the latest is credited", () => {
    expect(summary(l, { ...rules, model: "last_touch" })).toEqual([
      "riya:none:duplicate:another_creator",
      "arjun:none:duplicate:another_creator",
      "neha:last:credited",
    ]);
  });
  it("an ineligible earlier touch does not block a later eligible one", () => {
    const x = lead("2026-11-03T12:00:00Z", [t("riya", "2026-11-01T09:00:00Z"), t("arjun", "2026-11-02T09:00:00Z")], { self_referral_creators: ["riya"] });
    expect(summary(x)).toEqual(["riya:none:self_referral:self_referral", "arjun:first:credited"]);
  });
  it("only one creator is ever credited per lead", () => {
    for (const model of ["first_touch", "last_touch", "first_touch_with_assisted"] as const) {
      const ds = decide(l, { ...rules, model });
      expect(ds.filter((d) => d.status === "credited" && d.touch !== "assisted")).toHaveLength(1);
      expect(creditHolder(ds)).not.toBeNull();
    }
  });
  it("ties are broken deterministically by code", () => {
    const x = lead("2026-11-03T12:00:00Z", [t("b", "2026-11-01T09:00:00Z"), t("a", "2026-11-01T09:00:00Z")]);
    expect(summary(x)[0]).toBe("a:first:credited");
  });
});

describe("attribution: one creator, several touches", () => {
  it("uses the creator's earliest eligible touch (first-touch models) and latest (last touch)", () => {
    const l = lead("2026-11-03T12:00:00Z", [
      t("riya", "2026-11-02T09:00:00Z", { code: "RIYA-YT-BB", link_id: "yt" }),
      t("riya", "2026-11-01T09:00:00Z", { code: "RIYA-IG-AA", link_id: "ig" }),
    ]);
    expect(decide(l, rules).map((d) => d.link_id)).toEqual(["ig"]);
    expect(decide(l, { ...rules, model: "last_touch" }).map((d) => d.link_id)).toEqual(["yt"]);
  });
  it("prefers an eligible touch over an earlier ineligible one", () => {
    const l = lead("2026-11-03T12:00:00Z", [
      t("riya", "2026-06-01T09:00:00Z", { link_id: "old" }),
      t("riya", "2026-11-02T09:00:00Z", { link_id: "new" }),
    ]);
    expect(decide(l, rules).map((d) => `${d.link_id}:${d.status}`)).toEqual(["new:credited"]);
  });
});

describe("attribution: re-enquiries", () => {
  const base = lead("2026-01-01T00:00:00Z", [t("riya", "2026-11-01T09:00:00Z")], { reopened_at: "2026-11-01T10:00:00Z" });
  it("are duplicates by default", () => {
    expect(summary(base)).toEqual(["riya:none:duplicate:existing_lead"]);
  });
  it("can be credited after the configured gap", () => {
    expect(summary(base, { ...rules, reenquiry_credit_after_days: 180 })).toEqual(["riya:first:credited"]);
    expect(summary(base, { ...rules, reenquiry_credit_after_days: 365 })).toEqual(["riya:none:duplicate:existing_lead"]);
  });
  it("a touch after the re-enquiry is still a duplicate", () => {
    const l = { ...base, touches: [t("riya", "2026-11-05T09:00:00Z")] };
    expect(summary(l, { ...rules, reenquiry_credit_after_days: 180 })).toEqual(["riya:none:duplicate:existing_lead"]);
  });
});

describe("attribution: staff decisions are sticky", () => {
  const l = lead("2026-11-03T12:00:00Z", [t("riya", "2026-11-01T09:00:00Z"), t("arjun", "2026-11-02T09:00:00Z")]);
  it("a manual rejection stays rejected and the credit moves to the next eligible creator", () => {
    expect(summary(l, rules, [{ creator_id: "riya", status: "manually_rejected" }] as never)).toEqual([
      "riya:none:manually_rejected",
      "arjun:first:credited",
    ]);
  });
  it("a manual credit takes the credit from the computed winner", () => {
    const ds = decide(l, { ...rules, model: "first_touch" }, [{ creator_id: "arjun", status: "manually_credited" }]);
    expect(ds.map((d) => `${d.creator_id}:${d.status}`)).toEqual(["riya:duplicate", "arjun:manually_credited"]);
    expect(creditHolder(ds)?.creator_id).toBe("arjun");
  });
  it("a fraud review stays open until staff decide", () => {
    expect(summary(l, rules, [{ creator_id: "riya", status: "fraud_suspected" }] as never)[0]).toBe("riya:first:fraud_suspected");
  });
  it("a computed status that is not sticky is recomputed", () => {
    expect(summary(l, rules, [{ creator_id: "riya", status: "duplicate" }] as never)[0]).toBe("riya:first:credited");
  });
  it("is deterministic", () => {
    expect(decide(l, rules)).toEqual(decide(l, rules));
  });
});
