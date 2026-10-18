import "server-only";
import { z } from "zod";
import { runDeal } from "@/lib/ledger/runner";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ deal_id: z.uuid() });

/**
 * Recomputes a deal after a deliverable goes live, is cancelled or fails its disclosure check. Since Phase 7 the full
 * ledger run does this: it syncs penalty proposals (they still wait for a person to approve them) along with the
 * deal's ledger.
 */
export const penaltiesRefresh: JobHandler = async (job) => {
  const { deal_id } = payloadSchema.parse(job.payload);
  await runDeal(deal_id);
};
