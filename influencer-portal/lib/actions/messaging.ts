"use server";
// Messages and notifications (spec 14). Anyone who may read a thread may write in it (staff with message.write);
// files go straight to private storage with a one-time signed upload under the thread's folder. Notification and
// digest choices belong to the signed-in person; mandatory events stay on. Each action validates its input and calls
// one inf.* function, which decides who may act.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { log } from "@/lib/log";
import { THREADS_BUCKET, threadFilePath } from "@/lib/messaging/files";
import {
  digestInput,
  MESSAGING_DB_ERRORS,
  postInput,
  preferenceInput,
  uploadRequest,
  type DigestInput,
  type PostInput,
  type PreferenceInput,
  type UploadRequest,
} from "@/lib/messaging/schemas";
import { adminClient } from "@/lib/supabase/admin";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
type DbError = { code?: string; message: string };

async function signedIn(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

function dbFail(error: DbError, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of MESSAGING_DB_ERRORS)
    if (re.test(error.message)) return fail(t(`messaging.errors.${key}` as "messaging.errors.empty"));
  if (error.code === "22023" || error.code === "23514") return fail(t("errors.invalidInput"));
  log.warn("messaging.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

async function act<S extends z.ZodType, Res extends ActionResult<unknown>>(
  schema: S,
  input: unknown,
  body: (db: ServerSupabase, v: z.output<S>, t: T) => Promise<Res>,
): Promise<Res | ActionResult<never>> {
  const t = await getTranslations();
  const parsed = schema.safeParse(input);
  if (!parsed.success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  return body(supabase, parsed.data, t);
}

function refreshInbox() {
  revalidatePath("/admin/messages");
  revalidatePath("/creator/messages");
  revalidatePath("/agency/messages");
}

/** Posts a message (and any files already uploaded under the thread's folder). */
export async function postMessage(input: PostInput): Promise<ActionResult<{ threadId: string }>> {
  return act(postInput, input, async (db, v, t) => {
    const { data, error } = await db.rpc("thread_post", {
      p_type: v.type,
      p_entity: v.entityId,
      p_body: v.body,
      p_attachments: v.attachments.map((a) => ({ path: a.path, name: a.name, mime: a.mime, size_bytes: a.size })),
      p_creator: v.creatorId ?? undefined,
    });
    if (error) return dbFail(error, t);
    refreshInbox();
    const threadId = z.object({ thread_id: z.uuid() }).parse(data).thread_id;
    return { ok: true, data: { threadId } };
  });
}

/** A one-time signed upload for one attachment, after the database confirms the caller may post on the thread. */
export async function threadUploadUrl(input: UploadRequest): Promise<ActionResult<{ path: string; token: string }>> {
  return act(uploadRequest, input, async (db, v, t) => {
    const { data: threadId, error } = await db.rpc("thread_open", {
      p_type: v.type,
      p_entity: v.entityId,
      p_creator: v.creatorId ?? undefined,
    });
    if (error || !threadId) return error ? dbFail(error, t) : fail(t("errors.forbidden"));
    const signed = await adminClient()
      .storage.from(THREADS_BUCKET)
      .createSignedUploadUrl(threadFilePath(threadId, v.fileName));
    if (signed.error) {
      log.error("thread.sign_failed", { error: signed.error.message });
      return fail(t("errors.generic"));
    }
    return { ok: true, data: { path: signed.data.path, token: signed.data.token } };
  });
}

/** Marks some notifications read (null = every unread one). */
export async function markNotificationsRead(ids: string[] | null): Promise<ActionResult> {
  return act(z.array(z.uuid()).max(100).nullable(), ids, async (db, v, t) => {
    const { error } = v
      ? await db.rpc("notifications_mark_read", { p_ids: v })
      : await db.rpc("notifications_mark_all_read");
    if (error) return dbFail(error, t);
    return { ok: true, message: v ? undefined : t("notifications.allRead") };
  });
}

export async function setNotificationPreference(input: PreferenceInput): Promise<ActionResult> {
  return act(preferenceInput, input, async (db, v, t) => {
    const { error } = await db.rpc("notification_preference_set", {
      p_event: v.event,
      p_channel: v.channel,
      p_enabled: v.enabled,
    });
    if (error) return dbFail(error, t);
    return { ok: true };
  });
}

export async function setDigestPreference(input: DigestInput): Promise<ActionResult> {
  return act(digestInput, input, async (db, v, t) => {
    const { error } = await db.rpc("digest_preference_set", { p_frequency: v.frequency, p_channel: v.channel });
    if (error) return dbFail(error, t);
    return { ok: true, message: t("notifications.prefs.digestSaved") };
  });
}
