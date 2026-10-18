"use server";
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { assertStaff, ForbiddenError } from "@/lib/auth/guards";
import { fail, type ActionResult } from "./result";

export async function retryJob(id: number): Promise<ActionResult> {
  const t = await getTranslations();
  if (!z.number().int().positive().safeParse(id).success) return fail(t("errors.invalidInput"));
  try {
    const { supabase } = await assertStaff("system.read");
    const { data, error } = await supabase.rpc("job_retry", { p_id: id });
    if (error) return fail(t("errors.generic"));
    revalidatePath("/admin/system");
    return data ? { ok: true, message: t("system.retried") } : fail(t("system.notRetryable"));
  } catch (e) {
    return fail(e instanceof ForbiddenError ? e.message : t("errors.generic"));
  }
}
