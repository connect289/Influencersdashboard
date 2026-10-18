import "server-only";
// Loaders for the admin communication tools; each inf.* function returns nothing to staff without the permission.
import { z } from "zod";
import type { Db } from "@/lib/contracts/data";
import { segmentSchema } from "@/lib/notify/segments";

const ts = z.string();

export const templateVersion = z.object({
  id: z.uuid(),
  channel: z.enum(["email", "whatsapp"]),
  version: z.number(),
  subject: z.string().nullable(),
  body: z.string(),
  wa_template_name: z.string().nullable(),
  active: z.boolean(),
  updated_at: ts,
  updated_by: z.string().nullable(),
});
export type TemplateVersion = z.infer<typeof templateVersion>;

export const templateEvent = z.object({
  event: z.string(),
  group: z.string(),
  audience: z.array(z.string()),
  mandatory: z.boolean(),
  channels: z.array(z.string()),
  vars: z.array(z.string()),
  templates: z.array(templateVersion),
});
export type TemplateEvent = z.infer<typeof templateEvent>;

export async function loadTemplates(db: Db): Promise<TemplateEvent[]> {
  const { data, error } = await db.rpc("notification_templates_list");
  if (error) throw new Error(error.message);
  return z.array(templateEvent).parse(data ?? []);
}

export const announcementRow = z.object({
  id: z.uuid(),
  title: z.string(),
  body: z.string(),
  link: z.string().nullable(),
  segment: segmentSchema.catch(segmentSchema.parse({})),
  channels: z.array(z.enum(["email", "whatsapp"])).catch([]),
  status: z.enum(["draft", "scheduled", "sent", "cancelled"]),
  scheduled_at: ts.nullable(),
  sent_at: ts.nullable(),
  recipients: z.number().nullable(),
  created_at: ts,
  created_by: z.string().nullable(),
});
export type AnnouncementAdminRow = z.infer<typeof announcementRow>;

export async function loadAnnouncements(db: Db): Promise<AnnouncementAdminRow[]> {
  const { data, error } = await db.rpc("announcements_list");
  if (error) throw new Error(error.message);
  return z.array(announcementRow).parse(data ?? []);
}

export const webhookDelivery = z.object({
  id: z.number(),
  event: z.string(),
  event_id: z.string(),
  status: z.enum(["queued", "delivered", "failed"]),
  attempts: z.number(),
  last_status: z.number().nullable(),
  last_error: z.string().nullable(),
  created_at: ts,
  delivered_at: ts.nullable(),
  next_attempt_at: ts.nullable(),
});
export const webhookEndpoint = z.object({
  id: z.uuid(),
  url: z.string(),
  description: z.string().nullable(),
  events: z.array(z.string()),
  active: z.boolean(),
  created_at: ts,
  last_success_at: ts.nullable(),
  failing_since: ts.nullable(),
  deliveries: z.array(webhookDelivery),
});
export type WebhookEndpoint = z.infer<typeof webhookEndpoint>;

export async function loadWebhooks(db: Db): Promise<WebhookEndpoint[]> {
  const { data, error } = await db.rpc("webhooks_list");
  if (error) throw new Error(error.message);
  return z.array(webhookEndpoint).parse(data ?? []);
}

/** Campaigns and tiers for the segment picker. */
export async function loadSegmentOptions(db: Db): Promise<{
  campaigns: { id: string; name: string }[];
  tiers: { id: string; name: string }[];
}> {
  const [campaigns, tiers] = await Promise.all([
    db.from("campaigns").select("id, name").in("status", ["open", "invite_only", "active"]).order("name"),
    db.from("tiers").select("id, name").eq("active", true).order("rank"),
  ]);
  return { campaigns: campaigns.data ?? [], tiers: tiers.data ?? [] };
}
