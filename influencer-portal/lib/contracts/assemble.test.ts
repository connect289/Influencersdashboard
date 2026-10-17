import { describe, expect, it } from "vitest";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { assembleContract, canonicalJson, type ClauseInput } from "./assemble";
import { diffContents, diffWords } from "./diff";
import { docFromText, EMPTY_DOC } from "./doc";
import { contractHtml, escapeHtml } from "./html";
import {
  buildContext,
  commissionTable,
  milestoneTable,
  VARIABLE_KEYS,
  VARIABLES,
  type ContextInput,
} from "./variables";

const input = (over: Partial<ContextInput["deal"]> = {}): ContextInput => ({
  creator: {
    legal_name: "Riya Sharma",
    display_name: "Riya",
    handle: "riyalearns",
    city: "Pune",
    state: "Maharashtra",
    email: "r@example.test",
    pan_masked: "ABCxxxx4F",
    gstin: null,
  },
  payee: { name: "Riya Sharma", is_agency: false },
  deal: {
    code: "DL-00001",
    title: "Diwali",
    starts_on: "2026-11-01",
    ends_on: "2027-01-31",
    model: "hybrid",
    config: SYSTEM_PRESETS.fixed_plus_commission.config,
    ...over,
  },
  deliverables: [{ platform: "instagram", format: "reel", count: 2 }],
  campaign: { name: "MBA push" },
  eduwit: {
    legal_name: "Eduwit Learning Services",
    address: "Ghaziabad",
    gstin: "",
    pan: "",
    support_email: "creators@eduwit.in",
  },
  signatory: { name: "Asha Admin", designation: "Director" },
  contract: { number: "CT-00001", date: "2026-10-17", parent_number: null },
});

const clause = (key: string, body: string, over: Partial<ClauseInput> = {}): ClauseInput => ({
  clause_id: `id-${key}`,
  version: 1,
  key,
  category: "general",
  title: key,
  body: docFromText(body),
  negotiable: false,
  locked: false,
  required: false,
  reviewed: true,
  condition: null,
  ...over,
});

describe("deal tables", () => {
  it("milestones come from the deal config, never typed", () => {
    const t = milestoneTable(SYSTEM_PRESETS.fixed_plus_commission.config);
    expect(t.rows).toEqual([
      ["Content fee: On signing", "₹7,500 (50%)", "on signing this agreement", "7 days"],
      ["Content fee: When the content is live", "₹7,500 (50%)", "when the content is live", "7 days"],
    ]);
    expect(commissionTable(SYSTEM_PRESETS.commission_only.config).rows[0]).toEqual([
      "Commission per enrolment",
      "10% of Eduwit's commission per enrolment (net of GST)",
      "when Eduwit receives its commission",
      "—",
    ]);
  });

  it("the context has a value for every catalogue variable", () => {
    const ctx = buildContext(input());
    for (const v of VARIABLES) expect(Object.hasOwn(ctx, v.key), v.key).toBe(true);
    expect(Object.keys(ctx).every((k) => VARIABLE_KEYS.has(k))).toBe(true);
    expect(ctx["deal.fixed_fee_total"]).toBe("₹15,000");
    expect(ctx["deal.has_commission"]).toBe(true);
  });
});

describe("assembleContract", () => {
  const template = {
    title: "Agreement {{contract.number}}",
    header: docFromText("Between {{eduwit.legal_name}} and {{creator.legal_name}}."),
    footer: EMPTY_DOC,
    clauses: [
      clause("parties", "The creator is {{creator.legal_name}} ({{creator.handle}})."),
      clause("fees", "Fees:\n{{deal.milestone_table}}", { condition: "deal.has_fixed" }),
      clause("commission", "Commission:\n{{deal.commission_table}}", {
        condition: "deal.has_commission",
      }),
      clause("exclusivity", "Exclusive.", { condition: "deal.has_exclusivity" }),
      clause("conduct", "Be good.", { negotiable: true, reviewed: false }),
    ],
  };

  it("numbers the clauses that apply, renders tables and flags unreviewed clauses", () => {
    const r = assembleContract(template, buildContext(input()));
    expect(r.content.title).toBe("Agreement CT-00001");
    expect(r.content.sections.map((s) => [s.number, s.key])).toEqual([
      [1, "parties"],
      [2, "fees"],
      [3, "commission"],
      [4, "conduct"],
    ]);
    expect(r.content.sections[1]?.blocks.some((b) => b.type === "table")).toBe(true);
    expect(r.unreviewed).toEqual(["conduct"]);
    expect(r.errors).toEqual([]);
  });

  it("a fixed-only deal drops the commission clause", () => {
    const r = assembleContract(
      template,
      buildContext(input({ config: SYSTEM_PRESETS.fixed_only.config, model: "fixed_only" })),
    );
    expect(r.content.sections.map((s) => s.key)).toEqual(["parties", "fees", "conduct"]);
  });

  it("negotiated wording replaces only negotiable clauses", () => {
    const r = assembleContract(template, buildContext(input()), {
      conduct: docFromText("Be very good."),
      parties: docFromText("Hacked"),
    });
    const conduct = r.content.sections.find((s) => s.key === "conduct");
    expect(conduct?.amended).toBe(true);
    expect(r.content.sections[0]?.amended).toBe(false);
    expect(contractHtml(r.content)).toContain("Be very good.");
    expect(contractHtml(r.content)).not.toContain("Hacked");
  });

  it("is deterministic and escapes everything", () => {
    const ctx = buildContext({
      ...input(),
      creator: { ...input().creator, legal_name: '<script>alert("x")</script>' },
    });
    const a = assembleContract(template, ctx);
    const b = assembleContract(template, ctx);
    expect(canonicalJson(a.content)).toBe(canonicalJson(b.content));
    const html = contractHtml(a.content);
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
    expect(canonicalJson({ b: 1, a: [{ d: 1, c: 2 }] })).toBe('{"a":[{"c":2,"d":1}],"b":1}');
    expect(escapeHtml(`'"&`)).toBe("&#39;&quot;&amp;");
  });

  it("reports missing values (e.g. no signatory yet)", () => {
    const r = assembleContract(
      { ...template, footer: docFromText("Signed for Eduwit by {{eduwit.signatory_name}}") },
      buildContext({ ...input(), signatory: null }),
    );
    expect(r.missing).toContain("eduwit.signatory_name");
  });
});

describe("diff", () => {
  it("diffs words, merging runs", () => {
    expect(diffWords("pay within 7 days", "pay within 14 days")).toEqual([
      { op: "eq", text: "pay within " },
      { op: "del", text: "7" },
      { op: "ins", text: "14" },
      { op: "eq", text: " days" },
    ]);
    expect(diffWords("same", "same")).toEqual([{ op: "eq", text: "same" }]);
    expect(diffWords("", "new text")).toEqual([{ op: "ins", text: "new text" }]);
  });

  it("diffs contract versions section by section", () => {
    const t = {
      title: "T",
      header: EMPTY_DOC,
      footer: EMPTY_DOC,
      clauses: [clause("a", "Alpha one"), clause("b", "Beta"), clause("c", "Gamma")],
    };
    const ctx = buildContext(input());
    const v1 = assembleContract(t, ctx).content;
    const v2 = assembleContract(
      { ...t, clauses: [clause("a", "Alpha two"), clause("c", "Gamma"), clause("d", "Delta")] },
      ctx,
    ).content;
    expect(diffContents(v1, v2).map((d) => [d.key, d.change])).toEqual([
      ["a", "changed"],
      ["c", "same"],
      ["d", "added"],
      ["b", "removed"],
    ]);
  });
});
