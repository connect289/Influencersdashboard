import { describe, expect, it } from "vitest";
import { codeEmail } from "./code-email.ts";

describe("codeEmail", () => {
  it("shows the code spaced, the expiry and nothing else to click", () => {
    const m = codeEmail("123456", 10, "https://one.eduwit.in");
    expect(m.subject).toBe("Eduwit One sign-in code: 123 456");
    expect(m.text).toContain("123 456");
    expect(m.text).toContain("10 minutes");
    expect(m.html).not.toMatch(/<a\s/);
  });

  it("refuses anything but six digits", () => {
    expect(() => codeEmail("12345", 10, "x")).toThrow();
    expect(() => codeEmail("<b>12</b>", 10, "x")).toThrow();
  });
});
