/**
 * A university's commission statement as CSV (spec B11.1): the rows b2c.statement_import reconciles. Universities name
 * their columns differently, so headers are matched loosely: a reference (our enrolment number or theirs), the student,
 * the programme and the amount.
 */
export type StatementRow = { ref: string; student: string; programme: string; amount: string };

export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], cell = "", quoted = false;
  const s = text.replace(/^﻿/, "");
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (quoted) {
      if (ch === '"' && s[i + 1] === '"') { cell += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cell += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") { row.push(cell); cell = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && s[i + 1] === "\n") i++;
      row.push(cell); cell = "";
      if (row.some((c) => c.trim() !== "")) rows.push(row);
      row = [];
    } else cell += ch;
  }
  row.push(cell);
  if (row.some((c) => c.trim() !== "")) rows.push(row);
  return rows;
}

const PICK: Record<keyof StatementRow, RegExp> = {
  ref: /^(enrol{1,2}ment ?(id|no|number)|ref(erence)?|eduwit ?ref|application ?(id|no))$/i,
  student: /^(student( name)?|name|candidate( name)?|learner)$/i,
  programme: /^(programme|program|course|programme name|program name)$/i,
  amount: /^(amount|commission( amount)?|payable|net payable|total)$/i,
};

export function statementRows(text: string): { rows: StatementRow[]; missing: string[] } {
  const table = parseCsv(text);
  if (table.length < 2) return { rows: [], missing: ["a header row and at least one row"] };
  const head = table[0]!.map((h) => h.trim().replace(/\s+/g, " "));
  const idx = Object.fromEntries((Object.keys(PICK) as (keyof StatementRow)[]).map((k) => [k, head.findIndex((h) => PICK[k].test(h))])) as Record<keyof StatementRow, number>;
  const missing = (["amount"] as const).filter((k) => idx[k] < 0).map((k) => `a column for ${k}`);
  if (idx.ref < 0 && idx.student < 0) missing.push("a reference or student column");
  const rows = table.slice(1).map((r) => ({
    ref: idx.ref >= 0 ? (r[idx.ref] ?? "").trim() : "",
    student: idx.student >= 0 ? (r[idx.student] ?? "").trim() : "",
    programme: idx.programme >= 0 ? (r[idx.programme] ?? "").trim() : "",
    amount: idx.amount >= 0 ? (r[idx.amount] ?? "").replace(/[₹,\s]|rs\.?/gi, "") : "",
  }));
  return { rows, missing };
}
