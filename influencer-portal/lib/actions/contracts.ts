"use server";
// Contract actions. Staff edit the clause library and templates, generate contracts from deals, answer change
// requests (each accepted or countered round is a new version) and move contracts through their states. Creators and
// their negotiating agencies comment, suggest wording for negotiable clauses and send structured compensation
// counter-offers. Each action validates its input and calls inf.* functions, which decide who may act.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { applyCounter, counterTerms, type ApplyError } from "@/lib/contracts/counter";
import { loadContract, loadContractSource } from "@/lib/contracts/data";
import { richDoc } from "@/lib/contracts/doc";
import { generateVersion, type GenerateResult, type Resolution } from "@/lib/contracts/generate";
import {
  changeRequestInput,
  clauseDecisionInput,
  clauseInput,
  commentInput,
  compDecisionInput,
  contractCreateInput,
  contractStatusInput,
  CONTRACT_DB_ERRORS,
  templateInput,
  type ChangeRequestInput,
  type ClauseDecisionInput,
  type ClauseInput,
  type CommentInput,
  type CompDecisionInput,
  type ContractCreateInput,
  type ContractStatusInput,
  type TemplateInput,
} from "@/lib/contracts/schemas";
import { log } from "@/lib/log";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
const uuid = z.uuid();

async function signedIn(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

function dbFail(error: { code?: string; message: string }, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of CONTRACT_DB_ERRORS)
    if (re.test(error.message)) return fail(t(`contracts.errors.${key}` as "contracts.errors.locked"));
  if (error.code === "22023" || error.code === "23514" || error.code === "23505") return fail(t("errors.invalidInput"));
  log.warn("contracts.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

function generateFail(r: Extract<GenerateResult, { ok: false }>, t: T): ActionResult<never> {
  if (r.error === "db") return dbFail({ code: r.code, message: r.message ?? "" }, t);
  if (r.error === "template") return fail(t("contracts.errors.template", { detail: r.detail.slice(0, 5).join(", ") }));
  if (r.error === "no_terms") return fail(t("contracts.errors.noTerms"));
  return fail(t("errors.notFoundBody"));
}

function applyFail(error: ApplyError, t: T): ActionResult<never> {
  return fail(t(`contracts.errors.counter.${error}` as "contracts.errors.counter.no_change"));
}

function refresh(contractId?: string) {
  revalidatePath("/admin/contracts", "layout");
  revalidatePath("/admin/deals", "layout");
  revalidatePath("/creator/contracts", "layout");
  revalidatePath("/agency", "layout");
  if (contractId) revalidatePath(`/admin/contracts/${contractId}`);
}

function generated(r: GenerateResult, t: T, ok: string): ActionResult<{ missing: string[] }> {
  if (!r.ok) return generateFail(r, t);
  return {
    ok: true,
    data: { missing: r.missing },
    message: r.missing.length ? t("contracts.savedWithMissing", { fields: r.missing.join(", ") }) : ok,
  };
}

// ---------------------------------------------------------------------------------------------------------------
// Clause library and templates
// ---------------------------------------------------------------------------------------------------------------
export async function saveClause(input: ClauseInput): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const parsed = clauseInput.safeParse(input);
  if (!parsed.success) {
    const msg = parsed.error.issues[0]?.message ?? "";
    if (msg.startsWith("unknown:") || msg.startsWith("errors:"))
      return fail(t("contracts.errors.template", { detail: msg.replace(/^\w+:/, "") }));
    if (msg === "negotiable_locked") return fail(t("contracts.errors.negotiableLocked"));
    return fail(t("errors.invalidInput"));
  }
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { data, error } = await supabase.rpc("clause_save", {
    p: {
      id: v.id ?? null,
      key: v.key,
      category: v.category,
      deal_types: v.dealTypes,
      title: v.title,
      body: v.body,
      required: v.required,
      negotiable: v.negotiable,
      locked: v.locked,
    },
  });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/contracts", "layout");
  return { ok: true, data: { id: data }, message: t("contracts.library.saved") };
}

export async function markClauseReviewed(clauseId: string, version: number): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(clauseId).success || !Number.isInteger(version) || version < 1)
    return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("clause_mark_reviewed", {
    p_clause: clauseId,
    p_version: version,
  });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/contracts", "layout");
  return { ok: true, message: t("contracts.library.reviewed") };
}

export async function archiveClause(clauseId: string, archived: boolean): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(clauseId).success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("clause_archive", {
    p_clause: clauseId,
    p_archived: archived,
  });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/contracts", "layout");
  return {
    ok: true,
    message: archived ? t("contracts.library.archived") : t("contracts.library.restored"),
  };
}

