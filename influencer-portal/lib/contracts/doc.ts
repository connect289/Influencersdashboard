// The contract document model (D-81): a whitelisted subset of the rich-text editor's JSON. Clause and template bodies
// are stored as this JSON and rendered by us (html.ts, pdf.tsx), so no stored HTML is ever trusted. Anything outside
// the whitelist fails validation.
import { z } from "zod";

export const MARKS = ["bold", "italic", "underline"] as const;
export type MarkType = (typeof MARKS)[number];

const text = z.object({
  type: z.literal("text"),
  text: z.string().min(1).max(20_000),
  marks: z
    .array(z.object({ type: z.enum(MARKS) }).transform(({ type }) => ({ type })))
    .max(3)
    .optional(),
});
const hardBreak = z.object({ type: z.literal("hardBreak") }).transform(() => ({ type: "hardBreak" as const }));
export const inline = z.union([text, hardBreak]);
export type Inline = z.infer<typeof inline>;

export type Block =
  | { type: "paragraph"; content?: Inline[] }
  | { type: "heading"; attrs: { level: 2 | 3 | 4 }; content?: Inline[] }
  | { type: "bulletList"; content: ListItem[] }
  | { type: "orderedList"; content: ListItem[] }
  /** Generated only (deal tables); never accepted from the editor. */
  | { type: "table"; head: string[]; rows: string[][] };
// A type alias (not an interface) so documents stay assignable to the database's Json type.
export type ListItem = {
  type: "listItem";
  content: Block[];
};

const paragraph = z.object({
  type: z.literal("paragraph"),
  content: z.array(inline).max(500).optional(),
});
const heading = z.object({
  type: z.literal("heading"),
  attrs: z
    .object({ level: z.coerce.number().int().min(1).max(6) })
    .transform(({ level }) => ({ level: Math.min(Math.max(level, 2), 4) as 2 | 3 | 4 })),
  content: z.array(inline).max(500).optional(),
});

/** Editor blocks (no tables). Lists nest up to the editor's practical depth. */
export const editorBlock: z.ZodType<Block> = z.lazy(() =>
  z.union([
    paragraph.transform((p) => ({
      type: "paragraph" as const,
      ...(p.content ? { content: p.content } : {}),
    })),
    heading.transform((h) => ({
      type: "heading" as const,
      attrs: h.attrs,
      ...(h.content ? { content: h.content } : {}),
    })),
    z
      .object({ type: z.literal("bulletList"), content: z.array(listItem).min(1).max(200) })
      .transform((l) => ({ type: "bulletList" as const, content: l.content })),
    z
      .object({ type: z.literal("orderedList"), content: z.array(listItem).min(1).max(200) })
      .transform((l) => ({ type: "orderedList" as const, content: l.content })),
  ]),
);
const listItem: z.ZodType<ListItem> = z.lazy(() =>
  z
    .object({ type: z.literal("listItem"), content: z.array(editorBlock).min(1).max(50) })
    .transform((li) => ({ type: "listItem" as const, content: li.content })),
);

/** Stored contract blocks: editor blocks plus the generated deal tables. */
export const contentBlock: z.ZodType<Block> = z.union([
  editorBlock,
  z.object({
    type: z.literal("table"),
    head: z.array(z.string().max(200)).max(20),
    rows: z.array(z.array(z.string().max(2000)).max(20)).max(500),
  }),
]);

export const richDoc = z
  .object({ type: z.literal("doc"), content: z.array(editorBlock).max(2000).default([]) })
  .transform((d) => ({ type: "doc" as const, content: d.content }));
export type RichDoc = { type: "doc"; content: Block[] };

export const EMPTY_DOC: RichDoc = { type: "doc", content: [] };

/** A document from plain paragraphs (seed clauses, tests). Lines starting with "- " become a bullet list. */
export function docFromText(source: string): RichDoc {
  const content: Block[] = [];
  let bullets: ListItem[] = [];
  const flush = () => {
    if (bullets.length) content.push({ type: "bulletList", content: bullets });
    bullets = [];
  };
  for (const raw of source.split("\n")) {
    const line = raw.trim();
    if (!line) {
      flush();
      continue;
    }
    const para = (s: string): Block => ({
      type: "paragraph",
      content: [{ type: "text", text: s }],
    });
    if (line.startsWith("- ")) bullets.push({ type: "listItem", content: [para(line.slice(2))] });
    else {
      flush();
      content.push(para(line));
    }
  }
  flush();
  return { type: "doc", content };
}

/** Plain text of inline content. */
export function inlineText(content: readonly Inline[] | undefined): string {
  return (content ?? []).map((i) => (i.type === "text" ? i.text : "\n")).join("");
}

/** Plain text of a block list, one line per paragraph or list item (for diffs and search). */
export function plainText(blocks: readonly Block[]): string {
  const out: string[] = [];
  const walk = (bs: readonly Block[], prefix: string) => {
    for (const b of bs) {
      if (b.type === "paragraph" || b.type === "heading") out.push(prefix + inlineText(b.content));
      else if (b.type === "table") {
        out.push(b.head.join(" | "));
        for (const r of b.rows) out.push(r.join(" | "));
      } else b.content.forEach((li, i) => walk(li.content, b.type === "orderedList" ? `${String(i + 1)}. ` : "• "));
    }
  };
  walk(blocks, "");
  return out.join("\n");
}
