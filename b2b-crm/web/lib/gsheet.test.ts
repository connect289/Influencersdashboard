import { describe, expect, it } from "vitest";
import { parseSheetLink, sheetDue, sheetExportUrl } from "./gsheet";

const ID = "1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abc";

describe("Google Sheet links", () => {
  it("takes the ID from a browser link, a /u/0 link or a bare ID", () => {
    expect(parseSheetLink(`https://docs.google.com/spreadsheets/d/${ID}/edit#gid=0`)).toBe(ID);
    expect(parseSheetLink(`https://docs.google.com/spreadsheets/u/1/d/${ID}/edit?usp=sharing`)).toBe(ID);
    expect(parseSheetLink(`  ${ID}  `)).toBe(ID);
  });
  it("refuses other links and short strings", () => {
    expect(parseSheetLink("https://drive.google.com/file/d/abc/view")).toBeNull();
    expect(parseSheetLink("https://example.com/spreadsheets/d/short")).toBeNull();
    expect(parseSheetLink("")).toBeNull();
  });
  it("downloads the whole workbook as Excel", () => {
    expect(sheetExportUrl(ID)).toBe(`https://docs.google.com/spreadsheets/d/${ID}/export?format=xlsx`);
  });
  it("is due once the interval has passed or it was never checked", () => {
    const now = Date.parse("2026-10-06T12:00:00Z");
    expect(sheetDue(null, 6, now)).toBe(true);
    expect(sheetDue("2026-10-06T07:00:00Z", 6, now)).toBe(false);
    expect(sheetDue("2026-10-06T05:00:00Z", 6, now)).toBe(true);
  });
});
