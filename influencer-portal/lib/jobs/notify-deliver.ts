import "server-only";
import { z } from "zod";
import { env } from "@/lib/env";
import { log, errorMessage } from "@/lib/log";
import { emailProvider } from "@/lib/notify/email";
import { escapeHtml } from "@/lib/notify/templates";
import { ProviderError } from "@/lib/notify/types";
import { adminClient } from "@/lib/supabase/admin";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ notification_id: z.uuid() });

/**
 * Delivers the queued email/WhatsApp copies of one in-app notification. Idempotent: only rows still 'queued' are sent.
 * Nothing leaves the system unless LIVE_MODE=on (rows are marked skipped with the reason). WhatsApp templates arrive
 * with the notification phase; until then WhatsApp rows are skipped as "no template".
 */
export const notifyDeliver: JobHandler = async (job) => {
  const { notification_id } = payloadSchema.parse(job.payload);
  const db = adminClient();
  const { data: n, error } = await db
    .from("notifications")
    .select("id, user_id, title, body, link")
    .eq("id", notification_id)
    .maybeSingle();
  if (error) throw new Error(error.message);
  if (!n) return;
  const { data: rows } = await db
    .from("notification_deliveries")
    .select("id, channel")
    .eq("notification_id", notification_id)
    .eq("status", "queued");
  let retryable: Error | null = null;
  for (const d of (rows ?? []) as { id: number; channel: "email" | "whatsapp" }[]) {
    if (env().LIVE_MODE !== "on") {
      await db.rpc("delivery_result", {
        p_id: d.id,
        p_status: "skipped",
        p_provider: undefined,
        p_ref: undefined,
        p_error: "live_mode_off",
      });
      continue;
    }
    if (d.channel === "whatsapp") {
      await db.rpc("delivery_result", {
        p_id: d.id,
        p_status: "skipped",
        p_provider: undefined,
        p_ref: undefined,
        p_error: "no_template",
      });
      continue;
    }
    const user = await db.auth.admin.getUserById(n.user_id);
    const to = user.data.user?.email;
    if (!to) {
      await db.rpc("delivery_result", {
        p_id: d.id,
        p_status: "failed",
        p_provider: undefined,
        p_ref: undefined,
        p_error: "no_email",
      });
      continue;
    }
    const link = n.link ? `${env().NEXT_PUBLIC_SITE_URL}${n.link}` : null;
    try {
      const sent = await emailProvider().send({
        to,
        subject: n.title,
        text: [n.body ?? "", link ?? ""].filter(Boolean).join("\n\n"),
        html: `<p>${escapeHtml(n.body ?? n.title)}</p>${link ? `<p><a href="${escapeHtml(link)}">${escapeHtml(link)}</a></p>` : ""}`,
        idempotencyKey: `delivery:${d.id}`,
      });
      await db.rpc("delivery_result", {
        p_id: d.id,
        p_status: "sent",
        p_provider: sent.provider,
        p_ref: sent.id ?? undefined,
        p_error: undefined,
      });
    } catch (e) {
      const permanent = e instanceof ProviderError && !e.retryable;
      await db.rpc("delivery_result", {
        p_id: d.id,
        p_status: permanent ? "failed" : "queued",
        p_provider: emailProvider().name,
        p_ref: undefined,
        p_error: errorMessage(e),
      });
      log.warn("notify.email_failed", { delivery: d.id, permanent });
      if (!permanent) retryable = e instanceof Error ? e : new Error(String(e));
    }
  }
  if (retryable) throw retryable;
};
