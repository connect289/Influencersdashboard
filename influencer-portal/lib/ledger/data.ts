import "server-only";
// Loaders for the ledger, payouts, invoices, TDS and earnings. Staff read through inf.* list functions (each checks
// its permission); creators and agencies with the earnings grant read inf.creator_earnings().
import { z } from "zod";
import { TDS_COMPONENTS } from "@/lib/compensation/tax";
import type { Db } from "@/lib/contracts/data";
import { ENTRY_STATUSES, LEDGER_TYPES } from "./lifecycle";

const ts = z.string();
const status = z.enum(ENTRY_STATUSES);
const type = z.enum(LEDGER_TYPES);
const direction = z.enum(["credit", "debit"]);
const paise = z.number().int();

export const ledgerRow = z.object({
  id: z.number().int(),
  creator_id: z.uuid(),
  creator_name: z.string(),
  deal_id: z.uuid().nullable(),
  deal_title: z.string().nullable(),
  type,
  direction,
  amount_paise: paise,
  confirmed_paise: paise,
  paid_paise: paise,
  status,
  source: z.enum(["engine", "penalty", "revision_fee", "adjustment", "reversal", "payout"]),
  period: z.string(),
  due_on: z.string(),
  note: z.string().nullable(),
  held: z.boolean(),
  hold_reason: z.string().nullable(),
  posted_at: ts,
  reverses_id: z.number().int().nullable(),
  reversed_by_id: z.number().int().nullable(),
});
export type LedgerRow = z.infer<typeof ledgerRow>;

export const LEDGER_FILTER_KEYS = ["creator_id", "deal_id", "status", "type", "period", "q", "page"] as const;
export const ledgerFilters = z.object({
  creator_id: z.uuid().nullable().catch(null),
  deal_id: z.uuid().nullable().catch(null),
  status: status.nullable().catch(null),
  type: type.nullable().catch(null),
  period: z
    .string()
    .regex(/^\d{4}-\d{2}$/)
    .nullable()
    .catch(null),
  q: z.string().trim().max(60).nullable().catch(null),
  page: z.coerce.number().int().min(1).max(10_000).catch(1),
});
export type LedgerFilters = z.infer<typeof ledgerFilters>;

export function parseLedgerFilters(sp: Record<string, string | undefined>): LedgerFilters {
  return ledgerFilters.parse(Object.fromEntries(LEDGER_FILTER_KEYS.map((k) => [k, sp[k] || null])));
}

export async function listLedger(db: Db, f: LedgerFilters): Promise<{ total: number; rows: LedgerRow[] }> {
  const { data, error } = await db.rpc("ledger_list", {
    p: {
      creator_id: f.creator_id ?? "",
      deal_id: f.deal_id ?? "",
      status: f.status ?? "",
      type: f.type ?? "",
      period: f.period ?? "",
      q: f.q ?? "",
      page: f.page,
    },
  });
  if (error) throw new Error(error.message);
  return z.object({ total: z.number(), rows: z.array(ledgerRow) }).parse(data);
}

export const statusEvent = z.object({
  from: status.nullable(),
  to: status,
  reason: z.string().nullable(),
  at: ts,
  actor: z.string().nullable(),
});
export async function loadEntryEvents(db: Db, entryId: number) {
  const { data, error } = await db.rpc("ledger_entry_events", { p_entry: entryId });
  if (error) throw new Error(error.message);
  return z.array(statusEvent).parse(data);
}

// ---------------------------------------------------------------------------------------------------------------
// Payouts
// ---------------------------------------------------------------------------------------------------------------
export const BATCH_STATUSES = ["draft", "approved", "processing", "paid", "cancelled"] as const;
export const PAYOUT_STATUSES = ["pending", "paid", "failed", "removed", "cancelled"] as const;

export const batchRow = z.object({
  id: z.uuid(),
  ref: z.string(),
  status: z.enum(BATCH_STATUSES),
  created_at: ts,
  note: z.string().nullable(),
  approvals: z.number().int(),
  payouts: z.number().int(),
  net_paise: paise,
  paid: z.number().int(),
});
export type BatchRow = z.infer<typeof batchRow>;

