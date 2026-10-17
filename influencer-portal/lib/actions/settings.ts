"use server";
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { assertStaff, ForbiddenError } from "@/lib/auth/guards";
import { isSettingKey, SETTINGS } from "@/lib/settings/registry";
import { fail, type ActionResult } from "./result";

const reasonSchema = z.string().trim().min(3).max(500);

export async function saveSetting(
  key: string,
  value: unknown,
  reason: string,
  expectedVersion: number,
): Promise<ActionResult<{ version: number }>> {
  const t = await getTranslations();
  if (!isSettingKey(key)) return fail(t("settings.errors.unknown"));
  const def = SETTINGS[key];
  const parsed = def.schema.safeParse(value);
  if (!parsed.success)
    return fail(
      t("settings.errors.invalid", {
        details: parsed.error.issues
          .slice(0, 3)
          .map((i) => `${i.path.join(".")}: ${i.message}`)
          .join("; "),
      }),
    );
  const why = reasonSchema.safeParse(reason);
  if (!why.success) return fail(t("settings.errors.reason"));
  if (!Number.isInteger(expectedVersion) || expectedVersion < 0)
    return fail(t("errors.invalidInput"));
  try {
    const { supabase } = await assertStaff(def.edit);
    const { data, error } = await supabase.rpc("setting_set", {
      p_key: key,
      p_value: parsed.data,
      p_reason: why.data,
      p_expected_version: expectedVersion,
    });
    if (error) return fail(t("errors.generic"));
    const r = data as { ok: boolean; error?: string; version?: number; details?: string[] };
    if (!r.ok) {
      if (r.error === "stale") return fail(t("settings.errors.stale"));
      if (r.error === "invalid")
        return fail(
          t("settings.errors.invalid", { details: (r.details ?? []).slice(0, 3).join("; ") }),
        );
      return fail(t("errors.generic"));
    }
    revalidatePath("/admin/settings");
    return {
      ok: true,
      data: { version: r.version ?? expectedVersion },
      message: t("settings.saved"),
    };
  } catch (e) {
    return fail(e instanceof ForbiddenError ? e.message : t("errors.generic"));
  }
}

export async function confirmSetting(key: string, note: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!isSettingKey(key)) return fail(t("settings.errors.unknown"));
  const why = reasonSchema.safeParse(note);
  if (!why.success) return fail(t("settings.errors.note"));
  try {
    const { supabase } = await assertStaff(SETTINGS[key].edit);
    const { error } = await supabase.rpc("setting_confirm", { p_key: key, p_note: why.data });
    if (error) return fail(t("errors.generic"));
  } catch (e) {
    return fail(e instanceof ForbiddenError ? e.message : t("errors.generic"));
  }
  revalidatePath("/admin/settings");
  revalidatePath("/admin");
  return { ok: true, message: t("settings.confirmed") };
}

export interface HistoryRow {
  version: number;
  value: unknown;
  actor_name: string | null;
  reason: string;
  at: string;
}

export async function settingHistory(key: string): Promise<ActionResult<HistoryRow[]>> {
  const t = await getTranslations();
  if (!isSettingKey(key)) return fail(t("settings.errors.unknown"));
  try {
    const { supabase } = await assertStaff();
    const { data, error } = await supabase.rpc("setting_history", { p_key: key });
    if (error) return fail(t("errors.generic"));
    return { ok: true, data };
  } catch (e) {
    return fail(e instanceof ForbiddenError ? e.message : t("errors.generic"));
  }
}
