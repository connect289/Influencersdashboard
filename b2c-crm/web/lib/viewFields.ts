/** What the view builder, the table and segments offer (spec B8.2, B10.1). Every field is one of b2c.lead_fields(); the database checks again. */
import { inr, when } from "@/lib/format";
import { APP_STATUS_LABEL, CONSENT_LABEL, LANE_LABEL, OUTCOME_LABEL, STATUS_LABEL } from "@/lib/labels";

export type FieldType = "text" | "choice" | "date" | "number" | "bool" | "tag" | "stage" | "set";
export type FieldDef = {
  field: string; label: string; type: FieldType; choices?: [string, string][]; workspaceOnly?: boolean;
  /** University and counsellor commission: Admin and Marketing only (b2c.money_fields). */
  money?: boolean;
  /** Shown in rupees. */
  inr?: boolean;
  /** Not offered as a filter (a twin field filters better) or as a column. */
  noFilter?: boolean; noColumn?: boolean;
};
export type Condition = { field: string; op: string; value?: string | number | string[] | number[] };
export type Filters = { all?: Condition[]; any?: Condition[]; groups?: { all?: Condition[]; any?: Condition[] }[] };
export type Group = { mode: "all" | "any"; conds: Condition[] };

const pairs = (o: Record<string, string>): [string, string][] => Object.entries(o);

