/** What the view builder offers (spec B8.4). Every field is one lead_list() accepts; the database checks again. */

export type FieldType = "text" | "choice" | "date" | "number" | "bool" | "tag" | "stage";
export type FieldDef = { field: string; label: string; type: FieldType; choices?: [string, string][]; workspaceOnly?: boolean };
export type Condition = { field: string; op: string; value?: string | number | string[] | number[] };

export const VIEW_FIELDS: FieldDef[] = [
  { field: "stage_id", label: "Stage", type: "stage" },
  { field: "sub_stage", label: "Sub-stage", type: "text" },
  { field: "temperature", label: "Temperature", type: "choice", choices: [["hot", "Hot"], ["warm", "Warm"], ["cold", "Cold"]] },
  { field: "next_task_due_at", label: "Next follow-up", type: "date" },
  { field: "last_contacted_at", label: "Last contact", type: "date" },
  { field: "assigned_at", label: "Assigned", type: "date" },
  { field: "contact_attempts", label: "Call attempts", type: "number" },
  { field: "score", label: "Score", type: "number" },
  { field: "course", label: "Programme", type: "text" },
  { field: "university", label: "University", type: "text" },
  { field: "source", label: "Source", type: "text" },
  { field: "campaign", label: "Campaign", type: "text" },
  { field: "city", label: "City", type: "text" },
  { field: "language", label: "Language", type: "text" },
  { field: "handoff_reason", label: "Why with us", type: "text" },
  { field: "tags", label: "Tag", type: "tag" },
  { field: "flagged", label: "Flagged", type: "bool" },
  { field: "sla_breached_at", label: "First-contact timer missed", type: "date" },
  { field: "opted_out", label: "Opted out", type: "bool" },
  { field: "status", label: "Status", type: "choice", choices: [["active", "Active"], ["pool", "Nurture pool"], ["closed", "Closed"]], workspaceOnly: true },
  { field: "lane", label: "Lane", type: "choice", choices: [["sales", "Sales"], ["nurture", "Nurture"]], workspaceOnly: true },
  { field: "owner_name", label: "Counsellor", type: "text", workspaceOnly: true },
  { field: "owner_id", label: "Unassigned", type: "bool", workspaceOnly: true },
];

export const OPS: Record<FieldType, [string, string][]> = {
  text: [["contains", "contains"], ["eq", "is exactly"], ["neq", "is not"], ["not_null", "is set"], ["is_null", "is empty"]],
  choice: [["eq", "is"], ["neq", "is not"]],
  stage: [["in", "is one of"], ["not_in", "is none of"]],
  date: [["lte_now", "is due or past"], ["within_days", "in the last … days"], ["older_than_days", "more than … days ago"], ["is_null", "never"], ["not_null", "is set"]],
  number: [["gte", "at least"], ["lte", "at most"], ["eq", "exactly"]],
  bool: [["is_true", "yes"], ["is_false", "no"]],
  tag: [["has_tag", "has"]],
};

export const SORTS: [string, string][] = [
  ["next_task_due_at", "Next follow-up"], ["assigned_at", "Assigned"], ["last_contacted_at", "Last contact"], ["stage_changed_at", "Stage changed"],
  ["score", "Score"], ["handed_off_at", "Handed to B2C"], ["name", "Name"], ["updated_at", "Last change"],
];

export const needsValue = (op: string) => !["lte_now", "is_null", "not_null", "is_true", "is_false"].includes(op);

/** "Unassigned" is stored as owner_id is null; everything else is passed as written. */
export function toFilter(c: Condition): Condition {
  if (c.field === "owner_id") return { field: "owner_id", op: c.op === "is_true" ? "is_null" : "not_null" };
  return needsValue(c.op) ? c : { field: c.field, op: c.op };
}

export function fromFilter(c: Condition): Condition {
  if (c.field === "owner_id") return { field: "owner_id", op: c.op === "is_null" ? "is_true" : "is_false" };
  return c;
}
