"use server";
// Admin communication tools (spec 14, 18): notification templates (Super Admin), announcements (Influencer Manager)
// and webhook endpoints (Super Admin). Each action validates its input and calls one inf.* function, which checks the
// permission. Webhook signing secrets are generated here and shown once; the database keeps them encrypted.
import { randomBytes } from "node:crypto";
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { toStaffMe, type StaffMe } from "@/lib/auth/me";
import {
  announcementInput,
  COMMUNICATION_DB_ERRORS,
  SAMPLE_VARS,
  templateInput,
  templateRef,
  templateTestInput,
  webhookCreateInput,
  webhookUpdateInput,
  type AnnouncementInput,
  type TemplateInput,
  type TemplateRef,
  type TemplateTestInput,
  type WebhookCreateInput,
  type WebhookUpdateInput,
} from "@/lib/communication/schemas";
import { istLocalToIso } from "@/lib/deals/schemas";
import { env } from "@/lib/env";
import { log } from "@/lib/log";
import { composeEmail } from "@/lib/notify/compose";
import { emailProvider } from "@/lib/notify/email";
import { segmentSchema, type Segment } from "@/lib/notify/segments";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
type DbError = { code?: string; message: string };

async function staffSession(): Promise<{ db: ServerSupabase; me: StaffMe } | null> {
  const db = await createClient();
  const raw = await fetchMe(db);
  const me = toStaffMe(raw);
  if (!me || !raw.session?.verified || raw.session.revoked) return null;
  return { db, me };
}

