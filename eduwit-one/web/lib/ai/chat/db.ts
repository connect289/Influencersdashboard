import "server-only";
import { z } from "zod";
import { ui } from "../../ui/api.ts";

// The chat's door to the database, as the signed-in person (migration 0021, one.ui_chat_*): every call carries their
// session, so one.ui_require() applies and a thread is its owner's only. The model calls' budget rows and the read
// tools go through the worker's AiDb (service role, one.ai_calls_add and one.ai_tool), held by the task the turn opened.

const num = z.number();
const iso = z.string();

export const historyItemSchema = z.object({
  role: z.enum(["user", "assistant", "action"]),
  content: z.record(z.string(), z.unknown()),
});
export type HistoryItem = z.infer<typeof historyItemSchema>;

export const turnStartSchema = z.object({
  thread_id: num,
  message_id: num,
  task_id: num,
  me: z.object({ email: z.string(), role: z.enum(["owner", "engineer"]) }),
  ai: z.unknown(),
  budget: z.object({ spent_inr: num, cap_inr: num, remaining_inr: num }),
  history: z.array(historyItemSchema),
  snapshot: z.record(z.string(), z.unknown()),
});
export type TurnStart = z.infer<typeof turnStartSchema>;

export const chatActionSchema = z.looseObject({
  id: num,
  tool: z.string(),
  args: z.record(z.string(), z.unknown()),
  summary: z.string(),
  risk: z.enum(["low", "medium", "high"]),
  status: z.enum(["proposed", "confirmed", "done", "failed", "declined", "expired"]),
  proposed_at: iso,
  decided_at: iso.nullable().optional(),
  result: z.unknown().optional(),
  error: z.string().nullable().optional(),
});
export type ChatAction = z.infer<typeof chatActionSchema>;

export const chatMessageSchema = z.object({
  id: num,
  seq: num,
  role: z.enum(["user", "assistant", "action"]),
  content: z.record(z.string(), z.unknown()),
  created_at: iso,
});
export type ChatMessageRow = z.infer<typeof chatMessageSchema>;

export const chatThreadSchema = z.object({
  thread: z.object({
    id: num,
    title: z.string(),
    created_at: iso,
    updated_at: iso,
    archived_at: iso.nullable(),
  }),
  messages: z.array(chatMessageSchema),
  actions: z.array(chatActionSchema),
  busy: z.boolean(),
});
export type ChatThread = z.infer<typeof chatThreadSchema>;

export const chatThreadsSchema = z.array(
  z.object({ id: num, title: z.string(), created_at: iso, updated_at: iso, messages: num, open_actions: num }),
);
export type ChatThreadRow = z.infer<typeof chatThreadsSchema>[number];

const decidedSchema = z.looseObject({
  ok: z.boolean(),
  status: z.string(),
  error: z.string().optional(),
  id: num.optional(),
  tool: z.string().optional(),
  args: z.record(z.string(), z.unknown()).optional(),
  summary: z.string().optional(),
});
export type Decided = z.infer<typeof decidedSchema>;

/** The assistant's turn as one.chat_messages keeps it. */
export type AssistantContent = {
  text: string;
  tools: Array<{
    name: string;
    args: Record<string, unknown>;
    ok: boolean;
    rows: number;
    result: string;
    error?: string;
  }>;
  actions: number[];
  meta?: { model: string; tier: string; prompt_version: string; calls: number; cost_inr: number };
};

export interface ChatDb {
  turnStart(thread: number | null, text: string, holder: string, requestId: string): Promise<TurnStart>;
  turnFinish(
    task: number,
    holder: string,
    assistant: AssistantContent,
    status: "done" | "failed",
    error: string | null,
  ): Promise<number>;
  actionPropose(
    task: number,
    holder: string,
    tool: string,
    args: Record<string, unknown>,
    summary: string,
    risk: string,
  ): Promise<number>;
  /** shown: the arguments the card showed; a confirmation runs only if they are the stored ones (0031, D-115). */
  actionDecide(
    id: number,
    decision: "confirm" | "decline",
    requestId: string,
    shown?: Record<string, unknown> | null,
  ): Promise<Decided>;
  actionResult(id: number, ok: boolean, result: unknown, error: string | null): Promise<string>;
}

export class SupabaseChatDb implements ChatDb {
  async turnStart(thread: number | null, text: string, holder: string, requestId: string) {
    return ui("ui_chat_turn_start", turnStartSchema, {
      p_thread: thread,
      p_text: text,
      p_holder: holder,
      p_request_id: requestId,
    });
  }

  async turnFinish(
    task: number,
    holder: string,
    assistant: AssistantContent,
    status: "done" | "failed",
    error: string | null,
  ) {
    const r = await ui("ui_chat_turn_finish", z.object({ ok: z.boolean(), message_id: num }), {
      p_task: task,
      p_holder: holder,
      p_assistant: assistant,
      p_status: status,
      p_error: error,
    });
    return r.message_id;
  }

  async actionPropose(
    task: number,
    holder: string,
    tool: string,
    args: Record<string, unknown>,
    summary: string,
    risk: string,
  ) {
    const r = await ui("ui_chat_action_propose", z.object({ id: num }), {
      p_task: task,
      p_holder: holder,
      p_tool: tool,
      p_args: args,
      p_summary: summary,
      p_risk: risk,
    });
    return r.id;
  }

  async actionDecide(
    id: number,
    decision: "confirm" | "decline",
    requestId: string,
    shown: Record<string, unknown> | null = null,
  ) {
    return ui("ui_chat_action_decide", decidedSchema, {
      p_id: id,
      p_decision: decision,
      p_request_id: requestId,
      p_shown: shown,
    });
  }

  async actionResult(id: number, ok: boolean, result: unknown, error: string | null) {
    const r = await ui("ui_chat_action_result", z.looseObject({ ok: z.boolean(), status: z.string() }), {
      p_id: id,
      p_ok: ok,
      p_result: result ?? null,
      p_error: error,
    });
    return r.status;
  }
}
