// Exact money arithmetic for the compensation engine. Amounts are integer paise; percentages are basis points
// (1% = 100 bps) so nothing passes through floating point. Rounding is banker's rounding (half to even), applied once
// per line item (spec 2.4; setting compensation.defaults.rounding).

export type Paise = number;
export type Bps = number;

export class MoneyError extends Error {}

function assertInt(n: number, what: string): void {
  if (!Number.isSafeInteger(n))
    throw new MoneyError(`${what} must be a safe integer, got ${String(n)}`);
}

/** a × num / den, rounded half to even. All arguments integers; den > 0. */
export function mulDiv(a: number, num: number, den: number): Paise {
  assertInt(a, "amount");
  assertInt(num, "numerator");
  assertInt(den, "denominator");
  if (den <= 0) throw new MoneyError("denominator must be positive");
  const p = BigInt(a) * BigInt(num);
  const d = BigInt(den);
  let q = p / d;
  let r = p % d;
  if (r < 0n) {
    // Floor division for negatives, so the half-to-even rule below is symmetric.
    q -= 1n;
    r += d;
  }
  const twice = 2n * r;
  if (twice > d || (twice === d && q % 2n !== 0n)) q += 1n;
  const out = Number(q);
  assertInt(out, "result");
  return out;
}

/** amount × bps / 10,000 (a percentage of an amount). */
export function pctOf(amount: Paise, bps: Bps): Paise {
  return mulDiv(amount, bps, 10_000);
}

/** A percentage with up to two decimals (e.g. 12.5) → basis points (1250). */
export function toBps(pct: number): Bps {
  const bps = Math.round(pct * 100);
  if (Math.abs(bps / 100 - pct) > 1e-9)
    throw new MoneyError(`at most two decimals in a percentage: ${String(pct)}`);
  return bps;
}

/** The GST-exclusive part of a GST-inclusive amount: gross × 10,000 / (10,000 + rate). */
export function netOfGst(gross: Paise, gstBps: Bps): Paise {
  return mulDiv(gross, 10_000, 10_000 + gstBps);
}

export function sum(xs: readonly number[]): number {
  let s = 0;
  for (const x of xs) s += x;
  assertInt(s, "sum");
  return s;
}

/**
 * Split `total` into parts proportional to `weights` so the parts add up to `total` exactly (largest remainder;
 * ties go to the earlier part). Used for percentage milestone schedules.
 */
export function allocate(total: Paise, weights: readonly number[]): Paise[] {
  assertInt(total, "total");
  const w = weights.map((x) => {
    assertInt(x, "weight");
    if (x < 0) throw new MoneyError("weights must not be negative");
    return BigInt(x);
  });
  const wSum = w.reduce((a, b) => a + b, 0n);
  if (wSum === 0n) return weights.map(() => 0);
  const t = BigInt(total);
  const base = w.map((x) => (t * x) / wSum);
  const rem = w.map((x, i) => t * x - (base[i] ?? 0n) * wSum);
  let left = t - base.reduce((a, b) => a + b, 0n);
  const order = rem
    .map((r, i) => ({ r, i }))
    .sort((a, b) => (b.r > a.r ? 1 : b.r < a.r ? -1 : a.i - b.i));
  for (const { i } of order) {
    if (left <= 0n) break;
    base[i] = (base[i] ?? 0n) + 1n;
    left -= 1n;
  }
  return base.map(Number);
}
