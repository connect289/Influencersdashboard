import { z } from "zod";
import type { TaskKind } from "./models.ts";

// What each task kind must answer (spec §11: outputs validated against schemas). The schema is sent to Claude as its
// structured-output format, and the worker checks every answer against it again before anything is filed. Every field
// is required (null where it may be empty), as structured outputs expect. Lengths are generous; the database cuts what
// it stores.

const confidence = z.enum(["low", "medium", "high"]);
const risk = z.enum(["low", "medium", "high"]);
const text = (max: number) => z.string().min(1).max(max);

export const APPS = ["witty", "b2b", "b2c", "web", "influencer", "one", "platform", "catalogue", "integrity"] as const;

/** What a proposal touches; the sensitive ones make it the owner's to approve (one.proposal_sensitive, D-065). */
export const TOUCHES = [
  "money",
  "allocation",
  "live_switches",
  "partner_mappings",
  "prompts",
  "versioned_settings",
  "api_keys",
  "credentials",
  "auth",
  "auth_settings",
  "database_security",
  "data_retention",
  "staging",
  "security",
  "app_code",
  "app_settings",
  "n8n_workflow",
  "infrastructure",
  "tests",
  "docs",
] as const;

export const classifySchema = z.object({
  category: z.enum([
    "data",
    "integration",
    "infrastructure",
    "configuration",
    "code",
    "vendor",
    "capacity",
    "test_traffic",
    "unknown",
  ]),
  code_related: z.boolean(),
  confidence,
  note: text(400),
});

export const triageSchema = z.object({
  summary: text(800),
  likely_cause: z.string().max(800).nullable(),
  next_steps: z.array(text(300)).max(6),
  checks_to_watch: z.array(z.string().max(80)).max(8),
  confidence,
  propose_fix: z.boolean(),
});

export const explainSchema = z.object({
  explanation: text(6000),
  likely_cause: text(800),
  timeline: z.array(z.object({ at: z.string().max(40), what: text(300) })).max(12),
  confidence,
});

export const proposeFixSchema = z.object({
  title: z.string().min(5).max(200),
  rationale: z.string().min(10).max(4000),
  where: text(300),
  owner_action: text(4000),
  steps: z.array(text(400)).max(10),
  touches: z.array(z.enum(TOUCHES)).max(8),
  risk,
  uses_fix: z.string().max(60).nullable(),
  verify: text(1000),
});

export const proposeFeatureSchema = z.object({
  proposals: z
    .array(
      z.object({
        kind: z.enum(["feature", "cleanup", "config"]),
        app: z.enum(APPS),
        title: z.string().min(5).max(200),
        rationale: z.string().min(10).max(4000),
        where: text(300),
        owner_action: text(4000),
        evidence: z.array(text(300)).max(8),
        touches: z.array(z.enum(TOUCHES)).max(8),
        risk,
      }),
    )
    .max(3),
});

export const testAuthorSchema = z.object({
  needed: z.boolean(),
  rationale: z.string().min(10).max(4000),
  risk,
  test: z
    .object({
      title: z.string().min(5).max(160),
      app: z.enum(APPS),
      trigger: text(300),
      steps: z
        .array(z.object({ title: text(200), expect: text(400) }))
        .min(1)
        .max(10),
      safety: text(1000),
      purge: text(600),
    })
    .nullable(),
});

export const briefSchema = z.object({
  headline: text(200),
  body_md: z.string().min(20).max(12000),
});

export const ASK_TOOLS = [
  "incidents",
  "incident",
  "check",
  "checks_failing",
  "tests",
  "events",
  "analytics",
  "marketing",
  "witty",
  "health",
  "cron",
  "ai_spend",
  "proposals",
  "deliveries",
  "n8n_executions",
  // Set-up and running (0020, D-083): the database's setup, app_status, fixes, actions and audit; the app's operate
  // and runbook.
  "setup",
  "app_status",
  "operate",
  "fixes",
  "actions",
  "audit",
  "runbook",
] as const;
export type AskTool = (typeof ASK_TOOLS)[number];

/** One round of Ask: tool calls to make, or the answer. Arguments travel as a JSON string (any shape, checked later). */
export const askRoundSchema = z.object({
  calls: z.array(z.object({ tool: z.enum(ASK_TOOLS), args_json: z.string().max(1000) })).max(6),
  answer: z.string().max(6000).nullable(),
});
export const askFinalSchema = z.object({ answer: text(6000) });

export const SCHEMAS = {
  classify: classifySchema,
  triage: triageSchema,
  explain: explainSchema,
  propose_fix: proposeFixSchema,
  propose_feature: proposeFeatureSchema,
  test_author: testAuthorSchema,
  brief: briefSchema,
  ask: askFinalSchema,
} satisfies Record<TaskKind, z.ZodType>;

/** Output allowance per kind (thinking counts against it on Claude); the worst-case cost check uses the same numbers. */
export const MAX_TOKENS: Record<TaskKind | "ask_round", number> = {
  classify: 2000,
  triage: 6000,
  explain: 12000,
  propose_fix: 12000,
  propose_feature: 16000,
  test_author: 8000,
  brief: 12000,
  ask: 6000,
  ask_round: 4000,
};
