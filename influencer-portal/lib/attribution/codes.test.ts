import { describe, expect, it } from "vitest";
import { codeStem, codeTag, looksLikeAccessCode, normalizeCode, suffix, suggestCode, SUFFIX_ALPHABET } from "./codes";

describe("creator codes", () => {
  it.each([
    ["rahul-mba-07", "RAHUL-MBA-07"],
    ["  PRIYA-IG-3K ", "PRIYA-IG-3K"],
    ["AB-C", null],
    ["ABCDEF", null],
    ["RAHUL_MBA", null],
    ["RAHUL--MBA", null],
    ["A-B-C-D-E", null],
    ["ABCDEFGHIJKLM-X", null],
    ["ABCDEFGHIJKL-ABCDEFGH-ABCDEFGH", "ABCDEFGHIJKL-ABCDEFGH-ABCDEFGH"],
    ["RIYA-IG", "RIYA-IG"],
  ])("normalizeCode(%j) = %j", (raw, out) => {
    expect(normalizeCode(raw)).toBe(out);
  });

  it("never clashes with Witty's 6-character access codes", () => {
    expect(looksLikeAccessCode("K7QM2X")).toBe(true);
    for (let i = 0; i < 200; i++) {
      const c = suggestCode("riya", "instagram");
      expect(looksLikeAccessCode(c)).toBe(false);
      expect(normalizeCode(c)).toBe(c);
    }
  });

  it("builds stems and tags", () => {
    expect(codeStem("riya.learns_2024")).toBe("RIYALEARNS20");
    expect(codeStem("é")).toBe("EC");
    expect(codeStem("")).toBe("CR");
    expect(codeTag("instagram")).toBe("IG");
    expect(codeTag("Diwali 2026 sale")).toBe("DIWALI20");
    expect(codeTag("!!!")).toBe("GO");
  });

  it("draws suffixes only from the no-confusion alphabet", () => {
    expect(SUFFIX_ALPHABET).not.toMatch(/[01OI]/);
    expect(suffix(2, () => 0)).toBe("AA");
    expect(suffix(3, () => 0.9999)).toBe("999");
    expect(suggestCode("riyalearns", "youtube", () => 0.5)).toBe("RIYALEARNS-YT-SS");
  });
});
