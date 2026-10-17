"use server";
// Deal actions. Staff build, propose, amend and move deals; the creator (or their negotiating agency) accepts or
// declines proposed terms. Each validates input and calls one inf.* function, which decides who may act. The
// simulator and the dry-run are pure computations over data the caller is allowed to read.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { toStaffMe } from "@/lib/auth/me";
import { compConfig } from "@/lib/compensation/schema";
import {
  forCreator,
  scenario,
  simulate,
  type CreatorSimulation,
  type ScenarioInput,
} from "@/lib/compensation/simulator";
import { commissionEstimate, loadCompContext, loadDeal, loadTdsSections, versionsOf } from "@/lib/deals/data";
import { dryRun, type DryRunResult } from "@/lib/deals/dry-run";
import {
  DEAL_DB_ERRORS,
  dealCreateInput,
  dealUpdateInput,
  istLocalToIso,
  presetInput,
  proposeInput,
  renewInput,
  respondInput,
  statusInput,
  type DealCreateInput,
  type DealUpdateInput,
} from "@/lib/deals/schemas";
import type { Json } from "@/lib/database.types";
import { log } from "@/lib/log";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
const uuid = z.uuid();

async function signedIn(): Promise<{ supabase: ServerSupabase; staff: boolean; canWrite: boolean } | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  const staff = toStaffMe(me);
  return {
    supabase,
    staff: staff?.permissions.has("deal.read") ?? false,
    canWrite: staff?.permissions.has("deal.write") ?? false,
  };
}

