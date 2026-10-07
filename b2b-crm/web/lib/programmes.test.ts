import { describe, expect, it } from "vitest";
import {
  findHeaderRow, headerNames, inferLevel, normaliseRow, normaliseSpecialization, parseActive, parseCommission, parseCsv, parseDate,
  parseLevel, parseMode, parseMoney, parsePct, suggestTemplate, zipUncompressedSize,
} from "./programmes";

describe("parseMoney", () => {
  it.each([
    ["1.5 L", 150000], ["1.5 lakh", 150000], ["₹1,20,000/-", 120000], ["Rs. 95,000", 95000], ["2.4 Cr", 24000000], ["50k", 50000],
    [120000, 120000], ["", null], ["NA", null], ["-", null], ["about 1L", "invalid"], [-5, "invalid"],
  ])("%s → %s", (v, out) => expect(parseMoney(v as never)).toBe(out));
});

describe("modes, levels, pct, dates, active", () => {
  it("modes", () => {
    expect(parseMode("online")).toBe("Online");
    expect(parseMode("Distance Learning")).toBe("ODL");
    expect(parseMode("On-campus")).toBe("Regular");
    expect(parseMode("")).toBeNull();
    expect(parseMode("hybrid")).toBe("invalid");
  });
  it("levels and inference", () => {
    expect(parseLevel("Post Graduate")).toBe("PG");
    expect(parseLevel("UG")).toBe("UG");
    expect(parseLevel("PG Diploma")).toBe("PG");
    expect(parseLevel("x")).toBe("invalid");
    expect(inferLevel("MBA (Dual)")).toBe("PG");
    expect(inferLevel("B.Com")).toBe("UG");
    expect(inferLevel("PGDM")).toBe("PG");
    expect(inferLevel("Diploma in Computer Applications")).toBe("DIPLOMA");
    expect(inferLevel("Executive programme")).toBeNull();
  });
  it("percent", () => {
    expect(parsePct("50%")).toBe(50);
    expect(parsePct("45.5")).toBe(45.5);
    expect(parsePct("150")).toBe("invalid");
    expect(parsePct("")).toBeNull();
  });
  it("dates", () => {
    expect(parseDate("2026-10-01")).toBe("2026-10-01");
    expect(parseDate("01/10/2026")).toBe("2026-10-01");
    expect(parseDate("31/02/2026")).toBe("invalid");
    expect(parseDate(new Date(Date.UTC(2026, 0, 5)))).toBe("2026-01-05");
    expect(parseDate("")).toBeNull();
  });
  it("active", () => {
    expect(parseActive("Yes")).toBe(true);
    expect(parseActive("")).toBe(true);
    expect(parseActive("Discontinued")).toBe(false);
    expect(parseActive("maybe")).toBe("invalid");
  });
});

describe("commission", () => {
  it("reads percent, fixed and tier", () => {
    expect(parseCommission("20%")).toEqual({ type: "percent", value: 20 });
    expect(parseCommission("18")).toEqual({ type: "percent", value: 18 });
    expect(parseCommission("₹35,000")).toEqual({ type: "fixed", value: 35000 });
    expect(parseCommission("35000")).toEqual({ type: "fixed", value: 35000 });
    expect(parseCommission("Tier 2")).toEqual({ type: "tier", ref: "Tier 2" });
    expect(parseCommission("")).toBeNull();
    expect(parseCommission("ask sales")).toBe("invalid");
  });
  it("reads an Excel percentage cell (a fraction)", () => {
    expect(parseCommission(0.18)).toEqual({ type: "percent", value: 18 });
    expect(parseCommission(0.2242)).toEqual({ type: "percent", value: 22.42 });
    expect(parseCommission(18)).toEqual({ type: "percent", value: 18 });
    expect(parseCommission("22.42")).toEqual({ type: "percent", value: 22.42 });
  });
});

