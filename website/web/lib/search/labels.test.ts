import { describe, expect, it } from "vitest";
import { parseFinderParams } from "./params";
import { appliedFilters, finderHeading, relaxationLabel } from "./labels";
import type { Facets } from "./types";

const facets = {
  programme: [{ value: "mba", label: "MBA", count: 1 }],
  spec: [{ value: "marketing", label: "Marketing", count: 1 }],
  university: [{ value: "nmims", label: "NMIMS", count: 1 }],
  level: [{ value: "pg", label: "Postgraduate (PG)", count: 1 }],
  goal: [],
} as unknown as Facets;

describe("finder labels", () => {
  it("headings read naturally", () => {
    expect(finderHeading(parseFinderParams({ programme: "mba", spec: "marketing", mode: "online" }), facets)).toBe("Online MBA in Marketing");
    expect(finderHeading(parseFinderParams({ uni: "nmims" }), facets)).toBe("Programmes at NMIMS");
    expect(finderHeading(parseFinderParams({}), facets)).toBe("Find your programme");
  });
  it("chips remove only their own value", () => {
    const p = parseFinderParams({ spec: "marketing,finance", fee_max: "200000" });
    const chips = appliedFilters(p, facets);
    expect(chips.map((c) => c.label)).toEqual(["finance", "Marketing", "Up to ₹2 lakh"]);
    expect(chips[1]!.without).toEqual({ spec: ["finance"] });
  });
  it("relaxations name the filter to remove", () => {
    const p = parseFinderParams({ naac: "a-plus-plus" });
    expect(relaxationLabel("naac", p, facets)).toEqual({ label: "NAAC A++", without: { naac: [] } });
    expect(relaxationLabel("elig", p, facets)?.without).toEqual({ all: true });
  });
});

describe("study modes", () => {
  it("shows on-campus (Regular) programmes as On-campus", async () => {
    const { modeDisplay, MODE_LABEL } = await import("./labels");
    expect(modeDisplay("Regular")).toBe("On-campus");
    expect(modeDisplay("ODL")).toBe("Distance (ODL)");
    expect(modeDisplay("Online")).toBe("Online");
    expect(modeDisplay(null)).toBeNull();
    expect(MODE_LABEL.regular).toBe("On-campus");
  });
});
