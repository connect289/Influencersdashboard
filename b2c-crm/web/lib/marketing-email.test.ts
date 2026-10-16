import { describe, expect, it } from "vitest";
import { decodeLink } from "./tokens";
import { marketingEmail } from "./marketing-email";

const K = "k".repeat(40);

describe("marketing email", () => {
  const m = marketingEmail({ emailId: 9, leadId: 900021, text: "Hi Asha,\n\nBrochure: https://x.in/b.pdf\nMore <b>here</b>", site: "https://b2c.eduwit.in/", key: K });
  it("tracks links through signed redirects that keep the destination", () => {
    const tokens = [...m.html.matchAll(/\/e\/c\/([^"]+)"/g)].map((x) => decodeLink(x[1]!, K));
    expect(tokens).toContainEqual({ kind: "click", email: 9, link: "brochure", url: "https://x.in/b.pdf" });
    expect(tokens).toContainEqual({ kind: "click", email: 9, link: "interested", url: "https://b2c.eduwit.in/thanks" });
  });
  it("escapes the text, adds the footer, the pixel and one-click unsubscribe", () => {
    expect(m.html).toContain("&lt;b&gt;here&lt;/b&gt;");
    expect(m.html).toContain("Unsubscribe</a>");
    expect(m.html).toContain("/e/o/");
    expect(m.headers["List-Unsubscribe"]).toMatch(/^<https:\/\/b2c\.eduwit\.in\/e\/u\/.+>$/);
    expect(m.headers["List-Unsubscribe-Post"]).toBe("List-Unsubscribe=One-Click");
    expect(m.text).toContain("Unsubscribe: https://b2c.eduwit.in/u/");
  });
});
