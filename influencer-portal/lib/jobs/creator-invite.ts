import "server-only";
import { z } from "zod";
import { env } from "@/lib/env";
import { emailProvider } from "@/lib/notify/email";
import { creatorInviteEmail } from "@/lib/notify/templates";
import { adminClient } from "@/lib/supabase/admin";
import type { JobHandler } from "./types";

const payloadSchema = z.object({ creator_id: z.uuid(), date: z.iso.date() });

/**
 * One invitation (queued by the Invite action, one job per creator per day): gives the creator an auth account, so
 * the email code works, and sends the invitation email. Skipped when the creator was blocked, lost their email or
 * signed up since. A failure is retried with backoff; the email keeps one idempotency key per creator and day.
 */
export const creatorInvite: JobHandler = async (job) => {
  const { creator_id, date } = payloadSchema.parse(job.payload);
  const db = adminClient();
  const [creator, account] = await Promise.all([
    db.from("creators").select("email, display_name, is_blocked").eq("id", creator_id).maybeSingle(),
    db.from("creator_accounts").select("creator_id").eq("creator_id", creator_id).maybeSingle(),
  ]);
  if (creator.error) throw new Error(creator.error.message);
  if (account.error) throw new Error(account.error.message);
  const c = creator.data;
  if (!c?.email || c.is_blocked || account.data) return;
  const email = c.email.toLowerCase();
  const existing = await db.rpc("auth_user_id_by_email", { p_email: email });
  if (existing.error) throw new Error(existing.error.message);
  if (!existing.data) {
    const created = await db.auth.admin.createUser({
      email,
      email_confirm: true,
      user_metadata: { full_name: c.display_name },
    });
    if (created.error) throw new Error(`could not create the sign-in account: ${created.error.message}`);
  }
  await emailProvider().send({
    ...creatorInviteEmail(`${env().NEXT_PUBLIC_SITE_URL}/login`, c.display_name),
    to: email,
    idempotencyKey: `creator_invite:${creator_id}:${date}`,
  });
};
