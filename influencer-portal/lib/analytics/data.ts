import "server-only";
// Loaders for the dashboards. Staff read the summary views through inf.analytics_* (analytics.read); the creator home
// reads live rows through inf.creator_dashboard. Each response is parsed with zod before any screen uses it.
import { z } from "zod";
import type { Db } from "@/lib/contracts/data";
import type { Totals } from "./compute";
import type { DateRange } from "./ranges";

const n = z.coerce.number();
const totalsRow = z.object({
  key: z.string().nullable(),
  label: z.string().nullable(),
  clicks: n,
  leads: n,
  qualified: n,
  allocated: n,
  applied: n,
  enrolled: n,
  junk: n,
  attributions: n,
  duplicates: n,
  cost_paise: n,
  revenue_paise: n,
});
export type TotalsRow = z.infer<typeof totalsRow> & Totals;

export const DIMENSIONS = ["creator", "campaign", "platform", "content_type", "programme", "deal_model"] as const;
export type Dimension = (typeof DIMENSIONS)[number] | "all" | "deal";

export interface Scope {
  campaignId?: string | null;
  creatorId?: string | null;
  dealId?: string | null;
  includeTest?: boolean;
}

const scopeParams = (s: Scope) => ({
  campaign_id: s.campaignId ?? "",
  creator_id: s.creatorId ?? "",
  deal_id: s.dealId ?? "",
  include_test: s.includeTest ?? false,
});

export async function loadTotals(
  db: Db,
  range: { from: string; to: string },
  opts: Scope & { dim?: Dimension; bucket?: DateRange["bucket"] } = {},
): Promise<TotalsRow[]> {
  const { data, error } = await db.rpc("analytics_totals", {
    p: { from: range.from, to: range.to, dim: opts.dim ?? "all", bucket: opts.bucket ?? "", ...scopeParams(opts) },
  });
  if (error) throw new Error(error.message);
  return z.array(totalsRow).parse(data);
}

const spendRow = z.object({
  key: z.string().nullable(),
  label: z.string().nullable(),
  committed_paise: n,
  accrued_paise: n,
  accrued_to_date_paise: n,
  paid_paise: n,
  budget_paise: n.nullable(),
});
export type SpendRow = z.infer<typeof spendRow>;

export async function loadSpend(
  db: Db,
  range: { from: string; to: string },
  dim: "all" | "deal_model" | "campaign" | "creator",
  campaignId?: string | null,
): Promise<SpendRow[]> {
  const { data, error } = await db.rpc("analytics_spend", {
    p: { from: range.from, to: range.to, dim, campaign_id: campaignId ?? "" },
  });
  if (error) throw new Error(error.message);
  return z.array(spendRow).parse(data);
}

const health = z.object({
  active: n,
  dormant: n,
  new: n,
  new_previous: n,
  pipeline: z.record(z.string(), n),
});
export type Health = z.infer<typeof health>;

export async function loadHealth(db: Db, range: DateRange, includeTest = false): Promise<Health | null> {
  const { data, error } = await db.rpc("analytics_health", {
    p: {
      from: range.from,
      to: range.to,
      prev_from: range.previous.from,
      prev_to: range.previous.to,
      include_test: includeTest,
    },
  });
  if (error) throw new Error(error.message);
  return data === null ? null : health.parse(data);
}

const operations = z.object({
  overdue_deliverables: n,
  pending_reviews: n,
  pending_negotiations: n,
  contracts_expiring: n,
  payouts_due_paise: n,
  kyc_pending: n,
  fraud_flags: n,
});
export type Operations = z.infer<typeof operations>;

export async function loadOperations(db: Db, campaignId?: string | null): Promise<Operations | null> {
  const { data, error } = await db.rpc("analytics_operations", campaignId ? { p_campaign: campaignId } : {});
  if (error) throw new Error(error.message);
  return data === null ? null : operations.parse(data);
}