export const LEAD_FIELDS: FieldDef[] = [
  { field: "stage_id", label: "Stage", type: "stage", noColumn: true },
  { field: "stage", label: "Stage", type: "text", noFilter: true },
  { field: "sub_stage", label: "Sub-stage", type: "text" },
  { field: "canonical_stage", label: "Standard stage", type: "text" },
  { field: "stage_changed_at", label: "Stage changed", type: "date" },
  { field: "days_in_stage", label: "Days in stage", type: "number" },
  { field: "temperature", label: "Temperature", type: "choice", choices: [["hot", "Hot"], ["warm", "Warm"], ["cold", "Cold"]] },
  { field: "hot", label: "Marked hot", type: "bool" },
  { field: "score", label: "Score", type: "number" },
  { field: "fit_points", label: "Fit points", type: "number" },
  { field: "engagement_points", label: "Engagement points", type: "number" },
  { field: "name", label: "Student", type: "text" },
  { field: "lead_id", label: "Lead #", type: "number" },
  { field: "phone", label: "Phone", type: "text" },
  { field: "email", label: "Email", type: "text" },
  { field: "city", label: "City", type: "text" },
  { field: "state", label: "State", type: "text" },
  { field: "language", label: "Language", type: "text" },
  { field: "course", label: "Programme", type: "text" },
  { field: "specialization", label: "Specialization", type: "text" },
  { field: "university", label: "University", type: "text" },
  { field: "programme_level", label: "Level", type: "text" },
  { field: "study_mode", label: "Study mode", type: "text" },
  { field: "qualification", label: "Qualification", type: "text" },
  { field: "work_experience", label: "Work experience", type: "text" },
  { field: "budget", label: "Budget (₹ a year)", type: "number", inr: true },
  { field: "timeline", label: "Timeline", type: "text" },
  { field: "created_at", label: "Lead date", type: "date" },
  { field: "source", label: "Source", type: "text" },
  { field: "campaign", label: "Campaign", type: "text" },
  { field: "lead_status", label: "Status in the master table", type: "text" },
  { field: "lane", label: "Lane", type: "choice", choices: pairs(LANE_LABEL), workspaceOnly: true },
  { field: "status", label: "Status", type: "choice", choices: pairs(STATUS_LABEL), workspaceOnly: true },
  { field: "handoff_reason", label: "Why with us", type: "text" },
  { field: "cause", label: "Hand-off cause", type: "text" },
  { field: "handed_off_at", label: "Handed to Spark", type: "date" },
  { field: "partner_bar_reason", label: "Partner-barred", type: "choice", choices: [["duplicate", "Duplicate"], ["lost", "A partner lost it"]] },
  { field: "partner", label: "Partner who lost it", type: "text" },
  { field: "partner_lost_reason", label: "Partner's lost reason", type: "text" },
  { field: "partners_tried_count", label: "Partners tried", type: "number" },
  { field: "owner_name", label: "Counsellor", type: "text", workspaceOnly: true },
  { field: "owner_id", label: "Unassigned", type: "bool", workspaceOnly: true, noColumn: true },
  { field: "assigned_at", label: "Assigned", type: "date" },
  { field: "next_task_due_at", label: "Next follow-up", type: "date" },
  { field: "first_contacted_at", label: "First contact", type: "date" },
  { field: "last_contacted_at", label: "Last contact", type: "date" },
  { field: "contact_attempts", label: "Call attempts", type: "number" },
  { field: "last_activity_at", label: "Last activity", type: "date" },
  { field: "days_untouched", label: "Days untouched", type: "number" },
  { field: "sla_status", label: "First-contact SLA", type: "choice", choices: [["running", "Running"], ["at_risk", "At risk"], ["breached", "Breached"], ["met", "Met"]] },
  { field: "sla_due_at", label: "First contact due", type: "date" },
  { field: "sla_breached_at", label: "First-contact timer missed", type: "date" },
  { field: "sla_met_at", label: "First contact in time", type: "date" },
  { field: "calls_logged", label: "Calls logged", type: "number" },
  { field: "calls_connected", label: "Calls connected", type: "number" },
  { field: "last_call_outcome", label: "Last call outcome", type: "choice", choices: pairs(OUTCOME_LABEL) },
  { field: "last_call_at", label: "Last call", type: "date" },
  { field: "wa_sent", label: "WhatsApp sent", type: "number" },
  { field: "wa_received", label: "WhatsApp received", type: "number" },
  { field: "last_wa_in_at", label: "Last WhatsApp from the student", type: "date" },
  { field: "emails_sent", label: "Emails sent", type: "number" },
  { field: "emails_opened", label: "Emails opened", type: "number" },
  { field: "last_email_at", label: "Last email", type: "date" },
  { field: "last_reply_at", label: "Last reply", type: "date" },
  { field: "last_reply_class", label: "Last reply was", type: "choice", choices: [["positive", "Positive"], ["question", "Question"], ["negative", "Negative"], ["opt_out", "Opt-out"], ["other", "Other"]] },
  { field: "partner_consent_state", label: "Partner-sharing consent", type: "choice", choices: pairs(CONSENT_LABEL) },
  { field: "marketing_consent", label: "Marketing consent", type: "bool" },
  { field: "opted_out", label: "Opted out", type: "bool" },
  { field: "tags", label: "Tag", type: "tag" },
  { field: "flagged", label: "Flagged", type: "set" },
  { field: "pool_reason", label: "Pool reason", type: "choice", choices: [["partner_lost", "Partner lost"], ["counsellor_lost", "Counsellor lost"], ["not_qualified", "Not qualified"]] },
  { field: "pool_entered_at", label: "Entered the pool", type: "date" },
  { field: "lost_by", label: "Lost by", type: "choice", choices: [["partner", "Partner"], ["counsellor", "Counsellor"]] },
  { field: "journey", label: "Journey (key)", type: "text" },
  { field: "reengaged_at", label: "Re-engaged", type: "date" },
  { field: "reenquired_at", label: "Enquired again", type: "date" },
  { field: "application_status", label: "Application", type: "choice", choices: pairs(APP_STATUS_LABEL) },
  { field: "application_ref", label: "Application ID", type: "text" },
  { field: "documents_pending", label: "Documents pending", type: "number" },
  { field: "enrollment_status", label: "Enrolment", type: "choice", choices: [["reported", "Reported"], ["verified", "Verified"], ["refunded", "Refunded"], ["cancelled", "Cancelled"]] },
  { field: "enrolled_on", label: "Enrolled on", type: "date" },
  { field: "fee", label: "Programme fee", type: "number", inr: true },
  { field: "university_gross", label: "University commission (gross)", type: "number", inr: true, money: true },
  { field: "university_gst", label: "University commission GST", type: "number", inr: true, money: true },
  { field: "university_net", label: "University commission (net)", type: "number", inr: true, money: true },
  { field: "university_status", label: "University commission status", type: "choice", choices: [["expected", "Expected"], ["realised", "Realised"], ["invoiced", "Invoiced"]], money: true },
  { field: "counsellor_commission", label: "Counsellor commission", type: "number", inr: true, money: true },
  { field: "updated_at", label: "Last change", type: "date" },
  { field: "closed_at", label: "Closed", type: "date" },
  { field: "is_test", label: "Test lead", type: "bool", workspaceOnly: true },
];

