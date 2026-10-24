"use server";
import { z } from "zod";
import { act, fields, invalid, type ActionResult } from "./act.ts";

const id = z.coerce.number().int().positive();
const reason = z.string().trim().min(3, "Give a reason of at least 3 characters.").max(500);

export async function acknowledge(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ id }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_ack", { p_id: p.data.id }, "Acknowledged: reminders stop.");
}

export async function resolve(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({ id, resolution: z.enum(["fixed", "false_positive", "accepted", "manual"]), note: reason })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_resolve", { p_id: p.data.id, p_resolution: p.data.resolution, p_note: p.data.note }, "Resolved.");
}

export async function mute(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({
      target_type: z.enum(["check", "app"]),
      target: z.string().min(1).max(80),
      // From an incident page the form carries both; the choice of "what" picks one.
      app: z.string().min(1).max(40).optional(),
      minutes: z.coerce.number().int().min(1, "At least a minute.").max(10080, "At most 7 days."),
      reason,
    })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  const { target_type, minutes } = p.data;
  const target = target_type === "app" && p.data.app ? p.data.app : p.data.target;
  return act(
    "ui_mute",
    { p_target_type: target_type, p_target: target, p_minutes: minutes, p_reason: p.data.reason },
    `Muted for ${minutes} minutes.`,
  );
}

export async function unmute(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ id }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_unmute", { p_id: p.data.id }, "Mute ended.");
}

export async function rerunDeep(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ id }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_rerun_deep", { p_id: p.data.id }, "Queued for the deep model.");
}
