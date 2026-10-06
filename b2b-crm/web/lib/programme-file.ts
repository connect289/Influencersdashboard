import "server-only";
import readXlsxFile from "read-excel-file/node";
import { adminClient } from "@/lib/supabase/admin";
import {
  cellText, findHeaderRow, headerNames, isBlankRow, MAX_COLS, MAX_FILE_BYTES, MAX_ROWS, MAX_UNZIPPED_BYTES, parseCsv, zipUncompressedSize,
  type Cell,
} from "@/lib/programmes";

/**
 * Partner programme files: validated, stored as uploaded in the private bucket (path `<partner>/<uuid>.<ext>`, which
 * b2b.programme_version_create also checks), and parsed on the server. Callers have already run assertAdmin().
 */

export const BUCKET = "b2b-programme-files";
const CONTENT_TYPE = { xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", csv: "text/csv" } as const;
export type Ext = keyof typeof CONTENT_TYPE;

export class FileProblem extends Error {}

export const filePathFor = (partnerId: number, ext: Ext) => `${partnerId}/${crypto.randomUUID()}.${ext}`;
export const isPartnerFilePath = (partnerId: number, path: string) => new RegExp(`^${partnerId}/[0-9a-f-]{36}\\.(xlsx|csv)$`).test(path);

/** Checks size, extension and content (an .xlsx must be a zip whose contents stay small); returns the type. */
export function checkFile(name: string, bytes: Uint8Array): Ext {
  if (bytes.length === 0) throw new FileProblem("The file is empty.");
  if (bytes.length > MAX_FILE_BYTES) throw new FileProblem("The file is larger than 4 MB.");
  const ext = name.toLowerCase().split(".").pop();
  if (ext === "xls") throw new FileProblem("Old .xls files cannot be read. Open it in Excel and save it as .xlsx or CSV.");
  if (ext === "xlsx") {
    const size = zipUncompressedSize(bytes);
    if (size === null) throw new FileProblem("This is not a valid .xlsx file.");
    if (size > MAX_UNZIPPED_BYTES) throw new FileProblem("This workbook is too large to read.");
    return "xlsx";
  }
  if (ext === "csv") {
    if (bytes.subarray(0, 4096).includes(0)) throw new FileProblem("This is not a text CSV file.");
    return "csv";
  }
  throw new FileProblem("Upload an .xlsx or .csv file.");
}

export async function storeFile(path: string, ext: Ext, bytes: Uint8Array): Promise<void> {
  const { error } = await adminClient().storage.from(BUCKET).upload(path, bytes, { contentType: CONTENT_TYPE[ext], upsert: false });
  if (error) throw new Error(`storage upload failed: ${error.message}`);
}

export async function fetchFile(path: string): Promise<Uint8Array> {
  const { data, error } = await adminClient().storage.from(BUCKET).download(path);
  if (error || !data) throw new FileProblem("The uploaded file could not be read again. Upload it once more.");
  return new Uint8Array(await data.arrayBuffer());
}

export type Sheet = { name: string; rows: Cell[][] };

/** Every sheet of the workbook (or the CSV as one sheet), capped at MAX_ROWS data rows and MAX_COLS columns. */
export async function readSheets(bytes: Uint8Array, ext: Ext): Promise<Sheet[]> {
  const cap = (rows: Cell[][]) => rows.slice(0, MAX_ROWS + 20).map((r) => r.slice(0, MAX_COLS));
  if (ext === "csv") return [{ name: "CSV", rows: cap(parseCsv(new TextDecoder("utf-8").decode(bytes))) }];
  try {
    const sheets = await readXlsxFile(Buffer.from(bytes));
    return sheets.map((s) => ({ name: s.sheet.slice(0, 100), rows: cap(s.data as unknown as Cell[][]) }));
  } catch {
    throw new FileProblem("This workbook could not be read. Save it again from Excel and retry.");
  }
}

export type Table = { headers: string[]; rows: Record<string, Cell>[]; rowNumbers: number[] };

/** The sheet as header names plus data rows (blank rows dropped), with the spreadsheet row number of each. */
export function toTable(sheet: Sheet): Table {
  const h = findHeaderRow(sheet.rows);
  const headers = headerNames(sheet.rows[h] ?? []);
  const rows: Record<string, Cell>[] = [];
  const rowNumbers: number[] = [];
  for (let i = h + 1; i < sheet.rows.length && rows.length < MAX_ROWS; i++) {
    const r = sheet.rows[i] ?? [];
    if (isBlankRow(r)) continue;
    rows.push(Object.fromEntries(headers.map((name, c) => [name, r[c] ?? null])));
    rowNumbers.push(i + 1);
  }
  return { headers, rows, rowNumbers };
}

/** Plain-text sample rows for the column-mapping preview. */
export const sample = (t: Table, n = 6) => t.rows.slice(0, n).map((r) => Object.fromEntries(t.headers.map((h) => [h, cellText(r[h]).slice(0, 80)])));

/** The first sheet that has data, or the named one. */
export function pickSheet(sheets: Sheet[], name?: string | null): Sheet {
  const named = name ? sheets.find((s) => s.name === name) : undefined;
  const sheet = named ?? sheets.find((s) => s.rows.some((r) => !isBlankRow(r))) ?? sheets[0];
  if (!sheet) throw new FileProblem("The file has no sheets.");
  return sheet;
}
