import "server-only";
// Loaders for briefs, deliverables, the banned-claims list and penalty proposals. Every read goes through an inf.*
// function that decides what the caller may see (staff, the creator, or an agency with "act on deliverables").
import { z } from "zod";
import type { Db } from "@/lib/contracts/data";
import { CONTENT_FORMATS, PLATFORMS } from "@/lib/creators/schemas";
import { briefContent, briefTemplateContent } from "./brief";

export { METRIC_FIELDS, type MetricField } from "./schemas";
import { DELIVERABLE_STATUSES, DUE_STAGES, STAGES } from "./workflow";

const ts = z.string();
const side = z.enum(["eduwit", "creator", "agency"]);
const dueDates = z.partialRecord(z.enum(DUE_STAGES), z.string()).catch({});
const toggles = z.object(
  Object.fromEntries(STAGES.map((s) => [s, z.boolean()])) as Record<
    (typeof STAGES)[number],
    z.ZodBoolean
  >,
);
const status = z.enum(DELIVERABLE_STATUSES);
const platform = z.enum(PLATFORMS);
const format = z.enum(CONTENT_FORMATS);
const dealRef = z.object({
  id: z.uuid(),
  code: z.string().nullable(),
  title: z.string(),
  status: z.string(),
});
const creatorRef = z.object({
  id: z.uuid(),
  display_name: z.string(),
  handle: z.string().nullable(),
});

// ---------------------------------------------------------------------------------------------------------------
// Briefs
// ---------------------------------------------------------------------------------------------------------------
export const briefTemplateRow = z.object({
  id: z.uuid(),
  name: z.string(),
  description: z.string().nullable(),
  content: briefTemplateContent.catch(briefTemplateContent.parse({})),
  is_default: z.boolean(),
  archived_at: ts.nullable(),
  updated_at: ts,
});
export type BriefTemplateRow = z.infer<typeof briefTemplateRow>;

export async function loadBriefTemplates(
  db: Db,
  includeArchived = false,
): Promise<BriefTemplateRow[]> {
  let q = db
    .from("brief_templates")
    .select("id, name, description, content, is_default, archived_at, updated_at")
    .order("is_default", { ascending: false })
    .order("name");
  if (!includeArchived) q = q.is("archived_at", null);
  const { data, error } = await q;
  if (error) throw new Error(error.message);
  return z.array(briefTemplateRow).parse(data);
}

export const briefRow = z.object({
  id: z.uuid(),
  deal_id: z.uuid(),
  deal_code: z.string().nullable(),
  deal_title: z.string(),
  creator_name: z.string(),
  handle: z.string().nullable(),
  version: z.number().int().nullable(),
  published_at: ts.nullable(),
  acknowledged: z.boolean(),
  open_questions: z.number().int(),
  updated_at: ts,
});
export type BriefRow = z.infer<typeof briefRow>;
export const BRIEF_STATES = ["draft", "unacknowledged", "acknowledged"] as const;
export type BriefState = (typeof BRIEF_STATES)[number];

export async function listBriefs(
  db: Db,
  f: { q?: string; state?: BriefState | null },
): Promise<BriefRow[]> {
  const { data, error } = await db.rpc("briefs_list", {
    p: { q: f.q ?? "", state: f.state ?? "" },
  });
  if (error) throw new Error(error.message);
  return z.array(briefRow).parse(data);
}

export const myBriefRow = z.object({
  id: z.uuid(),
  deal_id: z.uuid(),
  deal_title: z.string(),
  version: z.number().int(),
  published_at: ts,
  acknowledged: z.boolean(),
});
export type MyBriefRow = z.infer<typeof myBriefRow>;

export async function loadMyBriefs(db: Db, creatorId: string): Promise<MyBriefRow[]> {
  const { data, error } = await db.rpc("my_briefs", { p_creator: creatorId });
  if (error) throw new Error(error.message);
  return z.array(myBriefRow).parse(data);
}