const BY_FIELD = new Map(LEAD_FIELDS.map((f) => [f.field, f]));
export const fieldDef = (f: string): FieldDef | undefined => BY_FIELD.get(f);

/** The fields one person may use: Sales sees no workspace-only fields, and only Admin and Marketing see money. */
export function fieldsFor(role: "sales" | "workspace", money: boolean): FieldDef[] {
  return LEAD_FIELDS.filter((f) => (role === "workspace" || !f.workspaceOnly) && (money || !f.money));
}

/** Kept for the segment builder and older callers: the filterable fields of the Workspace. */
export const VIEW_FIELDS: FieldDef[] = LEAD_FIELDS.filter((f) => !f.noFilter && !f.money);

export const OPS: Record<FieldType, [string, string][]> = {
  text: [["contains", "contains"], ["eq", "is exactly"], ["neq", "is not"], ["not_null", "is set"], ["is_null", "is empty"]],
  choice: [["eq", "is"], ["neq", "is not"], ["not_null", "is set"], ["is_null", "is empty"]],
  stage: [["in", "is one of"], ["not_in", "is none of"]],
  date: [["today", "today"], ["this_week", "this week"], ["this_month", "this month"], ["last_month", "last month"], ["within_days", "in the last … days"],
    ["older_than_days", "more than … days ago"], ["next_days", "in the next … days"], ["between", "between"], ["gte", "on or after"], ["lte", "on or before"],
    ["lte_now", "is due or past"], ["is_null", "never"], ["not_null", "is set"]],
  number: [["gte", "at least"], ["lte", "at most"], ["gt", "more than"], ["lt", "less than"], ["eq", "exactly"], ["between", "between"], ["is_null", "is empty"], ["not_null", "is set"]],
  bool: [["is_true", "yes"], ["is_false", "no"]],
  tag: [["has_tag", "has"], ["not_tag", "does not have"]],
  set: [["not_null", "yes"], ["is_null", "no"]],
};

const NO_VALUE = ["lte_now", "is_null", "not_null", "is_true", "is_false", "today", "this_week", "this_month", "last_month"];
export const needsValue = (op: string) => !NO_VALUE.includes(op);

const IST_START = "T00:00:00+05:30";
const IST_END = "T23:59:59.999+05:30";
const day = (v: unknown) => String(v ?? "").slice(0, 10);

/** A condition as the database wants it: "Unassigned" as owner_id is null, numbers as numbers, dates as whole IST days. */
export function toFilter(c: Condition): Condition {
  if (c.field === "owner_id") return { field: "owner_id", op: c.op === "is_true" ? "is_null" : "not_null" };
  if (!needsValue(c.op)) return { field: c.field, op: c.op };
  const d = fieldDef(c.field);
  if (c.op === "between") {
    const [a, b] = Array.isArray(c.value) ? c.value : [];
    if (d?.type === "date") return { ...c, value: [day(a) + IST_START, day(b) + IST_END] };
    return { ...c, value: [Number(a ?? 0), Number(b ?? 0)] };
  }
  if (d?.type === "date" && (c.op === "gte" || c.op === "lte")) return { ...c, value: day(c.value) + (c.op === "gte" ? IST_START : IST_END) };
  if (d?.type === "number" || c.op.endsWith("_days")) return { ...c, value: Number(c.value ?? 0) };
  return c;
}

