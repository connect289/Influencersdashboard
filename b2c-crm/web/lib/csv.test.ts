import { describe, expect, it } from "vitest";
import { csvCell, toCsv } from "./csv";

describe("csv", () => {
  it("quotes and neutralises formulas", () => {
    expect(csvCell('a "b", c')).toBe('"a ""b"", c"');
    expect(csvCell("=HYPERLINK(\"x\")")).toBe("\"'=HYPERLINK(\"\"x\"\")\"");
    expect(csvCell("+91 98")).toBe("'+91 98");
    expect(csvCell(["mba", "diwali"])).toBe("mba; diwali");
    expect(csvCell(null)).toBe("");
  });
  it("writes a header and rows with a BOM for Excel", () => {
    expect(toCsv(["a", "b"], [{ a: 1, b: "x\ny" }])).toBe('﻿a,b\r\n1,"x\ny"\r\n');
  });
});
