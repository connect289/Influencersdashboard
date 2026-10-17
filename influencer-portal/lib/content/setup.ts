import "server-only";
// Creates a deal's brief (working copy, from its campaign's template or the default) and its deliverables (one per
// piece agreed, with due dates from the template's offsets). Idempotent: a deal that already has a brief keeps it,
// and deliverables are only created when the deal has none. Runs as the signed-in staff member, or as the service
// role when the deal follows an accepted application.
import { z } from "zod";
import { deliverableItem, type DeliverableItem } from "@/lib/campaigns/schemas";
import type { Db } from "@/lib/contracts/data";
import { CONTENT_FORMATS, PLATFORMS, type ContentFormat, type Platform } from "@/lib/creators/schemas";
import { briefTemplateContent, buildBrief, deliverableSpecs, dueDatesFrom, type CatalogueProgramme } from "./brief";

const programme = z.object({
  id: z.number().int(),
  program_name: z.string(),
  specialization: z.string().nullable(),
  level: z.string().nullable(),
  mode: z.string().nullable(),
  university: z.string(),
  recognitions: z.array(z.string()).nullable(),
  accreditation_text: z.string().nullable(),
  fee_total: z.number().nullable(),
  fee_yearly: z.number().nullable(),
  min_qualification: z.string().nullable(),
  min_pct_general: z.number().nullable(),
  eligibility_text: z.string().nullable(),
}) satisfies z.ZodType<CatalogueProgramme>;

const source = z.object({
  deal: z.object({
    id: z.uuid(),
    title: z.string(),
    status: z.string(),
    starts_on: z.string(),
    agreed_terms: z
      .object({ deliverables: z.array(deliverableItem).catch([]) })
      .nullable()
      .catch(null),
  }),
  template: z.object({ id: z.uuid(), name: z.string(), content: z.unknown() }).nullable(),
  campaign: z
    .object({
      description: z.string().nullable(),
      deliverables: z.array(deliverableItem).catch([]),
    })
    .nullable(),
  programmes: z.array(programme).catch([]),
  banned: z.array(z.string()),
  disclosure_terms: z.array(z.string()).catch(["#ad"]),
  brief_id: z.uuid().nullable(),
  deliverables: z.number().int(),
});

const PLATFORM_LABEL: Record<Platform, string> = {
  instagram: "Instagram",
  youtube: "YouTube",
  facebook: "Facebook",
  linkedin: "LinkedIn",
  x: "X",
  telegram: "Telegram",
  moj_josh: "Moj/Josh",
  other: "Other",
};
const FORMAT_LABEL: Record<ContentFormat, string> = {
  reel: "reel",
  story: "story",
  post: "post",
  youtube_video: "video",
  short: "short",
  live: "live session",
  carousel: "carousel",
  blog: "blog post",
  other: "piece",
};

export type DeliverablePlan = {
  title: string;
  platform: Platform;
  format: ContentFormat;
  specs: { duration_s: number | null; aspect_ratio: string | null; notes: string };
  stages: Record<string, boolean>;
  due_dates: Record<string, string>;
};

/** One row per piece: "Instagram reel 1", "Instagram reel 2", … with format specs and due dates. Pure. */
export function planDeliverables(
  items: readonly DeliverableItem[],
  start: string,
  template: z.output<typeof briefTemplateContent>,
): DeliverablePlan[] {
  const specs = deliverableSpecs(items);
  const due = dueDatesFrom(start, template.due_offsets, template.stages);
  return items.flatMap((d, i) =>
    Array.from({ length: d.count }, (_, n) => ({
      title: `${PLATFORM_LABEL[d.platform]} ${FORMAT_LABEL[d.format]}${d.count > 1 ? ` ${String(n + 1)}` : ""}`,
      platform: z.enum(PLATFORMS).parse(d.platform),
      format: z.enum(CONTENT_FORMATS).parse(d.format),
      specs: { duration_s: specs[i]?.duration_s ?? null, aspect_ratio: specs[i]?.aspect_ratio ?? null, notes: "" },
      stages: { ...template.stages },
      due_dates: due,
    })),
  );
}

/** The brief id for the deal (created when missing), or null when the deal is unknown or closed. */
export async function setupContentForDeal(db: Db, dealId: string, now = new Date()): Promise<string | null> {
  const { data, error } = await db.rpc("brief_source", { p_deal: dealId });
  if (error) throw new Error(error.message);
  if (data === null) return null;
  const src = source.parse(data);
  if (["completed", "terminated", "expired"].includes(src.deal.status)) return src.brief_id;
  const template = briefTemplateContent.catch(briefTemplateContent.parse({})).parse(src.template?.content ?? {});
  const agreed = src.deal.agreed_terms?.deliverables ?? [];
  let briefId = src.brief_id;
  if (!briefId) {
    const content = buildBrief({
      template,
      campaign: src.campaign
        ? {
            objective_text: src.campaign.description,
            description: src.campaign.description,
            deliverables: src.campaign.deliverables,
          }
        : null,
      agreed,
      programmes: src.programmes,
      banned: src.banned,
      disclosureTerms: src.disclosure_terms,
    });
    const created = await db.rpc("brief_create", {
      p: { deal_id: dealId, template_id: src.template?.id ?? null, content },
    });
    if (created.error) throw new Error(created.error.message);
    briefId = created.data;
  }
  if (src.deliverables === 0) {
    const items = agreed.length ? agreed : (src.campaign?.deliverables ?? []);
    // Due dates count from the deal's start, or from today when the deal started already.
    const startMs = Math.max(Date.parse(`${src.deal.starts_on}T00:00:00+05:30`), now.getTime());
    const plan = planDeliverables(items, new Date(startMs).toISOString(), template);
    if (plan.length) {
      const r = await db.rpc("deliverables_create", { p_deal: dealId, p_items: plan });
      if (r.error) throw new Error(r.error.message);
    }
  }
  return briefId;
}
