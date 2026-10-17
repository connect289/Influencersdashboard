// Assembling a contract version from loaded data (the deal's terms in force, parties, template). Pure: used by the
// app (lib/contracts/generate.ts) and by the local seed script.
import { z } from "zod";
import { deliverableItem } from "@/lib/campaigns/schemas";
import { compConfig } from "@/lib/compensation/schema";
import { assembleContract, type AssembleResult, type ClauseInput } from "./assemble";
import { richDoc, type RichDoc } from "./doc";
import { contractHtml } from "./html";
import { buildContext } from "./variables";

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

export const contractSource = z.object({
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
    renewal_of: z.uuid().nullable().default(null),
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
  campaign: z
    .object({
      name: z.string(),
      deliverables: z.array(deliverableItem).catch([]),
      contract_template_id: z.uuid().nullable(),
    })
    .nullable(),
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
export type ContractSource = z.infer<typeof contractSource>;

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
