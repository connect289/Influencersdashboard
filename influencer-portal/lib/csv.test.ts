import { describe, expect, it } from "vitest";
import { CsvError, parseCsv, toCsv } from "./csv";

describe("parseCsv", () => {
  it("parses headers and rows with CRLF, BOM and trailing newline", () => {
    expect(parseCsv("﻿name,handle\r\nRiya,riya\r\nArjun,arjun\r\n")).toEqual({
      headers: ["name", "handle"],
      rows: [
        ["Riya", "riya"],
        ["Arjun", "arjun"],
      ],
    });
  });
  it("handles quotes, escaped quotes, commas and newlines inside quotes", () => {
    const r = parseCsv('a,b\n"Sharma, Riya","She said ""hi""\nthen left"\n');
    expect(r.rows).toEqual([["Sharma, Riya", 'She said "hi"\nthen left']]);
  });
  it("keeps empty fields and skips blank lines", () => {
    expect(parseCsv("a,b,c\n1,,3\n\n,,\n").rows).toEqual([
      ["1", "", "3"],
      ["", "", ""],
    ]);
  });
  it("rejects unterminated quotes, empty input and too many rows", () => {
    expect(() => parseCsv('a\n"open')).toThrow(CsvError);
    expect(() => parseCsv("")).toThrow(CsvError);
    expect(() => parseCsv("a\n1\n2\n3\n", { maxRows: 2 })).toThrow("too_many_rows");
  });
});

describe("toCsv", () => {
  it("quotes when needed and neutralises formulas", () => {
    expect(
      toCsv(
        ["a", "b"],
        [
          ["x,y", "=HYPERLINK(1)"],
          [null, 'say "hi"'],
        ],
      ),
    ).toBe('a,b\r\n"x,y",\'=HYPERLINK(1)\r\n,"say ""hi"""\r\n');
  });
  it("round-trips", () => {
    const rows = [["Riya", "multi\nline", 'q"uote']];
    expect(parseCsv(toCsv(["n", "m", "q"], rows)).rows).toEqual(rows);
  });
});

describe("negative numbers", () => {
  it("keeps plain negative numbers as numbers but still neutralises formulas", () => {
    expect(toCsv(["a", "b", "c"], [[-100.5, "-12.00", "-2+3"]])).toBe("a,b,c\r\n-100.5,-12.00,'-2+3\r\n");
  });
});
