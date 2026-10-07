"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import type { AdapterPreview, AdapterStatus } from "@/lib/adapters";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();
const Env = z.enum(["live", "sandbox"]);
type Result<T> = { ok: true; data: T } | { ok: false; error: string };

/** Messages raised by the b2b functions for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
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
});
export type AdapterForm = z.input<typeof SaveSchema>;

/** Settings and secrets for one environment. Secrets go to Vault; empty secret fields keep the stored ones. */
export async function saveAdapter(partnerId: number, f: AdapterForm): Promise<Result<AdapterStatus>> {
  const p = SaveSchema.safeParse(f);
  if (!p.success) return { ok: false, error: "Check the fields." };
  const d = p.data;
  const r = await call<AdapterStatus>(partnerId, "partner_adapter_save", { p_partner_id: partnerId, p: {
    env: d.env, settings: d.settings, secrets: Object.fromEntries(Object.entries(d.secrets).filter(([, v]) => v)),
    reference_field: d.reference_field || null, status_field: d.status_field || null, poll: d.poll,
    ...(d.poll_minutes ? { poll_minutes: Number(d.poll_minutes) } : {}),
    fixed: Object.fromEntries(d.fixed.filter((x) => x.k).map((x) => [x.k, x.v])),
  } }, "Could not save. Try again.");
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
