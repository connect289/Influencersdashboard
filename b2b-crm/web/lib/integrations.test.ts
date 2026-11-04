import { describe, expect, it } from "vitest";
import {
  ApiKeySchema, apiKeyFrom, B2C_DEFAULT_EVENTS, B2C_INBOUND_EVENTS, B2C_REQUIRED_EVENTS, describeEvents, endpointHealth, EndpointSchema, eventSubscribed, parseHandoffsQuery,
  parseReferralCodes, parseReferralQuery, PUBLISHED_EVENTS, referralCodesProblem, type EndpointRow,
} from "./integrations";

const endpoint = (x: Partial<EndpointRow>): EndpointRow => ({
  id: 1, name: "B2C CRM", consumer: "b2c_crm", url: "https://b2c.example/hooks", events: ["b2c.*"], active: true, has_secret: true,
  last_success_at: null, last_failure_at: null, last_error: null, pending: 0, dead: 0, delivered_24h: 0, created_at: "2026-10-06T10:00:00Z", ...x,
});

const V3_EVENTS = ["b2c.lead_requalified", "b2c.lead_reengaged", "b2c.consent_requested", "b2c.consent_closed"];

describe("API key from headers", () => {
  it("reads a Bearer token or x-api-key", () => {
    expect(apiKeyFrom(new Headers({ authorization: "Bearer ewk_abc" }))).toBe("ewk_abc");
    expect(apiKeyFrom(new Headers({ authorization: "bearer  ewk_abc " }))).toBe("ewk_abc");
    expect(apiKeyFrom(new Headers({ "x-api-key": "ewk_xyz" }))).toBe("ewk_xyz");
    expect(apiKeyFrom(new Headers({ authorization: "Basic abc" }))).toBe("");
    expect(apiKeyFrom(new Headers())).toBe("");
  });
});

describe("handoffs query", () => {
  it("defaults and validates", () => {
    expect(parseHandoffsQuery(new URLSearchParams())).toEqual({ ok: true, q: { since: null, after: null, limit: 200 } });
    expect(parseHandoffsQuery(new URLSearchParams("after=6460&limit=50"))).toEqual({ ok: true, q: { since: null, after: 6460, limit: 50 } });
    const s = parseHandoffsQuery(new URLSearchParams("since=2026-10-06T00:00:00%2B05:30"));
    expect(s.ok && s.q.since).toBe("2026-10-05T18:30:00.000Z");
  });
  it("refuses bad values", () => {
    expect(parseHandoffsQuery(new URLSearchParams("after=-1")).ok).toBe(false);
    expect(parseHandoffsQuery(new URLSearchParams("after=1e5")).ok).toBe(false);
    expect(parseHandoffsQuery(new URLSearchParams("limit=0")).ok).toBe(false);
    expect(parseHandoffsQuery(new URLSearchParams("limit=501")).ok).toBe(false);
    expect(parseHandoffsQuery(new URLSearchParams("since=yesterday")).ok).toBe(false);
    expect(parseHandoffsQuery(new URLSearchParams("since=")).ok).toBe(false);
  });
});

describe("endpoint form", () => {
  it("requires https and known events", () => {
    expect(EndpointSchema.safeParse({ name: "B2C", consumer: "b2c_crm", url: "http://x.example", events: ["b2c.*"] }).success).toBe(false);
    expect(EndpointSchema.safeParse({ name: "B2C", consumer: "b2c_crm", url: "https://x.example/h", events: ["lead.nope"] }).success).toBe(false);
    expect(EndpointSchema.safeParse({ name: "B2C", consumer: "b2c_crm", url: "https://x.example/h", events: [] }).success).toBe(false);
    expect(EndpointSchema.safeParse({ name: "B2C", consumer: "b2c_crm", url: "https://x.example/h", events: ["b2c.*", "lead.enrolled"] }).success).toBe(true);
  });
  it("accepts the contract version 3 event types one by one", () => {
    expect(EndpointSchema.safeParse({ name: "B2C", consumer: "b2c_crm", url: "https://x.example/h", events: [...V3_EVENTS, "b2c.lead_reenquired"] }).success).toBe(true);
    expect(EndpointSchema.safeParse({ name: "B2C", consumer: "b2c_crm", url: "https://x.example/h", events: ["b2ccrm.partner_consent"] }).success).toBe(false);
  });
});

