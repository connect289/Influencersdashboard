"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { adapterSavePayload, type AdapterPreview, type AdapterStatus } from "@/lib/adapters";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();
const Env = z.enum(["live", "sandbox"]);
type Result<T> = { ok: true; data: T } | { ok: false; error: string };

/**
 * Messages raised by the b2b functions for the Admin (22023, P0002) are safe to show as they are: partner_adapter_save's refusals
 * ('the access key is required', 'dedupe_confirmed: true or false', 'poll every 2 to 1,440 minutes' …) name the field. Others are generic.
 */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1).replace(/\.$/, "") + ".";
  if (error.code === "42501") return "Not allowed: only an Admin can change a partner's connection.";
  return fallback;
}

async function call<T>(partnerId: number, fn: string, args: Record<string, unknown>, fallback: string): Promise<Result<T>> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success) return { ok: false, error: "Invalid partner." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) return { ok: false, error: dbMessage(error, fallback) };
  return { ok: true, data: data as T };
}

const Text = z.string().trim().max(300);
const SaveSchema = z.object({
  env: Env,
  settings: z.record(z.string().max(40), Text),
  secrets: z.record(z.string().max(40), z.string().max(4000)),
  reference_field: Text, status_field: Text,
  poll: z.boolean(), poll_minutes: z.string().max(5),
  fixed: z.array(z.object({ k: z.string().trim().max(80), v: z.string().trim().max(500) })).max(20),
  /** D37: 'This CRM blocks duplicates on create'. Absent or null, partner_adapter_save keeps the stored confirmation. */
  dedupe_confirmed: z.boolean().nullable().optional(),
});
export type AdapterForm = z.input<typeof SaveSchema>;

/**
 * Settings and secrets for one environment, plus the partner-wide duplicate-blocking confirmation (b2b.partner_adapter_save, m31i 24:
 * confirmed → dedupe_mode 'sync' and a 0-minute hold, otherwise 'async' and 30 minutes). Secrets go to Vault; empty secret fields
 * keep the stored ones. The function's 22023 refusals are returned as the error text.
 */
export async function saveAdapter(partnerId: number, f: AdapterForm): Promise<Result<AdapterStatus>> {
  const p = SaveSchema.safeParse(f);
  if (!p.success) return { ok: false, error: "Check the fields." };
  const r = await call<AdapterStatus>(partnerId, "partner_adapter_save", { p_partner_id: partnerId, p: adapterSavePayload(p.data) }, "Could not save. Try again.");
  if (r.ok) revalidatePath(`/partners/${partnerId}`);
  return r;
}

/** Fetch the CRM's fields now (a schema snapshot for Mapping studio) or poll for changed leads now. Answers arrive within a minute. */
export async function adapterAction(partnerId: number, env: "live" | "sandbox", action: "schema" | "poll"): Promise<Result<unknown>> {
  if (!Env.safeParse(env).success || !["schema", "poll"].includes(action)) return { ok: false, error: "Unknown action." };
  const r = await call<unknown>(partnerId, "partner_adapter_action", { p_partner_id: partnerId, p_env: env, p_action: action }, "Could not reach the CRM. Try again.");
  if (r.ok) revalidatePath(`/partners/${partnerId}`);
  return r;
}

export async function adapterStatus(partnerId: number): Promise<Result<AdapterStatus>> {
  return call<AdapterStatus>(partnerId, "partner_adapter_status", { p_partner_id: partnerId }, "Could not read the status.");
}

/** The create call the latest lead (or a sample student) would make; credentials masked. */
export async function adapterPreview(partnerId: number, env: "live" | "sandbox"): Promise<Result<AdapterPreview>> {
  if (!Env.safeParse(env).success) return { ok: false, error: "Unknown environment." };
  return call<AdapterPreview>(partnerId, "partner_adapter_preview", { p_partner_id: partnerId, p_env: env }, "Could not build the preview.");
}
