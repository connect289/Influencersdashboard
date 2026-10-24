import { z } from "zod";

// Which model a task runs on, and what it costs (spec §11). Claude only (owner, 24 Oct; D-004). The tier comes from the
// task's hint or the routing table, the model from the tier, with the fallback tier when a tier has no model. A model
// without a price in ai.prices is never called: its spend could not be counted against the caps (D-075).

export const TIERS = ["quick", "regular", "deep"] as const;
export type Tier = (typeof TIERS)[number];
export type Provider = "anthropic";
export type Effort = "low" | "medium" | "high" | "xhigh" | "max";

export const TASK_KINDS = [
  "classify",
  "triage",
  "explain",
  "brief",
  "propose_fix",
  "propose_feature",
  "ask",
  "test_author",
] as const;
export type TaskKind = (typeof TASK_KINDS)[number];

const tier = z.enum(TIERS);
const perTier = <T extends z.ZodType>(t: T) => z.object({ quick: t, regular: t, deep: t });
const price = z.object({
  input: z.number().min(0),
  output: z.number().min(0),
  cache_read: z.number().min(0).default(0),
  cache_write: z.number().min(0).default(0),
});
export type Price = z.infer<typeof price>;

export const aiSettingsSchema = z.object({
  models: perTier(z.string().min(1).nullable()),
  effort: perTier(z.enum(["low", "medium", "high", "xhigh", "max"]).nullable())
    .partial()
    .default({}),
  prices: z.record(z.string(), price.nullable()).default({}),
  fallback_when_model_missing: tier.nullable().default("regular"),
  routing: z.record(z.string(), tier),
  daily_cap_inr: z.number().min(0),
  per_task_cap_inr: z.number().min(0),
  queue_non_triage_at_pct: z.number().min(0).max(100),
  usd_inr: z.number().positive(),
  allow_message_excerpts: z.boolean().default(false),
  /** A model asked once more when the routed one declines (a refusal): it must have a price too. */
  refusal_fallback: z.string().min(1).nullable().default(null),
});
export type AiSettings = z.infer<typeof aiSettingsSchema>;

export type Route = { tier: Tier; provider: Provider; model: string; price: Price; effort: Effort | null };
export type RouteError = { error: string; detail: string };

/** The tier, model and price for a task, or why there is none (never a guess). */
export function route(ai: AiSettings, kind: TaskKind, hint: Tier | null): Route | RouteError {
  const wanted: Tier = hint ?? ai.routing[kind] ?? "regular";
  const tried: Tier[] = [wanted];
  if (ai.fallback_when_model_missing && ai.fallback_when_model_missing !== wanted) {
    tried.push(ai.fallback_when_model_missing);
  }
  for (const t of tried) {
    const model = ai.models[t];
    if (!model) continue;
    const pr = ai.prices[model];
    if (!pr) {
      return {
        error: "no_price",
        detail: `model ${model} (${t} tier) has no price in Settings → AI (prices, USD per million tokens)`,
      };
    }
    return { tier: t, provider: "anthropic", model, price: pr, effort: ai.effort[t] ?? null };
  }
  return { error: "no_model", detail: `no model for the ${tried.join(" or ")} tier in Settings → AI` };
}

/** The refusal fallback as a route on the same tier, or null when none is set, priced and different. */
export function fallbackRoute(ai: AiSettings, r: Route): Route | null {
  const model = ai.refusal_fallback;
  const pr = model ? ai.prices[model] : null;
  return model && pr && model !== r.model ? { ...r, model, price: pr } : null;
}

export type Usage = { input: number; output: number; cacheRead: number; cacheWrite: number };

/** Dollars and rupees for one call; rupees rounded up to the paisa, so the caps are never undercounted. */
export function costOf(p: Price, u: Usage, usdInr: number): { usd: number; inr: number } {
  const usd =
    (u.input * p.input + u.output * p.output + u.cacheRead * p.cache_read + u.cacheWrite * p.cache_write) / 1e6;
  return { usd: Math.round(usd * 1e5) / 1e5, inr: Math.max(0, Math.ceil(usd * usdInr * 100 - 1e-9)) / 100 };
}

/**
 * The most a call can cost: every input token at its dearest rate (2 characters a token, rounded up) and the whole
 * output allowance spent. The worker refuses a call whose worst case is above the per-task cap or what is left today.
 */
export function worstCaseInr(p: Price, inputChars: number, maxTokens: number, usdInr: number): number {
  // JSON full of digits, ids and timestamps runs near 2 characters a token, so 2 is the bound (review M6).
  const input = Math.ceil(inputChars / 2);
  // An input written to the cache costs more than a plain one; count whichever is dearer.
  const asWrite = p.cache_write > p.input;
  return costOf(
    p,
    { input: asWrite ? 0 : input, output: maxTokens, cacheRead: 0, cacheWrite: asWrite ? input : 0 },
    usdInr,
  ).inr;
}
