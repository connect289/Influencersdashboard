"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import {
  ENGINE_FIELDS, EngineSchema, enginePayload, GOLIVE_LABEL, HANDOFF_FIELDS, HandoffSchema, handoffPayload, parseRuleForm, RateSchema, type Decision,
} from "@/lib/routing";
import { createClient } from "@/lib/supabase/server";
import { settingsHistory, type DecisionReplay, type HistoryKey, type SettingsHistoryRow } from "@/lib/routing-data";
import { PolicySchema, reqNum } from "@/lib/segments";

/** Addendum 3 routing actions. Every action re-checks the Admin on the server (assertAdmin) and calls the b2b functions by
 *  the names and parameter names of CONTRACT.md §13: engine_settings_save / engine_policy_save / lost_delays_save /
 *  settings_history (m31l), handoff_settings_save (m31g), routing_golive_ack / set_live_switch (m31e), route_simulate /
 *  route_now / route_to_partners (route_decide, m31f), pass_to_crm, allocation_partner_lost (m31i), decision_replay,
 *  simulate_change (m31m). Messages the functions raise for the Admin (errcode 22023, P0002) are shown as they are. */

const Id = z.number().int().positive();
const Reason = z.string().trim().min(3).max(300);

/** Messages raised by the b2b routing functions for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}

/** The 22023 message as the function raised it (prefixes such as 'partner_barred:' kept for the caller), else the fallback. */
function dbMessageRaw(error: { code?: string; message: string }, fallback: string): string {
  return error.code === "22023" || error.code === "P0002" ? error.message : fallback;
}

async function rpc(fn: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  return supabase.schema("b2b").rpc(fn, args);
}

const refresh = () => { revalidatePath("/routing"); revalidatePath("/leads"); revalidatePath("/", "layout"); };

export type FormState = { errors?: Record<string, string>; error?: string; ok?: number } | undefined;

function fieldErrors(issues: { path: PropertyKey[]; message: string }[]) {
  const errors: Record<string, string> = {};
  for (const i of issues) errors[String(i.path[0])] ??= i.message;
  return errors;
}

/** FormData → a flat record of strings for zod: a missing field is "" (a blank), never undefined, so reqNum and the list
 *  fields report their own message and an unticked checkbox reads as off. */
const formRaw = (form: FormData, keys: readonly string[]) =>
  Object.fromEntries(keys.map((k) => { const v = form.get(k); return [k, typeof v === "string" ? v : ""]; }));

// ---------- decisions: preview, route now, the switch ----------

/** b2b.route_simulate: route_decide(id, false, null, 'auto'). The Decision's destination may be 'none', 'not_passed',
 *  'consent_request', 'consent_requested' or 'consent_pending' (CONTRACT 1.3); a preview writes nothing. */
export async function simulateLead(leadId: number): Promise<{ ok: true; decision: Decision } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(leadId).success) return { ok: false, error: "Enter a lead ID." };
  const { data, error } = await rpc("route_simulate", { p_lead_id: leadId });
  if (error) return { ok: false, error: dbMessage(error, "The simulation failed. Try again.") };
  return { ok: true, decision: data as Decision };
}

/** b2b.route_now: route_decide(id, true, note, 'auto'). 22023 when the lead is already routed or a test lead. */
export async function routeLeadNow(leadId: number, note: string): Promise<{ ok: true; decision: Decision } | { ok: false; error: string }> {
  await assertAdmin();
  const p = z.object({ leadId: Id, note: Reason }).safeParse({ leadId, note });
  if (!p.success) return { ok: false, error: "Add a short note for the audit log (3 characters or more)." };
  const { data, error } = await rpc("route_now", { p_lead_id: p.data.leadId, p_note: p.data.note });
  if (error) return { ok: false, error: dbMessage(error, "Routing failed. Try again.") };
  refresh();
  return { ok: true, decision: data as Decision };
}

/** The go-live gate's keys in words inside set_live_switch's 22023 text ('routing cannot go live: <key>: <why>; …'). */
function goliveText(message: string): string {
  let out = message;
  for (const [key, label] of Object.entries(GOLIVE_LABEL)) out = out.split(`${key}:`).join(`${label}:`);
  return out;
}

/** b2b.set_live_switch('routing', …). Turning routing on is refused (22023) while a blocking go-live item fails: the returned
 *  string lists those items (m31e). */
export async function setRoutingLive(live: boolean, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ live: z.boolean(), reason: Reason }).safeParse({ live, reason });
  if (!p.success) return "A reason is required (3 characters or more).";
  const { error } = await rpc("set_live_switch", { p_scope: "routing", p_live: p.data.live, p_reason: p.data.reason });
  if (error) return error.code === "22023" ? goliveText(dbMessage(error, "")) : dbMessage(error, "Could not change the switch. Try again.");
  refresh();
}

