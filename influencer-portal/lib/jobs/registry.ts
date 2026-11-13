import "server-only";
import { contractFinalize } from "./contract-finalize";
import { creatorInvite } from "./creator-invite";
import { dealFromApplication } from "./deal-from-application";
import { digestPerson, digestRun } from "./digest";
import { ledgerRun } from "./ledger";
import { leadsBackfill, leadsRerun } from "./leads";
import { notifyDeliver } from "./notify-deliver";
import { payoutAdvice } from "./payout-advice";
import { penaltiesRefresh } from "./penalties-refresh";
import { scorecardsCreator, scorecardsRun } from "./scorecards";
import { storageRemove } from "./storage-remove";
import { webhookDeliver } from "./webhook-deliver";
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
  "payout.advice": payoutAdvice,
  "digest.run": digestRun,
  "digest.person": digestPerson,
  "webhook.deliver": webhookDeliver,
  "scorecards.run": scorecardsRun,
  "scorecards.creator": scorecardsCreator,
  "storage.remove": storageRemove,
  "creator.invite": creatorInvite,
};
