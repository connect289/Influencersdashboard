"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { GSTIN_RE } from "@/lib/money";
import { createClient } from "@/lib/supabase/server";

type Result<T = null> = { ok: true; data: T } | { ok: false; error: string };
const Id = z.number().int().positive();
const Day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).or(z.literal(""));
const Money = z.string().trim().regex(/^-?\d+(\.\d{1,2})?$/, "An amount in rupees").or(z.literal(""));

/** Messages raised by the b2b functions for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}

async function call<T = null>(fn: string, args: Record<string, unknown>, fallback: string): Promise<Result<T>> {
  await assertAdmin();
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) return { ok: false, error: dbMessage(error, fallback) };
  revalidatePath("/money", "layout");
  return { ok: true, data: data as T };
}
const bad = (error: string): Result<never> => ({ ok: false, error });

// ---------- enrollments ----------
const VerifySchema = z.object({
  proof_type: z.enum(["statement_line", "university_confirmation", "fee_receipt"]),
  proof_ref: z.string().trim().min(1, "Describe the proof").max(300),
  proof_url: z.string().trim().max(500).refine((v) => !v || /^https:\/\//.test(v), "A link starting with https://"),
  fee_amount_inr: Money, fee_paid_inr: Money, enrolled_on: Day,
});
export type VerifyForm = z.input<typeof VerifySchema>;
export async function verifyEnrollment(id: number, f: VerifyForm) {
  const p = VerifySchema.safeParse(f);
  if (!Id.safeParse(id).success || !p.success) return bad(p.error?.issues[0]?.message ?? "Check the fields.");
  return call<{ amounts: { net: number; gross: number } }>("enrollment_verify", { p_id: id, p: p.data }, "Could not verify. Try again.");
}

export async function cancelEnrollment(id: number, reason: string) {
  if (!Id.safeParse(id).success || !reason.trim()) return bad("Give a reason.");
  return call("enrollment_cancel", { p_id: id, p_reason: reason.trim().slice(0, 300) }, "Could not cancel. Try again.");
}

const RefundSchema = z.object({ refunded_on: Day, reason: z.string().trim().min(1, "Give a reason").max(300), outside_window: z.boolean() });
export type RefundForm = z.input<typeof RefundSchema>;
export async function refundEnrollment(id: number, f: RefundForm) {
  const p = RefundSchema.safeParse(f);
  if (!Id.safeParse(id).success || !p.success) return bad(p.error?.issues[0]?.message ?? "Check the fields.");
  return call<{ reversed_net_inr: number }>("enrollment_refund", { p_id: id, p: p.data }, "Could not record the refund. Try again.");
}

const AddSchema = z.object({
  reference: z.string().trim().regex(/^[A-Za-z]{2,6}-?\d{1,12}$/, "An Eduwit reference such as EDW-5502"),
  enrolled_on: Day, fee_amount_inr: Money, fee_paid_inr: Money, proof_ref: z.string().trim().max(300),
});
export type AddEnrollmentForm = z.input<typeof AddSchema>;
export async function addEnrollment(f: AddEnrollmentForm) {
  const p = AddSchema.safeParse(f);
  if (!p.success) return bad(p.error.issues[0]?.message ?? "Check the fields.");
  return call<{ id: number; existing: boolean }>("money_enrollment_add", { p: p.data }, "Could not record the enrolment. Try again.");
}

const AdjustSchema = z.object({ partner_id: z.number().int().positive(), enrollment_id: z.string().regex(/^\d*$/), net_inr: Money, note: z.string().trim().min(1, "Say what was agreed").max(300) });
export type AdjustForm = z.input<typeof AdjustSchema>;
export async function addAdjustment(f: AdjustForm) {
  const p = AdjustSchema.safeParse(f);
  if (!p.success || !p.data.net_inr || Number(p.data.net_inr) === 0) return bad(p.success ? "Enter a non-zero amount." : p.error.issues[0]?.message ?? "Check the fields.");
  return call<number>("earning_manual", { p: p.data }, "Could not record the adjustment. Try again.");
}

// ---------- months and invoices ----------
export async function closeMonth(period: string) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(period)) return bad("Choose a month.");
  return call<{ partners_settled: number; tier_adjustments: number; drafts: number }>("money_period_close", { p_period: period }, "Could not close the month. Try again.");
}
export async function approveInvoice(id: number) {
  if (!Id.safeParse(id).success) return bad("Invalid invoice.");
  return call<{ number: string }>("invoice_approve", { p_id: id }, "Could not approve. Try again.");
}
export async function markInvoiceSent(id: number) {
  if (!Id.safeParse(id).success) return bad("Invalid invoice.");
  return call("invoice_mark_sent", { p_id: id }, "Could not update. Try again.");
}
export async function cancelInvoice(id: number, reason: string) {
  if (!Id.safeParse(id).success || !reason.trim()) return bad("Give a reason.");
  return call("invoice_cancel", { p_id: id, p_reason: reason.trim().slice(0, 300) }, "Could not cancel. Try again.");
}

// ---------- receipts ----------
const ReceiptSchema = z.object({
  partner_id: z.number().int().positive("Choose a partner"), received_on: Day, amount_inr: Money.refine((v) => Number(v) > 0, "Enter the amount received"),
  tds_inr: Money, bank_ref: z.string().trim().max(80), note: z.string().trim().max(300), invoice_id: z.string().regex(/^\d*$/),
});
export type ReceiptForm = z.input<typeof ReceiptSchema>;
export async function recordReceipt(f: ReceiptForm) {
  const p = ReceiptSchema.safeParse(f);
  if (!p.success) return bad(p.error.issues[0]?.message ?? "Check the fields.");
  return call<{ id: number; applied_inr: number; unapplied_inr: number }>("receipt_record", { p: p.data }, "Could not record the receipt. Try again.");
}
export async function applyReceipt(receiptId: number, invoiceId: number) {
  if (!Id.safeParse(receiptId).success || !Id.safeParse(invoiceId).success) return bad("Choose an invoice.");
  return call<number>("receipt_allocate", { p_receipt_id: receiptId, p_invoice_id: invoiceId }, "Could not apply the receipt. Try again.");
}
export async function voidReceipt(id: number, reason: string) {
  if (!Id.safeParse(id).success || !reason.trim()) return bad("Give a reason.");
  return call("receipt_void", { p_id: id, p_reason: reason.trim().slice(0, 300) }, "Could not void the receipt. Try again.");
}

// ---------- statements ----------
const StatementRowSchema = z.object({
  reference: z.string().max(60).nullable(), record_id: z.string().max(80).nullable(), phone: z.string().max(30).nullable(), name: z.string().max(120).nullable(),
  programme: z.string().max(200).nullable(), enrolled_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(), amount_inr: z.string().max(30).nullable(),
  raw: z.record(z.string().max(80), z.string().max(500)),
});
const ImportSchema = z.object({
  partner_id: z.number().int().positive("Choose a partner"), period_from: Day.refine(Boolean, "Give the period"), period_to: Day.refine(Boolean, "Give the period"),
  file_name: z.string().max(200), rows: z.array(StatementRowSchema).min(1, "No usable rows").max(5000, "At most 5,000 rows"),
});
export type ImportForm = z.input<typeof ImportSchema>;
export async function importStatement(f: ImportForm) {
  const p = ImportSchema.safeParse(f);
  if (!p.success) return bad(p.error.issues[0]?.message ?? "Check the file.");
  return call<{ statement: { id: number } }>("statement_import", { p: p.data }, "Could not import the statement. Try again.");
}
export async function resolveLine(lineId: number, action: "verify" | "record" | "dismiss", note: string) {
  if (!Id.safeParse(lineId).success || !["verify", "record", "dismiss"].includes(action)) return bad("Unknown action.");
  return call("statement_resolve", { p_line_id: lineId, p_action: action, p_note: note.trim().slice(0, 300) || null }, "Could not update the line. Try again.");
}
export async function verifyMatched(statementId: number) {
  if (!Id.safeParse(statementId).success) return bad("Invalid statement.");
  return call<{ verified: number; errors: { line_id: number; error: string }[] }>("statement_verify_matched", { p_statement_id: statementId }, "Could not verify. Try again.");
}

// ---------- settings, billing, exports ----------
const SettingsSchema = z.object({
  gst_pct: z.coerce.number().min(0).max(28), sac_code: z.string().trim().regex(/^(\d{4,8})?$/, "The SAC code is 4 to 8 digits"),
  tds_pct: z.string().trim().regex(/^(\d{1,2}(\.\d{1,2})?)?$/, "TDS as a percentage"), refund_window_days: z.coerce.number().int().min(0).max(365),
  invoice_prefix: z.string().trim().regex(/^[A-Z0-9-]{1,10}$/, "1 to 10 capital letters, digits or dashes"), tier_min_leads: z.coerce.number().int().min(1).max(1000),
  close_day: z.coerce.number().int().min(1).max(28), auto_close: z.boolean(), confirmed_by_ca: z.boolean(),
  eduwit: z.object({
    legal_name: z.string().trim().max(200), gstin: z.string().trim().toUpperCase().refine((v) => !v || GSTIN_RE.test(v), "The GSTIN must be 15 characters"),
    address: z.string().trim().max(500), state_code: z.string().trim().regex(/^(\d{2})?$/, "Two digits, e.g. 07 for Delhi"), bank: z.string().trim().max(300),
  }),
  reason: z.string().trim().min(3, "Say why you are changing the money settings").max(300),
});
export type MoneySettingsForm = z.input<typeof SettingsSchema>;
export async function saveMoneySettings(f: MoneySettingsForm) {
  const p = SettingsSchema.safeParse(f);
  if (!p.success) return bad(p.error.issues[0]?.message ?? "Check the fields.");
  const { gst_pct, tds_pct, reason, ...rest } = p.data;
  return call("money_settings_save", { p: { ...rest, gst_rate: gst_pct / 100, tds_rate: tds_pct ? Number(tds_pct) / 100 : null }, p_reason: reason },
              "Could not save the settings. Try again.");
}

const BillingSchema = z.object({
  legal_name: z.string().trim().max(200), gstin: z.string().trim().toUpperCase().refine((v) => !v || GSTIN_RE.test(v), "The GSTIN must be 15 characters"),
  billing_address: z.string().trim().max(500), billing_state_code: z.string().trim().regex(/^(\d{2})?$/, "Two digits"),
  billing_email: z.string().trim().max(200).refine((v) => !v || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v), "An email address"),
  payment_terms_days: z.coerce.number().int().min(0).max(180),
});
export type BillingForm = z.input<typeof BillingSchema>;
export async function saveBilling(partnerId: number, f: BillingForm) {
  const p = BillingSchema.safeParse(f);
  if (!Id.safeParse(partnerId).success || !p.success) return bad(p.error?.issues[0]?.message ?? "Check the fields.");
  return call("partner_billing_save", { p_partner_id: partnerId, p: p.data }, "Could not save the billing details. Try again.");
}

export async function exportRows(kind: "invoices" | "receipts" | "earnings", from: string, to: string) {
  if (!["invoices", "receipts", "earnings"].includes(kind) || !Day.safeParse(from).success || !Day.safeParse(to).success || !from || !to) return bad("Choose the dates.");
  return call<Record<string, unknown>[]>("money_export", { p_kind: kind, p_from: from, p_to: to }, "Could not export. Try again.");
}
