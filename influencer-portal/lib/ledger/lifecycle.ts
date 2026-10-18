// Ledger entry lifecycle (spec 11, ERD D-06): accrued → confirmed → payable → in payout batch → paid, plus on hold,
// reversed and clawed back. Amounts never change; the status is derived from an entry's facts (how much is confirmed,
// paid and claimed by an open batch, whether it is held, reversed or itself a reversal, and its due date) and only
// inf.ledger_transition() writes it, logging every change. The database mirrors statusOf() in inf.ledger_status_of();
// supabase/tests/020_ledger_status_matrix.sql is generated from STATUS_CASES so the two cannot drift. Pure.

export const ENTRY_STATUSES = [
  "accrued",
  "confirmed",
  "payable",
  "in_batch",
  "paid",
  "on_hold",
  "reversed",
  "clawed_back",
] as const;
export type EntryStatus = (typeof ENTRY_STATUSES)[number];

/** Every ledger entry type (ERD §7). Engine lines use the earning types; the rest are posted by people or payouts. */
export const LEDGER_TYPES = [
  "fixed_fee",
  "milestone",
  "commission",
  "bonus",
  "usage_fee",
  "exclusivity_fee",
  "reimbursement",
  "penalty",
  "clawback",
  "adjustment",
  "reversal",
  "tds",
  "gst",
  "payout",
] as const;
export type LedgerType = (typeof LEDGER_TYPES)[number];

/** Types that settle a payout; they are paid when posted and never enter a batch. */
export const SETTLEMENT_TYPES: readonly LedgerType[] = ["tds", "gst", "payout"];

export interface EntryState {
  /** Whole amount (never changes). */
  amount_paise: number;
  /** How much is confirmed (only grows). For a reversal entry: the amount to recover (what was already paid). */
  confirmed_paise: number;
  /** Settled through payouts so far. */
  paid_paise: number;
  /** Claimed by a payout in a batch that is not paid, failed or cancelled. */
  in_open_batch: boolean;
  held: boolean;
  /** Cancelled by a reversal entry. */
  reversed: boolean;
  is_reversal: boolean;
  /** IST date the confirmed amount becomes payable. */
  due_on: string;
}

export function statusOf(e: EntryState, today: string): EntryStatus {
  if (e.is_reversal) {
    if (e.confirmed_paise === 0) return "reversed";
    if (e.paid_paise >= e.confirmed_paise) return "paid";
    if (e.in_open_batch) return "in_batch";
    if (e.held) return "on_hold";
    return "payable";
  }
  if (e.reversed) return e.paid_paise > 0 ? "clawed_back" : "reversed";
  if (e.amount_paise > 0 && e.paid_paise >= e.amount_paise) return "paid";
  if (e.in_open_batch) return "in_batch";
  if (e.held) return "on_hold";
  if (e.confirmed_paise > e.paid_paise && e.due_on <= today) return "payable";
  if (e.confirmed_paise >= e.amount_paise) return "confirmed";
  return "accrued";
}

/** What a payout may still take from an entry (signed by the caller with the entry's direction). */
export function remainingPayable(e: EntryState, today: string): number {
  const s = statusOf(e, today);
  if (s !== "payable") return 0;
  return Math.max(e.confirmed_paise - e.paid_paise, 0);
}

/**
 * Status changes that can happen (the database refuses any other). Confirmation only grows and payouts only take
 * payable amounts, so an entry moves forward; holds come and go on open entries; a batch that is cancelled or a
 * payout the bank returns puts entries back. Reversed and clawed back are final. An entry claimed by an open batch is
 * never reversed: the runner waits until the batch is settled.
 */
export const ALLOWED_TRANSITIONS: Readonly<Record<EntryStatus, readonly EntryStatus[]>> = {
  accrued: ["confirmed", "payable", "on_hold", "reversed", "clawed_back"],
  confirmed: ["payable", "on_hold", "reversed", "clawed_back"],
  payable: ["in_batch", "on_hold", "reversed", "clawed_back"],
  in_batch: ["paid", "accrued", "confirmed", "payable", "on_hold"],
  paid: ["clawed_back", "payable"],
  on_hold: ["accrued", "confirmed", "payable", "reversed", "clawed_back"],
  reversed: [],
  clawed_back: [],
};

export function canTransition(from: EntryStatus, to: EntryStatus): boolean {
  return from === to || ALLOWED_TRANSITIONS[from].includes(to);
}

const base: EntryState = {
  amount_paise: 10_000,
  confirmed_paise: 0,
  paid_paise: 0,
  in_open_batch: false,
  held: false,
  reversed: false,
  is_reversal: false,
  due_on: "2026-11-10",
};

/** Cases shared by the unit test and the generated database test (today is 2026-11-15). */
export const STATUS_CASES: readonly { name: string; state: EntryState; status: EntryStatus }[] = [
  { name: "nothing confirmed", state: base, status: "accrued" },
  { name: "partly confirmed, due", state: { ...base, confirmed_paise: 4_000 }, status: "payable" },
  {
    name: "fully confirmed, not yet due",
    state: { ...base, confirmed_paise: 10_000, due_on: "2026-12-01" },
    status: "confirmed",
  },
  { name: "fully confirmed and due", state: { ...base, confirmed_paise: 10_000 }, status: "payable" },
  { name: "due today", state: { ...base, confirmed_paise: 10_000, due_on: "2026-11-15" }, status: "payable" },
  {
    name: "claimed by an open batch",
    state: { ...base, confirmed_paise: 10_000, in_open_batch: true },
    status: "in_batch",
  },
  { name: "paid in full", state: { ...base, confirmed_paise: 10_000, paid_paise: 10_000 }, status: "paid" },
  {
    name: "partly paid, rest unconfirmed",
    state: { ...base, confirmed_paise: 4_000, paid_paise: 4_000 },
    status: "accrued",
  },
  {
    name: "partly paid, more confirmed",
    state: { ...base, confirmed_paise: 7_000, paid_paise: 4_000 },
    status: "payable",
  },
  { name: "held", state: { ...base, confirmed_paise: 10_000, held: true }, status: "on_hold" },
  {
    name: "held but already in a batch",
    state: { ...base, confirmed_paise: 10_000, held: true, in_open_batch: true },
    status: "in_batch",
  },
  { name: "reversed before payment", state: { ...base, confirmed_paise: 10_000, reversed: true }, status: "reversed" },
  {
    name: "reversed after payment",
    state: { ...base, confirmed_paise: 10_000, paid_paise: 10_000, reversed: true },
    status: "clawed_back",
  },
  {
    name: "reversal of an unpaid entry",
    state: { ...base, is_reversal: true, confirmed_paise: 0 },
    status: "reversed",
  },
  {
    name: "reversal to recover",
    state: { ...base, is_reversal: true, confirmed_paise: 6_000 },
    status: "payable",
  },
  {
    name: "reversal being recovered",
    state: { ...base, is_reversal: true, confirmed_paise: 6_000, in_open_batch: true },
    status: "in_batch",
  },
  {
    name: "reversal recovered",
    state: { ...base, is_reversal: true, confirmed_paise: 6_000, paid_paise: 6_000 },
    status: "paid",
  },
  {
    name: "reversal held",
    state: { ...base, is_reversal: true, confirmed_paise: 6_000, held: true },
    status: "on_hold",
  },
  { name: "zero amount", state: { ...base, amount_paise: 0 }, status: "confirmed" },
];
export const STATUS_TODAY = "2026-11-15";
