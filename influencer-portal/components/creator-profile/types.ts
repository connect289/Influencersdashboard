import type { Database } from "@/lib/database.types";

type Tables = Database["inf"]["Tables"];
export type CreatorRow = Tables["creators"]["Row"];
export type PlatformRow = Tables["creator_platforms"]["Row"];
export type RateCardRow = Tables["creator_rate_cards"]["Row"];
export type PortfolioRow = Tables["creator_portfolio"]["Row"];
export type ContactRow = Pick<
  Tables["creator_contacts"]["Row"],
  "id" | "kind" | "label" | "phone_last2" | "created_at"
>;

/** The masked KYC shape returned by inf.kyc_view(). */
export interface KycView {
  exists: boolean;
  status: "pending" | "submitted" | "verified" | "rejected";
  rejection_reason?: string | null;
  pan_masked?: string | null;
  name_on_pan?: string | null;
  gst_status?: "unregistered" | "registered" | "composition";
  gstin?: string | null;
  gstin_verified?: boolean;
  bank_masked?: string | null;
  ifsc?: string | null;
  account_holder?: string | null;
  has_proof?: boolean;
  submitted_at?: string | null;
  verified_at?: string | null;
}
