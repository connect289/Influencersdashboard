import "server-only";
import { z } from "zod";
import { env } from "@/lib/env";
import { log, errorMessage } from "@/lib/log";
import { composeEmail, composeWhatsApp, type Template } from "@/lib/notify/compose";
import { emailProvider } from "@/lib/notify/email";
import { inQuietHours, sendAfterQuiet } from "@/lib/notify/quiet";
import { ProviderError } from "@/lib/notify/types";
import { whatsAppProvider } from "@/lib/notify/whatsapp";
import { SETTINGS } from "@/lib/settings/registry";
import { adminClient } from "@/lib/supabase/admin";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ notification_id: z.uuid() });
const template = z.object({
  subject: z.string().nullable(),
  body: z.string(),
  wa_template_name: z.string().nullable(),
});

type Db = ReturnType<typeof adminClient>;
interface Outcome {
  status: "sent" | "skipped" | "failed";
  provider?: string;
  ref?: string;
  error?: string;
}

/** The recipient's name and WhatsApp number (creators only have one on file). */
async function recipient(db: Db, userId: string): Promise<{ name: string; phone: string | null }> {
  const [staff, creator, member] = await Promise.all([
    db.from("staff_profiles").select("full_name").eq("user_id", userId).maybeSingle(),
    db.from("creator_accounts").select("creators(display_name, phone_e164)").eq("user_id", userId).maybeSingle(),
    db.from("agency_members").select("full_name").eq("user_id", userId).limit(1).maybeSingle(),
  ]);
  const c = creator.data?.creators;
  const name = staff.data?.full_name ?? c?.display_name ?? member.data?.full_name ?? "there";
  return { name: name.split(" ")[0] ?? name, phone: c?.phone_e164 ?? null };
}

async function templateFor(db: Db, event: string, channel: "email" | "whatsapp"): Promise<Template | null> {
  const { data } = await db.rpc("notification_template_for", { p_event: event, p_channel: channel });
  const p = template.safeParse(data);
  return p.success ? p.data : null;
}

/**
 * Delivers the queued email/WhatsApp copies of one in-app notification, using the staff-edited template for the event
 * when there is one. Idempotent: only rows still 'queued' are sent. Nothing leaves the system unless LIVE_MODE=on
 * (rows are marked skipped with the reason). WhatsApp needs an approved provider template for the event and the
 * creator's number; otherwise that copy is skipped with the reason. During quiet hours (setting notifications.delivery)
 * the WhatsApp copy waits and the job runs again when they end.
 */
export const notifyDeliver: JobHandler = async (job) => {
  const { notification_id } = payloadSchema.parse(job.payload);
  const db = adminClient();
  const { data: n, error } = await db
    .from("notifications")
    .select("id, user_id, event, title, body, link, data")
    .eq("id", notification_id)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!n) return;
  const { data: rows } = await db
    .from("notification_deliveries")
    .select("id, channel")
    .eq("notification_id", notification_id)
    .eq("status", "queued");
  const queued = (rows ?? []) as { id: number; channel: "email" | "whatsapp" }[];
  if (queued.length === 0) return;

  // Every outcome is written back; a write that fails fails the job, so a sent copy is never left looking queued
  // (the retry re-sends with the same idempotency key, which the provider answers without sending twice).
  const result = async (
    id: number,
    status: "sent" | "skipped" | "failed" | "queued",
    extra: { provider?: string; ref?: string; error?: string } = {},
  ): Promise<void> => {
    const { error: e } = await db.rpc("delivery_result", {
      p_id: id,
      p_status: status,
      p_provider: extra.provider,
      p_ref: extra.ref,
      p_error: extra.error,
    });
    if (e) throw new Error(`could not record delivery ${id.toString()} as ${status}: ${e.message}`);
  };

  if (env().LIVE_MODE !== "on") {
    for (const d of queued) await result(d.id, "skipped", { error: "live_mode_off" });
    return;
  }

  const facts = {
    event: n.event,
    title: n.title,
    body: n.body,
    link: n.link,
    data: z.record(z.string(), z.unknown()).catch({}).parse(n.data),
  };
  const site = env().NEXT_PUBLIC_SITE_URL;
  const who = await recipient(db, n.user_id);
  const delivery = SETTINGS["notifications.delivery"].schema
    .catch(SETTINGS["notifications.delivery"].default)
    .parse((await db.rpc("setting", { p_key: "notifications.delivery" })).data);
  const now = new Date();
  const quiet = inQuietHours(now, delivery.quiet_hours_start, delivery.quiet_hours_end);

  /** Sends one copy. Null: nothing to record now (the WhatsApp copy waits for the end of quiet hours). */
  const deliverOne = async (d: (typeof queued)[number]): Promise<Outcome | null> => {
    if (d.channel === "whatsapp") {
      if (quiet) {
        // Quiet hours: the WhatsApp copy stays queued and this job runs again when they end.
        const at = sendAfterQuiet(now, delivery.quiet_hours_start, delivery.quiet_hours_end);
        const { error: e } = await db.rpc("job_enqueue", {
          p_kind: "notify.deliver",
          p_payload: { notification_id },
          p_run_at: at.toISOString(),
          p_idem_key: `notify:${notification_id}:after-quiet:${at.toISOString()}`,
        });
        if (e) throw new Error(`could not schedule the after-quiet delivery: ${e.message}`);
        return null;
      }
      const msg = composeWhatsApp(facts, await templateFor(db, n.event, "whatsapp"), who.name, who.phone, site);
      if (!msg) return { status: "skipped", error: who.phone ? "no_template" : "no_number" };
      const sent = await whatsAppProvider().sendTemplate(msg);
      return { status: "sent", provider: sent.provider, ref: sent.id ?? undefined };
    }
    const user = await db.auth.admin.getUserById(n.user_id);
    const to = user.data.user?.email;
    if (!to) return { status: "failed", error: "no_email" };
    const mail = composeEmail(facts, await templateFor(db, n.event, "email"), who.name, site);
    const sent = await emailProvider().send({ ...mail, to, idempotencyKey: `delivery:${d.id.toString()}` });
    return { status: "sent", provider: sent.provider, ref: sent.id ?? undefined };
  };

  let retryable: Error | null = null;
  for (const d of queued) {
    let outcome: Outcome | null;
    try {
      outcome = await deliverOne(d);
    } catch (e) {
      const permanent = e instanceof ProviderError && !e.retryable;
      await result(d.id, permanent ? "failed" : "queued", {
        provider: d.channel === "email" ? emailProvider().name : whatsAppProvider().name,
        error: errorMessage(e),
      });
      log.warn("notify.delivery_failed", { delivery: d.id, channel: d.channel, permanent });
      if (!permanent) retryable = e instanceof Error ? e : new Error(String(e));
      continue;
    }
    if (outcome) await result(d.id, outcome.status, outcome);
  }
  if (retryable) throw retryable;
};
