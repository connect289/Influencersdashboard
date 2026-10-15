import { describe, expect, it } from "vitest";
import { containsPii, scrubPii } from "./scrub";

describe("scrubPii", () => {
  it("removes phone numbers however they are written", () => {
    for (const p of ["9876543210", "+91 98765 43210", "+91-98765-43210", "(022) 2345 6789", "98765.43210", "919000000042"]) {
      const out = scrubPii(`call me on ${p} please`);
      expect(out).toContain("[phone]");
      expect(out).not.toMatch(/\d{5}/);
    }
  });
  it("removes email addresses, including spelled-out ones", () => {
    expect(scrubPii("mail bina.home@gmail.com now")).toBe("mail [email] now");
    expect(scrubPii("write to bina (at) yahoo dot com")).toBe("write to [email]");
  });
  it("keeps fees, years and short numbers", () => {
    const t = "Budget 2 lakh (200000), joined in 2024, 3 calls, MBA fee 179000";
    expect(scrubPii(t)).toBe(t);
    expect(containsPii(t)).toBe(false);
  });
  it("detects what is left", () => {
    expect(containsPii("x 98765 43210")).toBe(true);
    expect(containsPii("a@b.co")).toBe(true);
    expect(containsPii(scrubPii("a@b.co 98765 43210"))).toBe(false);
  });
  it("does not take dates and timestamps for phone numbers", () => {
    const brief = JSON.stringify({ activity: [{ at: "2026-10-15T10:45:08.443+00:00", text: "Handed to B2C" }], due: "2026-10-16 09:30" });
    expect(containsPii(brief)).toBe(false);
    expect(scrubPii(brief)).toBe(brief);
    expect(containsPii(`${brief} call 98765 43210`)).toBe(true);
    expect(scrubPii("on 2026-10-15 call +91 98765 43210")).toBe("on 2026-10-15 call [phone]");
  });
});

