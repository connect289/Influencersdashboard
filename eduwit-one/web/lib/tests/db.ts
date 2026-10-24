import "server-only";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { DbError } from "../db.ts";
import { bootEnv } from "../env.ts";
import { type DueRun, parseDue, type PurgeDb } from "./purge.ts";
import type { TestRow, TestsDb, TestsState } from "./runner.ts";
import type { Run } from "./types.ts";

// The test runner's door to schema one (migrations 0014 and 0016), with the service role like lib/db.ts: the run
// bookkeeping, the seams (one.test_fact, one.test_act) through which a journey reads and acts on the apps, and the purge.

const identitiesSchema = z.object({
  phone_prefix: z.string().default("910000"),
  whatsapp_number: z.string().nullable().default(null),
  mailbox: z.string().nullable().default(null),
  website_preview_url: z.string().nullable().default(null),
  spark_test_user_email: z.string().nullable().default(null),
  partner_slug: z.string().nullable().default(null),
  creator_referral_code: z.string().nullable().default(null),
  run_phone_prefix: z.string().default("9100009"),
  runner_email: z.string().nullable().default(null),
  spark_test_journey_id: z.union([z.string(), z.number()]).transform(String).nullable().default(null),
  whatsapp_phone_number_id: z.string().nullable().default(null),
  witty_number: z.string().nullable().default(null),
});

const stepSchema = z.object({
  key: z.string(),
  title: z.string(),
  ok: z.boolean(),
  ms: z.number(),
  detail: z.string().nullable(),
  at: z.string(),
});

const runSchema = z.object({
  id: z.number(),
  testId: z.string(),
  startedAt: z.string(),
  steps: z.array(stepSchema).catch([]),
  artefacts: z.record(z.string(), z.unknown()).catch({}),
  state: z.object({
    step: z.number().int().min(0),
    stepStartedAt: z.string(),
    acted: z.boolean(),
    acting: z.boolean().optional(),
  }),
});

const stateSchema = z.object({
  tests: z.array(
    z.object({
      id: z.string(),
      enabled: z.boolean(),
      schedule: z.string(),
      timeout_s: z.number(),
      run_requested_at: z.string().nullable(),
      last_started_at: z.string().nullable(),
      inflight: z.boolean(),
    }),
  ),
  identities: identitiesSchema,
  runs: z.array(runSchema),
});

export interface TestSeams {
  /** What a step waits to see (one.test_fact): only for a run in flight, only kinds its test may use. */
  fact(run: number, kind: string, args?: Record<string, unknown>): Promise<Record<string, unknown>>;
  /** What a step does (one.test_act), on test identities only; recorded on the run for the purge. */
  act(run: number, kind: string, args?: Record<string, unknown>): Promise<Record<string, unknown>>;
}

const record = z.record(z.string(), z.unknown());

function createTestsClient(url: string, key: string) {
  return createClient(url, key, { db: { schema: "one" }, auth: { persistSession: false, autoRefreshToken: false } });
}

export class SupabaseTestsDb implements TestsDb, TestSeams, PurgeDb {
  private readonly client: ReturnType<typeof createTestsClient>;

  private constructor(client: ReturnType<typeof createTestsClient>) {
    this.client = client;
  }

  static fromEnv(): SupabaseTestsDb | undefined {
    const env = bootEnv();
    if (!env.ONE_SUPABASE_URL || !env.ONE_SUPABASE_SERVICE_KEY) return undefined;
    return new SupabaseTestsDb(createTestsClient(env.ONE_SUPABASE_URL, env.ONE_SUPABASE_SERVICE_KEY));
  }

  private async rpc(fn: string, args: Record<string, unknown>): Promise<unknown> {
    const { data, error } = await this.client.rpc(fn, args);
    if (error) throw new DbError(fn, error.code);
    return data;
  }

  async testsState(holder: string, leaseS: number): Promise<TestsState> {
    const s = stateSchema.parse(await this.rpc("tests_state", { p_holder: holder, p_lease_s: leaseS }));
    return { tests: s.tests satisfies TestRow[], identities: s.identities, runs: s.runs };
  }

  async runStart(
    testId: string,
    trigger: "schedule" | "manual",
    key: string,
    holder: string,
    leaseS: number,
  ): Promise<Run | null> {
    const data = await this.rpc("test_run_start", {
      p_test: testId,
      p_trigger: trigger,
      p_key: key,
      p_holder: holder,
      p_lease_s: leaseS,
    });
    return data == null ? null : runSchema.parse(data);
  }

  async runSave(run: Run, holder: string, leaseS: number): Promise<void> {
    await this.rpc("test_run_save", {
      p_run: run.id,
      p_holder: holder,
      p_lease_s: leaseS,
      p_steps: run.steps,
      p_artefacts: run.artefacts,
      p_state: run.state,
    });
  }

  async runFinish(run: Run, ok: boolean, error: string | null, holder: string): Promise<void> {
    await this.rpc("test_run_finish", {
      p_run: run.id,
      p_holder: holder,
      p_ok: ok,
      p_error: error,
      p_steps: run.steps,
      p_artefacts: run.artefacts,
    });
  }

  async fact(run: number, kind: string, args: Record<string, unknown> = {}) {
    return record.parse((await this.rpc("test_fact", { p_run: run, p_kind: kind, p_args: args })) ?? {});
  }

  async act(run: number, kind: string, args: Record<string, unknown> = {}) {
    return record.parse((await this.rpc("test_act", { p_run: run, p_kind: kind, p_args: args })) ?? {});
  }

  async purgeDue(limit: number): Promise<DueRun[]> {
    return parseDue(await this.rpc("test_purge_due", { p_limit: limit }));
  }

  async runPurge(run: number, report: Record<string, unknown>): Promise<boolean> {
    const r = record.parse((await this.rpc("test_run_purge", { p_run: run, p_report: report })) ?? {});
    return r.purged === true;
  }

  /** What the Setup validators of the test items read (0016): the identities and the named Spark journey. */
  async setupFacts(): Promise<unknown> {
    return await this.rpc("setup_test_facts", {});
  }
}
