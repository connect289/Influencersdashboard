"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { createHash } from "node:crypto";
import { parseSheetLink, sheetExportUrl } from "@/lib/gsheet";
import { checkFile, fetchFile, FileProblem, filePathFor, isPartnerFilePath, pickSheet, readSheets, sample, storeFile, toTable, type Ext, type Sheet, type Table } from "@/lib/programme-file";
import { FIELDS, MAX_FILE_BYTES, normaliseRow, suggestTemplate, type Template } from "@/lib/programmes";
import type { ProgrammeLabel } from "@/lib/programmes-data";
import { createClient } from "@/lib/supabase/server";

const Id = z.number().int().positive();

/** Messages the b2b.programme_* functions raise for the Admin (22023, P0002) are safe to show; others are generic. */
function dbMessage(error: { code?: string; message: string }, fallback: string): string {
  if (error.code === "22023" || error.code === "P0002") return error.message.charAt(0).toUpperCase() + error.message.slice(1) + ".";
  return fallback;
}

export type Staged = {
  path: string;
  fileName: string;
  sheets: string[];
  sheet: string;
  headers: string[];
  sample: Record<string, string>[];
  rowCount: number;
  template: Template;
  /** Set when the file came from the partner's Google Sheet. */
  source?: "upload" | "gsheet";
  contentHash?: string;
};

async function savedTemplate(partnerId: number): Promise<Template> {
  const supabase = await createClient();
  const { data } = await supabase.schema("b2b").from("partner_programme_sources").select("column_template").eq("partner_id", partnerId).maybeSingle();
  return (data?.column_template ?? {}) as Template;
}

async function describe(partnerId: number, path: string, fileName: string, bytes: Uint8Array, ext: Ext, sheetName?: string): Promise<Staged> {
  const sheets = await readSheets(bytes, ext);
  const sheet = pickSheet(sheets, sheetName);
  const table = toTable(sheet);
  if (table.rows.length === 0) throw new FileProblem(`Sheet “${sheet.name}” has no rows under its header.`);
  return {
    path, fileName, sheets: sheets.map((s) => s.name), sheet: sheet.name, headers: table.headers, sample: sample(table), rowCount: table.rows.length,
    template: suggestTemplate(table.headers, await savedTemplate(partnerId)),
  };
}

/** Step 1: store the partner's file as uploaded and read its columns. */
export async function stageFile(partnerId: number, form: FormData): Promise<{ ok: true; staged: Staged } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success) return { ok: false, error: "Invalid partner." };
  const file = form.get("file");
  if (!(file instanceof File)) return { ok: false, error: "Choose a file." };
  try {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const ext = checkFile(file.name, bytes);
    const path = filePathFor(partnerId, ext);
    const staged = await describe(partnerId, path, file.name.slice(0, 200), bytes, ext);
    await storeFile(path, ext, bytes);
    return { ok: true, staged };
  } catch (e) {
    if (e instanceof FileProblem) return { ok: false, error: e.message };
    console.error("stageFile failed", e instanceof Error ? e.message : e);
    return { ok: false, error: "The file could not be uploaded. Try again." };
  }
}

/** Re-reads a stored file with another sheet. */
export async function switchSheet(partnerId: number, path: string, fileName: string, sheet: string): Promise<{ ok: true; staged: Staged } | { ok: false; error: string }> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success || !isPartnerFilePath(partnerId, path)) return { ok: false, error: "Invalid file." };
  try {
    const ext = path.endsWith(".csv") ? "csv" : "xlsx";
    return { ok: true, staged: await describe(partnerId, path, fileName.slice(0, 200), await fetchFile(path), ext, sheet.slice(0, 100)) };
  } catch (e) {
    return { ok: false, error: e instanceof FileProblem ? e.message : "The sheet could not be read." };
  }
}

const TemplateSchema = z.record(z.enum(FIELDS.map((f) => f.key) as [string, ...string[]]), z.string().max(80));

