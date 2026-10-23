"use server";
import { z } from "zod";
import { act, fields, invalid, type ActionResult } from "./act.ts";

const reason = z.string().trim().min(3, "Give a reason of at least 3 characters.").max(500);

/** A whole settings value, edited as JSON, saved as a new version with a reason. */
export async function saveSetting(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ key: z.string().regex(/^[a-z_]{2,40}$/), value: z.string(), reason }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  let value: unknown;
  try {
    value = JSON.parse(p.data.value);
  } catch {
    return { ok: false, error: "The value is not valid JSON." };
  }
  if (typeof value !== "object" || value === null || Array.isArray(value))
    return { ok: false, error: "A setting is a JSON object." };
  return act(
    "ui_settings_put",
    { p_key: p.data.key, p_value: value, p_reason: p.data.reason },
    ["/settings", `/settings/${p.data.key}`],
    "Saved as a new version.",
  );
}

export async function updateCheck(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({
      id: z.string().regex(/^[A-Z0-9]+(-[A-Za-z0-9:._]+)+$/),
      enabled: z.enum(["on", "off"]).optional(),
      severity: z.enum(["P1", "P2", "P3"]).optional(),
      cadence_s: z.coerce.number().int().min(60).max(604800).optional(),
      open_after: z.coerce.number().int().min(1).max(60).optional(),
      resolve_after: z.coerce.number().int().min(1).max(60).optional(),
      reason,
    })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  const { id, enabled, reason: why, ...rest } = p.data;
  const patch = { ...rest, ...(enabled ? { enabled: enabled === "on" } : {}) };
  return act(
    "ui_check_update",
    { p_id: id, p_patch: patch, p_reason: why },
    ["/settings/checks", "/"],
    "Check updated.",
  );
}

export async function acceptBaseline(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({ key: z.enum(["lead_intake_md5", "student_leads_columns", "security_definer_views"]) })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act(
    "ui_baseline_accept",
    { p_key: p.data.key },
    ["/settings/privileges"],
    "The current state is the new baseline.",
  );
}

export async function acknowledgePrivilege(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ fn: z.string().min(3).max(300) }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_privilege_ack", { p_fn: p.data.fn }, ["/settings/privileges"], "Acknowledged.");
}

export async function putUser(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({
      email: z.email().max(254),
      role: z.enum(["owner", "engineer"]),
      active: z.enum(["on", "off"]).default("on"),
    })
    .safeParse({ ...fields(form), active: form.get("active") === "on" ? "on" : "off" });
  if (!p.success) return invalid(p.error.issues);
  return act(
    "ui_user_put",
    { p_email: p.data.email, p_role: p.data.role, p_active: p.data.active === "on" },
    ["/settings/users"],
    "Saved.",
  );
}

export async function revokeDevices(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ user_id: z.uuid() }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_devices_revoke", { p_user: p.data.user_id }, ["/settings/users"], "Trusted browsers forgotten.");
}

export async function updateTest(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({
      id: z.string().regex(/^T-[A-Z0-9-]+$/),
      enabled: z.enum(["on", "off"]).optional(),
      schedule: z
        .string()
        .trim()
        .regex(/^(\S+\s+){4}\S+$/, "A 5-field cron expression.")
        .optional(),
      reason,
    })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  const { id, enabled, schedule, reason: why } = p.data;
  return act(
    "ui_test_update",
    {
      p_id: id,
      p_patch: { ...(enabled ? { enabled: enabled === "on" } : {}), ...(schedule ? { schedule } : {}) },
      p_reason: why,
    },
    ["/tests"],
    "Test updated.",
  );
}

export async function runTest(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ id: z.string().regex(/^T-[A-Z0-9-]+$/) }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_test_run", { p_id: p.data.id }, ["/tests"], "Requested: the test runner takes it on its next tick.");
}
