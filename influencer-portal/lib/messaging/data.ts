import "server-only";
// Loaders for threads, the inbox and the notification centre. Every read goes through an inf.* function that decides
// what the caller may see (staff by permission, the creator, or an agency by its grants); lead notes are staff-only.
import { z } from "zod";
import type { Db } from "@/lib/contracts/data";
import { CHANNELS } from "@/lib/notify/catalogue";
import { DIGEST_FREQUENCIES } from "@/lib/notify/digest";
import { threadView, unreadCounts, type ThreadView, type UnreadCounts } from "./data-shapes";
import { THREAD_TYPES, type InboxFilter, type ThreadRef } from "./schemas";

const ts = z.string();

export {
  messageRow,
  threadView,
  unreadCounts,
  type MessageRow,
  type ThreadView,
  type UnreadCounts,
} from "./data-shapes";

/** A thread with its messages, or null when the caller may not read it. */
export async function loadThread(db: Db, ref: ThreadRef): Promise<ThreadView | null> {
  const { data, error } = await db.rpc("thread_get", {
    p_type: ref.type,
    p_entity: ref.entityId,
    p_creator: ref.creatorId ?? undefined,
  });
  if (error) {
    if (error.code === "42501") return null;
    throw new Error(error.message);
  }
  return threadView.parse(data);
}

export const inboxRow = z.object({
  id: z.uuid(),
  entity_type: z.enum(THREAD_TYPES),
  entity_id: z.uuid(),
  creator_id: z.uuid().nullable(),
  creator_name: z.string().nullable(),
  subject: z.string().nullable(),
  link: z.string().nullable(),
  last_message_at: ts.nullable(),
  last_message: z.string().nullable(),
  unread: z.number(),
  staff_only: z.boolean(),
});
export type InboxRow = z.infer<typeof inboxRow>;

export async function loadInbox(db: Db, f: InboxFilter = {}): Promise<InboxRow[]> {
  const { data, error } = await db.rpc("my_threads", {
    p: {
      q: f.q ?? "",
      type: f.type ?? "",
      unread: f.unread ?? false,
      mentions: f.mentions ?? false,
      creator_id: f.creatorId ?? "",
    },
  });
  if (error) throw new Error(error.message);
  return z.array(inboxRow).parse(data ?? []);
}

export const notificationRow = z.object({
  id: z.uuid(),
  event: z.string(),
  title: z.string(),
  body: z.string().nullable(),
  link: z.string().nullable(),
  read_at: ts.nullable(),
  created_at: ts,
  mandatory: z.boolean(),
});
export type NotificationRow = z.infer<typeof notificationRow>;

export const NOTIFICATIONS_PAGE = 30;

export async function loadNotifications(
  db: Db,
  opts: { before?: string; unread?: boolean } = {},
): Promise<NotificationRow[]> {
  const { data, error } = await db.rpc("my_notifications_page", {
    p_limit: NOTIFICATIONS_PAGE,
    p_before: opts.before,
    p_unread: opts.unread ?? false,
  });
  if (error) throw new Error(error.message);
  return z.object({ items: z.array(notificationRow) }).parse(data ?? { items: [] }).items;
}

export const preferencesView = z.object({
  prefs: z.array(z.object({ event: z.string(), channel: z.enum(CHANNELS), enabled: z.boolean() })),
  digest: z.object({ frequency: z.enum(DIGEST_FREQUENCIES), channel: z.enum(["email", "whatsapp"]) }).nullable(),
});
export type PreferencesView = z.infer<typeof preferencesView>;

export async function loadPreferences(db: Db): Promise<PreferencesView> {
  const { data, error } = await db.rpc("my_notification_preferences");
  if (error) throw new Error(error.message);
  return preferencesView.parse(data ?? { prefs: [], digest: null });
}

export async function loadUnreadCounts(db: Db): Promise<UnreadCounts> {
  const { data, error } = await db.rpc("my_unread_counts");
  if (error || !data) return { notifications: 0, messages: 0 };
  return unreadCounts.catch({ notifications: 0, messages: 0 }).parse(data);
}

export const mentionable = z.array(z.object({ user_id: z.uuid(), full_name: z.string() }));

export async function loadMentionable(db: Db): Promise<z.infer<typeof mentionable>> {
  const { data } = await db.rpc("mentionable_staff");
  return mentionable.catch([]).parse(data ?? []);
}

export const announcementRow = z.object({
  id: z.uuid(),
  title: z.string(),
  body: z.string().nullable(),
  link: z.string().nullable(),
  created_at: ts,
  read_at: ts.nullable(),
});
export type AnnouncementRow = z.infer<typeof announcementRow>;

export async function loadMyAnnouncements(db: Db, limit = 3): Promise<AnnouncementRow[]> {
  const { data } = await db.rpc("my_announcements", { p_limit: limit });
  return z
    .array(announcementRow)
    .catch([])
    .parse(data ?? []);
}
