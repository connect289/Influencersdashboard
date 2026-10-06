"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { SettingsSchema, TemplateSchema, settingsPayload, zodErrors, type Preview } from "@/lib/notifications";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();

/** Messages raised by the b2b functions for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}

async function rpc(fn: string, args?: Record<string, unknown>) {
  const supabase = await createClient();
  return supabase.schema("b2b").rpc(fn, args);
}

const refresh = () => revalidatePath("/notifications");

export type FormState = { errors?: Record<string, string>; error?: string; ok?: number } | undefined;

const SETTINGS_FIELDS = ["quiet_start", "quiet_end", "support_contact", "unsubscribe_url", "wa_phone_number_id", "wa_api_version", "wa_token",
  "email_provider", "email_from", "email_from_name", "email_reply_to", "email_api_key", "reason"] as const;

export async function saveNotificationSettings(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const p = SettingsSchema.safeParse(Object.fromEntries(SETTINGS_FIELDS.map((k) => [k, String(form.get(k) ?? "")])));
  if (!p.success) return { errors: zodErrors(p.error.issues), error: "Check the highlighted fields." };
  const { error } = await rpc("notification_settings_save", { p: settingsPayload(p.data), p_reason: p.data.reason });
  if (error) return { error: dbMessage(error, "Could not save the settings. Try again.") };
  refresh();
  return { ok: Date.now() };
}

export async function saveTemplate(id: number, _prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return { error: "Invalid template." };
  const raw = Object.fromEntries(["channel", "subject", "body", "wa_template", "wa_language", "status"].map((k) => [k, String(form.get(k) ?? "")]));
  const p = TemplateSchema.safeParse(raw);
  if (!p.success) return { errors: zodErrors(p.error.issues), error: "Check the highlighted fields." };
  const { channel: _c, ...rest } = p.data;
  const { error } = await rpc("template_save", { p: { id, ...rest } });
  if (error) return { error: dbMessage(error, "Could not save the template. Try again.") };
  refresh();
  return { ok: Date.now() };
}

/** What a student would receive for a saved template and a partner (sample student, the partner's real name and hours). */
export async function previewTemplate(templateId: number, partnerId: number | null): Promise<{ ok: true; preview: Preview } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(templateId).success || (partnerId !== null && !Id.safeParse(partnerId).success)) return { ok: false, error: "Invalid choice." };
  const { data, error } = await rpc("notification_preview", { p_template_id: templateId, p_partner_id: partnerId });
  if (error || !data) return { ok: false, error: "Could not build the preview. Try again." };
  return { ok: true, preview: data as Preview };
}

export async function setChannelLive(channel: "whatsapp" | "email", live: boolean, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ channel: z.enum(["whatsapp", "email"]), live: z.boolean(), reason: z.string().trim().min(3).max(300) }).safeParse({ channel, live, reason });
  if (!p.success) return "A reason is required.";
  const { error } = await rpc("set_live_switch", { p_scope: p.data.channel, p_live: p.data.live, p_reason: p.data.reason });
  if (error) return dbMessage(error, "Could not change the switch. Try again.");
  refresh();
}

export async function retryNotification(id: number): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid message.";
  const { error } = await rpc("notification_retry", { p_id: id });
  if (error) return dbMessage(error, "Could not queue the message again. Try again.");
  refresh();
}
