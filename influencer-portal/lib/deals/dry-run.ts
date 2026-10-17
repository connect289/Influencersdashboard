// Amendment dry-run (spec 6.3): what would change if the working copy took effect at `effective_from`. Pure.
// Both ledgers are replayed over the same event stream (a scenario projected to the deal's end, since real events
// arrive with the Phase 7 runner) and compared line by line on rule + subject + kind, so a line that only moves to
// the new version's key but keeps its amount is not a change.
import {
  computeLedger,
  type DealVersion,
  type EngineContext,
  type LedgerLine,
} from "@/lib/compensation/engine";
import { addDays, istMidnight } from "@/lib/compensation/events";
import type { Paise } from "@/lib/compensation/money";
import type { CompConfig } from "@/lib/compensation/schema";
import { scenarioEvents, simulationConfig, type Scenario } from "@/lib/compensation/simulator";

export interface DryRunInput {
  deal: { id: string; starts_on: string; ends_on: string | null };
  /** Accepted versions (the terms in force), oldest first. */
  versions: DealVersion[];
  draft: { config: CompConfig; effective_from: string };
  scenario: Scenario;
  context: EngineContext;
}

export interface DryRunChange {
  /** "<rule>:<subject>:<kind>" (the ledger key without its version). */
  key: string;
  type: LedgerLine["type"];
  rule_id: string;
  subject: string;
  /** Signed amounts (credit positive); null when the line exists on one side only. */
  before_paise: Paise | null;
  after_paise: Paise | null;
}

export interface DryRunResult {
  changes: DryRunChange[];
  before: { net_paise: Paise; lines: number };
  after: { net_paise: Paise; lines: number };
  /** Net change for the creator (after − before). */
  delta_paise: Paise;
  as_of: string;
}

const signed = (l: LedgerLine) => (l.direction === "credit" ? l.amount_paise : -l.amount_paise);
const net = (lines: readonly LedgerLine[]) => lines.reduce((s, l) => s + signed(l), 0);
const withoutVersion = (key: string) => key.slice(key.indexOf(":") + 1);

function compare(before: readonly LedgerLine[], after: readonly LedgerLine[]): DryRunChange[] {
  const b = new Map(before.map((l) => [withoutVersion(l.key), l]));
  const a = new Map(after.map((l) => [withoutVersion(l.key), l]));
  const out: DryRunChange[] = [];
  for (const key of new Set([...b.keys(), ...a.keys()])) {
    const x = b.get(key);
    const y = a.get(key);
    const bp = x ? signed(x) : null;
    const ap = y ? signed(y) : null;
    if (bp === ap) continue;
    const l = (y ?? x) as LedgerLine;
    out.push({
      key,
      type: l.type,
      rule_id: l.rule_id,
      subject: l.subject,
      before_paise: bp,
      after_paise: ap,
    });
  }
  return out;
}

export function dryRun(input: DryRunInput): DryRunResult {
  const months = input.deal.ends_on
    ? Math.max(
        1,
        Math.min(
          24,
          Math.ceil(
            (Date.parse(input.deal.ends_on) - Date.parse(input.deal.starts_on)) / (30 * 86_400_000),
          ),
        ),
      )
    : input.scenario.months;
  const s = { ...input.scenario, months };
  const latest = input.versions.at(-1);
  if (!latest) throw new Error("a dry-run needs the current terms");
  const { events, ends_on } = scenarioEvents(
    simulationConfig(latest.config),
    s,
    input.deal.starts_on,
  );
  const endsOn = input.deal.ends_on ?? ends_on;
  const asOf = istMidnight(addDays(endsOn, 60));
  const run = (versions: DealVersion[]) =>
    computeLedger({
      deal: {
        id: input.deal.id,
        starts_on: input.deal.starts_on,
        ends_on: endsOn,
        campaign_ends_on: endsOn,
      },
      versions: versions.map((v) => ({ ...v, config: simulationConfig(v.config) })),
      events,
      as_of: asOf,
      context: input.context,
    });
  const before = run(input.versions);
  const after = run([
    ...input.versions,
    { id: "amendment", effective_from: input.draft.effective_from, config: input.draft.config },
  ]);
  return {
    changes: compare(before.lines, after.lines),
    before: { net_paise: net(before.lines), lines: before.lines.length },
    after: { net_paise: net(after.lines), lines: after.lines.length },
    delta_paise: net(after.lines) - net(before.lines),
    as_of: asOf,
  };
}
