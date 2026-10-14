import { describe, expect, it } from "vitest";
import { fill, firstName, shareText, textToHtml, unfilled } from "./compose";

describe("compose", () => {
  it("fills known placeholders and blanks unknown ones", () => {
    expect(fill("Hi {{first_name}}, about {{ programme }} at {{university}}. {{x}}", { first_name: "Asha", programme: "MBA", university: null }))
      .toBe("Hi Asha, about MBA at . ");
    expect(unfilled("Hi {{first_name}} {{first_name}} {{programme}}")).toEqual(["first_name", "programme"]);
  });
  it("takes a capitalised first name", () => {
    expect(firstName("  asha rao ")).toBe("Asha");
    expect(firstName(null)).toBeNull();
  });
  it("turns text into HTML without letting markup through", () => {
    const h = textToHtml("Hello <b>there</b>\nline two\n\nSee https://eduwit.in/x?a=1&b=2 now");
    expect(h).toContain("Hello &lt;b&gt;there&lt;/b&gt;<br>line two");
    expect(h).toContain('<a href="https://eduwit.in/x?a=1&amp;b=2">');
    expect(h).not.toContain("<b>");
    expect(textToHtml('javascript:alert(1) "x"')).not.toContain("<a");
  });
  it("writes a share message with fees and only https brochures", () => {
    const t = shareText([{ name: "Online MBA", university: "Amity", fee_total: 179000, mode: "Online", brochure_url: "https://x.in/b.pdf" },
                         { name: "Online MBA", university: "Jain", fee_yearly: 80000, brochure_url: "http://insecure" }], "Asha", "Priya");
    expect(t).toContain("1. Online MBA, Amity (Online, ₹1,79,000 in total)");
    expect(t).toContain("Brochure: https://x.in/b.pdf");
    expect(t).not.toContain("http://insecure");
    expect(t).toMatch(/Priya, Eduwit$/);
  });
});
