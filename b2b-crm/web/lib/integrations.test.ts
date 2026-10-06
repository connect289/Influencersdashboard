import { describe, expect, it } from "vitest";
import { apiKeyFrom, describeEvents, endpointHealth, EndpointSchema, parseHandoffsQuery, type EndpointRow } from "./integrations";

const endpoint = (x: Partial<EndpointRow>): EndpointRow => ({
  id: 1, name: "B2C CRM", consumer: "b2c_crm", url: "https://b2c.example/hooks", events: ["b2c.*"], active: true, has_secret: true,
  last_success_at: null, last_failure_at: null, last_error: null, pending: 0, dead: 0, delivered_24h: 0, created_at: "2026-10-06T10:00:00Z", ...x,
});

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
});

describe("display", () => {
  it("collapses events a wildcard covers", () => {
    expect(describeEvents(["b2c.*", "b2c.lead_flagged", "lead.enrolled"])).toBe("b2c.*, lead.enrolled");
    expect(describeEvents(["*", "b2c.*"])).toBe("All events");
  });
  it("rates endpoint health", () => {
    expect(endpointHealth(endpoint({ has_secret: false })).label).toBe("No secret yet");
    expect(endpointHealth(endpoint({ active: false })).label).toBe("Paused");
    expect(endpointHealth(endpoint({ dead: 2 })).tone).toBe("danger");
    expect(endpointHealth(endpoint({ last_failure_at: "2026-10-06T11:00:00Z", last_success_at: "2026-10-06T10:00:00Z" })).label).toBe("Failing");
    expect(endpointHealth(endpoint({ last_failure_at: "2026-10-06T09:00:00Z", last_success_at: "2026-10-06T10:00:00Z" })).label).toBe("Healthy");
  });
});
