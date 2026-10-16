/** Shapes the money functions return (b19, b20, b24), and the words the screens use for them. */
export type RateCalc = { pct?: number | null; base?: number | null; note?: string | null; tier?: unknown; amount?: number | null };
export type PartnerRate = { id: string; scope: string; rate_type: string; value: number | null; tiers: unknown; fee_base: string; valid_from: string | null; gst_inclusive: boolean };
export type PartnerSeen = { partner_id: number; name: string; rate: PartnerRate | null; computed?: RateCalc | null; offers_programme?: boolean };
export type CommissionLine = {
  id: number; kind: "booking" | "reversal" | "clawback" | "adjustment" | string; status: string; amount: number; tds: number; fee: number | null; base: number | null;
  rate: RateCalc | null; rate_source: string | null; rate_used: PartnerSeen | null; partners: PartnerSeen[]; override: Record<string, unknown> | null;
  reason: string | null; run_id: number | null; due_on: string | null; flagged: boolean; lead_id: number; student: string | null; programme: string | null;
  university: string | null; enrolled_on: string | null; enrollment_id: number; enrollment_status: string; counsellor_id: string; created_at: string;
  expected_settlement: string | null;
};
export type Tier = { from: number; to?: number | null; value: number };

export const LINE_STATUS: Record<string, { label: string; chip: string }> = {
  needs_rate: { label: "Needs a rate", chip: "breach" }, provisional: { label: "Provisional", chip: "soft" }, confirmed: { label: "Confirmed", chip: "soft" },
  due: { label: "Due", chip: "warm" }, settled: { label: "Settled", chip: "ok" }, void: { label: "Void", chip: "line" },
};
export const RATE_SOURCE: Record<string, string> = {
  partner: "highest partner rate", university_highest: "highest rate across the university", fallback: "university fallback", override: "override",
  none: "no rate found", reversal: "reversal", adjustment: "adjustment",
};
export const FEE_BASE: Record<string, string> = { first_year: "first-year fee", total: "total fee", amount_paid: "amount paid" };

/** "25% of ₹90,000" or "fixed ₹5,000" or "tiered", for one rate. */
export function rateText(r: { rate_type?: string; value?: number | null; fee_base?: string; tiers?: unknown } | null | undefined, inr: (n: number) => string): string {
  if (!r) return "–";
  if (r.rate_type === "percent") return `${Number(r.value)}% of the ${FEE_BASE[r.fee_base ?? "first_year"] ?? r.fee_base}`;
  if (r.rate_type === "fixed") return `fixed ${inr(Number(r.value))}`;
  if (r.rate_type === "tiered" && Array.isArray(r.tiers)) return `tiered: ${(r.tiers as Tier[]).map((t) => `${t.from}–${t.to ?? "∞"}% conv. → ${t.value}%`).join(", ")}`;
  return r.rate_type ?? "–";
}

/** "25% of ₹90,000 = ₹22,500" for what was actually computed on a line. */
export function calcText(c: RateCalc | null | undefined, inr: (n: number) => string): string {
  if (!c) return "–";
  if (c.pct !== null && c.pct !== undefined) return `${c.pct}% of ${inr(Number(c.base ?? 0))} = ${inr(Number(c.amount ?? 0))}`;
  return c.amount !== null && c.amount !== undefined ? `fixed ${inr(Number(c.amount))}` : "–";
}

/** Parses tier rows typed as "0-7:22.42, 7-9:20.42, 9-:18.42" (from-to % conversion : rate %). */
export function parseTiers(text: string): Tier[] | null {
  const parts = text.split(/[,\n]+/).map((s) => s.trim()).filter(Boolean);
  if (!parts.length) return null;
  const out: Tier[] = [];
  for (const p of parts) {
    const m = /^(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)?\s*:\s*(\d+(?:\.\d+)?)$/.exec(p);
    if (!m) return null;
    out.push({ from: Number(m[1]), to: m[2] === undefined ? null : Number(m[2]), value: Number(m[3]) });
  }
  out.sort((a, b) => a.from - b.from);
  for (let i = 1; i < out.length; i++) if (out[i - 1]!.to !== out[i]!.from) return null;
  return out[0]!.from === 0 && out[out.length - 1]!.to === null ? out : null;
}
