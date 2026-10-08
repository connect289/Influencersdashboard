"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { CHUNK_ROWS, CONSENT_CHANNELS, IMPORT_FIELDS, type ConsentText, type ConsentTextForm, type CourseMatch, type ImportPreview, type Mapping } from "@/lib/intake";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();
const FieldKey = z.enum(IMPORT_FIELDS.map((f) => f.key) as [string, ...string[]]);
const MappingSchema = z.record(z.string().max(80), z.union([FieldKey, z.literal("ignore")]));
const Purpose = z.enum(["sales", "partner_share", "marketing"]);
const Purposes = z.array(Purpose).max(3);
/** A registered consent_texts.version (1–80 chars, no control characters); "" means none. */
const ConsentVersion = z.string().trim().max(80).regex(/^[^\u0000-\u001f\u007f]*$/, "The version id has unusual characters.");

type Result<T = undefined> = { ok: true; data: T } | { ok: false; error: string };

/** Messages raised by the b2b functions for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}

async function call<T>(fn: string, args: Record<string, unknown> | undefined, fallback: string): Promise<Result<T>> {
  await assertAdmin();
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) return { ok: false, error: dbMessage(error, fallback) };
  return { ok: true, data: data as T };
}

const refresh = () => { revalidatePath("/intake"); revalidatePath("/pool"); };

// ---------- import wizard ----------
export async function createImport(fileName: string, mapping: Mapping, template: { name?: string; id?: number }): Promise<Result<number>> {
  const m = MappingSchema.safeParse(mapping);
  if (!m.success || !z.string().trim().min(1).max(200).safeParse(fileName).success) return { ok: false, error: "The file or its mapping is not valid." };
  return call<number>("import_create", { p: { file_name: fileName, mapping: m.data, template_name: template.name?.trim() || undefined, template_id: template.id } },
    "Could not start the import. Try again.");
}

const Row = z.record(z.string().max(80), z.string().max(2000));
export async function stageRows(importId: number, startRow: number, rows: Record<string, string>[]): Promise<Result<{ staged: number; total: number }>> {
  if (!Id.safeParse(importId).success || !Id.safeParse(startRow).success || !z.array(Row).max(CHUNK_ROWS).safeParse(rows).success) {
    return { ok: false, error: "These rows are not valid." };
  }
  return call("import_stage_rows", { p_import_id: importId, p_start_row: startRow, p_rows: rows }, "Could not upload the rows. Try again.");
}

export async function importCourses(importId: number): Promise<Result<CourseMatch[]>> {
  if (!Id.safeParse(importId).success) return { ok: false, error: "Invalid import." };
  return call("import_courses", { p_import_id: importId }, "Could not match the courses. Try again.");
}

export async function setImportCourse(importId: number, text: string, courseKey: string | null): Promise<Result<null>> {
  if (!Id.safeParse(importId).success || !z.string().max(500).safeParse(text).success) return { ok: false, error: "Invalid course." };
  return call("import_set_course", { p_import_id: importId, p_text: text, p_course_key: courseKey }, "Could not save the course. Try again.");
}

export async function importPreview(importId: number): Promise<Result<ImportPreview>> {
  if (!Id.safeParse(importId).success) return { ok: false, error: "Invalid import." };
  return call("import_preview", { p_import_id: importId }, "Could not read the import. Try again.");
}

export async function importRowsPage(importId: number, preview: string | null, after: number): Promise<Result<Record<string, unknown>[]>> {
  if (!Id.safeParse(importId).success || !z.number().int().min(0).safeParse(after).success) return { ok: false, error: "Invalid import." };
  return call("import_rows_page", { p_import_id: importId, p_preview: preview, p_after: after }, "Could not read the rows. Try again.");
}

/**
 * Step 5 of the wizard. 'route' no longer needs partner sharing (D39: students without it are asked, rate-limited); the wording is
 * registered as consent text 'import:<id>', covering admission partners only when the Admin says so together with partner_share.
 */
const CommitSchema = z.object({
  source_label: z.string().trim().min(2, "Give a source label.").max(60),
  campaign: z.string().trim().max(120).optional(),
  routing_choice: z.enum(["route", "hold", "b2c"]),
  b2c_lane: z.enum(["sales", "nurture"]).optional(),
  consent: z.object({
    where: z.string().trim().min(3, "Say where the students agreed.").max(300), when: z.string().min(8).max(40),
    text: z.string().trim().min(10, "Give the consent text the students saw (at least 10 characters).").max(2000), purposes: Purposes,
    covers_admission_partners: z.boolean().optional(),
  }),
});
export type CommitForm = z.input<typeof CommitSchema>;
/** import_commit / import_continue / import_process result (m31h adds recorded_not_passed: blocked or invalid rows written as Not passed). */
export type ImportProgress = { processed: number; left: number; status: string; recorded_not_passed?: number };

