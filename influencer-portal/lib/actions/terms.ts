"use server";
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { assertCreator } from "@/lib/auth/guards";
import { fail, type ActionResult } from "./result";

export async function acceptTerms(termsVersionId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!z.uuid().safeParse(termsVersionId).success) return fail(t("errors.invalidInput"));
  try {
    const { supabase } = await assertCreator();
    const { error } = await supabase.rpc("terms_accept", { p_terms_version_id: termsVersionId });
    if (error) return fail(t("errors.generic"));
  } catch {
    return fail(t("errors.sessionEnded"));
  }
  revalidatePath("/creator");
  revalidatePath("/creator/terms");
  revalidatePath("/creator/onboarding");
  return { ok: true, message: t("terms.accepted") };
}
