import { z } from "zod";
import { bankFile, BANK_COLUMNS, type BankRow } from "@/lib/ledger/bank-file";
import { SETTINGS } from "@/lib/settings/registry";
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
 * numbers, audits the export and moves the batch to processing; the file is built here and never stored.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ batchId: string }> }) {
  const { batchId } = await params;
  if (!z.uuid().safeParse(batchId).success) return new Response("Not found", { status: 404 });
  const supabase = await createClient();
  const [rows, batch, setting] = await Promise.all([
    supabase.rpc("payout_bank_rows", { p_batch: batchId }),
    supabase.from("payout_batches").select("ref").eq("id", batchId).maybeSingle(),
    supabase.rpc("setting", { p_key: "finance.payouts" }),
  ]);
  if (rows.error || !batch.data) return new Response("Not found", { status: 404 });
  const s = SETTINGS["finance.payouts"].schema.catch(SETTINGS["finance.payouts"].default).parse(setting.data);
  const body = bankFile(z.array(rowSchema).parse(rows.data), {
    delimiter: s.bank_export.delimiter,
    header: s.bank_export.header,
    columns: s.bank_export.columns.filter((c): c is (typeof BANK_COLUMNS)[number] => BANK_COLUMNS.includes(c)),
  });
  return new Response(body, {
    headers: {
      "Content-Type":
        s.bank_export.delimiter === "\t" ? "text/tab-separated-values; charset=utf-8" : "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${batch.data.ref}.${s.bank_export.delimiter === "\t" ? "tsv" : "csv"}"`,
      "Cache-Control": "no-store",
    },
  });
}
