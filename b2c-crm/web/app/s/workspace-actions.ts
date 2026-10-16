"use server";
import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { textToHtml } from "@/lib/compose";
import { act, friendly, rpc, type ActionResult } from "@/lib/data";
import type { Programme } from "@/lib/programmes";
import { createClient } from "@/lib/supabase/server";
import { adminClient } from "@/lib/supabase/admin";
import { suggestNext, type MergeValues, type Suggestion } from "@/lib/workspace";

/** Server actions for the counsellor workspace (completion C, E3, E12, E15). Every check is the database's. */

const SALES = ["counsellor", "sales_head", "admin"] as const;
const id = z.coerce.number().int().positive();
const iso = z.string().datetime({ offset: true });
const uuid = z.string().uuid();
const BUCKET = "b2c-documents";

function done(leadId?: number) {
  revalidatePath("/s", "layout");
  if (leadId) {
    revalidatePath(`/s/leads/${leadId}`);
    revalidatePath(`/w/leads/${leadId}`);
  }
}

/** A short signed link to a stored file the database has just allowed (and logged). */
async function signed(path: string, filename: string): Promise<string> {
  const { data, error } = await adminClient().storage.from(BUCKET).createSignedUrl(path, 120, { download: filename || true });
  if (error || !data) throw new Error("The file could not be opened.");
  return data.signedUrl;
}

// ---------- documents and WhatsApp media (C1, C10) ----------

export async function documentOpen(docId: number): Promise<ActionResult<string>> {
  await assertUser();
  try {
    const r = await rpc<{ bucket: string; path: string; filename: string }>("document_open", { p_document: id.parse(docId) });
    if (r.bucket !== BUCKET) throw new Error("The file could not be opened.");
    return { ok: true, data: await signed(r.path, r.filename) };
  } catch (e) {
    return { ok: false, error: friendly(e) };
  }
}

export async function waMediaOpen(messageId: number): Promise<ActionResult<string>> {
  await assertUser();
  try {
    const r = await rpc<{ bucket: string; path: string; filename: string }>("wa_media_open", { p_message: id.parse(messageId) });
    if (r.bucket !== BUCKET) throw new Error("The file could not be opened.");
    return { ok: true, data: await signed(r.path, r.filename) };
  } catch (e) {
    return { ok: false, error: friendly(e) };
  }
}

/** One tap: a document the student sent on WhatsApp goes onto an application's checklist (or the lead's documents). */
export async function waMediaAttach(messageId: number, applicationId: number | null, kind: string, leadId: number): Promise<ActionResult<number>> {
  await assertUser([...SALES]);
  const r = await act(() => rpc<number>("wa_media_attach", { p_message: id.parse(messageId), p_application: applicationId ? id.parse(applicationId) : null, p_kind: kind.trim().slice(0, 80) }),
    "Added to the checklist.");
  done(leadId);
  return r;
}

const MAX_FILE = 4 * 1024 * 1024;
const IMAGE = ["image/jpeg", "image/png", "image/webp"];
const DOCS = ["application/pdf"];

/** An image or a PDF to the student inside the 24-hour window: stored under the lead's folder, then queued (b2c.wa_queue_media). */
export async function waSendFile(form: FormData): Promise<ActionResult<number>> {
  await assertUser([...SALES]);
  const leadId = id.parse(form.get("lead_id"));
  const r = await act(async () => {
    const file = form.get("file");
    if (!(file instanceof File) || file.size === 0) throw new Error("Attach the file.");
    if (file.size > MAX_FILE) throw new Error("The file is larger than 4 MB.");
    const kind = IMAGE.includes(file.type) ? "image" : DOCS.includes(file.type) ? "document" : null;
    if (!kind) throw new Error("Send a JPEG, PNG or WebP image, or a PDF.");
    if (!(await rpc<boolean>("can_see", { p_lead: leadId }))) throw new Error("not allowed");
    const ext = file.type === "application/pdf" ? "pdf" : file.type.split("/")[1];
    const path = `leads/${leadId}/wa/${randomUUID()}.${ext}`;
    const { error } = await adminClient().storage.from(BUCKET).upload(path, file, { contentType: file.type, upsert: false });
    if (error) throw new Error(`Upload failed: ${error.message}`);
    const caption = String(form.get("caption") ?? "").trim().slice(0, 1024) || null;
    try {
      return await rpc<number>("wa_queue_media", { p_lead: leadId, p_kind: kind, p_path: path, p_caption: caption, p_filename: file.name.slice(0, 120), p_link: null });
    } catch (e) {
      await adminClient().storage.from(BUCKET).remove([path]).catch(() => undefined);
      throw e;
    }
  }, "File queued.");
  revalidatePath("/s/inbox");
  done(leadId);
  return r;
}

/** A brochure (a public https link from the Programme page) to the student inside the window. */
export async function waSendLink(leadId: number, link: string, caption?: string, filename?: string): Promise<ActionResult<number>> {
  await assertUser([...SALES]);
  const r = await act(() => rpc<number>("wa_queue_media", {
    p_lead: id.parse(leadId), p_kind: "document", p_path: null, p_caption: caption?.slice(0, 1024) || null, p_filename: filename?.slice(0, 120) || "Brochure",
    p_link: z.string().url().startsWith("https://").parse(link),
  }), "Brochure queued.");
  revalidatePath("/s/inbox");
  done(leadId);
  return r;
}

