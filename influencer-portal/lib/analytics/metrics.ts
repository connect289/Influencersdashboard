// Every number on a dashboard is defined here once (spec 12): its unit, whether up is good, the formula and where the
// data comes from. The plain-language label and definition live in messages (analytics.metrics.<id>) so the UI shows
// them as tooltips; docs/METRICS.md is generated from both (npm run gen:sql) and a test fails if it is stale. Pure.
import type { Polarity } from "./compute";

export type MetricUnit = "count" | "money" | "percent" | "ratio" | "date";
export const METRIC_GROUPS = [
  "funnel",
  "quality",
  "spend",
  "economics",
  "health",
  "operations",
  "earnings",
  "finance",
] as const;
export type MetricGroup = (typeof METRIC_GROUPS)[number];

export interface MetricDef {
  group: MetricGroup;
  unit: MetricUnit;
  polarity: Polarity;
  /** How it is computed, in terms of the other metrics or the stored data. */
  formula: string;
  /** Tables and views it reads. */
  source: string;
  /** "period" counts what happened in the date range; "now" is a snapshot at the time of viewing. */
  basis: "period" | "now" | "all_time";
}

const m = (d: MetricDef) => d;
const LEADS = "`inf.an_leads` (from `inf.lead_attributions` and `inf.creator_lead_feed`)";

