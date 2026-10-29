import { z } from "zod";
import { APPS, ASK_TOOLS } from "../schemas.ts";

// The command centre's tools (D-094). Three kinds:
//   read    the fixed read-only tools Ask already has (the database's one.ai_tool_data, plus runbook, operate and
//           n8n_executions in the app); the model calls them freely.
//   act     one one.ui_* page function each, run as the signed-in person with their own role check and audit row.
//           A low-risk, reversible act runs at once ("auto"); every other act is first an action card the person
//           confirms in the chat ("confirm"). The model never gets a function the pages do not have.
//   secret  no model involvement at all: the chat shows a Vault card; the value goes to one.ui_secret_put directly.
// The arguments are validated here (zod) before anything runs, whatever the model sent.

export type Risk = "low" | "medium" | "high";
export type Perm = "operate" | "owner";

type Call = { fn: string; args: Record<string, unknown> } | { local: "validate_setup"; item: string };

export type ReadTool = { kind: "read"; name: string; description: string; input: z.ZodObject };
export type ActTool = {
  kind: "act";
  name: string;
  description: string;
  input: z.ZodObject;
  /** Run at once (false) or after the person confirms the action card (true). */
  confirm: boolean;
  risk: Risk;
  /** The role the database will ask for; owner-only tools are not offered to an engineer. */
  perm: Perm;
  call: (args: Record<string, unknown>) => Call;
  summary: (args: Record<string, unknown>) => string;
};
export type SecretTool = { kind: "secret"; name: string; description: string; input: z.ZodObject };
export type ChatTool = ReadTool | ActTool | SecretTool;

const id = z.number().int().positive();
const appKey = z.enum(APPS);
const text = (max: number) => z.string().trim().min(1).max(max);
const reason = z.string().trim().min(3).max(500).describe("Why, in one sentence; it is kept in the audit.");
const hours = z.number().int().min(1).max(720).optional().describe("How far back, in hours (default 168)");
const limit = (max: number) => z.number().int().min(1).max(max).optional();

const read = (name: string, description: string, input: z.ZodObject): ReadTool => ({
  kind: "read",
  name,
  description,
  input,
});

