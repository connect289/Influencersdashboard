import { describe, expect, it } from "vitest";
import type { CatalogRow } from "./contract";
import { budgetToInr, qualificationRank, readinessFromTimeline, scoreToPct } from "./normalise";
import { fillPlaceholders, hasFields } from "./placeholders";
import { detectLanguage } from "./language";
import { fallbackReply, verifyReply, type VerifyInput } from "./verifier";

const r1: CatalogRow = { id: 1, university: "Deen Dayal Upadhyay Gorakhpur University", university_short: "DDU", program_name: "Master of Business Administration- Marketing", mode: "ODL", fee_yearly: 21000, fee_semester: 11000, fee_total: 42500, min_pct_general: 50, specialization: "Marketing" };
const r2: CatalogRow = { id: 2, university: "Amity University", program_name: "MBA Finance", mode: "Online", fee_yearly: null, fee_semester: null, fee_total: null };
const rows = [{ ref: "P1", row: r1 }, { ref: "P2", row: r2 }];
const base: VerifyInput = {
  reply: "",
  mode: "PROGRAMS",
  askText: "When are you hoping to start: this session or later?",
  maxWords: 120,
  studentMessage: "Finance please",
  programCount: 12,
  rows,
  universityNames: ["Deen Dayal Upadhyay Gorakhpur University", "DDU", "Amity University", "Amity"],
  mayPromiseCallback: false,
};

describe("verifier", () => {
  it("passes a reply shaped like the prompt's own example", () => {
    const reply = "Here are options you qualify for:\n\n• {{P1.program}} – {{P1.university}} ({{P1.mode}}), {{P1.fee}}\n• {{P2.program}} – {{P2.university}} ({{P2.mode}}), fee on request\n\nWhen are you hoping to start: this session or later?";
    expect(verifyReply({ ...base, reply })).toEqual([]);
  });
  it("catches typed fees, universities, numbers, promises, extra questions, bad placeholders", () => {
    expect(verifyReply({ ...base, reply: "Amity has an MBA for ₹1.2 lakh. {{P1.program}}" })).toEqual(expect.arrayContaining(["typed_university", "typed_fee", "unsourced_number"]));
    expect(verifyReply({ ...base, reply: "You will definitely get a placement. {{P1.program}}" })).toContain("promise");
    expect(verifyReply({ ...base, reply: "A counsellor will call you soon. {{P1.program}}" })).toContain("callback_promise");
    expect(verifyReply({ ...base, reply: "{{P1.program}} Which one? And when?" })).toContain("multiple_questions");
    expect(verifyReply({ ...base, reply: "{{P2.fee}} and {{P3.program}}" })).toContain("bad_placeholder");
    expect(verifyReply({ ...base, mode: "ACK", reply: "Noted. Let me check other options for you." })).toContain("promise_later");
    expect(verifyReply({ ...base, mode: "ANSWER", askText: "", reply: "Yes, it is UGC approved and valid." })).toContain("unsourced_claim");
    expect(verifyReply({ ...base, mode: "DIRECTIONAL", reply: "We have 12 options. {{P1.program}}" })).toContain("rows_in_wrong_mode");
  });
  it("allows the program count, the student's own numbers and knowledge numbers", () => {
    expect(verifyReply({ ...base, mode: "DIRECTIONAL", studentMessage: "I got 72%", reply: "Thanks! With 72% we have 12 MBA options. When are you hoping to start: this session or later?" })).toEqual([]);
  });
  it("fallback lists rows with placeholders and the ask", () => {
    const f = fallbackReply("PROGRAMS", base.askText, rows, "english");
    expect(f).toContain("{{P1.fee}}");
    expect(f).toContain("fee on request");
    expect(fillPlaceholders(f, rows)).toContain("₹21,000 per year");
  });
});

describe("placeholders", () => {
  it("fills from catalogue rows and lists available fields", () => {
    expect(fillPlaceholders("{{P1.program}} – {{P1.university}} ({{P1.mode}}), {{P1.fee}}; min {{P1.min_pct}}", rows)).toBe(
      "Master of Business Administration- Marketing – Deen Dayal Upadhyay Gorakhpur University (ODL), ₹21,000 per year; min 50%",
    );
    expect(hasFields(r2)).toEqual(["program", "university", "mode"]);
  });
});

describe("normalise and language", () => {
  it.each([
    ["72", "percent", 72],
    ["7.8", "cgpa10", 74.1],
    ["3.4", "gpa4", 85],
    ["58 or 59", "percent", 59],
    ["3.4", "unknown", null],
  ] as const)("score %s (%s) → %s", (raw, scale, pct) => expect(scoreToPct(raw, scale)).toBe(pct));
  it.each([
    ["1.5 lakh", 150000],
    ["1 se 1.5 lakh saal ka", 150000],
    ["50-60k", 60000],
    ["₹80,000", 80000],
    ["2L", 200000],
  ])("budget %s → %s", (raw, inr) => expect(budgetToInr(raw)).toBe(inr));
  it.each([
    ["12th", 2],
    ["B.Com", 3],
    ["BA", 3],
    ["MA English", 4],
    ["Diploma", 2],
    ["Matric", 1],
    ["Graduation", 3],
    ["Post-graduation", 4],
  ])("qualification %s → rank %s", (raw, rank) => expect(qualificationRank(raw)).toBe(rank));
  it("readiness from the timeline", () => {
    expect(readinessFromTimeline("this month")).toBe("READY_NOW");
    expect(readinessFromTimeline("isi mahine admission lena hai")).toBe("READY_NOW");
    expect(readinessFromTimeline("next session")).toBe("PLANNING");
    expect(readinessFromTimeline("just exploring")).toBe("EXPLORING");
  });
  it("language follows the student", () => {
    expect(detectLanguage("I want to do an MBA in finance")).toBe("english");
    expect(detectLanguage("mujhe MBA karna hai")).toBe("hinglish");
    expect(detectLanguage("मुझे एमबीए करना है")).toBe("hindi");
    expect(detectLanguage("ok", "hinglish")).toBe("hinglish");
  });
});
