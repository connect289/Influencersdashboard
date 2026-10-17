import { describe, expect, it } from "vitest";
import { sanitiseEvent, funnelContext } from "./events";

describe("analytics events carry no PII", () => {
  it("drops parameters that are not allow-listed", () => {
    expect(sanitiseEvent("lead_created", { surface: "gate", email: "a@b.co", phone: "9876543210" } as never)).toEqual({
      surface: "gate",
    });
  });
  it("scrubs allowed string values", () => {
    expect(sanitiseEvent("programme_view", { programme: "MBA for asha@x.in" })).toEqual({
      programme: "MBA for [email]",
    });
  });
  it("search sends only the query length, never the query text", () => {
    expect(sanitiseEvent("search", { query_length: 12, results: 40, q: "mba 9876543210" } as never)).toEqual({
      query_length: 12,
      results: 40,
    });
  });
});

describe("funnelContext", () => {
  it("keeps only the allow-listed keys of the matching event", () => {
    expect(funnelContext("form", "submitted", { form: "application", offering_id: 7, email: "a@b.co", name: "Asha" })).toEqual({ form: "application", offering_id: 7 });
    expect(funnelContext("form", "step_2", { form: "application", step: 2, phone: "9876543210" })).toEqual({ form: "application", step: 2 });
    expect(funnelContext("gate", "nonsense", { surface: "hero" })).toEqual({});
  });
});
