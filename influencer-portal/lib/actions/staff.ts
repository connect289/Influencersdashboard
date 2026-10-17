"use server";
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { assertStaff, ForbiddenError } from "@/lib/auth/guards";
import { STAFF_ROLES } from "@/lib/auth/permissions";
import { env } from "@/lib/env";
import { errorMessage, log } from "@/lib/log";
import { emailProvider } from "@/lib/notify/email";
import { passwordLinkEmail } from "@/lib/notify/templates";
import { adminClient } from "@/lib/supabase/admin";
import { fail, type ActionResult } from "./result";

const staffInput = z
  .object({
    email: z
      .email()
      .max(254)
      .transform((v) => v.trim().toLowerCase()),
    fullName: z.string().trim().min(1).max(120),
    roles: z.array(z.enum(STAFF_ROLES)).min(1),
    isSignatory: z.boolean(),
    designation: z.string().trim().max(120).optional().default(""),
  })
  .refine((v) => !v.isSignatory || v.designation.length >= 2, {
    path: ["designation"],
    message: "designation required",
  });
export type StaffInput = z.input<typeof staffInput>;

function dbError(e: { message: string } | null, t: (k: string) => string): string {
  if (!e) return t("errors.generic");
  if (/only Super Admin/i.test(e.message)) return t("staff.errors.lastAdmin");
  if (/creator account/i.test(e.message)) return t("staff.errors.isCreator");
  if (/not allowed/i.test(e.message)) return t("errors.forbidden");
  return t("errors.generic");
}

/** Invite (or update) a staff member. Creates the auth account if the email has none, then emails a password link. */
export async function saveStaff(input: StaffInput, invite: boolean): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = staffInput.safeParse(input);
  if (!parsed.success)
    return fail(
      parsed.error.issues.some((i) => i.path[0] === "designation")
        ? t("staff.errors.designation")
        : t("errors.invalidInput"),
    );
  const v = parsed.data;
  try {
    const { supabase } = await assertStaff("staff.manage");
    const admin = adminClient();
    let userId: string | null = (await admin.rpc("auth_user_id_by_email", { p_email: v.email }))
      .data;
    if (!userId) {
      const created = await admin.auth.admin.createUser({
        email: v.email,
        email_confirm: true,
        user_metadata: { full_name: v.fullName },
      });
      if (created.error) return fail(t("staff.errors.createFailed"));
      userId = created.data.user.id;
    }
    const { error } = await supabase.rpc("staff_save", {
      p_user: userId,
      p_full_name: v.fullName,
      p_email: v.email,
      p_roles: v.roles,
      p_is_signatory: v.isSignatory,
      p_designation: v.designation || undefined,
    });
    if (error) return fail(dbError(error, t));
    if (invite) {
      const link = await admin.auth.admin.generateLink({ type: "recovery", email: v.email });
      if (!link.error && link.data.properties.hashed_token) {
        const url = `${env().NEXT_PUBLIC_SITE_URL}/auth/confirm?token_hash=${encodeURIComponent(link.data.properties.hashed_token)}&type=recovery&next=/password/new`;
        try {
          await emailProvider().send({ ...passwordLinkEmail(url, v.fullName), to: v.email });
        } catch (e) {
          log.error("staff_invite.mail_failed", { error: errorMessage(e) });
          revalidatePath("/admin/staff");
          return { ok: true, message: t("staff.invitedNoMail") };
        }
      }
    }
    revalidatePath("/admin/staff");
    return {
      ok: true,
      message: invite ? t("staff.invited", { email: v.email }) : t("staff.saved"),
    };
  } catch (e) {
    return fail(e instanceof ForbiddenError ? e.message : t("errors.generic"));
  }
}

const statusInput = z.object({
  userId: z.uuid(),
  status: z.enum(["active", "suspended"]),
  reason: z.string().trim().min(3).max(300),
});

export async function setStaffStatus(
  userId: string,
  status: "active" | "suspended",
  reason: string,
): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = statusInput.safeParse({ userId, status, reason });
  if (!parsed.success) return fail(t("staff.errors.reason"));
  try {
    const { supabase } = await assertStaff("staff.manage");
    const { error } = await supabase.rpc("staff_set_status", {
      p_user: parsed.data.userId,
      p_status: parsed.data.status,
      p_reason: parsed.data.reason,
    });
    if (error)
      return fail(/yourself/i.test(error.message) ? t("staff.errors.self") : dbError(error, t));
  } catch (e) {
    return fail(e instanceof ForbiddenError ? e.message : t("errors.generic"));
  }
  revalidatePath("/admin/staff");
  return {
    ok: true,
    message: status === "suspended" ? t("staff.suspended") : t("staff.reactivated"),
  };
}

export async function signOutStaffEverywhere(
  userId: string,
  reason: string,
): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = z
    .object({ userId: z.uuid(), reason: z.string().trim().min(3).max(300) })
    .safeParse({ userId, reason });
  if (!parsed.success) return fail(t("staff.errors.reason"));
  try {
    const { supabase } = await assertStaff("staff.manage");
    const { data, error } = await supabase.rpc("staff_revoke_all_sessions", {
      p_user: parsed.data.userId,
      p_reason: parsed.data.reason,
    });
    if (error) return fail(dbError(error, t));
    revalidatePath("/admin/staff");
    return { ok: true, message: t("staff.signedOut", { count: data }) };
  } catch (e) {
    return fail(e instanceof ForbiddenError ? e.message : t("errors.generic"));
  }
}
