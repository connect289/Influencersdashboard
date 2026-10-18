import "server-only";
// Loaders for the privacy page (creator) and the privacy-requests queue (staff with privacy.manage).
import { z } from "zod";
import type { Db } from "@/lib/contracts/data";

export const myRequest = z.object({
  id: z.uuid(),
  kind: z.enum(["export", "deletion"]),
  status: z.enum(["requested", "ready", "completed", "rejected", "expired", "purged"]),
  requested_at: z.string(),
  decided_at: z.string().nullable(),
  decision_note: z.string().nullable(),
  file_ready: z.boolean(),
  file_expires_at: z.string().nullable(),
  purge_on: z.string().nullable(),
});
export type MyRequest = z.infer<typeof myRequest>;

export async function loadMyPrivacyRequests(db: Db): Promise<MyRequest[]> {
  const { data, error } = await db.rpc("my_privacy_requests");
  if (error) throw new Error(error.message);
  return z.array(myRequest).parse(data ?? []);
}

export const consentRow = z.object({
  purpose: z.string(),
  channel: z.enum(["email", "whatsapp"]),
  granted: z.boolean(),
  detail: z.string().nullable(),
  created_at: z.string(),
});
export type ConsentRow = z.infer<typeof consentRow>;

export async function loadMyConsents(db: Db): Promise<ConsentRow[]> {
  const { data } = await db.rpc("my_consents");
  return z
    .array(consentRow)
    .catch([])
    .parse(data ?? []);
}

export const staffRequest = z.object({
  id: z.uuid(),
  kind: z.enum(["export", "deletion"]),
  status: myRequest.shape.status,
  reason: z.string().nullable(),
  requested_at: z.string(),
  decided_at: z.string().nullable(),
  decision_note: z.string().nullable(),
  purge_on: z.string().nullable(),
  creator_id: z.uuid(),
  creator: z.string(),
  handle: z.string().nullable(),
  decided_by: z.string().nullable(),
});
export type StaffRequest = z.infer<typeof staffRequest>;

export async function loadPrivacyRequests(db: Db): Promise<StaffRequest[]> {
  const { data, error } = await db.rpc("privacy_requests_list");
  if (error) throw new Error(error.message);
  return z.array(staffRequest).parse(data ?? []);
}

export const deletionFacts = z.object({
  last_record_on: z.string().nullable(),
  open_deals: z.number(),
  balance_paise: z.coerce.number(),
  retention_years: z.number(),
  today: z.string(),
});

export async function loadDeletionFacts(db: Db, requestId: string) {
  const { data, error } = await db.rpc("privacy_deletion_facts", { p_request: requestId });
  if (error) return null;
  return deletionFacts.parse(data);
}