/** b2b.routing_golive_ack: acknowledges one of the two Witty go-live items with a reason of 10 characters or more. */
export async function ackGolive(key: string, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ key: z.string().regex(/^[a-z0-9_]{1,60}$/), reason: z.string().trim().min(10).max(300) }).safeParse({ key, reason });
  if (!p.success) return p.error.issues.some((i) => i.path[0] === "reason") ? "Give a reason of at least 10 characters." : "Invalid checklist item.";
  const { error } = await rpc("routing_golive_ack", { p_key: p.data.key, p_reason: p.data.reason });
  if (error) return dbMessage(error, "Could not record the acknowledgement. Try again.");
  refresh();
}

// ---------- rules and rates (unchanged) ----------

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
  if (!p.success) return { errors: fieldErrors(p.error.issues), error: "Check the highlighted fields." };
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

// ---------- engine settings (Addendum 3, D24: only the editable keys; the rulebook numbers are refused by the save) ----------

/** b2b.engine_settings_save(p, p_reason): a partial update of exactly the keys EngineSchema carries (enginePayload). The
 *  function refuses anything else with 22023 'fixed by Addendum 3: <key>' / 'retired by Addendum 3: <key>' / 'unknown engine
 *  setting: <key>', and those messages are shown as they are. */
export async function saveEngineSettings(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const p = EngineSchema.safeParse(formRaw(form, ENGINE_FIELDS));
  if (!p.success) return { errors: fieldErrors(p.error.issues), error: "Check the highlighted fields." };
  const { error } = await rpc("engine_settings_save", { p: enginePayload(p.data), p_reason: p.data.reason });
  if (error) return { error: dbMessage(error, "Could not save the settings. Try again.") };
  refresh();
  return { ok: Date.now() };
}

/** b2b.engine_policy_save(p, p_reason): only holdout_share (0–0.5) is editable since Addendum 3 (C63). */
export async function saveEnginePolicy(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const p = PolicySchema.safeParse(formRaw(form, ["holdout_share", "reason"]));
  if (!p.success) return { errors: fieldErrors(p.error.issues), error: "Check the highlighted fields." };
  const { error } = await rpc("engine_policy_save", { p: { holdout_share: p.data.holdout_share }, p_reason: p.data.reason });
  if (error) return { error: dbMessage(error, "Could not save the policy. Try again.") };
  refresh();
  return { ok: Date.now() };
}

/** b2b.settings_history(p_key, p_limit) for the client-side History cards (C62): one row per version, newest first, with the
 *  keys that changed against the version before. */
export async function loadSettingsHistory(key: HistoryKey, limit = 30): Promise<{ ok: true; rows: SettingsHistoryRow[] } | { ok: false; error: string }> {
  await assertAdmin();
  const p = z.object({
    key: z.enum(["engine", "engine_policy", "ml", "ai", "attribution", "lost_nurture_delays", "golive_acks"]),
    limit: z.number().int().min(1).max(200),
  }).safeParse({ key, limit });
  if (!p.success) return { ok: false, error: "Unknown setting." };
  try {
    return { ok: true, rows: (await settingsHistory(p.data.key, p.data.limit)) ?? [] };
  } catch {
    return { ok: false, error: "The version history is not available (settings_history is not applied yet)." };
  }
}

// ---------- hand-off rules (R5, R6) and the lost delays (PART 6.1) ----------

/** b2b.handoff_settings_save(p, p_reason): B2C-created sources, blocked phones, the junk CAPI signal and the spam rules
 *  (handoffPayload). The paid rule is gone: paid is an attribution label (D38); the function refuses paid_rule with 22023. */
export async function saveHandoffSettings(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const p = HandoffSchema.safeParse(formRaw(form, HANDOFF_FIELDS));
  if (!p.success) return { errors: fieldErrors(p.error.issues), error: "Check the highlighted fields." };
  const { error } = await rpc("handoff_settings_save", { p: handoffPayload(p.data), p_reason: p.data.reason });
  if (error) return { error: dbMessage(error, "Could not save the hand-off rules. Try again.") };
  refresh();
  return { ok: Date.now() };
}

const DelayDays = reqNum("3 to 90 days").pipe(z.number().int("A whole number of days").min(3, "3 to 90 days").max(90, "3 to 90 days"));

/** b2b.lost_delays_save(p, p_reason): the whole `lost_nurture_delays` document {default, reasons {lost reason: days}}, each
 *  3–90 days (D36). Form fields: default, lost_reason[] + days[] (paired by position), reason. Row errors are keyed row_<n>. */
