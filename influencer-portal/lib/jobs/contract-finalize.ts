import "server-only";
import { z } from "zod";
import { finalizeContract } from "@/lib/contracts/finalize";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ contract_id: z.uuid() });

/** Safety net for the signed PDF after a countersignature (the signing action normally builds it at once). */
export const contractFinalize: JobHandler = async (job) => {
  const { contract_id } = payloadSchema.parse(job.payload);
  await finalizeContract(contract_id);
};
