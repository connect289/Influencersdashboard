"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";
import { statementRows } from "@/lib/statement-csv";

/** Money (spec B11): Admin only for every change; the database checks again (b2c.require('money')). */
const ADMIN = ["admin"] as const;
const id = z.coerce.number().int().positive();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const reason = z.string().trim().min(3, "Give a reason.").max(300);
const done = (...paths: string[]) => { for (const p of ["/w/money", ...paths]) revalidatePath(p); };

async function admin<T>(run: () => Promise<T>, notice?: string, ...paths: string[]): Promise<ActionResult<T>> {
  await assertUser([...ADMIN]);
  const r = await act(run, notice);
  done(...paths);
  return r;
}

// ---------- universities ----------
const RateSchema = z.object({
  university_id: id, programme_id: id.nullable().optional(), rate_type: z.enum(["percent", "fixed", "tiered"]),
  fee_base: z.enum(["first_year", "total", "amount_paid"]).default("first_year"), value: z.coerce.number().min(0).nullable().optional(),
  tiers: z.array(z.object({ from: z.coerce.number().min(0), to: z.coerce.number().positive().nullable().optional(), value: z.coerce.number().min(0) })).nullable().optional(),
  gst_inclusive: z.boolean().default(false), valid_from: day, valid_to: day.nullable().optional(), note: z.string().max(300).nullable().optional(),
});
export async function rateSave(p: z.input<typeof RateSchema>) {
  const v = RateSchema.safeParse(p);
  if (!v.success) return { ok: false as const, error: v.error.issues[0]?.message ?? "Check the rate." };
  return admin(() => rpc<number>("university_rate_save", { p: v.data }), "Rate saved. Bookings from its start date use it.");
}
export async function rateRetire(rate: number, why: string) {
  return admin(() => rpc("university_rate_retire", { p_id: id.parse(rate), p_reason: reason.parse(why) }), "Rate retired.");
}
const BillingSchema = z.object({
  university_id: id, legal_name: z.string().trim().min(2).max(200), gstin: z.string().trim().toUpperCase().regex(/^[0-9]{2}[A-Z0-9]{13}$/, "A GSTIN has 15 characters.").or(z.literal("")),
  state_code: z.string().trim().regex(/^\d{2}$/, "Two digits, e.g. 07.").or(z.literal("")), address: z.string().max(500).optional(), email: z.string().email().or(z.literal("")).optional(),
  payment_terms_days: z.coerce.number().int().min(0).max(180).nullable().optional(), refund_days: z.coerce.number().int().min(0).max(365).nullable().optional(),
});
export async function billingSave(p: z.input<typeof BillingSchema>) {
  const v = BillingSchema.safeParse(p);
  if (!v.success) return { ok: false as const, error: v.error.issues[0]?.message ?? "Check the billing details." };
  return admin(() => rpc("university_billing_save", { p: v.data }), "Billing details saved.");
}
export async function periodClose(university: number, period: string, leads: number | null) {
  return admin(() => rpc<{ tier: unknown; adjustments: number }>("period_close", { p_university: id.parse(university), p_period: day.parse(period), p_leads: leads }), "Period closed; the tier is settled.");
}

// ---------- enrolments ----------
export async function enrollmentLink(enrollment: number, university: number, programme: number | null, feeFirstYear: number | null) {
  return admin(() => rpc("enrollment_link", { p_id: id.parse(enrollment), p_university: id.parse(university), p_programme: programme, p_fee_first_year: feeFirstYear }),
    "Linked to the catalogue and booked.", "/w/enrollments");
}
export async function moneyRebook(enrollment: number, why: string) {
  return admin(() => rpc("money_rebook", { p_id: id.parse(enrollment), p_reason: reason.parse(why) }), "Booked again at today's rates.");
}
export async function enrollmentRefund(enrollment: number, on: string, why: string) {
  return admin(() => rpc<string>("enrollment_refund", { p_id: id.parse(enrollment), p_on: day.parse(on), p_reason: reason.parse(why) }), "Refund recorded.", "/w/enrollments");
}