function dbFail(error: { code?: string; message: string }, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of DEAL_DB_ERRORS)
    if (re.test(error.message)) return fail(t(`deals.errors.${key}` as "deals.errors.config"));
  if (error.code === "22023" || error.code === "23514") return fail(t("errors.invalidInput"));
  log.warn("deals.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

function refresh(dealId?: string) {
  revalidatePath("/admin/deals", "layout");
  revalidatePath("/creator/deals", "layout");
  revalidatePath("/agency", "layout");
  if (dealId) revalidatePath(`/admin/deals/${dealId}`);
}

// ---------------------------------------------------------------------------------------------------------------
// Staff
// ---------------------------------------------------------------------------------------------------------------
export async function createDeal(input: DealCreateInput): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const parsed = dealCreateInput.safeParse(input);
  if (!parsed.success) return fail(t("deals.errors.config"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { data, error } = await s.supabase.rpc("deal_create", {
    p: {
      creator_id: v.creatorId,
      campaign_id: v.campaignId,
      title: v.title,
      starts_on: v.startsOn,
      ends_on: v.endsOn,
      preset_id: v.presetId,
      comp_config: v.config,
      internal_notes: v.internalNotes,
    },
  });
  if (error) return dbFail(error, t);
  refresh();
  return { ok: true, data: { id: data }, message: t("deals.created") };
}

export async function updateDeal(input: DealUpdateInput): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = dealUpdateInput.safeParse(input);
  if (!parsed.success) return fail(t("deals.errors.config"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const p: { [key: string]: Json | undefined } = {};
  if (v.title !== undefined) p.title = v.title;
  if (v.startsOn !== undefined) p.starts_on = v.startsOn;
  if (v.endsOn !== undefined) p.ends_on = v.endsOn;
  if (v.config !== undefined) p.comp_config = v.config;
  if (v.ownerId !== undefined) p.owner_id = v.ownerId;
  if (v.internalNotes !== undefined) p.internal_notes = v.internalNotes;
  const { error } = await s.supabase.rpc("deal_update", { p_deal: v.dealId, p });
  if (error) return dbFail(error, t);
  refresh(v.dealId);
  return { ok: true, message: t("deals.saved") };
}

export async function proposeDeal(input: z.input<typeof proposeInput>): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = proposeInput.safeParse(input);
  if (!parsed.success) return fail(t("errors.invalidInput"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { error } = await s.supabase.rpc("deal_propose", {
    p_deal: v.dealId,
    p_effective_from: v.effectiveFrom ? istLocalToIso(v.effectiveFrom) : undefined,
    p_note: v.note || undefined,
  });
  if (error) return dbFail(error, t);
  refresh(v.dealId);
  return { ok: true, message: t("deals.proposed") };
}

export async function withdrawProposal(versionId: string, dealId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(versionId).success || !uuid.safeParse(dealId).success) return fail(t("errors.invalidInput"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const { error } = await s.supabase.rpc("deal_version_withdraw", { p_version: versionId });
  if (error) return dbFail(error, t);
  refresh(dealId);
  return { ok: true, message: t("deals.withdrawn") };
}

export async function setDealStatus(input: z.input<typeof statusInput>): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = statusInput.safeParse(input);
  if (!parsed.success) return fail(t("deals.errors.reason"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { error } = await s.supabase.rpc("deal_set_status", {
    p_deal: v.dealId,
    p_status: v.status,
    p_reason: v.reason || undefined,
  });
  if (error) return dbFail(error, t);
  refresh(v.dealId);
  return { ok: true, message: t("deals.statusChanged") };
}

export async function deleteDraftDeal(dealId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(dealId).success) return fail(t("errors.invalidInput"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const { error } = await s.supabase.rpc("deal_delete_draft", { p_deal: dealId });
  if (error) return dbFail(error, t);
  refresh();
  return { ok: true, message: t("deals.deleted") };
}

/** A renewal: a new draft deal with the same terms and new dates, to propose and contract as usual. */
export async function renewDeal(input: z.input<typeof renewInput>): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const parsed = renewInput.safeParse(input);
  if (!parsed.success) return fail(t("deals.errors.dates"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { data, error } = await s.supabase.rpc("deal_renew", {
    p_deal: v.dealId,
    p_starts_on: v.startsOn,
    p_ends_on: v.endsOn || undefined,
  });
  if (error) return dbFail(error, t);
  refresh(v.dealId);
  return { ok: true, data: { id: data }, message: t("deals.renewed") };
}

export async function savePreset(input: z.input<typeof presetInput>): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const parsed = presetInput.safeParse(input);
  if (!parsed.success) return fail(t("deals.errors.config"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { data, error } = await s.supabase.rpc("deal_preset_save", {
    p: { id: v.id, name: v.name, description: v.description, comp_config: v.config },
  });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/deals", "layout");
  return { ok: true, data: { id: data }, message: t("deals.presets.saved") };
}

export async function archivePreset(id: string, archived: boolean): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(id).success) return fail(t("errors.invalidInput"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const { error } = await s.supabase.rpc("deal_preset_archive", { p_id: id, p_archived: archived });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/deals", "layout");
  return { ok: true, message: archived ? t("deals.presets.archived") : t("deals.presets.restored") };
}

const creatorSimInput = z.object({ dealId: z.uuid(), versionId: z.uuid().optional(), scenario });

/**
 * The creator's read-only simulator on their own deal. Eduwit's commission per enrolment comes from the catalogue on
 * the server and is never returned; the result carries the creator's own earnings only (spec 6.2).
 */
export async function simulateMyDeal(input: {
  dealId: string;
  versionId?: string;
  scenario: Omit<ScenarioInput, "avg_commission_gross_paise">;
}): Promise<ActionResult<CreatorSimulation>> {
  const t = await getTranslations();
  const parsed = creatorSimInput.safeParse(input);
  if (!parsed.success) return fail(t("deals.errors.scenario"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const deal = await loadDeal(s.supabase, parsed.data.dealId);
  if (!deal) return fail(t("errors.forbidden"));
  const { current, pending } = versionsOf(deal);
  const version = parsed.data.versionId
    ? deal.versions.find((x) => x.id === parsed.data.versionId)
    : (current ?? pending);
  if (!version) return fail(t("deals.errors.noTerms"));
  const [ctx, tds, estimate] = await Promise.all([
    loadCompContext(s.supabase),
    loadTdsSections(s.supabase),
    commissionEstimate(deal.campaign_id),
  ]);
  const sc = { ...parsed.data.scenario, avg_commission_gross_paise: estimate ?? undefined };
  const result = simulate(version.comp_config, sc, {
    starts_on: deal.starts_on,
    context: ctx.engine,
    sections: tds.sections,
    gst_rate_bps: ctx.gst_rate_bps,
  });
  return { ok: true, data: forCreator(result) };
}

const dryRunInput = z.object({
  dealId: z.uuid(),
  config: compConfig,
  effectiveFrom: z.union([z.literal(""), z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/)]).default(""),
  scenario,
});

/** What an amendment would change, under a scenario projected to the deal's end. Recorded as a dry run. */
export async function dryRunAmendment(input: z.input<typeof dryRunInput>): Promise<ActionResult<DryRunResult>> {
  const t = await getTranslations();
  const parsed = dryRunInput.safeParse(input);
  if (!parsed.success) return fail(t("deals.errors.scenario"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  if (!s.canWrite) return fail(t("errors.forbidden"));
  const v = parsed.data;
  const deal = await loadDeal(s.supabase, v.dealId);
  if (!deal) return fail(t("errors.forbidden"));
  const { accepted, current } = versionsOf(deal);
  if (!current) return fail(t("deals.errors.noTerms"));
  const effective = v.effectiveFrom ? istLocalToIso(v.effectiveFrom) : new Date().toISOString();
  if (effective <= current.effective_from) return fail(t("deals.errors.effectiveFrom"));
  const [ctx, estimate] = await Promise.all([loadCompContext(s.supabase), commissionEstimate(deal.campaign_id)]);
  const result = dryRun({
    deal: { id: deal.id, starts_on: deal.starts_on, ends_on: deal.ends_on },
    versions: accepted.map((x) => ({ id: x.id, effective_from: x.effective_from, config: x.comp_config })),
    draft: { config: v.config, effective_from: effective },
    scenario: {
      ...v.scenario,
      avg_commission_gross_paise: v.scenario.avg_commission_gross_paise ?? estimate ?? undefined,
    },
    context: ctx.engine,
  });
  const { error } = await s.supabase.rpc("comp_run_record", {
    p_deal: deal.id,
    p_version: current.id,
    p_kind: "dry_run",
    p_as_of: result.as_of,
    p_summary: {
      effective_from: effective,
      delta_paise: result.delta_paise,
      changes: result.changes.length,
      before_paise: result.before.net_paise,
      after_paise: result.after.net_paise,
    },
  });
  if (error) log.warn("deals.dry_run_record_failed", { error: error.message });
  revalidatePath(`/admin/deals/${deal.id}`);
  return { ok: true, data: result };
}

// ---------------------------------------------------------------------------------------------------------------
// Creator / agency
// ---------------------------------------------------------------------------------------------------------------
export async function respondToTerms(input: z.input<typeof respondInput>, dealId: string): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = respondInput.safeParse(input);
  if (!parsed.success || !uuid.safeParse(dealId).success) return fail(t("deals.errors.reason"));
  const s = await signedIn();
  if (!s) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { error } = await s.supabase.rpc("deal_version_respond", {
    p_version: v.versionId,
    p_accept: v.accept,
    p_reason: v.reason || undefined,
  });
  if (error) return dbFail(error, t);
  refresh(dealId);
  return { ok: true, message: v.accept ? t("deals.accepted") : t("deals.declined") };
}
