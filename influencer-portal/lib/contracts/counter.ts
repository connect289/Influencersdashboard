// Structured compensation counter-offers (spec 8.3): the creator proposes new values for the numbers in the deal's
// terms, never free text and never new rules. Each number has a stable key; applying a counter-offer returns a new,
// validated compensation config, which becomes the deal's terms when Eduwit accepts (or counters) it.
import { z } from "zod";
import { compConfig, FLAT_BASES, type CompConfig } from "@/lib/compensation/schema";

export type CounterKind = "amount" | "pct";
/** One negotiable number. Amounts are paise; percentages are percent with up to two decimals. */
export interface CounterItem {
  key: string;
  label: string;
  kind: CounterKind;
  value: number;
}

const KEY = /^(fixed|commission|floor|bonus|fee)\.([a-z0-9][a-z0-9_-]{0,39})(?:\.tier\.(\d{1,2}))?$/;

export const counterChange = z.object({
  key: z.string().regex(KEY),
  value: z.number().min(0).max(10_000_000_000_00),
});
export type CounterChange = z.infer<typeof counterChange>;

export const counterTerms = z
  .object({ changes: z.array(counterChange).min(1).max(50) })
  .refine((t) => new Set(t.changes.map((c) => c.key)).size === t.changes.length, "duplicate");
export type CounterTerms = z.infer<typeof counterTerms>;

/** Every number a counter-offer may change, in the order the terms list them. */
export function counterItems(c: CompConfig): CounterItem[] {
  const out: CounterItem[] = [];
  for (const f of c.fixed) {
    const per = f.basis === "retainer" ? " (per period)" : f.units > 1 ? " (per unit)" : "";
    out.push({
      key: `fixed.${f.id}`,
      label: `${f.label}${per}`,
      kind: "amount",
      value: f.amount_paise,
    });
  }
  for (const r of c.commission) {
    const flat = FLAT_BASES.includes(r.basis.type);
    if (r.slabs) {
      r.slabs.tiers.forEach((t, i) => {
        out.push({
          key: `commission.${r.id}.tier.${String(i)}`,
          label: `${r.label}: from unit ${String(t.from)}`,
          kind: flat ? "amount" : "pct",
          value: (flat ? t.amount_paise : t.pct) ?? 0,
        });
      });
    } else {
      const b = r.basis;
      out.push({
        key: `commission.${r.id}`,
        label: r.label,
        kind: "amount_paise" in b ? "amount" : "pct",
        value: "amount_paise" in b ? b.amount_paise : b.pct,
      });
    }
  }
  for (const fl of c.floors)
    out.push({ key: `floor.${fl.id}`, label: fl.label, kind: "amount", value: fl.amount_paise });
  for (const b of c.bonuses) {
    const a = b.amount;
    out.push({
      key: `bonus.${b.id}`,
      label: b.label,
      kind: a.type === "fixed" ? "amount" : "pct",
      value: a.type === "fixed" ? a.amount_paise : a.pct,
    });
  }
  for (const f of c.fees) out.push({ key: `fee.${f.id}`, label: f.label, kind: "amount", value: f.amount_paise });
  return out;
}

export type ApplyError = "unknown_item" | "invalid_value" | "no_change" | "invalid_config";
export type ApplyResult = { ok: true; config: CompConfig } | { ok: false; error: ApplyError; key?: string };

function validValue(kind: CounterKind, v: number): boolean {
  if (!Number.isFinite(v) || v < 0) return false;
  if (kind === "amount") return Number.isInteger(v);
  return v <= 100 && Math.abs(Math.round(v * 100) - v * 100) < 1e-9;
}

/** Splits a new total over amount-share milestones in proportion to the old shares (the remainder on the last). */
function rescale(shares: readonly number[], total: number): number[] {
  const old = shares.reduce((s, x) => s + x, 0);
  const out =
    old === 0 ? shares.map(() => Math.floor(total / shares.length)) : shares.map((x) => Math.floor((x * total) / old));
  const rest = total - out.reduce((s, x) => s + x, 0);
  if (out.length > 0) out[out.length - 1] = (out[out.length - 1] ?? 0) + rest;
  return out;
}

/** Applies a counter-offer to a config. Pure; the result is validated against the compensation schema. */
export function applyCounter(config: CompConfig, changes: readonly CounterChange[]): ApplyResult {
  const items = new Map(counterItems(config).map((i) => [i.key, i]));
  const next = structuredClone(config);
  let changed = false;
  for (const ch of changes) {
    const item = items.get(ch.key);
    const m = KEY.exec(ch.key);
    if (!item || !m) return { ok: false, error: "unknown_item", key: ch.key };
    if (!validValue(item.kind, ch.value)) return { ok: false, error: "invalid_value", key: ch.key };
    if (ch.value === item.value) continue;
    changed = true;
    const [, area, id, tier] = m;
    if (area === "fixed") {
      const f = next.fixed.find((x) => x.id === id);
      if (!f) return { ok: false, error: "unknown_item", key: ch.key };
      f.amount_paise = ch.value;
      if (f.basis !== "retainer" && f.milestones.every((ms) => ms.share.type === "amount")) {
        const shares = rescale(
          f.milestones.map((ms) => (ms.share.type === "amount" ? ms.share.amount_paise : 0)),
          ch.value * f.units,
        );
        f.milestones.forEach((ms, i) => {
          ms.share = { type: "amount", amount_paise: shares[i] ?? 0 };
        });
      }
    } else if (area === "commission") {
      const r = next.commission.find((x) => x.id === id);
      if (!r) return { ok: false, error: "unknown_item", key: ch.key };
      if (tier !== undefined) {
        const t = r.slabs?.tiers[Number(tier)];
        if (!t) return { ok: false, error: "unknown_item", key: ch.key };
        if (item.kind === "amount") t.amount_paise = ch.value;
        else t.pct = ch.value;
      } else if ("amount_paise" in r.basis) r.basis.amount_paise = ch.value;
      else r.basis.pct = ch.value;
    } else if (area === "floor") {
      const fl = next.floors.find((x) => x.id === id);
      if (!fl) return { ok: false, error: "unknown_item", key: ch.key };
      fl.amount_paise = ch.value;
    } else if (area === "bonus") {
      const b = next.bonuses.find((x) => x.id === id);
      if (!b) return { ok: false, error: "unknown_item", key: ch.key };
      if (b.amount.type === "fixed") b.amount.amount_paise = ch.value;
      else b.amount.pct = ch.value;
    } else {
      const f = next.fees.find((x) => x.id === id);
      if (!f) return { ok: false, error: "unknown_item", key: ch.key };
      f.amount_paise = ch.value;
    }
  }
  if (!changed) return { ok: false, error: "no_change" };
  const parsed = compConfig.safeParse(next);
  return parsed.success ? { ok: true, config: parsed.data } : { ok: false, error: "invalid_config" };
}

export interface CounterLine {
  key: string;
  label: string;
  kind: CounterKind;
  from: number | null;
  to: number;
}

/** A counter-offer as "label: from → to" lines against a config (from is null when the item no longer exists). */
export function describeCounter(config: CompConfig, changes: readonly CounterChange[]): CounterLine[] {
  const items = new Map(counterItems(config).map((i) => [i.key, i]));
  return changes.map((ch) => {
    const item = items.get(ch.key);
    return {
      key: ch.key,
      label: item?.label ?? ch.key,
      kind: item?.kind ?? "amount",
      from: item ? item.value : null,
      to: ch.value,
    };
  });
}
