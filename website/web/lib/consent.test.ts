import { describe, expect, it } from "vitest";
import { allowed, parseConsent, serialiseConsent } from "./consent";

describe("consent", () => {
  it("defaults to nothing optional before a choice", () => {
    expect(allowed(null, "analytics")).toBe(false);
    expect(allowed(null, "marketing")).toBe(false);
  });
  it("round-trips a choice", () => {
    const raw = serialiseConsent({ analytics: true, marketing: false }, new Date("2026-10-17T00:00:00Z"));
    const s = parseConsent(raw);
    expect(s).toEqual({ v: 1, analytics: true, marketing: false, at: "2026-10-17T00:00:00.000Z" });
    expect(allowed(s, "analytics")).toBe(true);
    expect(allowed(s, "marketing")).toBe(false);
  });
  it("rejects tampered or old-version values", () => {
    expect(parseConsent("not-json")).toBeNull();
    expect(
      parseConsent(encodeURIComponent(JSON.stringify({ v: 0, analytics: true, marketing: true, at: "x" }))),
    ).toBeNull();
    expect(
      parseConsent(encodeURIComponent(JSON.stringify({ v: 1, analytics: "yes", marketing: true, at: "x" }))),
    ).toBeNull();
  });
});
