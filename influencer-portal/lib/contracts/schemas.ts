// Inputs for contract actions (client and server) and the database errors they map to.
import { z } from "zod";
import { DEAL_MODELS } from "@/lib/deals/schemas";
import { counterTerms } from "./counter";
import { plainText, richDoc, type RichDoc } from "./doc";
import { CLAUSE_CATEGORIES } from "./library";
import { renderDoc } from "./template";
import { VARIABLE_KEYS } from "./variables";

export const EDITABLE_CATEGORIES = [...CLAUSE_CATEGORIES, "other"] as const;
export type EditableCategory = (typeof EDITABLE_CATEGORIES)[number];

/** A template condition: `path`, `!path`, `path == "x"` or `path != "x"` (same rule as the database check). */
export const CONDITION = /^!?\s*[a-z][a-z0-9_.]*(\s*(==|!=)\s*"[^"]*")?$/;

/** Unknown variables and malformed conditionals in a clause, header or footer (empty when it is sound). */
export function docIssues(doc: RichDoc): { unknown: string[]; errors: string[] } {
  const r = renderDoc(doc, {}, VARIABLE_KEYS);
  return { unknown: r.unknown, errors: r.errors };
}

const soundDoc = richDoc.superRefine((d, ctx) => {
  const { unknown, errors } = docIssues(d);
  if (unknown.length) ctx.addIssue({ code: "custom", message: `unknown:${unknown.join(",")}` });
  if (errors.length) ctx.addIssue({ code: "custom", message: `errors:${errors.join(",")}` });
});

export const clauseInput = z
  .object({
    id: z.uuid().optional(),
    key: z.string().regex(/^[a-z][a-z0-9_]{1,59}$/),
    category: z.enum(EDITABLE_CATEGORIES),
    dealTypes: z.array(z.enum(DEAL_MODELS)).max(DEAL_MODELS.length),
    title: z.string().trim().min(2).max(160),
    body: soundDoc,
    required: z.boolean(),
    negotiable: z.boolean(),
    locked: z.boolean(),
  })
  .refine((c) => !(c.negotiable && c.locked), { path: ["locked"], message: "negotiable_locked" });
export type ClauseInput = z.input<typeof clauseInput>;

export const templateInput = z.object({
  id: z.uuid().optional(),
  name: z.string().trim().min(2).max(120),
  description: z.string().trim().max(500),
  title: z.string().trim().min(2).max(200),
  header: soundDoc,
  footer: soundDoc,
  isDefault: z.boolean(),
  clauses: z
    .array(
      z.object({
        clauseId: z.uuid(),
        condition: z
          .string()
          .trim()
          .max(120)
          .refine((c) => c === "" || CONDITION.test(c), "condition"),
      }),
    )
    .min(1)
    .max(60)
    .refine((cs) => new Set(cs.map((c) => c.clauseId)).size === cs.length, "duplicate_clause"),
});
export type TemplateInput = z.input<typeof templateInput>;

export const contractCreateInput = z.object({
  dealId: z.uuid(),
  templateId: z.uuid(),
  payeeAgencyId: z.uuid().nullable(),
  parentContractId: z.uuid().nullable(),
  kind: z.enum(["original", "renewal"]),
  effectiveOn: z.iso.date().or(z.literal("")),
  expiresOn: z.iso.date().or(z.literal("")),
  stampDutyReference: z.string().trim().max(120),
});
export type ContractCreateInput = z.input<typeof contractCreateInput>;

/** Staff answer to a clause change request: accept the suggested wording, or counter with their own. */
export const clauseDecisionInput = z.discriminatedUnion("decision", [
  z.object({ requestId: z.uuid(), contractId: z.uuid(), decision: z.literal("accepted") }),
  z.object({
    requestId: z.uuid(),
    contractId: z.uuid(),
    decision: z.literal("countered"),
    body: richDoc,
    note: z.string().trim().min(2).max(1000),
  }),
  z.object({
    requestId: z.uuid(),
    contractId: z.uuid(),
    decision: z.literal("rejected"),
    note: z.string().trim().min(2).max(1000),
  }),
]);
export type ClauseDecisionInput = z.input<typeof clauseDecisionInput>;

