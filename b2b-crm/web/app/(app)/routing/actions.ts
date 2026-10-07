"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { EngineSchema, HandoffSchema, handoffPayload, parseRuleForm, RateSchema, type Decision } from "@/lib/routing";
import { createClient } from "@/lib/supabase/server";
import type { DecisionReplay } from "@/lib/routing-data";
import { PartnerWeightSchema, PerformanceSchema, PolicySchema, SegmentPolicySchema, segmentPolicyPayload } from "@/lib/segments";

const Id = z.number().int().positive();

/** Messages raised by the b2b routing functions for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}

async function rpc(fn: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  return supabase.schema("b2b").rpc(fn, args);
}

const refresh = () => { revalidatePath("/routing"); revalidatePath("/leads"); revalidatePath("/", "layout"); };

export async function simulateLead(leadId: number): Promise<{ ok: true; decision: Decision } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(leadId).success) return { ok: false, error: "Enter a lead ID." };
  const { data, error } = await rpc("route_simulate", { p_lead_id: leadId });
  if (error) return { ok: false, error: dbMessage(error, "The simulation failed. Try again.") };
  return { ok: true, decision: data as Decision };
}

export async function routeLeadNow(leadId: number, note: string): Promise<{ ok: true; decision: Decision } | { ok: false; error: string }> {
  await assertAdmin();
  const p = z.object({ leadId: Id, note: z.string().trim().min(3).max(300) }).safeParse({ leadId, note });
  if (!p.success) return { ok: false, error: "Add a short note for the audit log." };
  const { data, error } = await rpc("route_now", { p_lead_id: p.data.leadId, p_note: p.data.note });
  if (error) return { ok: false, error: dbMessage(error, "Routing failed. Try again.") };
  refresh();
  return { ok: true, decision: data as Decision };
}

export async function setRoutingLive(live: boolean, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ live: z.boolean(), reason: z.string().trim().min(3).max(300) }).safeParse({ live, reason });
  if (!p.success) return "A reason is required.";
  const { error } = await rpc("set_live_switch", { p_scope: "routing", p_live: p.data.live, p_reason: p.data.reason });
  if (error) return dbMessage(error, "Could not change the switch. Try again.");
  refresh();
}

export type FormState = { errors?: Record<string, string>; error?: string; ok?: number } | undefined;

export async function saveRule(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const parsed = parseRuleForm(form);
  if (!parsed.ok) return { errors: parsed.errors, error: "Check the highlighted fields." };
  const { error } = await rpc("routing_rule_save", { p: parsed.data });
  if (error) return { error: dbMessage(error, "Could not save the rule. Try again.") };
  refresh();
  return { ok: Date.now() };
}

export async function setRuleActive(id: number, active: boolean): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid rule.";
  const { error } = await rpc("routing_rule_set_active", { p_id: id, p_active: active });
  if (error) return dbMessage(error, "Could not change the rule. Try again.");
  refresh();
}

export async function saveRate(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const raw = Object.fromEntries(["partner_id", "scope", "university_id", "rate_type", "value", "tiers", "fee_base", "gst_inclusive", "valid_from", "note"].map((k) => [k, form.get(k) ?? undefined]));
  const p = RateSchema.safeParse(raw);
  if (!p.success) {
    const errors: Record<string, string> = {};
    for (const i of p.error.issues) errors[String(i.path[0])] ??= i.message;
    return { errors, error: "Check the highlighted fields." };
  }
  const { error } = await rpc("rate_save", { p: p.data });
  if (error) return { error: dbMessage(error, "Could not save the rate. Try again.") };
  refresh();
  return { ok: Date.now() };
}

export async function endRate(id: number): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return "Invalid rate.";
  const { error } = await rpc("rate_end", { p_id: id });
  if (error) return dbMessage(error, "Could not end the rate. Try again.");
  refresh();
}

export async function confirmFileRates(partnerId: number): Promise<{ created: number; unchanged: number; tiers_skipped: number } | { error: string }> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success) return { error: "Invalid partner." };
  const { data, error } = await rpc("rates_confirm_from_offers", { p_partner_id: partnerId });
  if (error) return { error: dbMessage(error, "Could not confirm the rates. Try again.") };
  refresh();
  return data as { created: number; unchanged: number; tiers_skipped: number };
}

export async function saveEngineSettings(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const raw = Object.fromEntries(["exploration_share", "cpe_aggregate", "min_learning_leads", "attempt_limit", "partner_limit", "witty_idle_minutes",
    "require_partner_consent", "trusted_sources", "reason"].map((k) => [k, form.get(k) ?? undefined]));
  const p = EngineSchema.safeParse(raw);
  const perf = PerformanceSchema.safeParse(Object.fromEntries(["maturity_days", "half_life_days", "prior_weight", "default_p_enroll", "min_matured_leads",
    "speed_factor", "reliability_factor", "kill_switch", "fixed_split"].map((k) => [k, form.get(k) ?? undefined])));
  if (!p.success || !perf.success) {
    const errors: Record<string, string> = {};
    for (const i of [...(p.error?.issues ?? []), ...(perf.error?.issues ?? [])]) errors[String(i.path[0])] ??= i.message;
    return { errors, error: "Check the highlighted fields." };
  }
  if (perf.data.kill_switch && Object.keys(perf.data.fixed_split).length === 0) {
    return { errors: { fixed_split: "Set the fixed split before turning the kill switch on" }, error: "Check the highlighted fields." };
  }
  const { reason, ...settings } = p.data;
  const { error } = await rpc("engine_settings_save", { p: { ...settings, ...perf.data }, p_reason: reason });
  if (error) return { error: dbMessage(error, "Could not save the settings. Try again.") };
  refresh();
  return { ok: Date.now() };
}

// ---------- Addenda 1 and 2: hand-off rules, rescue, manual routes and the review queue ----------

export async function saveHandoffSettings(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const raw = Object.fromEntries(["sources", "click_ids", "utm_mediums", "include_campaigns", "exclude_campaigns", "b2c_sources", "blocked_phones",
    "junk_capi_signal", "reason"].map((k) => [k, form.get(k) ?? undefined]));
  const p = HandoffSchema.safeParse({ ...raw, ...Object.fromEntries(["sources", "click_ids", "utm_mediums", "include_campaigns", "exclude_campaigns",
    "b2c_sources", "blocked_phones"].map((k) => [k, raw[k] ?? ""])) });
  if (!p.success) {
    const errors: Record<string, string> = {};
    for (const i of p.error.issues) errors[String(i.path[0])] ??= i.message;
    return { errors, error: "Check the highlighted fields." };
  }
  const { error } = await rpc("handoff_settings_save", { p: handoffPayload(p.data), p_reason: p.data.reason });
  if (error) return { error: dbMessage(error, "Could not save the hand-off rules. Try again.") };
  refresh();
  return { ok: Date.now() };
}

const Reason = z.string().trim().min(3).max(300);

/** Pass not-passed (junk / mismatch) leads to a CRM through the normal rules. */
export async function passToCrm(leadIds: number[], reason: string): Promise<{ ok: true; passed: number; failed: number } | { ok: false; error: string }> {
  await assertAdmin();
  const p = z.object({ ids: z.array(Id).min(1).max(500), reason: Reason }).safeParse({ ids: leadIds, reason });
  if (!p.success) return { ok: false, error: "Choose leads and give a reason (3 characters or more)." };
  const { data, error } = await rpc("pass_to_crm", { p_lead_ids: p.data.ids, p_reason: p.data.reason });
  if (error) return { ok: false, error: dbMessage(error, "Could not pass the leads. Try again.") };
  refresh();
  const r = data as { passed: number; results: { ok: boolean }[] };
  return { ok: true, passed: r.passed, failed: r.results.filter((x) => !x.ok).length };
}

