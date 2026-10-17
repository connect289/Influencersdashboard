import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { CONTRAST_PAIRS, contrast } from "./contrast";

describe("design tokens meet WCAG 2.1 AA", () => {
  for (const p of CONTRAST_PAIRS) {
    it(`${p.theme}: ${p.name} (${p.fg} on ${p.bg}) ≥ ${p.min}:1`, () => {
      expect(contrast(p.fg, p.bg)).toBeGreaterThanOrEqual(p.min);
    });
  }
  it("every checked colour exists in tokens.css (pairs stay in sync with the tokens)", () => {
    const css = readFileSync(path.join(import.meta.dirname, "../../app/tokens.css"), "utf8").toLowerCase();
    for (const p of CONTRAST_PAIRS) {
      expect(css, p.fg).toContain(p.fg);
      expect(css, p.bg).toContain(p.bg);
    }
  });
});