const creatorRow = z.object({
  creator_id: z.uuid(),
  name: z.string(),
  handle: z.string(),
  opt_in: z.boolean(),
  leads: n,
  qualified: n,
  enrolled: n,
  cost_paise: n,
  revenue_paise: n,
  due: n,
  on_time: n,
});
export type CreatorRow = z.infer<typeof creatorRow>;

export async function loadCreatorRows(db: Db, range: { from: string; to: string }, scope: Scope = {}) {
  const { data, error } = await db.rpc("analytics_creators", {
    p: {
      from: range.from,
      to: range.to,
      campaign_id: scope.campaignId ?? "",
      include_test: scope.includeTest ?? false,
    },
  });
  if (error) throw new Error(error.message);
  return z.array(creatorRow).parse(data);
}

const finance = z.object({
  liabilities_paise: n,
  confirmed_unpaid_paise: n,
  payable_paise: n,
  payouts: z.array(z.object({ at: z.string(), count: n, gross_paise: n, tds_paise: n, gst_paise: n, net_paise: n })),
  tds: z.array(z.object({ fy: z.string(), quarter: z.string(), section: z.string(), amount_paise: n, creators: n })),
});
export type FinanceAnalytics = z.infer<typeof finance>;

export async function loadFinanceAnalytics(db: Db, range: DateRange): Promise<FinanceAnalytics> {
  const { data, error } = await db.rpc("analytics_finance", {
    p: { from: range.from, to: range.to, bucket: range.bucket === "day" ? "week" : range.bucket },
  });
  if (error) throw new Error(error.message);
  return finance.parse(data);
}

const funnelCounts = z.object({ clicks: n, leads: n, qualified: n, allocated: n, applied: n, enrolled: n });
const creatorDashboard = z.object({
  current: funnelCounts,
  previous: funnelCounts,
  series: z.array(z.object({ at: z.string(), leads: n, enrolled: n })),
  content: z.array(
    z.object({
      deliverable_id: z.uuid().nullable(),
      link_id: z.uuid().nullable(),
      title: z.string().nullable(),
      platform: z.string().nullable(),
      leads: n,
      enrolled: n,
    }),
  ),
  programmes: z.array(z.object({ key: n.nullable(), label: z.string().nullable(), leads: n, enrolled: n })),
  platforms: z.array(z.object({ key: z.string().nullable(), leads: n, enrolled: n })),
  deals: z.array(
    z.object({
      id: z.uuid(),
      title: z.string(),
      status: z.string(),
      campaign_id: z.uuid().nullable(),
      campaign_name: z.string().nullable(),
      ends_on: z.string().nullable(),
      committed_paise: n.nullable(),
    }),
  ),
  fixed: z.object({ committed_paise: n, earned_paise: n }),
  actions: z.object({
    contracts: n,
    briefs: n,
    due_soon: n,
    overdue: n,
    changes_requested: n,
    metrics_due: n,
    invoices: n,
    kyc: z.boolean(),
  }),
  leaderboard: z.object({ rank: n, of: n, enrolled: n }).nullable(),
  opt_in: z.boolean(),
});
export type CreatorDashboard = z.infer<typeof creatorDashboard>;

export async function loadCreatorDashboard(db: Db, creatorId: string, range: DateRange): Promise<CreatorDashboard> {
  const { data, error } = await db.rpc("creator_dashboard", {
    p_creator: creatorId,
    p: {
      from: range.from,
      to: range.to,
      prev_from: range.previous.from,
      prev_to: range.previous.to,
      bucket: range.bucket,
    },
  });
  if (error) throw new Error(error.message);
  return creatorDashboard.parse(data);
}

export async function loadRefreshedAt(db: Db): Promise<string | null> {
  const { data, error } = await db.rpc("analytics_meta");
  if (error) throw new Error(error.message);
  return z.object({ refreshed_at: z.string().nullable() }).nullable().parse(data)?.refreshed_at ?? null;
}
