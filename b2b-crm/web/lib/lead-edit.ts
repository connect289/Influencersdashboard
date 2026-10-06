import { z } from "zod";

/** Lead corrections (spec B6.1.3). The database (b2b.lead_edit) repeats every check; this gives instant field errors. */

export const EDIT_GROUPS = [
  { title: "Contact", fields: ["student_name", "email_id", "alternate_phone", "preferred_language", "city", "state", "guardian_name", "guardian_phone"] },
  { title: "Interest", fields: ["interested_course", "interested_specialization", "interested_university", "program_level", "study_mode_preference"] },
  { title: "Profile", fields: ["highest_qualification", "academic_score_pct", "work_experience_years_num", "annual_budget_inr", "enrollment_timeline"] },
  { title: "Classification and notes", fields: ["lead_status", "Comments"] },
] as const;

export type EditField = (typeof EDIT_GROUPS)[number]["fields"][number];
export const EDIT_FIELDS: EditField[] = EDIT_GROUPS.flatMap((g) => [...g.fields]);

export const FIELD_LABEL: Record<EditField, string> = {
  student_name: "Name",
  email_id: "Email",
  alternate_phone: "Alternate phone",
  preferred_language: "Language",
  city: "City",
  state: "State",
  guardian_name: "Guardian's name",
  guardian_phone: "Guardian's phone",
  interested_course: "Course",
  interested_specialization: "Specialisation",
  interested_university: "University",
  program_level: "Level",
  study_mode_preference: "Study mode",
  highest_qualification: "Highest qualification",
  academic_score_pct: "Score (%)",
  work_experience_years_num: "Work experience (years)",
  annual_budget_inr: "Budget (₹ a year)",
  enrollment_timeline: "Wants to start",
  lead_status: "Classification",
  Comments: "Notes",
};

export const CLASSIFICATIONS = ["HOT", "WARM", "COLD", "UNQUALIFIED", "JUNK", "PROGRAM_MISMATCH"] as const;

const text = z.string().trim().max(200, "At most 200 characters");
const phone = z.string().trim().refine((v) => v === "" || /^\+?[\d\s-]{10,18}$/.test(v), "Enter a phone number");
const num = (max: number, msg: string, whole = false) =>
  z.string().trim().refine((v) => v === "" || ((whole ? /^\d+$/ : /^\d+(\.\d{1,2})?$/).test(v) && Number(v) <= max), msg);

const FieldSchemas: Record<EditField, z.ZodType<string>> = {
  student_name: text,
  email_id: z.string().trim().toLowerCase().refine((v) => v === "" || /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/.test(v), "Enter an email address"),
  alternate_phone: phone,
  preferred_language: text,
  city: text,
  state: text,
  guardian_name: text,
  guardian_phone: phone,
  interested_course: text,
  interested_specialization: text,
  interested_university: text,
  program_level: text,
  study_mode_preference: text,
  highest_qualification: text,
  academic_score_pct: num(100, "A percentage from 0 to 100"),
  work_experience_years_num: num(50, "A number of years"),
  annual_budget_inr: num(999_999_999, "Whole rupees, digits only", true),
  enrollment_timeline: text,
  lead_status: z.string().trim().refine((v) => v === "" || (CLASSIFICATIONS as readonly string[]).includes(v), "Choose a classification"),
  Comments: z.string().trim().max(2000, "At most 2,000 characters"),
};

/** Only the fields whose value differs from the current one; emptying a filled field is refused (lead_intake cannot clear). */
export function parseEdit(form: Record<string, string>, current: Record<string, string | null>):
  { ok: true; changes: Partial<Record<EditField, string>> } | { ok: false; errors: Record<string, string> } {
  const errors: Record<string, string> = {};
  const changes: Partial<Record<EditField, string>> = {};
  for (const f of EDIT_FIELDS) {
    if (!(f in form)) continue;
    const r = FieldSchemas[f].safeParse(form[f] ?? "");
    if (!r.success) { errors[f] = r.error.issues[0]?.message ?? "Invalid"; continue; }
    const v = r.data;
    const was = current[f] ?? "";
    if (v === "") {
      if (was !== "") errors[f] = "Can't be emptied; correct it instead";
      continue;
    }
    const same = ["academic_score_pct", "work_experience_years_num", "annual_budget_inr"].includes(f) && was !== "" ? Number(v) === Number(was) : v === was;
    if (!same) changes[f] = v;
  }
  return Object.keys(errors).length ? { ok: false, errors } : { ok: true, changes };
}

export type EditHistory = {
  id: number; field: string; old: string | null; new: string; reason: string; at: string; current: string | null; overwritten: boolean; updated_by: string | null;
}[];
