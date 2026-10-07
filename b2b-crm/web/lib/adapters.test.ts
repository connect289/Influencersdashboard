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
                        reference_field: "Letters, digits and underscores (a path like stage.name for nested fields).", poll_minutes: "2 to 1,440 minutes." });
  });
  it("keeps stored secrets", () => {
    const s = spec({ settings: ["login_url", "client_id"], secrets: ["client_secret"] });
    expect(adapterProblems(s, { settings: { client_id: "abc" }, secrets: {}, secretsSet: ["client_secret"], reference_field: "", status_field: "", poll_minutes: "", fixed: [] })).toEqual({});
  });
  it("checks an in-house CRM form", () => {
    const s = spec({ settings: ["create_url", "auth_type", "auth_name", "wrap_key", "record_id_path", "duplicate_status", "poll_url", "since_param"], secrets: ["token"], schema: false });
    const base = { secrets: {}, secretsSet: [], reference_field: "", status_field: "stage.name", poll_minutes: "", fixed: [] };
    expect(isCrmAdapter("inhouse")).toBe(true);
    expect(adapterProblems(s, { ...base, settings: { create_url: "http://crm.example.com/leads", auth_type: "", record_id_path: "data..id", duplicate_status: "99" } })).toEqual({
      "settings.create_url": "An https address.", "settings.auth_type": "Choose one.", "settings.record_id_path": "Like data or data.lead.id.",
      "settings.duplicate_status": "An HTTP code such as 409.", "secrets.token": "Required." });
    // no key needed when the CRM trusts Eduwit's address
    expect(adapterProblems(s, { ...base, settings: { create_url: "https://crm.example.com/leads", auth_type: "none", poll_url: "https://crm.example.com/changes?since={since}" } })).toEqual({});
  });
  it("summarises a poll", () => {
    expect(pollSummary({ records: 3, applied: 2, unmatched: 1 })).toBe("3 changed · 2 applied · 1 not Eduwit's");
    expect(pollSummary(null)).toBe("—");
  });
});
