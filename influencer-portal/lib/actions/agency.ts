"use server";
// Agencies: staff administration (agency.manage), agency owners managing their team and link requests, and creators
// accepting, re-scoping or ending a link. Authorisation is enforced by the inf.agency_* functions.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import {
  agencyInput,
  grantsInput,
  memberInput,
  type AgencyInput,
  type GrantsInput,
  type MemberInput,
} from "@/lib/agencies/schemas";
import { normalisePhone } from "@/lib/creators/schemas";
import { env } from "@/lib/env";
import { errorMessage, log } from "@/lib/log";
import { emailProvider } from "@/lib/notify/email";
import { agencyInviteEmail } from "@/lib/notify/templates";
import { adminClient } from "@/lib/supabase/admin";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
const uuid = z.uuid();
const reason = z.string().trim().min(3).max(300);

async function session(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

function dbFail(error: { code?: string; message: string }, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  if (error.code === "23505") return fail(t("agencies.errors.duplicate"));
  if (/staff or creator account/i.test(error.message)) return fail(t("agencies.errors.otherAccount"));
  if (/at least one owner/i.test(error.message)) return fail(t("agencies.errors.lastOwner"));
  if (/has ended|no live link/i.test(error.message)) return fail(t("agencies.errors.linkEnded"));
  if (error.code === "22023" || error.code === "23514") return fail(t("errors.invalidInput"));
  log.warn("agency.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

function refreshAll() {
  revalidatePath("/admin/agencies", "layout");
  revalidatePath("/agency", "layout");
  revalidatePath("/creator/agency");
}

export async function saveAgency(input: AgencyInput): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const p = agencyInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = p.data;
  const { data, error } = await supabase.rpc("agency_save", {
    p: {
      id: v.id ?? "",
      name: v.name,
      legal_name: v.legalName,
      email: v.email,
      phone_e164: v.phone ? (normalisePhone(v.phone) ?? "") : "",
      gstin: v.gstin,
      notes: v.notes,
    },
  });
  if (error) return dbFail(error, t);
  refreshAll();
  return { ok: true, data: { id: data }, message: t("agencies.saved") };
}

export async function setAgencyStatus(
  agencyId: string,
  status: "active" | "suspended",
  why: string,
): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(agencyId).success || !reason.safeParse(why).success) return fail(t("agencies.errors.reason"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("agency_set_status", {
    p_agency: agencyId,
    p_status: status,
    p_reason: why.trim(),
  });
  if (error) return dbFail(error, t);
  refreshAll();
  return {
    ok: true,
    message: status === "active" ? t("agencies.reactivated") : t("agencies.suspended"),
  };
}

/**
 * Add a member and email them a sign-in invitation. The database checks the caller first (staff with agency.manage or
 * the agency's owner); only then is an auth account created for the email, so nobody else can create accounts.
 */
export async function addAgencyMember(input: MemberInput): Promise<ActionResult> {
  const t = await getTranslations();
  const p = memberInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = p.data;
  const { error } = await supabase.rpc("agency_member_add", {
    p_agency: v.agencyId,
    p_email: v.email,
    p_full_name: v.fullName,
    p_role: v.role,
  });
  if (error) return dbFail(error, t);
  const admin = adminClient();
  const existing = (await admin.rpc("auth_user_id_by_email", { p_email: v.email })).data;
  if (!existing) {
    const created = await admin.auth.admin.createUser({
      email: v.email,
      email_confirm: true,
      user_metadata: { full_name: v.fullName },
    });
    if (created.error) log.error("agency_member.create_user_failed", { error: created.error.message });
  }
  const { data: agency } = await supabase.from("agencies").select("name").eq("id", v.agencyId).maybeSingle();
  refreshAll();
  try {
    await emailProvider().send({
      ...agencyInviteEmail(`${env().NEXT_PUBLIC_SITE_URL}/login`, v.fullName, agency?.name ?? "your agency"),
      to: v.email,
    });
  } catch (e) {
    log.error("agency_member.mail_failed", { error: errorMessage(e) });
    return { ok: true, message: t("agencies.members.addedNoMail") };
  }
  return { ok: true, message: t("agencies.members.added", { email: v.email }) };
}

export async function removeAgencyMember(memberId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(memberId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("agency_member_remove", { p_member: memberId });
  if (error) return dbFail(error, t);
  refreshAll();
  return { ok: true, message: t("agencies.members.removed") };
}

/** Request a link to a creator by handle (staff with agency.manage, or the agency's owner). */
export async function requestAgencyLink(agencyId: string, handle: string): Promise<ActionResult> {
  const t = await getTranslations();
  const h = handle.trim().replace(/^@/, "").toLowerCase();
  if (!uuid.safeParse(agencyId).success || !/^[a-z0-9._]{2,40}$/.test(h)) return fail(t("agencies.errors.handle"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("agency_link_request_by_handle", {
    p_agency: agencyId,
    p_handle: h,
  });
  if (error && /no such creator/i.test(error.message)) return fail(t("agencies.errors.noCreator"));
  if (error) return dbFail(error, t);
  refreshAll();
  return { ok: true, message: t("agencies.links.requested") };
}

export async function revokeAgencyLink(linkId: string, why: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(linkId).success || !reason.safeParse(why).success) return fail(t("agencies.errors.reason"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("agency_link_revoke", {
    p_link: linkId,
    p_reason: why.trim(),
  });
  if (error) return dbFail(error, t);
  refreshAll();
  return { ok: true, message: t("agencies.links.revoked") };
}

/** Creator: accept (or update) a link with the chosen grants, or decline / end it. */
export async function respondAgencyLink(linkId: string, accept: boolean, grants: GrantsInput): Promise<ActionResult> {
  const t = await getTranslations();
  const g = grantsInput.safeParse(grants);
  if (!uuid.safeParse(linkId).success || !g.success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("agency_link_respond", {
    p_link: linkId,
    p_accept: accept,
    p_view: true,
    p_deliverables: g.data.deliverables,
    p_negotiate: g.data.negotiate,
    p_earnings: g.data.earnings,
  });
  if (error) return dbFail(error, t);
  refreshAll();
  return { ok: true, message: accept ? t("agencies.links.saved") : t("agencies.links.ended") };
}