/** Send a lead held by B2C into partner routing (the only way a B2C lead reaches a partner). */
export async function routeToPartners(leadId: number, reason: string): Promise<{ ok: true; decision: Decision } | { ok: false; error: string }> {
  await assertAdmin();
  const p = z.object({ id: Id, reason: Reason }).safeParse({ id: leadId, reason });
  if (!p.success) return { ok: false, error: "A reason is required." };
  const { data, error } = await rpc("route_to_partners", { p_lead_id: p.data.id, p_reason: p.data.reason });
  if (error) return { ok: false, error: dbMessage(error, "Could not send the lead to partners. Try again.") };
  refresh();
  return { ok: true, decision: data as Decision };
}

/** The partner says the lead is lost: it goes to B2C nurture (until partner sync reports it automatically). */
export async function markPartnerLost(allocationId: number, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ id: Id, reason: Reason }).safeParse({ id: allocationId, reason });
  if (!p.success) return "Say what the partner reported.";
  const { error } = await rpc("allocation_partner_lost", { p_allocation_id: p.data.id, p_detail: { lost_reason: p.data.reason, reported_by: "admin" } });
  if (error) return dbMessage(error, "Could not record the loss. Try again.");
  refresh();
}

export async function resolveFlag(id: number, resolution: "keep" | "close", note: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ id: Id, resolution: z.enum(["keep", "close"]), note: z.string().trim().max(300) }).safeParse({ id, resolution, note });
  if (!p.success) return "Invalid request.";
  const { error } = await rpc("review_flag_resolve", { p_id: p.data.id, p_resolution: p.data.resolution, p_note: p.data.note });
  if (error) return dbMessage(error, "Could not resolve the flag. Try again.");
  refresh();
}