// ---------- the lead screen (C9, E3) ----------

export async function customFieldSet(leadId: number, key: string, value: string): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("custom_field_set", { p_lead: id.parse(leadId), p_key: z.string().max(40).parse(key), p_value: value.slice(0, 300) }), "Saved.");
  done(leadId);
  return r;
}

export async function setPrimaryFor(contactId: number, forWhat: ("call" | "whatsapp" | "email")[], leadId: number): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("set_primary", { p_contact: id.parse(contactId), p_for: forWhat }), "Primary changed.");
  done(leadId);
  return r;
}

/** The sales head (their team) or the Admin moves leads to a named person, or back through the rules (b2c.reassign). */
export async function reassignLeads(leads: number[], userId: string | null, reason: string): Promise<ActionResult<number>> {
  await assertUser(["sales_head", "admin"]);
  const r = await act(() => rpc<number>("reassign", { p_leads: z.array(id).min(1).max(200).parse(leads), p_user: userId ? uuid.parse(userId) : null, p_reason: reason.trim().slice(0, 300) }),
    userId ? "Reassigned." : "Sent through the allocation rules again.");
  done();
  revalidatePath("/w", "layout");
  return r;
}

export async function handBackLead(leadId: number, reason: string): Promise<ActionResult> {
  await assertUser([...SALES]);
  const r = await act(() => rpc("hand_back", { p_lead: id.parse(leadId), p_reason: reason.trim().slice(0, 300) }), "Handed back. The allocation rules choose someone else.");
  done();
  return r;
}

// ---------- stage overrides (E15) ----------

const overrideSchema = z.object({ lead: id, stage: z.coerce.number().int().min(1).max(10), sub: z.string().min(1).max(80), comment: z.string().trim().min(3).max(1000), next: iso.optional() });

export async function stageOverrideRequest(input: z.input<typeof overrideSchema>): Promise<ActionResult<number>> {
  await assertUser([...SALES]);
  const p = overrideSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Choose the stage and sub-stage and give a reason." };
  const r = await act(() => rpc<number>("stage_override_request", { p_lead: p.data.lead, p_stage: p.data.stage, p_sub: p.data.sub, p_comment: p.data.comment, p_next_due: p.data.next ?? null }),
    "Asked. Your sales head (or the Admin) approves it.");
  done(p.data.lead);
  return r;
}

export async function stageOverrideDecide(requestId: number, approve: boolean, note?: string, leadId?: number): Promise<ActionResult> {
  await assertUser(["sales_head", "admin"]);
  const r = await act(() => rpc("stage_override_decide", { p_request: id.parse(requestId), p_approve: approve, p_note: note?.trim().slice(0, 300) || null }),
    approve ? "Approved: the stage is changed." : "Declined.");
  done(leadId);
  revalidatePath("/w");
  return r;
}

// ---------- calls (C8) ----------

/** The next step a call outcome suggests (b2c.call_suggestion; the same rule here if the function is not callable). */
export async function callSuggestion(leadId: number, outcome: string): Promise<ActionResult<Suggestion>> {
  await assertUser([...SALES]);
  const lead = id.parse(leadId);
  try {
    return { ok: true, data: await rpc<Suggestion>("call_suggestion", { p_lead: lead, p_outcome: outcome }) };
  } catch {
    const supabase = await createClient();
    const since = new Date(Date.now() - 48 * 3600e3).toISOString();
    const { count } = await supabase.from("calls").select("id", { count: "exact", head: true })
      .eq("lead_id", lead).in("outcome", ["no_answer", "busy", "switched_off"]).gt("logged_at", since);
    return { ok: true, data: suggestNext(outcome, count ?? 0) };
  }
}

// ---------- programmes (C2, C6) ----------

export async function programmeCompare(ids: number[], leadId?: number | null): Promise<ActionResult<Programme[]>> {
  await assertUser();
  return act(() => rpc<Programme[]>("programme_compare", { p_ids: z.array(id).min(2).max(4).parse(ids), p_lead: leadId ? id.parse(leadId) : null }));
}

export async function programmeFitRows(leadId: number): Promise<ActionResult<{ interest: Record<string, string | null>; rows: Programme[] }>> {
  await assertUser();
  return act(() => rpc("programme_fit", { p_lead: id.parse(leadId), p_limit: 12 }));
}

/** Programmes for a picker (template attachments): a short search. */
export async function programmeFind(q: string): Promise<ActionResult<Programme[]>> {
  await assertUser();
  return act(async () => (await rpc<{ rows: Programme[] }>("programme_search", { p: { q: q.trim().slice(0, 100) || null, limit: 20 } })).rows);
}