/** Staff answer to a compensation counter-offer: accept it as proposed, or counter with other values. */
export const compDecisionInput = z.discriminatedUnion("decision", [
  z.object({ requestId: z.uuid(), contractId: z.uuid(), decision: z.literal("accepted") }),
  z.object({
    requestId: z.uuid(),
    contractId: z.uuid(),
    decision: z.literal("countered"),
    terms: counterTerms,
    note: z.string().trim().min(2).max(1000),
  }),
  z.object({
    requestId: z.uuid(),
    contractId: z.uuid(),
    decision: z.literal("rejected"),
    note: z.string().trim().min(2).max(1000),
  }),
]);
export type CompDecisionInput = z.input<typeof compDecisionInput>;

export const commentInput = z.object({
  contractId: z.uuid(),
  clauseKey: z.string().min(1).max(60),
  body: z.string().trim().min(1).max(4000),
  parentId: z.uuid().nullable(),
});
export type CommentInput = z.input<typeof commentInput>;

export const changeRequestInput = z.discriminatedUnion("kind", [
  z.object({
    contractId: z.uuid(),
    kind: z.literal("clause"),
    clauseKey: z.string().min(1).max(60),
    // Suggested wording is literal text: template syntax would be interpreted when the version is assembled.
    body: richDoc.refine((d) => d.content.length > 0 && !plainText(d.content).includes("{{"), "braces"),
    note: z.string().trim().max(1000),
  }),
  z.object({
    contractId: z.uuid(),
    kind: z.literal("compensation"),
    terms: counterTerms,
    note: z.string().trim().max(1000),
  }),
]);
export type ChangeRequestInput = z.input<typeof changeRequestInput>;

export const contractStatusInput = z.object({
  contractId: z.uuid(),
  status: z.enum(["void", "terminated", "completed"]),
  reason: z.string().trim().min(3).max(500),
});
export type ContractStatusInput = z.input<typeof contractStatusInput>;

export const CONTRACT_DB_ERRORS: [RegExp, string][] = [
  [/legally reviewed/i, "unreviewed"],
  [/details are missing/i, "missing"],
  [/no agreed terms/i, "noTerms"],
  [/deal is closed/i, "dealClosed"],
  [/already has an open contract/i, "openExists"],
  [/active contract: amend/i, "activeExists"],
  [/only an active contract/i, "parent"],
  [/cannot be the payee/i, "payee"],
  [/signed or closed contract/i, "locked"],
  [/only a draft can be sent/i, "notDraft"],
  [/no content yet/i, "noContent"],
  [/cannot mark this contract ready/i, "notReady"],
  [/pending change request/i, "pendingRequests"],
  [/cannot move a/i, "transition"],
  [/reason is required/i, "reason"],
  [/change request is not pending/i, "notPending"],
  [/not negotiable/i, "notNegotiable"],
  [/already pending/i, "duplicateRequest"],
  [/comments are closed|negotiation is closed/i, "closed"],
  [/no such clause/i, "noClause"],
  [/invalid compensation config/i, "config"],
  [/used by a template/i, "clauseInUse"],
  [/template with this name/i, "templateName"],
  [/duplicate key value/i, "duplicateKey"],
  [/already reviewed/i, "alreadyReviewed"],
];

export const signCodeInput = z.object({ contractId: z.uuid(), channel: z.enum(["email", "whatsapp"]) });
export type SignCodeInput = z.input<typeof signCodeInput>;

export const signInput = z.object({
  contractId: z.uuid(),
  versionId: z.uuid(),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
  name: z.string().trim().min(2).max(160),
  consentVersion: z.number().int().min(1),
  code: z.string().regex(/^\d{6}$/),
});
export type SignInput = z.input<typeof signInput>;

/** What inf.contract_sign_code_issue and inf.contract_sign answer when they refuse (message keys). */
export const SIGN_ERRORS = [
  "cannot_sign",
  "channel",
  "cooldown",
  "too_many_codes",
  "changed",
  "consent",
  "name",
  "expired",
  "too_many_attempts",
  "wrong_code",
] as const;