export const briefQuestion = z.object({
  id: z.uuid(),
  parent_id: z.uuid().nullable(),
  author_side: side,
  body: z.string(),
  created_at: ts,
  mine: z.boolean(),
});
export type BriefQuestion = z.infer<typeof briefQuestion>;

export const briefDetail = z.object({
  id: z.uuid(),
  side,
  template_id: z.uuid().nullable(),
  deal: dealRef.extend({ campaign_id: z.uuid().nullable() }),
  creator: creatorRef,
  draft_content: briefContent.nullable(),
  current: z
    .object({
      id: z.uuid(),
      version: z.number().int(),
      content: briefContent,
      note: z.string().nullable(),
      published_at: ts,
    })
    .nullable(),
  versions: z.array(
    z.object({
      id: z.uuid(),
      version: z.number().int(),
      note: z.string().nullable(),
      published_at: ts,
      acknowledged_at: ts.nullable(),
    }),
  ),
  acknowledged_current: z.boolean(),
  programmes: z.array(
    z.object({
      id: z.number().int(),
      program_name: z.string().nullable(),
      specialization: z.string().nullable(),
      university: z.string(),
      mode: z.string().nullable(),
      level: z.string().nullable(),
      fee_total: z.number().nullable(),
      fee_yearly: z.number().nullable(),
      active: z.boolean().nullable(),
    }),
  ),
  questions: z.array(briefQuestion),
  deliverables: z.array(
    z.object({
      id: z.uuid(),
      code: z.string(),
      title: z.string(),
      platform,
      format,
      specs: z.record(z.string(), z.unknown()),
      due_dates: dueDates,
      status,
    }),
  ),
  can_write: z.boolean(),
});
export type BriefDetail = z.infer<typeof briefDetail>;

export async function loadBrief(db: Db, briefId: string): Promise<BriefDetail | null> {
  const { data, error } = await db.rpc("brief_detail", { p_brief: briefId });
  if (error) throw new Error(error.message);
  return briefDetail.nullable().parse(data);
}

/** Threads: top-level questions with their replies, oldest first. */
export function threads(
  questions: readonly BriefQuestion[],
): { root: BriefQuestion; replies: BriefQuestion[] }[] {
  const roots = questions.filter((q) => q.parent_id === null);
  return roots.map((root) => ({ root, replies: questions.filter((q) => q.parent_id === root.id) }));
}

// ---------------------------------------------------------------------------------------------------------------
// Deliverables
// ---------------------------------------------------------------------------------------------------------------
export const DELIVERABLE_VIEWS = ["open", "review", "overdue", "live", "all"] as const;
export type DeliverableView = (typeof DELIVERABLE_VIEWS)[number];

export const deliverableRow = z.object({
  id: z.uuid(),
  code: z.string(),
  title: z.string(),
  platform,
  format,
  status,
  deal_id: z.uuid(),
  deal_code: z.string().nullable(),
  deal_title: z.string(),
  creator_name: z.string(),
  handle: z.string().nullable(),
  due_dates: dueDates,
  pending_stage: z.enum(DUE_STAGES).nullable(),
  overdue_days: z.number().int().nullable(),
  awaiting_verification: z.boolean(),
  updated_at: ts,
});
export type DeliverableRow = z.infer<typeof deliverableRow>;

export async function listDeliverables(
  db: Db,
  f: { view: DeliverableView; q?: string; dealId?: string | null },
): Promise<DeliverableRow[]> {
  const { data, error } = await db.rpc("deliverables_list", {
    p: { view: f.view, q: f.q ?? "", deal_id: f.dealId ?? "" },
  });
  if (error) throw new Error(error.message);
  return z.array(deliverableRow).parse(data);
}

export const myDeliverableRow = deliverableRow.omit({
  deal_code: true,
  creator_name: true,
  handle: true,
  awaiting_verification: true,
});
export type MyDeliverableRow = z.infer<typeof myDeliverableRow>;

