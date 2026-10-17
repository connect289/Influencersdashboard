import { describe, expect, it } from "vitest";
// @ts-expect-error plain ESM helper used by a Node script
import { lit, toContentBlocks } from "./legacy-blocks.mjs";

describe("legacy import", () => {
  it("keeps text verbatim, starts after the H1, groups list items, skips navigation", () => {
    const blocks = [
      { tag: "a", text: "Home", section: "nav" },
      { tag: "h1", text: "Privacy Policy" },
      { tag: "p", text: "We  respect   your privacy." },
      { tag: "h2", text: "What we collect" },
      { tag: "li", text: "Name" },
      { tag: "li", text: "Phone" },
      { tag: "h4", text: "Contact" },
      { tag: "p", text: "© Eduwit", section: "footer" },
    ];
    expect(toContentBlocks(blocks)).toEqual([
      { type: "p", text: "We respect your privacy." },
      { type: "h2", text: "What we collect" },
      { type: "ul", items: ["Name", "Phone"] },
      { type: "h3", text: "Contact" },
    ]);
  });
  it("escapes SQL literals", () => {
    expect(lit("Eduwit's policy")).toBe("'Eduwit''s policy'");
  });
});
