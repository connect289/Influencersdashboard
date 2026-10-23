import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { contrast, pairs, themes, tokensCss } from "./tokens.ts";

describe("brand tokens", () => {
  it("app/tokens.css is generated from tokens.ts", () => {
    expect(readFileSync(new URL("../../app/tokens.css", import.meta.url), "utf8")).toBe(tokensCss());
  });

  for (const [name, theme] of Object.entries(themes)) {
    it(`every text-on-background pair meets WCAG AA in the ${name} theme`, () => {
      const failing = pairs
        .map(([fg, bg]) => ({ pair: `${fg} on ${bg}`, ratio: contrast(theme[fg], theme[bg]) }))
        .filter((p) => p.ratio < 4.5)
        .map((p) => `${p.pair}: ${p.ratio.toFixed(2)}`);
      expect(failing).toEqual([]);
    });
  }
});
