import "server-only";
// Loaders for the lead pipeline and links. Creators and agencies read inf.creator_lead_feed (RLS: their own rows,
// already masked in the database); staff use inf.leads_list / inf.lead_detail, where contact details appear only for
// lead.contacts.
import { z } from "zod";
import { ATTRIBUTION_STATUSES } from "@/lib/attribution/rules";
import { CREATOR_STAGES } from "@/lib/attribution/stages";
import type { Db } from "@/lib/contracts/data";

const ts = z.string();
const stage = z.enum(CREATOR_STAGES);
const status = z.enum(ATTRIBUTION_STATUSES);
const timeline = z
  .array(z.object({ stage, reason: z.string().nullable(), flags: z.array(z.string()), at: ts }))
  .catch([]);

export const feedRow = z.object({
  attribution_id: z.uuid(),
  creator_id: z.uuid(),
  lead_ref: z.string(),
  display_name: z.string().nullable(),
  phone_masked: z.string(),
  email_masked: z.string().nullable(),
  fields: z.record(z.string(), z.unknown()),
  creator_stage: stage,
  reason_category: z.string().nullable(),
  flags: z.array(z.string()),
  temperature: z.string().nullable(),
  attribution_status: status,
  attribution_reason: z.string().nullable(),
  touch: z.enum(["first", "last", "assisted", "none"]),
  code: z.string(),
  link_id: z.uuid().nullable(),
  link_label: z.string().nullable(),
  campaign_id: z.uuid().nullable(),
  campaign_name: z.string().nullable(),
  deal_id: z.uuid().nullable(),
  deal_title: z.string().nullable(),
  deliverable_id: z.uuid().nullable(),
  deliverable_title: z.string().nullable(),
  programme_id: z.number().int().nullable(),
  programme_name: z.string().nullable(),
  stage_timeline: timeline,
  earning_status: z.enum(["none", "pending", "accrued", "confirmed", "paid", "clawed_back"]),
  is_test: z.boolean(),
  removed: z.boolean(),
  lead_at: ts,
  stage_changed_at: ts.nullable(),
  updated_at: ts,
});
export type FeedRow = z.infer<typeof feedRow>;

export const TEMPERATURES = ["HOT", "WARM", "COLD"] as const;

export const leadFilters = z.object({
  stage: stage.nullable().catch(null),
  campaign: z.uuid().nullable().catch(null),
  deal: z.uuid().nullable().catch(null),
  deliverable: z.uuid().nullable().catch(null),
  link: z.uuid().nullable().catch(null),
  programme: z.coerce.number().int().positive().nullable().catch(null),
  temperature: z.enum(TEMPERATURES).nullable().catch(null),
  city: z.string().trim().max(60).nullable().catch(null),
  from: z.iso.date().nullable().catch(null),
  to: z.iso.date().nullable().catch(null),
  q: z.string().trim().max(60).nullable().catch(null),
});
export type LeadFilters = z.infer<typeof leadFilters>;

export function parseFilters(sp: Record<string, string | undefined>): LeadFilters {
  const v = (k: string) => (sp[k] ? sp[k] : null);
  return leadFilters.parse({
    stage: v("stage"),
    campaign: v("campaign"),
    deal: v("deal"),
    deliverable: v("deliverable"),
    link: v("link"),
    programme: v("programme"),
    temperature: v("temperature"),
    city: v("city"),
    from: v("from"),
    to: v("to"),
    q: v("q"),
  });
}

