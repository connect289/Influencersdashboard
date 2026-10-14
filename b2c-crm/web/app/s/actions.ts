"use server";
import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { lookupByPhone, b2bReady } from "@/lib/b2b";
import { textToHtml } from "@/lib/compose";
import { act, rpc, type ActionResult } from "@/lib/data";
import { createClient } from "@/lib/supabase/server";
import { adminClient } from "@/lib/supabase/admin";

const SALES = ["counsellor", "sales_head", "admin"] as const;
const id = z.coerce.number().int().positive();
const iso = z.string().datetime({ offset: true });

function done(leadId?: number) {
  revalidatePath("/s", "layout");
  if (leadId) revalidatePath(`/s/leads/${leadId}`);
}

// ---------- calls ----------

/** Records the tap and returns the number to dial (b2c.call_tap). The log sheet opens next. */
export async function callTap(leadId: number, contactId?: number): Promise<ActionResult<{ call_id: number; number: string; tel: string }>> {
  await assertUser([...SALES]);
  return act(() => rpc("call_tap", { p_lead: id.parse(leadId), p_contact: contactId ?? null }));
}

const callLogSchema = z.object({
  call: id, outcome: z.enum(["connected", "no_answer", "busy", "switched_off", "wrong_number", "call_back"]),
  duration: z.coerce.number().int().min(0).max(36000).optional(), note: z.string().max(2000).optional(),
  next: iso, nextKind: z.enum(["call", "whatsapp", "email", "document", "followup", "qualify"]).default("call"), nextNote: z.string().max(300).optional(),
});

/** Logs the call's outcome; the next follow-up is required (spec B8.3). Stage moves automatically from New / Could Not Connect. */
export async function callLog(input: z.input<typeof callLogSchema>, leadId: number): Promise<ActionResult<{ moved_to: string | null; sub_stage: string | null }>> {
  await assertUser([...SALES]);
  const p = callLogSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Choose the outcome and the next follow-up." };
  const r = await act(() => rpc<{ moved_to: string | null; sub_stage: string | null }>("call_log", {
    p_call: p.data.call, p_outcome: p.data.outcome, p_duration_s: p.data.duration ?? null, p_note: p.data.note ?? null,
    p_next_due: p.data.next, p_next_kind: p.data.nextKind, p_next_note: p.data.nextNote ?? null,
  }), "Call logged. It reaches the master lead table with the next sync.");
  done(leadId);
  return r;
}

// ---------- stage ----------

const stageSchema = z.object({
  lead: id, stage: z.coerce.number().int().min(1).max(10), sub: z.string().min(1).max(80), comment: z.string().max(1000).optional(),
  next: iso.optional(), nextKind: z.string().max(20).optional(), nextNote: z.string().max(300).optional(),
});

export async function setStage(input: z.input<typeof stageSchema>): Promise<ActionResult> {
  await assertUser([...SALES]);
  const p = stageSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Choose a stage and a sub-stage." };
  const r = await act(() => rpc("set_stage", {
    p_lead: p.data.lead, p_stage: p.data.stage, p_sub: p.data.sub, p_comment: p.data.comment || null,
    p_next_due: p.data.next ?? null, p_next_kind: p.data.nextKind ?? "call", p_next_note: p.data.nextNote || null,
  }), "Stage saved.");
  done(p.data.lead);
  return r;
}

// ---------- follow-ups ----------

export async function taskAdd(leadId: number, kind: string, title: string, due: string, note?: string): Promise<ActionResult> {
  await assertUser([...SALES]);
  if (!iso.safeParse(due).success) return { ok: false, error: "Pick a date and time." };
  const r = await act(() => rpc("task_add", { p_lead: id.parse(leadId), p_kind: kind, p_title: title.slice(0, 200), p_due: due, p_note: note?.slice(0, 1000) || null }), "Follow-up added.");
  done(leadId);
  return r;
}

export async function taskDone(taskId: number, outcome: string, next: string | null, nextKind = "call", nextNote?: string, leadId?: number): Promise<ActionResult> {
  await assertUser([...SALES]);
  if (next && !iso.safeParse(next).success) return { ok: false, error: "Pick a date and time for the next follow-up." };
  const r = await act(() => rpc("task_done", { p_task: id.parse(taskId), p_outcome: outcome.slice(0, 300), p_next_due: next, p_next_kind: nextKind, p_next_note: nextNote || null }), "Done.");
  done(leadId);
  return r;
}

