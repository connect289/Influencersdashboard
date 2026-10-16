"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertUser } from "@/lib/auth";
import { aiConfigured } from "@/lib/ai";
import { writeInsights } from "@/lib/analytics-ai";
import type { Spec } from "@/lib/analytics";
import { act, friendly, rpc, type ActionResult } from "@/lib/data";
import { siteUrl } from "@/lib/env";
import { sendMail } from "@/lib/mail";
import { adminClient } from "@/lib/supabase/admin";
import { importWaTemplates } from "@/lib/wa-template-import";
import { submitTemplate, type TemplateRow } from "@/lib/wa-templates";
import { createClient } from "@/lib/supabase/server";
import { renderBlocks, BlocksSchema, type Block } from "@/lib/email-blocks";

/**
 * Workspace admin screens (Settings, Lead Allocation, Teams, Connectors, Money, Templates, Analytics, Guide). Every call
 * runs as the signed-in person; the b2c function checks the role again and raises a plain-English message.
 */
const ADMIN = ["admin"] as const;
const MKT = ["admin", "marketing"] as const;
const id = z.coerce.number().int().positive();
const uuid = z.string().uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Choose a date.");
const reason = z.string().trim().min(3, "Give a reason.").max(300);
const done = (...paths: string[]) => { for (const p of paths) revalidatePath(p); };

// ---------- Settings: stages and sub-stages (b2c.stage_save, sub_stage_save) ----------

export type StageAdmin = {
  stages: { id: number; name: string; rank: number; canon: string; required: string[]; reachable_from_any: boolean; is_closed: boolean; active: boolean; leads: number;
    sub_stages: { id: number; stage_id: number; name: string; rank: number; returns_to_pool: boolean; journey: string | null; first_message_days: number | null; comment_required: boolean; active: boolean; leads: number }[] }[];
  history: { at: string; by: string | null; action: string; detail: Record<string, unknown> }[];
};

const REQUIRED = ["call_attempt", "contact", "profile", "followup", "programme_shared", "application", "checklist", "enrollment", "comment"] as const;
const StageSchema = z.object({
  id, name: z.string().trim().min(2, "Name the stage.").max(60), required: z.array(z.enum(REQUIRED)).max(9),
  reachable_from_any: z.boolean(), active: z.boolean(), reason,
});
export async function stageSave(p: z.input<typeof StageSchema>): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const v = StageSchema.safeParse(p);
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the stage." };
  const r = await act(() => rpc("stage_save", { p: v.data }), "Stage saved.");
  done("/w/settings");
  return r;
}

const SubStageSchema = z.object({
  id: id.nullable().optional(), stage_id: id, name: z.string().trim().min(2, "Name the sub-stage.").max(80), rank: z.coerce.number().int().min(0).max(10000).nullable().optional(),
  returns_to_pool: z.boolean(), journey: z.string().trim().max(80).nullable().optional(), first_message_days: z.coerce.number().int().min(0).max(365).nullable().optional(),
  comment_required: z.boolean(), active: z.boolean(), reason,
});
export async function subStageSave(p: z.input<typeof SubStageSchema>): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const v = SubStageSchema.safeParse(p);
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the sub-stage." };
  // a key left out keeps its value; null clears it (the function reads "" as empty)
  const { journey, first_message_days, ...rest } = v.data;
  const body: Record<string, unknown> = { ...rest };
  if (journey !== undefined) body.journey = journey ?? "";
  if (first_message_days !== undefined) body.first_message_days = first_message_days ?? "";
  const r = await act(() => rpc<number>("sub_stage_save", { p: body }), "Sub-stage saved.");
  done("/w/settings");
  return r;
}

// ---------- Settings: document checklists, custom fields ----------

export async function checklistSave(university: string, items: string[], why: string): Promise<ActionResult> {
  await assertUser([...ADMIN]);
  const v = z.object({ university: z.string().trim().min(1, "Name the university (or * for the default list).").max(200), items: z.array(z.string().trim().min(1).max(120)).max(40), why: reason })
    .safeParse({ university, items, why });
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the list." };
  const r = await act(() => rpc("checklist_save", { p_university: v.data.university, p_items: v.data.items, p_reason: v.data.why }), "Checklist saved.");
  done("/w/settings");
  return r;
}

const FieldSchema = z.object({
  key: z.string().regex(/^[a-z][a-z0-9_]{1,30}$/, "Field keys are lower-case letters, digits and _ (2 to 31)."), label: z.string().trim().min(1, "Every field needs a label.").max(60),
  type: z.enum(["text", "number", "date", "select", "yes_no"]), options: z.array(z.string().trim().min(1).max(60)).max(30).optional(),
});
export async function customFieldsSave(fields: z.input<typeof FieldSchema>[], why: string): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const v = z.object({ fields: z.array(FieldSchema).max(30, "At most 30 fields."), why: reason }).safeParse({ fields, why });
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the fields." };
  const clean = v.data.fields.map((f) => (f.type === "select" ? f : { key: f.key, label: f.label, type: f.type }));
  const r = await act(() => rpc<number>("custom_fields_save", { p_fields: clean, p_reason: v.data.why }), "Custom fields saved.");
  done("/w/settings");
  return r;
}

