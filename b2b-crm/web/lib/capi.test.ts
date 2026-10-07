import { describe, expect, it } from "vitest";
import { STAGES, formatInr, keyShare, platformTotals, settingsProblems, type GoogleMap, type MetaMap } from "./capi";

const metaMap = Object.fromEntries(STAGES.map((s) => [s, { event: "Event", enabled: true }])) as MetaMap;
const googleMap = Object.fromEntries(STAGES.map((s) => [s, { action: null, enabled: true }])) as GoogleMap;

describe("capi", () => {
  it("adds up a platform's statuses", () => {
    expect(platformTotals({ "meta.sent": 4, "meta.held": 2, "meta.pending": 1, "meta.rejected": 1, "meta.dead": 1, "google.sent": 9 }, "meta"))
      .toEqual({ sent: 4, waiting: 3, problems: 2, dry_run: 0, skipped: 0 });
  });
  it("computes match-key shares", () => {
    expect(keyShare({ events: 8, keys: { email: 6 } }, "email")).toBe(75);
    expect(keyShare({ events: 8, keys: {} }, "phone")).toBe(0);
    expect(keyShare(undefined, "phone")).toBe(0);
  });
  it("checks the settings form", () => {
    expect(settingsProblems({ meta: { dataset_id: "", api_version: "", map: metaMap }, google: { customer_id: "", login_customer_id: "", api_version: "", map: googleMap } })).toEqual({});
    const e = settingsProblems({
      meta: { dataset_id: "pixel1", api_version: "21", map: { ...metaMap, applied: { event: " ", enabled: true } } },
      google: { customer_id: "123-456-789", login_customer_id: "1234567890", api_version: "v21", map: { ...googleMap, enrolled: { action: "5", enabled: true } } },
    });
    expect(Object.keys(e).sort()).toEqual(["google.customer_id", "google.map.enrolled", "meta.api_version", "meta.dataset_id", "meta.map.applied"]);
  });
  it("formats rupees", () => {
    expect(formatInr(150000)).toBe("₹1,50,000");
    expect(formatInr(null)).toBe("—");
  });
});
