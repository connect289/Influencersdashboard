import "server-only";
import { z } from "zod";
import { offerTerms } from "@/lib/campaigns/schemas";
import { compConfig } from "@/lib/compensation/schema";
import { setupContentForDeal } from "@/lib/content/setup";
import { draftContractForDeal } from "@/lib/contracts/generate";
import { log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";
import { configFromTerms } from "./terms";

const source = z.object({
  application_id: z.uuid(),
  status: z.string(),
  terms: z.unknown(),
  preset_config: z.unknown().nullable(),
  has_deal: z.boolean(),
});

/**
 * Creates the deal for an accepted campaign application (idempotent): the campaign's preset with the agreed terms on
 * top, then its draft contract and its draft brief with deliverables. Runs as the service role because it is system work that follows a completed acceptance; the database checks
 * the application is accepted and refuses a second deal.
 */
export async function createDealFromApplication(applicationId: string): Promise<string | null> {
  const db = adminClient();
  const { data, error } = await db.rpc("application_deal_source", { p_app: applicationId });
  if (error) throw new Error(error.message);
  const src = source.nullable().parse(data);
  if (!src || src.status !== "accepted") return null;
  const preset = src.preset_config === null ? null : compConfig.parse(src.preset_config);
  const config = configFromTerms(preset, offerTerms.parse(src.terms));
  const { data: dealId, error: e2 } = await db.rpc("deal_from_application", { p_app: applicationId, p_config: config });
  if (e2) throw new Error(e2.message);
  // The draft contract follows the deal; a failure here leaves the deal intact and staff generate it by hand.
  await draftContractForDeal(db, dealId).catch((e: unknown) =>
    log.warn("contracts.draft_failed", { deal_id: dealId, error: e instanceof Error ? e.message : String(e) }),
  );
  // Likewise the draft brief and deliverables (staff publish the brief once it is reviewed).
  await setupContentForDeal(db, dealId).catch((e: unknown) =>
    log.warn("content.setup_failed", { deal_id: dealId, error: e instanceof Error ? e.message : String(e) }),
  );
  return dealId;
}
