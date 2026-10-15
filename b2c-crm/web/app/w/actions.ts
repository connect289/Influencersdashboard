"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser, isAllowedEmail } from "@/lib/auth";
import { act, rpc, type ActionResult } from "@/lib/data";
import { adminClient } from "@/lib/supabase/admin";

const ADMIN = ["admin"] as const;
const ids = z.array(z.coerce.number().int().positive()).min(1).max(500, "At most 500 leads at a time for this action.");
const manyIds = z.array(z.coerce.number().int().positive()).min(1, "Tick at least one lead.").max(20000, "At most 20,000 leads at a time.");
const uuid = z.string().uuid();
const id = z.coerce.number().int().positive();
type Refusals = { done: number; refused: { lead_id: number; why: string }[] };

function done(path = "/w") {
  revalidatePath(path, "layout");
}

// ---------- leads (bulk) ----------

export async function reassign(leads: number[], userId: string | null, reason: string): Promise<ActionResult<number>> {
  await assertUser([...ADMIN, "sales_head"]);
  const r = await act(() => rpc<number>("reassign", { p_leads: ids.parse(leads), p_user: userId ? uuid.parse(userId) : null, p_reason: reason }),
    userId ? "Reassigned." : "Sent through the allocation rules again.");
  done();
  return r;
}

export async function routeToPartners(leads: number[], reason: string): Promise<ActionResult<{ sent: number; refused: { lead_id: number; why: string }[] }>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<{ sent: number; refused: { lead_id: number; why: string }[] }>("route_to_partners", { p_leads: ids.parse(leads), p_reason: reason }));
  done();
  return r;
}

export async function deleteLeads(leads: number[], reason: string): Promise<ActionResult<{ deleted: number; kept: { lead_id: number; why: string }[] }>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<{ deleted: number; kept: { lead_id: number; why: string }[] }>("lead_delete", { p_leads: ids.parse(leads), p_reason: reason }));
  done();
  return r;
}

export async function restoreLeads(leads: number[]): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<number>("lead_restore", { p_leads: ids.parse(leads) }), "Restored.");
  done();
  return r;
}

export async function tagLeads(leads: number[], tag: string, add: boolean): Promise<ActionResult<number>> {
  await assertUser([...ADMIN, "marketing"]);
  const r = await act(() => rpc<number>("tag", { p_leads: ids.parse(leads), p_tag: tag.slice(0, 40), p_add: add }), add ? "Tagged." : "Tag removed.");
  done();
  return r;
}

/** Every id of the current view or search ("select all N in this view"), at most 20,000 (b2c.lead_list mode ids). */
export async function viewIds(query: Record<string, unknown>): Promise<ActionResult<{ total: number; ids: number[] }>> {
  await assertUser([...ADMIN, "marketing"]);
  const { filters, search, include_test, drill, deleted } = query;
  return act(() => rpc<{ total: number; ids: number[] }>("lead_list", { p: { filters: filters ?? {}, search: search ?? "", include_test: typeof include_test === "boolean" ? include_test : null, drill: drill ?? null, deleted: deleted === true, mode: "ids" } }));
}

/** Into a journey or out of one (b2c.bulk_journey: Marketing too); each lead is checked as if done alone. */
export async function bulkJourney(leads: number[], action: "add" | "remove", journey: number | null): Promise<ActionResult<Refusals>> {
  await assertUser([...ADMIN, "marketing"]);
  const r = await act(() => rpc<Refusals>("bulk_journey", { p_leads: manyIds.parse(leads), p_action: action, p_journey: action === "add" ? id.parse(journey) : null }));
  done();
  return r;
}

/** One stage, sub-stage and comment for many (b2c.bulk_stage, Admin), under the stage rules. */
export async function bulkStage(leads: number[], stage: number, sub: string | null, comment: string, nextDue: string | null): Promise<ActionResult<Refusals>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<Refusals>("bulk_stage", { p_leads: manyIds.parse(leads), p_stage: id.parse(stage), p_sub: sub || null, p_comment: comment.trim() || null, p_next_due: nextDue }));
  done();
  return r;
}

/** Bulk delete as a background job (b2c.lead_delete_request): the typed confirmation "DELETE <n>" is checked again there. */
export async function deleteRequest(leads: number[], reason: string, confirm: string): Promise<ActionResult<{ job_id: number; leads: number }>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<{ job_id: number; leads: number }>("lead_delete_request", { p_leads: manyIds.parse(leads), p_reason: reason, p_confirm: confirm }));
  done();
  return r;
}

export async function bulkJobUndo(job: number): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<number>("bulk_job_undo", { p_job: id.parse(job) }));
  done();
  return r.ok ? { ...r, notice: `${r.data ?? 0} leads restored.` } : r;
}

