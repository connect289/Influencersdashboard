/** Commission and money (B12): types for the b2b.money_* reads, labels and pure helpers shared by the money screens. */

export type Tier = { from_pct: number; pct: number };
export type TierNow = { pct: number | null; provisional: boolean; conversion_pct: number | null; basis: "settled" | "projected" | "last_settled" | "first_tier";
                        accepted?: number; enrollments?: number };

export type MoneySettings = {
  gst_rate: number; sac_code: string | null; tds_rate: number | null; refund_window_days: number; confirmed_by_ca: boolean; invoice_prefix: string;
  tier_min_leads: number; auto_close: boolean; close_day: number; reminder_days?: number[];
  eduwit: { legal_name: string | null; gstin: string | null; address: string | null; state_code: string | null; bank: string | null };
};

export type MoneyOverview = {
  month: string;
  totals: { expected_net: number; realised_uninvoiced_net: number; realised_fy_net: number };
  invoices: { drafts: number; draft_total: number; outstanding: number; overdue: number; ageing: Record<"0_30" | "31_60" | "61_90" | "90_plus", number> };
  received_fy: { amount: number; tds: number };
  enrollments: { to_verify: number; oldest_to_verify: string | null; verified_month: number; reported_month: number; no_line: number };
  partners: {
    id: number; name: string; billing_ready: boolean; expected_net: number; realised_uninvoiced_net: number; outstanding: number; to_verify: number;
    conversion: { accepted: number; enrollments: number; conversion_pct: number | null };
    tier: { rate_id: number; tiers: Tier[]; now: TierNow } | null;
  }[];
  months: { period: string; closed: boolean; partners_settled: number }[];
  setup_missing: string[];
  settings: MoneySettings;
};

export type EarningLine = {
  id: number; kind: "commission" | "tier_adjustment" | "reversal" | "manual_adjustment"; status: "expected" | "realised" | "void"; period: string;
  pct: number | null; fee_base_inr: number | null; net_inr: number; gst_inr: number; gross_inr: number; provisional: boolean;
  invoice_id: number | null; invoice_number: string | null; note: string | null; rate_type: string | null; gst_inclusive: boolean | null;
};

export type EnrollmentStatus = "reported" | "verified" | "refunded" | "cancelled";
export type EnrollmentRow = {
  id: number; lead_id: number; allocation_id: number | null; reference: string | null; record_id: string | null; name: string | null;
  partner_id: number; partner_name: string; programme: string | null; university: string | null; programme_id: number | null; enrolled_on: string;
  fee_amount_inr: number | null; fee_paid_inr: number | null; status: EnrollmentStatus; proof_ref: string | null; proof_url: string | null;
  verified_at: string | null; refund_window_ends_on: string | null; refunded_at: string | null; refund_reason: string | null;
  expected_net_inr: number | null; realised_net_inr: number | null; created_at: string; lines: EarningLine[];
};
export type EnrollmentList = { rows: EnrollmentRow[]; total: number };

export type InvoiceStatus = "draft" | "approved" | "sent" | "partly_paid" | "paid" | "cancelled";
export type InvoiceRow = {
  id: number; number: string | null; status: InvoiceStatus; partner_id: number; partner_name: string; through_period: string; issue_date: string | null;
  due_date: string | null; taxable_inr: number; gst_inr: number; total_inr: number; received_inr: number; tds_inr: number; outstanding_inr: number;
  lines: number; days_overdue: number | null; created_at: string;
};
export type Party = { legal_name: string | null; gstin: string | null; address: string | null; state_code: string | null; bank?: string | null; email?: string | null; name?: string | null };
export type InvoiceDetail = Omit<InvoiceRow, "gst_inr" | "outstanding_inr" | "lines" | "days_overdue"> & {
  fy: string | null; seq: number | null; supplier: Party; recipient: Party; sac_code: string | null; place_of_supply: string | null;
  tax_type: "igst" | "cgst_sgst" | null; gst_rate: number; cgst_inr: number; sgst_inr: number; igst_inr: number;
  approved_at: string | null; sent_at: string | null; paid_at: string | null; cancelled_at: string | null; cancel_reason: string | null;
  lines: { id: number; earning_id: number; lead_id: number | null; reference: string | null; description: string; taxable_inr: number; gst_inr: number; total_inr: number; released: boolean }[];
  payments: { receipt_id: number; received_on: string; bank_ref: string | null; amount_inr: number; tds_inr: number; method: string; reversed: boolean }[];
  setup_missing: string[];
};

