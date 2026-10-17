import "server-only";
// The app's entry point to the ledger runner (runner-core.ts) with the service-role client: the ledger.run job, the
// nightly re-runs and the staff dry run.
import { adminClient } from "@/lib/supabase/admin";
import { planDealWith, runDealWith, type RunResult } from "./runner-core";

export function runDeal(dealId: string, asOf = new Date().toISOString()): Promise<RunResult | null> {
  return runDealWith(adminClient(), dealId, asOf);
}

/** What the next run would write for a deal, without writing it (staff dry run against posted entries). */
export function previewDeal(dealId: string, asOf = new Date().toISOString()) {
  return planDealWith(adminClient(), dealId, asOf);
}
