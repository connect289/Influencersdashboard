import "server-only";
// Finance files: creators' GST invoices in the private inf-invoices bucket (<creator>/<payout>/<file>), payment
// advice PDFs and Form 16A certificates in inf-documents (advice/<creator>/…, form16a/<creator>/…). Uploads are
// one-time signed URLs; downloads go through /api/finance/file after inf.finance_file_allowed() for the caller.
import { safeFileName } from "@/lib/creators/schemas";

export const INVOICES_BUCKET = "inf-invoices";
export const DOCUMENTS_BUCKET = "inf-documents";
export const INVOICE_TYPES = ["application/pdf", "image/jpeg", "image/png"] as const;
export const INVOICE_MAX_BYTES = 10 * 1024 * 1024;

export function bucketForPath(path: string): string | null {
  if (/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[A-Za-z0-9._-]{1,120}$/.test(path)) return INVOICES_BUCKET;
  if (/^(advice|form16a)\/[0-9a-f-]{36}\/[A-Za-z0-9._-]{1,120}$/.test(path)) return DOCUMENTS_BUCKET;
  return null;
}

export function invoicePath(creatorId: string, payoutId: string, fileName: string): string {
  return `${creatorId}/${payoutId}/${Date.now().toString()}-${safeFileName(fileName).slice(0, 100)}`;
}

export function certificatePath(creatorId: string, fy: string, quarter: string): string {
  return `form16a/${creatorId}/${fy}-${quarter}-${crypto.randomUUID().slice(0, 8)}.pdf`;
}

export function advicePath(creatorId: string, payoutRef: string): string {
  return `advice/${creatorId}/${payoutRef}.pdf`;
}

/** A link to a finance file for whoever is signed in, or null when they may not open it. */
export function fileHref(path: string): string {
  return `/api/finance/file?path=${encodeURIComponent(path)}`;
}
