import { describe, expect, it } from "vitest";
import { assembleContract } from "./assemble";
import { docFromText } from "./doc";
import { DEFAULT_TEMPLATE, SEED_CLAUSES } from "./library";
import { SAMPLE_KINDS, sampleContext } from "./sample";
import { VARIABLES } from "./variables";

const template = {
  title: DEFAULT_TEMPLATE.title,
  header: docFromText(DEFAULT_TEMPLATE.header),
  footer: docFromText(DEFAULT_TEMPLATE.footer),
  clauses: DEFAULT_TEMPLATE.clauses.map((c) => {
    const s = SEED_CLAUSES.find((x) => x.key === c.key);
    if (!s) throw new Error(c.key);
    return {
      ...s,
      clause_id: s.key,
      version: 1,
      body: docFromText(s.body),
      reviewed: true,
      condition: c.condition,
    };
  }),
};

describe("sample contexts", () => {
  it.each(SAMPLE_KINDS)(
    "%s has a value for every text variable and renders the default template",
    (kind) => {
      const ctx = sampleContext(kind, "2026-10-17");
      for (const v of VARIABLES) expect(Object.hasOwn(ctx, v.key), v.key).toBe(true);
      const r = assembleContract(template, ctx);
      expect(r.errors).toEqual([]);
      expect(r.unknown).toEqual([]);
    },
  );
  it("the full sample switches on every optional clause", () => {
    const keys = assembleContract(
      template,
      sampleContext("full", "2026-10-17"),
    ).content.sections.map((s) => s.key);
    expect(keys).toEqual(expect.arrayContaining(["exclusivity", "penalties"]));
    const plain = assembleContract(
      template,
      sampleContext("commission_only", "2026-10-17"),
    ).content.sections.map((s) => s.key);
    expect(plain).not.toContain("exclusivity");
  });
});