/** A 2-minute link to one of the person's ready exports (b2c.export_open logs the download). */
export async function exportLink(exportId: number): Promise<ActionResult<string>> {
  await assertUser([...ADMIN]);
  return act(async () => {
    const path = await rpc<string>("export_open", { p_export: id.parse(exportId) });
    const { data, error } = await adminClient().storage.from("b2c-exports").createSignedUrl(path, 120, { download: true });
    if (error || !data) throw new Error("The file could not be opened.");
    return data.signedUrl;
  });
}

/** The student's erasure request (DPDP, b2c.lead_erase): cannot be undone. */
export async function eraseLead(leadId: number, reference: string, note: string): Promise<ActionResult<{ erased: boolean; messages: number; files: number }>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<{ erased: boolean; messages: number; files: number }>("lead_erase", { p_lead: id.parse(leadId), p_reference: reference.trim().slice(0, 200), p_note: note.trim().slice(0, 300) || null }));
  done();
  return r;
}

/** The Admin's answer to a flagged lead (b2c.flag_review). */
export async function flagReview(leadId: number, action: "keep" | "junk" | "cannot_serve", note: string): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("flag_review", { p_lead: id.parse(leadId), p_action: action, p_note: note.trim() || null }),
    action === "keep" ? "Kept: marketing may continue." : "Closed and sent to the master lead table.");
  done();
  return r;
}

// ---------- to qualify (b39) ----------

export async function qualifyAssign(request: number, userId: string | null): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("qualify_assign", { p_request: id.parse(request), p_user: userId ? uuid.parse(userId) : null }), userId ? "Given to the counsellor." : "Taken back.");
  done("/w/qualify");
  return r;
}

export async function qualifyResend(request: number): Promise<ActionResult<{ whatsapp: number | null; email: number | null }>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<{ whatsapp: number | null; email: number | null }>("qualify_resend", { p_request: id.parse(request) }));
  done("/w/qualify");
  if (!r.ok) return r;
  const via = [r.data?.whatsapp && "WhatsApp", r.data?.email && "email"].filter(Boolean).join(" and ");
  return { ...r, notice: via ? `Sent again by ${via}.` : "Nothing could be sent: no open WhatsApp window or approved template, and no email." };
}

/** The counsellors who may answer the Replies inbox (b2c.replies_delegates_set). */
export async function repliesDelegatesSet(users: string[]): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("replies_delegates_set", { p_users: z.array(uuid).max(50).parse(users) }), "Saved.");
  done("/w/nurture");
  return r;
}

export async function coachingNote(leadId: number, body: string): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("add_note", { p_lead: leadId, p_body: body.slice(0, 4000), p_internal: true }), "Coaching note saved (only the Admin and the sales head see it).");
  revalidatePath(`/w/leads/${leadId}`);
  return r;
}

export async function adminEditContact(contactId: number, value: string | null, remove: boolean, leadId: number): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("admin_edit_contact", { p_contact: contactId, p_value: value, p_remove: remove }), remove ? "Removed." : "Saved.");
  revalidatePath(`/w/leads/${leadId}`);
  return r;
}

/** Logged when the Admin opens a lead's phone number or exports (spec B15). */
export async function audit(action: "phone_reveal" | "export" | "view_as_sales" | "contact_copy", leadId?: number, detail?: Record<string, unknown>): Promise<void> {
  await assertUser();
  await rpc("audit", { p_action: action, p_lead: leadId ?? null, p_detail: detail ?? {} }).catch(() => undefined);
}

// ---------- allocation ----------

const condition = z.object({
  all: z.array(z.object({ field: z.string(), op: z.string(), value: z.unknown().optional() })).optional(),
  any: z.array(z.object({ field: z.string(), op: z.string(), value: z.unknown().optional() })).optional(),
});

/** The shares a performance rule would use now (b2c.perf_preview). */
export async function perfPreview(rule: number): Promise<ActionResult<unknown>> {
  await assertUser([...ADMIN]);
  return act(() => rpc("perf_preview", { p_rule: z.coerce.number().int().positive().parse(rule) }));
}

export async function ruleSave(input: {
  id?: number | null; name: string; enabled?: boolean; condition?: z.infer<typeof condition>; logic?: string; params?: Record<string, unknown>;
  pool_id?: number | null; fallbacks?: string[]; applies_from?: string | null;
}): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  if (input.condition && !condition.safeParse(input.condition).success) return { ok: false, error: "The condition is not valid." };
  const r = await act(() => rpc<number>("rule_save", { p: input }), "Rule saved. It applies to the next lead.");
  done("/w/allocation");
  return r;
}

export async function rulesReorder(order: number[]): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("rules_reorder", { p_ids: ids.parse(order) }), "Order saved.");
  done("/w/allocation");
  return r;
}