/** Step 2: apply the column template to every row, normalise, and create a draft version (which matches the rows). */
export async function createDraft(partnerId: number, input: { path: string; fileName: string; sheet: string; template: Template; source?: "upload" | "gsheet"; contentHash?: string }): Promise<{ error: string } | { versionId: number }> {
  await assertAdmin();
  const t = TemplateSchema.safeParse(input.template);
  if (!Id.safeParse(partnerId).success || !isPartnerFilePath(partnerId, input.path) || !t.success) return { error: "Invalid request." };
  const template = t.data as Template;
  for (const f of FIELDS) if (f.required && !template[f.key]) return { error: `Choose the column for ${f.label}.` };

  let rows;
  try {
    const ext = input.path.endsWith(".csv") ? "csv" : "xlsx";
    const table = toTable(pickSheet(await readSheets(await fetchFile(input.path), ext), input.sheet));
    const built = buildRows(table, template);
    if ("error" in built) return built;
    rows = built.rows;
  } catch (e) {
    return { error: e instanceof FileProblem ? e.message : "The file could not be read." };
  }
  const hash = input.source === "gsheet" && /^[0-9a-f]{64}$/.test(input.contentHash ?? "") ? input.contentHash : undefined;
  return saveDraft(partnerId, { path: input.path, fileName: input.fileName, sheet: input.sheet, template, rows, source: input.source === "gsheet" ? "gsheet" : "upload", contentHash: hash });
}

/** The template applied to every row: what the file said (only mapped columns) and the normalised values. */
function buildRows(table: Table, template: Template): { error: string } | { rows: { row_no: number | undefined; raw: Record<string, unknown>; norm: unknown }[] } {
  for (const f of FIELDS) if (template[f.key] && !table.headers.includes(template[f.key]!)) return { error: `Column “${template[f.key]}” is not in the sheet.` };
  const used = new Set(Object.values(template));
  return {
    rows: table.rows.map((r, i) => ({
      row_no: table.rowNumbers[i],
      raw: Object.fromEntries(Object.entries(r).filter(([h]) => used.has(h)).map(([h, v]) => [h, v instanceof Date ? v.toISOString().slice(0, 10) : v])),
      norm: normaliseRow(r, template),
    })),
  };
}

async function saveDraft(partnerId: number, d: { path: string; fileName: string; sheet: string; template: Template; rows: unknown[]; source: "upload" | "gsheet"; contentHash?: string }):
  Promise<{ error: string } | { versionId: number }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("programme_version_create", {
    p: { partner_id: partnerId, file_path: d.path, file_name: d.fileName.slice(0, 200), sheet: d.sheet.slice(0, 100), template: d.template, rows: d.rows,
         source: d.source, content_hash: d.contentHash ?? null },
  });
  if (error) return { error: dbMessage(error, "The draft could not be created. Try again.") };
  revalidatePath("/programmes");
  return { versionId: (data as { id: number }).id };
}

// ---------- Google Sheet source ----------

const SHEET_TIMEOUT_MS = 20_000;

/** A stable fingerprint of the tab's content (headers and cell values), so an unchanged sheet is not drafted again. */
function tableHash(table: Table): string {
  const cells = table.rows.map((r) => table.headers.map((h) => { const v = r[h]; return v instanceof Date ? v.toISOString() : v ?? null; }));
  return createHash("sha256").update(JSON.stringify([table.headers, cells])).digest("hex");
}

/** Downloads the sheet as Excel. A sheet that is not shared comes back as Google's sign-in page, not a workbook. */
async function downloadSheet(sheetId: string): Promise<Uint8Array> {
  let res: Response;
  try {
    res = await fetch(sheetExportUrl(sheetId), { redirect: "follow", cache: "no-store", signal: AbortSignal.timeout(SHEET_TIMEOUT_MS) });
  } catch {
    throw new FileProblem("Google did not answer. Try again in a minute.");
  }
  if (res.status === 404) throw new FileProblem("The sheet was not found. Check the link.");
  if (!res.ok) throw new FileProblem(`Google refused the download (HTTP ${res.status}). Check that the sheet is shared with “anyone with the link”.`);
  const type = res.headers.get("content-type") ?? "";
  if (!type.includes("spreadsheetml")) throw new FileProblem("The sheet is not shared. In Google Sheets: Share → General access → Anyone with the link → Viewer.");
  const length = Number(res.headers.get("content-length") ?? 0);
  if (length > MAX_FILE_BYTES) throw new FileProblem("The sheet is larger than 4 MB.");
  return new Uint8Array(await res.arrayBuffer());
}

