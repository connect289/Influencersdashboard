// A creator's earnings view (spec 11): totals for lifetime, this FY and this month, and what is pending, confirmed,
// payable and paid; the next expected payout date; and the monthly statement (opening balance, entries, closing
// balance). Pure; the loaders pass the creator's ledger entries.
import { financialYear } from "@/lib/format";
import { SETTLEMENT_TYPES, type EntryStatus, type LedgerType } from "./lifecycle";

export interface EarningEntry {
  type: LedgerType;
  direction: "credit" | "debit";
  amount_paise: number;
  confirmed_paise: number;
  paid_paise: number;
  status: EntryStatus;
  /** IST month the entry belongs to (YYYY-MM). */
  period: string;
  /** When it was posted (ISO). */
  posted_at: string;
}

export interface EarningTotals {
  lifetime_paise: number;
  fy_paise: number;
  month_paise: number;
  /** Earned but not yet confirmed. */
  pending_paise: number;
  /** Confirmed, not yet due. */
  confirmed_paise: number;
  /** Due, or in a payout batch being paid. */
  payable_paise: number;
  /** Settled through payouts (before TDS). */
  paid_paise: number;
}

const sign = (e: Pick<EarningEntry, "direction">) => (e.direction === "credit" ? 1 : -1);
const isEarning = (e: Pick<EarningEntry, "type">) => !SETTLEMENT_TYPES.includes(e.type);

/** IST month of a date (YYYY-MM-DD or YYYY-MM) → the FY label it falls in, e.g. "2026-27". */
const fyOfMonth = (month: string) => financialYear(`${month.slice(0, 7)}-15T00:00:00+05:30`);

export function earningTotals(entries: readonly EarningEntry[], today: string): EarningTotals {
  const month = today.slice(0, 7);
  const fy = fyOfMonth(month);
  const t: EarningTotals = {
    lifetime_paise: 0,
    fy_paise: 0,
    month_paise: 0,
    pending_paise: 0,
    confirmed_paise: 0,
    payable_paise: 0,
    paid_paise: 0,
  };
  for (const e of entries.filter(isEarning)) {
    const s = sign(e);
    t.lifetime_paise += s * e.amount_paise;
    if (fyOfMonth(e.period) === fy) t.fy_paise += s * e.amount_paise;
    if (e.period === month) t.month_paise += s * e.amount_paise;
    t.paid_paise += s * e.paid_paise;
    if (e.type === "reversal" || e.status === "reversed" || e.status === "clawed_back") continue;
    const open = Math.max(e.amount_paise - e.confirmed_paise, 0);
    const unpaidConfirmed = Math.max(e.confirmed_paise - e.paid_paise, 0);
    t.pending_paise += s * open;
    if (e.status === "payable" || e.status === "in_batch") t.payable_paise += s * unpaidConfirmed;
    else t.confirmed_paise += s * unpaidConfirmed;
  }
  // Recoveries of paid amounts (reversal entries still to recover) reduce what is payable.
  for (const e of entries.filter((x) => x.type === "reversal" && (x.status === "payable" || x.status === "in_batch")))
    t.payable_paise += sign(e) * Math.max(e.confirmed_paise - e.paid_paise, 0);
  return t;
}

export type PayoutCycle = "weekly" | "fortnightly" | "monthly";

const addDays = (d: string, n: number) =>
  new Date(Date.parse(`${d}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);

/**
 * The next payout run on or after `today` (IST dates): monthly on the payout day; fortnightly on the payout day and
 * fourteen days later; weekly on Mondays.
 */
export function nextPayoutDate(cycle: PayoutCycle, payoutDay: number, today: string): string {
  if (cycle === "weekly") {
    const dow = new Date(`${today}T00:00:00Z`).getUTCDay();
    return addDays(today, (8 - dow) % 7);
  }
  const days = cycle === "monthly" ? [payoutDay] : [payoutDay, payoutDay + 14];
  const [y, m] = today.split("-").map(Number) as [number, number];
  for (let k = 0; k < 3; k++) {
    const ym = new Date(Date.UTC(y, m - 1 + k, 1));
    const last = new Date(Date.UTC(ym.getUTCFullYear(), ym.getUTCMonth() + 1, 0)).getUTCDate();
    for (const d of days) {
      const date = new Date(Date.UTC(ym.getUTCFullYear(), ym.getUTCMonth(), Math.min(d, last)))
        .toISOString()
        .slice(0, 10);
      if (date >= today) return date;
    }
  }
  throw new Error("no payout date found");
}

export interface StatementLine {
  posted_at: string;
  type: LedgerType;
  /** Signed: what the creator is owed goes up (credit) or down (debit). */
  amount_paise: number;
  label: string;
}

export interface Statement {
  month: string;
  opening_paise: number;
  lines: StatementLine[];
  closing_paise: number;
  earned_paise: number;
  tds_paise: number;
  gst_paise: number;
  paid_out_paise: number;
}

/**
 * A month's statement. The balance is what Eduwit owes the creator: earnings (including unconfirmed ones) plus GST,
 * less TDS withheld and payouts made. Months are IST calendar months of posting.
 */
export function monthStatement(entries: readonly (EarningEntry & { label: string })[], month: string): Statement {
  const ist = (iso: string) => new Date(Date.parse(iso) + 330 * 60_000).toISOString().slice(0, 7);
  let opening = 0;
  const lines: StatementLine[] = [];
  for (const e of [...entries].sort((a, b) => a.posted_at.localeCompare(b.posted_at))) {
    const m = ist(e.posted_at);
    const amount = sign(e) * e.amount_paise;
    if (m < month) opening += amount;
    else if (m === month) lines.push({ posted_at: e.posted_at, type: e.type, amount_paise: amount, label: e.label });
  }
  const of = (types: readonly LedgerType[]) =>
    lines.filter((l) => types.includes(l.type)).reduce((s, l) => s + l.amount_paise, 0);
  return {
    month,
    opening_paise: opening,
    lines,
    closing_paise: opening + lines.reduce((s, l) => s + l.amount_paise, 0),
    earned_paise: lines.filter((l) => !SETTLEMENT_TYPES.includes(l.type)).reduce((s, l) => s + l.amount_paise, 0),
    tds_paise: -of(["tds"]),
    gst_paise: of(["gst"]),
    paid_out_paise: -of(["payout"]),
  };
}
