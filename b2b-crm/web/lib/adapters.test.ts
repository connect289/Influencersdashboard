import { describe, expect, it } from "vitest";
import { adapterProblems, isCrmAdapter, pollSummary, type AdapterStatus } from "./adapters";

const spec = (over: Partial<AdapterStatus["spec"]>): AdapterStatus["spec"] => ({
  label: "X", settings: [], secrets: [], oauth: false, poll: true, schema: true, status_field: "S", reference_field: "R", record_field: "id", default_fields: {}, ...over,
});

describe("adapters", () => {
  it("knows the CRM adapters", () => {
    expect(isCrmAdapter("zoho")).toBe(true);
    expect(isCrmAdapter("generic_rest")).toBe(false);
  });
  it("checks a LeadSquared form", () => {
    const s = spec({ settings: ["host"], secrets: ["access_key", "secret_key"] });
    const e = adapterProblems(s, { settings: { host: "example.com" }, secrets: { access_key: "short" }, secretsSet: [], reference_field: "mx Ref", status_field: "", poll_minutes: "1", fixed: [] });
    expect(e).toEqual({ "settings.host": "Looks like api-in21.leadsquared.com.", "secrets.access_key": "8 to 4,000 characters.", "secrets.secret_key": "Required.",
                        reference_field: "Letters, digits and underscores.", poll_minutes: "2 to 1,440 minutes." });
  });
  it("keeps stored secrets", () => {
    const s = spec({ settings: ["login_url", "client_id"], secrets: ["client_secret"] });
    expect(adapterProblems(s, { settings: { client_id: "abc" }, secrets: {}, secretsSet: ["client_secret"], reference_field: "", status_field: "", poll_minutes: "", fixed: [] })).toEqual({});
  });
  it("summarises a poll", () => {
    expect(pollSummary({ records: 3, applied: 2, unmatched: 1 })).toBe("3 changed · 2 applied · 1 not Eduwit's");
    expect(pollSummary(null)).toBe("—");
  });
});
