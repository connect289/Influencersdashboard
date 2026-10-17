"use server";
// Payout actions (Finance): prepare a batch from payable entries with the pure payout builder, remove a payout,
// approve (two-person when configured), cancel, mark paid one by one or from the bank's UTR file, mark failed; review
// GST invoices; record Form 16A certificates. Creators get a signed upload for their GST invoice and submit it.
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { requireCreator, requireStaff } from "@/lib/auth/guards";
import { rupeesToPaise } from "@/lib/creators/schemas";
import { act, ledgerDbFail, refreshFinance } from "@/lib/ledger/act";
import { loadCandidates } from "@/lib/ledger/data";
import {
  certificatePath,
  DOCUMENTS_BUCKET,
  INVOICE_MAX_BYTES,
  INVOICE_TYPES,
  INVOICES_BUCKET,
  invoicePath,
} from "@/lib/ledger/files";
import { preparePayouts } from "@/lib/ledger/prepare";
import {
  batchPrepareInput,
  batchReasonInput,
  certificateInput,
  invoiceInput,
  invoiceReviewInput,
  markPaidInput,
  utrFileInput,
  type BatchPrepareInput,
  type InvoiceInput,
  type MarkPaidInput,
} from "@/lib/ledger/schemas";
import { parseUtrFile } from "@/lib/ledger/utr";
import { istToday } from "@/lib/format";
import { log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";
import { fail, type ActionResult } from "./result";

export async function prepareBatch(input: BatchPrepareInput): Promise<ActionResult<{ id: string; skipped: number }>> {
  return act(batchPrepareInput, input, async (db, v, t) => {
    let c;
    try {
      c = await loadCandidates(db, { creator_ids: v.creatorIds, campaign_id: v.campaignId, due_by: v.dueBy });
    } catch (e) {
      return ledgerDbFail(e instanceof Error ? { message: e.message } : { message: String(e) }, t);
    }
    const { payouts, skipped } = preparePayouts(c.creators, c.rules);
    if (!payouts.length) return fail(t("finance.payouts.nothing", { skipped: skipped.length }));
    const { data, error } = await db.rpc("payout_batch_create", {
      p: {
        note: v.note,
        filters: { creator_ids: v.creatorIds, campaign_id: v.campaignId, due_by: v.dueBy, skipped },
        payouts: payouts.map((p) => ({
          creator_id: p.creator_id,
          gross_paise: p.gross_paise,
          gst_base_paise: p.gst_base_paise,
          gst_paise: p.gst_paise,
          tds_paise: p.tds_paise,
          eduwit_tds_paise: p.eduwit_tds_paise,
          net_paise: p.net_paise,
          needs_invoice: p.needs_invoice,
          sections: p.sections,
          items: p.items,
        })),
      } as never,
    });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return {
      ok: true,
      data: { id: data, skipped: skipped.length },
      message: t("finance.payouts.prepared", { count: payouts.length, skipped: skipped.length }),
    };
  });
}

export async function removePayout(input: z.input<typeof batchReasonInput>): Promise<ActionResult> {
  return act(batchReasonInput, input, async (db, v, t) => {
    const { error } = await db.rpc("payout_remove", { p_payout: v.id, p_reason: v.reason });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return { ok: true, message: t("finance.payouts.removed") };
  });
}

export async function approveBatch(batchId: string): Promise<ActionResult> {
  return act(z.uuid(), batchId, async (db, id, t) => {
    const { data, error } = await db.rpc("payout_batch_approve", { p_batch: id });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return { ok: true, message: t(data === "approved" ? "finance.payouts.approved" : "finance.payouts.firstApproval") };
  });
}

export async function cancelBatch(input: z.input<typeof batchReasonInput>): Promise<ActionResult> {
  return act(batchReasonInput, input, async (db, v, t) => {
    const { error } = await db.rpc("payout_batch_cancel", { p_batch: v.id, p_reason: v.reason });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return { ok: true, message: t("finance.payouts.cancelled") };
  });
}

export async function markPaid(input: MarkPaidInput): Promise<ActionResult> {
  return act(markPaidInput, input, async (db, v, t) => {
    if (v.paidOn > istToday()) return fail(t("finance.errors.futureDate"));
    const { error } = await db.rpc("payouts_mark_paid", {
      p: [{ payout_ref: v.payoutRef, utr: v.utr, paid_on: v.paidOn }] as never,
    });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return { ok: true, message: t("finance.payouts.paid", { count: 1 }) };
  });
}

export async function markPaidFromFile(input: z.input<typeof utrFileInput>): Promise<ActionResult> {
  return act(utrFileInput, input, async (db, v, t) => {
    const { rows, errors } = parseUtrFile(v.text, istToday());
    if (errors.length)
      return fail(
        t("finance.payouts.fileErrors", {
          lines: errors
            .slice(0, 5)
            .map((e) => `${String(e.line)} (${t(`finance.utr.${e.code}`)})`)
            .join(", "),
          count: errors.length,
        }),
      );
    if (!rows.length) return fail(t("finance.payouts.fileEmpty"));
    const { data, error } = await db.rpc("payouts_mark_paid", { p: rows as never });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return { ok: true, message: t("finance.payouts.paid", { count: data }) };
  });
}

export async function markFailed(input: z.input<typeof batchReasonInput>): Promise<ActionResult> {
  return act(batchReasonInput, input, async (db, v, t) => {
    const { error } = await db.rpc("payout_mark_failed", { p_payout: v.id, p_reason: v.reason });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return { ok: true, message: t("finance.payouts.failed") };
  });
}

export async function reviewInvoice(input: z.input<typeof invoiceReviewInput>): Promise<ActionResult> {
  return act(invoiceReviewInput, input, async (db, v, t) => {
    const { error } = await db.rpc("invoice_review", { p_invoice: v.id, p_accept: v.accept, p_note: v.note });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return { ok: true, message: t(v.accept ? "finance.invoices.accepted" : "finance.invoices.rejected") };
  });
}

const uploadRequest = z.object({
  payoutId: z.uuid(),
  fileName: z.string().min(1).max(200),
  type: z.enum(INVOICE_TYPES),
  size: z.number().int().min(1).max(INVOICE_MAX_BYTES),
});

/** A one-time signed upload for the creator's GST invoice (straight to the private bucket). */
export async function invoiceUploadUrl(
  input: z.input<typeof uploadRequest>,
): Promise<ActionResult<{ path: string; token: string }>> {
  const t = await getTranslations();
  const p = uploadRequest.safeParse(input);
  if (!p.success) return fail(t("finance.errors.file"));
  const { supabase, me } = await requireCreator();
  const allowed = await supabase.rpc("invoice_upload_allowed", { p_payout: p.data.payoutId });
  if (allowed.data !== true) return fail(t("errors.forbidden"));
  const { data, error } = await adminClient()
    .storage.from(INVOICES_BUCKET)
    .createSignedUploadUrl(invoicePath(me.creatorId, p.data.payoutId, p.data.fileName));
  if (error) {
    log.error("invoice.sign_failed", { error: error.message });
    return fail(t("errors.generic"));
  }
  return { ok: true, data: { path: data.path, token: data.token } };
}

export async function submitInvoice(input: InvoiceInput): Promise<ActionResult> {
  return act(invoiceInput, input, async (db, v, t) => {
    const { error } = await db.rpc("invoice_submit", {
      p: {
        payout_id: v.payoutId,
        number: v.number,
        issued_on: v.issuedOn,
        gstin: v.gstin,
        taxable_paise: rupeesToPaise(v.taxableRupees),
        gst_paise: rupeesToPaise(v.gstRupees),
        file_path: v.filePath,
      },
    });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return { ok: true, message: t("earnings.invoice.submitted") };
  });
}

const certificateRequest = z.object({
  creatorId: z.uuid(),
  fy: z.string().regex(/^\d{4}-\d{2}$/),
  quarter: z.enum(["Q1", "Q2", "Q3", "Q4"]),
  size: z.number().int().min(1).max(INVOICE_MAX_BYTES),
});

/** A one-time signed upload for a creator's Form 16A (Finance). */
export async function certificateUploadUrl(
  input: z.input<typeof certificateRequest>,
): Promise<ActionResult<{ path: string; token: string }>> {
  const t = await getTranslations();
  const p = certificateRequest.safeParse(input);
  if (!p.success) return fail(t("finance.errors.file"));
  const { me } = await requireStaff();
  if (!me.permissions.has("tax.manage")) return fail(t("errors.forbidden"));
  const { data, error } = await adminClient()
    .storage.from(DOCUMENTS_BUCKET)
    .createSignedUploadUrl(certificatePath(p.data.creatorId, p.data.fy, p.data.quarter));
  if (error) {
    log.error("certificate.sign_failed", { error: error.message });
    return fail(t("errors.generic"));
  }
  return { ok: true, data: { path: data.path, token: data.token } };
}

export async function recordCertificate(input: z.input<typeof certificateInput>): Promise<ActionResult> {
  return act(certificateInput, input, async (db, v, t) => {
    const { error } = await db.rpc("tds_certificate_record", {
      p_creator: v.creatorId,
      p_fy: v.fy,
      p_quarter: v.quarter,
      p_path: v.filePath,
    });
    if (error) return ledgerDbFail(error, t);
    refreshFinance();
    return { ok: true, message: t("finance.tds.recorded") };
  });
}
