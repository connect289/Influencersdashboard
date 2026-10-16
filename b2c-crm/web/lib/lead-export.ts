import { toCsv } from "@/lib/csv";
import { toXlsx, XLSX_TYPE } from "@/lib/xlsx";
import { fieldDef } from "@/lib/viewFields";

// What a leads export holds (spec B10.5): the view's own columns, else the standard set; CSV or Excel. Shared by the
// inline download (app/w/leads/export) and the background job (lib/lead-jobs.ts).

export const EXPORT_COLUMNS = ["lead_id", "name", "phone", "email", "city", "state", "language", "course", "specialization", "university", "programme_level", "study_mode",
  "qualification", "source", "campaign", "created_at", "lane", "status", "stage", "sub_stage", "temperature", "score", "owner_name", "handoff_reason", "partner",
  "partner_lost_reason", "partner_consent_state", "marketing_consent", "opted_out", "handed_off_at", "assigned_at", "first_contacted_at", "last_contacted_at",
  "contact_attempts", "calls_logged", "last_call_outcome", "next_task_due_at", "journey", "application_status", "enrollment_status", "tags", "is_test"];

export type ExportFormat = "csv" | "xlsx";

/** The view's columns (lead_id always first), else the standard set. Unknown names are dropped. */
export function exportColumns(viewColumns: unknown): string[] {
  const cols = Array.isArray(viewColumns) ? viewColumns.filter((c): c is string => typeof c === "string" && !!fieldDef(c)) : [];
  if (cols.length === 0) return EXPORT_COLUMNS;
  return ["lead_id", ...cols.filter((c) => c !== "lead_id")];
}

export function exportFile(format: ExportFormat, columns: string[], rows: Record<string, unknown>[]): { body: Uint8Array | string; type: string; ext: string } {
  if (format === "xlsx") return { body: toXlsx(columns, rows, "Leads"), type: XLSX_TYPE, ext: "xlsx" };
  return { body: toCsv(columns, rows), type: "text/csv; charset=utf-8", ext: "csv" };
}