export type Receipt = {
  id: number; partner_id: number; partner_name: string; received_on: string; amount_inr: number; tds_inr: number; bank_ref: string | null; note: string | null;
  status: "active" | "void"; void_reason: string | null; unapplied_inr: number;
  applied: { invoice_id: number; number: string | null; amount_inr: number; tds_inr: number; method: string }[];
};
export type ReceiptsData = { receipts: Receipt[]; open_invoices: { id: number; number: string; partner_id: number; outstanding_inr: number; issue_date: string }[] };

export type StatementRow = {
  id: number; partner_id: number; partner_name: string; period_from: string; period_to: string; file_name: string | null; row_count: number;
  created_at: string; matched: number; partner_only: number; amount_mismatch: number; open: number;
};
export type MatchStatus = "matched" | "partner_only" | "amount_mismatch";
export type StatementLine = {
  id: number; row_no: number; reference: string | null; record_id: string | null; phone: string | null; name: string | null; programme: string | null;
  enrolled_on: string | null; amount_inr: number | null; match_status: MatchStatus; match_method: string | null; lead_id: number | null;
  allocation_id: number | null; enrollment_id: number | null; enrollment_status: EnrollmentStatus | null; eduwit_amount_inr: number | null;
  diff_inr: number | null; resolution: "verified" | "recorded" | "dismissed" | null; resolution_note: string | null;
};
export type StatementDetail = {
  statement: { id: number; partner_id: number; partner_name: string; period_from: string; period_to: string; file_name: string | null; row_count: number; created_at: string };
  lines: StatementLine[];
  eduwit_only: { enrollment_id: number; lead_id: number; reference: string | null; name: string | null; programme: string | null; enrolled_on: string;
                 status: EnrollmentStatus; record_id: string | null; eduwit_amount_inr: number | null }[];
  counts: { matched: number; partner_only: number; amount_mismatch: number; resolved: number; to_verify: number };
};

// ---------- labels ----------
type Tone = "neutral" | "success" | "warning" | "danger" | "info" | "brand";
export const ENROLLMENT_STATUS: Record<EnrollmentStatus, { label: string; tone: Tone }> = {
  reported: { label: "To verify", tone: "warning" },
  verified: { label: "Verified", tone: "success" },
  refunded: { label: "Refunded", tone: "danger" },
  cancelled: { label: "Cancelled", tone: "neutral" },
};
export const INVOICE_STATUS: Record<InvoiceStatus, { label: string; tone: Tone }> = {
  draft: { label: "Draft", tone: "brand" },
  approved: { label: "Approved", tone: "info" },
  sent: { label: "Sent", tone: "info" },
  partly_paid: { label: "Part paid", tone: "warning" },
  paid: { label: "Paid", tone: "success" },
  cancelled: { label: "Cancelled", tone: "neutral" },
};
export const LINE_KIND: Record<EarningLine["kind"], string> = {
  commission: "Commission",
  tier_adjustment: "Tier settlement",
  reversal: "Refund reversal",
  manual_adjustment: "Adjustment",
};
export const PROOF_TYPE = {
  statement_line: "Partner statement line",
  university_confirmation: "University confirmation",
  fee_receipt: "Fee receipt",
} as const;
export type ProofType = keyof typeof PROOF_TYPE;
export const MATCH_STATUS: Record<MatchStatus | "eduwit_only", { label: string; tone: Tone; hint: string }> = {
  matched: { label: "Matched", tone: "success", hint: "On the statement and in Eduwit's records with the same amount." },
  amount_mismatch: { label: "Amount mismatch", tone: "warning", hint: "Both sides have the enrolment but the amounts differ." },
  partner_only: { label: "Partner only", tone: "danger", hint: "On the partner's statement but not enrolled in Eduwit's records: possible leakage." },
  eduwit_only: { label: "Eduwit only", tone: "info", hint: "Enrolled in Eduwit's records in this period but missing from the statement." },
};
export const MATCH_METHOD: Record<string, string> = {
  reference: "Eduwit reference",
  record_id: "Partner record ID",
  phone: "Phone",
  name_programme: "Name and programme",
};
export const TIER_BASIS: Record<TierNow["basis"], string> = {
  settled: "settled",
  projected: "projected from this month",
  last_settled: "last settled month (too few leads yet)",
  first_tier: "first tier (no history yet)",
};