export async function taskMove(taskId: number, due: string, leadId?: number): Promise<ActionResult> {
  await assertUser([...SALES]);
  if (!iso.safeParse(due).success) return { ok: false, error: "Pick a date and time." };
  const r = await act(() => rpc("task_move", { p_task: id.parse(taskId), p_due: due }), "Moved.");
  done(leadId);
  return r;
}

// ---------- notes, contacts, profile ----------

export async function addNote(leadId: number, body: string): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("add_note", { p_lead: id.parse(leadId), p_body: body.slice(0, 4000), p_internal: false }), "Note added.");
  done(leadId);
  return r;
}

export async function addContact(leadId: number, kind: "phone" | "email", value: string, label: string, primary: string[]): Promise<ActionResult<{ duplicate_of_lead: number | null }>> {
  await assertUser([...SALES]);
  const r = await act(() => rpc<{ duplicate_of_lead: number | null }>("add_contact", {
    p_lead: id.parse(leadId), p_kind: kind, p_value: value.slice(0, 254), p_label: label || "alternate", p_primary: primary,
  }), "Contact added.");
  done(leadId);
  return r;
}

export async function setPrimary(contactId: number, forWhat: string[], leadId: number): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("set_primary", { p_contact: id.parse(contactId), p_for: forWhat }), "Primary changed.");
  done(leadId);
  return r;
}

/** Profile corrections and cross-sell (b2c.correct_lead keeps the field history; a programme change needs a reason). */
export async function correctLead(leadId: number, fields: Record<string, string | number | null>, reason?: string): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("correct_lead", { p_lead: id.parse(leadId), p_fields: fields, p_reason: reason || null }), "Saved. It reaches the master lead table with the next sync.");
  done(leadId);
  return r;
}

export async function handBack(leadId: number, reason: string): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("hand_back", { p_lead: id.parse(leadId), p_reason: reason }), "Handed back.");
  done();
  return r;
}

// ---------- WhatsApp ----------

export async function waTemplate(leadId: number, templateId: number): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("wa_queue_template", { p_lead: id.parse(leadId), p_template: id.parse(templateId), p_extra: {} }), "Template queued.");
  revalidatePath("/s/inbox");
  done(leadId);
  return r;
}

export async function waText(leadId: number, text: string): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("wa_queue_text", { p_lead: id.parse(leadId), p_text: text.slice(0, 4096) }), "Message queued.");
  revalidatePath("/s/inbox");
  done(leadId);
  return r;
}

export async function waRead(leadId: number): Promise<void> {
  await assertUser();
  await rpc("wa_mark_read", { p_lead: id.parse(leadId) }).catch(() => undefined);
}

// ---------- applications and enrolment ----------

export async function applicationSave(input: Record<string, unknown>): Promise<ActionResult<number>> {
  await assertUser([...SALES]);
  const leadId = id.parse(input.lead_id);
  const r = await act(() => rpc<number>("application_save", { p: input }), "Application saved.");
  done(leadId);
  return r;
}

const MAX_PROOF = 4 * 1024 * 1024;
const PROOF_TYPES = ["application/pdf", "image/jpeg", "image/png", "image/webp"];

/** Uploads a document to the private bucket under the lead's folder, after the database confirms the person may see the lead. */
async function uploadDoc(leadId: number, file: File): Promise<string> {
  if (!(file instanceof File) || file.size === 0) throw new Error("Attach the file.");
  if (file.size > MAX_PROOF) throw new Error("The file is larger than 4 MB.");
  if (!PROOF_TYPES.includes(file.type)) throw new Error("Use a PDF, JPEG, PNG or WebP file.");
  const allowed = await rpc<boolean>("can_see", { p_lead: leadId });
  if (!allowed) throw new Error("not allowed");
  const ext = file.type === "application/pdf" ? "pdf" : file.type.split("/")[1];
  const path = `leads/${leadId}/${randomUUID()}.${ext}`;
  const { error } = await adminClient().storage.from("b2c-documents").upload(path, file, { contentType: file.type, upsert: false });
  if (error) throw new Error(`Upload failed: ${error.message}`);
  return path;
}

/** Records an enrolment: fee, date and proof are required (spec B11). The Admin then verifies it. */
export async function enrollmentRecord(form: FormData): Promise<ActionResult> {
  await assertUser([...SALES]);
  const leadId = id.parse(form.get("lead_id"));
  const r = await act(async () => {
    const path = await uploadDoc(leadId, form.get("proof") as File);
    return rpc("enrollment_record", {
      p: {
        lead_id: leadId, application_id: form.get("application_id") || null, university: String(form.get("university") ?? ""),
        programme: String(form.get("programme") ?? ""), fee: form.get("fee"), fee_paid: form.get("fee_paid") || 0,
        enrolled_on: form.get("enrolled_on"), proof_path: path, note: form.get("note") || null,
      },
    });
  }, "Enrolment recorded. The Admin verifies it next.");
  done(leadId);
  return r;
}