export async function saveLostDelays(_prev: FormState, form: FormData): Promise<FormState> {
  await assertAdmin();
  const errors: Record<string, string> = {};
  const def = DelayDays.safeParse(typeof form.get("default") === "string" ? form.get("default") : "");
  if (!def.success) errors.default = def.error.issues[0]?.message ?? "3 to 90 days";
  const audit = Reason.safeParse(typeof form.get("reason") === "string" ? form.get("reason") : "");
  if (!audit.success) errors.reason = "Say why you are changing the delays (3 to 300 characters)";

  const keys = form.getAll("lost_reason").map((v) => (typeof v === "string" ? v.trim() : ""));
  const days = form.getAll("days").map((v) => (typeof v === "string" ? v.trim() : ""));
  const reasons: Record<string, number> = {};
  const seen = new Set<string>();
  const n = Math.max(keys.length, days.length);
  for (let i = 0; i < n; i++) {
    const k = keys[i] ?? "", d = days[i] ?? "";
    if (!k && !d) continue; // an empty row
    if (!k) { errors[`row_${i}`] = "Name the lost reason, as the partner reports it"; continue; }
    if (k.length > 60) { errors[`row_${i}`] = "A lost reason is at most 60 characters"; continue; }
    const dup = k.toLowerCase();
    if (seen.has(dup)) { errors[`row_${i}`] = "This lost reason is already in the list"; continue; }
    const v = DelayDays.safeParse(d);
    if (!v.success) { errors[`row_${i}`] = v.error.issues[0]?.message ?? "3 to 90 days"; continue; }
    seen.add(dup);
    reasons[k] = v.data;
  }
  if (Object.keys(reasons).length > 50) errors.reasons = "At most 50 lost reasons";
  if (Object.keys(errors).length) return { errors, error: "Check the highlighted fields." };

  const { error } = await rpc("lost_delays_save", { p: { default: def.data, reasons }, p_reason: audit.data });
  if (error) return { error: dbMessage(error, "Could not save the delays. Try again.") };
  refresh();
  return { ok: Date.now() };
}

// ---------- rescue, manual routes, the review queue ----------

/** b2b.pass_to_crm: not-passed (junk / mismatch / spam) leads are judged on their details (not_passed.override) and decided
 *  through the normal rules (route_decide, p_how 'pass'). */
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

/** b2b.route_to_partners (route_to_partners_core, m31f): a lead held by B2C goes through partner routing by hand. Refusals
 *  come back as the function's 22023 text with its prefix kept: 'partner_barred: …', 'no_consent: …', 'not_held: …',
 *  'test leads use the sandbox', 'a reason is required'. The Decision's destination is 'partner', or 'in_house' with reason
 *  manual_route_failed when no partner could take it. */
export async function routeToPartners(leadId: number, reason: string): Promise<{ ok: true; decision: Decision } | { ok: false; error: string }> {
  await assertAdmin();
  const p = z.object({ id: Id, reason: Reason }).safeParse({ id: leadId, reason });
  if (!p.success) return { ok: false, error: "A reason is required (3 characters or more)." };
  const { data, error } = await rpc("route_to_partners", { p_lead_id: p.data.id, p_reason: p.data.reason });
  if (error) return { ok: false, error: dbMessageRaw(error, "Could not send the lead to partners. Try again.") };
  refresh();
  return { ok: true, decision: data as Decision };
}

/** b2b.allocation_partner_lost (m31i): the partner reports the lead lost. The lead stays with the partner for the 7-day grace
 *  (status 'grace', grace_until); activity in the grace revives it, otherwise it moves to B2C nurture, partner-barred.
 *  22023 when the allocation is not pushed or accepted. */
export async function markPartnerLost(allocationId: number, reason: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ id: Id, reason: Reason }).safeParse({ id: allocationId, reason });
  if (!p.success) return "Say what the partner reported (3 characters or more).";
  const { data, error } = await rpc("allocation_partner_lost", { p_allocation_id: p.data.id, p_detail: { lost_reason: p.data.reason, reported_by: "admin" } });
  if (error) return dbMessage(error, "Could not record the loss. Try again.");
  const r = data as { status?: "grace" | "ignored"; grace_until?: string | null; reference?: string | null; why?: string | null } | null;
  if (r?.status === "ignored") return r.why ? r.why.charAt(0).toUpperCase() + r.why.slice(1) + "." : "The loss was not recorded.";
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

// ---------- statistics, replay, what-if ----------

export async function refreshStats(): Promise<string | void> {
  await assertAdmin();
  const { error } = await rpc("stats_refresh_now", {});
  if (error) return dbMessage(error, "Could not refresh the statistics. Try again.");
  refresh();
}

/** b2b.decision_replay (m31l, C128): an A3 decision re-sorted from its stored candidates with the lane recomputed from the
 *  seed (reproduced, lane_applied, draw, share); legacy decisions keep the M24 branches. */
export async function replayDecision(id: number): Promise<{ ok: true; replay: DecisionReplay } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(id).success) return { ok: false, error: "Invalid decision." };
  const { data, error } = await rpc("decision_replay", { p_decision_id: id });
  if (error) return { ok: false, error: dbMessage(error, "Could not replay the decision. Try again.") };
  return { ok: true, replay: data as DecisionReplay };
}

/** b2b.simulate_change (m31m, C113): replays a proposed change ({lever, value}) on logged, matured decisions. The lever and
 *  value are passed through unchanged; the Admin ranges are validated by the function (22023 text shown as it is). */
export async function simulateChange(change: Record<string, unknown>, days: number): Promise<{ ok: true; result: Record<string, unknown> } | { ok: false; error: string }> {
  await assertAdmin();
  if (!z.number().int().min(7).max(365).safeParse(days).success) return { ok: false, error: "7 to 365 days." };
  const { data, error } = await rpc("simulate_change", { p_change: change, p_days: days });
  if (error) return { ok: false, error: dbMessage(error, "The simulation failed. Try again.") };
  return { ok: true, result: data as Record<string, unknown> };
}
