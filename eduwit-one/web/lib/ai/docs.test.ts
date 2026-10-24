import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { type DocFile, docsModule, findSections, sections } from "./docs-source.ts";
import { DOCS, DOCS_VERSION } from "./docs.generated.ts";

// The runbook the AI quotes is the runbook in the repository: the generated module must match the documents.

const read = (file: DocFile) => readFileSync(new URL(`../../../docs/${file}.md`, import.meta.url), "utf8");

describe("the runbook tool's source", () => {
  it("docs.generated.ts matches the documents (node scripts/gen-docs.ts)", () => {
    expect(readFileSync(new URL("./docs.generated.ts", import.meta.url), "utf8")).toBe(docsModule(read));
    expect(DOCS_VERSION).toMatch(/^[0-9a-f]{10}$/);
  });

  it("splits a document at its second-level headings", () => {
    const s = sections("RUNBOOK", "# Title\n\nintro\n\n## Alerts\n\n- a\n\n## Fixes\n\ntext\n");
    expect(s.map((x) => x.title)).toEqual(["About", "Alerts", "Fixes"]);
    expect(s[1]?.text).toBe("- a");
  });

  it("carries the sections an operator needs", () => {
    const titles = DOCS.map((d) => `${d.file}: ${d.title}`);
    for (const t of [
      "RUNBOOK: Alerts",
      "RUNBOOK: Signing in",
      "RUNBOOK: Setup",
      "RUNBOOK: Fixes",
      "RUNBOOK: Rotating a secret",
      "RUNBOOK: Rolling back a migration",
      "RUNBOOK: Adding a check or a test",
      "RUNBOOK: The external watchdog (UptimeRobot)",
      "RUNBOOK-database: 2. Rehearse on staging",
      "WALKTHROUGH: 9. If you are paged (on the way out, no time)",
    ])
      expect(titles).toContain(t);
  });

  it("finds a section by the words of a question", () => {
    expect(findSections(DOCS, "how do I rotate the n8n key").map((d) => d.title)[0]).toBe("Rotating a secret");
    expect(findSections(DOCS, "locked out, no owner can sign in")[0]?.title).toBe("Signing in");
    expect(findSections(DOCS, "zzzz")).toEqual([]);
    expect(findSections(DOCS, "", 2)).toHaveLength(2);
  });

  it("holds no secret-looking value", () => {
    for (const d of DOCS) expect(d.text).not.toMatch(/sk-ant-|eyJhbGci|re_[A-Za-z0-9]{20}/);
  });
});