export async function documentAdd(form: FormData): Promise<ActionResult> {
  await assertUser([...SALES]);
  const leadId = id.parse(form.get("lead_id"));
  const r = await act(async () => {
    const file = form.get("file") as File;
    const path = await uploadDoc(leadId, file);
    return rpc("document_add", {
      p_lead: leadId, p_application: form.get("application_id") ? Number(form.get("application_id")) : null,
      p_kind: String(form.get("kind") ?? "Document").slice(0, 80), p_path: path, p_name: file.name.slice(0, 200), p_source: "upload",
    });
  }, "Document saved.");
  done(leadId);
  return r;
}

// ---------- new lead ----------

/**
 * Phone first (spec B5.2): looks the number up in the B2B CRM. With a partner → refused with who holds it; in our pool →
 * re-engaged to this counsellor; with another counsellor → refused; otherwise the student goes in through the Intake API.
 */
export async function newLead(input: { phone: string; name?: string; email?: string; course?: string; city?: string; notes?: string }): Promise<ActionResult<{ outcome: string; lead_id?: number; owner?: string }>> {
  await assertUser([...SALES]);
  const digits = input.phone.replace(/\D/g, "");
  if (digits.length < 10 || digits.length > 13) return { ok: false, error: "Enter a valid phone number." };
  let existing: Record<string, unknown> | null = null;
  if (b2bReady()) {
    const found = await lookupByPhone(digits);
    if (found.status >= 500 || found.status === 0) return { ok: false, error: "The master lead table did not answer. Try again in a minute." };
    const matches = ((found.body.result as { leads?: unknown[] } | undefined)?.leads ?? (found.body.leads as unknown[] | undefined) ?? []) as Record<string, unknown>[];
    const m = matches[0];
    if (m) existing = { lead_id: m.lead_id, held_by_b2c: m.held_by_b2c === true, holder: (m.record as Record<string, unknown> | undefined)?.allocation ?? null };
  }
  const r = await act(() => rpc<{ outcome: string; lead_id?: number; owner?: string }>("new_lead", {
    p: { phone: digits, name: input.name || null, email: input.email || null, course: input.course || null, city: input.city || null,
         // No partner-sharing consent is recorded here: only a text registered in the B2B CRM counts (contract §3.6).
         notes: input.notes || null },
    p_existing: existing,
  }));
  done();
  return r;
}

// ---------- me ----------

export async function setAway(minutes: number): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("set_away", { p_minutes: Math.max(0, Math.min(1440, Math.round(minutes))) }), minutes > 0 ? "You are away. New leads go to others." : "You are working.");
  done();
  return r;
}

export async function emailTemplateSave(input: Record<string, unknown>): Promise<ActionResult<number>> {
  await assertUser([...SALES, "marketing"]);
  const r = await act(() => rpc<number>("email_template_save", { p: input }), "Template saved.");
  revalidatePath("/s/me");
  return r;
}

export async function notificationsRead(ids?: number[]): Promise<void> {
  await assertUser();
  await rpc("notifications_read", { p_ids: ids ?? null }).catch(() => undefined);
  revalidatePath("/s", "layout");
}

// ---------- email (spec B8.6: from the counsellor's own mailbox) ----------

export type ComposeTemplate = { id: number; name: string; category: string; subject: string; body: string; recommended: boolean; mine: boolean };

/** The sales templates the composer offers: recommended first, then the most used. Hidden ones only to their author. */
export async function emailTemplatesList(): Promise<ActionResult<ComposeTemplate[]>> {
  const me = await assertUser([...SALES]);
  const supabase = await createClient();
  const { data, error } = await supabase.from("sales_email_templates").select("id, owner_id, name, category, subject, body, recommended, hidden")
    .is("deleted_at", null).order("recommended", { ascending: false }).order("uses", { ascending: false }).limit(200);
  if (error) return { ok: false, error: error.message };
  return { ok: true, data: (data ?? []).filter((t) => !t.hidden || t.owner_id === me.user_id)
    .map((t) => ({ id: t.id, name: t.name, category: t.category, subject: t.subject, body: t.body, recommended: t.recommended, mine: t.owner_id === me.user_id })) };
}

const emailSchema = z.object({ lead: id, subject: z.string().trim().min(1).max(300), text: z.string().trim().min(1).max(20000), template: id.nullable().optional() });