export async function commitImport(importId: number, f: CommitForm): Promise<Result<ImportProgress>> {
  const p = CommitSchema.safeParse(f);
  if (!Id.safeParse(importId).success) return { ok: false, error: "Invalid import." };
  if (!p.success) return { ok: false, error: p.error.issues[0]?.message ?? "Check the form." };
  const r = await call<ImportProgress>("import_commit", { p_import_id: importId, p: p.data }, "Could not start the import. Try again.");
  if (r.ok) refresh();
  return r;
}

export async function continueImport(importId: number): Promise<Result<ImportProgress>> {
  if (!Id.safeParse(importId).success) return { ok: false, error: "Invalid import." };
  const r = await call<ImportProgress>("import_continue", { p_import_id: importId }, "Could not continue the import. It carries on in the background.");
  if (r.ok && r.data.status === "done") refresh();
  return r;
}

export async function rollbackImport(importId: number, note: string): Promise<string | void> {
  if (!Id.safeParse(importId).success) return "Invalid import.";
  const r = await call<{ deleted: number; kept: number }>("import_rollback", { p_import_id: importId, p_note: note }, "Could not roll back. Try again.");
  if (!r.ok) return r.error;
  refresh();
}

export async function abandonImport(importId: number): Promise<string | void> {
  if (!Id.safeParse(importId).success) return "Invalid import.";
  const r = await call("import_abandon", { p_import_id: importId }, "Could not abandon the import. Try again.");
  if (!r.ok) return r.error;
  refresh();
}

/** Releases held leads: every held lead of an import, or the given leads. They route on the next run. */
export async function releaseHeld(importId: number | null, leadIds: number[] | null): Promise<Result<number>> {
  if (importId !== null && !Id.safeParse(importId).success) return { ok: false, error: "Invalid import." };
  if (leadIds !== null && !z.array(Id).max(5000).safeParse(leadIds).success) return { ok: false, error: "Invalid leads." };
  const r = await call<number>("intake_release", { p_import_id: importId, p_lead_ids: leadIds }, "Could not release the leads. Try again.");
  if (r.ok) refresh();
  return r;
}

// ---------- requests ----------
export async function retryRequest(id: number): Promise<string | void> {
  if (!Id.safeParse(id).success) return "Invalid request.";
  const r = await call("intake_request_retry", { p_id: id }, "Could not retry. Try again.");
  if (!r.ok) return r.error;
  refresh();
}

export async function discardRequest(id: number, reason: string): Promise<string | void> {
  if (!Id.safeParse(id).success) return "Invalid request.";
  const r = await call("intake_request_discard", { p_id: id, p_reason: reason }, "Could not discard. Try again.");
  if (!r.ok) return r.error;
  refresh();
}

// ---------- manual entry ----------
const Opt = z.string().trim().max(500).optional();
/**
 * b2b.intake_manual(p). lead.other_courses is comma-separated text (D30: secondary interests, up to 9); consent_version names a
 * registered consent text so a manual partner-sharing tick counts (D8) — without one the stamp is 'manual:<where>' and uncovered.
 */
const ManualSchema = z.object({
  lead: z.object({
    full_name: z.string().trim().min(2, "Give the student's name.").max(120), phone: z.string().trim().min(8, "Give the phone number.").max(20),
    email: z.union([z.literal(""), z.email("Not a valid email.")]).optional(), city: Opt, state: Opt, course: Opt, specialization: Opt, university: Opt,
    programme_level: Opt, other_courses: z.string().trim().max(1200, "Up to 9 other courses, comma-separated.").optional(),
    highest_qualification: Opt, work_experience: Opt, notes: z.string().trim().max(2000).optional(),
  }),
  source: z.string().trim().max(60).optional(), campaign: z.string().trim().max(120).optional(),
  route: z.enum(["route", "hold", "b2c"]), b2c_lane: z.enum(["sales", "nurture"]).optional(),
  consent_purposes: Purposes, consent_where: z.string().trim().min(3, "Say how the student agreed.").max(80), consent_version: ConsentVersion.optional(),
  note: z.string().trim().max(300).optional(),
});
export type ManualForm = z.input<typeof ManualSchema>;

/** intake_lead's routing block (m31h): outlook values are lib/intake ROUTE_OUTLOOKS. */
export type ManualRouting = { status: string; destination?: string | null; outlook: string; outlook_reason?: string | null; outlook_lane?: string | null; waiting_for: string[]; missing?: string[] };
export type ManualResult = { lead_id: number; action: string; is_test?: boolean; warnings?: string[]; outlook?: string | null; interests_added?: number; routing: ManualRouting };

export async function enterLead(f: ManualForm): Promise<({ ok: true } & ManualResult) | { ok: false; error: string; errors?: Record<string, string> }> {
  const p = ManualSchema.safeParse(f);
  if (!p.success) {
    const errors: Record<string, string> = {};
    for (const i of p.error.issues) errors[i.path.join(".")] ??= i.message;
    return { ok: false, error: "Check the highlighted fields.", errors };
  }
  const lead = Object.fromEntries(Object.entries(p.data.lead).filter(([, v]) => v));
  const { consent_version, ...rest } = p.data;
  const r = await call<ManualResult>("intake_manual", { p: { ...rest, lead, ...(consent_version ? { consent_version } : {}) } }, "Could not save the lead. Try again.");
  if (!r.ok) return r;
  refresh();
  return { ok: true, ...r.data, warnings: r.data.warnings ?? [] };
}

