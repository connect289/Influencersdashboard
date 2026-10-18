import "server-only";
import { z } from "zod";
import { env } from "@/lib/env";
import { log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";
import { postWebhook } from "@/lib/webhooks/deliver";
import { assertSafePayload, MAX_ATTEMPTS, nextAttemptAt, outcome } from "@/lib/webhooks/sign";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ delivery_id: z.number().int().positive() });
const delivery = z.object({
  id: z.number(),
  url: z.string(),
  secret: z.string(),
  payload: z.record(z.string(), z.unknown()),
  attempts: z.number(),
  status: z.string(),
  active: z.boolean(),
});

/**
 * Delivers one queued webhook (spec 18): signed POST, result recorded, retried with backoff (1 min … 1 day, 7 tries)
 * on timeouts, 408/425/429 and 5xx. Nothing is sent unless LIVE_MODE=on: the attempt is recorded as not sent.
 */
export const webhookDeliver: JobHandler = async (job) => {
  const { delivery_id } = payloadSchema.parse(job.payload);
  const db = adminClient();
  const got = await db.rpc("webhook_delivery_get", { p_id: delivery_id });
  if (got.error) throw new Error(got.error.message);
  const d = delivery.safeParse(got.data);
  if (!d.success || d.data.status !== "queued") return;
  const record = (
    o: "delivered" | "retry" | "failed",
    status: number | null,
    error: string | null,
    next: Date | null,
  ) =>
    db.rpc("webhook_delivery_result", {
      p_id: d.data.id,
      p_outcome: o,
      p_status: status ?? undefined,
      p_error: error ?? undefined,
      p_next_at: next?.toISOString() ?? undefined,
    });

  if (!d.data.active) {
    await record("failed", null, "endpoint paused", null);
    return;
  }
  if (env().LIVE_MODE !== "on") {
    await record("failed", null, "live_mode_off", null);
    return;
  }
  assertSafePayload(d.data.payload);
  const attempt = await postWebhook(d.data.url, d.data.secret, JSON.stringify(d.data.payload));
  const o = attempt.blocked ? "failed" : outcome(attempt.status);
  const attempts = d.data.attempts + 1;
  const next = o === "retry" && attempts < MAX_ATTEMPTS ? nextAttemptAt(attempts, new Date()) : null;
  const res = await record(next || o !== "retry" ? o : "failed", attempt.status, attempt.error, next);
  if (res.error) throw new Error(res.error.message);
  log.info("webhook.attempt", { delivery: d.data.id, status: attempt.status, outcome: o, attempts });
};
