import "server-only";
import { z } from "zod";
import { createDealFromApplication } from "@/lib/deals/from-application";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ application_id: z.uuid() });

/** Safety net for deal creation after an accepted offer (the accept action normally creates it at once). */
export const dealFromApplication: JobHandler = async (job) => {
  const { application_id } = payloadSchema.parse(job.payload);
  await createDealFromApplication(application_id);
};
