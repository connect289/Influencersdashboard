import { describe, expect, it } from "vitest";
import { parseEdit } from "./lead-edit";
import { csvLines, toCsv } from "./leads";

describe("lead corrections", () => {
  const current = { student_name: "Ravi", email_id: null, academic_score_pct: "68.00", lead_status: "UNQUALIFIED", city: "Delhi" };
  it("sends only real changes", () => {
    const r = parseEdit({ student_name: "Ravi Kumar", email_id: "Ravi@Example.com", academic_score_pct: "68", lead_status: "UNQUALIFIED", city: "Delhi" }, current);
    expect(r).toEqual({ ok: true, changes: { student_name: "Ravi Kumar", email_id: "ravi@example.com" } });
  });
  it("refuses emptying, bad formats and unknown classifications", () => {
    const r = parseEdit({ student_name: "", email_id: "nope", academic_score_pct: "120", lead_status: "MAYBE", annual_budget_inr: "1.5L" }, current);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(Object.keys(r.errors).sort()).toEqual(["academic_score_pct", "annual_budget_inr", "email_id", "lead_status", "student_name"]);
  });
  it("leaves an empty field empty without error", () => {
    expect(parseEdit({ guardian_name: "" }, {})).toEqual({ ok: true, changes: {} });
  });
});

describe("streamed CSV", () => {
  it("joins header and pages into the same file as toCsv", () => {
    const rows = [{ a: "x", b: 1 }, { a: "=1+1", b: null }];
    expect(`﻿a,b\r\n${csvLines(["a", "b"], rows.slice(0, 1))}${csvLines(["a", "b"], rows.slice(1))}`).toBe(toCsv(["a", "b"], rows));
  });
});