export async function saveTemplate(input: TemplateInput): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const parsed = templateInput.safeParse(input);
  if (!parsed.success) {
    const msg = parsed.error.issues[0]?.message ?? "";
    if (msg.startsWith("unknown:") || msg.startsWith("errors:"))
      return fail(t("contracts.errors.template", { detail: msg.replace(/^\w+:/, "") }));
    if (msg === "condition") return fail(t("contracts.errors.condition"));
    return fail(t("errors.invalidInput"));
  }
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { data, error } = await supabase.rpc("template_save", {
    p: {
      id: v.id ?? null,
      name: v.name,
      description: v.description,
      title: v.title,
      header: v.header,
      footer: v.footer,
      is_default: v.isDefault,
      clauses: v.clauses.map((c) => ({ clause_id: c.clauseId, condition: c.condition || null })),
    },
  });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/contracts", "layout");
  return { ok: true, data: { id: data }, message: t("contracts.templates.saved") };
}

export async function archiveTemplate(templateId: string, archived: boolean): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(templateId).success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("template_archive", {
    p_template: templateId,
    p_archived: archived,
  });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/contracts", "layout");
  return {
    ok: true,
    message: archived ? t("contracts.templates.archived") : t("contracts.templates.restored"),
  };
}

// ---------------------------------------------------------------------------------------------------------------
// Contracts (staff)
// ---------------------------------------------------------------------------------------------------------------
export async function createContract(input: ContractCreateInput): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const parsed = contractCreateInput.safeParse(input);
  if (!parsed.success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { data: id, error } = await supabase.rpc("contract_create", {
    p: {
      deal_id: v.dealId,
      template_id: v.templateId,
      payee_agency_id: v.payeeAgencyId,
      parent_contract_id: v.parentContractId,
      kind: v.kind,
      effective_on: v.effectiveOn,
      expires_on: v.expiresOn,
      stamp_duty_reference: v.stampDutyReference,
    },
  });
  if (error) return dbFail(error, t);
  const r = await generateVersion(supabase, id, { note: t("contracts.firstVersionNote") });
  refresh(id);
  if (!r.ok) {
    // The draft exists; staff fix the template or the deal and regenerate from the contract page.
    const f = generateFail(r, t);
    return { ok: true, data: { id }, message: f.ok ? undefined : f.error };
  }
  return {
    ok: true,
    data: { id },
    message: r.missing.length
      ? t("contracts.savedWithMissing", { fields: r.missing.join(", ") })
      : t("contracts.created"),
  };
}

const noteSchema = z.string().trim().max(1000);