// ---------- invoices and receipts ----------
export async function invoiceDraft(university: number, upto: string | null, test: boolean) {
  return admin(() => rpc<number>("invoice_draft", { p_university: id.parse(university), p_upto: upto ? day.parse(upto) : null, p_test: test }), "Draft invoice made. Check it, then approve.");
}
export async function invoiceAct(invoice: number, action: "approve" | "discard" | "sent", issue?: string) {
  const i = id.parse(invoice);
  if (action === "approve") return admin(() => rpc("invoice_approve", { p_id: i, p_issue: issue ? day.parse(issue) : null }), "Approved; the number is given.");
  if (action === "discard") return admin(() => rpc("invoice_discard", { p_id: i }), "Draft discarded.");
  return admin(() => rpc("invoice_mark_sent", { p_id: i }), "Marked as sent.");
}
export async function invoiceCancel(invoice: number, why: string) {
  return admin(() => rpc<number>("invoice_cancel", { p_id: id.parse(invoice), p_reason: reason.parse(why) }), "Cancelled; a credit note was raised.");
}
const ReceiptSchema = z.object({
  university_id: id, invoice_id: id.nullable().optional(), amount: z.coerce.number().positive("Enter the amount received."), tds: z.coerce.number().min(0).default(0),
  received_on: day, reference: z.string().trim().min(2, "Enter the UTR or cheque number.").max(100), note: z.string().max(300).optional(),
});
export async function receiptRecord(p: z.input<typeof ReceiptSchema>) {
  const v = ReceiptSchema.safeParse(p);
  if (!v.success) return { ok: false as const, error: v.error.issues[0]?.message ?? "Check the receipt." };
  return admin(() => rpc("receipt_record", { p: v.data }), "Receipt recorded.");
}
export async function statementUpload(university: number, from: string, to: string, fileName: string, csv: string) {
  await assertUser([...ADMIN]);
  if (csv.length > 2_000_000) return { ok: false as const, error: "The file is too large (2 MB at most)." };
  const { rows, missing } = statementRows(csv);
  if (missing.length) return { ok: false as const, error: `The file needs ${missing.join(" and ")}.` };
  const r = await act(() => rpc<number>("statement_import", { p: { university_id: id.parse(university), period_from: day.parse(from), period_to: day.parse(to), file_name: fileName.slice(0, 200), rows } }),
    `${rows.length} rows read and reconciled.`);
  done();
  return r;
}

// ---------- counsellor commission ----------
const RuleSchema = z.object({ rate_type: z.enum(["percent", "fixed"]), fee_base: z.enum(["first_year", "total", "amount_paid"]).default("first_year"), value: z.coerce.number().min(0), reason });
export async function fallbackSave(p: z.input<typeof RuleSchema> & { university_id: number }) {
  const v = RuleSchema.extend({ university_id: id }).safeParse(p);
  if (!v.success) return { ok: false as const, error: v.error.issues[0]?.message ?? "Check the fallback." };
  return admin(() => rpc<number>("commission_fallback_save", { p: v.data }), "Fallback saved; lines waiting for a rate were booked again.");
}
export async function overrideSave(p: z.input<typeof RuleSchema> & { counsellor_id?: string | null; programme_id?: number | null; valid_from: string; valid_to?: string | null }) {
  const v = RuleSchema.extend({ counsellor_id: z.string().uuid().nullable().optional(), programme_id: id.nullable().optional(), valid_from: day, valid_to: day.nullable().optional() })
    .refine((x) => x.counsellor_id || x.programme_id, "Choose a counsellor, a programme or both.").safeParse(p);
  if (!v.success) return { ok: false as const, error: v.error.issues[0]?.message ?? "Check the override." };
  return admin(() => rpc<number>("commission_override_save", { p: v.data }), "Override saved. It applies to bookings from its start date.");
}
export async function overrideRetire(override: number, why: string) {
  return admin(() => rpc("commission_override_retire", { p_id: id.parse(override), p_reason: reason.parse(why) }), "Override retired.");
}
export async function commissionAdjust(enrollment: number, amount: number, why: string) {
  return admin(() => rpc("commission_adjust", { p_enrollment: id.parse(enrollment), p_amount: z.coerce.number().refine((n) => n !== 0).parse(amount), p_reason: reason.parse(why) }), "Adjustment booked.");
}
export async function runPrepare(period: string, test: boolean) {
  return admin(() => rpc<number>("commission_run_prepare", { p_period: day.parse(period), p_test: test }), "Run prepared with every due line.");
}
export async function runAct(run: number, action: "approve" | "cancel", why?: string) {
  const r = id.parse(run);
  if (action === "approve") return admin(() => rpc("commission_run_approve", { p_run: r }), "Approved. Counsellors can download their statements.");
  return admin(() => rpc("commission_run_cancel", { p_run: r, p_reason: reason.parse(why ?? "") }), "Run cancelled; its lines are due again.");
}
export async function runRelease(run: number, line: number, why: string) {
  return admin(() => rpc("commission_run_release", { p_run: id.parse(run), p_line: id.parse(line), p_reason: reason.parse(why) }), "Line held back for the next run.");
}

// ---------- team ----------
const TargetSchema = z.object({
  calls: z.coerce.number().int().min(0).nullable(), connected: z.coerce.number().int().min(0).nullable(), counselled: z.coerce.number().int().min(0).nullable(),
  applications: z.coerce.number().int().min(0).nullable(), enrollments: z.coerce.number().int().min(0).nullable(), commission: z.coerce.number().min(0).nullable(),
});
export async function targetSave(user: string, month: string, p: Record<string, string>) {
  await assertUser(["admin", "sales_head"]);
  const clean = Object.fromEntries(Object.keys(TargetSchema.shape).map((k) => [k, p[k] === "" || p[k] === undefined ? null : p[k]]));
  const v = TargetSchema.safeParse(clean);
  if (!v.success) return { ok: false as const, error: "Targets are whole numbers of zero or more." };
  const r = await act(() => rpc("target_save", { p_user: z.string().uuid().parse(user), p_month: day.parse(month), p: v.data }), "Target saved.");
  revalidatePath("/w/team");
  return r;
}
