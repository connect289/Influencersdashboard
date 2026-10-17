import "server-only";
import { z } from "zod";
import { runDeal } from "@/lib/ledger/runner";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ deal_id: z.uuid() });

/**
 * Replays a deal with the compensation engine and posts the difference to the ledger (enqueued by events that change
 * what a deal earns, by receipts and manual releases, and nightly for time-based confirmations).
 */
export const ledgerRun: JobHandler = async (job) => {
  const { deal_id } = payloadSchema.parse(job.payload);
  await runDeal(deal_id);
};
