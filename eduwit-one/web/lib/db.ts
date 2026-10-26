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
  watchdog(): Promise<Watchdog>;
  claimDeliveries(limit: number): Promise<unknown[]>;
  finishDelivery(id: number, ok: boolean, error: string | null, providerId: string | null): Promise<string>;
  appSecrets(): Promise<Record<string, string>>;
  authIssueCode(userId: string, sessionId: string): Promise<string>;
  authRecord(entry: SignInEntry): Promise<void>;
  setupValidated(item: string, ok: boolean, detail: string, actor: string, requestId: string): Promise<number>;
  setupEngineFacts(): Promise<unknown>;
}

/** One line of one.sign_in_log, written by the signed-out steps (0009). */
export type SignInEntry = {
  email: string | null;
  user_id?: string | null;
  method: "google" | "email_code" | "trusted_device" | "sign_out";
  outcome:
    | "success"
    | "refused_domain"
    | "refused_unknown"
    | "code_sent"
    | "mail_failed"
    | "too_many_codes"
    | "revoked"
    | "idle";
  ip?: string | null;
  user_agent?: string | null;
};

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
const watchdogSchema = z.object({
  tick_age_s: z.number().nullable(),
  app_age_s: z.number().nullable(),
  delivery_wait_s: z.number().nullable(),
});
export type Watchdog = z.infer<typeof watchdogSchema>;

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

  async claimDeliveries(limit: number) {
    return z.array(z.unknown()).parse(await this.rpc("claim_deliveries", { p_limit: limit }));
  }

  async appSecrets() {
    return z.record(z.string(), z.string()).parse(await this.rpc("app_secrets"));
  }

  async authIssueCode(userId: string, sessionId: string) {
    return z
      .string()
      .regex(/^\d{6}$/)
      .parse(await this.rpc("auth_issue_code", { p_user: userId, p_session: sessionId }));
  }

  async authRecord(entry: SignInEntry) {
    await this.rpc("auth_record", { p: entry });
  }

  /** A Setup item's probe result, run by the app itself (0011 one.setup_validated); returns the checks switched on. */
  async setupValidated(item: string, ok: boolean, detail: string, actor: string, requestId: string) {
    const r = z
      .object({ checks_on: z.number() })
      .loose()
      .parse(
        await this.rpc("setup_validated", {
          p_item: item,
          p_ok: ok,
          p_detail: detail,
          p_actor: actor,
          p_request_id: requestId,
        }),
      );
    return r.checks_on;
  }

  /** What the catalogue_engine Setup validator reads (0021 one.setup_engine_facts): schema ce's tables, names only. */
  async setupEngineFacts() {
    return await this.rpc("setup_engine_facts");
  }

  async finishDelivery(id: number, ok: boolean, error: string | null, providerId: string | null) {
    return z
      .string()
      .parse(await this.rpc("finish_delivery", { p_id: id, p_ok: ok, p_error: error, p_provider_id: providerId }));
  }
}
