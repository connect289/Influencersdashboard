"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { ApiKeySchema, EndpointSchema } from "@/lib/integrations";
import { zodErrors } from "@/lib/notifications";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();
const Reason = z.string().trim().min(3).max(300);

/** Messages raised by the b2b functions for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}

async function rpc(fn: string, args?: Record<string, unknown>) {
  const supabase = await createClient();
  return supabase.schema("b2b").rpc(fn, args);
}

const refresh = () => revalidatePath("/system");

export type SecretResult = { ok: true; secret: string } | { ok: false; error: string; errors?: Record<string, string> };

/** Creates an API key and returns it once; only its hash is stored. */
export async function createApiKey(name: string, scopes: string[]): Promise<SecretResult> {
  await assertAdmin();
  const p = ApiKeySchema.safeParse({ name, scopes });
  if (!p.success) return { ok: false, error: "Check the highlighted fields.", errors: zodErrors(p.error.issues) };
  const { data, error } = await rpc("create_api_key", { p_name: p.data.name, p_scopes: p.data.scopes });
  if (error || !data) return { ok: false, error: error ? dbMessage(error, "Could not create the key. Try again.") : "Could not create the key. Try again." };
  refresh();
  return { ok: true, secret: (data as { key: string }).key };
}

export async function revokeApiKey(id: number): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid key.";
  const { data, error } = await rpc("revoke_api_key", { p_id: id });
  if (error) return dbMessage(error, "Could not revoke the key. Try again.");
  if (data === false) return "This key is already revoked.";
  refresh();
}

export type EndpointForm = { name: string; consumer: string; url: string; events: string[] };

export async function saveEndpoint(id: number | null, f: EndpointForm): Promise<{ ok: true; id: number } | { ok: false; error: string; errors?: Record<string, string> }> {
  await assertAdmin();
  if (id !== null && !Id.safeParse(id).success) return { ok: false, error: "Invalid endpoint." };
  const p = EndpointSchema.safeParse(f);
  if (!p.success) return { ok: false, error: "Check the highlighted fields.", errors: zodErrors(p.error.issues) };
  const { data, error } = await rpc("webhook_endpoint_save", { p: { ...(id ? { id } : {}), ...p.data } });
  if (error || !data) return { ok: false, error: error ? dbMessage(error, "Could not save the endpoint. Try again.") : "Could not save the endpoint. Try again." };
  refresh();
  return { ok: true, id: (data as { id: number }).id };
}

/** A new signing secret, shown once. The previous one stops working immediately (on both sides). */
export async function rotateEndpointSecret(id: number): Promise<SecretResult> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return { ok: false, error: "Invalid endpoint." };
  const { data, error } = await rpc("webhook_endpoint_rotate_secret", { p_id: id });
  if (error || typeof data !== "string") return { ok: false, error: error ? dbMessage(error, "Could not create the secret. Try again.") : "Could not create the secret. Try again." };
  refresh();
  return { ok: true, secret: data };
}

export async function setEndpointActive(id: number, active: boolean, reason: string): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid endpoint.";
  if (!Reason.safeParse(reason).success) return "A reason is required.";
  const { error } = await rpc("webhook_endpoint_set_active", { p_id: id, p_active: active, p_reason: reason.trim() });
  if (error) return dbMessage(error, "Could not change the endpoint. Try again.");
  refresh();
}

export async function testEndpoint(id: number): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid endpoint.";
  const { error } = await rpc("webhook_test", { p_id: id });
  if (error) return dbMessage(error, "Could not queue the test event. Try again.");
  refresh();
}

export async function retryDelivery(id: number): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid delivery.";
  const { error } = await rpc("outbox_retry", { p_id: id });
  if (error) return dbMessage(error, "Could not send it again. Try again.");
  refresh();
}

export async function closeErasure(id: number, status: "done" | "rejected", note: string): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success || !["done", "rejected"].includes(status)) return "Invalid request.";
  if (!Reason.safeParse(note).success) return "A note is required.";
  const { error } = await rpc("erasure_request_close", { p_id: id, p_status: status, p_note: note.trim() });
  if (error) return dbMessage(error, "Could not close the request. Try again.");
  refresh();
}