// ---------- Lead Allocation: queues, calendar, capacity, simulation ----------

export async function queueAllocate(lead: number): Promise<ActionResult<{ outcome: string; why?: string }>> {
  await assertUser([...ADMIN, "sales_head"]);
  const r = await act(() => rpc<{ outcome: string; why?: string; chosen_name?: string }>("queue_allocate", { p_lead: id.parse(lead) }));
  done("/w/allocation", "/w");
  if (!r.ok) return r;
  const o = r.data?.outcome;
  return { ...r, notice: o === "assigned" ? "Allocated." : o === "manual_queue" ? "A rule sends it to the manual queue: give it to someone." : `Nobody could take it now${r.data?.why ? `: ${r.data.why}` : ""}.` };
}

const BreakSchema = z.object({
  user_id: uuid.nullable(), isodow: z.coerce.number().int().min(1).max(7).nullable(),
  start: z.string().regex(/^\d{2}:\d{2}$/), end: z.string().regex(/^\d{2}:\d{2}$/), label: z.string().trim().max(40),
}).refine((b) => b.end > b.start, "A break ends after it starts.");
export async function breaksSave(breaks: z.input<typeof BreakSchema>[]): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const v = z.array(BreakSchema).max(50).safeParse(breaks);
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the breaks." };
  const r = await act(() => rpc<number>("breaks_save", { p: v.data }), "Breaks saved. Only hot leads are given during them.");
  done("/w/allocation");
  return r;
}

const HolidaySchema = z.object({ day, name: z.string().trim().min(1).max(80), kind: z.enum(["national", "company"]) });
export async function holidaysImport(rows: z.input<typeof HolidaySchema>[]): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const v = z.array(HolidaySchema).min(1, "Paste at least one holiday.").max(200, "At most 200 holidays at a time.").safeParse(rows);
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the list." };
  const r = await act(() => rpc<number>("holidays_import", { p: v.data }));
  done("/w/allocation");
  return r.ok ? { ...r, notice: `${r.data ?? 0} holidays saved.` } : r;
}

export type SimResult = { leads: number; unassigned: number; by_person: { user_id: string; name: string | null; actual: number; simulated: number }[] };
export async function simulateWith(from: string, to: string, include: number[]): Promise<ActionResult<SimResult>> {
  await assertUser([...ADMIN]);
  const v = z.object({ from: day, to: day, include: z.array(id).max(50) }).safeParse({ from, to, include });
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the dates." };
  return act(() => rpc<SimResult>("simulate", { p_from: v.data.from, p_to: v.data.to, p_include: v.data.include.length ? v.data.include : null }));
}

// ---------- Teams: directory, invitations, devices ----------

/** Sends the sign-in invitation by email and starts its 7-day clock (b2c.invite_sent). */
export async function inviteSend(userId: string): Promise<ActionResult<string>> {
  await assertUser([...ADMIN]);
  const u = uuid.safeParse(userId);
  if (!u.success) return { ok: false, error: "Unknown person." };
  return act(async () => {
    const { data, error } = await adminClient().from("users").select("email, full_name, first_sign_in_at, is_active").eq("user_id", u.data).maybeSingle();
    if (error || !data) throw new Error("Unknown person.");
    if (data.first_sign_in_at) throw new Error("They have already signed in.");
    if (!data.is_active) throw new Error("Make them active first.");
    const expires = await rpc<string>("invite_sent", { p_user: u.data });
    const first = String(data.full_name ?? "").split(" ")[0] || "there";
    const until = new Date(expires).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Kolkata" });
    const sent = await sendMail({
      to: String(data.email), subject: "You are invited to Eduwit Spark",
      text: `Hi ${first},\n\nYou now have an account on Eduwit Spark, Eduwit's B2C CRM. Sign in with your @eduwit.in Google account (or set a password from the sign-in page):\n\n${siteUrl()}/login\n\nThis invitation works until ${until}. After that, ask the Admin to send a new one.\n\nEduwit Spark`,
    });
    if (!sent.sent) throw new Error(`The email could not be sent (email is not set up on the server). The invitation is open until ${until}; tell them to sign in at ${siteUrl()}/login.`);
    done("/w/teams");
    return expires;
  });
}

