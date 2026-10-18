"use server";
// Admin creator CRM actions. Each validates input, calls one inf.* function (which checks the staff permission) and
// refreshes the affected screens.
import { revalidatePath } from "next/cache";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { fetchMe } from "@/lib/auth/guards";
import { CsvError, parseCsv, toCsv } from "@/lib/csv";
import {
  creatorFilterSchema,
  creatorInput,
  filtersForView,
  IMPORT_MAX_BYTES,
  IMPORT_MAX_ROWS,
  mapHeaders,
  outreachInput,
  PIPELINE_STAGES,
  prepareImport,
  taskInput,
  type CreatorInput,
  type OutreachInput,
  type TaskInput,
} from "@/lib/creators/crm";
import { normalisePhone } from "@/lib/creators/schemas";
import { log } from "@/lib/log";
import { createClient, type ServerSupabase } from "@/lib/supabase/server";
import { fail, type ActionResult } from "./result";

type T = Awaited<ReturnType<typeof getTranslations>>;
const uuid = z.uuid();

async function session(): Promise<ServerSupabase | null> {
  const supabase = await createClient();
  const me = await fetchMe(supabase);
  if (me.kind !== "staff" || !me.session?.verified || me.session.revoked) return null;
  return supabase;
}

function dbFail(error: { code?: string; message: string }, t: T): ActionResult<never> {
  if (error.code === "42501") return fail(t("errors.forbidden"));
  if (error.code === "23505") {
    if (/email/i.test(error.message)) return fail(t("creators.errors.emailTaken"));
    if (/phone/i.test(error.message)) return fail(t("creators.errors.phoneTaken"));
    return fail(t("creators.errors.handleTaken"));
  }
  if (/not signed up/i.test(error.message)) return fail(t("creators.errors.notSignedUp"));
  if (/is blocked/i.test(error.message)) return fail(t("creators.errors.blocked"));
  if (/untouched prospects/i.test(error.message)) return fail(t("creators.errors.notDraft"));
  if (/in the past/i.test(error.message)) return fail(t("creators.errors.pastFollowUp"));
  if (error.code === "22023" || error.code === "23514" || error.code === "22P02") return fail(t("errors.invalidInput"));
  log.warn("creators.db_error", { code: error.code, error: error.message });
  return fail(t("errors.generic"));
}

function refresh(creatorId?: string) {
  revalidatePath("/admin/creators");
  revalidatePath("/admin");
  if (creatorId) revalidatePath(`/admin/creators/${creatorId}`);
}

export async function saveCreator(input: CreatorInput): Promise<ActionResult<{ id: string }>> {
  const t = await getTranslations();
  const p = creatorInput.safeParse(input);
  if (!p.success) {
    const code = p.error.issues[0]?.message;
    return fail(
      code === "handle"
        ? t("creators.errors.handle")
        : code === "phone"
          ? t("profile.fields.phoneHint")
          : t("errors.invalidInput"),
    );
  }
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = p.data;
  const { data, error } = await supabase.rpc("creator_save", {
    p: {
      id: v.id ?? "",
      display_name: v.displayName,
      legal_name: v.legalName,
      handle: v.handle,
      email: v.email,
      phone_e164: v.phone ? (normalisePhone(v.phone) ?? "") : "",
      city: v.city,
      state: v.state,
      languages: v.languages,
      niches: v.niches,
      tags: v.tags,
      owner_id: v.ownerId,
      tier_id: v.tierId,
      source: v.source,
      bio: v.bio,
    },
  });
  if (error) return dbFail(error, t);
  refresh(data);
  return {
    ok: true,
    data: { id: data },
    message: v.id ? t("creators.saved") : t("creators.created"),
  };
}

export async function setCreatorStage(creatorId: string, stage: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(creatorId).success || !(PIPELINE_STAGES as readonly string[]).includes(stage))
    return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("creator_set_stage", {
    p_creator: creatorId,
    p_stage: stage,
  });
  if (error) return dbFail(error, t);
  refresh(creatorId);
  return {
    ok: true,
    message: t("creators.stageMoved", { stage: t(`creators.stages.${stage as "prospect"}`) }),
  };
}

