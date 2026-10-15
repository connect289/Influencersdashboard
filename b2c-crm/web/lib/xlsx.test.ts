import { describe, expect, it } from "vitest";
import { colName, sheetXml, toXlsx, xmlText } from "./xlsx";
import { unzip } from "./unzip.testutil";

describe("xlsx", () => {
  it("names columns like a spreadsheet", () => {
    expect([0, 1, 25, 26, 27, 51, 52, 701, 702].map(colName)).toEqual(["A", "B", "Z", "AA", "AB", "AZ", "BA", "ZZ", "AAA"]);
  });

  it("escapes XML and drops control characters", () => {
    expect(xmlText(`a<b>&"c"\u0001\u0007d`)).toBe("a&lt;b&gt;&amp;&quot;c&quot;d");
  });

  it("writes numbers as numbers, text inline, a bold header and no formulas", () => {
    const x = sheetXml(["lead_id", "name", "tags", "opted_out", "phone"], [{ lead_id: 12, name: "=HYPERLINK(1)", tags: ["hot", "mba"], opted_out: false, phone: "+919876543210" }]);
    expect(x).toContain('<c r="A1" s="1" t="inlineStr"><is><t xml:space="preserve">lead_id</t></is></c>');
    expect(x).toContain('<c r="A2"><v>12</v></c>');
    expect(x).toContain('<c r="B2" t="inlineStr"><is><t xml:space="preserve">=HYPERLINK(1)</t></is></c>');
    expect(x).toContain('<c r="C2" t="inlineStr"><is><t xml:space="preserve">hot; mba</t></is></c>');
    expect(x).toContain('<c r="D2" t="b"><v>0</v></c>');
    expect(x).toContain('<c r="E2" t="inlineStr">');
    expect(x).not.toContain("<f>");
  });

  it("leaves empty cells out", () => {
    expect(sheetXml(["a", "b"], [{ a: null, b: "" }])).toContain('<row r="2"></row>');
  });

  it("packages a workbook a spreadsheet program can open", () => {
    const files = unzip(toXlsx(["lead_id", "name"], [{ lead_id: 1, name: "Asha" }], "Leads: test/1"));
    expect(Object.keys(files).sort()).toEqual(["[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/workbook.xml", "xl/worksheets/sheet1.xml"]);
    expect(files["xl/workbook.xml"]).toContain('<sheet name="Leads  test 1" sheetId="1" r:id="rId1"/>');
    expect(files["xl/worksheets/sheet1.xml"]).toContain("Asha");
    expect(files["[Content_Types].xml"]).toContain("/xl/worksheets/sheet1.xml");
  });
});