export type Devices = {
  sessions: { session_id: string; method: string | null; signed_in_at: string; last_seen_at: string | null; user_agent: string | null; ip: string | null; current: boolean }[];
  devices: { id: string; label: string | null; created_at: string; expires_at: string; last_used_at: string | null }[];
};
export async function devicesOf(userId: string): Promise<ActionResult<Devices>> {
  await assertUser([...ADMIN]);
  return act(() => rpc<Devices>("my_devices", { p_user: uuid.parse(userId) }));
}
export async function signOutEverywhere(userId: string): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<number>("session_revoke", { p_session: null, p_device: null, p_user: uuid.parse(userId) }));
  done("/w/teams");
  return r.ok ? { ...r, notice: `Signed out of ${r.data ?? 0} sessions and devices.` } : r;
}
export async function sessionRevoke(userId: string, session: string | null, device: string | null): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<number>("session_revoke", { p_session: session ? uuid.parse(session) : null, p_device: device ? z.string().regex(/^[0-9a-f]{1,16}$/).parse(device) : null, p_user: uuid.parse(userId) }),
    session ? "Signed out." : "Device forgotten.");
  done("/w/teams");
  return r;
}

// ---------- Connectors ----------

export async function waTemplatesImport(): Promise<ActionResult<{ added: number; updated: number }>> {
  await assertUser([...MKT]);
  const r = await importWaTemplates();
  done("/w/connectors", "/w/templates");
  if (!r.ok) return { ok: false, error: r.error };
  return { ok: true, data: { added: r.added, updated: r.updated }, notice: `${r.fetched} templates read from WhatsApp: ${r.added} added, ${r.updated} updated.` };
}

// ---------- Money ----------

export async function invoiceEmail(invoice: number, note: string): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<number>("invoice_send", { p_id: id.parse(invoice), p_note: note.trim().slice(0, 500) || null }), "Queued: the invoice goes to the university's billing email with the PDF.");
  done("/w/money");
  return r;
}
export async function runStatementsEmail(run: number): Promise<ActionResult<number>> {
  await assertUser([...ADMIN]);
  const r = await act(() => rpc<number>("run_statements_send", { p_run: id.parse(run) }));
  done("/w/money");
  return r.ok ? { ...r, notice: `Statements queued for ${r.data ?? 0} counsellors.` } : r;
}

// ---------- Templates ----------

export type TemplateVersion = { version: number; at: string; by: string | null; content: Record<string, unknown> };
export async function templateHistory(kind: "whatsapp" | "email", template: number): Promise<ActionResult<TemplateVersion[]>> {
  await assertUser([...MKT]);
  return act(() => rpc<TemplateVersion[]>("template_history", { p_kind: kind, p_id: id.parse(template) }));
}

export type TestLead = { lead_id: number; name: string | null; course: string | null; university: string | null };
export async function testLeads(): Promise<ActionResult<TestLead[]>> {
  await assertUser([...MKT]);
  return act(async () => {
    const r = await rpc<{ rows: TestLead[] }>("lead_list", { p: { filters: { all: [{ field: "is_test", op: "is_true" }] }, include_test: true, sort: { field: "handed_off_at", dir: "desc" }, limit: 50 } });
    return r.rows.map((l) => ({ lead_id: l.lead_id, name: l.name, course: l.course, university: l.university }));
  });
}

export type Preview = { header?: { type: string; text?: string; example_url?: string } | null; body: string; subject?: string; params?: unknown; buttons?: { type: string; text: string }[] };
export async function templatePreview(kind: "whatsapp" | "email", template: number, lead: number): Promise<ActionResult<Preview>> {
  await assertUser([...MKT]);
  return act(() => rpc<Preview>("template_preview", { p_kind: kind, p_id: id.parse(template), p_lead: id.parse(lead) }));
}

/** Submits a WhatsApp template to Meta with its header (the shared submit reads the header too). */
export async function waTemplateSubmitWithHeader(template: number): Promise<ActionResult> {
  await assertUser([...MKT]);
  const supabase = await createClient();
  const { data: t, error } = await supabase.from("wa_templates").select("id, name, language, category, body, variables, buttons, header").eq("id", id.parse(template)).maybeSingle();
  if (error || !t) return { ok: false, error: "Template not found." };
  const mark = await act(() => rpc("wa_template_submitted", { p_id: t.id }));
  if (!mark.ok) return mark;
  const r = await submitTemplate(t as unknown as TemplateRow);
  done("/w/templates");
  return r.ok ? { ok: true, notice: "Submitted to Meta. Approval usually takes minutes to a day." } : { ok: false, error: r.error ?? "Meta refused it." };
}

