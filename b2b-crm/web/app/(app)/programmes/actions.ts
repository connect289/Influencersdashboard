"use server";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { assertAdmin } from "@/lib/auth";
import { checkFile, fetchFile, FileProblem, filePathFor, isPartnerFilePath, pickSheet, readSheets, sample, storeFile, toTable, type Ext } from "@/lib/programme-file";
import { FIELDS, normaliseRow, suggestTemplate, type Template } from "@/lib/programmes";
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
export async function createDraft(partnerId: number, input: { path: string; fileName: string; sheet: string; template: Template }): Promise<{ error: string } | { versionId: number }> {
  await assertAdmin();
  const t = TemplateSchema.safeParse(input.template);
  if (!Id.safeParse(partnerId).success || !isPartnerFilePath(partnerId, input.path) || !t.success) return { error: "Invalid request." };
  const template = t.data as Template;
  for (const f of FIELDS) if (f.required && !template[f.key]) return { error: `Choose the column for ${f.label}.` };

  let rows;
  try {
    const ext = input.path.endsWith(".csv") ? "csv" : "xlsx";
    const table = toTable(pickSheet(await readSheets(await fetchFile(input.path), ext), input.sheet));
    for (const f of FIELDS) if (template[f.key] && !table.headers.includes(template[f.key]!)) return { error: `Column “${template[f.key]}” is not in the sheet.` };
    const used = new Set(Object.values(template));
    rows = table.rows.map((r, i) => ({
      row_no: table.rowNumbers[i],
      raw: Object.fromEntries(Object.entries(r).filter(([h]) => used.has(h)).map(([h, v]) => [h, v instanceof Date ? v.toISOString().slice(0, 10) : v])),
      norm: normaliseRow(r, template),
    }));
  } catch (e) {
    return { error: e instanceof FileProblem ? e.message : "The file could not be read." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("programme_version_create", {
    p: { partner_id: partnerId, file_path: input.path, file_name: input.fileName.slice(0, 200), sheet: input.sheet.slice(0, 100), template, rows },
  });
  if (error) return { error: dbMessage(error, "The draft could not be created. Try again.") };
  revalidatePath("/programmes");
  return { versionId: (data as { id: number }).id };
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
