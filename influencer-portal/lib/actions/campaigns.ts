"use server";
// Campaign actions for staff (build, open, invite, review, counter), creators and negotiating agencies (apply,
// respond, counter, accept, message). Each validates input and calls one inf.* function, which decides who may act.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import {
  applyInput,
  campaignInput,
  CAMPAIGN_STATUSES,
  offerTerms,
  rupeesToPaise,
  type ApplyInput,
  type CampaignInput,
  type OfferTerms,
} from "@/lib/campaigns/schemas";
import { createDealFromApplication } from "@/lib/deals/from-application";
import { errorMessage, log } from "@/lib/log";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
const uuid = z.uuid();

async function session(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

const KNOWN: [RegExp, string][] = [
  [/before opening/i, "campaigns.errors.notReady"],
  [/cannot move a/i, "campaigns.errors.transition"],
  [/unknown programme/i, "campaigns.errors.programme"],
  [/open the campaign before inviting/i, "campaigns.errors.inviteDraft"],
  [/not open|applications closed/i, "campaigns.errors.closed"],
  [/invite-only/i, "campaigns.errors.inviteOnly"],
  [/not eligible/i, "campaigns.errors.notEligible"],
  [/no slots left/i, "campaigns.errors.noSlots"],
  [/already applied/i, "campaigns.errors.alreadyApplied"],
  [/already answered/i, "campaigns.errors.answered"],
  [/no longer open|application is closed/i, "campaigns.errors.offerClosed"],
  [/other side must accept/i, "campaigns.errors.ownOffer"],
  [/https/i, "campaigns.errors.sample"],
];

function dbFail(error: { code?: string; message: string }, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of KNOWN) if (re.test(error.message)) return fail(t(key as "campaigns.errors.closed"));
  if (error.code === "23505") return fail(t("campaigns.errors.alreadyApplied"));
  if (error.code === "22023" || error.code === "23514") return fail(t("errors.invalidInput"));
  log.warn("campaigns.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

function refreshAll(campaignId?: string, appId?: string) {
  revalidatePath("/admin/campaigns", "layout");
  revalidatePath("/admin/applications", "layout");
  revalidatePath("/creator/campaigns", "layout");
  revalidatePath("/agency", "layout");
  if (campaignId) revalidatePath(`/admin/campaigns/${campaignId}`);
  if (appId) {
    revalidatePath(`/admin/applications/${appId}`);
    revalidatePath(`/creator/applications/${appId}`);
  }
}

export async function saveCampaign(input: CampaignInput): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const p = campaignInput.safeParse(input);
  if (!p.success) {
    const code = p.error.issues[0]?.message;
    return fail(
      code === "end_before_start"
        ? t("campaigns.errors.dates")
        : code === "apply_after_end"
          ? t("campaigns.errors.applyBy")
          : t("errors.invalidInput"),
    );
  }
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = p.data;
  const { data, error } = await supabase.rpc("campaign_save", {
    p: {
      id: v.id ?? "",
      name: v.name,
      objective: v.objective,
      description: v.description,
      visibility: v.visibility,
      starts_on: v.startsOn,
      ends_on: v.endsOn,
      apply_by: v.applyBy,
      budget_paise: v.budgetRupees === null ? "" : rupeesToPaise(v.budgetRupees),
      slots: v.slots ?? "",
      eligibility: v.eligibility,
      deliverables: v.deliverables,
      compensation_summary: v.compensationSummary,
      internal_notes: v.internalNotes,
      owner_id: v.ownerId,
      default_preset_id: v.presetId,
      programme_ids: v.programmeIds.map(String),
    },
  });
  if (error) return dbFail(error, t);
  refreshAll(data);
  return { ok: true, data: { id: data }, message: v.id ? t("campaigns.saved") : t("campaigns.created") };
}

export async function setCampaignStatus(campaignId: string, status: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(campaignId).success || !(CAMPAIGN_STATUSES as readonly string[]).includes(status))
    return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("campaign_set_status", { p_campaign: campaignId, p_status: status });
  if (error) return dbFail(error, t);
  refreshAll(campaignId);
  return { ok: true, message: t("campaigns.statusChanged", { status: t(`campaigns.statuses.${status as "open"}`) }) };
}

export async function inviteToCampaign(
  campaignId: string,
  creatorIds: string[],
  message: string,
): Promise<ActionResult<{ count: number }>> {
  const t = await getTranslations();
  const ids = z.array(uuid).min(1).max(200).safeParse(creatorIds);
  if (!uuid.safeParse(campaignId).success || !ids.success || message.length > 2000)
    return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { data, error } = await supabase.rpc("campaign_invite", {
    p_campaign: campaignId,
    p_creators: ids.data,
    p_message: message,
  });
  if (error) return dbFail(error, t);
  refreshAll(campaignId);
  return {
    ok: true,
    data: { count: data },
    message: t("campaigns.invites.sent", { count: data, skipped: ids.data.length - data }),
  };
}

