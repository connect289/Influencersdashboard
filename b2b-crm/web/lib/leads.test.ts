import { describe, expect, it } from "vitest";
import {
  formatPhone, hasFilters, humanize, leadsHref, parseLeadId, parseLeadQuery, statusTone, toCsv, toRpcParams, toggle, whatsappLink,
} from "./leads";

describe("parseLeadQuery", () => {
  it("defaults to newest first, live leads, no tests", () => {
    expect(parseLeadQuery({})).toEqual({ q: "", stage: [], source: [], status: [], dest: null, sort: "created_at", dir: "desc", test: false, bin: false });
  });

  it("reads every filter", () => {
    const q = parseLeadQuery({ q: "  ravi ", stage: "new,qualifying", source: "whatsapp_direct", status: "hot,warm", dest: "partner", sort: "name", dir: "asc", test: "1", view: "bin" });
    expect(q).toEqual({ q: "ravi", stage: ["new", "qualifying"], source: ["whatsapp_direct"], status: ["HOT", "WARM"], dest: "partner", sort: "name", dir: "asc", test: true, bin: true });
  });

  it("rejects unknown enums and caps sizes", () => {
    const q = parseLeadQuery({ sort: "id; drop", dir: "sideways", dest: "x", q: "a".repeat(500), stage: Array.from({ length: 50 }, (_, i) => `s${i}`).join(",") });
    expect(q.sort).toBe("created_at");
    expect(q.dir).toBe("desc");
    expect(q.dest).toBeNull();
    expect(q.q).toHaveLength(100);
    expect(q.stage).toHaveLength(20);
  });

  it("de-duplicates and drops empty list items; takes the first of repeated params", () => {
    expect(parseLeadQuery({ stage: "a,,a, b ", q: ["first", "second"] })).toMatchObject({ stage: ["a", "b"], q: "first" });
  });
});

describe("parseLeadId", () => {
  it("accepts positive integers only", () => {
    expect(parseLeadId({ lead: "1218" })).toBe(1218);
    expect(parseLeadId({ lead: "0" })).toBeNull();
    expect(parseLeadId({ lead: "-3" })).toBeNull();
    expect(parseLeadId({ lead: "12abc" })).toBeNull();
    expect(parseLeadId({})).toBeNull();
  });
});

describe("leadsHref", () => {
  const base = parseLeadQuery({});
  it("leaves defaults out", () => {
    expect(leadsHref(base)).toBe("/leads");
  });
  it("round-trips through parseLeadQuery", () => {
    const q = parseLeadQuery({ q: "a&b=c", stage: "new", status: "HOT", dest: "unrouted", sort: "last_activity", dir: "asc", test: "1", view: "bin" });
    const sp = Object.fromEntries(new URLSearchParams(leadsHref(q).split("?")[1]));
    expect(parseLeadQuery(sp)).toEqual(q);
  });
  it("applies a patch and the open lead", () => {
    expect(leadsHref(base, { bin: true }, 7)).toBe("/leads?view=bin&lead=7");
  });
});

describe("toRpcParams", () => {
  it("maps the URL query to the database arguments", () => {
    const p = toRpcParams(parseLeadQuery({ dest: "in_house", test: "1" }), { after: { v: "x", id: "9" }, limit: 10 });
    expect(p).toMatchObject({ destination: "in_house", include_test: true, bin: false, limit: 10, after: { v: "x", id: "9" }, q: undefined });
  });
});

describe("helpers", () => {
  it("toggle adds and removes", () => {
    expect(toggle(["a"], "b")).toEqual(["a", "b"]);
    expect(toggle(["a", "b"], "a")).toEqual(["b"]);
  });
  it("hasFilters ignores sort, tests and bin", () => {
    expect(hasFilters(parseLeadQuery({ sort: "name", test: "1", view: "bin" }))).toBe(false);
    expect(hasFilters(parseLeadQuery({ status: "HOT" }))).toBe(true);
  });
  it("humanize", () => {
    expect(humanize("whatsapp_direct")).toBe("WhatsApp direct");
    expect(humanize("EARN_IT")).toBe("Earn it");
    expect(humanize("(none)")).toBe("None");
    expect(humanize("pg")).toBe("PG");
    expect(humanize(null)).toBe("None");
  });
  it("statusTone", () => {
    expect(statusTone("hot")).toBe("danger");
    expect(statusTone("WARM")).toBe("warning");
    expect(statusTone("COLD")).toBe("info");
    expect(statusTone(null)).toBe("neutral");
  });
  it("formatPhone and whatsappLink", () => {
    expect(formatPhone("919800000012")).toBe("+91 98000 00012");
    expect(formatPhone("9800000012")).toBe("+91 98000 00012");
    expect(formatPhone("+1 555 0100")).toBe("+1 555 0100");
    expect(formatPhone(null)).toBe("—");
    expect(whatsappLink("+91 98000-00012")).toBe("https://wa.me/919800000012");
    expect(whatsappLink("9800000012")).toBe("https://wa.me/919800000012");
    expect(whatsappLink("123")).toBeNull();
  });
});

describe("toCsv", () => {
  it("quotes, escapes, adds a BOM and CRLF", () => {
    const csv = toCsv(["a", "b"], [{ a: 'say "hi", ok', b: null }, { a: "line\nbreak", b: 3 }]);
    expect(csv).toBe('﻿a,b\r\n"say ""hi"", ok",\r\n"line\nbreak",3\r\n');
  });
  it("neutralises spreadsheet formulas", () => {
    const csv = toCsv(["a"], [{ a: "=HYPERLINK(\"x\")" }, { a: "+91 98000" }, { a: "-5" }, { a: "@SUM(1)" }, { a: "ok" }]);
    expect(csv.split("\r\n").slice(1, 6)).toEqual(['"\'=HYPERLINK(""x"")"', "'+91 98000", "'-5", "'@SUM(1)", "ok"]);
  });
});
