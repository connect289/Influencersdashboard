"use server";
// Refreshing the dashboards' summary views on demand (staff with analytics.read). pg_cron refreshes them every 15
// minutes; a manual refresh is skipped when the last one is under two minutes old.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { loadRefreshedAt } from "@/lib/analytics/data";
import { requireStaff } from "@/lib/auth/guards";
import { log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";
import { fail, type ActionResult } from "./result";

const MIN_INTERVAL_MS = 2 * 60_000;

export async function refreshAnalytics(): Promise<ActionResult> {
  const t = await getTranslations();
  const { supabase } = await requireStaff("analytics.read");
  const last = await loadRefreshedAt(supabase).catch(() => null);
  if (last && Date.now() - Date.parse(last) < MIN_INTERVAL_MS) return { ok: true, message: t("analytics.fresh") };
  const { error } = await adminClient().rpc("analytics_refresh");
  if (error) {
    log.error("analytics.refresh_failed", { error: error.message });
    return fail(t("errors.generic"));
  }
  revalidatePath("/admin/analytics", "layout");
  revalidatePath("/admin/creators", "layout");
  return { ok: true, message: t("analytics.refreshed") };
}