export async function withdrawInvite(inviteId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(inviteId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("invite_withdraw", { p_invite: inviteId });
  if (error) return dbFail(error, t);
  refreshAll();
  return { ok: true, message: t("campaigns.invites.withdrawn") };
}

export interface ProgrammeHit {
  id: number;
  program_name: string;
  specialization: string | null;
  level: string | null;
  mode: string | null;
  university: string;
  fee_total: number | null;
}

export async function searchProgrammes(q: string): Promise<ProgrammeHit[]> {
  const query = z.string().trim().max(80).safeParse(q);
  if (!query.success) return [];
  const supabase = await session();
  if (!supabase) return [];
  const { data, error } = await supabase.rpc("catalog_programmes_search", { p_q: query.data, p_limit: 20 });
  if (error) return [];
  return data;
}

// ---------------------------------------------------------------------------------------------------------------
// Creator / agency side
// ---------------------------------------------------------------------------------------------------------------
export async function applyToCampaign(input: ApplyInput): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const p = applyInput.safeParse(input);
  if (!p.success) {
    const code = p.error.issues[0]?.message;
    return fail(
      code === "fee_required"
        ? t("campaigns.errors.feeRequired")
        : code === "sample"
          ? t("campaigns.errors.sample")
          : t("errors.invalidInput"),
    );
  }
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = p.data;
  const { data, error } = await supabase.rpc("campaign_apply", {
    p_campaign: v.campaignId,
    p_creator: v.creatorId,
    p_pitch: v.pitch,
    p_samples: v.samples,
    p_terms: v.terms,
  });
  if (error) return dbFail(error, t);
  refreshAll(v.campaignId, data);
  return {
    ok: true,
    data: { id: data },
    message: v.terms.counter ? t("campaigns.apply.countered") : t("campaigns.apply.sent"),
  };
}

export async function declineInvite(inviteId: string, reason: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(inviteId).success || reason.length > 300) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("invite_decline", { p_invite: inviteId, p_reason: reason });
  if (error) return dbFail(error, t);
  refreshAll();
  return { ok: true, message: t("campaigns.invites.declined") };
}

export async function makeOffer(appId: string, terms: OfferTerms, message: string): Promise<ActionResult> {
  const t = await getTranslations();
  const p = offerTerms.safeParse(terms);
  if (!uuid.safeParse(appId).success || message.length > 2000) return fail(t("errors.invalidInput"));
  if (!p.success)
    return fail(
      p.error.issues[0]?.message === "fee_required" ? t("campaigns.errors.feeRequired") : t("errors.invalidInput"),
    );
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("offer_make", { p_app: appId, p_terms: p.data, p_message: message });
  if (error) return dbFail(error, t);
  refreshAll(undefined, appId);
  return { ok: true, message: t("campaigns.offers.sent") };
}

export async function acceptOffer(offerId: string, appId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(offerId).success || !uuid.safeParse(appId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("offer_accept", { p_offer: offerId });
  if (error) return dbFail(error, t);
  // The deal follows at once; if this fails, the queued deal.from_application job retries it.
  try {
    await createDealFromApplication(appId);
  } catch (e) {
    log.warn("deals.from_application_failed", { appId, error: errorMessage(e) });
  }
  refreshAll(undefined, appId);
  revalidatePath("/admin/deals", "layout");
  revalidatePath("/creator/deals", "layout");
  return { ok: true, message: t("campaigns.offers.accepted") };
}

export async function shortlistApplication(appId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(appId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("application_shortlist", { p_app: appId });
  if (error) return dbFail(error, t);
  refreshAll(undefined, appId);
  return { ok: true, message: t("campaigns.review.shortlisted") };
}

export async function rejectApplication(appId: string, reason: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(appId).success || reason.trim().length < 3 || reason.length > 1000)
    return fail(t("creators.errors.reason"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("application_reject", { p_app: appId, p_reason: reason.trim() });
  if (error) return dbFail(error, t);
  refreshAll(undefined, appId);
  return { ok: true, message: t("campaigns.review.rejected") };
}

export async function withdrawApplication(appId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(appId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("application_withdraw", { p_app: appId });
  if (error) return dbFail(error, t);
  refreshAll(undefined, appId);
  return { ok: true, message: t("campaigns.apply.withdrawn") };
}

export async function postApplicationMessage(appId: string, body: string): Promise<ActionResult> {
  const t = await getTranslations();
  const b = z.string().trim().min(1).max(4000).safeParse(body);
  if (!uuid.safeParse(appId).success || !b.success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("application_message", { p_app: appId, p_body: b.data });
  if (error) return dbFail(error, t);
  refreshAll(undefined, appId);
  return { ok: true };
}
