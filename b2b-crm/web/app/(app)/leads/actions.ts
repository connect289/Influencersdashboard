"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { DELETE_REASONS, parseLeadQuery, type LeadPage } from "@/lib/leads";
import { EDIT_FIELDS, parseEdit } from "@/lib/lead-edit";
import { listLeads } from "@/lib/leads-data";
import type { ConsentRequestResult, Decision, Interest } from "@/lib/routing";
import { createClient } from "@/lib/supabase/server";

const Ids = z.array(z.number().int().positive()).min(1).max(500);
type Blocked = { id: number; why: string }[];

/** Next page for the table's "Load more". The search string is parsed exactly like the page's own URL. */
export async function loadMoreLeads(search: string, after: { v: string; id: string }): Promise<LeadPage> {
  await assertAdmin();
  const cursor = z.object({ v: z.string().max(100), id: z.string().regex(/^\d{1,18}$/) }).parse(after);
  const query = parseLeadQuery(Object.fromEntries(new URLSearchParams(search.slice(0, 2000))));
  return listLeads(query, cursor);
}

/** Moves leads to the recycle bin. Leads with an enrollment, or with a partner for the wrong reason, come back blocked. */
export async function deleteLeads(ids: number[], reason: string): Promise<{ ok: true; deleted: number[]; blocked: Blocked } | { ok: false; error: string }> {
  await assertAdmin();
  const parsed = z.object({ ids: Ids, reason: z.enum(DELETE_REASONS) }).safeParse({ ids, reason });
  if (!parsed.success) return { ok: false, error: "Choose up to 500 leads and a reason." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("leads_soft_delete", { p_ids: parsed.data.ids, p_reason: parsed.data.reason });
  if (error) return { ok: false, error: "Could not delete. Try again." };
  revalidatePath("/leads");
  const r = data as { deleted: number[]; blocked: Blocked };
  return { ok: true, deleted: r.deleted ?? [], blocked: r.blocked ?? [] };
}

/** Brings leads back from the recycle bin, unless the student has since come back as a newer lead. */
export async function restoreLeads(ids: number[]): Promise<{ ok: true; restored: number[]; blocked: Blocked } | { ok: false; error: string }> {
  await assertAdmin();
  const parsed = Ids.safeParse(ids);
  if (!parsed.success) return { ok: false, error: "Choose up to 500 leads." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("leads_restore", { p_ids: parsed.data });
  if (error) return { ok: false, error: "Could not restore. Try again." };
  revalidatePath("/leads");
  const r = data as { restored: number[]; blocked: Blocked };
  return { ok: true, restored: r.restored ?? [], blocked: r.blocked ?? [] };
}

export type EditState = { errors?: Record<string, string>; error?: string; ok?: number; changed?: number } | undefined;

/**
 * Corrects a lead through b2b.lead_edit (which writes via lead_intake and keeps the field history). The form carries
 * the values it was opened with, so only fields the Admin changed are sent; the database compares again anyway.
 */
export async function editLead(id: number, _prev: EditState, form: FormData): Promise<EditState> {
  await assertAdmin();
  if (!z.number().int().positive().safeParse(id).success) return { error: "Invalid lead." };
  let original: Record<string, string | null> = {};
  try { original = z.record(z.string(), z.string().nullable()).parse(JSON.parse(String(form.get("_original") ?? "{}"))); } catch { return { error: "Reload the lead and try again." }; }
  const values = Object.fromEntries(EDIT_FIELDS.filter((f) => form.has(f)).map((f) => [f, String(form.get(f) ?? "")]));
  const parsed = parseEdit(values, original);
  if (!parsed.ok) return { errors: parsed.errors, error: "Check the highlighted fields." };
  if (Object.keys(parsed.changes).length === 0) return { error: "Nothing changed." };
  const reason = z.string().trim().min(3).max(300).safeParse(form.get("reason") ?? "");
  if (!reason.success) return { errors: { reason: "Say why, for the audit log" }, error: "Check the highlighted fields." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("lead_edit", { p_lead_id: id, p_changes: parsed.changes, p_reason: reason.data });
  if (error) {
    const safe = error.code === "22023" || error.code === "P0002";
    return { error: safe ? error.message.charAt(0).toUpperCase() + error.message.slice(1) + "." : "Could not save. Try again." };
  }
  revalidatePath("/leads");
  return { ok: Date.now(), changed: ((data as { changed: unknown[] }).changed ?? []).length };
}

// ---------- Addendum 3: routing actions from the lead drawer and the bulk bar ----------
// Every function below calls the b2b RPC by the exact name and parameter names of CONTRACT.md §13 and the owning migration:
// reroute_lead / reroute_many / route_to_partners_many / route_test_lead (m31l), reenquiry_ack (m31k), consent_request_admin /
// consent_record_admin (m31e), lead_interests_save (m31h). Messages raised for the Admin (errcode 22023, P0002) are passed
// through; anything else gets a generic sentence.

const Id = z.number().int().positive();
const Reason = z.string().trim().min(3).max(300);
const Lane = z.enum(["sales", "nurture"]);
const RerouteTo = z.enum(["b2c", "partners"]);

type Fail = { ok: false; error: string };

/** The function's own message for the Admin (22023 / P0002), its routing prefix ('partner_barred:', 'no_consent:', 'not_held:')
 *  dropped and the sentence capitalised; otherwise the fallback. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code !== "22023" && error.code !== "P0002") return fallback;
  const m = error.message.replace(/^(partner_barred|no_consent|not_held):\s*/, "").trim();
  if (!m) return fallback;
  return m.charAt(0).toUpperCase() + m.slice(1) + (/[.!?]$/.test(m) ? "" : ".");
}

async function rpc(fn: string, args: Record<string, unknown>) {
  const supabase = await createClient();
  return supabase.schema("b2b").rpc(fn, args);
}

const refresh = () => { revalidatePath("/leads"); revalidatePath("/routing"); revalidatePath("/", "layout"); };

/** b2b.reroute_lead's result (m31l): `route` is route_decide's result for a re-route to partners, null for B2C. */
export type RerouteResult = {
  rerouted: boolean; to: "b2c" | "partners"; recalled_allocation_id: number | null; reference: string | null; decision_id: number | null;
  allocation_id: number | null; destination: string | null; reason: string | null; partner_id: number | null; route: Decision | null;
};
/** b2b.reroute_many's counts (m31l), rendered by W5's rerouteToast. */
export type RerouteManyCounts = {
  done: number; skipped_no_partner_allocation: number; skipped_contacted_no_breach: number; skipped_lost_in_grace: number; skipped_barred: number; failed: number;
  results: { lead_id: number; ok: boolean; skipped: string | null; error: string | null; reference: string | null; destination?: string | null; partner_id?: number | null }[];
};
/** b2b.route_to_partners_many's counts (m31l), rendered by W5's bulkRouteToast. */
export type RouteManyCounts = {
  sent: number; to_partner: number; back_to_b2c: number; consent_requested: number; skipped_barred: number; skipped_no_consent: number; skipped_not_held: number; failed: number;
  results: { lead_id: number; ok: boolean; destination: string | null; reason: string | null; skipped: string | null; error: string | null; reference: string | null; partner_id?: number | null }[];
};
/** b2b.consent_answer's result (m31e), returned by consent_record_admin. */
export type ConsentAnswerResult = {
  recorded: boolean; duplicate: boolean; request_id: number | null; answer: "yes" | "no"; ledger_id: number | null; state: "given" | "refused" | "withdrawn" | null;
  effect: "routed" | "requalified" | "recorded" | "none" | "route_error"; route: Record<string, unknown> | null; why: string | null;
};
/** b2b.route_test_lead's result (m31l): route_decide's shape for the sandbox (destination 'none' with reason
 *  no_sandbox_partner when no partner has a test endpoint), or the b2c_test hand-off. */
export type TestRouteResult = Partial<Decision> & { destination: string; reason: string | null; outcome?: string | null; committed?: boolean; reference?: string; allocation_id?: number | null; is_test?: boolean };

/** One secondary interest for b2b.lead_interests_save (m31h: course text, optional specialization, level, mode and university). */
export type InterestInput = { course: string; specialization?: string | null; level?: string | null; mode?: string | null; university?: string | null };
const InterestItem = z.object({
  course: z.string().trim().min(2, "Give the course").max(120),
  specialization: z.string().trim().max(120).nullish().transform((v) => v || null),
  level: z.enum(["UG", "PG", "DIPLOMA", "CERTIFICATE"]).nullish().transform((v) => v ?? null),
  mode: z.enum(["Online", "ODL", "Regular"]).nullish().transform((v) => v ?? null),
  university: z.string().trim().max(160).nullish().transform((v) => v || null),
});

/** PART 6.2 / D20: recall the open partner allocation and hand the lead to B2C (lane) or the next-best partner. Refused with
 *  reroute_check's why (contact without a breach; 'lost, in grace: …'), or 'partner_barred: …' for partners. */
export async function rerouteLead(leadId: number, to: "b2c" | "partners", reason: string, lane?: "sales" | "nurture"): Promise<({ ok: true } & RerouteResult) | Fail> {
  await assertAdmin();
  const p = z.object({ leadId: Id, to: RerouteTo, reason: Reason, lane: Lane.optional() }).safeParse({ leadId, to, reason, lane });
  if (!p.success) return { ok: false, error: "Choose B2C or partners and give a reason (3 to 300 characters)." };
  const { data, error } = await rpc("reroute_lead", { p_lead_id: p.data.leadId, p_to: p.data.to, p_reason: p.data.reason, p_b2c_lane: p.data.lane ?? "sales" });
  if (error) return { ok: false, error: dbMessage(error, "Could not re-route the lead. Try again.") };
  refresh();
  return { ok: true, ...(data as RerouteResult) };
}

/** Bulk re-route (m31l reroute_many): each lead is done or skipped (no partner allocation, contacted without a breach, lost in
 *  grace, partner-barred) with counts for the toast. */
export async function rerouteMany(ids: number[], to: "b2c" | "partners", reason: string, lane?: "sales" | "nurture"): Promise<{ ok: true; counts: RerouteManyCounts } | Fail> {
  await assertAdmin();
  const p = z.object({ ids: Ids, to: RerouteTo, reason: Reason, lane: Lane.optional() }).safeParse({ ids, to, reason, lane });
  if (!p.success) return { ok: false, error: "Choose up to 500 leads, B2C or partners, and give a reason (3 to 300 characters)." };
  const { data, error } = await rpc("reroute_many", { p_lead_ids: p.data.ids, p_to: p.data.to, p_reason: p.data.reason, p_b2c_lane: p.data.lane ?? "sales" });
  if (error) return { ok: false, error: dbMessage(error, "Could not re-route the leads. Try again.") };
  refresh();
  return { ok: true, counts: data as RerouteManyCounts };
}

/** Bulk manual route-to-partners (m31l route_to_partners_many): barred leads, leads without consent and leads not held by B2C
 *  are skipped with a count (PART 6.3). */
export async function routeToPartnersMany(ids: number[], reason: string): Promise<{ ok: true; counts: RouteManyCounts } | Fail> {
  await assertAdmin();
  const p = z.object({ ids: Ids, reason: Reason }).safeParse({ ids, reason });
  if (!p.success) return { ok: false, error: "Choose up to 500 leads and give a reason (3 to 300 characters)." };
  const { data, error } = await rpc("route_to_partners_many", { p_lead_ids: p.data.ids, p_reason: p.data.reason });
  if (error) return { ok: false, error: dbMessage(error, "Could not send the leads to partners. Try again.") };
  refresh();
  return { ok: true, counts: data as RouteManyCounts };
}

/** D18: the Admin acknowledges re-enquiries recorded on a held lead (m31k reenquiry_ack); the note is optional. */
export async function reenquiryAck(ids: number[], note?: string | null): Promise<{ ok: true; count: number } | Fail> {
  await assertAdmin();
  const p = z.object({ ids: Ids, note: z.string().trim().max(300).nullish().transform((v) => v || null) }).safeParse({ ids, note });
  if (!p.success) return { ok: false, error: "Choose up to 500 re-enquiries; the note is at most 300 characters." };
  const { data, error } = await rpc("reenquiry_ack", { p_ids: p.data.ids, p_note: p.data.note });
  if (error) return { ok: false, error: dbMessage(error, "Could not acknowledge. Try again.") };
  refresh();
  return { ok: true, count: Number(data ?? 0) };
}

/** PART 7.2: ask the student for partner-sharing consent now (m31e consent_request_admin, context 'admin'): from Witty's
 *  number when the lead came through Witty and Witty W2 is live, otherwise from the B2C number; queued over the hourly budget. */
export async function consentRequest(leadId: number, reason: string): Promise<({ ok: true } & ConsentRequestResult) | Fail> {
  await assertAdmin();
  const p = z.object({ leadId: Id, reason: Reason }).safeParse({ leadId, reason });
  if (!p.success) return { ok: false, error: "Give a reason (3 to 300 characters)." };
  const { data, error } = await rpc("consent_request_admin", { p_lead_id: p.data.leadId, p_reason: p.data.reason });
  if (error) return { ok: false, error: dbMessage(error, "Could not send the consent request. Try again.") };
  refresh();
  return { ok: true, ...(data as ConsentRequestResult) };
}

/** D9: record the student's answer given to the Admin (m31e consent_record_admin). A refusal is always allowed; a YES needs
 *  engine.consent_admin_yes and a written evidence reference. The note is 10 characters or more. */
export async function consentRecord(leadId: number, answer: "yes" | "no", note: string, evidenceRef?: string | null): Promise<({ ok: true } & ConsentAnswerResult) | Fail> {
  await assertAdmin();
  const p = z.object({
    leadId: Id, answer: z.enum(["yes", "no"]), note: z.string().trim().min(10).max(300),
    evidenceRef: z.string().trim().max(300).nullish().transform((v) => v || null),
  }).safeParse({ leadId, answer, note, evidenceRef });
  if (!p.success) return { ok: false, error: p.error.issues.some((i) => i.path[0] === "note") ? "Write a note of 10 to 300 characters." : "Check the answer and the evidence reference." };
  if (p.data.answer === "yes" && !p.data.evidenceRef) return { ok: false, error: "A written evidence reference is required for a YES." };
  const { data, error } = await rpc("consent_record_admin", { p_lead_id: p.data.leadId, p_answer: p.data.answer, p_note: p.data.note, p_evidence_ref: p.data.evidenceRef });
  if (error) return { ok: false, error: dbMessage(error, "Could not record the answer. Try again.") };
  refresh();
  return { ok: true, ...(data as ConsentAnswerResult) };
}

/** D30: replace the lead's secondary interests (m31h lead_interests_save; at most 9, the primary interest stays derived from
 *  the lead). Returns b2b.lead_interest_list (the primary first). */
export async function interestsSave(leadId: number, list: InterestInput[], reason: string): Promise<{ ok: true; interests: Interest[] } | Fail> {
  await assertAdmin();
  const p = z.object({ leadId: Id, list: z.array(InterestItem).max(9), reason: Reason }).safeParse({ leadId, list, reason });
  if (!p.success) {
    const course = p.error.issues.find((i) => i.path[1] === "course");
    return { ok: false, error: course ? `Interest ${Number(course.path[0]) + 1}: give the course (2 characters or more).` : "Up to 9 other interests and a reason (3 to 300 characters)." };
  }
  const { data, error } = await rpc("lead_interests_save", { p_lead_id: p.data.leadId, p_list: p.data.list, p_reason: p.data.reason });
  if (error) return { ok: false, error: dbMessage(error, "Could not save the interests. Try again.") };
  refresh();
  return { ok: true, interests: (data as Interest[] | null) ?? [] };
}

/** R1 / D21: route a test lead on purpose (m31l route_test_lead): to a partner sandbox (is_test allocation, test endpoint only;
 *  destination 'none' with reason no_sandbox_partner when no partner has one) or as a test hand-off to B2C. */
export async function routeTestLead(leadId: number, target: "partner_sandbox" | "b2c_test", reason: string): Promise<({ ok: true } & TestRouteResult) | Fail> {
  await assertAdmin();
  const p = z.object({ leadId: Id, target: z.enum(["partner_sandbox", "b2c_test"]), reason: Reason }).safeParse({ leadId, target, reason });
  if (!p.success) return { ok: false, error: "Choose the sandbox or the B2C test hand-off and give a reason (3 to 300 characters)." };
  const { data, error } = await rpc("route_test_lead", { p_lead_id: p.data.leadId, p_target: p.data.target, p_reason: p.data.reason });
  if (error) return { ok: false, error: dbMessage(error, "Could not route the test lead. Try again.") };
  refresh();
  return { ok: true, ...(data as TestRouteResult) };
}
