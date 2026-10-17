"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { rpc } from "@/lib/server/db";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { resendCode, startVerification, verifyCode, type StartOutcome, type VerifyOutcome } from "@/lib/server/gate";
import { errorFields, log } from "@/lib/server/log";
import { clearStudentSession, currentStudent } from "@/lib/server/student-session";

/**
 * Student account actions (spec 12): sign in with an email code, profile for form pre-fill, shortlist sync, saved
 * comparisons, consent withdrawal, data opt-out / deletion requests, sign out. Every action acts only on the student of
 * the signed session.
 */

/** Name/phone/email of the signed-in student, for pre-filling forms. Null when signed out. */
export async function studentProfileAction(): Promise<{ name: string | null; phone: string | null; email: string } | null> {
  const s = await currentStudent().catch(() => null);
  return s ? { name: s.name, phone: s.phone, email: s.email } : null;
}

export async function signInStartAction(input: { email: string; idempotencyKey: string; turnstileToken?: string; website?: string }): Promise<StartOutcome> {
  return startVerification({
    surface: "signin",
    email: String(input.email ?? "").slice(0, 254),
    idempotencyKey: String(input.idempotencyKey ?? "").slice(0, 80),
    turnstileToken: input.turnstileToken ? String(input.turnstileToken).slice(0, 4096) : undefined,
    website: input.website ? String(input.website).slice(0, 200) : undefined,
  });
}

export async function signInResendAction(attemptId: string): Promise<StartOutcome> {
  return resendCode(String(attemptId).slice(0, 40));
}

export async function signInVerifyAction(attemptId: string, code: string): Promise<VerifyOutcome> {
  return verifyCode(String(attemptId).slice(0, 40), String(code).slice(0, 6));
}

export async function signOutAction(): Promise<void> {
  await clearStudentSession();
  redirect("/account/sign-in?signed_out=1");
}

const ids = z.array(z.number().int().positive()).max(200);

/** Merges the device's shortlist into the account and returns the account's full shortlist (null when signed out). */
export async function syncShortlistAction(local: number[]): Promise<number[] | null> {
  const s = await currentStudent();
  if (!s) return null;
  const p = ids.safeParse(local);
  if (!p.success) return null;
  try {
    return await rpc<number[]>("web_shortlist_merge", { p_student: s.studentId, p_ids: p.data });
  } catch (e) {
    log("warn", "account.shortlist_sync_failed", errorFields(e));
    return null;
  }
}

export async function removeShortlistAction(id: number): Promise<boolean> {
  const s = await currentStudent();
  if (!s || !Number.isInteger(id) || id <= 0) return false;
  await rpc("web_shortlist_remove", { p_student: s.studentId, p_id: id });
  return true;
}

export async function saveComparisonAction(offeringIds: number[]): Promise<{ ok: boolean; message?: string }> {
  const s = await currentStudent();
  if (!s) return { ok: false, message: "Sign in to save comparisons." };
  const p = z.array(z.number().int().positive()).min(2).max(4).safeParse(offeringIds);
  if (!p.success) return { ok: false, message: "Pick 2 to 4 programmes to save." };
  if (!(await rateLimit(LIMITS.savePerStudent, `cmp:${s.studentId}`)).ok) return { ok: false, message: "That's a lot of saves. Please try again later." };
  await rpc("web_comparison_save", { p_student: s.studentId, p_ids: p.data });
  return { ok: true };
}

export type AccountActionState = { ok?: string; error?: string } | null;

const PURPOSES = { marketing: ["marketing"], contact: ["sales", "partner_share"], ai_chat: ["ai_chat_storage"] } as const;

export async function withdrawConsentAction(_prev: AccountActionState, form: FormData): Promise<AccountActionState> {
  const s = await currentStudent();
  if (!s) return { error: "Your session has ended. Please sign in again." };
  const which = String(form.get("purpose") ?? "") as keyof typeof PURPOSES;
  if (!(which in PURPOSES)) return { error: "Choose what to withdraw." };
  try {
    await rpc("web_consent_withdraw", { p_student: s.studentId, p_purposes: PURPOSES[which] });
    return {
      ok:
        which === "contact"
          ? "Done. Our counsellors and partners will no longer contact you about your enquiry."
          : which === "marketing"
            ? "Done. You won't receive programme updates."
            : "Done. Your consent for storing chats is withdrawn; ask for deletion below to remove past chats.",
    };
  } catch (e) {
    log("error", "account.withdraw_failed", errorFields(e));
    return { error: "We couldn't record that just now. Please try again." };
  }
}

export async function deletionRequestAction(_prev: AccountActionState, form: FormData): Promise<AccountActionState> {
  const s = await currentStudent();
  if (!s) return { error: "Your session has ended. Please sign in again." };
  const kind = String(form.get("kind") ?? "");
  if (kind !== "delete" && kind !== "opt_out" && kind !== "export") return { error: "Choose a request type." };
  try {
    await rpc("web_deletion_request", { p_student: s.studentId, p_kind: kind });
    return { ok: "Request received. We'll confirm by email and complete it within 30 days, as our Privacy Policy describes." };
  } catch (e) {
    log("error", "account.deletion_failed", errorFields(e));
    return { error: "We couldn't record that just now. Please try again." };
  }
}
