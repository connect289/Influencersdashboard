import "server-only";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { bootEnv } from "./env.ts";
import { tickStateSchema, type Report, type TickState } from "./state.ts";

// The app's only door to the database (spec §5): the service role, schema one, and the functions of migration 0008.
// PostgREST must expose schema one for these calls (Setup item supabase_api_schema, D-047).

export interface OneDb {
  tickState(): Promise<TickState>;
  report(report: Report, actor: string, requestId: string): Promise<Record<string, unknown>>;
  wittyEscalations(
    limit: number,
  ): Promise<Array<{ conversation_id: number; account_id: number; escalated_at: string }>>;
  watchdog(): Promise<{ tick_age_s: number | null; app_age_s: number | null }>;
}

export class DbError extends Error {
  readonly operation: string;
  readonly code: string | undefined;

  constructor(operation: string, code: string | undefined) {
    super(`database ${operation} failed${code ? ` (${code})` : ""}`);
    this.operation = operation;
    this.code = code;
  }
}

const escalationsSchema = z.array(
  z.object({ conversation_id: z.number(), account_id: z.number(), escalated_at: z.string() }),
);
const watchdogSchema = z.object({ tick_age_s: z.number().nullable(), app_age_s: z.number().nullable() });

type OneClient = ReturnType<typeof createOneClient>;

function createOneClient(url: string, key: string) {
  return createClient(url, key, { db: { schema: "one" }, auth: { persistSession: false, autoRefreshToken: false } });
}

export class SupabaseOneDb implements OneDb {
  private readonly client: OneClient;

  private constructor(client: OneClient) {
    this.client = client;
  }

  static fromEnv(): SupabaseOneDb | undefined {
    const env = bootEnv();
    if (!env.ONE_SUPABASE_URL || !env.ONE_SUPABASE_SERVICE_KEY) return undefined;
    return new SupabaseOneDb(createOneClient(env.ONE_SUPABASE_URL, env.ONE_SUPABASE_SERVICE_KEY));
  }

  private async rpc(fn: string, args: Record<string, unknown> = {}): Promise<unknown> {
    const { data, error } = await this.client.rpc(fn, args);
    if (error) throw new DbError(fn, error.code);
    return data;
  }

  async tickState(): Promise<TickState> {
    return tickStateSchema.parse(await this.rpc("app_tick_state"));
  }

  async report(report: Report, actor: string, requestId: string): Promise<Record<string, unknown>> {
    return z
      .record(z.string(), z.unknown())
      .parse(await this.rpc("app_report", { p_report: report, p_actor: actor, p_request_id: requestId }));
  }

  async wittyEscalations(limit: number) {
    return escalationsSchema.parse(await this.rpc("witty_escalations", { p_limit: limit }));
  }

  async watchdog() {
    return watchdogSchema.parse(await this.rpc("watchdog"));
  }
}