// ---------- forms and connections ----------
/**
 * b2b.lead_form_save(p). consent_checkbox_map pairs a Meta checkbox key with the purpose it ticks (m31h: stamped only when the
 * checkbox is required or ticked in the Graph answer). partner_share, as a purpose or in the map, needs a covering consent_version
 * (D8: 22023 'register the consent text that names our admission partners (edtech companies) first').
 */
const FormSchema = z.object({
  platform: z.enum(["meta", "google"]),
  form_ref: z.string().trim().regex(/^[A-Za-z0-9_.:-]{1,80}$/, "Use the form ID the platform shows."),
  name: z.string().trim().min(2, "Give the form a name.").max(120),
  page_ref: z.string().trim().max(80).optional(),
  field_map: z.record(z.string().trim().min(1).max(120), z.union([FieldKey, z.literal("ignore")])),
  defaults: z.partialRecord(z.enum(["course", "specialization", "university", "programme_level", "study_mode", "campaign"]), z.string().trim().max(200)),
  campaign: z.string().trim().max(120).optional(),
  consent_text: z.string().trim().max(2000).optional(), consent_version: ConsentVersion.optional(),
  consent_purposes: Purposes.min(1), active: z.boolean(),
  consent_checkbox_map: z.record(z.string().trim().min(1, "A checkbox key is missing.").max(120, "Checkbox keys are 1 to 120 characters."),
    z.object({ purpose: Purpose, required: z.boolean() })).optional(),
});
export type FormForm = z.input<typeof FormSchema>;

export async function saveForm(f: FormForm): Promise<string | void> {
  const p = FormSchema.safeParse(f);
  if (!p.success) return p.error.issues[0]?.message ?? "Check the form.";
  const defaults = Object.fromEntries(Object.entries(p.data.defaults).filter(([, v]) => v));
  const r = await call("lead_form_save", { p: { ...p.data, defaults, consent_checkbox_map: p.data.consent_checkbox_map ?? {} } }, "Could not save the form. Try again.");
  if (!r.ok) return r.error;
  refresh();
}

// ---------- consent texts (rulebook PART 7.1, D8, D10) ----------
const ConsentTextSchema = z.object({
  version: ConsentVersion.min(1, "Give a version id."),
  channel: z.enum(CONSENT_CHANNELS.map((c) => c.key) as [string, ...string[]], "Choose the channel."),
  purposes: Purposes.min(1, "Tick at least one purpose."),
  body: z.string().trim().max(4000, "The wording is longer than 4,000 characters."),
  covers_admission_partners: z.boolean(),
  active: z.boolean(),
  lawyer_approved: z.boolean().optional(),
  approval_note: z.string().trim().max(1000).optional(),
});
const Reason = z.string().trim().min(3, "Give a reason for the change (at least 3 characters).").max(300);

/**
 * b2b.consent_text_save(p, p_reason): creates or updates a consent text and returns the row. The function refuses (22023) an
 * approval without a 10-character note or without a body, and covers=true without a body or the partner_share purpose; changing
 * the body or the covering flag of an approved text clears the approval unless it is re-approved in the same save. Revalidates the
 * routing and home pages too: the lawyer's approval is a go-live item (D10).
 */
export async function saveConsentText(f: ConsentTextForm, reason: string): Promise<Result<ConsentText>> {
  const p = ConsentTextSchema.safeParse(f);
  if (!p.success) return { ok: false, error: p.error.issues[0]?.message ?? "Check the form." };
  const why = Reason.safeParse(reason);
  if (!why.success) return { ok: false, error: why.error.issues[0]?.message ?? "Give a reason." };
  const body = { ...p.data, body: p.data.body || null, approval_note: p.data.approval_note || undefined };
  const r = await call<ConsentText>("consent_text_save", { p: body, p_reason: why.data }, "Could not save the consent text. Try again.");
  if (r.ok) { refresh(); revalidatePath("/routing"); revalidatePath("/"); }
  return r;
}

const Secret = z.string().trim().max(500).optional();
const ConnSchema = z.object({
  meta: z.object({ verify_token: Secret, app_secret: Secret, page_token: z.string().trim().max(1000).optional(), api_version: z.string().trim().max(10).optional() }),
  google: z.object({ key: Secret }),
});
export type ConnForm = z.input<typeof ConnSchema>;

/** Secrets go to Vault and are never read back; empty fields leave a secret unchanged. */
export async function saveConnections(f: ConnForm): Promise<string | void> {
  const p = ConnSchema.safeParse(f);
  if (!p.success) return "Check the fields.";
  const r = await call("intake_settings_save", { p: p.data }, "Could not save. Try again.");
  if (!r.ok) return r.error;
  refresh();
}
