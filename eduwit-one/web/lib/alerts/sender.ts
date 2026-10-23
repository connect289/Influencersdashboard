import type { OneDb } from "../db.ts";
import type { EmailClient } from "../clients/email.ts";
import { HttpError } from "../http.ts";
import { compose, deliverySchema } from "./compose.ts";

// The alert sender (spec §9), run by every tick after the probes: claim what is due, send each, record each verdict.
// The database decides what is due, escalates and suppresses; the app only delivers (single writer, standard 10).

export type SendSummary = {
  mode: "real" | "mock" | "not_configured";
  claimed: number;
  sent: number;
  failed: number;
  errors: string[];
};

export async function sendPending(deps: {
  db: Pick<OneDb, "claimDeliveries" | "finishDelivery">;
  email: { mode: SendSummary["mode"]; client: EmailClient | null };
  from: string;
  oneHost: string;
  limit?: number;
}): Promise<SendSummary> {
  const summary: SendSummary = { mode: deps.email.mode, claimed: 0, sent: 0, failed: 0, errors: [] };
  const client = deps.email.client;
  if (!client) return summary;
  const claimed = await deps.db.claimDeliveries(deps.limit ?? 20);
  summary.claimed = claimed.length;
  for (const raw of claimed) {
    const parsed = deliverySchema.safeParse(raw);
    const id = typeof (raw as { id?: unknown }).id === "number" ? (raw as { id: number }).id : null;
    if (!parsed.success) {
      if (id !== null) await deps.db.finishDelivery(id, false, "unreadable delivery", null);
      summary.failed++;
      continue;
    }
    const d = parsed.data;
    try {
      const m = compose(d, deps.oneHost);
      const { id: providerId } = await client.send({
        from: deps.from,
        to: d.recipient,
        ...m,
        idempotencyKey: d.idempotency_key,
      });
      await deps.db.finishDelivery(d.id, true, null, providerId);
      summary.sent++;
    } catch (e) {
      const error = e instanceof HttpError ? `email ${e.message}` : "email error";
      await deps.db.finishDelivery(d.id, false, error, null);
      summary.failed++;
      if (summary.errors.length < 5) summary.errors.push(error);
    }
  }
  return summary;
}