export async function loadBatches(db: Db): Promise<BatchRow[]> {
  const { data, error } = await db.rpc("payout_batches_list");
  if (error) throw new Error(error.message);
  return z.array(batchRow).parse(data);
}

export const batchPayout = z.object({
  id: z.uuid(),
  ref: z.string(),
  creator_id: z.uuid(),
  creator_name: z.string(),
  status: z.enum(PAYOUT_STATUSES),
  gross_paise: paise,
  gst_paise: paise,
  tds_paise: paise,
  net_paise: paise,
  needs_invoice: z.boolean(),
  utr: z.string().nullable(),
  paid_on: z.string().nullable(),
  status_reason: z.string().nullable(),
  items: z.number().int(),
  invoice_status: z.enum(["submitted", "accepted", "rejected"]).nullable(),
});
export const batchDetail = z.object({
  id: z.uuid(),
  ref: z.string(),
  status: z.enum(BATCH_STATUSES),
  note: z.string().nullable(),
  created_at: ts,
  created_by: z.string().nullable(),
  approved_by: z.string().nullable(),
  approved_at: ts.nullable(),
  approved_by_me: z.boolean().nullable(),
  second_approved_by: z.string().nullable(),
  second_approved_at: ts.nullable(),
  exported_at: ts.nullable(),
  export_count: z.number().int(),
  cancelled_reason: z.string().nullable(),
  two_person: z.boolean(),
  payouts: z.array(batchPayout),
});
export type BatchDetail = z.infer<typeof batchDetail>;

export async function loadBatch(db: Db, batchId: string): Promise<BatchDetail | null> {
  const { data, error } = await db.rpc("payout_batch_detail", { p_batch: batchId });
  if (error) throw new Error(error.message);
  return data === null ? null : batchDetail.parse(data);
}

const section = z.object({
  code: z.string(),
  label: z.string(),
  base_paise: paise,
  taxable_paise: paise,
  rate_bps: z.number().int(),
  tds_paise: paise,
  borne_by: z.enum(["creator", "eduwit"]),
});
export const payoutDetail = z.object({
  id: z.uuid(),
  ref: z.string(),
  status: z.enum(PAYOUT_STATUSES),
  batch_id: z.uuid(),
  batch_ref: z.string(),
  creator_id: z.uuid(),
  creator_name: z.string(),
  legal_name: z.string().nullable(),
  handle: z.string(),
  pan_last4: z.string().nullable(),
  bank_last4: z.string().nullable(),
  ifsc: z.string().nullable(),
  gstin: z.string().nullable(),
  gross_paise: paise,
  gst_base_paise: paise,
  gst_paise: paise,
  tds_paise: paise,
  eduwit_tds_paise: paise,
  net_paise: paise,
  sections: z.array(section),
  needs_invoice: z.boolean(),
  utr: z.string().nullable(),
  paid_on: z.string().nullable(),
  status_reason: z.string().nullable(),
  advice_path: z.string().nullable(),
  created_at: ts,
  items: z.array(
    z.object({
      entry_id: z.number().int(),
      amount_paise: paise,
      type,
      note: z.string().nullable(),
      period: z.string(),
      deal_title: z.string().nullable(),
    }),
  ),
  invoices: z.array(
    z.object({
      id: z.uuid(),
      kind: z.enum(["creator_gst_invoice", "payout_statement"]),
      number: z.string(),
      issued_on: z.string(),
      gstin: z.string().nullable(),
      taxable_paise: paise,
      gst_paise: paise,
      total_paise: paise,
      status: z.enum(["submitted", "accepted", "rejected"]),
      review_note: z.string().nullable(),
      file_path: z.string().nullable(),
      created_at: ts,
    }),
  ),
  organisation: z.record(z.string(), z.unknown()).nullable(),
});
export type PayoutDetail = z.infer<typeof payoutDetail>;

