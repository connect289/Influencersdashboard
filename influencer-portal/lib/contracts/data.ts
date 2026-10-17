import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import type { Database } from "@/lib/database.types";
import type { ContractContent } from "./assemble";
import { contractSource, templateSource, type ContractSource, type TemplateSource } from "./build";
import { contentBlock, richDoc } from "./doc";

export { buildVersion, type BuiltVersion, type ContractSource, type TemplateSource } from "./build";

/** The person's client (lib/supabase/server) or, for system work, the service-role client. */
export type Db = SupabaseClient<Database, "inf">;

// ---------------------------------------------------------------------------------------------------------------
// Library and templates
// ---------------------------------------------------------------------------------------------------------------
export const CONTRACT_STATUSES = [
  "draft",
  "sent",
  "in_negotiation",
  "ready_to_sign",
  "signed_by_creator",
  "active",
  "completed",
  "terminated",
  "expired",
  "void",
  "superseded",
] as const;
export type ContractStatus = (typeof CONTRACT_STATUSES)[number];
export const OPEN_CONTRACT_STATUSES: readonly ContractStatus[] = [
  "draft",
  "sent",
  "in_negotiation",
  "ready_to_sign",
  "signed_by_creator",
];

export const libraryClause = z.object({
  id: z.uuid(),
  key: z.string(),
  category: z.string(),
  deal_types: z.array(z.string()),
  version: z.number().int(),
  title: z.string(),
  body: richDoc,
  required: z.boolean(),
  negotiable: z.boolean(),
  locked: z.boolean(),
  reviewed_at: z.string().nullable(),
  archived: z.boolean(),
  updated_at: z.string(),
  versions: z.number().int(),
});
export type LibraryClause = z.infer<typeof libraryClause>;

export async function loadLibrary(supabase: Db, includeArchived = false): Promise<LibraryClause[]> {
  const { data, error } = await supabase.rpc("clause_library", {
    p_include_archived: includeArchived,
  });
  if (error) throw new Error(error.message);
  return z.array(libraryClause).parse(data);
}

export const clauseVersion = z.object({
  version: z.number().int(),
  title: z.string(),
  body: richDoc,
  required: z.boolean(),
  negotiable: z.boolean(),
  locked: z.boolean(),
  reviewed_at: z.string().nullable(),
  created_at: z.string(),
});
export type ClauseVersion = z.infer<typeof clauseVersion>;

export async function loadClauseHistory(supabase: Db, clauseId: string): Promise<ClauseVersion[]> {
  const { data, error } = await supabase.rpc("clause_history", { p_clause: clauseId });
  if (error) throw new Error(error.message);
  return z.array(clauseVersion).parse(data);
}

export async function loadTemplate(supabase: Db, id: string): Promise<TemplateSource | null> {
  const { data, error } = await supabase.rpc("template_source", { p_template: id });
  if (error) throw new Error(error.message);
  return data === null ? null : templateSource.parse(data);
}

// ---------------------------------------------------------------------------------------------------------------
// Building a version
// ---------------------------------------------------------------------------------------------------------------

export async function loadContractSource(supabase: Db, dealId: string): Promise<ContractSource | null> {
  const { data, error } = await supabase.rpc("contract_source", { p_deal: dealId });
  if (error) throw new Error(error.message);
  return data === null ? null : contractSource.parse(data);
}

// ---------------------------------------------------------------------------------------------------------------
// Contract detail
// ---------------------------------------------------------------------------------------------------------------
const section = z.object({
  key: z.string(),
  number: z.number(),
  clause_id: z.string(),
  clause_version: z.number(),
  category: z.string(),
  title: z.string(),
  negotiable: z.boolean(),
  locked: z.boolean(),
  amended: z.boolean(),
  blocks: z.array(contentBlock),
});
export const contractContent = z.object({
  title: z.string(),
  header: z.array(contentBlock),
  sections: z.array(section),
  footer: z.array(contentBlock),
});

