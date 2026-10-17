import "server-only";
import { contractFinalize } from "./contract-finalize";
import { dealFromApplication } from "./deal-from-application";
import { ledgerRun } from "./ledger";
import { leadsBackfill, leadsRerun } from "./leads";
import { notifyDeliver } from "./notify-deliver";
import { penaltiesRefresh } from "./penalties-refresh";
import type { JobHandler } from "./types";

/** Job kind → handler. Later phases register theirs here. */
export const JOB_HANDLERS: Record<string, JobHandler> = {
  "notify.deliver": notifyDeliver,
  "deal.from_application": dealFromApplication,
  "contract.finalize": contractFinalize,
  "penalties.refresh": penaltiesRefresh,
  "leads.rerun": leadsRerun,
  "leads.backfill": leadsBackfill,
  "ledger.run": ledgerRun,
};