export async function poolSave(input: { id?: number | null; name: string; description?: string | null; members: { user_id: string; weight: number }[] }): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<number>("pool_save", { p: input }), "Pool saved.");
  done("/w/allocation");
  return r;
}

export async function calendarSave(userId: string, patterns: { isodow: number; start: string; end: string }[]): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("calendar_save", { p_user: uuid.parse(userId), p_patterns: patterns }), "Working hours saved.");
  done("/w/allocation");
  return r;
}

export async function leaveAdd(userId: string, from: string, to: string, mode: "hold" | "reassign", afterHours: number | null, reason: string): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("leave_add", { p_user: uuid.parse(userId), p_from: from, p_to: to, p_mode: mode, p_after: afterHours, p_reason: reason || null }), "Leave added.");
  done("/w/allocation");
  return r;
}

export async function holidaySave(day: string, name: string): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("holiday_save", { p_day: day, p_name: name, p_kind: "company" }), "Holiday saved.");
  done("/w/allocation");
  return r;
}

export async function simulate(from: string, to: string): Promise<ActionResult<{ leads: number; unassigned: number; by_person: { user_id: string; name: string | null; actual: number; simulated: number }[] }>> {
  await assertUser([...ADMIN]);
  return act(() => rpc("simulate", { p_from: from, p_to: to }));
}

// ---------- enrolments ----------

export async function enrollmentVerify(enrollmentId: number, ok: boolean, note: string): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("enrollment_verify", { p_id: enrollmentId, p_ok: ok, p_note: note || null }), ok ? "Verified." : "Sent back to the counsellor.");
  done("/w/enrollments");
  return r;
}

/** A short-lived link to a private document, for the Admin checking an enrolment proof. */
export async function documentLink(path: string): Promise<ActionResult<string>> {
  await assertUser([...ADMIN]);
  if (!/^leads\/\d+\/[0-9a-f-]+\.(pdf|jpeg|png|webp)$/.test(path)) return { ok: false, error: "Unknown document." };
  const { data, error } = await adminClient().storage.from("b2c-documents").createSignedUrl(path, 300);
  if (error || !data) return { ok: false, error: "The document could not be opened." };
  return { ok: true, data: data.signedUrl };
}

// ---------- team ----------

const userSchema = z.object({
  email: z.email().max(254), full_name: z.string().min(2).max(120), role: z.enum(["admin", "marketing", "counsellor", "sales_head"]),
  is_active: z.boolean().default(true), phone: z.string().max(20).optional().nullable(), languages: z.array(z.string().max(30)).max(10).default([]),
  monthly_cap: z.coerce.number().int().min(0).max(5000).default(200), open_cap: z.coerce.number().int().min(0).max(5000).nullable().optional(),
  daily_cap: z.coerce.number().int().min(0).max(500).nullable().optional(), weight: z.coerce.number().int().min(1).max(10).default(1),
  takes_leads: z.boolean().default(true), on_call: z.boolean().default(false), is_test_user: z.boolean().default(false),
  skills: z.record(z.string(), z.array(z.string())).optional(), monthly_target: z.record(z.string(), z.number()).optional(),
});

/**
 * Adds or updates a person. A new @eduwit.in address gets a sign-in account (no password: they sign in with Google, or set one through "First time, or forgot your password?" on the sign-in page);
 * the person can sign in once active. Only the Admin.
 */
export async function userSave(input: z.input<typeof userSchema>): Promise<ActionResult<string>> {
  await assertUser([...ADMIN]);
  const p = userSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Check the name, email and role." };
  const email = p.data.email.toLowerCase();
  if (!isAllowedEmail(email)) return { ok: false, error: "Only @eduwit.in accounts." };
  return act(async () => {
    const admin = adminClient();
    let userId: string | undefined;
    const { data: list } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    userId = list?.users.find((u) => u.email?.toLowerCase() === email)?.id;
    if (!userId) {
      const { data, error } = await admin.auth.admin.createUser({ email, email_confirm: true });
      if (error || !data.user) throw new Error(`The sign-in account could not be created: ${error?.message ?? "unknown"}`);
      userId = data.user.id;
    }
    const id = await rpc<string>("user_save", { p: { ...p.data, email, user_id: userId } });
    done("/w/teams");
    return id;
  }, "Saved.");
}

export async function userDeactivate(userId: string, reason: string): Promise<ActionResult<{ reassigned: number }>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<{ reassigned: number }>("user_deactivate", { p_user: uuid.parse(userId), p_reason: reason }));
  done("/w/teams");
  return r;
}

// ---------- settings ----------

export async function settingSave(key: string, value: unknown, reason: string): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc("set_setting", { p_key: key, p_value: value, p_reason: reason || "edited in Settings" }), "Saved.");
  done("/w/settings");
  return r;
}
