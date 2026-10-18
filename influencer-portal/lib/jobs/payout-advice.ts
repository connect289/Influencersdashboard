import "server-only";
import { z } from "zod";
import { loadPayout } from "@/lib/ledger/data";
import { advicePath, DOCUMENTS_BUCKET } from "@/lib/ledger/files";
import { renderAdvicePdf } from "@/lib/ledger/pdf";
import { financePdfLabels } from "@/lib/ledger/pdf-labels";
import { adminClient } from "@/lib/supabase/admin";
import { PermanentJobError, type JobHandler } from "./types";

const payloadSchema = z.object({ payout_id: z.uuid() });

/**
 * Builds the payment advice PDF for a paid payout (enqueued by inf.payouts_mark_paid), stores it in inf-documents and
 * records its path. Idempotent: a payout that already has its advice is left alone.
 */
export const payoutAdvice: JobHandler = async (job) => {
  const { payout_id } = payloadSchema.parse(job.payload);
  const db = adminClient();
  const p = await loadPayout(db, payout_id);
  if (!p) throw new PermanentJobError("no such payout");
  if (p.status !== "paid" || p.advice_path) return;
  const pdf = await renderAdvicePdf(p, await financePdfLabels());
  const path = advicePath(p.creator_id, p.ref);
  const up = await db.storage
    .from(DOCUMENTS_BUCKET)
    .upload(path, pdf, { contentType: "application/pdf", upsert: true });
  if (up.error) throw new Error(up.error.message);
  const { error } = await db.rpc("payout_advice_saved", { p_payout: payout_id, p_path: path });
  if (error) throw new Error(error.message);
};