const sendSchema = z.object({
  lead: id, programmes: z.array(id).min(1).max(4), channel: z.enum(["whatsapp", "email", "call", "meeting"]),
  text: z.string().trim().max(4000).optional(), subject: z.string().trim().max(300).optional(), note: z.string().trim().max(500).optional(),
  brochures: z.array(z.object({ url: z.string().url().startsWith("https://"), name: z.string().max(120) })).max(4).optional(),
});

/**
 * Up to four programmes to the lead: on WhatsApp the message (inside the window) plus each brochure as a document, or by
 * email with the brochure links; a call or meeting is only recorded. Each share goes on the timeline (b2c.programme_share).
 */
export async function programmeSend(input: z.input<typeof sendSchema>): Promise<ActionResult> {
  await assertUser([...SALES]);
  const p = sendSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "Choose one to four programmes and how you shared them." };
  const { lead, programmes, channel, text, subject, note, brochures = [] } = p.data;
  if ((channel === "whatsapp" || channel === "email") && !text) return { ok: false, error: "Write the message." };
  const r = await act(async () => {
    if (channel === "whatsapp") {
      await rpc("wa_queue_text", { p_lead: lead, p_text: text });
      for (const b of brochures) await rpc("wa_queue_media", { p_lead: lead, p_kind: "document", p_path: null, p_caption: null, p_filename: b.name || "Brochure", p_link: b.url });
    }
    if (channel === "email") await rpc("email_queue", { p_lead: lead, p_subject: subject || "Programme details", p_html: textToHtml(text!), p_text: text, p_template: null });
    return rpc("programme_share", { p_lead: lead, p_programmes: programmes, p_channel: channel, p_note: note || null });
  }, channel === "whatsapp" ? "Shared on WhatsApp." : channel === "email" ? "Email queued." : "Recorded on the timeline.");
  revalidatePath("/s/inbox");
  done(lead);
  return r;
}

// ---------- the sales email library (C4) ----------

export type LibraryTemplate = {
  id: number; name: string; category: string; subject: string; body: string; attachments: { name?: string; url?: string; programme_id?: number }[];
  parent_id: number | null; version: number; recommended: boolean; hidden: boolean; owner_id: string; author: string | null; mine: boolean;
  uses: number; replies: number; reply_rate: number | null; updated_at: string;
};

export async function emailLibrary(p: { category?: string; mine?: boolean; search?: string } = {}): Promise<ActionResult<LibraryTemplate[]>> {
  await assertUser([...SALES, "marketing"]);
  return act(() => rpc<LibraryTemplate[]>("email_library", { p }));
}

export async function mergeValues(leadId: number): Promise<ActionResult<MergeValues>> {
  await assertUser();
  return act(() => rpc<MergeValues>("merge_values", { p_lead: id.parse(leadId) }));
}

/** The Admin marks a template recommended, or hides it (b2c.email_template_flag). */
export async function emailTemplateFlag(templateId: number, flags: { recommended?: boolean; hidden?: boolean }): Promise<ActionResult> {
  await assertUser(["admin"]);
  const r = await act(() => rpc("email_template_flag", { p_id: id.parse(templateId), p_recommended: flags.recommended ?? null, p_hidden: flags.hidden ?? null }),
    flags.hidden === true ? "Hidden from the library." : flags.hidden === false ? "Shown in the library." : flags.recommended ? "Recommended." : "No longer recommended.");
  revalidatePath("/s/me");
  return r;
}

/** The author or the Admin deletes a template; copies others saved stay. */
export async function emailTemplateDelete(templateId: number): Promise<ActionResult> {
  await assertUser([...SALES, "marketing"]);
  const r = await act(() => rpc("email_template_delete", { p_id: id.parse(templateId) }), "Template deleted.");
  revalidatePath("/s/me");
  return r;
}

const tplSchema = z.object({
  id: id.nullable().optional(), name: z.string().trim().min(1).max(120), category: z.string().max(40), subject: z.string().trim().min(1).max(300),
  body: z.string().trim().min(1).max(20000), attachments: z.array(z.object({ name: z.string().max(200), url: z.string().url().startsWith("https://"), programme_id: id.optional() })).max(6),
});

/** Saves a sales template with its brochure links (editing someone else's saves your own copy: b2c.email_template_save). */
export async function emailTemplateSaveFull(input: z.input<typeof tplSchema>): Promise<ActionResult<number>> {
  await assertUser([...SALES, "marketing"]);
  const p = tplSchema.safeParse(input);
  if (!p.success) return { ok: false, error: "A template needs a name, a subject and a body; brochure links must start with https://." };
  const r = await act(() => rpc<number>("email_template_save", { p: p.data }), "Template saved.");
  revalidatePath("/s/me");
  return r;
}

// ---------- WhatsApp alerts to my own number (C7) ----------

export async function myWaAlertsSet(kinds: string[]): Promise<ActionResult<string[]>> {
  await assertUser();
  const r = await act(() => rpc<string[]>("my_wa_alerts_set", { p_kinds: z.array(z.string().max(40)).max(20).parse(kinds) }),
    kinds.length ? "Saved. These alerts also come on WhatsApp." : "WhatsApp alerts are off.");
  revalidatePath("/s/me");
  return r;
}