export function fromFilter(c: Condition): Condition {
  if (c.field === "owner_id") return { field: "owner_id", op: c.op === "is_null" ? "is_true" : "is_false" };
  if (fieldDef(c.field)?.type === "date" && (c.op === "between" || c.op === "gte" || c.op === "lte")) {
    return { ...c, value: Array.isArray(c.value) ? c.value.map(day) : day(c.value) };
  }
  return c;
}

/** A saved view's filters as the builder's groups (all of the groups hold; inside a group all or any of the conditions). */
export function toGroups(f: Filters | null | undefined): Group[] {
  const out: Group[] = [];
  const push = (mode: Group["mode"], cs?: Condition[]) => { if (cs?.length) out.push({ mode, conds: cs.map(fromFilter) }); };
  push("all", f?.all);
  push("any", f?.any);
  for (const g of f?.groups ?? []) { push("all", g.all); push("any", g.any); }
  return out;
}

/** The builder's groups as filters: one "all" group stays {all}, anything else becomes {groups} (b40 lead_list). */
export function fromGroups(groups: Group[]): Filters {
  const gs = groups.filter((g) => g.conds.length > 0).map((g) => ({ mode: g.mode, conds: g.conds.map(toFilter) }));
  if (gs.length === 0) return {};
  if (gs.length === 1 && gs[0]!.mode === "all") return { all: gs[0]!.conds };
  return { groups: gs.map((g) => (g.mode === "all" ? { all: g.conds } : { any: g.conds })) };
}

/** The table's columns when a view names none. */
export const DEFAULT_COLUMNS = ["name", "course", "stage", "handoff_reason", "owner_name", "next_task_due_at", "sla_status", "score"];

/** Fields a view may be grouped by (a handful of values each). */
export const GROUPABLE = ["stage", "sub_stage", "canonical_stage", "status", "lane", "temperature", "owner_name", "handoff_reason", "source", "campaign", "course",
  "university", "city", "state", "language", "programme_level", "study_mode", "qualification", "pool_reason", "lost_by", "partner", "journey", "sla_status",
  "last_call_outcome", "last_reply_class", "application_status", "enrollment_status", "university_status", "partner_consent_state", "flagged", "timeline"];

/** A plain-text cell: dates in IST, rupees, yes/no, labels for codes. */
export function cellText(field: string, v: unknown, now = new Date()): string {
  if (v === null || v === undefined || v === "") return "—";
  const d = fieldDef(field);
  if (Array.isArray(v)) return v.length ? v.join(", ") : "—";
  if (d?.type === "date") return when(String(v), now);
  if (d?.inr) return inr(v as number);
  if (typeof v === "boolean" || d?.type === "bool") return v === true || v === "true" ? "Yes" : "No";
  if (d?.choices) return d.choices.find(([k]) => k === String(v))?.[1] ?? String(v).replace(/_/g, " ");
  return String(v);
}

/** Segments (spec B9.1) use the same fields (b40 widened segment_fields to lead_fields). */
export const SEGMENT_FIELDS: FieldDef[] = [
  ...LEAD_FIELDS.filter((f) => ["status", "pool_reason", "lost_by", "pool_entered_at", "marketing_consent", "journey", "reengaged_at", "lane"].includes(f.field)).map((f) => ({ ...f, workspaceOnly: false })),
  ...VIEW_FIELDS.filter((f) => !["status", "pool_reason", "lost_by", "pool_entered_at", "marketing_consent", "journey", "reengaged_at", "lane"].includes(f.field)),
];
