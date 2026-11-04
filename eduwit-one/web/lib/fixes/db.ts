import "server-only";
import { createClient } from "@supabase/supabase-js";
import { DbError } from "../db.ts";
import { bootEnv } from "../env.ts";
import { claimSchema, type FixRun, type FixesDb, reportSchema } from "./run.ts";

// The app's side of its two fixes (migration 0019), with the service role like lib/db.ts: the runs the database queued
// for the app, and the app's report on each.

function createFixesClient(url: string, key: string) {
  return createClient(url, key, { db: { schema: "one" }, auth: { persistSession: false, autoRefreshToken: false } });
}

export class SupabaseFixesDb implements FixesDb {
  private readonly client: ReturnType<typeof createFixesClient>;

  private constructor(client: ReturnType<typeof createFixesClient>) {
    this.client = client;
  }

  static fromEnv(): SupabaseFixesDb | undefined {
    const env = bootEnv();
    if (!env.ONE_SUPABASE_URL || !env.ONE_SUPABASE_SERVICE_KEY) return undefined;
    return new SupabaseFixesDb(createFixesClient(env.ONE_SUPABASE_URL, env.ONE_SUPABASE_SERVICE_KEY));
  }

  private async rpc(fn: string, args: Record<string, unknown>): Promise<unknown> {
    const { data, error } = await this.client.rpc(fn, args);
    if (error) throw new DbError(fn, error.code);
    return data;
  }

  async claim(holder: string): Promise<FixRun[]> {
    return claimSchema.parse(await this.rpc("app_fixes_claim", { p_holder: holder })).runs;
  }

  async report(actionId: number, ok: boolean, result: Record<string, unknown>) {
    return reportSchema.parse(await this.rpc("app_fix_report", { p_action: actionId, p_ok: ok, p_result: result }));
  }
}