const READ: ReadTool[] = [
  read(
    "incidents",
    "Incidents, newest first. Filter by status (open by default), app, check_id or severity.",
    z.object({
      status: z.enum(["open", "resolved", "all"]).optional(),
      app: appKey.optional(),
      check_id: z.string().max(60).optional(),
      severity: z.enum(["P1", "P2", "P3"]).optional(),
      since_hours: hours,
      limit: limit(50),
    }),
  ),
  read("incident", "One incident with its check, recent runs and history.", z.object({ id })),
  read("check", "A check's definition and its last 20 results.", z.object({ check_id: z.string().max(60) })),
  read("checks_failing", "Enabled checks whose latest result is not ok.", z.object({ app: appKey.optional() })),
  read("tests", "The synthetic tests and their last five runs.", z.object({ test_id: z.string().max(60).optional() })),
  read(
    "events",
    "Counts of app events (leads, messages, allocations and so on) by time bucket.",
    z.object({
      app: appKey.optional(),
      type: z.string().max(60).optional(),
      since_hours: hours,
      bucket: z.enum(["hour", "day"]).optional(),
    }),
  ),
  read(
    "analytics",
    "The cross-app funnel, events by app, and partners' and counsellors' numbers.",
    z.object({ days: z.number().int().min(1).max(90).optional() }),
  ),
  read(
    "marketing",
    "Leads by platform and campaign per day, touchpoints, ad spend and the WhatsApp numbers.",
    z.object({ days: z.number().int().min(1).max(90).optional() }),
  ),
  read(
    "witty",
    "Witty's panels: replies (daily counts and latency), outbox, digest, health_alerts, learnings, n8n.",
    z.object({ panel: z.enum(["replies", "outbox", "digest", "health_alerts", "learnings", "n8n"]) }),
  ),
  read(
    "health",
    "Eduwit One's own health, every heartbeat, and the B2B, website and influencer portal health.",
    z.object({}),
  ),
  read(
    "cron",
    "The database's cron jobs with their runs, failures and last failure.",
    z.object({ since_hours: z.number().int().min(1).max(48).optional() }),
  ),
  read(
    "ai_spend",
    "AI calls and spend per day and model.",
    z.object({ days: z.number().int().min(1).max(30).optional() }),
  ),
  read(
    "proposals",
    "Proposals, newest first.",
    z.object({
      status: z.enum(["open", "approved", "rejected", "applied", "expired", "snoozed"]).optional(),
      limit: limit(50),
    }),
  ),
  read("deliveries", "Alert and brief emails by kind and status.", z.object({ since_hours: hours })),
  read(
    "n8n_executions",
    "Witty's recent n8n executions (status and times only).",
    z.object({ status: z.enum(["success", "error", "waiting"]).optional(), limit: limit(20) }),
  ),
  read(
    "setup",
    "Settings → Setup: every item Eduwit One needs (or one), who fills it, its status, what it unblocks, the checks waiting for it and how to fix it. Start here for 'set up' and 'what does X need'.",
    z.object({ item: z.string().max(60).optional() }),
  ),
  read(
    "app_status",
    "One app as Eduwit One sees it now: heartbeats, checks with their last status, open incidents, its cron jobs, its fixes and its tests.",
    z.object({ app: appKey }),
  ),
  read(
    "operate",
    "The Operate page's text for an app: what it needs in order, the first-time steps, what to look at every day, the first place to look when each check fires, what stays in the app.",
    z.object({ app: z.enum(["witty", "b2b", "b2c", "web", "influencer", "one"]) }),
  ),
  read(
    "fixes",
    "The fix catalogue (or one fix): trigger, what it does, rights, rollback, switch and limits, counts and its last five rows.",
    z.object({ fix_id: z.string().max(60).optional() }),
  ),
  read(
    "actions",
    "Fix action rows, newest first.",
    z.object({ fix_id: z.string().max(60).optional(), since_hours: hours, limit: limit(50) }),
  ),
  read(
    "audit",
    "Who changed what in Eduwit One (actor, action, target; never the values).",
    z.object({ since_hours: hours, action: z.string().max(60).optional(), limit: limit(50) }),
  ),
  read(
    "runbook",
    "The runbook sections whose words match the query (RUNBOOK.md, RUNBOOK-database.md, WALKTHROUGH.md); with no query, the list of sections.",
    z.object({ query: z.string().max(200).optional() }),
  ),
];

const act = (t: Omit<ActTool, "kind">): ActTool => ({ kind: "act", ...t });

