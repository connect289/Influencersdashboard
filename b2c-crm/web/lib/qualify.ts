// The qualification questions (spec B6.3, b39): the public form /q/<token> and the counsellor's "Collect the missing
// details" form. b2c.qualify_apply accepts these keys only. Unit-tested in qualify.test.ts.

export type QuestionKey = "course" | "highest_qualification" | "enrollment_timeline" | "name" | "email" | "annual_budget_inr" | "specialization" | "study_mode";
export type Question = { key: QuestionKey; label: string; staffLabel: string; type: "text" | "email" | "select"; options?: [string, string][]; placeholder?: string; suggest?: string[] };

export const QUESTIONS: Record<QuestionKey, Question> = {
  course: { key: "course", label: "Which programme are you interested in?", staffLabel: "Programme", type: "text", placeholder: "For example MBA, BCA, B.Com",
    suggest: ["MBA", "Executive MBA", "BBA", "MCA", "BCA", "B.Com", "M.Com", "BA", "MA", "B.Sc", "M.Sc", "Diploma", "PhD"] },
  highest_qualification: { key: "highest_qualification", label: "What is your highest qualification?", staffLabel: "Highest qualification", type: "select",
    options: [["10th", "10th"], ["12th", "12th"], ["Diploma", "Diploma"], ["Bachelor's degree", "Bachelor's degree"], ["Master's degree", "Master's degree"], ["Doctorate", "Doctorate"]] },
  enrollment_timeline: { key: "enrollment_timeline", label: "When would you like to start?", staffLabel: "When they want to start", type: "select",
    options: [["Immediately", "As soon as possible"], ["Within 3 months", "Within 3 months"], ["In 3 to 6 months", "In 3 to 6 months"], ["Next year", "Next year"], ["Not sure yet", "Not sure yet"]] },
  name: { key: "name", label: "Your name", staffLabel: "Name", type: "text" },
  email: { key: "email", label: "Your email", staffLabel: "Email", type: "email", placeholder: "name@example.com" },
  annual_budget_inr: { key: "annual_budget_inr", label: "About how much can you spend a year on fees?", staffLabel: "Budget a year", type: "select",
    options: [["30000", "Under ₹50,000"], ["75000", "₹50,000 to ₹1 lakh"], ["150000", "₹1 to 2 lakh"], ["250000", "Over ₹2 lakh"]] },
  specialization: { key: "specialization", label: "Any specialization in mind?", staffLabel: "Specialization", type: "text" },
  study_mode: { key: "study_mode", label: "How would you like to study?", staffLabel: "Study mode", type: "select", options: [["Online", "Online"], ["Distance", "Distance"], ["Regular", "Regular (on campus)"]] },
};

export const DEFAULT_QUESTIONS: QuestionKey[] = ["course", "highest_qualification", "enrollment_timeline"];
const KEYS = Object.keys(QUESTIONS) as QuestionKey[];
export const isQuestion = (k: string): k is QuestionKey => (KEYS as string[]).includes(k);

/** The questions for a lead's missing details, in the order missing, as b2c.qualify_questions picks them; else the default three. */
export function questionsFor(missing: string[] | null | undefined): QuestionKey[] {
  const out: QuestionKey[] = [];
  for (const m of missing ?? []) {
    const q: QuestionKey | null = /course|programme|program/i.test(m) ? "course" : /qualif|education/i.test(m) ? "highest_qualification"
      : /timeline|start|when/i.test(m) ? "enrollment_timeline" : /name/i.test(m) ? "name" : /email/i.test(m) ? "email" : /budget/i.test(m) ? "annual_budget_inr" : null;
    if (q && !out.includes(q)) out.push(q);
  }
  return out.length ? out : [...DEFAULT_QUESTIONS];
}

/** The answers worth sending: known keys, trimmed, at most 200 characters, blanks left out. */
export function cleanAnswers(raw: Record<string, unknown>): Partial<Record<QuestionKey, string>> {
  const out: Partial<Record<QuestionKey, string>> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (!isQuestion(k)) continue;
    const s = String(v ?? "").trim().slice(0, 200);
    if (s) out[k] = s;
  }
  return out;
}
