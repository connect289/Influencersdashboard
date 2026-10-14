import { describe, expect, it } from "vitest";
import { parseCsv, statementRows } from "./statement-csv";

describe("statement CSV", () => {
  it("parses quotes, commas and CRLF", () => {
    expect(parseCsv('a,"b, c","d ""q"""\r\n1,2,3\r\n')).toEqual([["a", "b, c", 'd "q"'], ["1", "2", "3"]]);
  });
  it("maps loosely named columns and cleans amounts", () => {
    const { rows, missing } = statementRows("Student Name,Program,Enrollment ID,Commission Amount\nBina Test,Online MBA,42,\"₹16,336\"\nGhost,BBA,,\"Rs. 5,000\"\n");
    expect(missing).toEqual([]);
    expect(rows[0]).toEqual({ ref: "42", student: "Bina Test", programme: "Online MBA", amount: "16336" });
    expect(rows[1]?.amount).toBe("5000");
  });
  it("says what is missing", () => {
    expect(statementRows("Foo,Bar\n1,2").missing).toEqual(["a column for amount", "a reference or student column"]);
    expect(statementRows("").missing).toHaveLength(1);
  });
});
