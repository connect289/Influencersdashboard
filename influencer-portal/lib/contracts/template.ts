// Contract template language (spec 8.1). Pure.
//   {{path}}                         a variable (text), escaped when rendered
//   {{deal.milestone_table}}         a table variable: must be the only thing in its paragraph
//   {{#if expr}} … {{else}} … {{/if}}    conditional; as whole paragraphs (block) or inside one text run (inline)
//   {{#unless expr}} … {{/unless}}
//   expr := path | !path | path == "text" | path != "text"
import type { Block, Inline, ListItem, RichDoc } from "./doc";
import { inlineText } from "./doc";

export interface TableValue {
  head: string[];
  rows: string[][];
}
export type ContextValue = string | number | boolean | TableValue | null;
export type TemplateContext = Readonly<Record<string, ContextValue>>;

export interface RenderResult {
  blocks: Block[];
  /** Variables not in the catalogue. */
  unknown: string[];
  /** Catalogue variables with no value for this contract. */
  missing: string[];
  errors: string[];
}

const VAR = /\{\{\s*(?!else\s*\}\})([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*)\s*\}\}/g;
const CONTROL = /^\{\{\s*(#if|#unless|else|\/if|\/unless)(?:\s+([^{}]+?))?\s*\}\}$/;
const PATH = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*$/;

const isTable = (v: ContextValue | undefined): v is TableValue => typeof v === "object" && v !== null && "rows" in v;

export function truthy(v: ContextValue | undefined): boolean {
  if (v === undefined || v === null || v === false) return false;
  if (typeof v === "string") return v.trim().length > 0;
  if (typeof v === "number") return v !== 0;
  if (isTable(v)) return v.rows.length > 0;
  return true;
}

interface Env {
  ctx: TemplateContext;
  known: ReadonlySet<string>;
  unknown: Set<string>;
  missing: Set<string>;
  errors: string[];
}

function note(env: Env, path: string, required = true) {
  if (!env.known.has(path)) env.unknown.add(path);
  else if (required && !truthy(env.ctx[path]) && env.ctx[path] !== false && env.ctx[path] !== 0) env.missing.add(path);
}

/** Evaluates a condition. Unknown variables are reported; their value is false. */
export function evaluate(expr: string, ctx: TemplateContext, env?: Env): boolean {
  const e = expr.trim();
  const cmp = /^([a-z][a-z0-9_.]*)\s*(==|!=)\s*"([^"]*)"$/.exec(e);
  if (cmp) {
    const [, path = "", op, lit] = cmp;
    if (env) note(env, path, false);
    const v = ctx[path];
    const s = v === null || v === undefined || isTable(v) ? "" : String(v);
    return op === "==" ? s === lit : s !== lit;
  }
  const neg = e.startsWith("!");
  const path = (neg ? e.slice(1) : e).trim();
  if (!PATH.test(path)) {
    env?.errors.push(`invalid_condition:${e}`);
    return false;
  }
  if (env) note(env, path, false);
  const v = truthy(ctx[path]);
  return neg ? !v : v;
}

function textValue(v: ContextValue | undefined): string {
  if (v === undefined || v === null || isTable(v)) return "";
  if (typeof v === "boolean") return v ? "Yes" : "No";
  return String(v);
}

/** Inline conditionals inside one string (innermost first), then variables. */
export function renderString(s: string, env: Env): string {
  let out = s;
  const inlineIf =
    /\{\{\s*#(if|unless)\s+([^}]+?)\s*\}\}((?:(?!\{\{\s*#(?:if|unless)\b)[\s\S])*?)(?:\{\{\s*else\s*\}\}((?:(?!\{\{\s*#(?:if|unless)\b)[\s\S])*?))?\{\{\s*\/(if|unless)\s*\}\}/;
  for (let guard = 0; guard < 200; guard++) {
    const m = inlineIf.exec(out);
    if (!m) break;
    const [all, kind, expr = "", yes = "", no = "", close] = m;
    if (kind !== close) {
      env.errors.push(`mismatched:${kind ?? ""}/${close ?? ""}`);
      break;
    }
    const v = evaluate(expr, env.ctx, env);
    out = out.replace(all, (kind === "if" ? v : !v) ? yes : no);
  }
  if (/\{\{\s*(#if|#unless|else|\/if|\/unless)\b/.test(out)) env.errors.push("unbalanced_inline_condition");
  return out.replace(VAR, (_all, path: string) => {
    note(env, path);
    const v = env.ctx[path];
    if (isTable(v)) {
      env.errors.push(`table_inline:${path}`);
      return "";
    }
    return textValue(v);
  });
}

function renderInline(content: readonly Inline[] | undefined, env: Env): Inline[] {
  const out: Inline[] = [];
  for (const i of content ?? []) {
    if (i.type === "hardBreak") out.push(i);
    else {
      const text = renderString(i.text, env);
      if (text) out.push(i.marks ? { type: "text", text, marks: i.marks } : { type: "text", text });
    }
  }
  return out;
}

type Control = { kind: "if" | "unless" | "else" | "end"; expr?: string; close?: "if" | "unless" };

function controlOf(b: Block): Control | null {
  if (b.type !== "paragraph") return null;
  const m = CONTROL.exec(inlineText(b.content).trim());
  if (!m) return null;
  const tag = m[1];
  if (tag === "#if" || tag === "#unless") return { kind: tag === "#if" ? "if" : "unless", expr: m[2] ?? "" };
  if (tag === "else") return { kind: "else" };
  return { kind: "end", close: tag === "/if" ? "if" : "unless" };
}

function renderBlocks(blocks: readonly Block[], env: Env): Block[] {
  const out: Block[] = [];
  let i = 0;
  const walk = (): Block[] => {
    const acc: Block[] = [];
    while (i < blocks.length) {
      const b = blocks[i] as Block;
      const c = controlOf(b);
      if (c && (c.kind === "else" || c.kind === "end")) return acc;
      i++;
      if (c && (c.kind === "if" || c.kind === "unless")) {
        const yes = walk();
        let no: Block[] = [];
        const mid = i < blocks.length ? controlOf(blocks[i] as Block) : null;
        if (mid?.kind === "else") {
          i++;
          no = walk();
        }
        const end = i < blocks.length ? controlOf(blocks[i] as Block) : null;
        if (end?.kind !== "end" || end.close !== c.kind) env.errors.push(`unclosed:${c.kind}:${c.expr ?? ""}`);
        else i++;
        const v = evaluate(c.expr ?? "", env.ctx, env);
        acc.push(...((c.kind === "if" ? v : !v) ? yes : no));
        continue;
      }
      acc.push(b);
    }
    return acc;
  };
  const chosen = walk();
  while (i < blocks.length) {
    env.errors.push("stray_control");
    i++;
    chosen.push(...walk());
  }
  for (const b of chosen) out.push(...renderBlock(b, env));
  return out;
}

function renderBlock(b: Block, env: Env): Block[] {
  if (b.type === "table") return [b];
  if (b.type === "bulletList" || b.type === "orderedList") {
    const items: ListItem[] = b.content
      .map((li) => ({ type: "listItem" as const, content: renderBlocks(li.content, env) }))
      .filter((li) => li.content.length > 0);
    return items.length ? [{ type: b.type, content: items }] : [];
  }
  // A paragraph holding only a table variable becomes the table.
  const only = new RegExp(`^${VAR.source}$`).exec(inlineText(b.content).trim());
  if (b.type === "paragraph" && only?.[1] && isTable(env.ctx[only[1]])) {
    const path = only[1];
    note(env, path);
    const t = env.ctx[path] as TableValue;
    return t.rows.length ? [{ type: "table", head: t.head, rows: t.rows }] : [];
  }
  const content = renderInline(b.content, env);
  if (b.type === "heading") return [{ type: "heading", attrs: b.attrs, content }];
  return content.length ? [{ type: "paragraph", content }] : [];
}

export function renderDoc(doc: RichDoc, ctx: TemplateContext, known: ReadonlySet<string>): RenderResult {
  const env: Env = { ctx, known, unknown: new Set(), missing: new Set(), errors: [] };
  const blocks = renderBlocks(doc.content, env);
  return {
    blocks,
    unknown: [...env.unknown].sort(),
    missing: [...env.missing].sort(),
    errors: [...new Set(env.errors)],
  };
}

/** Every variable and condition path a document uses (for the template editor's checks). */
export function usedPaths(doc: RichDoc): string[] {
  const found = new Set<string>();
  const scan = (s: string) => {
    for (const m of s.matchAll(VAR)) found.add(m[1] ?? "");
    for (const m of s.matchAll(/\{\{\s*#(?:if|unless)\s+!?\s*([a-z][a-z0-9_.]*)/g)) found.add(m[1] ?? "");
  };
  const walk = (bs: readonly Block[]) => {
    for (const b of bs) {
      if (b.type === "paragraph" || b.type === "heading") scan(inlineText(b.content));
      else if (b.type !== "table") for (const li of b.content) walk(li.content);
    }
  };
  walk(doc.content);
  return [...found].sort();
}