const ACT: ActTool[] = [
  act({
    name: "acknowledge_incident",
    description: "Acknowledge an open incident (stops its reminders; it stays open).",
    input: z.object({ id }),
    confirm: false,
    risk: "low",
    perm: "operate",
    call: (a) => ({ fn: "ui_ack", args: { p_id: a.id } }),
    summary: (a) => `Acknowledge incident #${String(a.id)}`,
  }),
  act({
    name: "resolve_incident",
    description:
      "Resolve an open incident with a resolution: fixed, false_positive, accepted or manual, and a note. The check keeps running; it reopens if it fails again.",
    input: z.object({ id, resolution: z.enum(["fixed", "false_positive", "accepted", "manual"]), note: reason }),
    confirm: true,
    risk: "medium",
    perm: "operate",
    call: (a) => ({ fn: "ui_resolve", args: { p_id: a.id, p_resolution: a.resolution, p_note: a.note } }),
    summary: (a) => `Resolve incident #${String(a.id)} as ${String(a.resolution)}`,
  }),
  act({
    name: "rerun_deep",
    description: "Ask the AI worker to explain an incident again on the deep model.",
    input: z.object({ id }),
    confirm: false,
    risk: "low",
    perm: "operate",
    call: (a) => ({ fn: "ui_rerun_deep", args: { p_id: a.id } }),
    summary: (a) => `Explain incident #${String(a.id)} again on the deep model`,
  }),
  act({
    name: "mute",
    description:
      "Silence a check or a whole app for some minutes (a maintenance window): incidents are recorded but not alerted.",
    input: z.object({
      target_type: z.enum(["check", "app"]),
      target: z.string().trim().min(2).max(60),
      minutes: z.number().int().min(1).max(10080),
      reason,
    }),
    confirm: true,
    risk: "medium",
    perm: "operate",
    call: (a) => ({
      fn: "ui_mute",
      args: { p_target_type: a.target_type, p_target: a.target, p_minutes: a.minutes, p_reason: a.reason },
    }),
    summary: (a) => `Mute ${String(a.target_type)} ${String(a.target)} for ${String(a.minutes)} minutes`,
  }),
  act({
    name: "unmute",
    description: "End a mute before its time (the mute's id, from the mutes list on Settings).",
    input: z.object({ id }),
    confirm: true,
    risk: "low",
    perm: "operate",
    call: (a) => ({ fn: "ui_unmute", args: { p_id: a.id } }),
    summary: (a) => `End mute #${String(a.id)}`,
  }),
  act({
    name: "run_test",
    description: "Run a synthetic test now (test traffic only, on the test identities).",
    input: z.object({ test_id: z.string().regex(/^T-[A-Z0-9-]{2,60}$/) }),
    confirm: true,
    risk: "medium",
    perm: "operate",
    call: (a) => ({ fn: "ui_test_run", args: { p_id: a.test_id } }),
    summary: (a) => `Run test ${String(a.test_id)} now`,
  }),
  act({
    name: "dry_run_fix",
    description:
      "Record what a fix would do about an open incident, changing nothing. Use it before suggesting the owner switch a fix on.",
    input: z.object({ fix_id: z.string().regex(/^FIX-[A-Z0-9]+(-[A-Z0-9]+)*$/), incident_id: id }),
    confirm: false,
    risk: "low",
    perm: "operate",
    call: (a) => ({ fn: "ui_fix_dry_run", args: { p_fix: a.fix_id, p_incident: a.incident_id } }),
    summary: (a) => `Dry run ${String(a.fix_id)} on incident #${String(a.incident_id)}`,
  }),
  act({
    name: "set_fix",
    description:
      "Switch a fix on or off or change its limits (owner). A fix acts on an app only after its dry runs held and the observation window passed; the database refuses otherwise.",
    input: z.object({
      fix_id: z.string().regex(/^FIX-[A-Z0-9]+(-[A-Z0-9]+)*$/),
      enabled: z.boolean().optional(),
      per_tick: z.number().int().min(1).max(500).optional(),
      cooldown_min: z.number().int().min(1).max(1440).optional(),
      reason,
    }),
    confirm: true,
    risk: "high",
    perm: "owner",
    call: (a) => ({
      fn: "ui_fix_set",
      args: {
        p_fix: a.fix_id,
        p_patch: Object.fromEntries(
          Object.entries({ enabled: a.enabled, per_tick: a.per_tick, cooldown_min: a.cooldown_min }).filter(
            ([, v]) => v !== undefined,
          ),
        ),
        p_reason: a.reason,
      },
    }),
    summary: (a) =>
      a.enabled === undefined
        ? `Change the limits of ${String(a.fix_id)}`
        : `Switch ${String(a.fix_id)} ${a.enabled ? "on" : "off"}`,
  }),
  act({
    name: "unpause_fix",
    description: "Clear a fix its breaker paused after runs that did not hold (owner).",
    input: z.object({ fix_id: z.string().regex(/^FIX-[A-Z0-9]+(-[A-Z0-9]+)*$/), reason }),
    confirm: true,
    risk: "high",
    perm: "owner",
    call: (a) => ({ fn: "ui_fix_unpause", args: { p_fix: a.fix_id, p_reason: a.reason } }),
    summary: (a) => `Let ${String(a.fix_id)} act again`,
  }),
  act({
    name: "decide_proposal",
    description:
      "Approve, reject or snooze an open proposal. Approving a proposal that touches money, allocation, live switches, mappings, prompts or settings needs the owner.",
    input: z.object({
      id,
      decision: z.enum(["approve", "reject", "snooze"]),
      note: z.string().trim().max(1000).optional(),
      snooze_days: z.number().int().min(1).max(30).optional(),
    }),
    confirm: true,
    risk: "high",
    perm: "operate",
    call: (a) => ({
      fn: "ui_proposal_decide",
      args: {
        p_id: a.id,
        p_decision: a.decision,
        p_note: a.note ?? null,
        p_change: null,
        p_snooze_days: a.snooze_days ?? null,
      },
    }),
    summary: (a) => `${String(a.decision).replace(/^./, (c) => c.toUpperCase())} proposal #${String(a.id)}`,
  }),
  act({
    name: "create_proposal",
    description:
      "Open a proposal for a change Eduwit One cannot make itself (a change in an app, a new check, a clean-up), for the owner to decide and track.",
    input: z.object({
      kind: z.enum(["fix", "feature", "config", "cleanup"]),
      app: appKey,
      title: text(200),
      rationale: z.string().trim().min(10).max(4000),
      change: z.record(z.string(), z.unknown()).optional(),
      risk: z.enum(["low", "medium", "high"]),
      incident_id: id.optional(),
    }),
    confirm: true,
    risk: "medium",
    perm: "operate",
    call: (a) => ({
      fn: "ui_proposal_create",
      args: {
        p_kind: a.kind,
        p_app: a.app,
        p_title: a.title,
        p_rationale: a.rationale,
        p_change: a.change ?? {},
        p_risk: a.risk,
        p_incident_id: a.incident_id ?? null,
      },
    }),
    summary: (a) => `Open a ${String(a.kind)} proposal for ${String(a.app)}: ${String(a.title)}`,
  }),
  act({
    name: "update_check",
    description: "Change a check: enabled, severity, cadence_s, open_after, resolve_after or its threshold object.",
    input: z.object({
      id: z.string().regex(/^[A-Z0-9]+(-[A-Za-z0-9:._]+)+$/),
      patch: z.object({
        enabled: z.boolean().optional(),
        severity: z.enum(["P1", "P2", "P3"]).optional(),
        cadence_s: z.number().int().min(60).max(604800).optional(),
        open_after: z.number().int().min(1).max(60).optional(),
        resolve_after: z.number().int().min(1).max(60).optional(),
        threshold: z.record(z.string(), z.unknown()).optional(),
      }),
      reason,
    }),
    confirm: true,
    risk: "medium",
    perm: "operate",
    call: (a) => ({ fn: "ui_check_update", args: { p_id: a.id, p_patch: a.patch, p_reason: a.reason } }),
    summary: (a) => `Change check ${String(a.id)}: ${Object.keys(a.patch as object).join(", ")}`,
  }),
  act({
    name: "update_test",
    description: "Change a synthetic test: enabled or its 5-field cron schedule.",
    input: z.object({
      id: z.string().regex(/^T-[A-Z0-9-]{2,60}$/),
      patch: z.object({ enabled: z.boolean().optional(), schedule: z.string().max(60).optional() }),
      reason,
    }),
    confirm: true,
    risk: "medium",
    perm: "operate",
    call: (a) => ({ fn: "ui_test_update", args: { p_id: a.id, p_patch: a.patch, p_reason: a.reason } }),
    summary: (a) => `Change test ${String(a.id)}: ${Object.keys(a.patch as object).join(", ")}`,
  }),
  act({
    name: "put_setting",
    description:
      "Replace one settings key with a whole new value (versioned; Settings shows every version and can restore one). Read the current value first (the setup or app_status tools, or ask the person). Keys that touch alerts, fixes, access or money need the owner.",
    input: z.object({
      key: z.string().regex(/^[a-z_]{2,40}$/),
      value: z.record(z.string(), z.unknown()),
      reason,
    }),
    confirm: true,
    risk: "high",
    perm: "operate",
    call: (a) => ({ fn: "ui_settings_put", args: { p_key: a.key, p_value: a.value, p_reason: a.reason } }),
    summary: (a) => `Change setting ${String(a.key)}`,
  }),
  act({
    name: "put_user",
    description: "Add a person to Eduwit One or change their role or active state (owner).",
    input: z.object({ email: z.email().max(200), role: z.enum(["owner", "engineer"]), active: z.boolean() }),
    confirm: true,
    risk: "high",
    perm: "owner",
    call: (a) => ({ fn: "ui_user_put", args: { p_email: a.email, p_role: a.role, p_active: a.active } }),
    summary: (a) =>
      `${a.active ? "Give" : "Remove"} ${String(a.email)} ${a.active ? `the ${String(a.role)} role` : "access"}`,
  }),
  act({
    name: "regenerate_brief",
    description: "Queue the morning brief for a day again, on a tier.",
    input: z.object({ for_date: z.iso.date(), tier: z.enum(["quick", "regular", "deep"]) }),
    confirm: false,
    risk: "low",
    perm: "operate",
    call: (a) => ({ fn: "ui_brief_regenerate", args: { p_for_date: a.for_date, p_tier: a.tier } }),
    summary: (a) => `Build the brief for ${String(a.for_date)} again (${String(a.tier)})`,
  }),
  act({
    name: "validate_setup",
    description:
      "Run a Setup item's validator now (the real call with the saved value) and record the verdict; the checks it unblocks switch on when it passes.",
    input: z.object({ item: z.string().regex(/^[a-z0-9_]{2,60}$/) }),
    confirm: false,
    risk: "low",
    perm: "operate",
    call: (a) => ({ local: "validate_setup", item: String(a.item) }),
    summary: (a) => `Validate Setup item ${String(a.item)}`,
  }),
];