export async function loadMyDeliverables(db: Db, creatorId: string): Promise<MyDeliverableRow[]> {
  const { data, error } = await db.rpc("my_deliverables", { p_creator: creatorId });
  if (error) throw new Error(error.message);
  return z.array(myDeliverableRow).parse(data);
}

export const submissionFile = z.object({
  path: z.string(),
  name: z.string(),
  type: z.string(),
  size: z.number().int(),
});
export type SubmissionFile = z.infer<typeof submissionFile>;

export const submission = z.object({
  id: z.uuid(),
  kind: z.enum(["concept", "draft"]),
  version: z.number().int(),
  body: z.string().nullable(),
  files: z.array(submissionFile).catch([]),
  link_url: z.string().nullable(),
  creator_note: z.string().nullable(),
  status: z.enum(["submitted", "approved", "changes_requested"]),
  author_side: z.enum(["creator", "agency"]),
  created_at: ts,
  decided_at: ts.nullable(),
  decision_note: z.string().nullable(),
});
export type Submission = z.infer<typeof submission>;

export const imageRegion = z.object({
  file: z.number().int().min(0).max(9),
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
  w: z.number().min(0).max(1),
  h: z.number().min(0).max(1),
});
export type ImageRegion = z.infer<typeof imageRegion>;

export const reviewComment = z.object({
  id: z.uuid(),
  submission_id: z.uuid(),
  parent_id: z.uuid().nullable(),
  author_side: side,
  body: z.string(),
  video_timestamp_ms: z.number().int().nullable(),
  image_region: imageRegion.nullable(),
  resolved: z.boolean(),
  created_at: ts,
  mine: z.boolean(),
});
export type ReviewComment = z.infer<typeof reviewComment>;

export const complianceCheck = z.object({
  id: z.uuid(),
  submission_id: z.uuid().nullable(),
  kind: z.enum(["banned_claims", "disclosure", "asci_checklist"]),
  result: z.record(z.string(), z.unknown()),
  passed: z.boolean(),
  overridden: z.boolean(),
  override_reason: z.string().nullable(),
  created_at: ts,
});
export type ComplianceCheck = z.infer<typeof complianceCheck>;

export const oembed = z.object({
  title: z.string().nullable(),
  author_name: z.string().nullable(),
  thumbnail_url: z.string().nullable(),
});

export const publishedPost = z.object({
  id: z.uuid(),
  live_url: z.string(),
  posted_on: z.string(),
  oembed: oembed.nullable().catch(null),
  disclosure_ok: z.boolean().nullable(),
  verification_status: z.enum(["pending", "verified", "rejected", "replaced"]),
  verification: z
    .object({ live: z.boolean(), disclosure: z.boolean(), matches: z.boolean() })
    .nullable()
    .catch(null),
  verified_at: ts.nullable(),
  review_note: z.string().nullable(),
  created_at: ts,
});
export type PublishedPost = z.infer<typeof publishedPost>;

const count = z.number().int().nullable();
export const metricSnapshot = z.object({
  id: z.number().int(),
  checkpoint: z.string(),
  views: count,
  reach: count,
  likes: count,
  comments: count,
  shares: count,
  saves: count,
  clicks: count,
  watch_time_s: count,
  source: z.enum(["manual", "screenshot", "api"]),
  screenshot_paths: z.array(z.string()),
  captured_at: ts,
});
export type MetricSnapshot = z.infer<typeof metricSnapshot>;

export const revisionExtension = z.object({
  id: z.uuid(),
  reason: z.string(),
  fee_paise: z.number().int(),
  status: z.enum(["pending", "approved", "rejected"]),
  requested_at: ts,
  decided_at: ts.nullable(),
  decision_note: z.string().nullable(),
});
export type RevisionExtension = z.infer<typeof revisionExtension>;

