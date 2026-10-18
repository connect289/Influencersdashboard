// Messages and notifications (spec 14): what a thread is about, what a message may carry, and the notification and
// digest choices a person can make. Shared by the server actions and the client forms.
import { z } from "zod";
import { CHANNELS } from "@/lib/notify/catalogue";
import { DIGEST_FREQUENCIES } from "@/lib/notify/digest";

export const THREAD_TYPES = [
  "application",
  "campaign",
  "deal",
  "contract",
  "brief",
  "deliverable",
  "payout",
  "lead",
  "support",
] as const;
export type ThreadType = (typeof THREAD_TYPES)[number];

/** Private bucket for message attachments (under threads/<thread>/). */
export const ATTACHMENTS_BUCKET = "inf-documents";
export const MESSAGE_MAX = 4000;
export const ATTACHMENTS_MAX = 5;
export const ATTACHMENT_MAX_BYTES = 25 * 1024 * 1024;
export const ATTACHMENT_TYPES = ["application/pdf", "image/jpeg", "image/png", "text/csv"] as const;
export type AttachmentType = (typeof ATTACHMENT_TYPES)[number];

export function isAttachmentType(t: string): t is AttachmentType {
  return (ATTACHMENT_TYPES as readonly string[]).includes(t);
}

/** Which conversation: an entity, and the creator for campaign threads (one private thread per creator). */
export const threadRef = z.object({
  type: z.enum(THREAD_TYPES),
  entityId: z.uuid(),
  creatorId: z.uuid().nullable().optional(),
});
export type ThreadRef = z.infer<typeof threadRef>;

export const attachment = z.object({
  path: z.string().regex(/^threads\/[0-9a-f-]{36}\/[0-9a-f-]{36}-[A-Za-z0-9._-]{1,120}$/),
  name: z.string().min(1).max(200),
  mime: z.enum(ATTACHMENT_TYPES),
  size: z.number().int().min(1).max(ATTACHMENT_MAX_BYTES),
});
export type Attachment = z.infer<typeof attachment>;

export const postInput = threadRef
  .extend({
    body: z.string().trim().max(MESSAGE_MAX),
    attachments: z.array(attachment).max(ATTACHMENTS_MAX).default([]),
  })
  .refine((v) => v.body.length > 0 || v.attachments.length > 0, { path: ["body"] });
export type PostInput = z.input<typeof postInput>;

export const uploadRequest = threadRef.extend({
  fileName: z.string().min(1).max(200),
  mime: z.enum(ATTACHMENT_TYPES),
  size: z.number().int().min(1).max(ATTACHMENT_MAX_BYTES),
});
export type UploadRequest = z.input<typeof uploadRequest>;

export const preferenceInput = z.object({
  event: z.string().regex(/^[a-z_]+(\.[a-z_]+)?$/),
  channel: z.enum(CHANNELS).exclude(["in_app"]),
  enabled: z.boolean(),
});
export type PreferenceInput = z.infer<typeof preferenceInput>;

export const digestInput = z.object({
  frequency: z.enum(DIGEST_FREQUENCIES),
  channel: z.enum(["email", "whatsapp"]),
});
export type DigestInput = z.infer<typeof digestInput>;

export const inboxFilter = z.object({
  q: z.string().trim().max(100).optional(),
  type: z.enum(THREAD_TYPES).optional(),
  unread: z.boolean().optional(),
  mentions: z.boolean().optional(),
  creatorId: z.uuid().optional(),
});
export type InboxFilter = z.infer<typeof inboxFilter>;

/** Database messages mapped to message keys under `messaging.errors`. */
export const MESSAGING_DB_ERRORS: readonly (readonly [RegExp, string])[] = [
  [/a message is required/, "empty"],
  [/message too long/, "tooLong"],
  [/at most 5 attachments/, "tooManyFiles"],
  [/invalid file/, "file"],
  [/cannot be turned off/, "mandatory"],
  [/invalid digest choice/, "invalidInput"],
];
