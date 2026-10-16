// WCAG 2.1 AA contrast for the token pairs the UI uses, in both themes, read from the real stylesheet.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const css = readFileSync(join(import.meta.dirname, "..", "..", "app", "globals.css"), "utf8");

function block(selector: string): Record<string, string> {
  const start = css.indexOf(`${selector} {`);
  const body = css.slice(start, css.indexOf("}", start));
  return Object.fromEntries(
    [...body.matchAll(/--([a-z0-9-]+):\s*(#[0-9a-f]{6})/gi)].map((m) => [m[1] ?? "", (m[2] ?? "").toLowerCase()]),
  );
}

function luminance(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  }) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
}

const PAIRS: [fg: string, bg: string, min: number][] = [
  ["ink", "bg", 4.5],
  ["ink", "surface", 4.5],
  ["muted", "surface", 4.5],
  ["muted", "bg", 4.5],
  ["on-primary", "primary", 4.5],
  ["primary", "surface", 4.5],
  ["primary", "primary-soft", 4.5],
  ["on-accent", "accent", 4.5],
  ["accent-ink", "accent-soft", 4.5],
  ["accent-ink", "surface", 4.5],
  ["success", "success-soft", 4.5],
  ["danger", "danger-soft", 4.5],
  ["danger", "surface", 4.5],
  ["line-strong", "surface", 1.5],
];

describe.each([
  ["light", block(":root")],
  ["dark", { ...block(":root"), ...block(':root[data-theme="dark"]') }],
])("%s theme contrast", (_name, t) => {
  it.each(PAIRS)("%s on %s ≥ %s:1", (fg, bg, min) => {
    expect(t[fg], fg).toBeDefined();
    expect(t[bg], bg).toBeDefined();
    expect(contrast(t[fg] ?? "", t[bg] ?? "")).toBeGreaterThanOrEqual(min);
  });
});
