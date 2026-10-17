import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { ledgerMatrixSql, ledgerStates } from "./ledger-matrix";

describe("ledger status matrix test", () => {
  it("supabase/tests/020_ledger_status_matrix.sql matches lib/ledger/lifecycle.ts (run npm run gen:sql if this fails)", () => {
    const file = join(import.meta.dirname, "..", "..", "supabase", "tests", "020_ledger_status_matrix.sql");
    expect(readFileSync(file, "utf8")).toBe(ledgerMatrixSql());
  });

  it("covers a broad grid of entry facts", () => {
    expect(ledgerStates().length).toBeGreaterThan(300);
  });
});
