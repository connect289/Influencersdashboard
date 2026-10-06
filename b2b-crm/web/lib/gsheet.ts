/** Google Sheet links for partner programme files. The sheet must be shared as "anyone with the link can view". */

/** The spreadsheet ID from a sheet link (or a bare ID), or null. */
export function parseSheetLink(input: string): string | null {
  const s = input.trim();
  const m = s.match(/docs\.google\.com\/spreadsheets\/(?:u\/\d+\/)?d\/([A-Za-z0-9_-]{25,100})/);
  if (m?.[1]) return m[1];
  return /^[A-Za-z0-9_-]{25,100}$/.test(s) ? s : null;
}

/** The whole spreadsheet as Excel: every tab, so the Admin can choose one. */
export const sheetExportUrl = (id: string) => `https://docs.google.com/spreadsheets/d/${encodeURIComponent(id)}/export?format=xlsx`;

/** Where the Admin opens the sheet itself. */
export const sheetViewUrl = (id: string) => `https://docs.google.com/spreadsheets/d/${encodeURIComponent(id)}/edit`;

/** Whether a check is due, from the last check and the interval in hours. */
export function sheetDue(lastCheckedAt: string | null, everyHours: number, now = Date.now()): boolean {
  return !lastCheckedAt || now - Date.parse(lastCheckedAt) >= everyHours * 3_600_000;
}