function dbFail(error: DbError, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of COMMUNICATION_DB_ERRORS)
    if (re.test(error.message)) return fail(t(`communication.errors.${key}` as "communication.errors.pastTime"));
  if (error.code === "22023" || error.code === "23514") return fail(t("errors.invalidInput"));
  log.warn("communication.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

async function act<S extends z.ZodType, Res extends ActionResult<unknown>>(
  schema: S,
  input: unknown,
  body: (db: ServerSupabase, v: z.output<S>, t: T, me: StaffMe) => Promise<Res>,
): Promise<Res | ActionResult<never>> {
  const t = await getTranslations();
  const parsed = schema.safeParse(input);
  if (!parsed.success) {
    const unknown = parsed.error.issues.some((i) => i.message === "unknown_vars");
    return fail(unknown ? t("communication.errors.unknownVars") : t("errors.invalidInput"));
  }
  const s = await staffSession();
  if (!s) return fail(t("errors.sessionEnded"));
  return body(s.db, parsed.data, t, s.me);
}

const refresh = (section: "templates" | "announcements" | "webhooks") =>
  revalidatePath(`/admin/communication/${section}`);

// ---------------------------------------------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------------------------------------------
export async function saveTemplate(input: TemplateInput): Promise<ActionResult<{ id: string }>> {
  return act(templateInput, input, async (db, v, t) => {
    const { data, error } = await db.rpc("notification_template_save", {
      p: {
        event: v.event,
        channel: v.channel,
        subject: v.channel === "email" ? v.subject : "",
        body: v.body,
        wa_template_name: v.channel === "whatsapp" ? v.waTemplateName : "",
      },
    });
    if (error) return dbFail(error, t);
    refresh("templates");
    return { ok: true, data: { id: data }, message: t("communication.templates.saved") };
  });
}

export async function resetTemplate(input: TemplateRef): Promise<ActionResult> {
  return act(templateRef, input, async (db, v, t) => {
    const { error } = await db.rpc("notification_template_reset", { p_event: v.event, p_channel: v.channel });
    if (error) return dbFail(error, t);
    refresh("templates");
    return { ok: true, message: t("communication.templates.resetDone") };
  });
}

/** Emails the draft, filled with sample values, to the signed-in staff member (only when live sending is on). */
export async function sendTemplateTest(input: TemplateTestInput): Promise<ActionResult> {
  return act(templateTestInput, input, async (_db, v, t, me) => {
    if (!me.permissions.has("notification_template.write")) return fail(t("errors.forbidden"));
    if (env().LIVE_MODE !== "on") return fail(t("communication.templates.liveOff"));
    if (!me.email) return fail(t("errors.generic"));
    const mail = composeEmail(
      {
        event: v.event,
        title: SAMPLE_VARS.title ?? "",
        body: SAMPLE_VARS.body ?? "",
        link: "/creator",
        data: SAMPLE_VARS,
      },
      { subject: `[Test] ${v.subject}`, body: v.body, wa_template_name: null },
      me.fullName.split(" ")[0] ?? me.fullName,
      env().NEXT_PUBLIC_SITE_URL,
    );
    try {
      await emailProvider().send({ ...mail, to: me.email });
    } catch (e) {
      log.warn("communication.test_send_failed", { error: e instanceof Error ? e.message : String(e) });
      return fail(t("communication.templates.testFailed"));
    }
    return { ok: true, message: t("communication.templates.testSent", { email: me.email }) };
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Announcements
// ---------------------------------------------------------------------------------------------------------------
export async function saveAnnouncement(input: AnnouncementInput): Promise<ActionResult<{ id: string }>> {
  return act(announcementInput, input, async (db, v, t) => {
    const { data, error } = await db.rpc("announcement_save", {
      p: {
        id: v.id ?? "",
        title: v.title,
        body: v.body,
        link: v.link,
        segment: v.segment,
        channels: v.channels,
        action: v.action,
        scheduled_at: v.action === "schedule" && v.scheduledAt ? istLocalToIso(v.scheduledAt) : "",
      },
    });
    if (error) return dbFail(error, t);
    refresh("announcements");
    return { ok: true, data: { id: data }, message: t(`communication.announcements.done.${v.action}`) };
  });
}

export async function cancelAnnouncement(id: string): Promise<ActionResult> {
  return act(z.uuid(), id, async (db, v, t) => {
    const { error } = await db.rpc("announcement_cancel", { p_id: v });
    if (error) return dbFail(error, t);
    refresh("announcements");
    return { ok: true, message: t("communication.announcements.cancelled") };
  });
}

/** How many creators a segment reaches right now (the form's live preview). */
export async function announcementAudience(segment: Segment): Promise<ActionResult<{ count: number }>> {
  return act(segmentSchema, segment, async (db, v, t) => {
    const { data, error } = await db.rpc("announcement_audience_count", { p_segment: v });
    if (error) return dbFail(error, t);
    return { ok: true, data: { count: data } };
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Webhooks
// ---------------------------------------------------------------------------------------------------------------
function newSecret(): string {
  return `whsec_${randomBytes(32).toString("hex")}`;
}

export async function createWebhook(input: WebhookCreateInput): Promise<ActionResult<{ secret: string }>> {
  return act(webhookCreateInput, input, async (db, v, t) => {
    const secret = newSecret();
    const { error } = await db.rpc("webhook_endpoint_create", {
      p: { url: v.url, description: v.description, events: v.events, secret },
    });
    if (error) return dbFail(error, t);
    refresh("webhooks");
    return { ok: true, data: { secret }, message: t("communication.webhooks.created") };
  });
}

export async function updateWebhook(input: WebhookUpdateInput): Promise<ActionResult<{ secret: string | null }>> {
  return act(webhookUpdateInput, input, async (db, v, t) => {
    const secret = v.rotateSecret ? newSecret() : null;
    const { error } = await db.rpc("webhook_endpoint_update", {
      p_id: v.id,
      p: {
        ...(v.description !== undefined ? { description: v.description } : {}),
        ...(v.events ? { events: v.events } : {}),
        ...(v.active !== undefined ? { active: v.active } : {}),
        ...(secret ? { secret } : {}),
      },
    });
    if (error) return dbFail(error, t);
    refresh("webhooks");
    return { ok: true, data: { secret }, message: t("communication.webhooks.updated") };
  });
}

export async function deleteWebhook(id: string): Promise<ActionResult> {
  return act(z.uuid(), id, async (db, v, t) => {
    const { error } = await db.rpc("webhook_endpoint_delete", { p_id: v });
    if (error) return dbFail(error, t);
    refresh("webhooks");
    return { ok: true, message: t("communication.webhooks.deleted") };
  });
}

export async function testWebhook(id: string): Promise<ActionResult> {
  return act(z.uuid(), id, async (db, v, t) => {
    const { error } = await db.rpc("webhook_test", { p_id: v });
    if (error) return dbFail(error, t);
    refresh("webhooks");
    return { ok: true, message: t("communication.webhooks.testQueued") };
  });
}