/** A creator's leads (theirs only: RLS), filtered. Credited first; newest first. */
export async function loadFeed(db: Db, creatorId: string, f: LeadFilters, limit = 500): Promise<FeedRow[]> {
  let q = db
    .from("creator_lead_feed")
    .select("*")
    .eq("creator_id", creatorId)
    .order("lead_at", { ascending: false })
    .limit(limit);
  if (f.stage) q = q.eq("creator_stage", f.stage);
  if (f.campaign) q = q.eq("campaign_id", f.campaign);
  if (f.deal) q = q.eq("deal_id", f.deal);
  if (f.deliverable) q = q.eq("deliverable_id", f.deliverable);
  if (f.link) q = q.eq("link_id", f.link);
  if (f.programme) q = q.eq("programme_id", f.programme);
  if (f.temperature) q = q.eq("temperature", f.temperature);
  if (f.city)
    q = q.or(
      `fields->>city.ilike.%${f.city.replace(/[%,()]/g, "")}%,fields->>state.ilike.%${f.city.replace(/[%,()]/g, "")}%`,
    );
  if (f.from) q = q.gte("lead_at", new Date(`${f.from}T00:00:00+05:30`).toISOString());
  if (f.to) q = q.lt("lead_at", new Date(new Date(`${f.to}T00:00:00+05:30`).getTime() + 86_400_000).toISOString());
  if (f.q) q = q.or(`lead_ref.ilike.%${f.q.replace(/[%,()]/g, "")}%,code.ilike.%${f.q.replace(/[%,()]/g, "")}%`);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return z.array(feedRow).parse(data);
}

export const leadDetail = feedRow.extend({
  staff: z.boolean(),
  decisions: z
    .array(
      z.object({
        from: z.string().nullable(),
        to: z.string(),
        reason: z.string().nullable(),
        actor: z.string(),
        at: ts,
      }),
    )
    .nullable(),
  other_creators: z
    .array(
      z.object({
        attribution_id: z.uuid(),
        creator_id: z.uuid(),
        creator_name: z.string(),
        status,
        touch: z.string(),
        code: z.string(),
        touch_at: ts,
      }),
    )
    .nullable(),
  student_lead_id: z.number().int().nullable(),
  contact: z
    .object({
      phone: z.string().nullable(),
      email: z.string().nullable(),
      name: z.string().nullable(),
    })
    .nullable(),
  flags_open: z
    .array(
      z.object({
        id: z.uuid(),
        signal: z.string(),
        detail: z.record(z.string(), z.unknown()),
        opened_at: ts,
      }),
    )
    .nullable(),
  touch_at: ts,
  evidence_source: z.string(),
  /** When it was loaded (for "days in the current stage"). */
  as_of: ts,
});
export type LeadDetail = z.infer<typeof leadDetail>;

export async function loadLead(db: Db, attributionId: string): Promise<LeadDetail | null> {
  const { data, error } = await db.rpc("lead_detail", { p_attribution: attributionId });
  if (error) throw new Error(error.message);
  return leadDetail.nullable().parse(data === null ? null : { ...(data as object), as_of: new Date().toISOString() });
}

export const staffLeadRow = feedRow.extend({
  student_lead_id: z.number().int(),
  decision_note: z.string().nullable(),
  creator_name: z.string(),
  handle: z.string().nullable(),
  phone: z.string().nullable(),
  email: z.string().nullable(),
  student_name: z.string().nullable(),
});
export type StaffLeadRow = z.infer<typeof staffLeadRow>;

export async function listLeads(
  db: Db,
  p: {
    status?: string[];
    stage?: string | null;
    q?: string;
    creatorId?: string | null;
    page?: number;
    includeTest?: boolean;
  },
): Promise<{ total: number; rows: StaffLeadRow[] }> {
  const { data, error } = await db.rpc("leads_list", {
    p: {
      status: p.status ?? [],
      stage: p.stage ?? "",
      q: p.q ?? "",
      creator_id: p.creatorId ?? "",
      page: p.page ?? 1,
      page_size: 50,
      include_test: p.includeTest ?? false,
    },
  });
  if (error) throw new Error(error.message);
  return z.object({ total: z.number(), rows: z.array(staffLeadRow) }).parse(data);
}

export const linkRow = z.object({
  id: z.uuid(),
  code: z.string(),
  destination: z.enum(["whatsapp_witty", "website_landing", "custom_url"]),
  custom_url: z.string().nullable(),
  platform: z.string().nullable(),
  label: z.string().nullable(),
  active: z.boolean(),
  created_at: ts,
  deal_id: z.uuid().nullable(),
  deal_title: z.string().nullable(),
  deliverable_id: z.uuid().nullable(),
  deliverable_title: z.string().nullable(),
  campaign_id: z.uuid().nullable(),
  campaign_name: z.string().nullable(),
  programme_id: z.number().nullable(),
  programme_name: z.string().nullable(),
  clicks: z.number().int(),
  leads: z.number().int(),
});
export type LinkRow = z.infer<typeof linkRow>;

