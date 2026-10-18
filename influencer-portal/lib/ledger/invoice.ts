// GST invoices from registered creators (spec 11): before a payout that carries GST, the creator uploads a tax invoice
// whose GSTIN, taxable value and GST match the payout. Finance reviews it; the checks below run when it is submitted
// and again in the database. Pure.
import { GSTIN_RE } from "@/lib/creators/schemas";

/** Invoice numbers under the GST rules: at most 16 characters of letters, digits, "-" and "/". */
export const INVOICE_NUMBER_RE = /^[A-Za-z0-9/-]{1,16}$/;
/** Rounding allowance between the invoice and the payout (₹1). */
export const INVOICE_TOLERANCE_PAISE = 100;

const CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";

/** The GSTIN check character (the 15th) over the first 14, as published by GSTN. */
export function gstinCheckChar(first14: string): string {
  let total = 0;
  for (let i = 0; i < 14; i++) {
    const v = CHARS.indexOf(first14.charAt(i)) * (i % 2 === 0 ? 1 : 2);
    total += Math.floor(v / 36) + (v % 36);
  }
  return CHARS.charAt((36 - (total % 36)) % 36);
}

export function validGstin(gstin: string): boolean {
  const g = gstin.trim().toUpperCase();
  return GSTIN_RE.test(g) && gstinCheckChar(g.slice(0, 14)) === g.charAt(14);
}

export interface InvoiceInput {
  number: string;
  issued_on: string;
  gstin: string;
  taxable_paise: number;
  gst_paise: number;
}

export const INVOICE_PROBLEMS = [
  "number",
  "date_future",
  "date_before_payout",
  "gstin_invalid",
  "gstin_mismatch",
  "taxable_mismatch",
  "gst_mismatch",
] as const;
export type InvoiceProblem = (typeof INVOICE_PROBLEMS)[number];

export function invoiceProblems(
  inv: InvoiceInput,
  payout: { gst_base_paise: number; gst_paise: number; created_on: string },
  creatorGstin: string,
  today: string,
): InvoiceProblem[] {
  const out: InvoiceProblem[] = [];
  if (!INVOICE_NUMBER_RE.test(inv.number.trim())) out.push("number");
  if (inv.issued_on > today) out.push("date_future");
  if (inv.issued_on < payout.created_on) out.push("date_before_payout");
  const g = inv.gstin.trim().toUpperCase();
  if (!validGstin(g)) out.push("gstin_invalid");
  else if (g !== creatorGstin.trim().toUpperCase()) out.push("gstin_mismatch");
  if (Math.abs(inv.taxable_paise - payout.gst_base_paise) > INVOICE_TOLERANCE_PAISE) out.push("taxable_mismatch");
  if (Math.abs(inv.gst_paise - payout.gst_paise) > INVOICE_TOLERANCE_PAISE) out.push("gst_mismatch");
  return out;
}
