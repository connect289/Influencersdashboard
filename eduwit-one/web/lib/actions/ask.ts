"use server";
import { z } from "zod";
import { act, fields, invalid, type ActionResult } from "./act.ts";

export async function ask(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ question: z.string().trim().min(3, "Ask a question.").max(2000) }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act(
    "ui_ask",
    { p_question: p.data.question },
    ["/ask"],
    "Asked: the answer appears below when the AI worker has it.",
  );
}

export async function pin(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ id: z.coerce.number().int().positive() }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_ask_pin", { p_task_id: p.data.id }, ["/ask", "/brief"], "Pinned to the next brief.");
}

export async function regenerateBrief(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ for_date: z.iso.date(), tier: z.enum(["quick", "regular", "deep"]) }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act(
    "ui_brief_regenerate",
    { p_for_date: p.data.for_date, p_tier: p.data.tier },
    ["/brief"],
    `Queued on the ${p.data.tier} tier.`,
  );
}

export async function saveView(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({
      page: z.enum(["analytics", "marketing"]),
      name: z.string().trim().min(1).max(80),
      params: z.string().default("{}"),
      schedule: z.enum(["", "daily", "weekly"]).default(""),
    })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  let params: unknown;
  try {
    params = JSON.parse(p.data.params);
  } catch {
    return { ok: false, error: "The view could not be read." };
  }
  return act(
    "ui_view_save",
    { p_page: p.data.page, p_name: p.data.name, p_params: params, p_schedule: p.data.schedule || null },
    [`/${p.data.page}`],
    "View saved.",
  );
}