export type SheetState = { errors?: Record<string, string>; error?: string; ok?: number } | undefined;

export async function connectSheet(partnerId: number, _prev: SheetState, form: FormData): Promise<SheetState> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success) return { error: "Invalid partner." };
  const id = parseSheetLink(String(form.get("link") ?? ""));
  const hours = z.coerce.number().int().min(1).max(168).safeParse(form.get("every") ?? 6);
  const tab = String(form.get("tab") ?? "").trim().slice(0, 100);
  const errors: Record<string, string> = {};
  if (!id) errors.link = "Paste the sheet's link from the browser's address bar";
  if (!hours.success) errors.every = "1 to 168 hours";
  if (Object.keys(errors).length) return { errors, error: "Check the highlighted fields." };
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("programme_sheet_save", { p_partner_id: partnerId, p_sheet_id: id, p_tab: tab || null, p_every_hours: hours.data });
  if (error) return { error: dbMessage(error, "Could not save the sheet. Try again.") };
  revalidatePath(`/programmes/${partnerId}`);
  return { ok: Date.now() };
}

export async function disconnectSheet(partnerId: number): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success) return "Invalid partner.";
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("programme_sheet_disconnect", { p_partner_id: partnerId });
  if (error) return dbMessage(error, "Could not disconnect. Try again.");
  revalidatePath(`/programmes/${partnerId}`);
}

export type SyncResult =
  | { status: "unchanged" }
  | { status: "draft"; versionId: number }
  | { status: "needs_mapping"; staged: Staged }
  | { status: "error"; error: string };

/**
 * Reads the partner's sheet now. Unchanged since the last draft: only the check time is recorded. Changed, with a saved
 * template that still fits: a draft is created for review. Otherwise the Admin maps the columns, as for an upload.
 */
export async function syncSheet(partnerId: number, force = false): Promise<SyncResult> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success) return { status: "error", error: "Invalid partner." };
  const supabase = await createClient();
  const { data: src } = await supabase.schema("b2b").from("partner_programme_sources")
    .select("type, sheet_id, tab, column_template, content_hash").eq("partner_id", partnerId).maybeSingle();
  if (!src || src.type !== "gsheet" || !src.sheet_id) return { status: "error", error: "Connect the Google Sheet first." };
  const fail = async (message: string): Promise<SyncResult> => {
    await supabase.schema("b2b").rpc("programme_sheet_checked", { p_partner_id: partnerId, p_error: message });
    revalidatePath(`/programmes/${partnerId}`);
    return { status: "error", error: message };
  };

  let bytes: Uint8Array, table: Table, sheets: Sheet[], sheet: Sheet;
  try {
    bytes = await downloadSheet(src.sheet_id);
    checkFile("sheet.xlsx", bytes);
    sheets = await readSheets(bytes, "xlsx");
    sheet = pickSheet(sheets, src.tab);
    if (src.tab && sheet.name !== src.tab) return fail(`The tab “${src.tab}” is no longer in the sheet.`);
    table = toTable(sheet);
    if (table.rows.length === 0) return fail(`Tab “${sheet.name}” has no rows under its header.`);
  } catch (e) {
    return fail(e instanceof FileProblem ? e.message : "The sheet could not be read.");
  }

  const hash = tableHash(table);
  if (hash === src.content_hash && !force) {
    await supabase.schema("b2b").rpc("programme_sheet_checked", { p_partner_id: partnerId, p_error: null });
    revalidatePath(`/programmes/${partnerId}`);
    return { status: "unchanged" };
  }

  const path = filePathFor(partnerId, "xlsx");
  try { await storeFile(path, "xlsx", bytes); } catch { return fail("The sheet could not be stored. Try again."); }
  const fileName = `Google Sheet · ${sheet.name}`;
  const saved = (src.column_template ?? {}) as Template;
  const fits = FIELDS.every((f) => !f.required || (saved[f.key] && table.headers.includes(saved[f.key]!)))
    && Object.values(saved).every((c) => !c || table.headers.includes(c));
  if (fits) {
    const built = buildRows(table, saved);
    if ("error" in built) return fail(built.error);
    const res = await saveDraft(partnerId, { path, fileName, sheet: sheet.name, template: saved, rows: built.rows, source: "gsheet", contentHash: hash });
    return "error" in res ? fail(res.error) : { status: "draft", versionId: res.versionId };
  }
  return {
    status: "needs_mapping",
    staged: { path, fileName, sheets: sheets.map((s) => s.name), sheet: sheet.name, headers: table.headers, sample: sample(table), rowCount: table.rows.length,
              template: suggestTemplate(table.headers, saved), source: "gsheet", contentHash: hash },
  };
}

