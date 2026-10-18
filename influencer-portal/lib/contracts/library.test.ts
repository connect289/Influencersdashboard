import { describe, expect, it } from "vitest";
import { PRESET_KEYS, SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { compConfig } from "@/lib/compensation/schema";
import { assembleContract } from "./assemble";
import { docFromText } from "./doc";
import { contractHtml } from "./html";
import { CLAUSE_CATEGORIES, DEFAULT_TEMPLATE, DRAFT_MARKER, SEED_CLAUSES } from "./library";
import { usedPaths } from "./template";
import { buildContext, VARIABLE_KEYS, type ContextInput } from "./variables";

const base: Omit<ContextInput, "deal"> = {
  creator: {
    legal_name: "Riya Sharma",
    display_name: "Riya",
    handle: "riyalearns",
    city: "Pune",
    state: "MH",
    email: "r@example.test",
    pan_masked: "ABCxx4F",
    gstin: null,
  },
  payee: { name: "Riya Sharma", is_agency: false },
  deliverables: [{ platform: "instagram", format: "reel", count: 1 }],
  campaign: null,
  eduwit: {
    legal_name: "Eduwit Learning Services",
    address: "Ghaziabad",
    gstin: "",
    pan: "",
    support_email: "creators@eduwit.in",
  },
  signatory: { name: "Asha Admin", designation: "Director" },
  contract: { number: "CT-00001", date: "2026-10-17", parent_number: null },
};
const template = {
  title: DEFAULT_TEMPLATE.title,
  header: docFromText(DEFAULT_TEMPLATE.header),
  footer: docFromText(DEFAULT_TEMPLATE.footer),
  clauses: DEFAULT_TEMPLATE.clauses.map((c) => {
    const s = SEED_CLAUSES.find((x) => x.key === c.key);
    if (!s) throw new Error(c.key);
    return {
      clause_id: s.key,
      version: 1,
      key: s.key,
      category: s.category,
      title: s.title,
      body: docFromText(s.body),
      negotiable: s.negotiable,
      locked: s.locked,
      required: s.required,
      reviewed: false,
      condition: c.condition,
    };
  }),
};

describe("seed clause library", () => {
  it("covers every category once, marked as draft", () => {
    expect(new Set(SEED_CLAUSES.map((c) => c.category))).toEqual(new Set(CLAUSE_CATEGORIES));
    expect(new Set(SEED_CLAUSES.map((c) => c.key)).size).toBe(SEED_CLAUSES.length);
    for (const c of SEED_CLAUSES) expect(c.body.startsWith(DRAFT_MARKER), c.key).toBe(true);
    expect(DEFAULT_TEMPLATE.clauses.map((c) => c.key).sort()).toEqual(SEED_CLAUSES.map((c) => c.key).sort());
  });

  it("uses only catalogue variables", () => {
    for (const c of SEED_CLAUSES)
      for (const p of usedPaths(docFromText(c.body))) expect(VARIABLE_KEYS.has(p), `${c.key}: ${p}`).toBe(true);
  });

  it.each(PRESET_KEYS)("renders cleanly for the %s preset", (key) => {
    const config = SYSTEM_PRESETS[key].config;
    const r = assembleContract(
      template,
      buildContext({
        ...base,
        deal: {
          code: "DL-1",
          title: "T",
          starts_on: "2026-11-01",
          ends_on: null,
          model: key,
          config,
        },
      }),
    );
    expect(r.errors).toEqual([]);
    expect(r.unknown).toEqual([]);
    expect(r.unreviewed.length).toBe(r.content.sections.length);
    const html = contractHtml(r.content);
    if (config.commission.length) expect(html).toContain("Commission");
    else expect(html).not.toContain("<td>Commission per enrolment");
  });

  it("adds exclusivity and penalty clauses only when the deal has them", () => {
    const config = compConfig.parse({
      ...SYSTEM_PRESETS.fixed_only.config,
      fees: [
        {
          id: "x",
          kind: "exclusivity",
          label: "Exclusivity",
          amount_paise: 100_00,
          duration_days: 30,
          category: "edtech",
        },
      ],
      penalties: [{ id: "p", type: "disclosure", label: "Disclosure", amount_paise: 500_00 }],
    });
    const r = assembleContract(
      template,
      buildContext({
        ...base,
        deal: {
          code: "DL-1",
          title: "T",
          starts_on: "2026-11-01",
          ends_on: null,
          model: "fixed_only",
          config,
        },
      }),
    );
    expect(r.content.sections.map((s) => s.key)).toEqual(expect.arrayContaining(["exclusivity", "penalties"]));
    expect(contractHtml(r.content)).toContain("edtech");
  });
});
