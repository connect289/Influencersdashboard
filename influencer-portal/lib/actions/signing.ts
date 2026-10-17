"use server";
// OTP click-sign (spec 8.4). The person is authenticated here; the signing functions run as the service role with
// that person's own user id (never one from the browser), the IP and user agent of this request, and the version and
// hash the person was shown. The database decides whether they may sign, checks the code and records the signature.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { finalizeContract } from "@/lib/contracts/finalize";
import { SIGN_ERRORS, signCodeInput, signInput, type SignCodeInput, type SignInput } from "@/lib/contracts/schemas";
import { maskDestination, signingChannels } from "@/lib/contracts/signing";
import { errorMessage, log } from "@/lib/log";
import { emailProvider } from "@/lib/notify/email";
import { contractSignCodeEmail } from "@/lib/notify/templates";
import { whatsAppProvider } from "@/lib/notify/whatsapp";
import { requestContext } from "@/lib/request-context";
import { adminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;

async function person() {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.user_id || !me.session?.verified || me.session.revoked) return null;
  const name = me.staff?.full_name ?? me.agency?.member_name ?? me.creator?.display_name ?? "";
  return { userId: me.user_id, email: me.email ?? null, name, creatorId: me.creator?.id ?? null };
}

const refusal = z.object({
  ok: z.literal(false),
  error: z.enum(SIGN_ERRORS),
  attempts_left: z.number().optional(),
});

function signFail(data: unknown, t: T): ActionResult<never> {
  const r = refusal.safeParse(data);
  if (!r.success) return fail(t("errors.generic"));
  if (r.data.error === "wrong_code")
    return fail(t("contracts.sign.errors.wrong_code", { left: r.data.attempts_left ?? 0 }));
  return fail(t(`contracts.sign.errors.${r.data.error}` as "contracts.sign.errors.expired"));
}

function refresh(contractId: string) {
  revalidatePath("/admin/contracts", "layout");
  revalidatePath("/creator/contracts", "layout");
  revalidatePath("/agency", "layout");
  revalidatePath(`/admin/contracts/${contractId}`);
}

export async function requestSignCode(input: SignCodeInput): Promise<ActionResult<{ sentTo: string }>> {
  const t = await getTranslations();
  const parsed = signCodeInput.safeParse(input);
  if (!parsed.success) return fail(t("errors.invalidInput"));
  const p = await person();
  if (!p) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const channels = await signingChannels({ email: p.email, creatorId: p.creatorId });
  const dest = channels.find((c) => c.channel === v.channel);
  if (!dest) return fail(t("contracts.sign.errors.channel"));
  const { data, error } = await adminClient().rpc("contract_sign_code_issue", {
    p_contract: v.contractId,
    p_user: p.userId,
    p_channel: v.channel,
  });
  if (error) {
    log.warn("contracts.sign_code_failed", { error: error.message });
    return fail(t("errors.generic"));
  }
  const issued = z
    .object({
      ok: z.literal(true),
      code: z.string().regex(/^\d{6}$/),
      number: z.string(),
      expires_in_seconds: z.number(),
    })
    .safeParse(data);
  if (!issued.success) return signFail(data, t);
  const minutes = Math.round(issued.data.expires_in_seconds / 60);
  try {
    if (v.channel === "email" && p.email)
      await emailProvider().send({
        ...contractSignCodeEmail(issued.data.code, p.name, issued.data.number, minutes),
        to: p.email,
      });
    else if (dest.phone)
      await whatsAppProvider().sendTemplate({
        to: dest.phone.replace(/^\+/, ""),
        template: "contract_sign_code",
        language: "en",
        params: [issued.data.code, issued.data.number],
      });
  } catch (e) {
    log.error("contracts.sign_code_delivery_failed", {
      channel: v.channel,
      error: errorMessage(e),
    });
    return fail(t("contracts.sign.errors.delivery"));
  }
  const sentTo = maskDestination(v.channel, v.channel === "email" ? (p.email ?? "") : (dest.phone ?? ""));
  return {
    ok: true,
    data: { sentTo },
    message: t("contracts.sign.codeSent", { to: sentTo, minutes }),
  };
}

export async function signContract(input: SignInput): Promise<ActionResult<{ role: string }>> {
  const t = await getTranslations();
  const parsed = signInput.safeParse(input);
  if (!parsed.success) return fail(t("contracts.sign.errors.form"));
  const p = await person();
  if (!p) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const ctx = await requestContext();
  const { data, error } = await adminClient().rpc("contract_sign", {
    p_contract: v.contractId,
    p_user: p.userId,
    p_version: v.versionId,
    p_sha256: v.sha256,
    p_name: v.name,
    p_consent_version: v.consentVersion,
    p_code: v.code,
    p_ip: ctx.ip ?? "",
    p_user_agent: ctx.userAgent ?? "",
  });
  if (error) {
    log.warn("contracts.sign_failed", { error: error.message });
    return fail(t("errors.generic"));
  }
  const ok = z.object({ ok: z.literal(true), role: z.string() }).safeParse(data);
  if (!ok.success) return signFail(data, t);
  if (ok.data.role === "signatory")
    // The signed PDF at once; the queued contract.finalize job retries if this fails.
    await finalizeContract(v.contractId).catch((e: unknown) =>
      log.warn("contracts.finalize_inline_failed", { error: errorMessage(e) }),
    );
  refresh(v.contractId);
  return {
    ok: true,
    data: { role: ok.data.role },
    message: ok.data.role === "signatory" ? t("contracts.sign.countersigned") : t("contracts.sign.signed"),
  };
}
