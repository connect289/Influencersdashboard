import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import type { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";

/**
 * One Claude call for Phase 3 (spec B13.4, B8.3, B18): the brief, Ask, Explain and the insights feed.
 * - The daily spend cap is checked first (b2c.ai_budget) and every call is logged with its tokens and cost (b2c.ai_log).
 * - Only what the caller passes is sent: aggregates, the metric catalogue, or the brief's scrubbed input. Never a phone
 *   number or an email address (the callers scrub; lib/scrub.ts checks again).
 * - Structured output: the answer is parsed against a zod schema, so a spec or a brief is data, never free text or SQL.
 * - Refusals: the recommended server-side fallback is on for the models that take it; a refusal that survives is an
 *   error the screen shows ("Claude declined"), never a guess.
 */
export type Purpose = "ask" | "explain" | "insights" | "brief";

export class AiUnavailable extends Error {}

/** Whether a key is set; the jobs skip their Claude parts without one. */
export function aiConfigured(): boolean {
  return !!process.env.ANTHROPIC_API_KEY;
}

const FALLBACK_MODELS = new Set(["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]);

type Budget = { allowed: boolean; spent_inr: number; cap_inr: number; model: string };

export async function aiBudget(purpose: Purpose): Promise<Budget> {
  const { data, error } = await adminClient().rpc("ai_budget", { p_purpose: purpose });
  if (error) throw new Error(`ai_budget: ${error.message}`);
  return data as Budget;
}

export async function callClaude<S extends z.ZodType>(opts: {
  purpose: Purpose;
  schema: S;
  system: string;
  user: string;
  userId?: string | null;
  leadId?: number | null;
  question?: string | null;
  maxTokens?: number;
  effort?: "low" | "medium" | "high";
}): Promise<{ output: z.infer<S>; model: string; logId: number | null }> {
  if (!process.env.ANTHROPIC_API_KEY) throw new AiUnavailable("Claude is not set up yet (ANTHROPIC_API_KEY).");
  const budget = await aiBudget(opts.purpose);
  if (!budget.allowed) throw new AiUnavailable(`Today's AI budget is used up (₹${budget.spent_inr} of ₹${budget.cap_inr}). It resets at midnight IST.`);
  const model = budget.model || "claude-sonnet-5-5";
  const client = new Anthropic({ maxRetries: 1, timeout: 60_000 });
  const started = Date.now();
  const log = async (p: Record<string, unknown>) => {
    const { data } = await adminClient().rpc("ai_log", {
      p: { purpose: opts.purpose, model, user_id: opts.userId ?? null, lead_id: opts.leadId ?? null, question: opts.question ?? null, ms: Date.now() - started, ...p },
    });
    return (data as number | null) ?? null;
  };
  try {
    const res = await client.beta.messages.parse({
      model,
      max_tokens: opts.maxTokens ?? 4000,
      system: opts.system,
      messages: [{ role: "user", content: opts.user }],
      output_config: { format: betaZodOutputFormat(opts.schema), effort: opts.effort ?? "low" },
      ...(FALLBACK_MODELS.has(model) ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const } : {}),
    });
    const usage = { input_tokens: res.usage.input_tokens, output_tokens: res.usage.output_tokens };
    if (res.stop_reason === "refusal" || !res.parsed_output) {
      await log({ ...usage, ok: false, error: res.stop_reason === "refusal" ? "refusal" : `no output (${res.stop_reason})` });
      throw new AiUnavailable(res.stop_reason === "refusal" ? "Claude declined this request." : "Claude did not finish an answer. Try again.");
    }
    const logId = await log(usage);
    return { output: res.parsed_output as z.infer<S>, model: res.model, logId };
  } catch (e) {
    if (e instanceof AiUnavailable) throw e;
    await log({ ok: false, error: e instanceof Error ? e.message : String(e) }).catch(() => null);
    if (e instanceof Anthropic.RateLimitError) throw new AiUnavailable("Claude is busy. Try again in a minute.");
    if (e instanceof Anthropic.AuthenticationError) throw new AiUnavailable("The Claude API key is not valid.");
    if (e instanceof Anthropic.APIConnectionError) throw new AiUnavailable("Could not reach Claude. Try again.");
    throw e;
  }
}
