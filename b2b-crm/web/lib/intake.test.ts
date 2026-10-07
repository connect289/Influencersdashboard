import { describe, expect, it } from "vitest";
import { cellText, chunk, mappingProblem, parseCsvRows, suggestMapping, tableFromRows, toCsv } from "./intake";

describe("mapping suggestions", () => {
  it("maps common headers", () => {
    expect(suggestMapping(["Student Name", "Mobile No", "Email ID", "Course Interested", "City", "Remarks", "Owner"])).toEqual({
      "Student Name": "full_name", "Mobile No": "phone", "Email ID": "email", "Course Interested": "course", City: "city", Remarks: "notes", Owner: "ignore",
    });
  });
  it("uses each field once", () => {
    const m = suggestMapping(["Phone", "Phone Number"]);
    expect(Object.values(m).filter((v) => v === "phone")).toHaveLength(1);
  });
  it("keeps split names only without a full name", () => {
    expect(suggestMapping(["First Name", "Last Name", "Mobile"])).toMatchObject({ "First Name": "first_name", "Last Name": "last_name" });
    expect(suggestMapping(["Name", "First Name", "Mobile"])).toMatchObject({ Name: "full_name", "First Name": "ignore" });
  });
  it("finds problems", () => {
    expect(mappingProblem({ Name: "full_name" })).toBe("Map a column to the phone number.");
    expect(mappingProblem({ A: "phone", B: "email", C: "email" })).toBe("Email is mapped from more than one column.");
    expect(mappingProblem({ A: "phone", B: "ignore" })).toBeNull();
  });
});

describe("files", () => {
  it("parses CSV with quotes, semicolons and a BOM", () => {
    expect(parseCsvRows('﻿name;phone\n"Shah, A";"98765 43210"\r\nB;1')).toEqual([["name", "phone"], ["Shah, A", "98765 43210"], ["B", "1"]]);
  });
  it("caps rows", () => {
    expect(parseCsvRows("a,b\n1,2\n3,4\n5,6", 2)).toHaveLength(2);
  });
  it("finds the header and drops blank rows", () => {
    const t = tableFromRows([["Leads export"], [], ["Name", "Phone", "Phone"], ["Asha", 9876543210, ""], [null, "", ""], ["Ravi", "98765 00000", "x"]]);
    expect(t.headers).toEqual(["Name", "Phone", "Phone (2)"]);
    expect(t.rows).toEqual([{ Name: "Asha", Phone: "9876543210", "Phone (2)": "" }, { Name: "Ravi", Phone: "98765 00000", "Phone (2)": "x" }]);
  });
  it("renders cells", () => {
    expect(cellText(919876543210)).toBe("919876543210");
    expect(cellText(new Date("2026-10-01T00:00:00Z"))).toBe("2026-10-01");
    expect(cellText("  a   b ")).toBe("a b");
  });
  it("chunks", () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
  });
  it("writes safe CSV", () => {
    expect(toCsv([{ a: "x,y", b: "=SUM(1)" }, { a: null, b: 2 }], ["a", "b"])).toBe('a,b\r\n"x,y","\'=SUM(1)"\r\n,2');
  });
});
