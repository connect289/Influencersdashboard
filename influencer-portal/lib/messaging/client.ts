// Browser calls for background reads and read receipts. They use route handlers, not server actions, so they never
// queue ahead of a navigation the person starts.
import { threadView, unreadCounts, type ThreadView, type UnreadCounts } from "./data-shapes";
import type { ThreadRef } from "./schemas";

export async function fetchUnreadCounts(): Promise<UnreadCounts | null> {
  const res = await fetch("/api/me/unread", { cache: "no-store" }).catch(() => null);
  if (!res?.ok) return null;
  const p = unreadCounts.safeParse(await res.json().catch(() => null));
  return p.success ? p.data : null;
}

export async function fetchThreadView(ref: ThreadRef): Promise<ThreadView | null> {
  const q = new URLSearchParams({
    type: ref.type,
    entity: ref.entityId,
    ...(ref.creatorId ? { creator: ref.creatorId } : {}),
  });
  const res = await fetch(`/api/threads?${q}`, { cache: "no-store" }).catch(() => null);
  if (!res?.ok) return null;
  const p = threadView.safeParse(await res.json().catch(() => null));
  return p.success ? p.data : null;
}

async function post(url: string, body: unknown): Promise<boolean> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  }).catch(() => null);
  return res?.ok === true;
}

export const markThreadReadNow = (threadId: string) => post("/api/threads/read", { threadId });
export const markNotificationsReadNow = (ids: string[]) => post("/api/notifications/read", { ids });
