import { describe, expect, it } from "vitest";
import { verificationCodeEmail } from "./templates";

describe("verification email", () => {
  it("puts the code in subject, text and html and states the expiry", () => {
    const m = verificationCodeEmail("482913", "verify");
    expect(m.subject).toBe("482913 is your Eduwit verification code");
    expect(m.text).toContain("482913");
    expect(m.text).toContain("10 minutes");
    expect(m.html).toContain("482913");
  });
  it("escapes HTML", () => {
    expect(verificationCodeEmail("<b>1</b>", "admin").html).not.toContain("<b>1</b>");
  });
});
