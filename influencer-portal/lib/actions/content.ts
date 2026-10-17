"use server";
// Content actions (spec 10, 16). Staff write brief templates and briefs, set up deliverables, review submissions
// (approve or ask for changes, comment, override compliance checks with a reason), verify live posts and decide
// revision extensions and penalties. Creators and their agencies with "act on deliverables" acknowledge briefs, ask
// questions, upload and submit work, schedule, go live and report metrics. Each action validates its input and calls
// inf.* functions, which decide who may act.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { loadDeliverable } from "@/lib/content/data";
import { BRIEFS_BUCKET, contentPath, DELIVERABLES_BUCKET, signedLink, signedUpload } from "@/lib/content/files";
import { fetchOembed } from "@/lib/content/oembed";
import { scanAndRecord } from "@/lib/content/scan";
import {
  bannedClaimInput,
  briefPublishInput,
  briefSaveInput,
  briefTemplateInput,
  commentInput,
  CONTENT_DB_ERRORS,
  decisionInput,
  deliverableEditInput,
  deliverableNewInput,
  extensionInput,
  metricsInput,
  overrideInput,
  postInput,
  questionInput,
  reviewInput,
  scheduleInput,
  statusChangeInput,
  submissionInput,
  uploadRequest,
  verifyInput,
  type BannedClaimInput,
  type BriefSaveInput,
  type BriefTemplateInput,
  type CommentInput,
  type DeliverableEditInput,
  type DeliverableNewInput,
  type MetricsInput,
  type PostInput,
  type QuestionInput,
  type ReviewInput,
  type SubmissionInput,
  type UploadRequest,
  type VerifyInput,
} from "@/lib/content/schemas";
import { setupContentForDeal } from "@/lib/content/setup";
import { checkPostUrl } from "@/lib/content/urls";
import { log } from "@/lib/log";
import { SETTINGS } from "@/lib/settings/registry";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
type DbError = { code?: string; message: string };
const uuid = z.uuid();

