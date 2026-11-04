import "server-only";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { DbError } from "../db.ts";
import { bootEnv } from "../env.ts";
import { TASK_KINDS, TIERS } from "./models.ts";

// The AI worker's door to the database (migration 0018): the service role and the five ai_* functions. The claim
// carries the task, the settings, today's budget and the data the task may read, already redacted by the database.

export const claimSchema = z.object({
  task: z.object({
    id: z.number(),
    kind: z.enum(TASK_KINDS),
    input: z.record(z.string(), z.unknown()),
    model_hint: z.enum(TIERS).nullable(),
    attempts: z.number(),
    incident_id: z.number().nullable(),
  }),
  ai: z.unknown(),
  budget: z.object({
    spent_inr: z.number(),
    cap_inr: z.number(),
    remaining_inr: z.number(),
    /** What earlier attempts of this task spent (per_task_cap_inr holds across attempts). */
    task_spent_inr: z.number().default(0),
  }),
  context: z.unknown(),
});
export type Claim = z.infer<typeof claimSchema>;

/** One model call as one.ai_calls keeps it (the spend counts whether or not the task succeeds). */
export type CallRecord = {
  provider: "anthropic" | "gemini";
  model: string;
  purpose: string;
  prompt_version: string | null;
  input_tokens?: number;
  output_tokens?: number;
  cache_read?: number;
  cost_usd?: number;
  cost_inr?: number;
  latency_ms?: number;
  ok: boolean;
  error?: string | null;
};

export interface AiDb {
  claim(holder: string): Promise<Claim | null>;
  /** Records calls as they end, and answers with today's budget as it now stands. */
  recordCalls(task: number, holder: string, calls: CallRecord[]): Promise<{ remaining_inr: number }>;
  /**
   * Reserves a model call's worst case before it runs (0031, D-118): granted only while today's spend, the calls in
   * flight and this one fit under the day's cap. Recording the call settles it.
   */
  reserve(task: number, holder: string, amountInr: number): Promise<{ ok: boolean; remaining_inr: number }>;
  finish(task: number, holder: string, result: Record<string, unknown>, calls: CallRecord[]): Promise<void>;
  fail(task: number, holder: string, error: string, calls: CallRecord[], retry: boolean): Promise<string>;
  defer(task: number, holder: string, reason: string, minutes: number): Promise<void>;
  tool(task: number, holder: string, name: string, args: Record<string, unknown>): Promise<unknown>;
  aiSettings(): Promise<unknown>;
}

function createAiClient(url: string, key: string) {
  return createClient(url, key, { db: { schema: "one" }, auth: { persistSession: false, autoRefreshToken: false } });
}

export class SupabaseAiDb implements AiDb {
  private readonly client: ReturnType<typeof createAiClient>;

  private constructor(client: ReturnType<typeof createAiClient>) {
    this.client = client;
  }

  static fromEnv(): SupabaseAiDb | undefined {
    const env = bootEnv();
    if (!env.ONE_SUPABASE_URL || !env.ONE_SUPABASE_SERVICE_KEY) return undefined;
    return new SupabaseAiDb(createAiClient(env.ONE_SUPABASE_URL, env.ONE_SUPABASE_SERVICE_KEY));
  }

  private async rpc(fn: string, args: Record<string, unknown> = {}): Promise<unknown> {
    const { data, error } = await this.client.rpc(fn, args);
    if (error) throw new DbError(fn, error.code);
    return data;
  }

  async claim(holder: string) {
    const data = await this.rpc("ai_claim", { p_holder: holder });
    return data === null ? null : claimSchema.parse(data);
  }

  async recordCalls(task: number, holder: string, calls: CallRecord[]) {
    return z
      .object({ remaining_inr: z.number() })
      .parse(await this.rpc("ai_calls_add", { p_task: task, p_holder: holder, p_calls: calls }));
  }

  async reserve(task: number, holder: string, amountInr: number) {
    return z
      .object({ ok: z.boolean(), remaining_inr: z.number() })
      .parse(await this.rpc("ai_reserve", { p_task: task, p_holder: holder, p_amount: amountInr }));
  }

  async finish(task: number, holder: string, result: Record<string, unknown>, calls: CallRecord[]) {
    await this.rpc("ai_finish", { p_task: task, p_holder: holder, p_result: result, p_calls: calls });
  }

  async fail(task: number, holder: string, error: string, calls: CallRecord[], retry: boolean) {
    return z
      .string()
      .parse(
        await this.rpc("ai_fail", { p_task: task, p_holder: holder, p_error: error, p_calls: calls, p_retry: retry }),
      );
  }

  async defer(task: number, holder: string, reason: string, minutes: number) {
    await this.rpc("ai_defer", { p_task: task, p_holder: holder, p_reason: reason, p_minutes: minutes });
  }

  async tool(task: number, holder: string, name: string, args: Record<string, unknown>) {
    return this.rpc("ai_tool", { p_task: task, p_holder: holder, p_name: name, p_args: args });
  }

  async aiSettings() {
    return this.rpc("app_ai_settings");
  }
}