export const METRICS = {
  clicks: m({
    group: "funnel",
    unit: "count",
    polarity: "up_is_good",
    formula: "Clicks on tracking links by click date (IST), excluding crawlers, link previews and HEAD requests",
    source: "`inf.an_clicks_daily` (from `inf.link_clicks`)",
    basis: "period",
  }),
  leads: m({
    group: "funnel",
    unit: "count",
    polarity: "up_is_good",
    formula:
      "Credited leads (first touch, plus last touch under the last-touch model) by enquiry date (IST); the same leads a creator sees in their pipeline",
    source: LEADS,
    basis: "period",
  }),
  qualified_leads: m({
    group: "funnel",
    unit: "count",
    polarity: "up_is_good",
    formula: "Of those leads, the ones that have reached Qualified or any later stage (stages are cumulative)",
    source: LEADS,
    basis: "period",
  }),
  allocated_leads: m({
    group: "funnel",
    unit: "count",
    polarity: "up_is_good",
    formula: "Of those leads, the ones allocated to a counsellor or further",
    source: LEADS,
    basis: "period",
  }),
  applications: m({
    group: "funnel",
    unit: "count",
    polarity: "up_is_good",
    formula: "Of those leads, the ones that applied or enrolled",
    source: LEADS,
    basis: "period",
  }),
  enrollments: m({
    group: "funnel",
    unit: "count",
    polarity: "up_is_good",
    formula: "Of those leads, the ones that enrolled (refunded or cancelled enrolments do not count)",
    source: LEADS,
    basis: "period",
  }),
  click_to_lead_rate: m({
    group: "funnel",
    unit: "percent",
    polarity: "up_is_good",
    formula: "leads ÷ clicks (can exceed 100% when students type a creator code without clicking)",
    source: "clicks, leads",
    basis: "period",
  }),
  qualification_rate: m({
    group: "quality",
    unit: "percent",
    polarity: "up_is_good",
    formula: "qualified leads ÷ leads",
    source: LEADS,
    basis: "period",
  }),
  junk_rate: m({
    group: "quality",
    unit: "percent",
    polarity: "down_is_good",
    formula: "leads closed as junk ÷ leads",
    source: LEADS,
    basis: "period",
  }),
  duplicate_rate: m({
    group: "quality",
    unit: "percent",
    polarity: "down_is_good",
    formula: "attributions decided as duplicates ÷ all attribution decisions (credited or not)",
    source: "`inf.an_leads` (all decisions)",
    basis: "period",
  }),
  enrollment_rate: m({
    group: "quality",
    unit: "percent",
    polarity: "up_is_good",
    formula: "enrolments ÷ leads",
    source: LEADS,
    basis: "period",
  }),
  committed_spend: m({
    group: "spend",
    unit: "money",
    polarity: "neutral",
    formula:
      "For agreed and active deals: the fixed fees, milestones, retainers, minimum guarantees and extra fees the creator earns over the deal's term with no leads at all (the compensation engine's zero-performance simulation), before tax",
    source: "`inf.deals.committed_paise` (written by the ledger runner)",
    basis: "now",
  }),
  accrued_spend: m({
    group: "spend",
    unit: "money",
    polarity: "neutral",
    formula:
      "Earnings posted to creator ledgers in the period by posting date: credits minus debits (penalties, clawbacks, reversals), before TDS and GST; settlement lines excluded",
    source: "`inf.an_spend_daily` (from `inf.ledger_entries`)",
    basis: "period",
  }),
  paid_spend: m({
    group: "spend",
    unit: "money",
    polarity: "neutral",
    formula: "Gross amount of payouts marked paid in the period (by payment date), before TDS",
    source: "`inf.payouts`",
    basis: "period",
  }),
  budget: m({
    group: "spend",
    unit: "money",
    polarity: "neutral",
    formula: "The campaign's budget as entered on the campaign",
    source: "`inf.campaigns.budget_paise`",
    basis: "now",
  }),
  budget_used: m({
    group: "spend",
    unit: "percent",
    polarity: "neutral",
    formula: "accrued spend to date on the campaign's deals ÷ budget",
    source: "accrued spend (all time), budget",
    basis: "all_time",
  }),
  revenue: m({
    group: "economics",
    unit: "money",
    polarity: "up_is_good",
    formula:
      "Eduwit's commission received in the period for enrolments of credited leads, excluding GST, by the date it was received (or recorded, when the CRM gives no date); partly paid invoices count pro rata",
    source: "`inf.an_revenue` (from `inf.receipts_effective()` and `inf.lead_attributions`)",
    basis: "period",
  }),
  expected_revenue: m({
    group: "economics",
    unit: "money",
    polarity: "up_is_good",
    formula:
      "Eduwit's commission still expected now (not yet received) for enrolments of credited leads, excluding GST",
    source: "`inf.an_revenue`",
    basis: "now",
  }),
  cost_per_lead: m({
    group: "economics",
    unit: "money",
    polarity: "down_is_good",
    formula: "accrued spend ÷ leads",
    source: "accrued spend, leads",
    basis: "period",
  }),
  cost_per_qualified_lead: m({
    group: "economics",
    unit: "money",
    polarity: "down_is_good",
    formula: "accrued spend ÷ qualified leads",
    source: "accrued spend, qualified leads",
    basis: "period",
  }),
  cost_per_enrollment: m({
    group: "economics",
    unit: "money",
    polarity: "down_is_good",
    formula: "accrued spend ÷ enrolments",
    source: "accrued spend, enrolments",
    basis: "period",
  }),
  net_roi: m({
    group: "economics",
    unit: "percent",
    polarity: "up_is_good",
    formula: "(revenue − accrued spend) ÷ accrued spend",
    source: "revenue, accrued spend",
    basis: "period",
  }),
  roas: m({
    group: "economics",
    unit: "ratio",
    polarity: "up_is_good",
    formula: "revenue ÷ accrued spend",
    source: "revenue, accrued spend",
    basis: "period",
  }),
  active_creators: m({
    group: "health",
    unit: "count",
    polarity: "up_is_good",
    formula: "Creators whose status is Active now",
    source: "`inf.creators`",
    basis: "now",
  }),
  new_creators: m({
    group: "health",
    unit: "count",
    polarity: "up_is_good",
    formula: "Creators approved in the period",
    source: "`inf.creators.approved_at`",
    basis: "period",
  }),
  dormant_creators: m({
    group: "health",
    unit: "count",
    polarity: "down_is_good",
    formula: "Creators flagged dormant now (no activity for the dormancy period in Settings → Creators)",
    source: "`inf.creators`",
    basis: "now",
  }),
  overdue_deliverables: m({
    group: "operations",
    unit: "count",
    polarity: "down_is_good",
    formula: "Deliverables past their due date that are not live, done or cancelled",
    source: "`inf.deliverables`",
    basis: "now",
  }),
  pending_reviews: m({
    group: "operations",
    unit: "count",
    polarity: "down_is_good",
    formula: "Concepts and drafts waiting for an Eduwit review",
    source: "`inf.deliverables`",
    basis: "now",
  }),
  pending_negotiations: m({
    group: "operations",
    unit: "count",
    polarity: "down_is_good",
    formula: "Deals proposed or negotiating plus contracts sent or in negotiation",
    source: "`inf.deals`, `inf.contracts`",
    basis: "now",
  }),
  contracts_expiring: m({
    group: "operations",
    unit: "count",
    polarity: "neutral",
    formula: "Countersigned contracts whose deal ends in the next 30 days",
    source: "`inf.contracts`, `inf.deals`",
    basis: "now",
  }),
  payouts_due: m({
    group: "operations",
    unit: "money",
    polarity: "neutral",
    formula: "Confirmed earnings that are due and not yet in a payout batch",
    source: "`inf.ledger_entries`",
    basis: "now",
  }),
  kyc_pending: m({
    group: "operations",
    unit: "count",
    polarity: "down_is_good",
    formula: "KYC submissions waiting for verification",
    source: "`inf.creator_kyc`",
    basis: "now",
  }),
  fraud_flags: m({
    group: "operations",
    unit: "count",
    polarity: "down_is_good",
    formula: "Open fraud flags waiting for review",
    source: "`inf.fraud_flags`",
    basis: "now",
  }),
  on_time_rate: m({
    group: "operations",
    unit: "percent",
    polarity: "up_is_good",
    formula: "Deliverables that went live on or before their due date ÷ deliverables due in the period",
    source: "`inf.deliverables`",
    basis: "period",
  }),
  earned_total: m({
    group: "earnings",
    unit: "money",
    polarity: "up_is_good",
    formula: "Everything the creator has earned to date, net of penalties and clawbacks, before tax",
    source: "`inf.ledger_entries`",
    basis: "all_time",
  }),
  earnings_pending: m({
    group: "earnings",
    unit: "money",
    polarity: "neutral",
    formula: "Earned but not yet confirmed (for example commission waiting for Eduwit's own commission)",
    source: "`inf.ledger_entries`",
    basis: "now",
  }),
  earnings_payable: m({
    group: "earnings",
    unit: "money",
    polarity: "neutral",
    formula: "Confirmed and due: goes out in the next payout run",
    source: "`inf.ledger_entries`",
    basis: "now",
  }),
  earnings_paid: m({
    group: "earnings",
    unit: "money",
    polarity: "up_is_good",
    formula: "Settled by payouts to date, before TDS",
    source: "`inf.ledger_entries`",
    basis: "all_time",
  }),
  next_payout: m({
    group: "earnings",
    unit: "date",
    polarity: "neutral",
    formula:
      "The next payout run on or after today from Settings → Finance → Payouts (weekly on Mondays, fortnightly or monthly on the payout day)",
    source: "`finance.payouts` setting",
    basis: "now",
  }),
  fixed_received: m({
    group: "earnings",
    unit: "money",
    polarity: "up_is_good",
    formula: "Fixed fees and milestones already earned on the creator's active deals",
    source: "`inf.ledger_entries` (fixed fee and milestone lines)",
    basis: "all_time",
  }),
  fixed_remaining: m({
    group: "earnings",
    unit: "money",
    polarity: "neutral",
    formula:
      "Committed fixed amount of the creator's agreed and active deals minus what is already earned (never below zero)",
    source: "`inf.deals.committed_paise`, `inf.ledger_entries`",
    basis: "now",
  }),
  liabilities: m({
    group: "finance",
    unit: "money",
    polarity: "neutral",
    formula: "What Eduwit owes creators now: earned and not yet paid, confirmed or not (net of recoveries)",
    source: "`inf.ledger_entries`",
    basis: "now",
  }),
  tds_deducted: m({
    group: "finance",
    unit: "money",
    polarity: "neutral",
    formula: "TDS deducted from creators' payouts in the period (by payment date)",
    source: "`inf.tds_records`",
    basis: "period",
  }),
  receipts_waiting: m({
    group: "finance",
    unit: "money",
    polarity: "down_is_good",
    formula: "Creator commission still waiting for Eduwit's own commission to be received",
    source: "`inf.ledger_entries`, `inf.receipts_effective()`",
    basis: "now",
  }),
  receipts_flagged: m({
    group: "finance",
    unit: "count",
    polarity: "down_is_good",
    formula:
      "Enrolments whose creator commission has waited longer than the reconciliation period (Settings → Finance)",
    source: "`inf.recon_data()`",
    basis: "now",
  }),
} as const satisfies Record<string, MetricDef>;

export type MetricId = keyof typeof METRICS;
export const METRIC_IDS = Object.keys(METRICS) as MetricId[];
