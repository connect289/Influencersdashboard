import { describe, expect, it } from "vitest";
import { parseHolidays, weekOf } from "./holidays";

describe("holiday import", () => {
  it("reads dates, names and kinds, skipping a header and blank lines", () => {
    const r = parseHolidays("date, name, kind\n2026-10-20, Diwali, national\n\n2026-11-05,\"Guru Nanak Jayanti, Gurpurab\"\n25/12/2026, Christmas, company");
    expect(r.errors).toEqual([]);
    expect(r.rows).toEqual([
      { day: "2026-10-20", name: "Diwali", kind: "national" },
      { day: "2026-11-05", name: "Guru Nanak Jayanti, Gurpurab", kind: "company" },
      { day: "2026-12-25", name: "Christmas", kind: "company" },
    ]);
  });
  it("names the lines it cannot read", () => {
    const r = parseHolidays("2026-02-30, Nope\n2026-10-20, Diwali, festival\n2026-10-21, A\n2026-10-21, B");
    expect(r.rows).toEqual([{ day: "2026-10-21", name: "A", kind: "company" }]);
    expect(r.errors).toHaveLength(3);
    expect(r.errors[0]).toMatch(/^Line 1/);
  });
  it("finds the week's Monday", () => {
    expect(weekOf("2026-10-15")).toEqual({ from: "2026-10-12", prev: "2026-10-05", next: "2026-10-19" });
    expect(weekOf("2026-10-12").from).toBe("2026-10-12");
    expect(weekOf("2026-10-18").from).toBe("2026-10-12");
  });
});
