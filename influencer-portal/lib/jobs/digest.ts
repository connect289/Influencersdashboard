import "server-only";
import { z } from "zod";
import { log } from "@/lib/log";
import { creatorDigest, staffDigest } from "@/lib/notify/digest";
import { adminClient } from "@/lib/supabase/admin";
import { enqueueMany } from "./fan-out";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ date: z.iso.date() });
const recipients = z.array(
  z.object({
    user_id: z.uuid(),
    kind: z.enum(["creator", "staff"]),
    frequency: z.enum(["daily", "weekly"]),
    channel: z.enum(["email", "whatsapp"]),
    creator_id: z.uuid().nullable(),
  }),
);
const n = z.coerce.number().catch(0);
const creatorFacts = z.object({
  name: z.string().catch("there"),
  new_leads: n,
  enrolled: n,
  earned_paise: n,
  payable_paise: n,
  due_soon: n,
  overdue: n,
  unread_messages: n,
});
const staffFacts = z.object({
  overdue_deliverables: n,
  pending_reviews: n,
  pending_negotiations: n,
  contracts_expiring: n,
  payouts_due_paise: n,
  kyc_pending: n,
  fraud_flags: n,
  unread_messages: n,
});

const personPayload = z.object({
  date: z.iso.date(),
  user_id: z.uuid(),
  kind: z.enum(["creator", "staff"]),
  frequency: z.enum(["daily", "weekly"]),
  channel: z.enum(["email", "whatsapp"]),
  creator_id: z.uuid().nullable(),
});

/**
 * Daily at 08:00 IST (pg_cron enqueues it): everyone whose digest is due today gets a digest.person job, so each
 * person's digest is a short job of its own (one slow or failing person no longer holds up or restarts the rest).
 */
export const digestRun: JobHandler = async (job) => {
  const { date } = payloadSchema.parse(job.payload);
  const db = adminClient();
  const { data, error } = await db.rpc("digest_recipients", { p_today: date });
  if (error) throw new Error(error.message);
  const queued = await enqueueMany(
    db,
    recipients.parse(data).map((r) => ({
      kind: "digest.person",
      payload: { date, ...r },
      idemKey: `digest_person:${date}:${r.user_id}`,
    })),
  );
  log.info("digest.queued", { date, queued });
};

/**
 * One person's digest: one in-app notification plus their chosen channel, built from their facts; quiet periods send
 * nothing. One digest per person per day (inf.digest_send is idempotent).
 */
export const digestPerson: JobHandler = async (job) => {
  const r = personPayload.parse(job.payload);
  const db = adminClient();
  const facts = await db.rpc("digest_facts", {
    p_user: r.user_id,
    p_kind: r.kind,
    p_creator: r.creator_id ?? undefined,
    p_days: r.frequency === "daily" ? 1 : 7,
  });
  if (facts.error) throw new Error(facts.error.message);
  const digest =
    r.kind === "creator"
      ? creatorDigest(creatorFacts.parse(facts.data ?? {}), r.frequency)
      : staffDigest(staffFacts.parse(facts.data ?? {}));
  if (!digest) return;
  const res = await db.rpc("digest_send", {
    p_user: r.user_id,
    p_kind: r.kind,
    p_title: digest.title,
    p_body: digest.lines.join("\n"),
    p_channel: r.channel,
    p_date: r.date,
  });
  if (res.error) throw new Error(res.error.message);
};
