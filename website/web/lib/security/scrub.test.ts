import { describe, expect, it } from "vitest";
import { scrub, scrubString } from "./scrub";

describe("PII scrubbing", () => {
  it("removes emails, Indian mobile numbers and codes from text", () => {
    expect(scrubString("Contact asha.v@gmail.com or +91 98765 43210, code 482913")).toBe(
      "Contact [email] or [phone], code [digits]",
    );
    expect(scrubString("call 09876543210")).toBe("call [phone]");
    expect(scrubString("mba under 2 lakh")).toBe("mba under 2 lakh");
  });
  it("redacts sensitive keys and scrubs nested values", () => {
    expect(
      scrub({ email: "a@b.co", phone: "9876543210", page: "/programmes?q=mba", nested: { note: "mail me at x@y.in" } }),
    ).toEqual({
      email: "[redacted]",
      phone: "[redacted]",
      page: "/programmes?q=mba",
      nested: { note: "mail me at [email]" },
    });
  });
});
