"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { ApiKeySchema, EndpointSchema, referralCodesProblem } from "@/lib/integrations";
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

/** Creates an API key and returns it once; only its hash is stored. A referrals key is linked to its codes (M34d). */
export async function createApiKey(name: string, scopes: string[], expiresDays?: number, ratePerMinute?: number | null,
                                   referralCodes: string[] = []): Promise<SecretResult> {
  await assertAdmin();
  const p = ApiKeySchema.safeParse({ name, scopes, expires_days: expiresDays ?? 0, rate_per_minute: ratePerMinute ?? null, referral_codes: referralCodes });
  if (!p.success) return { ok: false, error: "Check the highlighted fields.", errors: zodErrors(p.error.issues) };
  const expiresAt = p.data.expires_days > 0 ? new Date(Date.now() + p.data.expires_days * 86400000).toISOString() : null;
  const { data, error } = await rpc("api_key_create", { p: { name: p.data.name, scopes: p.data.scopes, expires_at: expiresAt, rate_per_minute: p.data.rate_per_minute,
                                                             referral_codes: p.data.referral_codes } });
  if (error || !data) return { ok: false, error: error ? dbMessage(error, "Could not create the key. Try again.") : "Could not create the key. Try again." };
  refresh();
  return { ok: true, secret: (data as { key: string }).key };
}

/** M34d: replaces the referral codes a referrals key may read. */
export async function setKeyReferralCodes(id: number, codes: string[]): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid key.";
  const problem = z.array(z.string().max(70)).max(200).safeParse(codes).success ? referralCodesProblem(["referrals"], codes) : "At most 200 codes.";
  if (problem) return problem;
  const { error } = await rpc("api_key_update", { p_id: id, p: { referral_codes: codes } });
  if (error) return dbMessage(error, "Could not save the codes. Try again.");
  refresh();
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


// ---------- M33c: data protection ----------
export async function saveRetention(inactiveMonths: number | null, testLeadDays: number | null, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({
    inactiveMonths: z.number().int().min(6).max(120).nullable(), testLeadDays: z.number().int().min(1).max(365).nullable(),
    reason: z.string().trim().min(3, "Give a reason (3 to 300 characters).").max(300),
  }).safeParse({ inactiveMonths, testLeadDays, reason });
  if (!p.success) return p.error.issues[0]?.message ?? "Check the fields.";
  const { error } = await rpc("retention_settings_save", { p: { inactive_months: p.data.inactiveMonths, test_lead_days: p.data.testLeadDays }, p_reason: p.data.reason });
  if (error) return dbMessage(error, "Could not save. Try again.");
  refresh();
}

export async function anonymiseLead(leadId: number, reason: string): Promise<{ ok: true; partners: number[] } | { ok: false; error: string }> {
  await assertAdmin();
  const p = z.object({ leadId: z.number().int().positive(), reason: z.string().trim().min(3, "Give a reason (3 to 300 characters).").max(300) }).safeParse({ leadId, reason });
  if (!p.success) return { ok: false, error: p.error.issues[0]?.message ?? "Check the fields." };
  const { data, error } = await rpc("lead_anonymise", { p_lead_id: p.data.leadId, p_reason: p.data.reason, p_source: "admin" });
  if (error) return { ok: false, error: dbMessage(error, "Could not erase. Try again.") };
  refresh(); revalidatePath("/leads");
  return { ok: true, partners: ((data as { partners_to_notify?: number[] })?.partners_to_notify ?? []) };
}