async function signedIn(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (!me.signed_in || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

function dbFail(error: DbError, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  for (const [re, key] of CONTENT_DB_ERRORS)
    if (re.test(error.message)) return fail(t(`content.errors.${key}` as "content.errors.notNow"));
  if (error.code === "22023" || error.code === "23514" || error.code === "23505") return fail(t("errors.invalidInput"));
  log.warn("content.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

/** Validates, checks the session, then runs the body with the person's client. */
async function act<S extends z.ZodType, Res extends ActionResult<unknown>>(
  schema: S,
  input: unknown,
  body: (db: ServerSupabase, v: z.output<S>, t: T) => Promise<Res>,
): Promise<Res | ActionResult<never>> {
  const t = await getTranslations();
  const parsed = schema.safeParse(input);
  if (!parsed.success) return fail(t("errors.invalidInput"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  return body(supabase, parsed.data, t);
}

function refresh(opts: { briefId?: string; deliverableId?: string } = {}) {
  revalidatePath("/admin/briefs", "layout");
  revalidatePath("/admin/content", "layout");
  revalidatePath("/admin/deals", "layout");
  revalidatePath("/creator/briefs", "layout");
  revalidatePath("/creator/deliverables", "layout");
  revalidatePath("/creator", "page");
  revalidatePath("/agency", "layout");
  if (opts.briefId) revalidatePath(`/admin/briefs/${opts.briefId}`);
  if (opts.deliverableId) revalidatePath(`/admin/content/${opts.deliverableId}`);
}

// ---------------------------------------------------------------------------------------------------------------
// Brief templates, briefs and Q&A
// ---------------------------------------------------------------------------------------------------------------
export async function saveBriefTemplate(input: BriefTemplateInput): Promise<ActionResult<{ id: string }>> {
  return act(briefTemplateInput, input, async (db, v, t) => {
    const { data, error } = await db.rpc("brief_template_save", {
      p: {
        id: v.id,
        name: v.name,
        description: v.description,
        is_default: v.isDefault,
        content: v.content,
      },
    });
    if (error) return dbFail(error, t);
    revalidatePath("/admin/briefs", "layout");
    return { ok: true, data: { id: data }, message: t("content.templates.saved") };
  });
}

export async function archiveBriefTemplate(templateId: string, archived: boolean): Promise<ActionResult> {
  return act(uuid, templateId, async (db, id, t) => {
    const { error } = await db.rpc("brief_template_archive", {
      p_template: id,
      p_archived: archived,
    });
    if (error) return dbFail(error, t);
    revalidatePath("/admin/briefs", "layout");
    return {
      ok: true,
      message: archived ? t("content.templates.archived") : t("content.templates.restored"),
    };
  });
}

/** Creates the deal's brief and deliverables from its campaign's template (or the default). */
export async function createBriefForDeal(dealId: string): Promise<ActionResult<{ id: string }>> {
  return act(uuid, dealId, async (db, id, t) => {
    try {
      const briefId = await setupContentForDeal(db, id);
      if (!briefId) return fail(t("content.errors.dealClosed"));
      refresh({ briefId });
      return { ok: true, data: { id: briefId }, message: t("content.briefs.created") };
    } catch (e) {
      return dbFail(
        {
          code: (e as { code?: string }).code,
          message: e instanceof Error ? e.message : String(e),
        },
        t,
      );
    }
  });
}

export async function saveBrief(input: BriefSaveInput): Promise<ActionResult> {
  return act(briefSaveInput, input, async (db, v, t) => {
    const { error } = await db.rpc("brief_save", { p_brief: v.briefId, p_content: v.content });
    if (error) return dbFail(error, t);
    refresh({ briefId: v.briefId });
    return { ok: true, message: t("content.briefs.saved") };
  });
}

export async function publishBrief(input: z.input<typeof briefPublishInput>): Promise<ActionResult> {
  return act(briefPublishInput, input, async (db, v, t) => {
    const { error } = await db.rpc("brief_publish", { p_brief: v.briefId, p_note: v.note });
    if (error) return dbFail(error, t);
    refresh({ briefId: v.briefId });
    return { ok: true, message: t("content.briefs.published") };
  });
}

export async function acknowledgeBrief(briefId: string, versionId: string): Promise<ActionResult> {
  return act(z.object({ b: uuid, v: uuid }), { b: briefId, v: versionId }, async (db, x, t) => {
    const { error } = await db.rpc("brief_acknowledge", { p_brief: x.b, p_version: x.v });
    if (error) return dbFail(error, t);
    refresh({ briefId: x.b });
    return { ok: true, message: t("content.briefs.acknowledged") };
  });
}

export async function addBriefQuestion(input: QuestionInput): Promise<ActionResult> {
  return act(questionInput, input, async (db, v, t) => {
    const { error } = await db.rpc("brief_question_add", {
      p_brief: v.briefId,
      p_body: v.body,
      p_parent: v.parentId ?? undefined,
    });
    if (error) return dbFail(error, t);
    refresh({ briefId: v.briefId });
    return { ok: true, message: v.parentId ? t("content.qa.replied") : t("content.qa.asked") };
  });
}

/** A one-time signed upload for a brief asset (logo, b-roll, moodboard) in the private inf-briefs bucket. */
export async function briefAssetUploadUrl(input: {
  briefId: string;
  fileName: string;
  size: number;
}): Promise<ActionResult<{ path: string; token: string }>> {
  const schema = z.object({
    briefId: uuid,
    fileName: z.string().min(1).max(200),
    size: z.number().int().positive().max(104_857_600),
  });
  return act(schema, input, async (db, v, t) => {
    const detail = await db.rpc("brief_detail", { p_brief: v.briefId });
    if (detail.error || (detail.data as { can_write?: boolean } | null)?.can_write !== true)
      return fail(t("errors.forbidden"));
    const signed = await signedUpload(BRIEFS_BUCKET, contentPath(v.briefId, v.fileName));
    return signed ? { ok: true, data: signed } : fail(t("errors.generic"));
  });
}

export async function briefAssetLink(briefId: string, path: string): Promise<ActionResult<{ url: string }>> {
  return act(z.object({ b: uuid, p: z.string().max(200) }), { b: briefId, p: path }, async (db, v, t) => {
    const allowed = await db.rpc("brief_asset_allowed", { p_brief: v.b, p_path: v.p });
    if (allowed.data !== true) return fail(t("errors.forbidden"));
    const url = await signedLink(BRIEFS_BUCKET, v.p);
    return url ? { ok: true, data: { url } } : fail(t("errors.generic"));
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Deliverables (staff)
// ---------------------------------------------------------------------------------------------------------------
export async function addDeliverables(input: DeliverableNewInput): Promise<ActionResult> {
  return act(deliverableNewInput, input, async (db, v, t) => {
    const items = Array.from({ length: v.count }, (_, i) => ({
      title: v.count > 1 ? `${v.title} ${String(i + 1)}` : v.title,
      platform: v.platform,
      format: v.format,
      stages: v.stages,
      due_dates: v.dueDates,
      revision_limit: v.revisionLimit,
      config_ref: v.count > 1 || !v.configRef ? null : v.configRef,
    }));
    const { error } = await db.rpc("deliverables_create", { p_deal: v.dealId, p_items: items });
    if (error) return dbFail(error, t);
    refresh();
    return { ok: true, message: t("content.deliverables.added", { count: v.count }) };
  });
}

export async function updateDeliverable(input: DeliverableEditInput): Promise<ActionResult> {
  return act(deliverableEditInput, input, async (db, v, t) => {
    const { error } = await db.rpc("deliverable_update", {
      p_id: v.id,
      p: {
        title: v.title,
        stages: v.stages,
        due_dates: v.dueDates,
        revision_limit: v.revisionLimit,
        config_ref: v.configRef ?? "",
        specs: v.specs,
      },
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.id });
    return { ok: true, message: t("content.deliverables.saved") };
  });
}

export async function setDeliverableStatus(input: z.input<typeof statusChangeInput>): Promise<ActionResult> {
  return act(statusChangeInput, input, async (db, v, t) => {
    const { error } = await db.rpc("deliverable_set_status", {
      p_id: v.id,
      p_action: v.action,
      p_reason: v.reason,
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.id });
    return {
      ok: true,
      message: t(`content.deliverables.${v.action === "cancel" ? "cancelled" : "completed"}`),
    };
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Uploads and submissions (creator / agency)
// ---------------------------------------------------------------------------------------------------------------
const MB = 1024 * 1024;

/**
 * A one-time signed upload for a submission file or metrics screenshot, straight from the browser to the private
 * inf-deliverables bucket (resumable for large videos). Sizes follow the content.uploads setting.
 */
export async function deliverableUploadUrl(
  input: UploadRequest,
): Promise<ActionResult<{ path: string; token: string }>> {
  return act(uploadRequest, input, async (db, v, t) => {
    const [allowed, setting] = await Promise.all([
      db.rpc("deliverable_upload_allowed", { p_id: v.deliverableId }),
      db.rpc("setting", { p_key: "content.uploads" }),
    ]);
    if (allowed.data !== true) return fail(t("errors.forbidden"));
    const limits = SETTINGS["content.uploads"].schema.catch(SETTINGS["content.uploads"].default).parse(setting.data);
    const max = v.type.startsWith("video/")
      ? limits.max_video_mb
      : v.type.startsWith("image/")
        ? limits.max_image_mb
        : limits.max_document_mb;
    if (v.size > max * MB) return fail(t("content.errors.tooLarge", { mb: max }));
    const signed = await signedUpload(DELIVERABLES_BUCKET, contentPath(v.deliverableId, v.fileName));
    return signed ? { ok: true, data: signed } : fail(t("errors.generic"));
  });
}

export async function deliverableFileLink(deliverableId: string, path: string): Promise<ActionResult<{ url: string }>> {
  return act(z.object({ d: uuid, p: z.string().max(200) }), { d: deliverableId, p: path }, async (db, v, t) => {
    const allowed = await db.rpc("deliverable_file_allowed", { p_deliverable: v.d, p_path: v.p });
    if (allowed.data !== true) return fail(t("errors.forbidden"));
    const url = await signedLink(DELIVERABLES_BUCKET, v.p);
    return url ? { ok: true, data: { url } } : fail(t("errors.generic"));
  });
}

export async function submitWork(input: SubmissionInput): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = submissionInput.safeParse(input);
  if (!parsed.success)
    return fail(
      parsed.error.issues.some((i) => i.message === "empty")
        ? t("content.errors.submissionEmpty")
        : t("errors.invalidInput"),
    );
  const v = parsed.data;
  if (v.files.some((f) => !f.path.startsWith(`${v.deliverableId}/`))) return fail(t("content.errors.invalidFile"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const d = await loadDeliverable(supabase, v.deliverableId).catch(() => null);
  if (!d || d.side === "eduwit") return fail(t("errors.forbidden"));
  const { data: submissionId, error } = await supabase.rpc("submission_add", {
    p_deliverable: v.deliverableId,
    p: { kind: v.kind, body: v.body, files: v.files, link_url: v.linkUrl, note: v.note },
  });
  if (error) return dbFail(error, t);
  // The scan runs at once; if it fails, the reviewer can run it again (approval waits for it).
  const scan = await scanAndRecord({
    submissionId,
    kind: v.kind,
    platform: d.platform,
    text: [v.body, v.note].filter(Boolean).join("\n\n"),
  }).catch((e: unknown) => {
    log.error("content.scan_failed", {
      submission_id: submissionId,
      error: e instanceof Error ? e.message : String(e),
    });
    return null;
  });
  refresh({ deliverableId: v.deliverableId });
  if (scan && !scan.passed) return { ok: true, message: t("content.submit.sentWithFlags") };
  return { ok: true, message: t("content.submit.sent") };
}

/** Staff: run the automatic scan again (when it failed to run, or after the banned-claims list changed). */
export async function rescanSubmission(submissionId: string): Promise<ActionResult> {
  return act(uuid, submissionId, async (db, id, t) => {
    const { data: row, error } = await db
      .from("deliverable_submissions")
      .select("id, kind, body, creator_note, deliverable_id, deliverables(platform)")
      .eq("id", id)
      .maybeSingle();
    if (error || !row?.deliverables) return fail(t("errors.forbidden"));
    const review = await db.rpc("deliverable_detail", { p_id: row.deliverable_id });
    if ((review.data as { can_review?: boolean } | null)?.can_review !== true) return fail(t("errors.forbidden"));
    try {
      await scanAndRecord({
        submissionId: row.id,
        kind: row.kind === "draft" ? "draft" : "concept",
        platform: z
          .enum(["instagram", "youtube", "facebook", "linkedin", "x", "telegram", "moj_josh", "other"])
          .parse(row.deliverables.platform),
        text: [row.body, row.creator_note].filter(Boolean).join("\n\n"),
      });
    } catch (e) {
      log.error("content.rescan_failed", {
        submission_id: id,
        error: e instanceof Error ? e.message : String(e),
      });
      return fail(t("errors.generic"));
    }
    refresh({ deliverableId: row.deliverable_id });
    return { ok: true, message: t("content.review.rescanned") };
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Review (staff), comments (both sides), overrides, extensions
// ---------------------------------------------------------------------------------------------------------------
export async function reviewSubmission(input: ReviewInput & { deliverableId: string }): Promise<ActionResult> {
  return act(reviewInput.and(z.object({ deliverableId: uuid })), input, async (db, v, t) => {
    const { error } = await db.rpc("submission_review", {
      p_submission: v.submissionId,
      p_decision: v.decision,
      p_note: v.note,
      p_checklist: v.checklist ?? undefined,
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.deliverableId });
    return {
      ok: true,
      message: v.decision === "approve" ? t("content.review.approved") : t("content.review.changesSent"),
    };
  });
}

export async function addReviewComment(input: CommentInput & { deliverableId: string }): Promise<ActionResult> {
  return act(commentInput.and(z.object({ deliverableId: uuid })), input, async (db, v, t) => {
    const { error } = await db.rpc("review_comment_add", {
      p_submission: v.submissionId,
      p_body: v.body,
      p_timestamp_ms: v.timestampMs ?? undefined,
      p_region: v.region ?? undefined,
      p_parent: v.parentId ?? undefined,
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.deliverableId });
    return { ok: true, message: t("content.comments.added") };
  });
}

export async function setCommentResolved(
  commentId: string,
  resolved: boolean,
  deliverableId: string,
): Promise<ActionResult> {
  return act(z.object({ c: uuid, d: uuid }), { c: commentId, d: deliverableId }, async (db, v, t) => {
    const { error } = await db.rpc("review_comment_set_resolved", {
      p_comment: v.c,
      p_resolved: resolved,
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.d });
    return { ok: true };
  });
}

export async function overrideCheck(
  input: z.input<typeof overrideInput> & { deliverableId: string },
): Promise<ActionResult> {
  return act(overrideInput.and(z.object({ deliverableId: uuid })), input, async (db, v, t) => {
    const { error } = await db.rpc("compliance_override", {
      p_check: v.checkId,
      p_reason: v.reason,
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.deliverableId });
    return { ok: true, message: t("content.review.overridden") };
  });
}

export async function requestExtension(input: z.input<typeof extensionInput>): Promise<ActionResult> {
  return act(extensionInput, input, async (db, v, t) => {
    const { error } = await db.rpc("revision_extension_request", {
      p_deliverable: v.deliverableId,
      p_reason: v.reason,
      p_fee_paise: v.feePaise,
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.deliverableId });
    return { ok: true, message: t("content.extensions.requested") };
  });
}

export async function decideExtension(
  input: z.input<typeof decisionInput> & { deliverableId: string },
): Promise<ActionResult> {
  return act(decisionInput.and(z.object({ deliverableId: uuid })), input, async (db, v, t) => {
    const { error } = await db.rpc("revision_extension_decide", {
      p_id: v.id,
      p_approve: v.approve,
      p_note: v.note,
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.deliverableId });
    return {
      ok: true,
      message: v.approve ? t("content.extensions.approved") : t("content.extensions.rejected"),
    };
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Scheduling, go-live, verification and metrics
// ---------------------------------------------------------------------------------------------------------------
export async function scheduleDeliverable(input: z.input<typeof scheduleInput>): Promise<ActionResult> {
  return act(scheduleInput, input, async (db, v, t) => {
    const { error } = await db.rpc("deliverable_schedule", { p_id: v.deliverableId, p_at: v.at });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.deliverableId });
    return { ok: true, message: t("content.live.scheduled") };
  });
}

export async function submitLivePost(input: PostInput): Promise<ActionResult> {
  return act(postInput, input, async (db, v, t) => {
    const d = await loadDeliverable(db, v.deliverableId).catch(() => null);
    if (!d || d.side === "eduwit") return fail(t("errors.forbidden"));
    const check = checkPostUrl(d.platform, v.url);
    if (!check.ok) return fail(t(`content.errors.url.${check.error}`));
    const oembed = await fetchOembed(d.platform, check.url);
    const { error } = await db.rpc("post_submit", {
      p_deliverable: v.deliverableId,
      p_url: check.url,
      p_posted_on: v.postedOn,
      p_oembed: oembed ? { ...oembed } : undefined,
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.deliverableId });
    return { ok: true, message: t("content.live.submitted") };
  });
}

export async function verifyLivePost(input: VerifyInput & { deliverableId: string }): Promise<ActionResult> {
  return act(verifyInput.and(z.object({ deliverableId: uuid })), input, async (db, v, t) => {
    const { error } = await db.rpc("post_verify", {
      p_post: v.postId,
      p_live: v.live,
      p_disclosure: v.disclosure,
      p_matches: v.matches,
      p_note: v.note,
    });
    if (error) return dbFail(error, t);
    refresh({ deliverableId: v.deliverableId });
    return {
      ok: true,
      message: v.live && v.disclosure && v.matches ? t("content.live.verified") : t("content.live.rejected"),
    };
  });
}

export async function submitMetrics(input: MetricsInput): Promise<ActionResult> {
  const t = await getTranslations();
  const parsed = metricsInput.safeParse(input);
  if (!parsed.success)
    return fail(
      parsed.error.issues.some((i) => i.message === "empty")
        ? t("content.errors.metricsEmpty")
        : t("errors.invalidInput"),
    );
  const v = parsed.data;
  if (v.screenshots.some((p) => !p.startsWith(`${v.deliverableId}/`))) return fail(t("content.errors.invalidFile"));
  const supabase = await signedIn();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { deliverableId, ...p } = v;
  const { error } = await supabase.rpc("metrics_submit", { p_deliverable: deliverableId, p });
  if (error) return dbFail(error, t);
  refresh({ deliverableId });
  return { ok: true, message: t("content.metrics.saved") };
}

// ---------------------------------------------------------------------------------------------------------------
// Banned claims and penalties (staff)
// ---------------------------------------------------------------------------------------------------------------
export async function saveBannedClaim(input: BannedClaimInput): Promise<ActionResult> {
  const { safePattern } = await import("@/lib/content/compliance");
  return act(bannedClaimInput, input, async (db, v, t) => {
    if (v.kind === "regex" && !safePattern(v.pattern)) return fail(t("content.errors.unsafePattern"));
    const { error } = await db.rpc("banned_claim_save", {
      p: {
        id: v.id,
        pattern: v.pattern,
        kind: v.kind,
        severity: v.severity,
        note: v.note,
        active: v.active,
      },
    });
    if (error) return dbFail(error, t);
    revalidatePath("/admin/content/claims");
    return { ok: true, message: t("content.claims.saved") };
  });
}

export async function decidePenalty(input: z.input<typeof decisionInput>): Promise<ActionResult> {
  return act(decisionInput, input, async (db, v, t) => {
    const { error } = await db.rpc("penalty_decide", {
      p_id: v.id,
      p_approve: v.approve,
      p_note: v.note,
    });
    if (error) return dbFail(error, t);
    revalidatePath("/admin/content/penalties");
    revalidatePath("/admin/deals", "layout");
    return {
      ok: true,
      message: v.approve ? t("content.penalties.approved") : t("content.penalties.rejected"),
    };
  });
}
