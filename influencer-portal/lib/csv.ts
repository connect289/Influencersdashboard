// RFC 4180 CSV: parse (quotes, escaped quotes, CRLF/LF, BOM, quoted newlines) and write (with spreadsheet formula
// neutralising, so exported cells starting with = + - @ can't run as formulas in Excel or Sheets).

export interface ParsedCsv {
  headers: string[];
  rows: string[][];
}

export class CsvError extends Error {}

export function parseCsv(text: string, opts: { maxRows?: number } = {}): ParsedCsv {
  const maxRows = opts.maxRows ?? 10_000;
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  const records: string[][] = [];
  let field = "";
  let record: string[] = [];
  let inQuotes = false;
  let i = 0;
  const endRecord = () => {
    record.push(field);
    field = "";
    if (!(record.length === 1 && record[0] === "")) records.push(record);
    record = [];
    if (records.length > maxRows + 1) throw new CsvError(`too_many_rows`);
  };
  while (i < src.length) {
    const c = src.charAt(i);
    if (inQuotes) {
      if (c === '"') {
        if (src[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field += c;
      i++;
      continue;
    }
    if (c === '"' && field === "") {
      inQuotes = true;
      i++;
    } else if (c === ",") {
      record.push(field);
      field = "";
      i++;
    } else if (c === "\r" || c === "\n") {
      endRecord();
      i += c === "\r" && src[i + 1] === "\n" ? 2 : 1;
    } else {
      field += c;
      i++;
    }
  }
  if (inQuotes) throw new CsvError("unterminated_quote");
  if (field !== "" || record.length > 0) endRecord();
  const [head, ...rows] = records;
  if (!head) throw new CsvError("empty");
  return { headers: head.map((h) => h.trim()), rows };
}

function cell(v: unknown, delimiter = ","): string {
  let s =
    typeof v === "string"
      ? v
      : typeof v === "number" || typeof v === "boolean"
        ? String(v)
        : v === null || v === undefined
          ? ""
          : JSON.stringify(v);
  // A plain number ("-100.50") cannot run as a formula; anything else starting with a formula character is quoted.
  if (/^[=+\-@\t\r]/.test(s) && !/^-\d+(\.\d+)?$/.test(s)) s = `'${s}`;
  return /["\r\n]/.test(s) || s.includes(delimiter) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function toCsv(headers: string[], rows: unknown[][]): string {
  return toDelimited(headers, rows, ",");
}

/** Delimited text with any single-character delimiter (bank bulk-upload formats); `headers` null omits the header. */
export function toDelimited(headers: string[] | null, rows: unknown[][], delimiter: string): string {
  const lines = headers ? [headers, ...rows] : rows;
  return lines.map((r) => r.map((v) => cell(v, delimiter)).join(delimiter)).join("\r\n") + "\r\n";
}
