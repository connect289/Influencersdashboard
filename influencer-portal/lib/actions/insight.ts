"use server";
// Tiers and scorecards (spec 15). The Super Admin edits tiers and sets manual tiers (tier.manage); managers run an
// on-demand scorecard (creator.write), which never changes a tier. Each action validates its input and calls inf.*
// functions, which check the permission.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { istToday } from "@/lib/format";
import { log } from "@/lib/log";
import { runScorecard } from "@/lib/scorecards/data";
import {
  INSIGHT_DB_ERRORS,
  manualTierInput,
  tierInput,
  type ManualTierInput,
  type TierInput,
} from "@/lib/scorecards/schemas";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
type DbError = { code?: string; message: string };

async function signedIn(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

function dbFail(error: DbError, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of INSIGHT_DB_ERRORS)
    if (re.test(error.message)) return fail(t(`insight.errors.${key}` as "insight.errors.rankTaken"));
  if (error.code === "22023" || error.code === "23514") return fail(t("errors.invalidInput"));
  log.warn("insight.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

async function act<S extends z.ZodType, Res extends ActionResult<unknown>>(
  schema: S,
  input: unknown,
  body: (db: ServerSupabase, v: z.output<S>, t: T) => Promise<Res>,
): Promise<Res | ActionResult<never>> {
  const t = await getTranslations();
  const parsed = schema.safeParse(input);
  if (!parsed.success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  return body(supabase, parsed.data, t);
}

export async function saveTier(input: TierInput): Promise<ActionResult<{ id: string }>> {
  return act(tierInput, input, async (db, v, t) => {
    const { data, error } = await db.rpc("tier_save", {
      p: { id: v.id ?? "", name: v.name, rank: v.rank, entry_rules: v.rules, benefits: v.benefits, active: v.active },
    });
    if (error) return dbFail(error, t);
    revalidatePath("/admin/settings/tiers");
    return { ok: true, data: { id: data }, message: t("insight.tiers.saved") };
  });
}

export async function setManualTier(input: ManualTierInput): Promise<ActionResult> {
  return act(manualTierInput, input, async (db, v, t) => {
    const { error } = await db.rpc("tier_set_manual", {
      p_creator: v.creatorId,
      p_until: v.until,
      p_reason: v.reason,
      p_tier: v.tierId ?? undefined,
    });
    if (error) return dbFail(error, t);
    revalidatePath(`/admin/creators/${v.creatorId}`);
    return { ok: true, message: t("insight.manual.saved") };
  });
}

export async function clearManualTier(creatorId: string): Promise<ActionResult> {
  return act(z.uuid(), creatorId, async (db, id, t) => {
    const { error } = await db.rpc("tier_clear_manual", { p_creator: id });
    if (error) return dbFail(error, t);
    revalidatePath(`/admin/creators/${id}`);
    return { ok: true, message: t("insight.manual.cleared") };
  });
}

/** An on-demand scorecard for the month so far (never changes the tier). */
export async function runScorecardNow(creatorId: string): Promise<ActionResult> {
  return act(z.uuid(), creatorId, async (db, id, t) => {
    const today = istToday();
    try {
      await runScorecard({ db, creatorId: id, period: today.slice(0, 7), kind: "on_demand", to: today, today });
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      return dbFail({ code: /not allowed/.test(message) ? "42501" : undefined, message }, t);
    }
    revalidatePath(`/admin/creators/${id}`);
    return { ok: true, message: t("insight.scorecard.ran") };
  });
}
