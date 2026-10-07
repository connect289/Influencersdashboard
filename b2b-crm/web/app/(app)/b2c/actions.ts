"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import type { LinkLead, LinkSettings } from "@/lib/b2c-link";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();

/** Messages the b2b functions raise for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}

async function rpc(fn: string, args?: Record<string, unknown>) {
  const supabase = await createClient();
  return supabase.schema("b2b").rpc(fn, args);
}

const SettingsSchema = z.object({
  enabled: z.boolean(),
  scope: z.enum(["held", "all"]),
  writable: z.array(z.string().regex(/^[a-z_]{1,40}$/)).max(100),
  reason: z.string().trim().min(3, "Give a reason (3 to 300 characters).").max(300),
});

export async function saveLinkSettings(s: LinkSettings & { reason: string }): Promise<string | void> {
  await assertAdmin();
  const p = SettingsSchema.safeParse(s);
  if (!p.success) return p.error.issues[0]?.message ?? "Check the settings.";
  const { reason, ...settings } = p.data;
  const { error } = await rpc("b2c_link_settings_save", { p: settings, p_reason: reason });
  if (error) return dbMessage(error, "Could not save. Try again.");
  revalidatePath("/b2c");
}

/** Re-sends one lead, or every lead in scope when id is null. */
export async function resync(id: number | null): Promise<{ ok: true; leads: number } | { ok: false; error: string }> {
  await assertAdmin();
  if (id !== null && !Id.safeParse(id).success) return { ok: false, error: "Give a lead number." };
  const { data, error } = await rpc("b2c_link_resync", { p_lead_id: id });
  if (error) return { ok: false, error: dbMessage(error, "Could not resend. Try again.") };
  revalidatePath("/b2c");
  return { ok: true, leads: Number((data as { leads?: number } | null)?.leads ?? 0) };
}

export async function inspectLead(id: number): Promise<{ ok: true; data: LinkLead } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return { ok: false, error: "Give a lead number." };
  const { data, error } = await rpc("b2c_link_lead", { p_lead_id: id });
  if (error) return { ok: false, error: dbMessage(error, "Could not read the lead. Try again.") };
  return { ok: true, data: data as LinkLead };
}