const Action = z.enum(["approve", "match", "ignore", "request", "reopen"]);

export async function reviewRow(rowId: number, action: string, programmeId?: number | null, reason?: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ rowId: Id, action: Action, programmeId: Id.nullish(), reason: z.string().max(300).optional() }).safeParse({ rowId, action, programmeId, reason });
  if (!p.success) return "Invalid request.";
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("programme_row_review", {
    p_row_id: p.data.rowId, p_action: p.data.action, p_programme_id: p.data.programmeId ?? null, p_reason: p.data.reason ?? null,
  });
  if (error) return dbMessage(error, "Could not save. Try again.");
}

export async function approveRows(versionId: number, rowIds: number[]): Promise<{ approved: number } | { error: string }> {
  await assertAdmin();
  const p = z.object({ versionId: Id, rowIds: z.array(Id).min(1).max(5000) }).safeParse({ versionId, rowIds });
  if (!p.success) return { error: "Invalid request." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("programme_rows_approve", { p_version_id: p.data.versionId, p_row_ids: p.data.rowIds });
  if (error) return { error: dbMessage(error, "Could not approve. Try again.") };
  return { approved: data as number };
}

export async function publishVersion(partnerId: number, versionId: number, note: string): Promise<string | void> {
  await assertAdmin();
  const p = z.object({ partnerId: Id, versionId: Id, note: z.string().max(500) }).safeParse({ partnerId, versionId, note });
  if (!p.success) return "Invalid request.";
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("programme_version_publish", { p_version_id: p.data.versionId, p_note: p.data.note || null });
  if (error) return dbMessage(error, "Could not publish. Try again.");
  revalidatePath("/programmes");
  revalidatePath(`/partners/${partnerId}`);
  revalidatePath(`/programmes/${partnerId}`);
}

/** Whether the commission % in this partner's sheet includes GST; its programme rates follow at once. */
export async function setCommissionGst(partnerId: number, includesGst: boolean): Promise<{ created: number } | { error: string }> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success || typeof includesGst !== "boolean") return { error: "Invalid request." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("programme_commission_gst_save", { p_partner_id: partnerId, p_includes_gst: includesGst });
  if (error) return { error: dbMessage(error, "Could not save. Try again.") };
  revalidatePath(`/programmes/${partnerId}`);
  revalidatePath("/routing");
  return { created: Number((data as { created?: number } | null)?.created ?? 0) };
}

export async function discardVersion(partnerId: number, versionId: number): Promise<string | void> {
  await assertAdmin();
  if (!Id.safeParse(partnerId).success || !Id.safeParse(versionId).success) return "Invalid request.";
  const supabase = await createClient();
  const { error } = await supabase.schema("b2b").rpc("programme_version_discard", { p_version_id: versionId });
  if (error) return dbMessage(error, "Could not discard. Try again.");
  revalidatePath("/programmes");
  revalidatePath(`/programmes/${partnerId}`);
}

export async function searchCatalogue(universityId: number | null, q: string): Promise<ProgrammeLabel[]> {
  await assertAdmin();
  const p = z.object({ universityId: Id.nullable(), q: z.string().max(100) }).safeParse({ universityId, q });
  if (!p.success) return [];
  const supabase = await createClient();
  const { data } = await supabase.schema("b2b").rpc("catalogue_search", { p_university_id: p.data.universityId, p_q: p.data.q });
  return (data ?? []) as ProgrammeLabel[];
}