/** A new version from the deal's current terms and the template (keeps agreed clause wording). */
export async function regenerateContract(
  contractId: string,
  note: string,
): Promise<ActionResult<{ missing: string[] }>> {
  const t = await getTranslations();
  const n = noteSchema.safeParse(note);
  if (!uuid.safeParse(contractId).success || !n.success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const r = await generateVersion(supabase, contractId, {
    note: n.data || t("contracts.regeneratedNote"),
  });
  refresh(contractId);
  return generated(r, t, t("contracts.regenerated"));
}

export async function sendContract(contractId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(contractId).success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("contract_send", { p_contract: contractId });
  if (error) return dbFail(error, t);
  refresh(contractId);
  return { ok: true, message: t("contracts.sent") };
}

export async function markReadyToSign(contractId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(contractId).success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("contract_set_ready", { p_contract: contractId });
  if (error) return dbFail(error, t);
  refresh(contractId);
  return { ok: true, message: t("contracts.markedReady") };
}

export async function setContractStatus(input: ContractStatusInput): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = contractStatusInput.safeParse(input);
  if (!parsed.success) return fail(t("contracts.errors.reason"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { error } = await supabase.rpc("contract_set_status", {
    p_contract: v.contractId,
    p_status: v.status,
    p_reason: v.reason,
  });
  if (error) return dbFail(error, t);
  refresh(v.contractId);
  return { ok: true, message: t("contracts.statusChanged") };
}

async function pendingRequest(supabase: ServerSupabase, contractId: string, requestId: string) {
  const c = await loadContract(supabase, contractId);
  const r = c?.requests.find((x) => x.id === requestId && x.status === "pending");
  return c && r ? { contract: c, request: r } : null;
}

async function reject(supabase: ServerSupabase, t: T, requestId: string, note: string, contractId: string) {
  const { error } = await supabase.rpc("change_request_decide", {
    p_request: requestId,
    p_status: "rejected",
    p_note: note,
  });
  if (error) return dbFail(error, t);
  refresh(contractId);
  return { ok: true as const, message: t("contracts.requests.rejected") };
}

/** Accept the suggested wording of a negotiable clause, counter it with Eduwit's wording, or reject it. */
export async function decideClauseRequest(input: ClauseDecisionInput): Promise<ActionResult<{ missing: string[] }>> {
  const t = await getTranslations();
  const parsed = clauseDecisionInput.safeParse(input);
  if (!parsed.success) return fail(t("contracts.errors.reason"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  if (v.decision === "rejected") return reject(supabase, t, v.requestId, v.note, v.contractId);
  const found = await pendingRequest(supabase, v.contractId, v.requestId);
  if (!found || found.request.kind !== "clause" || !found.request.clause_key)
    return fail(t("contracts.errors.notPending"));
  const body = v.decision === "accepted" ? found.request.proposed_body : v.body;
  const doc = richDoc.safeParse(body);
  if (!doc.success) return fail(t("errors.invalidInput"));
  const resolution: Resolution = {
    id: v.requestId,
    status: v.decision,
    note: v.decision === "countered" ? v.note : undefined,
  };
  const r = await generateVersion(supabase, v.contractId, {
    overrides: { [found.request.clause_key]: doc.data },
    note:
      v.decision === "accepted"
        ? t("contracts.requests.acceptedNote", { clause: found.request.clause_key })
        : t("contracts.requests.counteredNote", { clause: found.request.clause_key }),
    resolve: [resolution],
  });
  refresh(v.contractId);
  return generated(
    r,
    t,
    v.decision === "accepted" ? t("contracts.requests.accepted") : t("contracts.requests.countered"),
  );
}

/**
 * Accept a compensation counter-offer as proposed, or counter it with other values. Either way the deal's terms are
 * replaced by a new accepted version and the contract is regenerated from it, so every number in the contract still
 * comes from the deal.
 */
export async function decideCompRequest(input: CompDecisionInput): Promise<ActionResult<{ missing: string[] }>> {
  const t = await getTranslations();
  const parsed = compDecisionInput.safeParse(input);
  if (!parsed.success) return fail(t("contracts.errors.reason"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  if (v.decision === "rejected") return reject(supabase, t, v.requestId, v.note, v.contractId);
  const found = await pendingRequest(supabase, v.contractId, v.requestId);
  if (!found || found.request.kind !== "compensation") return fail(t("contracts.errors.notPending"));
  const proposed = counterTerms.safeParse(found.request.proposed_terms);
  if (!proposed.success) return fail(t("contracts.errors.counter.unknown_item"));
  const src = await loadContractSource(supabase, found.contract.deal_id);
  if (!src?.deal.comp_config) return fail(t("contracts.errors.noTerms"));
  const changes = v.decision === "accepted" ? proposed.data.changes : v.terms.changes;
  const applied = applyCounter(src.deal.comp_config, changes);
  if (!applied.ok) return applyFail(applied.error, t);
  const { error } = await supabase.rpc("deal_version_from_counter", {
    p_request: v.requestId,
    p_config: applied.config,
  });
  if (error) return dbFail(error, t);
  const r = await generateVersion(supabase, v.contractId, {
    note:
      v.decision === "accepted" ? t("contracts.requests.compAcceptedNote") : t("contracts.requests.compCounteredNote"),
    resolve: [
      {
        id: v.requestId,
        status: v.decision,
        note: v.decision === "countered" ? v.note : undefined,
      },
    ],
  });
  refresh(v.contractId);
  revalidatePath(`/admin/deals/${found.contract.deal_id}`);
  return generated(
    r,
    t,
    v.decision === "accepted" ? t("contracts.requests.accepted") : t("contracts.requests.countered"),
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Negotiation (creator, agency, and staff comments)
// ---------------------------------------------------------------------------------------------------------------
export async function addContractComment(input: CommentInput): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = commentInput.safeParse(input);
  if (!parsed.success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const { error } = await supabase.rpc("contract_comment_add", {
    p_contract: v.contractId,
    p_clause: v.clauseKey,
    p_body: v.body,
    p_parent: v.parentId ?? undefined,
  });
  if (error) return dbFail(error, t);
  refresh(v.contractId);
  return { ok: true, message: t("contracts.comments.added") };
}

export async function resolveContractComment(commentId: string, contractId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(commentId).success || !uuid.safeParse(contractId).success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("contract_comment_resolve", { p_comment: commentId });
  if (error) return dbFail(error, t);
  refresh(contractId);
  return { ok: true, message: t("contracts.comments.resolved") };
}

export async function requestContractChange(input: ChangeRequestInput): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = changeRequestInput.safeParse(input);
  if (!parsed.success)
    return fail(
      parsed.error.issues.some((i) => i.message === "braces") ? t("contracts.errors.braces") : t("errors.invalidInput"),
    );
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = parsed.data;
  const p =
    v.kind === "clause"
      ? { kind: "clause", clause_key: v.clauseKey, proposed_body: v.body, note: v.note }
      : { kind: "compensation", proposed_terms: v.terms, note: v.note };
  const { error } = await supabase.rpc("change_request_create", { p_contract: v.contractId, p });
  if (error) return dbFail(error, t);
  refresh(v.contractId);
  return { ok: true, message: t("contracts.requests.sent") };
}

export async function withdrawContractChange(requestId: string, contractId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(requestId).success || !uuid.safeParse(contractId).success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("change_request_withdraw", { p_request: requestId });
  if (error) return dbFail(error, t);
  refresh(contractId);
  return { ok: true, message: t("contracts.requests.withdrawn") };
}
