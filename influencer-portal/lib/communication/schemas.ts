// Admin communication tools (spec 14, 18): notification templates (versions, variables, preview, test send),
// announcements to creators or a segment, and outbound webhook endpoints. Shared by the server actions and forms.
import { z } from "zod";
import { literalHostAllowed } from "@/lib/webhooks/ssrf";
import { eventDef } from "@/lib/notify/catalogue";
import { unknownVars } from "@/lib/notify/render";
import { segmentSchema } from "@/lib/notify/segments";
import { WEBHOOK_EVENTS } from "@/lib/webhooks/sign";

const eventKey = z.string().refine((e) => eventDef(e) !== null);

export const templateInput = z
  .object({
    event: eventKey,
    channel: z.enum(["email", "whatsapp"]),
    subject: z.string().trim().max(200).default(""),
    body: z.string().trim().min(1).max(5000),
    waTemplateName: z
      .string()
      .trim()
      .max(512)
      .regex(/^[a-z0-9_]*$/)
      .default(""),
  })
  .superRefine((v, ctx) => {
    if (v.channel === "email" && !v.subject) ctx.addIssue({ code: "custom", path: ["subject"], message: "required" });
    if (v.channel === "whatsapp" && !v.waTemplateName)
      ctx.addIssue({ code: "custom", path: ["waTemplateName"], message: "required" });
    if (unknownVars(v.event, v.subject, v.body).length)
      ctx.addIssue({ code: "custom", path: ["body"], message: "unknown_vars" });
  });
export type TemplateInput = z.input<typeof templateInput>;

export const templateRef = z.object({ event: eventKey, channel: z.enum(["email", "whatsapp"]) });
export type TemplateRef = z.infer<typeof templateRef>;

export const templateTestInput = z.object({
  event: eventKey,
  subject: z.string().trim().min(1).max(200),
  body: z.string().trim().min(1).max(5000),
});
export type TemplateTestInput = z.infer<typeof templateTestInput>;

export const ANNOUNCEMENT_ACTIONS = ["draft", "schedule", "send"] as const;

export const announcementInput = z
  .object({
    id: z.uuid().optional(),
    title: z.string().trim().min(3).max(120),
    body: z.string().trim().min(3).max(2000),
    link: z
      .string()
      .trim()
      .regex(/^(\/creator(\/[A-Za-z0-9/_\-?=&.%]*)?)?$/)
      .default(""),
    segment: segmentSchema,
    channels: z
      .array(z.enum(["email", "whatsapp"]))
      .max(2)
      .default([]),
    action: z.enum(ANNOUNCEMENT_ACTIONS),
    /** IST wall time from a datetime-local input, required to schedule. */
    scheduledAt: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/)
      .optional(),
  })
  .refine((v) => v.action !== "schedule" || !!v.scheduledAt, { path: ["scheduledAt"] });
export type AnnouncementInput = z.input<typeof announcementInput>;

export const webhookCreateInput = z.object({
  url: z
    .url()
    .max(500)
    .refine((u) => u.startsWith("https://"), { message: "https" })
    .refine(literalHostAllowed, { message: "private" }),
  description: z.string().trim().max(200).default(""),
  events: z.array(z.enum(WEBHOOK_EVENTS)).min(1),
});
export type WebhookCreateInput = z.input<typeof webhookCreateInput>;

export const webhookUpdateInput = z.object({
  id: z.uuid(),
  description: z.string().trim().max(200).optional(),
  events: z.array(z.enum(WEBHOOK_EVENTS)).min(1).optional(),
  active: z.boolean().optional(),
  rotateSecret: z.boolean().optional(),
});
export type WebhookUpdateInput = z.input<typeof webhookUpdateInput>;

/** Sample values for previews and test sends (never real people). */
export const SAMPLE_VARS: Readonly<Record<string, string>> = {
  name: "Riya",
  title: "Sample notification",
  body: "This is how the notification text appears.",
  link: "https://creators.eduwit.in/creator",
  campaign: "MBA Admissions 2027",
  deal: "Instagram reels – October",
  contract: "EDW-C-2026-0042",
  deliverable: "Reel 1: campus tour",
  amount: "₹4,500.00",
  utr: "HDFC0000123456",
  lead: "L-7K2Q",
  subject: "Deal: Instagram reels – October",
  sender: "Eduwit",
  creator: "Riya Sharma",
  count: "3",
};

/** Database messages mapped to keys under `communication.errors`. */
export const COMMUNICATION_DB_ERRORS: readonly (readonly [RegExp, string])[] = [
  [/unknown template variable/, "unknownVars"],
  [/invalid WhatsApp template name/, "waName"],
  [/choose a time in the future/, "pastTime"],
  [/only drafts and scheduled/, "notEditable"],
  [/this address cannot receive webhooks/, "privateUrl"],
  [/no such endpoint/, "noEndpoint"],
];
