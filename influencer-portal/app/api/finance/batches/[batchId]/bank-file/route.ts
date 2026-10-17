import { z } from "zod";
import { readSetting } from "@/lib/settings/read";
import { env } from "@/lib/env";
import { BANK_COLUMNS, type BankRow } from "@/lib/ledger/bank-file";
import { payoutProvider } from "@/lib/ledger/provider";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const rowSchema = z.object({
  beneficiary_name: z.string(),
  account_number: z.string(),
  ifsc: z.string(),
  net_paise: z.number().int(),
  payout_ref: z.string(),
  email: z.string().nullable(),
  creator_code: z.string(),
}) satisfies z.ZodType<BankRow>;

/**
 * The bank bulk-upload file for an approved batch (payout.manage). inf.payout_bank_rows() decrypts the account
 * numbers, audits the export and moves the batch to processing; the provider (lib/ledger/provider.ts, v1: the bank
 * file) builds the file here and it is never stored.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ batchId: string }> }) {
  const { batchId } = await params;
  if (!z.uuid().safeParse(batchId).success) return new Response("Not found", { status: 404 });
  const supabase = await createClient();
  const [rows, batch, s] = await Promise.all([
    supabase.rpc("payout_bank_rows", { p_batch: batchId }),
    supabase.from("payout_batches").select("ref").eq("id", batchId).maybeSingle(),
    readSetting("finance.payouts"),
  ]);
  if (rows.error || !batch.data) return new Response("Not found", { status: 404 });
  const out = payoutProvider(env().PAYOUT_PROVIDER).dispatch(batch.data.ref, z.array(rowSchema).parse(rows.data), {
    delimiter: s.bank_export.delimiter,
    header: s.bank_export.header,
    columns: s.bank_export.columns.filter((c): c is (typeof BANK_COLUMNS)[number] => BANK_COLUMNS.includes(c)),
  });
  if (out.kind !== "file") return new Response("Not found", { status: 404 });
  return new Response(out.body, {
    headers: {
      "Content-Type": out.contentType,
      "Content-Disposition": `attachment; filename="${out.filename}"`,
      "Cache-Control": "no-store",
    },
  });
}
