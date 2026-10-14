import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from "pdf-lib";

/**
 * Server-made PDFs (spec B11): GST invoices and credit notes, counsellor commission statements, scheduled dashboards.
 * pdf-lib with the standard Helvetica (no font files, no browser). Helvetica cannot draw the rupee sign, so amounts
 * read "Rs." here; the screens use ₹.
 */
const INK = rgb(0.02, 0.13, 0.27);
const MUTED = rgb(0.32, 0.43, 0.55);
const LINE = rgb(0.84, 0.87, 0.9);
const A4: [number, number] = [595.28, 841.89];
const M = 40;

export function rs(n: unknown): string {
  const v = typeof n === "number" ? n : Number(n ?? 0);
  return `Rs. ${(Number.isFinite(v) ? v : 0).toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** Text the standard font can draw (anything outside WinAnsi becomes "?"; the rupee sign becomes "Rs."). */
export function safe(s: unknown): string {
  return String(s ?? "").replace(/₹\s?/g, "Rs. ").replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[–—]/g, "-").replace(/[^\x20-\x7E\xA0-\xFF]/g, "?");
}

class Writer {
  page!: PDFPage;
  y = 0;
  constructor(readonly doc: PDFDocument, readonly font: PDFFont, readonly bold: PDFFont, readonly footer: string) { this.newPage(); }
  newPage() {
    this.page = this.doc.addPage(A4);
    this.y = A4[1] - M;
    this.page.drawText(safe(this.footer), { x: M, y: 20, size: 7, font: this.font, color: MUTED });
  }
  need(h: number) { if (this.y - h < 50) this.newPage(); }
  text(s: unknown, o: { size?: number; bold?: boolean; x?: number; color?: ReturnType<typeof rgb>; gap?: number } = {}) {
    const size = o.size ?? 9;
    for (const line of wrap(safe(s), o.bold ? this.bold : this.font, size, A4[0] - (o.x ?? M) - M)) {
      this.need(size + 4);
      this.page.drawText(line, { x: o.x ?? M, y: this.y - size, size, font: o.bold ? this.bold : this.font, color: o.color ?? INK });
      this.y -= size + 4;
    }
    this.y -= o.gap ?? 0;
  }
  rule() { this.need(8); this.page.drawLine({ start: { x: M, y: this.y - 3 }, end: { x: A4[0] - M, y: this.y - 3 }, thickness: 0.6, color: LINE }); this.y -= 8; }
  /** A table: widths are fractions of the printable width; numeric columns right-aligned. */
  table(cols: { label: string; w: number; right?: boolean }[], rows: unknown[][], size = 8) {
    const total = A4[0] - 2 * M;
    const xs: number[] = [];
    cols.reduce((x, c) => { xs.push(x); return x + c.w * total; }, M);
    const drawRow = (cells: unknown[], bold: boolean) => {
      const wrapped = cells.map((c, i) => wrap(safe(c), bold ? this.bold : this.font, size, cols[i]!.w * total - 6));
      const h = Math.max(...wrapped.map((w) => w.length)) * (size + 3) + 3;
      this.need(h);
      wrapped.forEach((lines, i) => lines.forEach((line, j) => {
        const f = bold ? this.bold : this.font;
        const col = cols[i]!, x0 = xs[i] ?? M;
        const x = col.right ? x0 + col.w * total - 3 - f.widthOfTextAtSize(line, size) : x0 + 3;
        this.page.drawText(line, { x, y: this.y - size - j * (size + 3), size, font: f, color: bold ? MUTED : INK });
      }));
      this.y -= h;
      this.page.drawLine({ start: { x: M, y: this.y + 1 }, end: { x: A4[0] - M, y: this.y + 1 }, thickness: 0.4, color: LINE });
    };
    drawRow(cols.map((c) => c.label), true);
    for (const r of rows) drawRow(r, false);
    this.y -= 6;
  }
}

function wrap(s: string, font: PDFFont, size: number, width: number): string[] {
  const out: string[] = [];
  for (const para of s.split("\n")) {
    let line = "";
    for (const word of para.split(/\s+/)) {
      const next = line ? `${line} ${word}` : word;
      if (font.widthOfTextAtSize(next, size) <= width || !line) line = next;
      else { out.push(line); line = word; }
      while (font.widthOfTextAtSize(line, size) > width && line.length > 1) {
        let cut = line.length - 1;
        while (cut > 1 && font.widthOfTextAtSize(line.slice(0, cut), size) > width) cut--;
        out.push(line.slice(0, cut)); line = line.slice(cut);
      }
    }
    out.push(line);
  }
  return out;
}

async function start(title: string, footer: string) {
  const doc = await PDFDocument.create();
  doc.setTitle(safe(title)); doc.setProducer("Eduwit CRM"); doc.setCreator("Eduwit CRM");
  const w = new Writer(doc, await doc.embedFont(StandardFonts.Helvetica), await doc.embedFont(StandardFonts.HelveticaBold), footer);
  return { doc, w };
}

export type InvoiceData = {
  kind: "invoice" | "credit_note"; number: string | null; issue_date: string | null; due_on: string | null; status: string; sac: string | null; gst_pct: number;
  supply: "intra" | "inter"; net: number; gst: number; gross: number; is_test: boolean; credit_of_number?: string | null;
  billing: { eduwit: { name?: string; gstin?: string; address?: string; state_code?: string }; university: { name?: string; gstin?: string; address?: string; state_code?: string } };
  lines: { description: string; net: number; gst: number; gross: number }[];
};

/** A GST tax invoice (or credit note): both parties' GSTINs, SAC, one line per enrolment, CGST+SGST or IGST. */
export async function invoicePdf(i: InvoiceData): Promise<Uint8Array> {
  const label = i.kind === "credit_note" ? "Credit note" : "Tax invoice";
  const { doc, w } = await start(`${label} ${i.number ?? "draft"}`, `${label} ${i.number ?? "DRAFT"} · generated by Eduwit CRM`);
  if (i.is_test) w.text("TEST - not a real invoice (test leads only)", { bold: true, size: 10, color: rgb(0.7, 0.14, 0.09), gap: 4 });
  if (!i.number) w.text("DRAFT - not yet approved", { bold: true, size: 10, color: rgb(0.7, 0.14, 0.09), gap: 4 });
  w.text(label.toUpperCase(), { size: 16, bold: true, gap: 6 });
  w.text(`Number: ${i.number ?? "-"}    Date: ${i.issue_date ?? "-"}    Due: ${i.due_on ?? "-"}`, { size: 9 });
  if (i.credit_of_number) w.text(`Against invoice ${i.credit_of_number}`, { size: 9 });
  w.text(`SAC: ${i.sac ?? "-"}    Place of supply: ${i.supply === "intra" ? "intra-state (CGST + SGST)" : "inter-state (IGST)"}`, { size: 9, gap: 8 });
  const e = i.billing.eduwit, u = i.billing.university;
  w.text("From", { bold: true, color: MUTED });
  w.text(`${e.name ?? ""}\nGSTIN ${e.gstin ?? "-"}${e.address ? `\n${e.address}` : ""}`, { gap: 6 });
  w.text("To", { bold: true, color: MUTED });
  w.text(`${u.name ?? ""}\nGSTIN ${u.gstin ?? "-"}${u.address ? `\n${u.address}` : ""}`, { gap: 10 });
  w.table([{ label: "#", w: 0.05 }, { label: "Description", w: 0.53 }, { label: "Taxable value", w: 0.14, right: true }, { label: "GST", w: 0.13, right: true }, { label: "Total", w: 0.15, right: true }],
    i.lines.map((l, n) => [n + 1, l.description, rs(l.net), rs(l.gst), rs(l.gross)]));
  const half = Math.round((i.gst / 2) * 100) / 100;
  const taxes: [string, string][] = i.supply === "intra"
    ? [[`CGST ${i.gst_pct / 2}%`, rs(half)], [`SGST ${i.gst_pct / 2}%`, rs(i.gst - half)]]
    : [[`IGST ${i.gst_pct}%`, rs(i.gst)]];
  for (const [k, v] of [["Taxable value", rs(i.net)] as [string, string], ...taxes, ["Total", rs(i.gross)] as [string, string]]) {
    w.need(14);
    w.page.drawText(safe(k), { x: A4[0] - M - 220, y: w.y - 10, size: 10, font: k === "Total" ? w.bold : w.font, color: INK });
    const t = safe(v);
    w.page.drawText(t, { x: A4[0] - M - w.bold.widthOfTextAtSize(t, 10), y: w.y - 10, size: 10, font: k === "Total" ? w.bold : w.font, color: INK });
    w.y -= 15;
  }
  w.y -= 10;
  w.text("Commission on enrolments verified by Eduwit. Subject to the agreement between the parties.", { size: 8, color: MUTED });
  return doc.save();
}

export type StatementData = {
  counsellor: { name: string | null; email: string | null }; period: string; approved_at: string | null; status: string; amount: number; tds: number; open: number;
  lines: { kind: string; student: string | null; university: string | null; programme: string | null; enrolled_on: string | null; amount: number | null; tds: number;
           rate?: { pct?: number; base?: number } | null; partners?: { name: string; computed?: { amount?: number } }[]; reason: string | null; rate_source: string | null }[];
};

/** A counsellor's statement for one run: what was settled, the rate behind each line, clawbacks, what stays open. */
export async function statementPdf(s: StatementData): Promise<Uint8Array> {
  const { doc, w } = await start(`Commission statement ${s.period}`, `Commission statement · ${s.counsellor.name ?? ""} · ${s.period} · Eduwit CRM`);
  w.text("COMMISSION STATEMENT", { size: 16, bold: true, gap: 4 });
  w.text(`${s.counsellor.name ?? ""} (${s.counsellor.email ?? ""})`, { size: 10 });
  w.text(`Run: ${s.period}    Status: ${s.status}${s.approved_at ? `    Approved: ${s.approved_at.slice(0, 10)}` : ""}`, { size: 9, gap: 8 });
  w.text("Each enrolment you closed owes Eduwit the commission the edtech partners pay Eduwit for that programme (the highest where several partners offer it). This statement records what was settled in this run.", { size: 8, color: MUTED, gap: 8 });
  w.table([{ label: "Student", w: 0.16 }, { label: "Programme", w: 0.22 }, { label: "Enrolled", w: 0.1 }, { label: "Rate and partners", w: 0.26 }, { label: "Kind", w: 0.1 }, { label: "Amount", w: 0.16, right: true }],
    s.lines.map((l) => [
      l.student ?? "-", `${l.university ?? ""} - ${l.programme ?? ""}`, l.enrolled_on ?? "-",
      l.kind === "booking" ? `${l.rate?.pct !== undefined ? `${l.rate.pct}% of ${rs(l.rate.base)}` : "fixed"}${l.rate_source === "override" ? " (override)" : ""}; ${(l.partners ?? []).map((p) => p.name).join(", ") || "no partner"}`
                           : (l.reason ?? ""),
      l.kind, rs(l.amount)]));
  w.text(`Settled in this run: ${rs(s.amount)}${s.tds ? `   TDS: ${rs(s.tds)}   Net: ${rs(s.amount - s.tds)}` : ""}`, { bold: true, size: 10 });
  w.text(`Still open (provisional, confirmed or due): ${rs(s.open)}`, { size: 9 });
  return doc.save();
}

/** A dashboard as tables, for the scheduled email (one section per widget). */
export async function dashboardPdf(d: { name: string; range: string; sections: { title: string; columns: string[]; rows: Record<string, unknown>[] }[] }): Promise<Uint8Array> {
  const { doc, w } = await start(d.name, `${d.name} · ${d.range} · Eduwit CRM`);
  w.text(d.name, { size: 16, bold: true, gap: 2 });
  w.text(d.range, { size: 9, color: MUTED, gap: 10 });
  for (const s of d.sections) {
    w.text(s.title, { size: 11, bold: true, gap: 2 });
    if (!s.rows.length) { w.text("No data in this period.", { size: 8, color: MUTED, gap: 6 }); continue; }
    const cols = s.columns.slice(0, 7);
    w.table(cols.map((c, i) => ({ label: c, w: 1 / cols.length, right: i > 0 })), s.rows.slice(0, 60).map((r) => cols.map((c) => r[c] ?? "")));
  }
  return doc.save();
}