// ---------- performance routing (M24): segments, partner weights, policy ----------

function fieldErrors(issues: { path: PropertyKey[]; message: string }[]) {
  const errors: Record<string, string> = {};
  for (const i of issues) errors[String(i.path[0])] ??= i.message;
  return errors;
}
const formRaw = (form: FormData, keys: string[]) => Object.fromEntries(keys.map((k) => [k, form.get(k) ?? undefined]));

export async function saveSegmentPolicy(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const p = SegmentPolicySchema.safeParse(formRaw(form, ["segment", "pin", "pin_until", "exploration_share", "share_cap", "killed", "reason"]));
  if (!p.success) return { errors: fieldErrors(p.error.issues), error: "Check the highlighted fields." };
  const { error } = await rpc("segment_policy_save", { p_segment: p.data.segment, p: segmentPolicyPayload(p.data), p_reason: p.data.reason });
  if (error) return { error: dbMessage(error, "Could not save the segment. Try again.") };
  refresh();
  return { ok: Date.now() };
}

export async function savePartnerWeight(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const p = PartnerWeightSchema.safeParse(formRaw(form, ["partner_id", "weight", "days", "reason"]));
  if (!p.success) return { errors: fieldErrors(p.error.issues), error: "Check the highlighted fields." };
  const until = p.data.weight === null ? null : new Date(Date.now() + p.data.days * 86_400_000).toISOString();
  const { error } = await rpc("partner_weight_save", { p_partner_id: p.data.partner_id, p_weight: p.data.weight, p_until: until, p_reason: p.data.reason });
  if (error) return { error: dbMessage(error, "Could not save the weight. Try again.") };
  refresh();
  return { ok: Date.now() };
}

export async function saveEnginePolicy(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const p = PolicySchema.safeParse(formRaw(form, ["holdout_share", "mc_draws", "leading_weight", "leading_min_days", "reason"]));
  if (!p.success) return { errors: fieldErrors(p.error.issues), error: "Check the highlighted fields." };
  const { reason, ...policy } = p.data;
  const { error } = await rpc("engine_policy_save", { p: policy, p_reason: reason });
  if (error) return { error: dbMessage(error, "Could not save the policy. Try again.") };
  refresh();
  return { ok: Date.now() };
}

export async function refreshStats(): Promise<string | void> {
  await assertAdmin();
  const { error } = await rpc("stats_refresh_now", {});
  if (error) return dbMessage(error, "Could not refresh the statistics. Try again.");
  refresh();
}

export async function replayDecision(id: number): Promise<{ ok: true; replay: DecisionReplay } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return { ok: false, error: "Invalid decision." };
  const { data, error } = await rpc("decision_replay", { p_decision_id: id });
  if (error) return { ok: false, error: dbMessage(error, "Could not replay the decision. Try again.") };
  return { ok: true, replay: data as DecisionReplay };
}