export const contractDetailSchema = z.object({
  id: z.uuid(),
  number: z.string(),
  kind: z.enum(["original", "amendment", "renewal"]),
  status: z.enum(CONTRACT_STATUSES),
  deal_id: z.uuid(),
  template_id: z.uuid(),
  parent: z.object({ id: z.uuid(), number: z.string() }).nullable(),
  effective_on: z.string().nullable(),
  expires_on: z.string().nullable(),
  stamp_duty_reference: z.string().nullable(),
  negotiation_deadline: z.string().nullable(),
  sent_at: z.string().nullable(),
  creator_signed_at: z.string().nullable(),
  countersigned_at: z.string().nullable(),
  closed_at: z.string().nullable(),
  status_reason: z.string().nullable(),
  integrity_failed_at: z.string().nullable(),
  payee_agency_id: z.uuid().nullable(),
  deal: z.object({
    id: z.uuid(),
    code: z.string(),
    title: z.string(),
    status: z.string(),
    current_version_id: z.uuid().nullable(),
  }),
  creator: z.object({ id: z.uuid(), display_name: z.string(), handle: z.string() }),
  side: z.enum(["eduwit", "creator", "agency"]),
  current: z
    .object({
      id: z.uuid(),
      version: z.number(),
      content: contractContent,
      sha256: z.string(),
      created_at: z.string(),
      note: z.string().nullable(),
      deal_version_id: z.uuid(),
      missing_fields: z.array(z.string()),
    })
    .nullable(),
  versions: z.array(
    z.object({
      id: z.uuid(),
      version: z.number(),
      sha256: z.string(),
      created_at: z.string(),
      note: z.string().nullable(),
    }),
  ),
  comments: z.array(
    z.object({
      id: z.uuid(),
      clause_key: z.string(),
      parent_id: z.uuid().nullable(),
      author_side: z.enum(["creator", "agency", "eduwit"]),
      body: z.string(),
      created_at: z.string(),
      resolved: z.boolean(),
      mine: z.boolean(),
    }),
  ),
  requests: z.array(
    z.object({
      id: z.uuid(),
      kind: z.enum(["clause", "compensation"]),
      clause_key: z.string().nullable(),
      proposed_body: richDoc.nullable(),
      proposed_terms: z.record(z.string(), z.unknown()).nullable(),
      note: z.string().nullable(),
      from_side: z.enum(["creator", "agency"]),
      status: z.enum(["pending", "accepted", "rejected", "countered", "withdrawn"]),
      created_at: z.string(),
      decided_at: z.string().nullable(),
      decision_note: z.string().nullable(),
      resolved_in_version_id: z.uuid().nullable(),
      version_id: z.uuid(),
    }),
  ),
  signatures: z.array(
    z.object({
      id: z.uuid(),
      version_id: z.uuid(),
      signer_role: z.enum(["creator", "agency", "signatory"]),
      signer_name: z.string(),
      signer_designation: z.string().nullable(),
      document_sha256: z.string(),
      signed_at: z.string(),
      signed_at_ist: z.string(),
      otp_channel: z.string(),
    }),
  ),
  file: z.object({ id: z.uuid(), sha256: z.string(), created_at: z.string() }).nullable(),
  can_write: z.boolean(),
  can_countersign: z.boolean(),
  consent: z.object({ version: z.number(), body: z.string() }).nullable(),
});
export type ContractDetail = z.infer<typeof contractDetailSchema>;

export async function loadContract(supabase: Db, id: string): Promise<ContractDetail | null> {
  const { data, error } = await supabase.rpc("contract_detail", { p_contract: id });
  if (error) throw new Error(error.message);
  return data === null ? null : contractDetailSchema.parse(data);
}

export async function loadVersionContent(
  supabase: Db,
  versionId: string,
): Promise<{ content: ContractContent; html: string; sha256: string; computed: string } | null> {
  const { data, error } = await supabase.rpc("contract_version_html", { p_version: versionId });
  if (error) throw new Error(error.message);
  if (!data) return null;
  const v = z
    .object({
      html: z.string(),
      sha256: z.string(),
      computed_sha256: z.string(),
      content: contractContent,
    })
    .parse(data);
  return { content: v.content, html: v.html, sha256: v.sha256, computed: v.computed_sha256 };
}

export const contractRowSchema = z.object({
  id: z.uuid(),
  number: z.string(),
  kind: z.string(),
  status: z.enum(CONTRACT_STATUSES),
  deal_id: z.uuid(),
  deal_code: z.string().optional(),
  deal_title: z.string(),
  creator_name: z.string().optional(),
  handle: z.string().optional(),
  updated_at: z.string(),
  pending_requests: z.number().optional(),
  needs_action: z.boolean().optional(),
});
export type ContractRow = z.infer<typeof contractRowSchema>;

export async function loadMyContracts(supabase: Db, creatorId: string): Promise<ContractRow[]> {
  const { data, error } = await supabase.rpc("my_contracts", { p_creator: creatorId });
  if (error) throw new Error(error.message);
  return z.array(contractRowSchema).parse(data);
}

/** Active templates for pickers (campaign builder, contract generation). Empty for people who cannot read them. */
export async function templateOptions(supabase: Db): Promise<{ id: string; name: string; is_default: boolean }[]> {
  const { data } = await supabase
    .from("contract_templates")
    .select("id, name, is_default")
    .is("archived_at", null)
    .order("name");
  return z
    .array(z.object({ id: z.uuid(), name: z.string(), is_default: z.boolean() }))
    .catch([])
    .parse(data ?? []);
}
