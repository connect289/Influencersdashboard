// The bank bulk-upload file for a payout batch (spec 11), in the column order and delimiter Finance configured
// (Settings → Finance → Payouts). Rows come from the audited inf.payout_bank_rows(), the only place account numbers are
// decrypted; the file is generated on request and never stored. Pure.
import { toDelimited } from "@/lib/csv";

export const BANK_COLUMNS = [
  "beneficiary_name",
  "account_number",
  "ifsc",
  "amount_inr",
  "narration",
  "payout_ref",
  "email",
  "creator_code",
] as const;
export type BankColumn = (typeof BANK_COLUMNS)[number];

export interface BankFormat {
  delimiter: "," | ";" | "|" | "\t";
  header: boolean;
  columns: readonly BankColumn[];
}

export interface BankRow {
  beneficiary_name: string;
  account_number: string;
  ifsc: string;
  net_paise: number;
  payout_ref: string;
  email: string | null;
  creator_code: string;
}

const HEADERS: Record<BankColumn, string> = {
  beneficiary_name: "Beneficiary name",
  account_number: "Account number",
  ifsc: "IFSC",
  amount_inr: "Amount",
  narration: "Narration",
  payout_ref: "Reference",
  email: "Email",
  creator_code: "Creator code",
};

/** Rupees with exactly two decimals and no grouping, as banks expect ("12345.50"). */
export function rupeesPlain(paise: number): string {
  if (!Number.isSafeInteger(paise) || paise < 0) throw new Error("amount must be whole, non-negative paise");
  return `${String(Math.floor(paise / 100))}.${String(paise % 100).padStart(2, "0")}`;
}

/** Narration banks accept: letters, digits and spaces, at most 30 characters. */
export function narration(ref: string): string {
  return `Eduwit payout ${ref}`
    .replace(/[^A-Za-z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 30);
}

function value(r: BankRow, c: BankColumn): string {
  switch (c) {
    case "beneficiary_name":
      return r.beneficiary_name
        .replace(/[^A-Za-z0-9 .&-]/g, " ")
        .replace(/\s+/g, " ")
        .trim();
    case "account_number":
      return r.account_number;
    case "ifsc":
      return r.ifsc.toUpperCase();
    case "amount_inr":
      return rupeesPlain(r.net_paise);
    case "narration":
      return narration(r.payout_ref);
    case "payout_ref":
      return r.payout_ref;
    case "email":
      return r.email ?? "";
    case "creator_code":
      return r.creator_code;
  }
}

export function bankFile(rows: readonly BankRow[], format: BankFormat): string {
  if (rows.some((r) => r.net_paise <= 0)) throw new Error("every bank row needs a positive amount");
  return toDelimited(
    format.header ? format.columns.map((c) => HEADERS[c]) : null,
    rows.map((r) => format.columns.map((c) => value(r, c))),
    format.delimiter,
  );
}
