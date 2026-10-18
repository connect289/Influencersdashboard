// Payment-provider adapter (spec 11). v1 moves no money: the only provider hands Finance a bank bulk-upload file and
// payouts are marked paid with the bank's UTR. A payout API (for example RazorpayX) is added later as another
// provider that submits the batch and reports each payout's result, which then goes through the same
// inf.payouts_mark_paid / inf.payout_mark_failed functions. Pure.
import { bankFile, type BankFormat, type BankRow } from "./bank-file";

export type Dispatch =
  /** Finance uploads this file to the bank and marks payouts paid from the bank's response. */
  | { kind: "file"; filename: string; contentType: string; body: string }
  /** The provider accepted the batch; results arrive later (webhook or polling) with one reference per payout. */
  | { kind: "submitted"; providerRef: string };

export interface PayoutProvider {
  id: string;
  /** Whether dispatching actually sends money (never true in v1). */
  movesMoney: boolean;
  dispatch(batchRef: string, rows: readonly BankRow[], format: BankFormat): Dispatch;
}

export const bankFileProvider: PayoutProvider = {
  id: "bank_file",
  movesMoney: false,
  dispatch(batchRef, rows, format) {
    const tsv = format.delimiter === "\t";
    return {
      kind: "file",
      filename: `${batchRef}.${tsv ? "tsv" : "csv"}`,
      contentType: tsv ? "text/tab-separated-values; charset=utf-8" : "text/csv; charset=utf-8",
      body: bankFile(rows, format),
    };
  },
};

const PROVIDERS: Readonly<Record<string, PayoutProvider>> = { [bankFileProvider.id]: bankFileProvider };

/** The configured provider (`PAYOUT_PROVIDER`, default and only v1 value `bank_file`). Unknown ids are refused. */
export function payoutProvider(id = "bank_file"): PayoutProvider {
  const p = PROVIDERS[id || "bank_file"];
  if (!p) throw new Error(`unknown payout provider: ${id}`);
  return p;
}