/** A marketing email from the block editor: the blocks are kept, the email-safe HTML is what is sent. */
export async function emailBlocksSave(p: { id?: number; name: string; language: string; subject: string; tags: string[]; blocks: Block[]; archived?: boolean }): Promise<ActionResult<number>> {
  await assertUser([...MKT]);
  const v = BlocksSchema.safeParse(p.blocks);
  if (!v.success) return { ok: false, error: v.error.issues[0]?.message ?? "Check the blocks." };
  if (!v.data.length) return { ok: false, error: "Add at least one block." };
  const body = renderBlocks(v.data);
  const r = await act(() => rpc<number>("email_template_m_save", { p: { id: p.id, name: p.name, language: p.language, subject: p.subject, tags: p.tags, body, blocks: v.data, ...(p.archived !== undefined ? { archived: p.archived } : {}) } }), "Template saved.");
  done("/w/templates");
  return r;
}

// ---------- Nurture: campaign replies ----------

export type CampaignReply = { reply_id: number; lead_id: number; name: string | null; channel: string; text: string | null; class: string | null; status: string; at: string; variant: string | null };
export async function campaignReplies(campaign: number): Promise<ActionResult<CampaignReply[]>> {
  await assertUser([...MKT]);
  return act(() => rpc<CampaignReply[]>("campaign_replies", { p_campaign: id.parse(campaign), p_limit: 200 }));
}

// ---------- Guide screenshots ----------

const IMAGE_TYPES: Record<string, string> = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp" };
export type GuideImage = { path: string; caption: string };

/** Uploads one screenshot to the private b2c-guides bucket and adds it to the article (b2c.guide_images_set). */
export async function guideImageAdd(article: number, form: FormData): Promise<ActionResult<GuideImage[]>> {
  await assertUser([...ADMIN]);
  const a = id.safeParse(article);
  const file = form.get("file");
  const caption = String(form.get("caption") ?? "").trim().slice(0, 120);
  if (!a.success) return { ok: false, error: "Unknown article." };
  if (!(file instanceof File) || !file.size) return { ok: false, error: "Choose an image." };
  const ext = IMAGE_TYPES[file.type];
  if (!ext) return { ok: false, error: "PNG, JPEG or WebP only." };
  if (file.size > 2 * 1024 * 1024) return { ok: false, error: "At most 2 MB." };
  return act(async () => {
    const db = adminClient();
    const { data: row, error } = await db.from("user_guides").select("images").eq("id", a.data).maybeSingle();
    if (error || !row) throw new Error("Unknown article.");
    const images = ((row.images ?? []) as GuideImage[]).slice();
    if (images.length >= 12) throw new Error("At most 12 screenshots.");
    const base = (file.name.replace(/\.[^.]*$/, "").toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "") || "screenshot").slice(0, 40);
    const path = `guides/${a.data}/${Date.now().toString(36)}-${base}.${ext}`;
    const up = await db.storage.from("b2c-guides").upload(path, Buffer.from(await file.arrayBuffer()), { contentType: file.type, upsert: false });
    if (up.error) throw new Error(`The image could not be stored: ${up.error.message}`);
    const next = [...images, { path, caption: caption || base }];
    try {
      await rpc("guide_images_set", { p_id: a.data, p_images: next });
    } catch (e) {
      await db.storage.from("b2c-guides").remove([path]);
      throw e;
    }
    done("/w/guide");
    return next;
  }, "Screenshot added.");
}

export async function guideImageRemove(article: number, index: number): Promise<ActionResult<GuideImage[]>> {
  await assertUser([...ADMIN]);
  return act(async () => {
    const a = id.parse(article);
    const db = adminClient();
    const { data: row, error } = await db.from("user_guides").select("images").eq("id", a).maybeSingle();
    if (error || !row) throw new Error("Unknown article.");
    const images = (row.images ?? []) as GuideImage[];
    const gone = images[index];
    if (!gone) throw new Error("Unknown screenshot.");
    const next = images.filter((_, i) => i !== index);
    await rpc("guide_images_set", { p_id: a, p_images: next });
    await db.storage.from("b2c-guides").remove([gone.path]);
    done("/w/guide");
    return next;
  }, "Screenshot removed. Later image numbers move up by one.");
}

// ---------- Analytics: insights on demand ----------

export type InsightItem = { title: string; body: string; metric?: string; spec?: Spec };
export type InsightRow = { id: number; day: string; kind: string; items: InsightItem[] };
export async function insightsNow(): Promise<ActionResult<InsightRow[]>> {
  const me = await assertUser([...MKT]);
  if (!aiConfigured()) return { ok: false, error: "Claude is not connected (ANTHROPIC_API_KEY), so insights cannot be written." };
  try {
    const n = await writeInsights({ roleGroup: me.role === "admin" ? "admin" : "marketing", userId: me.user_id! });
    const rows = await rpc<InsightRow[]>("insights_latest");
    done("/w/analytics");
    return { ok: true, data: rows, notice: n ? `${n} insights written from the last 7 days.` : "Nothing moved enough to write about." };
  } catch (e) {
    return { ok: false, error: friendly(e) };
  }
}
