import "server-only";
import { contractFinalize } from "./contract-finalize";
import { dealFromApplication } from "./deal-from-application";
import { notifyDeliver } from "./notify-deliver";
import type { JobHandler } from "./types";

/** Job kind → handler. Later phases register theirs here. */
export const JOB_HANDLERS: Record<string, JobHandler> = {
  "notify.deliver": notifyDeliver,
  "deal.from_application": dealFromApplication,
  "contract.finalize": contractFinalize,
};
