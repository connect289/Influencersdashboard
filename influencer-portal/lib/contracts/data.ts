import "server-only";
import { z } from "zod";
import { deliverableItem } from "@/lib/campaigns/schemas";
import { compConfig } from "@/lib/compensation/schema";
import type { ServerSupabase } from "@/lib/supabase/server";
import { assembleContract, type AssembleResult, type ClauseInput, type ContractContent } from "./assemble";
import { richDoc, type RichDoc } from "./doc";
import { contractHtml } from "./html";
import { buildContext } from "./variables";

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

export async function loadLibrary(supabase: ServerSupabase, includeArchived = false): Promise<LibraryClause[]> {
  const { data, error } = await supabase.rpc("clause_library", { p_include_archived: includeArchived });
  if (error) throw new Error(error.message);
  return z.array(libraryClause).parse(data);
}

const templateClause = z.object({
  clause_id: z.uuid(),
  key: z.string(),
  category: z.string(),
  version: z.number().int(),
  title: z.string(),
  body: richDoc,
  required: z.boolean(),
  negotiable: z.boolean(),
  locked: z.boolean(),
  reviewed: z.boolean(),
  condition: z.string().nullable(),
});
export const templateSource = z.object({
  id: z.uuid(),
  name: z.string(),
  description: z.string().nullable(),
  title: z.string(),
  header: richDoc,
  footer: richDoc,
  is_default: z.boolean(),
  archived: z.boolean(),
  clauses: z.array(templateClause),
});
export type TemplateSource = z.infer<typeof templateSource>;

export async function loadTemplate(supabase: ServerSupabase, id: string): Promise<TemplateSource | null> {
  const { data, error } = await supabase.rpc("template_source", { p_template: id });
  if (error) throw new Error(error.message);
  return data === null ? null : templateSource.parse(data);
}

// ---------------------------------------------------------------------------------------------------------------
// Building a version
// ---------------------------------------------------------------------------------------------------------------
const contractSourceSchema = z.object({
  deal: z.object({
    id: z.uuid(),
    code: z.string(),
    title: z.string(),
    status: z.string(),
    starts_on: z.string(),
    ends_on: z.string().nullable(),
    deal_model: z.string(),
    agreed_terms: z
      .object({ deliverables: z.array(deliverableItem).optional() })
      .loose()
      .nullable(),
    current_version_id: z.uuid().nullable(),
    comp_config: compConfig.nullable(),
  }),
  creator: z.object({
    id: z.uuid(),
    display_name: z.string(),
    handle: z.string(),
    city: z.string().nullable(),
    state: z.string().nullable(),
    email: z.string().nullable(),
    legal_name: z.string().nullable(),
    pan_last4: z.string().nullable(),
    gstin: z.string().nullable(),
  }),
  campaign: z.object({ name: z.string(), deliverables: z.array(deliverableItem).catch([]) }).nullable(),
  agencies: z.array(z.object({ id: z.uuid(), name: z.string() })),
  organisation: z
    .object({
      legal_name: z.string(),
      address: z.string(),
      gstin: z.string(),
      pan: z.string(),
      support_email: z.string(),
    })
    .loose(),
  signatory: z.object({ name: z.string(), designation: z.string().nullable() }).nullable(),
  contracts: z.array(z.object({ id: z.uuid(), number: z.string(), status: z.string(), kind: z.string() })),
});
export type ContractSource = z.infer<typeof contractSourceSchema>;

export async function loadContractSource(supabase: ServerSupabase, dealId: string): Promise<ContractSource | null> {
  const { data, error } = await supabase.rpc("contract_source", { p_deal: dealId });
  if (error) throw new Error(error.message);
  return data === null ? null : contractSourceSchema.parse(data);
}

export interface BuiltVersion extends AssembleResult {
  html: string;
}

/** Assembles a contract version from the deal's terms in force and the template. Pure apart from its inputs. */
export function buildVersion(
  src: ContractSource,
  template: TemplateSource,
  contract: { number: string; date: string; parent_number: string | null; payee_agency_id: string | null },
  overrides: Readonly<Record<string, RichDoc>> = {},
): BuiltVersion {
  if (!src.deal.comp_config) throw new Error("the deal has no agreed terms");
  const agency = contract.payee_agency_id ? src.agencies.find((a) => a.id === contract.payee_agency_id) : undefined;
  const legal = src.creator.legal_name ?? src.creator.display_name;
  const ctx = buildContext({
    creator: {
      legal_name: src.creator.legal_name,
      display_name: src.creator.display_name,
      handle: src.creator.handle,
      city: src.creator.city,
      state: src.creator.state,
      email: src.creator.email,
      pan_masked: src.creator.pan_last4 ? `XXXXXX${src.creator.pan_last4}` : null,
      gstin: src.creator.gstin,
    },
    payee: agency ? { name: agency.name, is_agency: true } : { name: legal, is_agency: false },
    deal: {
      code: src.deal.code,
      title: src.deal.title,
      starts_on: src.deal.starts_on,
      ends_on: src.deal.ends_on,
      model: src.deal.deal_model,
      config: src.deal.comp_config,
    },
    deliverables: src.deal.agreed_terms?.deliverables?.length
      ? src.deal.agreed_terms.deliverables
      : (src.campaign?.deliverables ?? []),
    campaign: src.campaign ? { name: src.campaign.name } : null,
    eduwit: {
      legal_name: src.organisation.legal_name,
      address: src.organisation.address,
      gstin: src.organisation.gstin,
      pan: src.organisation.pan,
      support_email: src.organisation.support_email,
    },
    signatory: src.signatory ? { name: src.signatory.name, designation: src.signatory.designation ?? "" } : null,
    contract: { number: contract.number, date: contract.date, parent_number: contract.parent_number },
  });
  const clauses: ClauseInput[] = template.clauses.map((c) => ({ ...c }));
  const r = assembleContract(
    { title: template.title, header: template.header, footer: template.footer, clauses },
    ctx,
    overrides,
  );
  return { ...r, html: contractHtml(r.content) };
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
  blocks: z.array(z.unknown()),
});
export const contractContent = z.object({
  title: z.string(),
  header: z.array(z.unknown()),
  sections: z.array(section),
  footer: z.array(z.unknown()),
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

export async function loadContract(supabase: ServerSupabase, id: string): Promise<ContractDetail | null> {
  const { data, error } = await supabase.rpc("contract_detail", { p_contract: id });
  if (error) throw new Error(error.message);
  return data === null ? null : contractDetailSchema.parse(data);
}

export async function loadVersionContent(
  supabase: ServerSupabase,
  versionId: string,
): Promise<{ content: ContractContent; html: string; sha256: string; computed: string } | null> {
  const { data, error } = await supabase.rpc("contract_version_html", { p_version: versionId });
  if (error) throw new Error(error.message);
  if (!data) return null;
  const v = z
    .object({ html: z.string(), sha256: z.string(), computed_sha256: z.string(), content: contractContent })
    .parse(data);
  return { content: v.content as ContractContent, html: v.html, sha256: v.sha256, computed: v.computed_sha256 };
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