export async function loadPayout(db: Db, payoutId: string): Promise<PayoutDetail | null> {
  const { data, error } = await db.rpc("payout_detail", { p_payout: payoutId });
  if (error) throw new Error(error.message);
  return data === null ? null : payoutDetail.parse(data);
}

const candidateEntry = z.object({
  id: z.number().int(),
  type,
  direction,
  remaining_paise: paise,
  tds_component: z.enum(TDS_COMPONENTS),
  deal_id: z.uuid().nullable(),
  deal_title: z.string().nullable(),
  note: z.string().nullable(),
  agency_payee: z.boolean(),
});
export const candidates = z.object({
  today: z.string(),
  rules: z.object({
    payouts: z.object({
      kyc_required_for_payout: z.boolean(),
      hold_until_tax_confirmed: z.boolean(),
      min_payout_rupees: z.number().int().catch(0),
      agency_payee: z.enum(["hold", "pay_creator"]).catch("hold"),
    }),
    gst: z.object({ rate_pct: z.number(), require_invoice_for_registered: z.boolean() }),
    sections: z.array(
      z.object({
        code: z.string(),
        label: z.string(),
        rate_bps: z.number().int(),
        no_pan_rate_bps: z.number().int(),
        single_threshold_paise: paise.nullable(),
        fy_threshold_paise: paise.nullable(),
        components: z.array(z.enum(TDS_COMPONENTS)),
        borne_by: z.enum(["creator", "eduwit"]),
      }),
    ),
    sections_confirmed: z.boolean(),
  }),
  creators: z.array(
    z.object({
      creator_id: z.uuid(),
      name: z.string(),
      handle: z.string(),
      kyc_verified: z.boolean(),
      has_pan: z.boolean(),
      charges_gst: z.boolean(),
      fy_prior: z.record(z.string(), z.object({ base_paise: paise, taxed: z.boolean() })),
      entries: z.array(candidateEntry),
    }),
  ),
});
export type Candidates = z.infer<typeof candidates>;

export async function loadCandidates(
  db: Db,
  filters: { creator_ids?: string[]; campaign_id?: string | null; due_by?: string | null },
): Promise<Candidates> {
  const { data, error } = await db.rpc("payout_candidates", {
    p: { creator_ids: filters.creator_ids ?? [], campaign_id: filters.campaign_id ?? "", due_by: filters.due_by ?? "" },
  });
  if (error) throw new Error(error.message);
  return candidates.parse(data);
}

export const invoiceRow = z.object({
  id: z.uuid(),
  payout_id: z.uuid(),
  payout_ref: z.string(),
  creator_id: z.uuid(),
  creator_name: z.string(),
  number: z.string(),
  issued_on: z.string(),
  gstin: z.string().nullable(),
  taxable_paise: paise,
  gst_paise: paise,
  total_paise: paise,
  payout_gst_base_paise: paise,
  payout_gst_paise: paise,
  status: z.enum(["submitted", "accepted", "rejected"]),
  review_note: z.string().nullable(),
  file_path: z.string().nullable(),
  created_at: ts,
});
export type InvoiceRow = z.infer<typeof invoiceRow>;

export async function loadInvoices(db: Db, status: "" | "submitted" | "accepted" | "rejected"): Promise<InvoiceRow[]> {
  const { data, error } = await db.rpc("invoices_queue", { p_status: status });
  if (error) throw new Error(error.message);
  return z.array(invoiceRow).parse(data);
}

export const tdsSummary = z.object({
  sections: z.array(
    z.object({
      section: z.string(),
      borne_by: z.enum(["creator", "eduwit"]),
      base_paise: paise,
      taxable_paise: paise,
      amount_paise: paise,
      creators: z.number().int(),
    }),
  ),
  creators: z.array(
    z.object({
      creator_id: z.uuid(),
      name: z.string().nullable(),
      display_name: z.string(),
      pan_last4: z.string().nullable(),
      base_paise: paise,
      amount_paise: paise,
      certificate: z.boolean().nullable(),
    }),
  ),
});
export type TdsSummary = z.infer<typeof tdsSummary>;