const SECRET: SecretTool = {
  kind: "secret",
  name: "request_secret",
  description:
    "Show the person a card to paste a secret (an API key, a token) straight into Vault under its one_* name. Use it instead of ever asking for a secret in the chat; you never see the value.",
  input: z.object({
    name: z
      .string()
      .regex(/^one_[a-z0-9_]{2,60}$/)
      .describe("The Vault name the Setup item stores, e.g. one_n8n_key"),
    item: z
      .string()
      .regex(/^[a-z0-9_]{2,60}$/)
      .optional()
      .describe("The Setup item it belongs to"),
  }),
};

export const CHAT_TOOLS: ChatTool[] = [...READ, ...ACT, SECRET];

/** Database read tools go through one.ai_tool; the rest the app answers itself. */
export const DB_READ_TOOLS = new Set<string>(
  ASK_TOOLS.filter((t) => t !== "runbook" && t !== "operate" && t !== "n8n_executions"),
);

export function toolByName(name: string): ChatTool | undefined {
  return CHAT_TOOLS.find((t) => t.name === name);
}

/** The tools a person of this role may use (an engineer is not offered the owner-only acts). */
export function toolsFor(role: "owner" | "engineer"): ChatTool[] {
  return CHAT_TOOLS.filter((t) => t.kind !== "act" || t.perm === "operate" || role === "owner");
}

/** A tool as the Anthropic API takes it: name, description and a JSON schema for its input. */
export function toolDefinition(t: ChatTool): {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
} {
  const schema = z.toJSONSchema(t.input, { target: "draft-7", io: "input" }) as Record<string, unknown>;
  delete schema.$schema;
  return { name: t.name, description: t.description, input_schema: { ...schema, type: "object" } };
}
