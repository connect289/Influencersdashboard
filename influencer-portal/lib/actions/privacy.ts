"use server";
// DPDP requests (spec 16): the creator asks for an export or deletion; staff with privacy.manage decide deletions.
// Each action validates its input and calls one inf.* function; an approved deletion also bans the sign-in account.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { log } from "@/lib/log";
import { removeFiles, storageFiles } from "@/lib/jobs/storage-remove";
import { adminClient } from "@/lib/supabase/admin";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
type DbError = { code?: string; message: string };

const PRIVACY_DB_ERRORS: readonly (readonly [RegExp, string])[] = [
  [/one export a day/, "exportDaily"],
  [/a deletion request is already open/, "deletionOpen"],
  [/open deals/, "openDeals"],
  [/money is still owed/, "balance"],
  [/already decided/, "decided"],
  [/say why/, "reason"],
];

async function signedIn(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

function dbFail(error: DbError, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of PRIVACY_DB_ERRORS)
    if (re.test(error.message)) return fail(t(`privacy.errors.${key}` as "privacy.errors.exportDaily"));
  if (error.code === "22023") return fail(t("errors.invalidInput"));
  log.warn("privacy.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

const requestInput = z.object({
  kind: z.enum(["export", "deletion"]),
  reason: z.string().trim().max(1000).default(""),
});

export async function createPrivacyRequest(input: z.input<typeof requestInput>): Promise<ActionResult> {
  const t = await getTranslations();
  const p = requestInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const db = await signedIn();
  if (!db) return fail(t("errors.sessionEnded"));
  const { error } = await db.rpc("privacy_request_create", {
    p_kind: p.data.kind,
    p_reason: p.data.reason || undefined,
  });
  if (error) return dbFail(error, t);
  revalidatePath("/creator/account/privacy");
  return { ok: true, message: t(`privacy.requested.${p.data.kind}`) };
}

const decideInput = z.object({
  requestId: z.uuid(),
  approve: z.boolean(),
  note: z.string().trim().min(3).max(1000),
});

export async function decideDeletion(input: z.input<typeof decideInput>): Promise<ActionResult> {
  const t = await getTranslations();
  const p = decideInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const db = await signedIn();
  if (!db) return fail(t("errors.sessionEnded"));
  const { data, error } = await db.rpc("privacy_deletion_decide", {
    p_request: p.data.requestId,
    p_approve: p.data.approve,
    p_note: p.data.note,
  });
  if (error) return dbFail(error, t);
  const done = z.object({ user_id: z.uuid().nullable(), files: storageFiles }).parse(data);
  if (p.data.approve) {
    // The sign-in account can no longer be used (records that reference it are kept), and the photo (and KYC proofs
    // nothing needs any more) leave storage.
    if (done.user_id) {
      const banned = await adminClient().auth.admin.updateUserById(done.user_id, { ban_duration: "876000h" });
      if (banned.error) log.error("privacy.ban_failed", { error: banned.error.message });
    }
    await removeFiles(done.files).catch((e: unknown) =>
      log.error("privacy.files_failed", { error: e instanceof Error ? e.message : String(e) }),
    );
  }
  revalidatePath("/admin/privacy");
  return { ok: true, message: t(p.data.approve ? "privacy.staff.done" : "privacy.staff.rejected") };
}
