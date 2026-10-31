import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { maskText } from "./pii.ts";

// The corpus both contact maskers are held to (D-119): this test runs it through the app's maskText, and
// supabase/tests/local/99_audit_fixes.sql runs the same file through the database's one.mask_text.
type Corpus = {
  mask: Array<{ text: string; hide: string[] }>;
  keep: Array<{ text: string; keep: string[] }>;
};
const corpus = JSON.parse(
  readFileSync(new URL("../../../supabase/tests/mask-corpus.json", import.meta.url), "utf8"),
) as Corpus;

describe("the shared masking corpus (D-119)", () => {
  it("is not empty", () => {
    expect(corpus.mask.length).toBeGreaterThan(20);
    expect(corpus.keep.length).toBeGreaterThan(5);
  });

  it.each(corpus.mask.map((c) => [c.text, c.hide] as const))("hides the contact in %s", (text, hide) => {
    const out = maskText(text);
    for (const h of hide) expect(out).not.toContain(h);
  });

  it.each(corpus.keep.map((c) => [c.text, c.keep] as const))("keeps the ids and dates in %s", (text, keep) => {
    const out = maskText(text);
    for (const k of keep) expect(out).toContain(k);
  });
});
