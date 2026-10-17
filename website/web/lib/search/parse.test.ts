import { describe, expect, it } from "vitest";
import { parseFinderParams } from "./params";
import { mergeParsed, parseQuery } from "./parse";

describe("parseQuery (deterministic NL → filters)", () => {
  it("budget ceiling in lakh", () => {
    expect(parseQuery("mba in marketing under 2 lakh")).toMatchObject({ fee_max: 200_000, rest: "mba in marketing" });
  });
  it("decimal lakh and rupee symbol", () => {
    expect(parseQuery("bca below ₹1.5 lakhs")).toMatchObject({ fee_max: 150_000, rest: "bca" });
  });
  it("thousands with k and commas", () => {
    expect(parseQuery("ba upto 60k").fee_max).toBe(60_000);
    expect(parseQuery("mca within rs 1,20,000").fee_max).toBe(120_000);
  });
  it("range", () => {
    expect(parseQuery("mba between 1 and 2 lakh")).toMatchObject({ fee_min: 100_000, fee_max: 200_000, rest: "mba" });
  });
  it("floor", () => {
    expect(parseQuery("mba above 3 lakh").fee_min).toBe(300_000);
  });
  it("bare amount with a unit is a budget; a bare small number is not", () => {
    expect(parseQuery("mba 2 lakh").fee_max).toBe(200_000);
    expect(parseQuery("top 10 mba").fee_max).toBeUndefined();
  });
  it("duration buckets", () => {
    expect(parseQuery("1 year mba").duration).toBe("le12");
    expect(parseQuery("mba 2 years").duration).toBe("13-24");
    expect(parseQuery("18 months pgdm").duration).toBe("13-24");
  });
  it("work experience is not a duration", () => {
    const p = parseQuery("mba for 2 years experience");
    expect(p.workex).toBe("required");
    expect(p.duration).toBeUndefined();
  });
  it("goals", () => {
    expect(parseQuery("bca online for working professionals")).toMatchObject({ goal: "upskill-while-working", rest: "bca online" });
    expect(parseQuery("ba for sarkari naukri").goal).toBe("government-job-eligibility");
  });
  it("qualification", () => {
    expect(parseQuery("courses after 12th").qual).toBe("12th");
    expect(parseQuery("mba after graduation").qual).toBe("graduation");
  });
  it("Hinglish passes through to the database resolver", () => {
    expect(parseQuery("mba online karna hai").rest).toBe("mba online karna hai");
  });
  it("explicit URL filters win over parsed ones", () => {
    const p = parseFinderParams({ q: "mba under 2 lakh", fee_max: "150000" });
    expect(mergeParsed(p, parseQuery(p.q!))).toMatchObject({ fee_max: 150_000, q: "mba" });
  });
});
