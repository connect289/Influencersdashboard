import { describe, expect, it } from "vitest";
import { salesEmail, trackLinks } from "./sales-email";
import { decodeLink } from "./tokens";

const KEY = "k".repeat(40);
const SITE = "https://b2c.eduwit.in";
const tokenOf = (html: string) => html.match(/\/e\/c\/([^"&]+)/)?.[1] ?? "";

describe("sales email click tracking", () => {
  it("sends each https link through the signed click redirect, keeping the destination", () => {
    const html = trackLinks('<p>Fees: <a href="https://amity.edu/mba?x=1&amp;y=2">here</a></p>', 77, SITE, KEY);
    expect(html).toMatch(/href="https:\/\/b2c\.eduwit\.in\/e\/c\//);
    expect(decodeLink(tokenOf(html), KEY)).toEqual({ kind: "click", email: 77, link: "other", url: "https://amity.edu/mba?x=1&y=2" });
  });

  it("marks brochures, and leaves mailto, http and Spark's own tracking links alone", () => {
    const html = trackLinks('<a href="https://cdn.example.com/MBA.pdf">b</a> <a href="mailto:a@b.c">m</a> <a href="http://x.example">h</a> <a href="https://b2c.eduwit.in/u/abc">u</a>', 5, SITE, KEY);
    expect(decodeLink(tokenOf(html), KEY)).toMatchObject({ link: "brochure", url: "https://cdn.example.com/MBA.pdf" });
    expect(html).toContain('href="mailto:a@b.c"');
    expect(html).toContain('href="http://x.example"');
    expect(html).toContain('href="https://b2c.eduwit.in/u/abc"');
  });

  it("builds the HTML from the text when there is none, with no pixel or footer, and keeps the text as written", () => {
    const m = salesEmail({ emailId: 9, text: "Hi Asha,\n\nDetails: https://amity.edu/mba", html: null, site: SITE, key: KEY });
    expect(m.text).toBe("Hi Asha,\n\nDetails: https://amity.edu/mba");
    expect(m.html).toContain("/e/c/");
    expect(m.html).not.toContain("/e/o/");
    expect(m.html).not.toMatch(/unsubscribe/i);
  });
});
