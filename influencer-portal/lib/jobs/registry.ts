import "server-only";
import { notifyDeliver } from "./notify-deliver";
import type { JobHandler } from "./types";

/** Job kind → handler. Later phases register theirs here. */
export const JOB_HANDLERS: Record<string, JobHandler> = {
  "notify.deliver": notifyDeliver,
};
