// Inputs for the ledger, payout, invoice and TDS actions, shared by forms and server actions.
import { z } from "zod";
import { TDS_COMPONENTS } from "@/lib/compensation/tax";
import { INVOICE_NUMBER_RE } from "./invoice";
import { UTR_RE } from "./utr";

const uuid = z.uuid();
const reason = z.string().trim().min(3).max(500);
const isoDate = z.iso.date();
/** Rupees as typed (up to two decimals), stored as paise. */
const rupees = z.number().positive().max(100_000_000);

export const adjustmentInput = z.object({
  creatorId: uuid,
  dealId: uuid.nullable().default(null),
  direction: z.enum(["credit", "debit"]),
  amountRupees: rupees,
  component: z.enum(TDS_COMPONENTS).default("commission"),
  dueOn: isoDate.nullable().default(null),
  reason,
});
export type AdjustmentInput = z.input<typeof adjustmentInput>;

export const holdInput = z.object({ entryId: z.number().int().positive(), hold: z.boolean(), reason });
export const holdCreatorInput = z.object({ creatorId: uuid, hold: z.boolean(), reason });

export const manualEventInput = z
  .object({
    dealId: uuid,
    kind: z.enum(["manual_release", "breach"]),
    ref: z
      .string()
      .regex(/^[a-z0-9_-]{1,40}\.[a-z0-9_-]{1,40}$/)
      .nullable()
      .default(null),
    reason,
  })
  .refine((v) => (v.kind === "manual_release") === (v.ref !== null), { path: ["ref"] });
export type ManualEventInput = z.input<typeof manualEventInput>;

export const RECEIPT_STATUSES = ["expected", "partly_received", "received", "reversed", "withdrawn"] as const;
export const receiptInput = z.object({
  enrollmentRef: z.string().regex(/^(b2b|b2c):\d+$/),
  studentLeadId: z.number().int().positive().nullable().default(null),
  status: z.enum(RECEIPT_STATUSES),
  grossRupees: z.number().min(0).max(100_000_000).default(0),
  receivedRupees: z.number().min(0).max(100_000_000).default(0),
  receivedOn: isoDate.nullable().default(null),
  reason,
});
export type ReceiptInput = z.input<typeof receiptInput>;

export const batchPrepareInput = z.object({
  creatorIds: z.array(uuid).max(500).default([]),
  campaignId: uuid.nullable().default(null),
  dueBy: isoDate.nullable().default(null),
  note: z.string().trim().max(500).default(""),
});
export type BatchPrepareInput = z.input<typeof batchPrepareInput>;

export const batchReasonInput = z.object({ id: uuid, reason });
export const markPaidInput = z.object({
  payoutRef: z.string().regex(/^PO-\d{4}-\d{2}-\d{5}$/),
  utr: z
    .string()
    .trim()
    .transform((s) => s.toUpperCase())
    .pipe(z.string().regex(UTR_RE)),
  paidOn: isoDate,
});
export type MarkPaidInput = z.input<typeof markPaidInput>;
export const utrFileInput = z.object({ text: z.string().min(10).max(500_000) });

export const invoiceInput = z.object({
  payoutId: uuid,
  number: z.string().trim().regex(INVOICE_NUMBER_RE),
  issuedOn: isoDate,
  gstin: z
    .string()
    .trim()
    .transform((s) => s.toUpperCase()),
  taxableRupees: z.number().min(0).max(100_000_000),
  gstRupees: z.number().min(0).max(100_000_000),
  filePath: z.string().regex(/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[A-Za-z0-9._-]{1,120}$/),
});
export type InvoiceInput = z.input<typeof invoiceInput>;
export const invoiceReviewInput = z
  .object({ id: uuid, accept: z.boolean(), note: z.string().trim().max(1000).default("") })
  .refine((v) => v.accept || v.note.length >= 3, { path: ["note"], message: "reason" });

export const certificateInput = z.object({
  creatorId: uuid,
  fy: z.string().regex(/^\d{4}-\d{2}$/),
  quarter: z.enum(["Q1", "Q2", "Q3", "Q4"]),
  filePath: z.string().regex(/^form16a\/[0-9a-f-]{36}\/\d{4}-\d{2}-Q[1-4](-[0-9a-f]{8})?\.pdf$/),
});

/** Database messages → finance.errors.* keys (first match wins). */
export const LEDGER_DB_ERRORS: readonly [RegExp, string][] = [
  [/a reason is required/, "reasonRequired"],
  [/amount must be positive/, "amount"],
  [/invalid (deal|creator)/, "invalidTarget"],
  [/this entry cannot be held/, "cannotHold"],
  [/no such manual milestone/, "noMilestone"],
  [/already released/, "alreadyReleased"],
  [/invalid enrolment reference/, "enrolmentRef"],
  [/no such lead/, "noLead"],
  [/nothing to pay/, "nothingToPay"],
  [/KYC is not verified/, "kyc"],
  [/an entry changed since/, "stale"],
  [/do not add up/, "stale"],
  [/only payouts in a draft batch/, "notDraft"],
  [/only a draft batch can be approved/, "notDraft"],
  [/waiting for its GST invoice/, "invoiceMissing"],
  [/a second approver is needed/, "secondApprover"],
  [/must be approved first/, "notApproved"],
  [/has not been sent to the bank can be cancelled/, "cannotCancel"],
  [/no such payout/, "noPayout"],
  [/is not waiting for payment/, "notPending"],
  [/payment date is in the future/, "futureDate"],
  [/does not need an invoice/, "noInvoiceNeeded"],
  [/must match your verified GSTIN/, "gstinMismatch"],
  [/invalid invoice number/, "invoiceNumber"],
  [/invalid invoice date/, "invoiceDate"],
  [/amounts must match/, "invoiceAmounts"],
  [/already submitted for this payout/, "invoiceDuplicate"],
  [/already been decided/, "alreadyDecided"],
  [/invalid file/, "file"],
];
