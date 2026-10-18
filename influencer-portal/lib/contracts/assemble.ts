// Builds a contract's content from a template, its clause versions and the deal context. Pure and deterministic:
// the same inputs always give the same content, so the content (and its hash) identifies a contract version.
import type { Block, RichDoc } from "./doc";
import { evaluate, renderDoc, renderString, type TemplateContext } from "./template";
import { VARIABLE_KEYS } from "./variables";

export interface ClauseInput {
  clause_id: string;
  version: number;
  key: string;
  category: string;
  title: string;
  body: RichDoc;
  negotiable: boolean;
  locked: boolean;
  required: boolean;
  reviewed: boolean;
  /** Show the clause only when this condition holds (template-level conditional). */
  condition: string | null;
}

export interface TemplateInput {
  title: string;
  header: RichDoc;
  footer: RichDoc;
  clauses: ClauseInput[];
}

export interface ContractSection {
  key: string;
  number: number;
  clause_id: string;
  clause_version: number;
  category: string;
  title: string;
  negotiable: boolean;
  locked: boolean;
  /** True when this contract uses negotiated wording instead of the library text. */
  amended: boolean;
  blocks: Block[];
}

export interface ContractContent {
  title: string;
  header: Block[];
  sections: ContractSection[];
  footer: Block[];
}

export interface AssembleResult {
  content: ContractContent;
  unknown: string[];
  missing: string[];
  errors: string[];
  /** Clause keys not yet marked as legally reviewed. */
  unreviewed: string[];
}

/**
 * @param overrides negotiated wording per clause key (accepted change requests); only negotiable clauses take them.
 */
export function assembleContract(
  t: TemplateInput,
  ctx: TemplateContext,
  overrides: Readonly<Record<string, RichDoc>> = {},
): AssembleResult {
  const unknown = new Set<string>();
  const missing = new Set<string>();
  const errors: string[] = [];
  const collect = (r: { unknown: string[]; missing: string[]; errors: string[] }) => {
    r.unknown.forEach((x) => unknown.add(x));
    r.missing.forEach((x) => missing.add(x));
    errors.push(...r.errors);
  };
  const env = { ctx, known: VARIABLE_KEYS, unknown, missing, errors };

  const header = renderDoc(t.header, ctx, VARIABLE_KEYS);
  collect(header);
  const sections: ContractSection[] = [];
  const unreviewed: string[] = [];
  for (const c of t.clauses) {
    if (c.condition && !evaluate(c.condition, ctx, env)) continue;
    const override = c.negotiable ? overrides[c.key] : undefined;
    const body = renderDoc(override ?? c.body, ctx, VARIABLE_KEYS);
    collect(body);
    if (!c.reviewed) unreviewed.push(c.key);
    sections.push({
      key: c.key,
      number: sections.length + 1,
      clause_id: c.clause_id,
      clause_version: c.version,
      category: c.category,
      title: renderString(c.title, env),
      negotiable: c.negotiable,
      locked: c.locked,
      amended: override !== undefined,
      blocks: body.blocks,
    });
  }
  const footer = renderDoc(t.footer, ctx, VARIABLE_KEYS);
  collect(footer);
  return {
    content: {
      title: renderString(t.title, env),
      header: header.blocks,
      sections,
      footer: footer.blocks,
    },
    unknown: [...unknown].sort(),
    missing: [...missing].sort(),
    errors: [...new Set(errors)],
    unreviewed,
  };
}

/** JSON with sorted keys, so equal content always serialises identically. */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(sortKeys(value));
}
function sortKeys(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v && typeof v === "object")
    return Object.fromEntries(
      Object.keys(v)
        .sort()
        .map((k) => [k, sortKeys((v as Record<string, unknown>)[k])]),
    );
  return v;
}
