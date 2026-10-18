// One deal through the engine and onto the ledger (spec 6.3, D-63): replay the deal's facts, diff the desired lines
// against what is posted, and return the writes. A reversal of an entry that an open payout batch holds waits for the
// batch to settle (it is reported as deferred and picked up by the next run). A reversal records how much of the
// cancelled entry was already paid, which future payouts recover. Pure.
import {
  computeLedger,
  type DealVersion,
  type EngineContext,
  type EngineResult,
  type LedgerLine,
} from "@/lib/compensation/engine";
import { baseKey, diffLedger, type PostedLine } from "@/lib/compensation/diff";
import type { TdsComponent } from "@/lib/compensation/tax";
import { dealEvents, type DealFacts } from "./facts";
import { componentForType } from "./payout";

export interface PostedEntry extends PostedLine {
  paid_paise: number;
  in_open_batch: boolean;
}

export interface LedgerWrite extends LedgerLine {
  tds_component: TdsComponent;
}

export interface DealPlan {
  result: EngineResult;
  create: LedgerWrite[];
  confirm: { key: string; confirmed_paise: number }[];
  reverse: { key: string; reason: "changed" | "obsolete"; recover_paise: number }[];
  deferred: string[];
  unchanged: number;
}

export function planDeal(input: {
  deal: { id: string; starts_on: string; ends_on: string | null; campaign_ends_on: string | null };
  versions: DealVersion[];
  facts: DealFacts;
  posted: readonly PostedEntry[];
  as_of: string;
  context: EngineContext;
}): DealPlan {
  const result = computeLedger({
    deal: input.deal,
    versions: input.versions,
    events: dealEvents(input.facts),
    as_of: input.as_of,
    context: input.context,
  });
  const diff = diffLedger(result.lines, input.posted);
  const byKey = new Map(input.posted.map((p) => [p.key, p]));
  const deferred = new Set(diff.reverse.filter((r) => byKey.get(r.key)?.in_open_batch === true).map((r) => r.key));
  // The re-post that replaces a deferred reversal waits with it, so the deal never holds both lines at once.
  const waiting = new Set([...deferred].map(baseKey));
  return {
    result,
    create: diff.create
      .filter((c) => !waiting.has(baseKey(c.key)))
      .map((c) => ({ ...c, tds_component: componentForType(c.type) })),
    confirm: diff.confirm.filter((c) => !deferred.has(c.key)),
    reverse: diff.reverse
      .filter((r) => !deferred.has(r.key))
      .map((r) => ({ ...r, recover_paise: byKey.get(r.key)?.paid_paise ?? 0 })),
    deferred: [...deferred],
    unchanged: diff.unchanged,
  };
}
