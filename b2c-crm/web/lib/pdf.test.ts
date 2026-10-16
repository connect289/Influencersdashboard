import { describe, expect, it } from "vitest";
import { PDFDocument } from "pdf-lib";
import { dashboardPdf, invoicePdf, rs, safe, statementPdf } from "./pdf";

describe("pdf", () => {
  it("formats rupees for the standard font", () => {
    expect(rs(1234567.5)).toBe("Rs. 12,34,567.50");
    expect(safe("₹500 – ok “x”")).toBe("Rs. 500 - ok \"x\"");
    expect(safe("नमस्ते")).toBe("??????");
  });
  it("builds an invoice with many lines over several pages", async () => {
    const lines = Array.from({ length: 80 }, (_, i) => ({ description: `Student ${i} · Online MBA · enrolled 02 Sep 2026`, net: 15254.24, gst: 2745.76, gross: 18000 }));
    const bytes = await invoicePdf({ kind: "invoice", number: "EDW/2026-27/0001", issue_date: "2026-10-05", due_on: "2026-11-04", status: "approved", sac: "998599", gst_pct: 18,
      supply: "intra", net: 1220339.2, gst: 219660.8, gross: 1440000, is_test: false,
      billing: { eduwit: { name: "Eduwit Learning Services", gstin: "07AABCE1234F1Z5" }, university: { name: "Amity Online", gstin: "07AAACA1234B1Z2" } }, lines });
    const doc = await PDFDocument.load(bytes);
    expect(doc.getPageCount()).toBeGreaterThan(1);
    expect(doc.getTitle()).toBe("Tax invoice EDW/2026-27/0001");
  });
  it("builds a statement and a dashboard", async () => {
    const s = await statementPdf({ counsellor: { name: "Priya", email: "p@eduwit.in" }, period: "2026-09-01", approved_at: "2026-10-05T10:00:00Z", status: "approved", amount: 37500, tds: 0, open: 35000,
      lines: [{ kind: "booking", student: "Asha", university: "Amity", programme: "Online MBA", enrolled_on: "2026-09-02", amount: 22500, tds: 0, rate: { pct: 25, base: 90000 },
                partners: [{ name: "Partner A" }, { name: "Partner B" }], reason: null, rate_source: "partner" }] });
    expect((await PDFDocument.load(s)).getPageCount()).toBe(1);
    const d = await dashboardPdf({ name: "My week", range: "9-15 Oct 2026", sections: [{ title: "Calls", columns: ["Day", "Calls"], rows: [{ Day: "2026-10-09", Calls: 4 }] }, { title: "Empty", columns: [], rows: [] }] });
    expect((await PDFDocument.load(d)).getPageCount()).toBe(1);
  });
});
