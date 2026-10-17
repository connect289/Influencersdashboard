import { describe, expect, it } from "vitest";
import { attributionToLead, decodeTouch, encodeTouch, isPaid, touchFromUrl } from "./attribution";

const now = new Date("2026-10-17T10:00:00Z");

describe("attribution capture", () => {
  it("captures UTM and click ids, keeps only the landing path", () => {
    const t = touchFromUrl(
      new URL(
        "https://eduwit.in/programmes/online-mba?utm_source=facebook&utm_medium=paid_social&fbclid=AbC123&email=x@y.z",
      ),
      "https://m.facebook.com/",
      now,
    )!;
    expect(t).toMatchObject({
      utm_source: "facebook",
      utm_medium: "paid_social",
      fbclid: "AbC123",
      landing: "/programmes/online-mba",
      referrer: "m.facebook.com",
    });
    expect(JSON.stringify(t)).not.toContain("x@y.z");
    expect(isPaid(t)).toBe(true);
  });
  it("captures creator codes from ?code= and /c/<handle>", () => {
    expect(touchFromUrl(new URL("https://eduwit.in/?code=RIYA21"), null, now)?.code).toBe("riya21");
    expect(touchFromUrl(new URL("https://eduwit.in/c/riya-sharma"), null, now)?.code).toBe("riya-sharma");
  });
  it("ignores visits without a signal and same-site referrers", () => {
    expect(touchFromUrl(new URL("https://eduwit.in/about"), "https://eduwit.in/", now)).toBeNull();
  });
  it("rejects unsafe values", () => {
    expect(touchFromUrl(new URL("https://eduwit.in/?utm_source=<script>"), null, now)).toBeNull();
  });
  it("round-trips through the cookie encoding and maps to lead keys (last click wins, first touch for UTMs)", () => {
    const first = touchFromUrl(new URL("https://eduwit.in/?utm_source=google&utm_medium=cpc&gclid=G1"), null, now)!;
    const last = touchFromUrl(new URL("https://eduwit.in/?code=riya21&fbclid=F2"), null, now)!;
    expect(decodeTouch(encodeTouch(first))).toEqual(first);
    expect(decodeTouch("garbage")).toBeNull();
    expect(attributionToLead(first, last)).toMatchObject({
      utm_source: "google",
      utm_medium: "cpc",
      click_ids: { gclid: "G1", fbclid: "F2" },
      referred_by_code: "riya21",
      landing_url: "/",
    });
  });
});
