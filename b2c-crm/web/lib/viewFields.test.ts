import { describe, expect, it } from "vitest";
import { cellText, fieldsFor, fromGroups, LEAD_FIELDS, needsValue, OPS, toFilter, toGroups } from "./viewFields";

// The list b2c.lead_fields() returns (b40); every field must be described here.
const DB_FIELDS = ["lead_id", "name", "phone", "email", "city", "state", "language", "course", "specialization", "university", "programme_level", "study_mode",
  "qualification", "source", "campaign", "lead_status", "partner_consent_state", "marketing_consent", "opted_out", "lane", "status", "handoff_reason", "cause",
  "partner_bar_reason", "owner_id", "owner_name", "assigned_at", "stage_id", "stage", "canonical_stage", "sub_stage", "stage_changed_at", "hot", "temperature", "score",
  "next_task_due_at", "first_contacted_at", "last_contacted_at", "contact_attempts", "last_activity_at", "sla_due_at", "sla_met_at", "sla_breached_at",
  "pool_entered_at", "pool_reason", "journey", "lost_by", "reengaged_at", "flagged", "reenquired_at", "tags", "is_test", "handed_off_at", "updated_at", "closed_at",
  "created_at", "timeline", "budget", "work_experience", "partner", "partner_lost_reason", "partners_tried_count", "engagement_points", "fit_points",
  "calls_logged", "calls_connected", "last_call_outcome", "last_call_at", "wa_sent", "wa_received", "last_wa_in_at", "emails_sent", "emails_opened", "last_email_at",
  "last_reply_at", "last_reply_class", "days_in_stage", "days_untouched", "sla_status", "application_status", "application_ref", "documents_pending",
  "enrollment_status", "enrolled_on", "fee", "university_gross", "university_net", "university_gst", "university_status", "counsellor_commission"];

describe("view fields", () => {
  it("describes exactly the database's fields", () => {
    expect(LEAD_FIELDS.map((f) => f.field).sort()).toEqual([...DB_FIELDS].sort());
  });

  it("marks the money fields and hides them from Sales and from people without money rights", () => {
    expect(LEAD_FIELDS.filter((f) => f.money).map((f) => f.field).sort()).toEqual(["counsellor_commission", "university_gross", "university_gst", "university_net", "university_status"]);
    expect(fieldsFor("workspace", false).some((f) => f.money)).toBe(false);
    expect(fieldsFor("workspace", true).some((f) => f.field === "university_gross")).toBe(true);
    expect(fieldsFor("sales", false).some((f) => f.field === "owner_name" || f.field === "status")).toBe(false);
  });

  it("offers the relative date operators and knows which need a value", () => {
    expect(OPS.date.map(([k]) => k)).toEqual(expect.arrayContaining(["today", "this_week", "this_month", "last_month", "between", "within_days"]));
    expect(OPS.number.map(([k]) => k)).toEqual(expect.arrayContaining(["gt", "lt", "between"]));
    expect(needsValue("this_month")).toBe(false);
    expect(needsValue("between")).toBe(true);
  });

  it("sends conditions as the database wants them", () => {
    expect(toFilter({ field: "owner_id", op: "is_true" })).toEqual({ field: "owner_id", op: "is_null" });
    expect(toFilter({ field: "created_at", op: "this_month", value: "x" })).toEqual({ field: "created_at", op: "this_month" });
    expect(toFilter({ field: "created_at", op: "between", value: ["2026-10-01", "2026-10-15"] }))
      .toEqual({ field: "created_at", op: "between", value: ["2026-10-01T00:00:00+05:30", "2026-10-15T23:59:59.999+05:30"] });
    expect(toFilter({ field: "score", op: "between", value: ["10", "40"] })).toEqual({ field: "score", op: "between", value: [10, 40] });
    expect(toFilter({ field: "calls_logged", op: "gt", value: "2" })).toEqual({ field: "calls_logged", op: "gt", value: 2 });
    expect(toFilter({ field: "assigned_at", op: "within_days", value: "7" })).toEqual({ field: "assigned_at", op: "within_days", value: 7 });
    expect(toFilter({ field: "enrolled_on", op: "lte", value: "2026-10-31" })).toEqual({ field: "enrolled_on", op: "lte", value: "2026-10-31T23:59:59.999+05:30" });
  });

  it("turns groups into filters and back", () => {
    const one = fromGroups([{ mode: "all", conds: [{ field: "temperature", op: "eq", value: "hot" }] }]);
    expect(one).toEqual({ all: [{ field: "temperature", op: "eq", value: "hot" }] });
    const two = fromGroups([
      { mode: "all", conds: [{ field: "status", op: "eq", value: "active" }] },
      { mode: "any", conds: [{ field: "source", op: "contains", value: "meta" }, { field: "created_at", op: "between", value: ["2026-10-01", "2026-10-02"] }] },
      { mode: "any", conds: [] },
    ]);
    expect(two.groups).toHaveLength(2);
    expect(two.groups![1]!.any![1]!.value).toEqual(["2026-10-01T00:00:00+05:30", "2026-10-02T23:59:59.999+05:30"]);
    const back = toGroups(two);
    expect(back.map((g) => g.mode)).toEqual(["all", "any"]);
    expect(back[1]!.conds[1]!.value).toEqual(["2026-10-01", "2026-10-02"]);
    expect(toGroups({ all: [{ field: "owner_id", op: "is_null" }], any: [{ field: "hot", op: "is_true" }] }))
      .toEqual([{ mode: "all", conds: [{ field: "owner_id", op: "is_true" }] }, { mode: "any", conds: [{ field: "hot", op: "is_true" }] }]);
    expect(fromGroups([])).toEqual({});
  });

  it("renders cells by type", () => {
    const now = new Date("2026-10-15T06:00:00Z");
    expect(cellText("university_gross", 125000)).toBe("₹1,25,000");
    expect(cellText("opted_out", false)).toBe("No");
    expect(cellText("last_call_outcome", "no_answer")).toBe("No answer");
    expect(cellText("created_at", "2026-10-15T05:00:00Z", now)).toBe("Today 10:30");
    expect(cellText("tags", ["a", "b"])).toBe("a, b");
    expect(cellText("partner", null)).toBe("—");
  });
});
