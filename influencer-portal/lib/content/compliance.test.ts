import { describe, expect, it } from "vitest";
import {
  ASCI_CHECKLIST,
  checkDisclosure,
  checklistComplete,
  MAX_SCAN_CHARS,
  safePattern,
  scanClaims,
  scanSubmission,
  type BannedClaim,
} from "./compliance";

const claims: BannedClaim[] = [
  { id: "guarantee", pattern: "guaranteed placement", kind: "phrase", severity: "block", note: "No outcome promises" },
  { id: "pct", pattern: "100\\s*%\\s*(job|placement)", kind: "regex", severity: "block", note: null },
  { id: "best", pattern: "best university", kind: "phrase", severity: "warn", note: "Unverifiable superlative" },
  { id: "free", pattern: "free", kind: "phrase", severity: "warn", note: null },
];
const settings = {
  disclosure_terms: ["#ad", "#collab", "paid partnership"],
  disclosure_required_platforms: ["instagram", "youtube"] as const,
};

describe("scanClaims", () => {
  it("finds phrases as whole words, any case and spacing", () => {
    const m = scanClaims("We offer GUARANTEED   placement and the best  university!", claims);
    expect(m.map((x) => [x.claim_id, x.text, x.severity])).toEqual([
      ["guarantee", "GUARANTEED   placement", "block"],
      ["best", "best  university", "warn"],
    ]);
  });
  it("doesn't match inside other words", () => {
    expect(scanClaims("Freedom to learn, carefree", claims)).toEqual([]);
    expect(scanClaims("It's free!", claims).map((m) => m.claim_id)).toEqual(["free"]);
  });
  it("runs safe regex patterns", () => {
    expect(scanClaims("100 % job after the course", claims).map((m) => m.text)).toEqual(["100 % job"]);
    expect(scanClaims("100% Placement", claims).map((m) => m.claim_id)).toEqual(["pct"]);
  });
  it("works with Hindi text", () => {
    const hi: BannedClaim[] = [{ id: "h", pattern: "पक्की नौकरी", kind: "phrase", severity: "block", note: null }];
    expect(scanClaims("इस कोर्स के बाद पक्की नौकरी मिलेगी", hi).map((m) => m.claim_id)).toEqual(["h"]);
  });
  it("skips unsafe patterns and caps the scanned length", () => {
    const bad: BannedClaim[] = [{ id: "x", pattern: "(a+)+$", kind: "regex", severity: "block", note: null }];
    expect(scanClaims(`${"a".repeat(40)}!`, bad)).toEqual([]);
    const tail = `${"x ".repeat(MAX_SCAN_CHARS)} guaranteed placement`;
    expect(scanClaims(tail, claims)).toEqual([]);
  });
});

describe("safePattern", () => {
  it.each([
    ["guaranteed\\s+job", true],
    ["100\\s*%", true],
    ["(a+)+", false],
    ["(.*)*x", false],
    ["(\\w+\\s?){2,}", false],
    ["(a)\\1", false],
    ["(?<=x)y", false],
    ["[unclosed", false],
    ["", false],
    ["a".repeat(201), false],
  ])("%s → %s", (p, ok) => {
    expect(safePattern(p)).toBe(ok);
  });
});

describe("checkDisclosure", () => {
  it("finds hashtags as whole tags only", () => {
    expect(checkDisclosure("Loved it #ad", "instagram", settings)).toEqual({
      required: true,
      present: true,
      found: "#ad",
    });
    expect(checkDisclosure("Wearing #adidas today", "instagram", settings).present).toBe(false);
    expect(checkDisclosure("##ad", "instagram", settings).present).toBe(false);
    expect(checkDisclosure("#AD at the start", "instagram", settings).present).toBe(true);
  });
  it("finds phrases", () => {
    expect(checkDisclosure("This is a Paid  Partnership with Eduwit", "youtube", settings).found).toBe(
      "paid partnership",
    );
  });
  it("knows which platforms require it", () => {
    expect(checkDisclosure("no tag", "linkedin", settings)).toEqual({ required: false, present: false, found: null });
  });
});

describe("scanSubmission", () => {
  it("blocks on a blocking claim or a missing required disclosure", () => {
    expect(scanSubmission("Guaranteed placement! #ad", "final", "instagram", claims, settings).passed).toBe(false);
    expect(scanSubmission("Great course", "final", "instagram", claims, settings).passed).toBe(false);
    expect(scanSubmission("Great course #collab", "final", "instagram", claims, settings).passed).toBe(true);
    // Warnings never block.
    expect(scanSubmission("The best university #ad", "draft", "instagram", claims, settings).passed).toBe(true);
  });
  it("doesn't check the disclosure on concepts or on platforms that don't need it", () => {
    const concept = scanSubmission("Script idea", "concept", "instagram", claims, settings);
    expect(concept.disclosure).toBeNull();
    expect(concept.passed).toBe(true);
    expect(scanSubmission("Post", "final", "linkedin", claims, settings).passed).toBe(true);
  });
});

describe("ASCI checklist", () => {
  it("needs every item", () => {
    const all = Object.fromEntries(ASCI_CHECKLIST.map((k) => [k, true]));
    expect(checklistComplete(all)).toBe(true);
    expect(checklistComplete({ ...all, disclosure_upfront: false })).toBe(false);
    expect(checklistComplete({})).toBe(false);
  });
});
