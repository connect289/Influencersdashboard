// Committed spend for a deal (spec 12 "Spend: committed"): what the creator earns over the deal's term with no leads
// at all, so fixed fees, milestones, retainers, minimum guarantees and extra fees, from the compensation engine's own
// zero-performance simulation (every agreed deliverable delivered on time). Before tax. Pure.
import type { EngineContext } from "@/lib/compensation/engine";
import type { CompConfig } from "@/lib/compensation/schema";
import { scenario, simulate } from "@/lib/compensation/simulator";

/** Whole months the deal runs (1–24); an open-ended deal counts as 12. */
export function termMonths(startsOn: string, endsOn: string | null): number {
  if (!endsOn) return 12;
  // Count to the day after the end, so 15 Oct – 14 Nov is exactly one month and 1 Oct – 31 Dec is three.
  const after = new Date(Date.parse(`${endsOn}T00:00:00Z`) + 86_400_000).toISOString().slice(0, 10);
  const [ys, ms, ds] = startsOn.split("-").map(Number) as [number, number, number];
  const [ye, me, de] = after.split("-").map(Number) as [number, number, number];
  const months = (ye - ys) * 12 + (me - ms) + (de > ds ? 1 : 0);
  return Math.min(Math.max(months, 1), 24);
}

export function committedPaise(
  config: CompConfig,
  startsOn: string,
  endsOn: string | null,
  context: EngineContext,
): number {
  const r = simulate(config, scenario.parse({ months: termMonths(startsOn, endsOn) }), {
    starts_on: startsOn,
    context,
    sections: [],
    gst_rate_bps: 0,
  });
  return Math.max(r.gross_paise, 0);
}
