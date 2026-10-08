"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { STAGES, type AttributionForm, type LeadCheck } from "@/lib/capi";
import { AttributionSchema, attributionPayload } from "@/lib/routing";
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

const refresh = () => revalidatePath("/capi");

const Stage = z.enum(STAGES);
const Secret = z.string().trim().max(2000).optional();
const SettingsSchema = z.object({
  consent: z.enum(["marketing", "sales"]),
  meta: z.object({
    dataset_id: z.string().trim().max(25), api_version: z.string().trim().max(10), test_event_code: z.string().trim().max(40), token: Secret,
    map: z.partialRecord(Stage, z.object({ event: z.string().trim().min(1).max(50), enabled: z.boolean() })),
  }),
  google: z.object({
    customer_id: z.string().trim().max(14), login_customer_id: z.string().trim().max(14), api_version: z.string().trim().max(6),
    client_id: z.string().trim().max(200), client_secret: Secret, refresh_token: Secret, developer_token: Secret,
    map: z.partialRecord(Stage, z.object({ action: z.string().trim().max(120).nullable(), enabled: z.boolean() })),
  }),
  values: z.object({ qualified: z.number().min(0).max(1), interested: z.number().min(0).max(1), applied: z.number().min(0).max(1) }).optional(),
  base_value_inr: z.number().min(0).max(10_000_000).optional(),
});
export type SettingsForm = z.input<typeof SettingsSchema>;

/** Secrets go to Vault and are never read back; empty fields leave a secret unchanged. */
export async function saveCapiSettings(f: SettingsForm): Promise<string | void> {
  await assertAdmin();
  const p = SettingsSchema.safeParse(f);
  if (!p.success) return "Check the highlighted fields.";
  const d = p.data;
  const google = { ...d.google, map: Object.fromEntries(Object.entries(d.google.map).map(([k, v]) => [k, { ...v, action: v.action || null }])) };
  const { error } = await rpc("capi_settings_save", { p: { ...d, google } });
  if (error) return dbMessage(error, "Could not save. Try again.");
  refresh();
}

/** What counts as a paid lead (D38): influencer or referral markers, campaigns never paid, Meta ad parameters. Saved as a
 *  new version of the 'attribution' setting with a reason through b2b.attribution_settings_save(p, p_reason); its 22023
 *  messages ('<list>: at most 50 entries', 'nothing to save', …) are shown as they are. */
export async function saveAttributionSettings(f: AttributionForm): Promise<{ ok: true; version: number | null } | { ok: false; error: string }> {
  await assertAdmin();
  const p = AttributionSchema.safeParse(f);
  if (!p.success) return { ok: false, error: p.error.issues[0]?.message ?? "Check the highlighted fields." };
  const { data, error } = await rpc("attribution_settings_save", { p: attributionPayload(p.data), p_reason: p.data.reason });
  if (error) return { ok: false, error: dbMessage(error, "Could not save the attribution settings. Try again.") };
  refresh();
  const version = (data as { version?: number | null } | null)?.version;
  return { ok: true, version: typeof version === "number" ? version : null };
}

export async function setCapiLive(platform: "meta" | "google", live: boolean, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ platform: z.enum(["meta", "google"]), live: z.boolean(), reason: z.string().trim().min(3).max(300) }).safeParse({ platform, live, reason });
  if (!p.success) return "A reason is required.";
  const { error } = await rpc("set_live_switch", { p_scope: `capi_${p.data.platform}`, p_live: p.data.live, p_reason: p.data.reason });
  if (error) return dbMessage(error, "Could not change the switch. Try again.");
  refresh();
}

export async function retryCapiEvent(id: number): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid event.";
  const { error } = await rpc("capi_retry", { p_id: id });
  if (error) return dbMessage(error, "Could not queue the event again. Try again.");
  refresh();
}

/** What Eduwit knows about one lead and the events it makes. With write, the events are logged (test leads as dry runs). */
export async function checkLead(id: number, write: boolean): Promise<{ ok: true; data: LeadCheck } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return { ok: false, error: "Give a lead number." };
  const { data, error } = await rpc("capi_lead_check", { p_lead_id: id, p_write: write });
  if (error) return { ok: false, error: dbMessage(error, "Could not check the lead. Try again.") };
  if (write) refresh();
  return { ok: true, data: data as LeadCheck };
}