describe("event catalogue (contract version 3)", () => {
  it("publishes the four Addendum 3 types and keeps lead_reenquired, each with a label", () => {
    const types = PUBLISHED_EVENTS.map((e) => e.type);
    for (const t of [...V3_EVENTS, "b2c.lead_reenquired", "b2c.lead_handed_off", "b2c.lead_upserted", "b2c.lead_released", "b2c.leads_batch", "b2b.lead_routed_to_partner"]) {
      expect(types).toContain(t);
    }
    expect(new Set(types).size).toBe(types.length);
    for (const e of PUBLISHED_EVENTS) expect(e.label.length).toBeGreaterThan(10);
  });
  it("lists the inbound consent events the B2C CRM sends", () => {
    const types = B2C_INBOUND_EVENTS.map((e) => e.type);
    expect(types).toContain("b2ccrm.partner_consent");
    expect(types).toContain("b2ccrm.consent_request_sent");
    expect(types.every((t) => t.startsWith("b2ccrm."))).toBe(true);
  });
  it("covers the go-live gate with the B2C default subscription", () => {
    expect(B2C_REQUIRED_EVENTS).toEqual(["b2c.lead_handed_off", "b2c.consent_requested"]);
    for (const t of B2C_REQUIRED_EVENTS) expect(eventSubscribed(B2C_DEFAULT_EVENTS, t)).toBe(true);
    expect(B2C_REQUIRED_EVENTS.every((t) => eventSubscribed(["b2c.lead_handed_off", "b2c.lead_upserted"], t))).toBe(false);
    expect(B2C_REQUIRED_EVENTS.every((t) => eventSubscribed(["b2c.lead_handed_off", "b2c.consent_requested"], t))).toBe(true);
  });
  it("matches subscriptions like b2b.event_subscribed", () => {
    expect(eventSubscribed(["*"], "b2c.consent_closed")).toBe(true);
    expect(eventSubscribed(["b2c.*"], "b2c.lead_requalified")).toBe(true);
    expect(eventSubscribed(["b2c.*"], "b2ccrm.partner_consent")).toBe(false);
    expect(eventSubscribed(["b2b.*"], "b2c.lead_reengaged")).toBe(false);
    expect(eventSubscribed(["lead.*", "b2c.consent_requested"], "b2c.consent_requested")).toBe(true);
    expect(eventSubscribed([], "b2c.consent_requested")).toBe(false);
  });
});

describe("display", () => {
  it("collapses events a wildcard covers", () => {
    expect(describeEvents(["b2c.*", "b2c.lead_flagged", "lead.enrolled"])).toBe("b2c.*, lead.enrolled");
    expect(describeEvents(["*", "b2c.*"])).toBe("All events");
  });
  it("collapses the contract version 3 types under b2c.* and lists them otherwise", () => {
    expect(describeEvents(["b2c.*", ...V3_EVENTS, "b2c.lead_reenquired", "b2b.lead_routed_to_partner"])).toBe("b2c.*, b2b.lead_routed_to_partner");
    expect(describeEvents(["b2c.consent_requested", "b2c.lead_handed_off"])).toBe("b2c.consent_requested, b2c.lead_handed_off");
    expect(describeEvents(["b2b.*", "b2c.consent_closed"])).toBe("b2b.*, b2c.consent_closed");
  });
  it("rates endpoint health", () => {
    expect(endpointHealth(endpoint({ has_secret: false })).label).toBe("No secret yet");
    expect(endpointHealth(endpoint({ active: false })).label).toBe("Paused");
    expect(endpointHealth(endpoint({ dead: 2 })).tone).toBe("danger");
    expect(endpointHealth(endpoint({ last_failure_at: "2026-10-06T11:00:00Z", last_success_at: "2026-10-06T10:00:00Z" })).label).toBe("Failing");
    expect(endpointHealth(endpoint({ last_failure_at: "2026-10-06T09:00:00Z", last_success_at: "2026-10-06T10:00:00Z" })).label).toBe("Healthy");
  });
});

describe("M34d: referral keys read only their own codes", () => {
  it("parses the codes typed into the key form", () => {
    expect(parseReferralCodes(" inf001, INF002\ninf001  abc* ")).toEqual(["ABC*", "INF001", "INF002"]);
    expect(parseReferralCodes("")).toEqual([]);
  });
  it("a referrals key needs at least one valid code; other keys take none", () => {
    expect(referralCodesProblem(["referrals"], [])).toMatch(/at least one referral code/);
    expect(referralCodesProblem(["referrals"], ["INF001", "INF*"])).toBeNull();
    expect(referralCodesProblem(["referrals"], ["IN*"])).toMatch(/Not a referral code/);
    expect(referralCodesProblem(["referrals"], ["*"])).toMatch(/Not a referral code/);
    expect(referralCodesProblem(["referrals"], ["inf001"])).toMatch(/Not a referral code/);
    expect(referralCodesProblem(["intake"], ["INF001"])).toMatch(/only to a key with the Referrals scope/);
    expect(referralCodesProblem(["intake"], [])).toBeNull();
  });
  it("the key form refuses a referrals key without codes", () => {
    const base = { name: "Influencer platform", scopes: ["referrals"], expires_days: 365, rate_per_minute: null };
    expect(ApiKeySchema.safeParse(base).success).toBe(false);
    const ok = ApiKeySchema.safeParse({ ...base, referral_codes: ["INF*"] });
    expect(ok.success && ok.data.referral_codes).toEqual(["INF*"]);
  });
  it("the outcomes cursor is opaque: a lead id is not accepted", () => {
    expect(parseReferralQuery(new URLSearchParams("after=338"))).toEqual({ ok: false, error: "after must be the next_after of the previous page" });
    expect(parseReferralQuery(new URLSearchParams())).toEqual({ ok: true, q: { after: null, limit: 100 } });
    const c = "c1.Zm9vYmFyYmF6cXV1eDEyMzQ1Ng";
    expect(parseReferralQuery(new URLSearchParams(`after=${c}&limit=50`))).toEqual({ ok: true, q: { after: c, limit: 50 } });
    expect(parseReferralQuery(new URLSearchParams("limit=501")).ok).toBe(false);
  });
});