export const deliverableDetail = z.object({
  id: z.uuid(),
  code: z.string(),
  deal_id: z.uuid(),
  title: z.string(),
  platform,
  format,
  position: z.number().int(),
  specs: z.record(z.string(), z.unknown()),
  stages: toggles,
  due_dates: dueDates,
  revision_limit: z.number().int(),
  revisions_used: z.number().int(),
  extra_revisions: z.number().int(),
  status,
  config_ref: z.string().nullable(),
  scheduled_for: ts.nullable(),
  live_at: ts.nullable(),
  verified_at: ts.nullable(),
  completed_at: ts.nullable(),
  cancelled_at: ts.nullable(),
  disclosure_failed_at: ts.nullable(),
  status_reason: z.string().nullable(),
  side,
  overdue_days: z.number().int().nullable(),
  pending_stage: z.enum(DUE_STAGES).nullable(),
  deal: dealRef,
  creator: creatorRef,
  brief: z.object({ id: z.uuid(), published: z.boolean(), acknowledged: z.boolean() }).nullable(),
  submissions: z.array(submission),
  comments: z.array(reviewComment),
  checks: z.array(complianceCheck),
  posts: z.array(publishedPost),
  metrics: z.array(metricSnapshot),
  transitions: z.array(
    z.object({
      from: z.string(),
      to: z.string(),
      action: z.string(),
      side: z.string(),
      note: z.string().nullable(),
      at: ts,
    }),
  ),
  extensions: z.array(revisionExtension).nullable(),
  can_review: z.boolean(),
  can_verify: z.boolean(),
  can_override: z.boolean(),
  can_edit: z.boolean(),
  can_extend: z.boolean(),
  metric_checkpoints: z.array(z.number().int()).catch([24, 168, 720]),
});
export type DeliverableDetail = z.infer<typeof deliverableDetail>;

export async function loadDeliverable(db: Db, id: string): Promise<DeliverableDetail | null> {
  const { data, error } = await db.rpc("deliverable_detail", { p_id: id });
  if (error) throw new Error(error.message);
  return deliverableDetail.nullable().parse(data);
}

// ---------------------------------------------------------------------------------------------------------------
// Banned claims and penalties
// ---------------------------------------------------------------------------------------------------------------
export const bannedClaimRow = z.object({
  id: z.uuid(),
  pattern: z.string(),
  kind: z.enum(["phrase", "regex"]),
  severity: z.enum(["block", "warn"]),
  note: z.string().nullable(),
  active: z.boolean(),
  updated_at: ts,
});
export type BannedClaimRow = z.infer<typeof bannedClaimRow>;

export async function loadBannedClaims(db: Db): Promise<BannedClaimRow[]> {
  const { data, error } = await db
    .from("banned_claims")
    .select("id, pattern, kind, severity, note, active, updated_at")
    .order("active", { ascending: false })
    .order("severity")
    .order("pattern");
  if (error) throw new Error(error.message);
  return z.array(bannedClaimRow).parse(data);
}

export const PENALTY_STATUSES = ["proposed", "approved", "rejected", "withdrawn"] as const;
export type PenaltyStatus = (typeof PENALTY_STATUSES)[number];
export const penaltyRow = z.object({
  id: z.uuid(),
  deal_id: z.uuid(),
  deal_code: z.string().nullable(),
  deal_title: z.string(),
  creator_name: z.string(),
  deliverable_id: z.uuid().nullable(),
  deliverable_title: z.string().nullable(),
  rule_id: z.string(),
  amount_paise: z.number().int(),
  forfeits: z.array(z.string()),
  reason: z.string(),
  proposed_at: ts,
  status: z.enum(PENALTY_STATUSES),
  decided_at: ts.nullable(),
  decision_note: z.string().nullable(),
});
export type PenaltyRow = z.infer<typeof penaltyRow>;

export async function listPenalties(
  db: Db,
  f: { status?: PenaltyStatus | null; dealId?: string | null },
): Promise<PenaltyRow[]> {
  const { data, error } = await db.rpc("penalties_list", {
    p: { status: f.status ?? "", deal_id: f.dealId ?? "" },
  });
  if (error) throw new Error(error.message);
  return z.array(penaltyRow).parse(data);
}
