import { describe, expect, it } from "vitest";
import { verificationCodeEmail, catalogUnmappedEmail } from "./templates";

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

describe("catalogue alert email", () => {
  it("lists the new programmes and links to the mapping tool, escaping names", () => {
    const m = catalogUnmappedEmail({ count: 2, total: 3, examples: [{ programme: "Online BHM", university: "A <b>Uni</b>" }, { course: "B.Voc" }], adminUrl: "https://eduwit.in/admin/taxonomy" });
    expect(m.subject).toBe("2 new catalogue programmes need a mapping on the website");
    expect(m.text).toContain("- Online BHM — A <b>Uni</b>");
    expect(m.html).toContain("A &lt;b&gt;Uni&lt;/b&gt;");
    expect(m.html).toContain("https://eduwit.in/admin/taxonomy");
    expect(m.text).toContain("3 are waiting in total");
  });
});
