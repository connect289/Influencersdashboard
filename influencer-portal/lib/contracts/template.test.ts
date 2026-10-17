import { describe, expect, it } from "vitest";
import { docFromText, plainText, richDoc, type RichDoc } from "./doc";
import { evaluate, renderDoc, truthy, usedPaths, type TemplateContext } from "./template";

const known = new Set(["a.name", "a.flag", "a.off", "a.kind", "t.table", "t.empty", "a.missing"]);
const ctx: TemplateContext = {
  "a.name": "Riya <Sharma>",
  "a.flag": true,
  "a.off": false,
  "a.kind": "hybrid",
  "t.table": { head: ["X", "Y"], rows: [["1", "2"]] },
  "t.empty": { head: ["X"], rows: [] },
  "a.missing": null,
};
const text = (r: ReturnType<typeof renderDoc>) => plainText(r.blocks);
const render = (src: string) => renderDoc(docFromText(src), ctx, known);

describe("evaluate", () => {
  it("handles truthiness, negation and comparisons", () => {
    expect(evaluate("a.flag", ctx)).toBe(true);
    expect(evaluate("!a.flag", ctx)).toBe(false);
    expect(evaluate("a.off", ctx)).toBe(false);
    expect(evaluate('a.kind == "hybrid"', ctx)).toBe(true);
    expect(evaluate('a.kind != "hybrid"', ctx)).toBe(false);
    expect(evaluate("t.table", ctx)).toBe(true);
    expect(evaluate("t.empty", ctx)).toBe(false);
    expect(evaluate("nope", ctx)).toBe(false);
    expect(truthy("  ")).toBe(false);
    expect(truthy(0)).toBe(false);
    expect(truthy(3)).toBe(true);
  });
});

describe("renderDoc", () => {
  it("substitutes variables and reports unknown and missing ones", () => {
    const r = render("Creator: {{a.name}}. Gone: {{a.missing}}. Bad: {{x.y}}.");
    expect(text(r)).toBe("Creator: Riya <Sharma>. Gone: . Bad: .");
    expect(r.unknown).toEqual(["x.y"]);
    expect(r.missing).toEqual(["a.missing"]);
  });

  it("block conditionals keep the chosen branch, with else and nesting", () => {
    const r = render(
      [
        "{{#if a.flag}}",
        "Yes 1",
        "{{#unless a.off}}",
        "Nested",
        "{{/unless}}",
        "{{else}}",
        "No 1",
        "{{/if}}",
        "{{#if a.off}}",
        "Hidden",
        "{{/if}}",
        "After",
      ].join("\n"),
    );
    expect(text(r)).toBe("Yes 1\nNested\nAfter");
    expect(r.errors).toEqual([]);
  });

  it("inline conditionals inside a sentence", () => {
    expect(
      text(
        render(
          'Paid {{#if a.flag}}monthly{{else}}once{{/if}} for a {{#if a.kind == "hybrid"}}hybrid{{/if}} deal.',
        ),
      ),
    ).toBe("Paid monthly for a hybrid deal.");
  });

  it("a paragraph with only a table variable becomes the table; empty tables disappear", () => {
    const r = render("Before\n{{t.table}}\n{{t.empty}}\nAfter");
    expect(r.blocks.map((b) => b.type)).toEqual(["paragraph", "table", "paragraph"]);
    expect(r.blocks[1]).toEqual({ type: "table", head: ["X", "Y"], rows: [["1", "2"]] });
  });

  it("a table variable inside a sentence is an error", () => {
    expect(render("See {{t.table}} here").errors).toContain("table_inline:t.table");
  });

  it("reports unbalanced conditionals", () => {
    expect(render("{{#if a.flag}}\nOpen").errors[0]).toMatch(/^unclosed:if/);
    expect(render("Text\n{{/if}}").errors).toContain("stray_control");
    expect(render("Inline {{#if a.flag}}never closed").errors).toContain(
      "unbalanced_inline_condition",
    );
    expect(render("{{#if 1bad}}\nX\n{{/if}}").errors).toContain("invalid_condition:1bad");
  });

  it("works inside lists and drops items that become empty", () => {
    const r = render("- one {{a.name}}\n- {{#if a.off}}gone{{/if}}\n- three");
    expect(r.blocks).toHaveLength(1);
    expect(text(r)).toBe("• one Riya <Sharma>\n• three");
  });

  it("keeps marks and line breaks", () => {
    const doc: RichDoc = {
      type: "doc",
      content: [
        {
          type: "paragraph",
          content: [
            { type: "text", text: "{{a.name}}", marks: [{ type: "bold" }] },
            { type: "hardBreak" },
            { type: "text", text: "x" },
          ],
        },
      ],
    };
    expect(renderDoc(doc, ctx, known).blocks[0]).toEqual({
      type: "paragraph",
      content: [
        { type: "text", text: "Riya <Sharma>", marks: [{ type: "bold" }] },
        { type: "hardBreak" },
        { type: "text", text: "x" },
      ],
    });
  });

  it("lists every path a document uses", () => {
    expect(
      usedPaths(
        docFromText(
          "{{#if a.flag}}\n{{a.name}} and {{t.table}}\n{{/if}}\n{{#unless !a.off}}x{{/unless}}",
        ),
      ),
    ).toEqual(["a.flag", "a.name", "a.off", "t.table"]);
  });
});

describe("richDoc (editor JSON whitelist)", () => {
  it("accepts the editor's nodes and strips unknown attributes", () => {
    const parsed = richDoc.parse({
      type: "doc",
      content: [
        {
          type: "heading",
          attrs: { level: 1, textAlign: "left" },
          content: [{ type: "text", text: "T" }],
        },
        {
          type: "paragraph",
          attrs: { textAlign: null },
          content: [{ type: "text", text: "a", marks: [{ type: "bold", attrs: {} }] }],
        },
        {
          type: "orderedList",
          attrs: { start: 1 },
          content: [{ type: "listItem", content: [{ type: "paragraph" }] }],
        },
      ],
    });
    expect(parsed.content[0]).toEqual({
      type: "heading",
      attrs: { level: 2 },
      content: [{ type: "text", text: "T" }],
    });
    expect(parsed.content[1]).toEqual({
      type: "paragraph",
      content: [{ type: "text", text: "a", marks: [{ type: "bold" }] }],
    });
  });

  it("refuses anything else (links, images, raw HTML, tables from the editor)", () => {
    for (const bad of [
      { type: "image", attrs: { src: "x" } },
      {
        type: "paragraph",
        content: [
          { type: "text", text: "a", marks: [{ type: "link", attrs: { href: "javascript:x" } }] },
        ],
      },
      { type: "table", head: [], rows: [] },
      { type: "codeBlock" },
    ])
      expect(richDoc.safeParse({ type: "doc", content: [bad] }).success).toBe(false);
  });
});