describe("specialization", () => {
  it("expands abbreviations and defaults to General", () => {
    expect(normaliseSpecialization("HR")).toBe("Human Resource Management");
    expect(normaliseSpecialization("Marketing Mgmt")).toBe("Marketing Management");
    expect(normaliseSpecialization("")).toBe("General");
    expect(normaliseSpecialization("N/A")).toBe("General");
    expect(normaliseSpecialization("Finance")).toBe("Finance");
  });
});

describe("headers and template", () => {
  it("finds the header row under a title row", () => {
    const rows = [["Acme Programme List Oct 2026"], [], ["S.No", "University Name", "Course", "Specialisation", "Mode", "Total Fees"], [1, "Amity", "MBA", "HR", "Online", "1.5L"]];
    expect(findHeaderRow(rows)).toBe(2);
  });
  it("names columns uniquely", () => {
    expect(headerNames(["Fee", "Fee", null, "  Mode  "])).toEqual(["Fee", "Fee (2)", "Column C", "Mode"]);
  });
  it("suggests a template, preferring the saved one", () => {
    const h = ["S.No", "University Name", "Program", "Specialisation", "Mode of Study", "Total Fees", "Commission %"];
    expect(suggestTemplate(h)).toMatchObject({ university: "University Name", course: "Program", specialization: "Specialisation", mode: "Mode of Study", fee_total: "Total Fees", commission: "Commission %" });
    expect(suggestTemplate(h, { course: "Specialisation", fee_total: "Gone" })).toMatchObject({ course: "Specialisation", fee_total: "Total Fees" });
  });
});

describe("normaliseRow", () => {
  const t = { university: "Uni", course: "Course", specialization: "Spec", mode: "Mode", fee_total: "Fee", commission: "Comm", valid_from: "From", valid_to: "To" };
  it("normalises a good row", () => {
    const r = normaliseRow({ Uni: "Amity", Course: "MBA", Spec: "HR", Mode: "online", Fee: "1.99 L", Comm: "20%", From: "01/10/2026", To: null }, t);
    expect(r).toMatchObject({ university: "Amity", course: "MBA", specialization: "Human Resource Management", mode: "Online", level: "PG", fees: { total: 199000 }, commission: { type: "percent", value: 20 }, season_from: "2026-10-01", errors: [] });
  });
  it("collects readable errors", () => {
    const r = normaliseRow({ Uni: "", Course: "MBA", Spec: "", Mode: "hybrid", Fee: "call us", Comm: "", From: "2026-12-01", To: "2026-01-01" }, t);
    expect(r.errors).toEqual(["University is missing", "Unknown mode “hybrid”", "Total fee is not an amount", "Valid from is after valid to"]);
    expect(r.specialization).toBe("General");
  });
});

describe("parseCsv", () => {
  it("handles quotes, BOM, CRLF and semicolons", () => {
    expect(parseCsv('﻿a,b\r\n"x, y","say ""hi"""\r\n')).toEqual([["a", "b"], ["x, y", 'say "hi"']]);
    expect(parseCsv("a;b\n1;2")).toEqual([["a", "b"], ["1", "2"]]);
    expect(parseCsv('a,b\n"line\nbreak",2')).toEqual([["a", "b"], ["line\nbreak", "2"]]);
  });
});

describe("zipUncompressedSize", () => {
  it("rejects non-zips and reads a minimal zip", () => {
    expect(zipUncompressedSize(new TextEncoder().encode("hello world, not a zip file"))).toBeNull();
    // one stored entry "a" containing "hi": local header + data + central directory + end record
    const name = [0x61];
    const local = [0x50, 0x4b, 0x03, 0x04, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, ...name, 0x68, 0x69];
    const central = [0x50, 0x4b, 0x01, 0x02, 20, 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ...name];
    const end = [0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0, 1, 0, 1, 0, central.length, 0, 0, 0, local.length, 0, 0, 0, 0, 0];
    expect(zipUncompressedSize(new Uint8Array([...local, ...central, ...end]))).toBe(2);
  });
});