export async function loadTdsSummary(db: Db, fy: string, quarter: string): Promise<TdsSummary> {
  const { data, error } = await db.rpc("tds_summary", { p_fy: fy, p_quarter: quarter });
  if (error) throw new Error(error.message);
  return data === null ? { sections: [], creators: [] } : tdsSummary.parse(data);
}

export const reconSource = z.object({
  flag_after_days: z.number().int(),
  entries: z.array(
    z.object({
      subject: z.string(),
      direction,
      amount_paise: paise,
      confirmed_paise: paise,
      reversed: z.boolean(),
      at: ts,
      creator_name: z.string(),
      deal_title: z.string().nullable(),
    }),
  ),
  receipts: z.array(
    z.object({
      enrollment_ref: z.string(),
      expected_paise: paise.nullable(),
      received_paise: paise,
      received_on: z.string().nullable(),
      status: z.enum(["expected", "partly_received", "received", "reversed", "withdrawn"]),
      source: z.enum(["b2b", "b2c", "manual"]),
      reason: z.string().nullable(),
      student_lead_id: z.number().int(),
      recorded_at: ts,
    }),
  ),
});
export type ReconSource = z.infer<typeof reconSource>;

export async function loadRecon(db: Db): Promise<ReconSource | null> {
  const { data, error } = await db.rpc("recon_data");
  if (error) throw new Error(error.message);
  return data === null ? null : reconSource.parse(data);
}

// ---------------------------------------------------------------------------------------------------------------
// Earnings (creator, agency with the earnings grant, staff)
// ---------------------------------------------------------------------------------------------------------------
export const earningsEntry = z.object({
  id: z.number().int(),
  type,
  direction,
  amount_paise: paise,
  confirmed_paise: paise,
  paid_paise: paise,
  status,
  period: z.string(),
  due_on: z.string(),
  posted_at: ts,
  note: z.string().nullable(),
  deal_id: z.uuid().nullable(),
  deal_title: z.string().nullable(),
  attribution_id: z.uuid().nullable(),
  lead_ref: z.string().nullable(),
  payout_id: z.uuid().nullable(),
});
export type EarningsEntry = z.infer<typeof earningsEntry>;

export const earningsPayout = z.object({
  id: z.uuid(),
  ref: z.string(),
  status: z.enum(PAYOUT_STATUSES),
  gross_paise: paise,
  gst_base_paise: paise,
  gst_paise: paise,
  tds_paise: paise,
  net_paise: paise,
  utr: z.string().nullable(),
  paid_on: z.string().nullable(),
  created_at: ts,
  needs_invoice: z.boolean(),
  advice: z.boolean(),
  invoice: z
    .object({
      id: z.uuid(),
      kind: z.enum(["creator_gst_invoice", "payout_statement"]),
      number: z.string(),
      status: z.enum(["submitted", "accepted", "rejected"]),
      review_note: z.string().nullable(),
    })
    .nullable(),
});
export type EarningsPayout = z.infer<typeof earningsPayout>;

export const earnings = z.object({
  entries: z.array(earningsEntry),
  payouts: z.array(earningsPayout),
  certificates: z.array(z.object({ id: z.uuid(), fy: z.string(), quarter: z.string(), uploaded_at: ts })),
  tds: z.array(z.object({ fy: z.string(), quarter: z.string(), section: z.string(), amount_paise: paise })),
  gst: z.object({ charges_gst: z.boolean(), gstin: z.string().nullable() }).nullable(),
  settings: z.object({
    cycle: z.enum(["weekly", "fortnightly", "monthly"]).catch("monthly"),
    payout_day_of_month: z.number().int().catch(10),
  }),
});
export type Earnings = z.infer<typeof earnings>;

export async function loadEarnings(db: Db, creatorId: string): Promise<Earnings | null> {
  const { data, error } = await db.rpc("creator_earnings", { p_creator: creatorId });
  if (error) throw new Error(error.message);
  return data === null ? null : earnings.parse(data);
}
