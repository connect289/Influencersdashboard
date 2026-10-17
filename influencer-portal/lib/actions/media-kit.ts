"use server";
// Media-kit preferences and the profile photo (public bucket, uploaded straight from the browser).
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { errorMessage, log } from "@/lib/log";
import { AVATAR_BUCKET, AVATAR_MAX_BYTES, AVATAR_TYPES } from "@/lib/media-kit/data";
import { adminClient } from "@/lib/supabase/admin";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

async function session(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

export async function saveMediaKitSettings(
  creatorId: string,
  publicPage: boolean,
  showRates: boolean,
): Promise<ActionResult> {
  const t = await getTranslations();
  if (!z.uuid().safeParse(creatorId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("media_kit_settings", {
    p_creator: creatorId,
    p_public: publicPage,
    p_show_rates: showRates,
  });
  if (error) return fail(error.code === "42501" ? t("errors.forbidden") : t("errors.generic"));
  revalidatePath("/creator/media-kit");
  revalidatePath("/creator/profile");
  return { ok: true, message: t("mediaKit.saved") };
}

const avatarRequest = z.object({
  creatorId: z.uuid(),
  type: z.enum(
    Object.keys(AVATAR_TYPES) as [keyof typeof AVATAR_TYPES, ...(keyof typeof AVATAR_TYPES)[]],
  ),
  size: z.number().int().positive().max(AVATAR_MAX_BYTES),
});

export async function avatarUploadUrl(
  input: z.input<typeof avatarRequest>,
): Promise<ActionResult<{ path: string; token: string }>> {
  const t = await getTranslations();
  const p = avatarRequest.safeParse(input);
  if (!p.success) return fail(t("mediaKit.errors.avatarType"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const allowed = await supabase.rpc("can_edit_creator", { p_creator: p.data.creatorId });
  if (allowed.data !== true) return fail(t("errors.forbidden"));
  const path = `${p.data.creatorId}/${Date.now().toString()}.${AVATAR_TYPES[p.data.type]}`;
  const { data, error } = await adminClient()
    .storage.from(AVATAR_BUCKET)
    .createSignedUploadUrl(path);
  if (error) {
    log.error("avatar.sign_failed", { error: errorMessage(error) });
    return fail(t("errors.generic"));
  }
  return { ok: true, data: { path: data.path, token: data.token } };
}

export async function setAvatar(creatorId: string, path: string | null): Promise<ActionResult> {
  const t = await getTranslations();
  if (!z.uuid().safeParse(creatorId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("avatar_set", {
    p_creator: creatorId,
    p_path: path ?? undefined,
  });
  if (error) return fail(error.code === "42501" ? t("errors.forbidden") : t("errors.invalidInput"));
  revalidatePath("/creator", "layout");
  revalidatePath(`/admin/creators/${creatorId}`);
  return { ok: true, message: path ? t("mediaKit.avatarSaved") : t("mediaKit.avatarRemoved") };
}
