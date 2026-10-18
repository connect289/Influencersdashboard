import "server-only";
import { z } from "zod";
import { istToday } from "@/lib/format";
import { log } from "@/lib/log";
import { buildVersion, loadContractSource, loadTemplate, type Db } from "./data";
import { richDoc, type RichDoc } from "./doc";

export interface Resolution {
  id: string;
  status: "accepted" | "countered";
  note?: string;
}

export type GenerateResult =
  | { ok: true; versionId: string; missing: string[] }
  | {
      ok: false;
      error: "not_found" | "no_terms" | "template" | "db";
      detail: string[];
      message?: string;
      code?: string;
    };

const contractRow = z.object({
  id: z.uuid(),
  number: z.string(),
  deal_id: z.uuid(),
  template_id: z.uuid(),
  parent_contract_id: z.uuid().nullable(),
  payee_agency_id: z.uuid().nullable(),
  current_version_id: z.uuid().nullable(),
});
const overridesSchema = z.record(z.string(), richDoc);

/**
 * Assembles a new version of a contract from the deal's terms in force and the contract's template, keeps earlier
 * clause overrides (the agreed wording of negotiable clauses) plus `overrides`, and stores it; the database hashes
 * the HTML and closes the `resolve` change requests in the same transaction. Works with the person's client (staff
 * with contract.write) or the service-role client (the draft for an accepted offer).
 */
export async function generateVersion(
  db: Db,
  contractId: string,
  opts: {
    overrides?: Readonly<Record<string, RichDoc>>;
    note?: string;
    resolve?: readonly Resolution[];
  } = {},
): Promise<GenerateResult> {
  const { data: row, error } = await db
    .from("contracts")
    .select("id, number, deal_id, template_id, parent_contract_id, payee_agency_id, current_version_id")
    .eq("id", contractId)
    .maybeSingle();
  if (error) return { ok: false, error: "db", detail: [], message: error.message, code: error.code };
  const c = contractRow.nullable().parse(row);
  if (!c) return { ok: false, error: "not_found", detail: [] };

  const [prev, parent, src, template] = await Promise.all([
    c.current_version_id
      ? db.from("contract_versions").select("overrides").eq("id", c.current_version_id).maybeSingle()
      : Promise.resolve({ data: null }),
    c.parent_contract_id
      ? db.from("contracts").select("number").eq("id", c.parent_contract_id).maybeSingle()
      : Promise.resolve({ data: null }),
    loadContractSource(db, c.deal_id),
    loadTemplate(db, c.template_id),
  ]);
  if (!src || !template) return { ok: false, error: "not_found", detail: [] };
  if (!src.deal.comp_config) return { ok: false, error: "no_terms", detail: [] };
  const kept = overridesSchema.catch({}).parse((prev.data as { overrides?: unknown } | null)?.overrides ?? {});
  const overrides = { ...kept, ...opts.overrides };

  const built = buildVersion(
    src,
    template,
    {
      number: c.number,
      date: istToday(),
      parent_number: (parent.data as { number?: string } | null)?.number ?? null,
      payee_agency_id: c.payee_agency_id,
    },
    overrides,
  );
  if (built.errors.length || built.unknown.length)
    return {
      ok: false,
      error: "template",
      detail: [...built.unknown.map((u) => `unknown:${u}`), ...built.errors],
    };

  const { data: versionId, error: e2 } = await db.rpc("contract_version_add", {
    p_contract: c.id,
    p_content: built.content as never,
    p_html: built.html,
    p_overrides: overrides as never,
    p_note: opts.note ?? undefined,
    p_resolve: (opts.resolve ?? []).map((r) => ({
      id: r.id,
      status: r.status,
      note: r.note ?? null,
    })),
    p_missing: built.missing,
  });
  if (e2) {
    log.warn("contracts.version_add_failed", { code: e2.code, error: e2.message });
    return { ok: false, error: "db", detail: [], message: e2.message, code: e2.code };
  }
  return { ok: true, versionId, missing: built.missing };
}

/**
 * The draft contract for a deal created from an accepted offer (spec 14: the contract is generated automatically).
 * Idempotent: does nothing when the deal already has a contract. Uses the campaign's template, else the default.
 */
export async function draftContractForDeal(db: Db, dealId: string): Promise<string | null> {
  const { count, error } = await db
    .from("contracts")
    .select("id", { count: "exact", head: true })
    .eq("deal_id", dealId);
  if (error) throw new Error(error.message);
  if ((count ?? 0) > 0) return null;
  const { data: id, error: e2 } = await db.rpc("contract_create", { p: { deal_id: dealId } });
  if (e2) throw new Error(e2.message);
  const r = await generateVersion(db, id, { note: "Generated for the accepted offer" });
  if (!r.ok)
    log.warn("contracts.draft_generation_failed", {
      deal_id: dealId,
      error: r.error,
      detail: r.detail.join(","),
    });
  return id;
}
