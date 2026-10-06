import { describe, expect, it } from "vitest";
import { csvCells, formatChain, normalizeName, parseChain, parseSchemaText, similarity, suggestField, suggestStage } from "./mapping";

const OPS = ["trim", "lower", "upper", "title", "constant", "default", "replace", "join", "split", "phone_e164", "date", "datetime", "amount", "cgpa_to_pct", "boolean"];
const CANON = [
  { key: "full_name", label: "Student name" }, { key: "email", label: "Email" }, { key: "counsellor_name", label: "Counsellor name" },
  { key: "fee_paid_inr", label: "Amount paid (₹)" }, { key: "next_follow_up_at", label: "Next follow-up" }, { key: "highest_qualification", label: "Highest qualification" },
];

describe("names", () => {
  it("normalizes LeadSquared custom fields", () => {
    expect(normalizeName("mx_Highest_Education")).toBe("highesteducation");
    expect(normalizeName("Email Address")).toBe("emailaddress");
  });
  it("scores similar names", () => {
    expect(similarity("Counsellor", "counsellor_name")).toBeGreaterThan(0.7);
    expect(similarity("abc", "xyz")).toBe(0);
  });
});

describe("field suggestions", () => {
  it("prefers what other partners on the same CRM use", () => {
    expect(suggestField("mx_Lead_Owner_X", CANON, [{ partner_field: "mx_Lead_Owner_X", canonical_key: "counsellor_name", partners: 2 }]))
      .toMatchObject({ key: "counsellor_name", confidence: 0.95 });
  });
  it("knows synonyms", () => {
    expect(suggestField("Email Address", CANON)?.key).toBe("email");
    expect(suggestField("mx_Highest_Education", CANON)?.key).toBe("highest_qualification");
    expect(suggestField("Lead Owner", CANON)?.key).toBe("counsellor_name");
    expect(suggestField("Amount Paid", CANON)?.key).toBe("fee_paid_inr");
  });
  it("falls back to similar names, or nothing", () => {
    expect(suggestField("Counsellor Nam", CANON)?.key).toBe("counsellor_name");
    expect(suggestField("zzzz", CANON)).toBeNull();
  });
});

describe("stage hints", () => {
  it("guesses from the wording", () => {
    expect(suggestStage("Attempted", "RNR")?.key).toBe("contacted");
    expect(suggestStage("Not Interested")?.key).toBe("lost");
    expect(suggestStage("Admission Done")?.key).toBe("enrolled");
    expect(suggestStage("Application Submitted")?.key).toBe("applied");
    expect(suggestStage("Hot Prospect")?.key).toBe("counselled");
    expect(suggestStage("Duplicate Lead")?.key).toBe("duplicate_at_partner");
    expect(suggestStage("Stage 7")).toBeNull();
  });
});

describe("transform chains", () => {
  it("parses and formats", () => {
    const r = parseChain("trim | amount | split(sep=' - ', part=last) | default(value='Eduwit')", OPS);
    expect(r).toEqual({ ok: true, chain: [{ op: "trim" }, { op: "amount" }, { op: "split", sep: " - ", part: "last" }, { op: "default", value: "Eduwit" }] });
    if (r.ok) expect(formatChain(r.chain)).toBe("trim | amount | split(sep=' - ', part='last') | default(value='Eduwit')");
    expect(parseChain("cgpa_to_pct(scale=10, factor=9.5)", OPS)).toEqual({ ok: true, chain: [{ op: "cgpa_to_pct", scale: 10, factor: 9.5 }] });
    expect(parseChain("split(sep='|', part=0)", OPS)).toEqual({ ok: true, chain: [{ op: "split", sep: "|", part: 0 }] });
    expect(parseChain("  ", OPS)).toEqual({ ok: true, chain: [] });
  });
  it("refuses unknown or broken transforms", () => {
    expect(parseChain("explode", OPS).ok).toBe(false);
    expect(parseChain("split(sep=' - ", OPS).ok).toBe(false);
    expect(parseChain("split(sep)", OPS).ok).toBe(false);
  });
});

describe("schema uploads", () => {
  it("reads quoted CSV cells", () => {
    expect(csvCells('field,"Name, full",,text')).toEqual(["field", "Name, full", "", "text"]);
    expect(csvCells('value,"He said ""hi""",x')).toEqual(["value", 'He said "hi"', "x"]);
  });
  it("reads the CSV layout", () => {
    const r = parseSchemaText([
      "kind,name,parent,type",
      "field,mx_Highest_Education,,picklist",
      "value,Graduate,mx_Highest_Education,",
      "value,Post Graduate,mx_Highest_Education,",
      "stage,Attempted,,",
      "sub_stage,RNR,Attempted,",
      "pipeline,Online MBA,,",
      "activity,Call Log,,",
      "outcome,Connected,Call Log,",
    ].join("\n"));
    expect(r).toEqual({ ok: true, schema: {
      fields: [{ name: "mx_Highest_Education", type: "picklist", values: ["Graduate", "Post Graduate"] }],
      stages: [{ stage: "Attempted", sub_stages: ["RNR"] }],
      pipelines: ["Online MBA"],
      activities: [{ type: "Call Log", outcomes: ["Connected"] }],
    } });
  });
  it("reads JSON and refuses bad input", () => {
    expect(parseSchemaText('{"fields":[{"name":"A"}],"stages":[]}')).toMatchObject({ ok: true, schema: { fields: [{ name: "A" }] } });
    expect(parseSchemaText("{oops").ok).toBe(false);
    expect(parseSchemaText("a,b\n1,2").ok).toBe(false);
    expect(parseSchemaText("kind,name,parent\nvalue,Graduate,").ok).toBe(false);
    expect(parseSchemaText("kind,name\nwidget,X").ok).toBe(false);
  });
});
