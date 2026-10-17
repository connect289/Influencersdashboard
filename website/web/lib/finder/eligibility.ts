/**
 * Eligibility marking (spec 6.2). Mirrors public.web_eligibility() exactly; both are tested against the same table
 * (lib/finder/eligibility.test.ts and supabase/tests/30_web_taxonomy.test.sql).
 */
import type { Eligibility } from "@/lib/search/types";

export type Qualification = "10th" | "12th" | "diploma" | "graduation" | "postgraduation";

const USER_RANK: Record<Qualification, number> = { "10th": 1, "12th": 2, diploma: 2, graduation: 3, postgraduation: 4 };
const REQ_RANK: Record<string, number> = { "12TH": 2, DIPLOMA: 2, BACHELOR: 3, MASTER: 4 };

export function eligibility(qual: Qualification | undefined, level: string, minQualification: string | null | undefined): Eligibility | null {
  if (!qual) return null;
  if (!minQualification) return "check";
  if (qual === "diploma" && minQualification === "DIPLOMA") return "eligible";
  if (qual === "diploma" && minQualification === "12TH") return "check";
  if (USER_RANK[qual] >= (REQ_RANK[minQualification] ?? 9)) return "eligible";
  // UG rows that say a bachelor's degree is required contradict themselves: never "not eligible".
  if (level === "ug" && (minQualification === "BACHELOR" || minQualification === "MASTER")) return "check";
  return "not_eligible";
}

export const ELIGIBILITY_LABEL: Record<Eligibility, string> = {
  eligible: "Eligible",
  check: "Check eligibility",
  not_eligible: "Not eligible",
};

export const QUALIFICATION_LABEL: Record<Qualification, string> = {
  "10th": "Class 10",
  "12th": "Class 12",
  diploma: "Diploma",
  graduation: "Graduation",
  postgraduation: "Post-graduation",
};

export const MIN_QUALIFICATION_LABEL: Record<string, string> = {
  "12TH": "Class 12",
  DIPLOMA: "Diploma",
  BACHELOR: "Bachelor's degree",
  MASTER: "Master's degree",
};