export async function loadLinks(db: Db, creatorId: string): Promise<LinkRow[]> {
  const { data, error } = await db.rpc("links_list", { p_creator: creatorId });
  if (error) throw new Error(error.message);
  return z.array(linkRow).parse(data);
}

export const linkOption = z.object({
  deal_id: z.uuid(),
  deal_title: z.string(),
  campaign_id: z.uuid().nullable(),
  campaign_name: z.string().nullable(),
  deliverables: z.array(z.object({ id: z.uuid(), title: z.string(), platform: z.string() })),
  programmes: z.array(z.object({ id: z.number(), name: z.string() })),
});
export type LinkOption = z.infer<typeof linkOption>;

export async function loadLinkOptions(db: Db, creatorId: string): Promise<LinkOption[]> {
  const { data, error } = await db.rpc("link_options", { p_creator: creatorId });
  if (error) throw new Error(error.message);
  return z.array(linkOption).parse(data);
}

export const savedView = z.object({
  id: z.uuid(),
  name: z.string(),
  filters: z.record(z.string(), z.string()),
  shared: z.boolean(),
  mine: z.boolean(),
});
export type SavedView = z.infer<typeof savedView>;

export async function loadViews(db: Db): Promise<SavedView[]> {
  const { data, error } = await db.rpc("lead_views");
  if (error) return [];
  return z.array(savedView).catch([]).parse(data);
}

export const fraudFlag = z.object({
  id: z.uuid(),
  creator_id: z.uuid(),
  creator_name: z.string(),
  handle: z.string().nullable(),
  attribution_id: z.uuid().nullable(),
  lead_ref: z.string().nullable(),
  signal: z.enum(["velocity", "same_device", "no_witty_reply", "off_hours_burst", "junk_rate"]),
  detail: z.record(z.string(), z.number()).catch({}),
  status: z.enum(["open", "cleared", "confirmed"]),
  opened_at: ts,
  decided_at: ts.nullable(),
  note: z.string().nullable(),
});
export type FraudFlag = z.infer<typeof fraudFlag>;

export async function loadFraudQueue(db: Db, status: "open" | "cleared" | "confirmed" | "all"): Promise<FraudFlag[]> {
  const { data, error } = await db.rpc("fraud_queue", { p: { status } });
  if (error) throw new Error(error.message);
  return z.array(fraudFlag).parse(data);
}

export const overview = z.object({
  by_status: z.record(z.string(), z.number()),
  open_flags: z.number(),
  last_sync: z.object({ watermark: ts, updated_at: ts, detail: z.record(z.string(), z.unknown()) }).nullable(),
  unmapped: z.number(),
});

export async function loadOverview(db: Db): Promise<z.infer<typeof overview> | null> {
  const { data, error } = await db.rpc("attribution_overview");
  if (error) throw new Error(error.message);
  return overview.nullable().parse(data);
}

export const stageRuleRow = z.object({
  id: z.uuid(),
  priority: z.number().int(),
  conditions: z.array(
    z.object({
      field: z.string(),
      in: z.array(z.string()).optional(),
      present: z.boolean().optional(),
      empty: z.boolean().optional(),
      is_true: z.boolean().optional(),
    }),
  ),
  creator_stage: stage.nullable(),
  reason_category: z.string().nullable(),
  flag: z.enum(["cancelled", "under_review"]).nullable(),
  active: z.boolean(),
});
export type StageRuleRow = z.infer<typeof stageRuleRow>;

export async function loadStageRules(db: Db): Promise<StageRuleRow[]> {
  const { data, error } = await db
    .from("stage_mappings")
    .select("id, priority, conditions, creator_stage, reason_category, flag, active")
    .order("priority");
  if (error) throw new Error(error.message);
  return z.array(stageRuleRow).parse(data);
}
