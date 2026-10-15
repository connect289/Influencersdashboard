import { parseCsv } from "@/lib/statement-csv";

/**
 * Ad spend exports (spec B13.2): Meta Ads Manager ("Export table data", broken down by day) and Google Ads (a campaign
 * report by day) as CSV. Headers differ by platform and language of the export, so they are matched loosely; Google's
 * title lines above the header are skipped. Amounts keep their digits and decimal point only.
 */
export type AdRow = { day: string; campaign_id: string; campaign: string; adset: string; spend: string; impressions: string; clicks: string; leads: string; currency: string };

const COLS: Record<keyof AdRow, RegExp> = {
  day: /^(day|date|reporting starts)$/i,
  campaign_id: /^campaign id$/i,
  campaign: /^(campaign name|campaign)$/i,
  adset: /^(ad set name|ad group|ad group name)$/i,
  spend: /^(amount spent( \([a-z]{3}\))?|cost|spend)$/i,
  impressions: /^(impressions|impr\.?)$/i,
  clicks: /^(link clicks|clicks|clicks \(all\))$/i,
  leads: /^(leads|results|conversions|on-facebook leads)$/i,
  currency: /^(currency|currency code)$/i,
};
const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

/** YYYY-MM-DD from the date shapes the exports use; null when unreadable. */
export function adDay(s: string): string | null {
  const v = s.trim();
  let m = /^(\d{4})-(\d{2})-(\d{2})/.exec(v);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  m = /^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/.exec(v);
  if (m) return `${m[3]}-${m[2]!.padStart(2, "0")}-${m[1]!.padStart(2, "0")}`;
  m = /^([A-Za-z]{3})[a-z]* (\d{1,2}), (\d{4})$/.exec(v);
  if (m && MONTHS.includes(m[1]!.toLowerCase())) return `${m[3]}-${String(MONTHS.indexOf(m[1]!.toLowerCase()) + 1).padStart(2, "0")}-${m[2]!.padStart(2, "0")}`;
  m = /^(\d{1,2}) ([A-Za-z]{3})[a-z]* (\d{4})$/.exec(v);
  if (m && MONTHS.includes(m[2]!.toLowerCase())) return `${m[3]}-${String(MONTHS.indexOf(m[2]!.toLowerCase()) + 1).padStart(2, "0")}-${m[1]!.padStart(2, "0")}`;
  return null;
}
const amount = (s: string | undefined) => (s ?? "").replace(/[^0-9.]/g, "") || "0";

export function adRows(text: string): { rows: AdRow[]; missing: string[]; skipped: number; guess: "meta" | "google" | null } {
  const table = parseCsv(text);
  const headAt = table.findIndex((r) => r.some((c) => COLS.day.test(c.trim())) && r.some((c) => COLS.campaign.test(c.trim()) || COLS.campaign_id.test(c.trim())) && r.some((c) => COLS.spend.test(c.trim())));
  if (headAt < 0) return { rows: [], missing: ["a header with a day, a campaign and the amount spent"], skipped: 0, guess: null };
  const head = table[headAt]!.map((h) => h.trim());
  const idx = Object.fromEntries((Object.keys(COLS) as (keyof AdRow)[]).map((k) => [k, head.findIndex((h) => COLS[k].test(h))])) as Record<keyof AdRow, number>;
  const spendHead = head[idx.spend] ?? "";
  const headCurrency = /\(([A-Z]{3})\)/.exec(spendHead)?.[1] ?? null;
  const guess = /amount spent/i.test(spendHead) ? "meta" : /^cost$/i.test(spendHead) ? "google" : null;
  const get = (r: string[], k: keyof AdRow) => (idx[k] >= 0 ? (r[idx[k]] ?? "").trim() : "");
  let skipped = 0;
  const rows: AdRow[] = [];
  for (const r of table.slice(headAt + 1)) {
    const day = adDay(get(r, "day"));
    const campaign = get(r, "campaign"), campaignId = get(r, "campaign_id");
    if (!day || (!campaign && !campaignId) || /^total/i.test(campaign) || /^total/i.test(get(r, "day"))) { skipped++; continue; }
    rows.push({ day, campaign_id: campaignId || campaign, campaign: campaign || campaignId, adset: get(r, "adset"), spend: amount(get(r, "spend")),
      impressions: amount(get(r, "impressions")).split(".")[0]!, clicks: amount(get(r, "clicks")).split(".")[0]!, leads: amount(get(r, "leads")).split(".")[0]!,
      currency: (get(r, "currency") || headCurrency || "INR").toUpperCase() });
  }
  return { rows, missing: [], skipped, guess };
}
