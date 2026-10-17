// A tier's commission uplift applied to a deal's terms (spec 15 "default commission uplift for new deals"): every
// commission rate and amount, including slab rates, is raised by the percentage, with the engine's exact money
// arithmetic (banker's rounding once per amount; percentages kept to two decimals and capped at 100). Fixed fees,
// caps and everything else stay as they are. Staff apply it in the deal builder; it is never applied on its own. Pure.
import { mulDiv, toBps } from "@/lib/compensation/money";
import type { CompConfig } from "@/lib/compensation/schema";

const raiseAmount = (paise: number, upliftBps: number) => mulDiv(paise, 10_000 + upliftBps, 10_000);
const raisePct = (pct: number, upliftBps: number) =>
  Math.min(100, mulDiv(toBps(pct), 10_000 + upliftBps, 10_000) / 100);

export function applyCommissionUplift(config: CompConfig, upliftPct: number): CompConfig {
  if (upliftPct <= 0) return config;
  const u = toBps(upliftPct);
  return {
    ...config,
    commission: config.commission.map((r) => ({
      ...r,
      basis:
        "amount_paise" in r.basis
          ? { ...r.basis, amount_paise: raiseAmount(r.basis.amount_paise, u) }
          : { ...r.basis, pct: raisePct(r.basis.pct, u) },
      ...(r.slabs
        ? {
            slabs: {
              ...r.slabs,
              tiers: r.slabs.tiers.map((t) => ({
                ...t,
                ...(t.amount_paise !== undefined ? { amount_paise: raiseAmount(t.amount_paise, u) } : {}),
                ...(t.pct !== undefined ? { pct: raisePct(t.pct, u) } : {}),
              })),
            },
          }
        : {}),
    })),
  };
}
