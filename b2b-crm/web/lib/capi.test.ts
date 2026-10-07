import { describe, expect, it } from "vitest";
import { STAGES, STAGE_LABEL, formatInr, keyShare, platformTotals, rate, settingsProblems, valuesProblems, type GoogleMap, type MetaMap } from "./capi";

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

describe("signal ladder", () => {
  it("lists the strongest signals first", () => {
    expect(STAGES.slice(0, 5)).toEqual(["verified", "enrolled", "applied", "interested", "qualified"]);
    expect(STAGE_LABEL.applied.label).toBe("Applicant");
  });
  it("checks the values form", () => {
    const ok = { pct: { applied: "40", interested: "15", qualified: "5" }, base: "15000" };
    expect(valuesProblems(ok)).toEqual({});
    expect(valuesProblems({ ...ok, pct: { ...ok.pct, applied: "140" } })).toHaveProperty("values.applied");
    expect(valuesProblems({ ...ok, pct: { ...ok.pct, qualified: "" } })).toHaveProperty("values.qualified");
    expect(valuesProblems({ ...ok, base: "-1" })).toHaveProperty("base");
    expect(valuesProblems({ ...ok, pct: { applied: "10", interested: "15", qualified: "5" } })).toHaveProperty("order");
  });
  it("computes rates", () => {
    expect(rate(1, 4)).toBe(25);
    expect(rate(1, 0)).toBeNull();
  });
});
