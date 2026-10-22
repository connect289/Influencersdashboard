import { describe, expect, it } from "vitest";
import { activeFilterCount, parseFinderParams, toQueryString, toSearchInput } from "./params";

describe("finder URL state", () => {
  it("drops unknown values and normalises lists", () => {
    const p = parseFinderParams({ programme: "MBA,mca,mba", mode: "online,nope", naac: "a-plus,zz", junk: "1" });
    expect(p.programme).toEqual(["mba", "mca"]);
    expect(p.mode).toEqual(["online"]);
    expect(p.naac).toEqual(["a-plus"]);
  });
  it("canonical query string is order-independent and removes defaults", () => {
    const a = toQueryString(parseFinderParams({ spec: "marketing,finance", programme: "mba", sort: "relevance", page: "1" }));
    const b = toQueryString(parseFinderParams(new URLSearchParams("programme=mba&spec=finance,marketing")));
    expect(a).toBe(b);
    expect(a).toBe("programme=mba&spec=finance,marketing");
  });
  it("rejects silly numbers and pages", () => {
    const p = parseFinderParams({ fee_max: "-5", page: "9999", qual: "phd" });
    expect(p.fee_max).toBeUndefined();
    expect(p.page).toBeUndefined();
    expect(p.qual).toBeUndefined();
  });
  it("lowercases and trims the query; strips nothing else", () => {
    expect(parseFinderParams({ q: "  MBA   in Marketing " }).q).toBe("mba in marketing");
  });
  it("maps to the database input", () => {
    expect(toSearchInput(parseFinderParams({ mode: "regular,online" })).mode).toEqual(["Online", "Regular"]);
    const input = toSearchInput(parseFinderParams({ mode: "odl", naac: "a-plus-plus", minq: "bachelor", uni: "nmims", all: "1" }));
    expect(input).toMatchObject({ mode: ["ODL"], naac: ["A++"], min_q: ["BACHELOR"], university: ["nmims"], show_ineligible: true });
  });
  it("counts active filters", () => {
    expect(activeFilterCount(parseFinderParams({ programme: "mba", spec: "a,b", ugc: "1", fee_max: "100000" }))).toBe(5);
  });
});