export async function setCreatorBlocked(creatorId: string, blocked: boolean, reason: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(creatorId).success || (blocked && reason.trim().length < 3))
    return fail(t("creators.errors.reason"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("creator_set_blocked", {
    p_creator: creatorId,
    p_blocked: blocked,
    p_reason: reason.trim(),
  });
  if (error) return dbFail(error, t);
  refresh(creatorId);
  return { ok: true, message: blocked ? t("creators.blockedDone") : t("creators.unblockedDone") };
}

export async function deleteDraftCreator(creatorId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(creatorId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("creator_delete_draft", { p_creator: creatorId });
  if (error) return dbFail(error, t);
  refresh();
  return { ok: true, message: t("creators.deleted") };
}

const bulkInput = z.discriminatedUnion("action", [
  z.object({ action: z.literal("tag_add"), value: z.string().trim().min(1).max(40) }),
  z.object({ action: z.literal("tag_remove"), value: z.string().trim().min(1).max(40) }),
  z.object({ action: z.literal("owner"), value: z.uuid() }),
  z.object({ action: z.literal("stage"), value: z.enum(PIPELINE_STAGES) }),
]);

export async function bulkCreators(
  ids: string[],
  input: z.input<typeof bulkInput>,
): Promise<ActionResult<{ count: number }>> {
  const t = await getTranslations();
  const p = bulkInput.safeParse(input);
  const idList = z.array(uuid).min(1).max(500).safeParse(ids);
  if (!p.success || !idList.success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { data, error } = await supabase.rpc("creators_bulk", {
    p_ids: idList.data,
    p_action: p.data.action,
    p_value: p.data.value,
  });
  if (error) return dbFail(error, t);
  refresh();
  return {
    ok: true,
    data: { count: data },
    message: t("creators.bulk.done", { count: data, total: idList.data.length }),
  };
}

export async function logOutreach(input: OutreachInput): Promise<ActionResult> {
  const t = await getTranslations();
  const p = outreachInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = p.data;
  const { error } = await supabase.rpc("outreach_log", {
    p_creator: v.creatorId,
    p_channel: v.channel,
    p_direction: v.direction,
    p_outcome: v.outcome,
    p_notes: v.notes,
    p_next_follow_up: v.nextFollowUp || undefined,
  });
  if (error) return dbFail(error, t);
  refresh(v.creatorId);
  return { ok: true, message: t("creators.outreach.logged") };
}

export async function markFollowUpDone(activityId: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(activityId).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("follow_up_done", { p_activity: activityId });
  if (error) return dbFail(error, t);
  refresh();
  revalidatePath("/admin/tasks");
  return { ok: true, message: t("creators.outreach.followUpDone") };
}

export async function saveTask(input: TaskInput): Promise<ActionResult> {
  const t = await getTranslations();
  const p = taskInput.safeParse(input);
  if (!p.success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const v = p.data;
  const { error } = await supabase.rpc("task_save", {
    p: {
      id: v.id ?? "",
      title: v.title,
      description: v.description,
      assignee_id: v.assigneeId,
      due_at: v.dueAt,
      priority: v.priority,
      related_type: v.relatedType ?? "",
      related_id: v.relatedId ?? "",
    },
  });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/tasks");
  revalidatePath("/admin");
  if (v.relatedType === "creator" && v.relatedId) revalidatePath(`/admin/creators/${v.relatedId}`);
  return { ok: true, message: v.id ? t("tasks.saved") : t("tasks.created") };
}

export async function setTaskStatus(taskId: string, status: "open" | "done" | "cancelled"): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(taskId).success || !["open", "done", "cancelled"].includes(status))
    return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("task_set_status", { p_task: taskId, p_status: status });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/tasks");
  revalidatePath("/admin");
  revalidatePath("/admin/creators", "layout");
  return { ok: true, message: t(`tasks.statusDone.${status}`) };
}

export async function saveCreatorView(
  name: string,
  filters: Record<string, unknown>,
  shared: boolean,
): Promise<ActionResult> {
  const t = await getTranslations();
  const n = z.string().trim().min(1).max(60).safeParse(name);
  const f = creatorFilterSchema.safeParse(filters);
  if (!n.success || !f.success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("saved_view_save", {
    p_name: n.data,
    p_filters: filtersForView(f.data) as never,
    p_shared: shared,
  });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/creators");
  return { ok: true, message: t("creators.views.saved") };
}

export async function deleteCreatorView(id: string): Promise<ActionResult> {
  const t = await getTranslations();
  if (!uuid.safeParse(id).success) return fail(t("errors.invalidInput"));
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { error } = await supabase.rpc("saved_view_delete", { p_id: id });
  if (error) return dbFail(error, t);
  revalidatePath("/admin/creators");
  return { ok: true, message: t("creators.views.deleted") };
}

// ---------------------------------------------------------------------------------------------------------------
// CSV import
// ---------------------------------------------------------------------------------------------------------------
const reportRow = z.object({
  row: z.number(),
  handle: z.string().nullable().optional(),
  result: z.enum(["created", "duplicate", "error"]),
  reason: z.string().optional(),
});
const importResult = z.object({
  import_id: z.uuid().nullable(),
  dry_run: z.boolean(),
  created: z.number(),
  duplicates: z.number(),
  errors: z.number(),
  report: z.array(reportRow),
});
export type ImportResult = z.infer<typeof importResult> & { reportCsv: string };

/** Validate (dry run) or import a prospects CSV. The file is read as text in the browser and sent here. */
export async function importCreators(
  fileName: string,
  text: string,
  dryRun: boolean,
): Promise<ActionResult<ImportResult>> {
  const t = await getTranslations();
  if (text.length > IMPORT_MAX_BYTES) return fail(t("creators.import.errors.tooBig"));
  let parsed;
  try {
    parsed = parseCsv(text, { maxRows: IMPORT_MAX_ROWS });
  } catch (e) {
    const code = e instanceof CsvError ? e.message : "invalid";
    return fail(
      t(
        code === "too_many_rows"
          ? "creators.import.errors.tooMany"
          : code === "empty"
            ? "creators.import.errors.empty"
            : "creators.import.errors.invalid",
      ),
    );
  }
  const { missing } = mapHeaders(parsed.headers);
  if (missing.length) return fail(t("creators.import.errors.missingColumns", { columns: missing.join(", ") }));
  const { valid, invalid } = prepareImport(parsed.headers, parsed.rows);
  const supabase = await session();
  if (!supabase) return fail(t("errors.sessionEnded"));
  const { data, error } = await supabase.rpc("creator_import", {
    p_file_name: fileName.slice(0, 200) || "import.csv",
    p_rows: valid.map((r) => ({ ...r, phone_e164: r.phone })) as never,
    p_invalid: invalid as never,
    p_dry_run: dryRun,
  });
  if (error) return dbFail(error, t);
  const r = importResult.parse(data);
  if (!dryRun) refresh();
  const reportCsv = toCsv(
    ["row", "handle", "result", "reason"],
    r.report.map((x) => [x.row, x.handle ?? "", x.result, x.reason ?? ""]),
  );
  return { ok: true, data: { ...r, reportCsv } };
}

// ---------------------------------------------------------------------------------------------------------------
// Command palette search
// ---------------------------------------------------------------------------------------------------------------
export async function searchCreators(q: string): Promise<{ id: string; name: string; handle: string }[]> {
  const query = z.string().trim().min(2).max(80).safeParse(q);
  if (!query.success) return [];
  const supabase = await session();
  if (!supabase) return [];
  const { data, error } = await supabase.rpc("creator_list", {
    p: { q: query.data, page_size: 8, sort: "name", dir: "asc" },
  });
  if (error) return [];
  const rows = (data as { rows?: { id: string; display_name: string; handle: string }[] } | null)?.rows ?? [];
  return rows.map((r) => ({ id: r.id, name: r.display_name, handle: r.handle }));
}
