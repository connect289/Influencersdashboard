import { describe, expect, it } from "vitest";
import { BlocksSchema, blocksText, htmlText, isBlocksHtml, newBlock, renderBlocks, type Block } from "./email-blocks";
import { marketingEmail } from "./marketing-email";
import { decodeLink } from "./tokens";

const blocks: Block[] = [
  { type: "heading", text: "Your MBA <options>", level: 1 },
  { type: "text", text: "Hi {{first_name}},\nfees & EMI below.\n\nSecond paragraph." },
  { type: "image", src: "https://x.in/a.png", alt: "Campus", href: "https://x.in/campus" },
  { type: "button", text: "Book a call", href: "https://x.in/call?a=1&b=2" },
  { type: "divider" },
  { type: "spacer", height: 24 },
  { type: "programme", name: "Online MBA", university: "Amity Online", fee: "₹1,75,000", note: "EMI from ₹7,000", href: "https://x.in/mba" },
];

describe("email blocks", () => {
  const html = renderBlocks(blocks);

  it("renders email-safe HTML: escaped text, inline styles, no scripts or classes", () => {
    expect(isBlocksHtml(html)).toBe(true);
    expect(html).toContain("Your MBA &lt;options&gt;");
    expect(html).toContain("Hi {{first_name}},<br>fees &amp; EMI below.</p><p");
    expect(html).toContain('href="https://x.in/call?a=1&amp;b=2"');
    expect(html).toContain('<img src="https://x.in/a.png" alt="Campus"');
    expect(html).toContain("height:24px");
    expect(html).toContain("Fee: ₹1,75,000");
    expect(html).not.toMatch(/<script|class=|on[a-z]+=/i);
  });

  it("accepts only https links and known block types", () => {
    expect(BlocksSchema.safeParse(blocks).success).toBe(true);
    expect(BlocksSchema.safeParse([{ type: "button", text: "x", href: "javascript:alert(1)" }]).success).toBe(false);
    expect(BlocksSchema.safeParse([{ type: "image", src: "http://x.in/a.png" }]).success).toBe(false);
    expect(BlocksSchema.safeParse([{ type: "html", html: "<b>" }]).success).toBe(false);
    expect(BlocksSchema.safeParse([newBlock("heading"), newBlock("text"), newBlock("divider"), newBlock("programme")]).success).toBe(true);
  });

  it("has a plain-text version", () => {
    expect(blocksText(blocks)).toContain("Book a call: https://x.in/call?a=1&b=2");
    const t = htmlText(html);
    expect(t).toContain("Hi {{first_name}},\nfees & EMI below.");
    expect(t).toContain("Book a call (https://x.in/call?a=1&b=2)");
    expect(t).toContain("Your MBA <options>");
    expect(t).not.toMatch(/<(table|td|p|a)\b/);
  });

  it("is sent as HTML with tracked links, not escaped as text", () => {
    const K = "k".repeat(40);
    const m = marketingEmail({ emailId: 3, leadId: 9, text: html, site: "https://b2c.eduwit.in", key: K });
    expect(m.html).toContain("Your MBA &lt;options&gt;");
    expect(m.html).not.toContain("&lt;table");
    const tokens = [...m.html.matchAll(/\/e\/c\/([^"]+)"/g)].map((x) => decodeLink(x[1]!, K));
    expect(tokens).toContainEqual({ kind: "click", email: 3, link: "other", url: "https://x.in/call?a=1&b=2" });
    expect(m.text).toContain("Book a call (https://x.in/call?a=1&b=2)");
    expect(m.text).toContain("Unsubscribe: https://b2c.eduwit.in/u/");
  });
});
