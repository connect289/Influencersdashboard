import { scoreToPercent, type AcademicInput, type PreferencesInput, type WorkInput } from "./validate";

/**
 * Maps the application form's answers onto the lead_intake `lead` keys (docs/SCHEMA_PLAN.md §4.1), so a form lead is as
 * sales-ready as a Witty lead. Answers with no lead column (year of passing, board, industry, why, EMI interest,
 * questions) stay in web_applications.steps only (A-LEAD-2). Pure; empty values are dropped.
 */
export const QUALIFICATION_LABELS: Record<string, string> = {
  "10th": "Class 10",
  "12th": "Class 12",
  diploma: "Diploma",
  graduation: "Graduation",
  postgraduation: "Post-graduation",
  doctorate: "Doctorate",
};

const clean = (o: Record<string, unknown>) =>
  Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined && v !== null && v !== ""));

export function academicLead(a: Partial<AcademicInput>): Record<string, unknown> {
  const q = a.qualification ? (QUALIFICATION_LABELS[a.qualification] ?? a.qualification) : undefined;
  const pct = a.scoreType && a.score ? scoreToPercent(a.scoreType, a.score) : null;
  return clean({
    highest_qualification: q ? (a.stream ? `${q} — ${a.stream.trim().slice(0, 80)}` : q) : undefined,
    current_study: a.currentlyStudying ? (q ? `Currently studying (${q})` : "Currently studying") : undefined,
    academic_score_raw: a.score ? `${a.score}${a.scoreType === "cgpa" ? " CGPA" : "%"}` : undefined,
    academic_score_pct: pct !== null && pct > 0 && pct <= 100 ? pct : undefined,
  });
}

export function workLead(w: Partial<WorkInput>, goalLabel?: string): Record<string, unknown> {
  const years = w.working === "yes" && w.years !== "" && w.years !== undefined ? Number(w.years) : null;
  return clean({
    work_experience_raw:
      w.working === "no" ? "Not working" : w.working === "yes" ? (years !== null ? `Working, ${years} years` : "Working") : undefined,
    work_experience_years_num: years !== null && Number.isFinite(years) ? years : w.working === "no" ? 0 : undefined,
    current_job_role: w.working === "yes" ? w.role?.trim().slice(0, 120) : undefined,
    primary_motivation: goalLabel,
  });
}

export const BUDGET_RANGES: { value: string; label: string; inr: number | null }[] = [
  { value: "under-1l", label: "Under ₹1 lakh", inr: 100000 },
  { value: "1-2l", label: "₹1–2 lakh", inr: 200000 },
  { value: "2-3l", label: "₹2–3 lakh", inr: 300000 },
  { value: "3-5l", label: "₹3–5 lakh", inr: 500000 },
  { value: "5l-plus", label: "Above ₹5 lakh", inr: null },
  { value: "not-sure", label: "Not sure yet", inr: null },
];

const MODE_LABEL = { call: "Call", whatsapp: "WhatsApp", email: "Email" } as const;

export function preferencesLead(p: Partial<PreferencesInput>, universityNames: string[] = []): Record<string, unknown> {
  const budget = BUDGET_RANGES.find((b) => b.value === p.budget || b.label === p.budget);
  const city = p.city?.trim().slice(0, 80);
  const state = p.state?.trim().slice(0, 80);
  const mode = p.contactMode ? MODE_LABEL[p.contactMode] : undefined;
  return clean({
    enrollment_timeline: p.intake?.trim().slice(0, 60),
    annual_budget_raw: budget && budget.value !== "not-sure" ? budget.label : undefined,
    annual_budget_inr: budget?.inr ?? undefined,
    university_preference: universityNames.length ? universityNames.join(", ").slice(0, 300) : undefined,
    city,
    state,
    location_raw: city || state ? [city, state].filter(Boolean).join(", ") : undefined,
    preferred_call_time: mode ? (p.bestTime?.trim() ? `${mode}, ${p.bestTime.trim().slice(0, 60)}` : mode) : undefined,
  });
}
