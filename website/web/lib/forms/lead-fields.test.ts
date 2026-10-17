import { describe, expect, it } from "vitest";
import { academicLead, preferencesLead, workLead } from "./lead-fields";

describe("lead field mapping (SCHEMA_PLAN §4.1)", () => {
  it("maps academic answers", () => {
    expect(academicLead({ qualification: "graduation", stream: "B.Com", scoreType: "percent", score: "72", currentlyStudying: false })).toEqual({
      highest_qualification: "Graduation — B.Com",
      academic_score_raw: "72%",
      academic_score_pct: 72,
    });
    expect(academicLead({ qualification: "12th", stream: "", scoreType: "cgpa", score: "8", currentlyStudying: true })).toEqual({
      highest_qualification: "Class 12",
      current_study: "Currently studying (Class 12)",
      academic_score_raw: "8 CGPA",
      academic_score_pct: 76,
    });
    expect(academicLead({})).toEqual({});
  });

  it("maps work answers", () => {
    expect(workLead({ working: "yes", years: "4", role: "Sales executive" }, "Career growth")).toEqual({
      work_experience_raw: "Working, 4 years",
      work_experience_years_num: 4,
      current_job_role: "Sales executive",
      primary_motivation: "Career growth",
    });
    expect(workLead({ working: "no", years: "", role: "ignored" })).toEqual({ work_experience_raw: "Not working", work_experience_years_num: 0 });
  });

  it("maps preferences, by budget label or value", () => {
    expect(
      preferencesLead({ intake: "Within 3 months", budget: "₹1–2 lakh", city: "Pune", state: "Maharashtra", contactMode: "whatsapp", bestTime: "Evening (4–8pm)" }, ["NMIMS", "Amity"]),
    ).toEqual({
      enrollment_timeline: "Within 3 months",
      annual_budget_raw: "₹1–2 lakh",
      annual_budget_inr: 200000,
      university_preference: "NMIMS, Amity",
      city: "Pune",
      state: "Maharashtra",
      location_raw: "Pune, Maharashtra",
      preferred_call_time: "WhatsApp, Evening (4–8pm)",
    });
    expect(preferencesLead({ budget: "not-sure", contactMode: "call" })).toEqual({ preferred_call_time: "Call" });
  });
});
