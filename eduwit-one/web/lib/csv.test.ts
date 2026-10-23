import { describe, expect, it } from "vitest";
import { toCsv } from "./csv.ts";

describe("toCsv", () => {
  it("quotes every value, doubles quotes and neutralises formulas", () => {
    const out = toCsv([{ a: 'say "hi"', b: "=1+1", c: { x: 1 }, d: null }], ["a", "b", "c", "d"]);
    expect(out).toBe('"a","b","c","d"\r\n"say ""hi""","\'=1+1","{""x"":1}",""\r\n');
  });
});