/** Queues the email (b2c.email_queue); the sync job sends it through Gmail, or records "test mode, not sent". */
export async function emailSend(input: z.input<typeof emailSchema>): Promise<ActionResult<number>> {
  await assertUser([...SALES]);
  const p = emailSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Write a subject and a message." };
  if (/\{\{\s*[a-z_]+\s*\}\}/.test(p.data.subject + p.data.text)) return { ok: false, error: "Fill in or remove the {{…}} placeholders first." };
  const r = await act(() => rpc<number>("email_queue", { p_lead: p.data.lead, p_subject: p.data.subject, p_html: textToHtml(p.data.text), p_text: p.data.text, p_template: p.data.template ?? null }),
    "Email queued. It goes from your mailbox within a minute.");
  done(p.data.lead);
  return r;
}

// ---------- programme fit and sharing (B8.3) ----------

export type FitRow = {
  id: number; name: string; course: string | null; specialization: string | null; level: string | null; mode: string | null; university: string;
  university_short: string | null; fee_yearly: number | null; fee_semester: number | null; fee_total: number | null; min_qualification: string | null;
  min_pct: number | null; eligibility: string | null; brochure_url: string | null; fit: number; matched: string[];
};
export type Fit = { interest: Record<string, string | null>; rows: FitRow[] };

export async function programmeFit(leadId: number): Promise<ActionResult<Fit>> {
  await assertUser();
  return act(() => rpc<Fit>("programme_fit", { p_lead: id.parse(leadId), p_limit: 12 }));
}

const shareSchema = z.object({
  lead: id, programmes: z.array(id).min(1).max(3), channel: z.enum(["whatsapp", "email", "call", "meeting"]),
  text: z.string().trim().max(4000).optional(), subject: z.string().trim().max(300).optional(), note: z.string().trim().max(500).optional(),
});

/** WhatsApp (inside the 24-hour window) or email first, then the share is recorded; a call or meeting is only recorded. */
export async function programmeShare(input: z.input<typeof shareSchema>): Promise<ActionResult> {
  await assertUser([...SALES]);
  const p = shareSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Choose one to three programmes and how you shared them." };
  const { lead, programmes, channel, text, subject, note } = p.data;
  if ((channel === "whatsapp" || channel === "email") && !text) return { ok: false, error: "Write the message." };
  const r = await act(async () => {
    if (channel === "whatsapp") await rpc("wa_queue_text", { p_lead: lead, p_text: text });
    if (channel === "email") await rpc("email_queue", { p_lead: lead, p_subject: subject || "Programme details", p_html: textToHtml(text!), p_text: text, p_template: null });
    return rpc("programme_share", { p_lead: lead, p_programmes: programmes, p_channel: channel, p_note: note || null });
  }, channel === "whatsapp" ? "Shared on WhatsApp." : channel === "email" ? "Email queued." : "Recorded on the timeline.");
  done(lead);
  return r;
}

// ---------- Witty's conversation (read-only) ----------

export type WittyMessage = { id: number; phone: string; direction: string; kind: string | null; content: string | null; at: string; sent: boolean | null };

export async function wittyTranscript(leadId: number): Promise<ActionResult<WittyMessage[]>> {
  await assertUser();
  return act(() => rpc<WittyMessage[]>("witty_transcript", { p_lead: id.parse(leadId), p_limit: 300 }));
}

// ---------- the laptop call view: a copied number is logged like a reveal ----------

export async function numberCopied(leadId: number): Promise<void> {
  await assertUser();
  await rpc("audit", { p_action: "contact_copy", p_lead: id.parse(leadId), p_detail: { via: "call_sheet" } }).catch(() => undefined);
}

// ---------- custom lead views (B8.4) ----------

const viewSchema = z.object({
  id: id.optional(), name: z.string().trim().min(1).max(60).optional(), role: z.enum(["sales", "workspace"]),
  filters: z.object({ all: z.array(z.object({ field: z.string().max(40), op: z.string().max(20), value: z.unknown().optional() })).max(12) }).optional(),
  sort: z.object({ field: z.string().max(40), dir: z.enum(["asc", "desc"]) }).optional(),
  is_standard: z.boolean().optional(), hidden: z.boolean().optional(),
});

/** Saves (or hides) one of the person's views; the database runs it once first, so a broken view is never saved. */
export async function viewSave(input: z.input<typeof viewSchema>): Promise<ActionResult<number>> {
  await assertUser();
  const p = viewSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Name the view and check its conditions." };
  const r = await act(() => rpc<number>("view_save", { p: p.data }), p.data.hidden ? "View removed." : "View saved.");
  revalidatePath(p.data.role === "sales" ? "/s/leads" : "/w/leads");
  return r;
}
