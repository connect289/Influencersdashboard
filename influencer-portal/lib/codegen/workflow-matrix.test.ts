import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { workflowMatrixSql } from "./workflow-matrix";

describe("workflow matrix test", () => {
  it("supabase/tests/017_workflow_matrix.sql matches lib/content/workflow.ts (run npm run gen:sql if this fails)", () => {
    const file = join(import.meta.dirname, "..", "..", "supabase", "tests", "017_workflow_matrix.sql");
    expect(readFileSync(file, "utf8")).toBe(workflowMatrixSql());
  });
});
