"use server";
// Creator profile and KYC writes. Used by the creator (own profile) and by staff with creator.write (any profile).
// Authorisation lives in the database functions (inf.can_edit_creator, kyc.* permissions); these actions validate
// input, call them and refresh the affected screens.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import {
  contactInput,
  KYC_DB_ERRORS,
  KYC_FORM_ERRORS,
  KYC_PROOF_MAX_BYTES,
  KYC_PROOF_TYPES,
  kycInput,
  normalisePhone,
  platformInput,
  portfolioInput,
  profileInput,
  rateCardInput,
  rupeesToPaise,
  safeFileName,
  type ContactInput,
  type KycInput,
  type PlatformInput,
  type PortfolioInput,
  type ProfileInput,
  type RateCardInput,
} from "@/lib/creators/schemas";
import { errorMessage, log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

const uuid = z.uuid();
type T = Awaited<ReturnType<typeof getTranslations>>;

async function session(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

function refresh(creatorId: string) {
  revalidatePath("/creator", "layout");
  revalidatePath(`/admin/creators/${creatorId}`);
}

function dbFail(error: { code?: string; message: string }, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  if (error.code === "23505") return fail(t("profile.errors.duplicate"));
  if (/at most 30/i.test(error.message)) return fail(t("profile.errors.portfolioFull"));
  if (error.code === "22023" || error.code === "23514" || error.code === "22P02")
    return fail(t("errors.invalidInput"));
  log.warn("creator_profile.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

/** Runs one RPC with a validated creator id. */
async function run(
  creatorId: string,
  call: (s: ServerSupabase) => PromiseLike<{ error: { code?: string; message: string } | null }>,
  message: string,
): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(creatorId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await call(supabase);
  if (error) return dbFail(error, t);
  refresh(creatorId);
  return { ok: true, message: t(message) };
}

export async function saveProfile(creatorId: string, input: ProfileInput): Promise<ActionResult> {
  const t = await getTranslations();
  const p = profileInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const v = p.data;
  return run(
    creatorId,
    (s) =>
      s.rpc("creator_profile_update", {
        p_creator: creatorId,
        p: {
          display_name: v.displayName,
          legal_name: v.legalName,
          bio: v.bio,
          city: v.city,
          state: v.state,
          phone_e164: v.phone ? normalisePhone(v.phone) : "",
          languages: v.languages,
          niches: v.niches,
          public_page_enabled: v.publicPageEnabled,
          leaderboard_opt_in: v.leaderboardOptIn,
        },
      }),
    "profile.saved",
  );
}

export async function savePlatform(creatorId: string, input: PlatformInput): Promise<ActionResult> {
  const t = await getTranslations();
  const p = platformInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const v = p.data;
  return run(
    creatorId,
    (s) =>
      s.rpc("platform_save", {
        p_creator: creatorId,
        p: {
          id: v.id ?? "",
          platform: v.platform,
          url: v.url,
          handle: v.handle,
          followers: v.followers,
          avg_views: v.avgViews,
          engagement_rate: v.engagementRate,
        },
      }),
    "profile.platforms.saved",
  );
}

export async function deletePlatform(creatorId: string, id: string): Promise<ActionResult> {
  if (!uuid.safeParse(id).success) return fail((await getTranslations())("errors.invalidInput"));
  return run(
    creatorId,
    (s) => s.rpc("platform_delete", { p_creator: creatorId, p_id: id }),
    "profile.removed",
  );
}

export async function saveRateCard(creatorId: string, input: RateCardInput): Promise<ActionResult> {
  const t = await getTranslations();
  const p = rateCardInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const v = p.data;
  return run(
    creatorId,
    (s) =>
      s.rpc("rate_card_save", {
        p_creator: creatorId,
        p: {
          platform: v.platform,
          format: v.format,
          suggested_paise: rupeesToPaise(v.rupees),
          notes: v.notes,
        },
      }),
    "profile.rates.saved",
  );
}

export async function deleteRateCard(creatorId: string, id: string): Promise<ActionResult> {
  if (!uuid.safeParse(id).success) return fail((await getTranslations())("errors.invalidInput"));
  return run(
    creatorId,
    (s) => s.rpc("rate_card_delete", { p_creator: creatorId, p_id: id }),
    "profile.removed",
  );
}

export async function addPortfolioItem(
  creatorId: string,
  input: PortfolioInput,
): Promise<ActionResult> {
  const t = await getTranslations();
  const p = portfolioInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  return run(
    creatorId,
    (s) => s.rpc("portfolio_save", { p_creator: creatorId, p: p.data }),
    "profile.portfolio.saved",
  );
}

export async function deletePortfolioItem(creatorId: string, id: string): Promise<ActionResult> {
  if (!uuid.safeParse(id).success) return fail((await getTranslations())("errors.invalidInput"));
  return run(
    creatorId,
    (s) => s.rpc("portfolio_delete", { p_creator: creatorId, p_id: id }),
    "profile.removed",
  );
}

export async function addContact(creatorId: string, input: ContactInput): Promise<ActionResult> {
  const t = await getTranslations();
  const p = contactInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const v = p.data;
  return run(
    creatorId,
    (s) =>
      s.rpc("creator_contact_add", {
        p_creator: creatorId,
        p_kind: v.kind,
        p_label: v.label,
        p_phone: v.phone ? (normalisePhone(v.phone) ?? "") : "",
        p_email: v.email,
      }),
    "profile.contacts.saved",
  );
}

export async function deleteContact(creatorId: string, id: string): Promise<ActionResult> {
  if (!uuid.safeParse(id).success) return fail((await getTranslations())("errors.invalidInput"));
  return run(
    creatorId,
    (s) => s.rpc("creator_contact_delete", { p_creator: creatorId, p_id: id }),
    "profile.removed",
  );
}

// ---------------------------------------------------------------------------------------------------------------
// KYC
// ---------------------------------------------------------------------------------------------------------------
const kycSaveResult = z.object({
  ok: z.boolean(),
  error: z.string().optional(),
  status: z.string().optional(),
  complete: z.boolean().optional(),
});

export async function saveKyc(
  creatorId: string,
  input: KycInput,
): Promise<ActionResult<{ status: string }>> {
  const t = await getTranslations();
  if (!uuid.safeParse(creatorId).success) return fail(t("errors.invalidInput"));
  const p = kycInput.safeParse(input);
  if (!p.success) {
    const code = p.error.issues[0]?.message ?? "";
    return fail(
      t(
        code in KYC_FORM_ERRORS
          ? KYC_FORM_ERRORS[code as keyof typeof KYC_FORM_ERRORS]
          : "errors.invalidInput",
      ),
    );
  }
  const v = p.data;
  if (v.proofPath && !v.proofPath.startsWith(`${creatorId}/`))
    return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { data, error } = await supabase.rpc("kyc_save", {
    p_creator: creatorId,
    p_pan: v.pan,
    p_name_on_pan: v.nameOnPan,
    p_gst_status: v.gstStatus,
    p_gstin: v.gstStatus === "unregistered" ? "" : v.gstin,
    p_bank_account: v.bankAccount,
    p_ifsc: v.ifsc,
    p_account_holder: v.accountHolder,
    p_proof_path: v.proofPath || undefined,
  });
  if (error) return dbFail(error, t);
  const r = kycSaveResult.parse(data);
  if (!r.ok)
    return fail(
      t(
        r.error && r.error in KYC_DB_ERRORS
          ? KYC_DB_ERRORS[r.error as keyof typeof KYC_DB_ERRORS]
          : "errors.invalidInput",
      ),
    );
  refresh(creatorId);
  revalidatePath("/admin/kyc");
  return {
    ok: true,
    data: { status: r.status ?? "pending" },
    message: r.complete ? t("kyc.submitted") : t("kyc.savedIncomplete"),
  };
}

const proofRequest = z.object({
  creatorId: z.uuid(),
  fileName: z.string().min(1).max(200),
  type: z.enum(KYC_PROOF_TYPES),
  size: z.number().int().positive().max(KYC_PROOF_MAX_BYTES),
});

/**
 * A one-time signed URL to upload a KYC proof straight to the private `inf-kyc` bucket (the file never passes through
 * the app server). Checks the caller may edit this creator first. The bucket itself enforces type and size.
 */
export async function kycProofUploadUrl(
  input: z.input<typeof proofRequest>,
): Promise<ActionResult<{ path: string; token: string }>> {
  const t = await getTranslations();
  const p = proofRequest.safeParse(input);
  if (!p.success) return fail(t("kyc.errors.proofType"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const allowed = await supabase.rpc("can_edit_creator", { p_creator: p.data.creatorId });
  if (allowed.data !== true) return fail(t("errors.forbidden"));
  const path = `${p.data.creatorId}/${Date.now().toString()}-${safeFileName(p.data.fileName)}`;
  const { data, error } = await adminClient().storage.from("inf-kyc").createSignedUploadUrl(path);
  if (error) {
    log.error("kyc_proof.sign_failed", { error: errorMessage(error) });
    return fail(t("errors.generic"));
  }
  return { ok: true, data: { path: data.path, token: data.token } };
}

const verifyInput = z
  .object({
    creatorId: z.uuid(),
    approve: z.boolean(),
    reason: z.string().trim().max(500),
    gstinVerified: z.boolean(),
  })
  .refine((v) => v.approve || v.reason.length >= 3, { path: ["reason"] });

export async function verifyKyc(input: z.input<typeof verifyInput>): Promise<ActionResult> {
  const t = await getTranslations();
  const p = verifyInput.safeParse(input);
  if (!p.success) return fail(t("kyc.errors.reason"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("kyc_verify", {
    p_creator: p.data.creatorId,
    p_approve: p.data.approve,
    p_reason: p.data.reason,
    p_gstin_verified: p.data.gstinVerified,
  });
  if (error)
    return /not ready/i.test(error.message) ? fail(t("kyc.errors.notReady")) : dbFail(error, t);
  refresh(p.data.creatorId);
  revalidatePath("/admin/kyc");
  return { ok: true, message: p.data.approve ? t("kyc.verified") : t("kyc.rejected") };
}

const revealResult = z.object({
  pan: z.string().nullable(),
  bank_account: z.string().nullable(),
  proof_path: z.string().nullable(),
});

/** Finance only (kyc.reveal): full PAN and account number plus a 60-second proof link. Audited in the database. */
export async function revealKyc(
  creatorId: string,
  reason: string,
): Promise<
  ActionResult<{ pan: string | null; bankAccount: string | null; proofUrl: string | null }>
> {
  const t = await getTranslations();
  const p = z
    .object({ creatorId: z.uuid(), reason: z.string().trim().min(3).max(300) })
    .safeParse({ creatorId, reason });
  if (!p.success) return fail(t("kyc.errors.reason"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { data, error } = await supabase.rpc("kyc_reveal", {
    p_creator: p.data.creatorId,
    p_reason: p.data.reason,
  });
  if (error) return dbFail(error, t);
  const r = revealResult.parse(data);
  let proofUrl: string | null = null;
  if (r.proof_path) {
    const signed = await adminClient().storage.from("inf-kyc").createSignedUrl(r.proof_path, 60);
    proofUrl = signed.data?.signedUrl ?? null;
  }
  return { ok: true, data: { pan: r.pan, bankAccount: r.bank_account, proofUrl } };
}
