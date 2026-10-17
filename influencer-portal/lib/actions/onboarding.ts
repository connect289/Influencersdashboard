"use server";
// Invitations (staff), the compliance quiz and onboarding submission (creator), and the staff review decision.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { env } from "@/lib/env";
import { errorMessage, log } from "@/lib/log";
import { emailProvider } from "@/lib/notify/email";
import { creatorInviteEmail } from "@/lib/notify/templates";
import { adminClient } from "@/lib/supabase/admin";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

async function session(kind: "staff" | "creator"): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (me.kind !== kind || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

/**
 * Invite creators to the portal. The database marks them invited and returns who qualified (email present, no account
 * yet, not blocked); then each gets an auth account (so the email code works) and the invitation email.
 */
export async function inviteCreators(ids: string[]): Promise<ActionResult<{ invited: number }>> {
  const t = await getTranslations();
  const list = z.array(z.uuid()).min(1).max(500).safeParse(ids);
  if (!list.success) return fail(t("errors.invalidInput"));
  const supabase = await session("staff");
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { data, error } = await supabase.rpc("creators_invite", { p_ids: list.data });
  if (error) return fail(error.code === "42501" ? t("errors.forbidden") : t("errors.generic"));
  const admin = adminClient();
  let mailFailures = 0;
  for (const c of data) {
    const existing = (await admin.rpc("auth_user_id_by_email", { p_email: c.email })).data;
    if (!existing) {
      const created = await admin.auth.admin.createUser({
        email: c.email,
        email_confirm: true,
        user_metadata: { full_name: c.display_name },
      });
      if (created.error) {
        log.error("invite.create_user_failed", { error: created.error.message });
        mailFailures++;
        continue;
      }
    }
    try {
      await emailProvider().send({
        ...creatorInviteEmail(`${env().NEXT_PUBLIC_SITE_URL}/login`, c.display_name),
        to: c.email,
      });
    } catch (e) {
      log.error("invite.mail_failed", { error: errorMessage(e) });
      mailFailures++;
    }
  }
  revalidatePath("/admin/creators", "layout");
  const skipped = list.data.length - data.length;
  return {
    ok: true,
    data: { invited: data.length },
    message:
      data.length === 0
        ? t("onboarding.invite.none")
        : t("onboarding.invite.sent", { count: data.length, skipped, failed: mailFailures }),
  };
}

const courseResult = z.object({
  ok: z.boolean(),
  error: z.string().optional(),
  score_pct: z.number().optional(),
  passed: z.boolean().optional(),
  pass_pct: z.number().optional(),
  wrong: z.array(z.object({ id: z.uuid(), explanation: z.string().nullable() })).optional(),
});
export type CourseResult = z.infer<typeof courseResult>;

export async function submitCourse(
  answers: Record<string, number>,
): Promise<ActionResult<CourseResult>> {
  const t = await getTranslations();
  const parsed = z.record(z.uuid(), z.number().int().min(0).max(5)).safeParse(answers);
  if (!parsed.success) return fail(t("errors.invalidInput"));
  const supabase = await session("creator");
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { data, error } = await supabase.rpc("course_submit", { p_answers: parsed.data });
  if (error) return fail(t("errors.generic"));
  const r = courseResult.parse(data);
  if (!r.ok)
    return fail(
      r.error === "too_many_attempts" ? t("onboarding.course.tooMany") : t("errors.generic"),
    );
  revalidatePath("/creator/onboarding");
  return { ok: true, data: r };
}

export async function submitOnboarding(): Promise<ActionResult<{ approved: boolean }>> {
  const t = await getTranslations();
  const supabase = await session("creator");
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { data, error } = await supabase.rpc("onboarding_submit");
  if (error) return fail(t("errors.generic"));
  const r = z
    .object({ ok: z.boolean(), approved: z.boolean().optional(), error: z.string().optional() })
    .parse(data);
  if (!r.ok) return fail(t("onboarding.errors.incomplete"));
  revalidatePath("/creator", "layout");
  return {
    ok: true,
    data: { approved: r.approved === true },
    message: r.approved ? t("onboarding.submit.approved") : t("onboarding.submit.sent"),
  };
}

const reviewInput = z
  .object({
    creatorId: z.uuid(),
    decision: z.enum(["approve", "changes", "decline"]),
    reason: z.string().trim().max(500),
  })
  .refine((v) => v.decision === "approve" || v.reason.length >= 3);

export async function reviewCreator(input: z.input<typeof reviewInput>): Promise<ActionResult> {
  const t = await getTranslations();
  const p = reviewInput.safeParse(input);
  if (!p.success) return fail(t("creators.errors.reason"));
  const supabase = await session("staff");
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("creator_review", {
    p_creator: p.data.creatorId,
    p_decision: p.data.decision,
    p_reason: p.data.reason,
  });
  if (error) {
    if (error.code === "42501") return fail(t("errors.forbidden"));
    if (/already approved/i.test(error.message))
      return fail(t("onboarding.errors.alreadyApproved"));
    if (/not signed up/i.test(error.message)) return fail(t("creators.errors.notSignedUp"));
    return fail(t("errors.generic"));
  }
  revalidatePath("/admin/creators", "layout");
  return { ok: true, message: t(`onboarding.review.done.${p.data.decision}`) };
}
