"use server";
import { z } from "zod";
import { SupabaseChatDb, type Decided } from "../ai/chat/db.ts";
import { shownArgs } from "../ai/chat/shown.ts";
import { toolByName } from "../ai/chat/tools.ts";
import { log } from "../log.ts";
import { assertUser } from "../session.ts";
import { runValidate } from "../setup/run.ts";
import { ui, UiError } from "../ui/api.ts";
import { okSchema } from "../ui/schemas.ts";
import { act, fields, invalid, type ActionResult } from "./act.ts";

// The person's side of the command centre's action cards (D-094). Confirm marks the action in the database and then
// runs the one one.ui_* call it names, as this person, under one request id, and closes the action with the result;
// decline closes it. A confirmation carries the arguments the card showed, and the database confirms only if they are
// the stored ones (D-115). The arguments are validated against the tool's schema again before anything runs.

export type ChatActionResult = ActionResult & { status?: string };

export async function decideChatAction(_: ChatActionResult | undefined, form: FormData): Promise<ChatActionResult> {
  const p = z
    .object({
      id: z.coerce.number().int().positive(),
      decision: z.enum(["confirm", "decline"]),
      args: z.string().optional(),
    })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  const shown = p.data.decision === "confirm" ? shownArgs(p.data.args) : null;
  if (p.data.decision === "confirm" && !shown)
    return { ok: false, error: "This card cannot be confirmed: reload the conversation and decide again." };
  let me;
  try {
    me = await assertUser();
  } catch {
    return { ok: false, error: "Your role cannot do this." };
  }
  const db = new SupabaseChatDb();
  const requestId = crypto.randomUUID();
  let decided: Decided;
  try {
    decided = await db.actionDecide(p.data.id, p.data.decision, requestId, shown);
  } catch (e) {
    return { ok: false, error: e instanceof UiError ? e.message : "That did not work. Try again." };
  }
  if (!decided.ok)
    return { ok: false, error: decided.error ?? "This action can no longer be decided.", status: decided.status };
  if (p.data.decision === "decline") return { ok: true, message: "Declined.", status: "declined" };

  const tool = decided.tool ? toolByName(decided.tool) : undefined;
  let outcome: { ok: boolean; result?: unknown; error?: string };
  if (!tool || tool.kind !== "act") {
    outcome = { ok: false, error: "this action's tool no longer exists" };
  } else {
    const args = tool.input.safeParse(decided.args ?? {});
    if (!args.success) {
      outcome = {
        ok: false,
        error: `the arguments are not valid any more: ${args.error.issues[0]?.message ?? "invalid"}`,
      };
    } else {
      const call = tool.call(args.data as Record<string, unknown>);
      try {
        if ("local" in call) {
          const v = await runValidate(call.item, me.email);
          outcome = { ok: v.ok, result: { validated: v.ok, detail: v.detail }, ...(v.ok ? {} : { error: v.detail }) };
        } else {
          const data = await ui(call.fn, okSchema, { ...call.args, p_request_id: requestId });
          outcome = { ok: true, result: data };
        }
      } catch (e) {
        outcome = { ok: false, error: e instanceof UiError ? e.message : "the call failed" };
        log("warn", "chat.action.failed", { requestId, tool: tool.name, error: outcome.error });
      }
    }
  }
  try {
    await db.actionResult(p.data.id, outcome.ok, outcome.result ?? null, outcome.error ?? null);
  } catch (e) {
    log("error", "chat.action.record_failed", { requestId, error: e instanceof Error ? e.message : "error" });
  }
  return outcome.ok
    ? { ok: true, message: `Done: ${decided.summary ?? "the action ran"}.`, status: "done" }
    : { ok: false, error: outcome.error ?? "The action failed.", status: "failed" };
}

export async function archiveChatThread(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ id: z.coerce.number().int().positive() }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_chat_thread_archive", { p_id: p.data.id }, "Archived.");
}
