// DPDP workflows (spec 16): what a creator's data export contains, and what a deletion request does. Deletion removes
// or anonymises everything that is only there to run the programme with them, but keeps financial and contract records
// (ledger, payouts, invoices, TDS, signed contracts and the KYC needed for them) until the retention period after the
// last such record ends (setting retention.privacy, at least 8 years), when the nightly job purges them. Pure.

/** Sections of the export, in order (each is a JSON file in the archive). */
export const EXPORT_SECTIONS = [
  "profile",
  "platforms",
  "agency_links",
  "consents",
  "applications",
  "deals",
  "contracts",
  "deliverables",
  "links",
  "leads",
  "earnings",
  "payouts",
  "messages",
  "notifications",
] as const;
export type ExportSection = (typeof EXPORT_SECTIONS)[number];

export const ERASED = ["profile", "platforms", "media_kit", "avatar", "notification_preferences", "messages"] as const;
export const RETAINED = ["ledger", "payouts", "invoices", "tds", "contracts", "kyc"] as const;

export interface DeletionFacts {
  /** ISO date of the creator's last financial or contract record (ledger line, payout, signed contract), if any. */
  last_record_on: string | null;
  /** Deals not yet completed, terminated or expired. */
  open_deals: number;
  /** Money still owed either way (payable or in a batch), in paise. */
  balance_paise: number;
  retention_years: number;
  today: string;
}

export interface DeletionPlan {
  /** Whether the request can be carried out now, or why not. */
  blocked: null | "open_deals" | "balance_due";
  erase: readonly (typeof ERASED)[number][];
  retain: readonly (typeof RETAINED)[number][];
  /** When the retained records are purged (ISO date), or null when there are none. */
  purge_on: string | null;
}

export function addYears(iso: string, years: number): string {
  const [y, m, d] = iso.split("-").map(Number) as [number, number, number];
  const target = new Date(Date.UTC(y + years, m - 1, d));
  // 29 Feb + n years falls back to 28 Feb rather than rolling into March.
  if (target.getUTCMonth() !== m - 1) target.setUTCDate(0);
  return target.toISOString().slice(0, 10);
}

export function deletionPlan(f: DeletionFacts): DeletionPlan {
  const blocked = f.open_deals > 0 ? "open_deals" : f.balance_paise !== 0 ? "balance_due" : null;
  const purge_on = f.last_record_on ? addYears(f.last_record_on, f.retention_years) : null;
  return { blocked, erase: ERASED, retain: purge_on ? RETAINED : [], purge_on };
}

/** Clicks older than this ISO timestamp lose their IP and user agent (retention.privacy.click_anonymise_days). */
export function anonymiseBefore(now: Date, days: number): string {
  return new Date(now.getTime() - days * 86_400_000).toISOString();
}