// ---------- helpers ----------
export function formatInr(v: number | null | undefined, paise = false): string {
  if (v === null || v === undefined || !Number.isFinite(Number(v))) return "—";
  const n = Number(v);
  const s = Math.abs(n).toLocaleString("en-IN", paise ? { minimumFractionDigits: 2, maximumFractionDigits: 2 } : { maximumFractionDigits: 0 });
  return `${n < 0 ? "−" : ""}₹${s}`;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** "2026-09" → "Sep 2026". */
export function monthLabel(period: string): string {
  const m = /^(\d{4})-(\d{2})$/.exec(period);
  return m ? `${MONTHS[Number(m[2]) - 1]} ${m[1]}` : period;
}

/** "2026-10-07" → "7 Oct 2026". */
export function dayLabel(d: string | null | undefined): string {
  const m = d ? /^(\d{4})-(\d{2})-(\d{2})/.exec(d) : null;
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : "—";
}

/** The next tier above the partner's conversion and how many more enrolments reach it this month. Lower rates at higher conversion are normal. */
export function tierWatch(tiers: Tier[] | null | undefined, accepted: number, enrollments: number) {
  if (!tiers?.length) return null;
  const sorted = [...tiers].sort((a, b) => a.from_pct - b.from_pct);
  const conv = accepted > 0 ? (enrollments * 100) / accepted : null;
  const current = conv === null ? sorted[0]! : [...sorted].reverse().find((t) => t.from_pct <= conv) ?? sorted[0]!;
  const next = sorted.find((t) => t.from_pct > (conv ?? -1) && t !== current) ?? null;
  const needed = next && accepted > 0 ? Math.max(0, Math.ceil((next.from_pct / 100) * accepted - 1e-9) - enrollments) : null;
  return { conversion_pct: conv === null ? null : Math.round(conv * 10) / 10, current, next, enrollments_to_next: needed };
}

export const GSTIN_RE = /^[0-9]{2}[A-Z0-9]{13}$/;
/** The two-digit state code a GSTIN starts with. */
export const stateOfGstin = (g: string | null | undefined) => (g && GSTIN_RE.test(g) ? g.slice(0, 2) : null);

export const GST_STATES: Record<string, string> = {
  "01": "Jammu and Kashmir", "02": "Himachal Pradesh", "03": "Punjab", "04": "Chandigarh", "05": "Uttarakhand", "06": "Haryana", "07": "Delhi",
  "08": "Rajasthan", "09": "Uttar Pradesh", "10": "Bihar", "11": "Sikkim", "12": "Arunachal Pradesh", "13": "Nagaland", "14": "Manipur", "15": "Mizoram",
  "16": "Tripura", "17": "Meghalaya", "18": "Assam", "19": "West Bengal", "20": "Jharkhand", "21": "Odisha", "22": "Chhattisgarh", "23": "Madhya Pradesh",
  "24": "Gujarat", "26": "Dadra and Nagar Haveli and Daman and Diu", "27": "Maharashtra", "29": "Karnataka", "30": "Goa", "31": "Lakshadweep", "32": "Kerala",
  "33": "Tamil Nadu", "34": "Puducherry", "35": "Andaman and Nicobar Islands", "36": "Telangana", "37": "Andhra Pradesh", "38": "Ladakh",
};

const ONES = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen",
  "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
const TENS = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
function belowThousand(n: number): string {
  const h = Math.floor(n / 100), r = n % 100;
  const rest = r < 20 ? ONES[r]! : `${TENS[Math.floor(r / 10)]}${r % 10 ? " " + ONES[r % 10] : ""}`;
  return [h ? `${ONES[h]} Hundred` : "", rest].filter(Boolean).join(" ");
}
/** Indian-style amount in words for an invoice: 53100.5 → "Rupees Fifty Three Thousand One Hundred and Fifty Paise Only". */
export function amountInWords(v: number): string {
  const total = Math.round(Math.abs(v) * 100);
  let n = Math.floor(total / 100);
  const paise = total % 100;
  if (n === 0 && paise === 0) return "Rupees Zero Only";
  const parts: string[] = [];
  const crore = Math.floor(n / 1e7); n %= 1e7;
  const lakh = Math.floor(n / 1e5); n %= 1e5;
  const thousand = Math.floor(n / 1e3); n %= 1e3;
  if (crore) parts.push(`${crore >= 1000 ? amountInWords(crore).replace(/^Rupees | Only$/g, "") : belowThousand(crore)} Crore`);
  if (lakh) parts.push(`${belowThousand(lakh)} Lakh`);
  if (thousand) parts.push(`${belowThousand(thousand)} Thousand`);
  if (n) parts.push(belowThousand(n));
  const rupees = parts.join(" ");
  return `Rupees ${rupees || "Zero"}${paise ? ` and ${belowThousand(paise)} Paise` : ""} Only`;
}

// ---------- statement upload ----------
export const STATEMENT_FIELDS = [
  { key: "reference", label: "Eduwit reference", hints: ["eduwit", "reference", "ref", "edw"] },
  { key: "record_id", label: "Partner record ID", hints: ["lead id", "record", "prospect id", "application", "crm id", "id"] },
  { key: "phone", label: "Phone", hints: ["phone", "mobile", "contact"] },
  { key: "name", label: "Student name", hints: ["name", "student", "candidate"] },
  { key: "programme", label: "Programme", hints: ["programme", "program", "course"] },
  { key: "enrolled_on", label: "Enrolment date", hints: ["enrol", "enroll", "admission", "date"] },
  { key: "amount_inr", label: "Commission amount", hints: ["commission", "payout", "amount", "payable"] },
] as const;
export type StatementField = (typeof STATEMENT_FIELDS)[number]["key"];

/** Best column for each statement field by header name; each column is used once, more specific fields first. */
export function suggestStatementMapping(headers: string[]): Partial<Record<StatementField, string>> {
  const used = new Set<string>();
  const out: Partial<Record<StatementField, string>> = {};
  for (const f of STATEMENT_FIELDS) {
    const h = headers.find((x) => !used.has(x) && f.hints.some((k) => x.toLowerCase().includes(k)));
    if (h) { out[f.key] = h; used.add(h); }
  }
  return out;
}

/** Turns a typed date (2026-09-20, 20/09/2026, 20-09-2026, 20 Sep 2026) into ISO, or null. Day first, as in India. */
export function isoDate(s: string): string | null {
  const t = s.trim();
  let m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(t);
  if (m) return valid(+m[1]!, +m[2]!, +m[3]!);
  m = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$/.exec(t);
  if (m) return valid(m[3]!.length === 2 ? 2000 + +m[3]! : +m[3]!, +m[2]!, +m[1]!);
  m = /^(\d{1,2})[\s-]([A-Za-z]{3})[A-Za-z]*[\s-,]+(\d{4})$/.exec(t);
  if (m) { const mo = MONTHS.findIndex((x) => x.toLowerCase() === m![2]!.toLowerCase()); return mo < 0 ? null : valid(+m[3]!, mo + 1, +m[1]!); }
  return null;
  function valid(y: number, mo: number, d: number) {
    const dt = new Date(Date.UTC(y, mo - 1, d));
    return dt.getUTCFullYear() === y && dt.getUTCMonth() === mo - 1 && dt.getUTCDate() === d ? dt.toISOString().slice(0, 10) : null;
  }
}

/** Statement rows in the shape b2b.statement_import takes, from the file's rows and the chosen columns. */
export function statementRows(rows: Record<string, string>[], map: Partial<Record<StatementField, string>>) {
  return rows.map((r) => {
    const get = (k: StatementField) => (map[k] ? (r[map[k]!] ?? "").trim() : "");
    const enrolled = get("enrolled_on");
    return {
      reference: get("reference") || null, record_id: get("record_id") || null, phone: get("phone") || null, name: get("name") || null,
      programme: get("programme") || null, enrolled_on: enrolled ? isoDate(enrolled) : null, amount_inr: get("amount_inr") || null, raw: r,
    };
  }).filter((r) => r.reference || r.record_id || r.phone || r.name);
}
