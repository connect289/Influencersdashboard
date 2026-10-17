// Creator-facing lead stages (spec 9.3, STAGE_MAPPING.md). CRM data (student_leads, the B2C status view) and the
// attribution status are mapped to one stage by priority-ordered rules stored in inf.stage_mappings and editable by a
// Super Admin. Stages never move backwards for the creator: a later CRM stage that maps lower is ignored, closed
// outcomes (lost, duplicate, junk, not attributed) can always follow, a closed lead that comes back starts again, and
// an enrolment only changes to "enrolled, cancelled". Pure.

export const CREATOR_STAGES = [
  "new",
  "qualifying",
  "qualified",
  "allocated",
  "counselling",
  "applied",
  "enrolled",
  "lost",
  "duplicate",
  "junk",
  "not_attributed",
] as const;
export type CreatorStage = (typeof CREATOR_STAGES)[number];

export const OPEN_STAGES: readonly CreatorStage[] = [
  "new",
  "qualifying",
  "qualified",
  "allocated",
  "counselling",
  "applied",
];
export const CLOSED_STAGES: readonly CreatorStage[] = ["lost", "duplicate", "junk", "not_attributed"];
const RANK: Record<CreatorStage, number> = {
  new: 1,
  qualifying: 2,
  qualified: 3,
  allocated: 4,
  counselling: 5,
  applied: 6,
  enrolled: 7,
  lost: 0,
  duplicate: 0,
  junk: 0,
  not_attributed: 0,
};

export const STAGE_FIELDS = [
  "attribution_status",
  "stage",
  "lost_reason",
  "enrollment_status",
  "applied_at",
  "is_sales_ready",
  "b2c_stage",
  "b2c_closed_reason",
] as const;
export type StageField = (typeof STAGE_FIELDS)[number];
export type StageInputs = Partial<Record<StageField, string | boolean | null>>;

export interface Condition {
  field: StageField;
  /** Value (case-insensitive) is one of these. */
  in?: string[];
  /** Value is present (not null, not empty). */
  present?: boolean;
  /** Value is empty or missing. */
  empty?: boolean;
  /** Value is true. */
  is_true?: boolean;
}

export interface MappingRule {
  priority: number;
  conditions: Condition[];
  /** null: only adds the flag and keeps evaluating (e.g. "under review"). */
  creator_stage: CreatorStage | null;
  reason_category: string | null;
  flag: "cancelled" | "under_review" | null;
}

export interface StageResult {
  stage: CreatorStage;
  reason: string | null;
  flags: ("cancelled" | "under_review")[];
  /** No rule matched; the last known stage is kept and staff are alerted. */
  unmapped: boolean;
}

const text = (v: string | boolean | null | undefined) => (typeof v === "string" ? v.trim().toLowerCase() : v);

export function matches(c: Condition, x: StageInputs): boolean {
  const v = text(x[c.field]);
  const isEmpty = v === null || v === undefined || v === "" || v === false;
  if (c.empty) return isEmpty;
  if (c.present && isEmpty) return false;
  if (c.is_true && v !== true) return false;
  if (c.in && !(typeof v === "string" && c.in.map((s) => s.toLowerCase()).includes(v))) return false;
  return true;
}

/** The first matching rule's stage (rules in priority order), without the never-backwards rule. */
export function evaluate(x: StageInputs, rules: readonly MappingRule[]): StageResult {
  const flags: StageResult["flags"] = [];
  for (const r of [...rules].sort((a, b) => a.priority - b.priority)) {
    if (!r.conditions.every((c) => matches(c, x))) continue;
    if (r.flag && !flags.includes(r.flag)) flags.push(r.flag);
    if (r.creator_stage) return { stage: r.creator_stage, reason: r.reason_category, flags, unmapped: false };
  }
  return { stage: "new", reason: null, flags, unmapped: true };
}

/** The creator stage given the previous one (never backwards; see the header). */
export function mapStage(
  x: StageInputs,
  rules: readonly MappingRule[],
  previous: { stage: CreatorStage; reason: string | null } | null,
): StageResult {
  const next = evaluate(x, rules);
  if (!previous) return next;
  if (next.unmapped) return { ...next, stage: previous.stage, reason: previous.reason };
  const p = previous.stage;
  const n = next.stage;
  if (p === "enrolled" && n !== "enrolled") return { ...next, stage: "enrolled", reason: previous.reason };
  if (CLOSED_STAGES.includes(n)) return next;
  if (CLOSED_STAGES.includes(p)) return next; // a closed lead that came back
  if (RANK[n] < RANK[p]) return { ...next, stage: p, reason: previous.reason };
  return next;
}
