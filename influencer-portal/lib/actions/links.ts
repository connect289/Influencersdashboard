"use server";
// Tracking links and attribution actions. Creators (and agencies with the negotiate grant) make links for their agreed
// deals; staff make them for anyone, override attributions with a reason, decide fraud flags, run backfills and edit
// the stage rules. Each action validates its input and calls inf.* functions, which decide who may act.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { cryptoRandom, suggestCode } from "@/lib/attribution/codes";
import {
  ATTRIBUTION_DB_ERRORS,
  backfillInput,
  fraudDecisionInput,
  linkInput,
  overrideInput,
  stageRuleInput,
  type LinkInput,
  type OverrideInput,
  type StageRuleInput,
} from "@/lib/attribution/schemas";
import { fetchMe } from "@/lib/auth/guards";
import { log } from "@/lib/log";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;

async function signedIn(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

function dbFail(error: { code?: string; message: string }, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of ATTRIBUTION_DB_ERRORS)
    if (re.test(error.message)) return fail(t(`leads.errors.${key}` as "leads.errors.codeTaken"));
  if (error.code === "22023" || error.code === "23514" || error.code === "23505")
    return fail(t("errors.invalidInput"));
  log.warn("attribution.db_error", { code: error.code, error: error.message });
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

function refresh() {
  revalidatePath("/creator/links");
  revalidatePath("/creator/leads");
  revalidatePath("/admin/leads", "layout");
  revalidatePath("/admin/creators", "layout");
  revalidatePath("/agency", "layout");
}

/** A new tracking link with a fresh code (`HANDLE-TAG-XX`), retrying on the rare clash. */
export async function createLink(
  input: LinkInput,
): Promise<ActionResult<{ id: string; code: string }>> {
  return act(linkInput, input, async (db, v, t) => {
    const { data: creator } = await db
      .from("creators")
      .select("handle")
      .eq("id", v.creatorId)
      .maybeSingle();
    const handle = creator?.handle ?? "creator";
    const tag =
      v.platform ??
      (v.destination === "website_landing"
        ? "website"
        : v.destination === "whatsapp_witty"
          ? "whatsapp"
          : "other");
    for (let attempt = 0; attempt < 6; attempt++) {
      const code = suggestCode(handle, tag, cryptoRandom);
      const { data, error } = await db.rpc("link_create", {
        p: {
          creator_id: v.creatorId,
          deal_id: v.dealId,
          deliverable_id: v.deliverableId,
          programme_id: v.programmeId,
          code,
          destination: v.destination,
          custom_url: v.customUrl,
          platform: v.platform,
          label: v.label,
        },
      });
      if (!error) {
        refresh();
        return { ok: true, data: { id: data, code }, message: t("links.created", { code }) };
      }
      if (!/this code is taken/.test(error.message)) return dbFail(error, t);
    }
    return fail(t("errors.generic"));
  });
}

export async function setLinkActive(linkId: string, active: boolean): Promise<ActionResult> {
  return act(z.uuid(), linkId, async (db, id, t) => {
    const { error } = await db.rpc("link_set_active", { p_link: id, p_active: active });
    if (error) return dbFail(error, t);
    refresh();
    return { ok: true, message: active ? t("links.activated") : t("links.deactivated") };
  });
}

export async function overrideAttribution(input: OverrideInput): Promise<ActionResult> {
  return act(overrideInput, input, async (db, v, t) => {
    const { error } = await db.rpc("attribution_override", {
      p: {
        student_lead_id: v.studentLeadId,
        creator_id: v.creatorId,
        status: v.status,
        link_id: v.linkId,
        reason: v.reason,
      },
    });
    if (error) return dbFail(error, t);
    refresh();
    return {
      ok: true,
      message:
        v.status === "manually_credited"
          ? t("leads.override.credited")
          : t("leads.override.rejected"),
    };
  });
}

export async function decideFraudFlag(
  input: z.input<typeof fraudDecisionInput>,
): Promise<ActionResult> {
  return act(fraudDecisionInput, input, async (db, v, t) => {
    const { error } = await db.rpc("fraud_decide", {
      p_flag: v.flagId,
      p_confirm: v.confirm,
      p_note: v.note,
    });
    if (error) return dbFail(error, t);
    refresh();
    return { ok: true, message: v.confirm ? t("leads.fraud.confirmed") : t("leads.fraud.cleared") };
  });
}

export async function startBackfill(input: z.input<typeof backfillInput>): Promise<ActionResult> {
  return act(backfillInput, input, async (db, v, t) => {
    const { error } = await db.rpc("lead_backfill", { p_from: v.from, p_to: v.to });
    if (error) return dbFail(error, t);
    return { ok: true, message: t("leads.backfill.queued") };
  });
}

export async function saveStageRule(input: StageRuleInput): Promise<ActionResult> {
  return act(stageRuleInput, input, async (db, v, t) => {
    const { error } = await db.rpc("stage_mapping_save", {
      p: {
        id: v.id,
        priority: v.priority,
        conditions: v.conditions,
        creator_stage: v.creatorStage ?? "",
        reason_category: v.reasonCategory,
        flag: v.flag ?? "",
        active: v.active,
      },
    });
    if (error) return dbFail(error, t);
    revalidatePath("/admin/leads/stages");
    return { ok: true, message: t("leads.stages.saved") };
  });
}
