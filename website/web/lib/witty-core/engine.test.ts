import { describe, expect, it } from "vitest";
import type { CatalogRow, SearchResult } from "./contract";
import { acceptFacts, classify, counselorInput, leadPayload, planTurn, searchQuery, type Extraction, type WittyState } from "./engine";

/** Scenario names follow Witty's harness (witty.md §8); the catalogue rows are fixtures shaped like w2_search_programs. */
const row = (id: number, university: string, spec: string, fee_yearly: number | null, min_pct = 50, min_q = "BACHELOR", extra: Partial<CatalogRow> = {}): CatalogRow => ({
  id, university, university_short: university.split(" ")[0], level: "PG", course: "MBA", specialization: spec, program_name: `MBA - ${spec}`, mode: "Online",
  fee_yearly, fee_semester: null, fee_total: fee_yearly ? fee_yearly * 2 : null, min_qualification: min_q, min_pct_general: min_pct, brochure_url: null, match: 1, uni_match: false, ...extra,
});
const MBA_ALL: CatalogRow[] = [
  row(1, "Alpha University", "Finance", 60000),
  row(2, "Beta University", "Finance", 45000, 55),
  row(3, "Gamma University", "Marketing", 50000),
  row(4, "Delta University", "Finance", 90000, 60),
  row(5, "Alpha University", "Marketing", 61000),
  row(6, "Epsilon University", "HR", 40000),
];
const search = (rows: CatalogRow[], o: Partial<SearchResult> = {}): SearchResult => ({
  rows, visible_total: rows.length, total_for_course: rows.length, specializations: ["Finance", "Marketing", "HR"], spec_matched: true, mode_matched: true, ...o,
});
const start = (): WittyState => ({ profile: { student_name: { value: "Rohit Sen", confirmed: true }, email_id: { value: "rohit@example.org", confirmed: true } } });
const ex = (facts: Extraction["facts"], intents: string[] = []): Extraction => ({ facts, intents });

function turn(state: WittyState, message: string, x: Extraction, rows: CatalogRow[] | null, more: Partial<Parameters<typeof planTurn>[0]> = {}) {
  const accepted = acceptFacts(state, x, message);
  const q = searchQuery(accepted.state.profile);
  const spec = q?.specialization?.toLowerCase();
  const res = q && rows ? search(spec ? rows.filter((r) => r.specialization!.toLowerCase() === spec) : rows) : null;
  return planTurn({ state: accepted.state, accepted, message, search: res, ...more });
}

describe("happy_path_mba", () => {
  it("asks before suggesting, shows eligible rows, then qualifies and escalates when ready now", () => {
    let s = start();
    const t1 = turn(s, "I want to do an MBA", ex([{ field: "interested_course", value: "MBA", evidence: "an MBA", op: "set", confidence: "HIGH" }, { field: "program_level", value: "PG", evidence: "MBA", confidence: "HIGH" }]), MBA_ALL);
    expect(t1.mode).toBe("DIRECTIONAL");
    expect(t1.ask).toBe("ASK_SPECIALIZATION");
    expect(t1.askText).toContain("Finance, Marketing, HR");
    expect(t1.facts.program_count).toBe(6);
    expect(t1.rows).toHaveLength(0); // no programme, university or fee yet
    expect(t1.state.phase).toBe("QUALIFY_IT");
    s = { ...t1.state, last_witty_message: "…" };

    const t2 = turn(s, "Finance please", ex([{ field: "specialization", value: "Finance", evidence: "Finance", confidence: "HIGH" }]), MBA_ALL);
    expect(t2.mode).toBe("DIRECTIONAL");
    expect(t2.ask).toBe("ASK_QUAL_AND_SCORE");
    s = t2.state;

    const t3 = turn(s, "B.Com, 58%", ex([{ field: "highest_qualification", value: "B.Com", evidence: "B.Com", confidence: "HIGH" }, { field: "academic_score", value: "58", evidence: "58%", scale: "percent", confidence: "HIGH" }]), MBA_ALL);
    expect(t3.mode).toBe("PROGRAMS");
    expect(t3.rows.map((r) => r.row.id)).toEqual([2, 1]); // Delta needs 60%: not shown; cheapest first
    expect(t3.ask).toBe("ASK_TIMELINE");
    expect(t3.state.eligibility).toBe("ELIGIBLE");
    expect(t3.state.classification).toBe("UNQUALIFIED"); // timeline unknown
    expect(t3.eventType).toBe("lead.updated");
    s = t3.state;

    const t4 = turn(s, "next session, around January", ex([{ field: "enrollment_timeline", value: "next session", evidence: "next session", confidence: "HIGH" }]), MBA_ALL);
    expect(t4.state.classification).toBe("WARM");
    expect(t4.eventType).toBe("lead.qualified");
    expect(t4.state.phase).toBe("ENRICH_IT");
    expect(t4.mode).toBe("ACK"); // rows already shown: no re-listing
    s = t4.state;

    const t5 = turn(s, "actually I want to join this month", ex([{ field: "enrollment_timeline", value: "this month", evidence: "join this month", op: "correct", confidence: "HIGH" }], ["wants_to_apply"]), MBA_ALL);
    expect(t5.mode).toBe("HANDOFF");
    expect(t5.fixedReply).toBe("Thank you Rohit. An academic counsellor will contact you shortly about MBA.");
    expect(t5.escalate).toBe(true);
    expect(t5.eventType).toBe("lead.escalated");
    expect(t5.state.classification).toBe("HOT");
    expect(t5.state.phase).toBe("ESCALATION");
  });
});

describe("hinglish_parent", () => {
  it("talks to the writer in Hinglish and keeps the student's facts", () => {
    const msg = "Namaste, main apne bhai Rohit ke liye pooch raha hoon, usne 12th commerce se 70% kiya hai aur BBA karna chahta hai";
    const t = turn(start(), msg, {
      facts: [
        { field: "highest_qualification", value: "12th", evidence: "12th commerce", subject: "sibling", confidence: "HIGH" },
        { field: "academic_score", value: "70", evidence: "70%", subject: "sibling", scale: "percent", confidence: "HIGH" },
        { field: "interested_course", value: "BBA", evidence: "BBA karna chahta hai", subject: "sibling", confidence: "HIGH" },
      ],
      enquirer: { name: null, relation: "sibling" },
      intents: [],
    }, [row(10, "Alpha University", "Finance", 40000, 45, "12TH", { course: "BBA", level: "UG" }), row(11, "Beta University", "Marketing", 38000, 50, "12TH", { course: "BBA", level: "UG" })]);
    expect(t.state.language).toBe("hinglish");
    expect(t.state.enquirer).toEqual({ name: null, relation: "sibling" });
    expect(t.mode).toBe("DIRECTIONAL");
    expect(t.askText).toMatch(/^Kya aapke mann mein koi specialization hai/);
    expect(counselorInput(t, [], msg).facts.writer).toEqual({ name: null, relation: "sibling" });
  });
});

describe("general_questions", () => {
  it("answers only from knowledge, then asks the next question", () => {
    const k = [{ ref: "K1", doc: "FAQ", text: "Online degrees from UGC-entitled universities are equivalent to regular degrees." }];
    const t = turn(start(), "Is an online MBA valid for government jobs?", ex([{ field: "interested_course", value: "MBA", evidence: "online MBA", confidence: "HIGH" }], ["general_question"]), MBA_ALL, { knowledge: k });
    expect(t.mode).toBe("ANSWER");
    expect(t.knowledge).toEqual(k);
    expect(t.ask).toBe("ASK_SPECIALIZATION");
    expect(counselorInput(t, [], "x").facts.knowledge).toEqual(k);
  });
  it("without a course yet, answers and asks for the course", () => {
    const t = turn(start(), "what is ODL?", ex([], ["general_question"]), null, { knowledge: [] });
    expect(t.mode).toBe("ANSWER");
    expect(t.ask).toBe("ASK_COURSE");
  });
});

describe("fee_check", () => {
  it("re-lists when fees are asked; budget marks options above it", () => {
    let s = start();
    s = turn(s, "MBA finance", ex([{ field: "interested_course", value: "MBA", evidence: "MBA", confidence: "HIGH" }, { field: "specialization", value: "Finance", evidence: "finance", confidence: "HIGH" }]), MBA_ALL).state;
    s = turn(s, "BCom 75%", ex([{ field: "highest_qualification", value: "BCom", evidence: "BCom", confidence: "HIGH" }, { field: "academic_score", value: "75", evidence: "75%", scale: "percent", confidence: "HIGH" }]), MBA_ALL).state;
    const t = turn(s, "budget 50k per year, fees kitni hai?", ex([{ field: "annual_budget", value: "50k", evidence: "budget 50k", confidence: "HIGH" }], ["asks_fees"]), MBA_ALL);
    expect(t.mode).toBe("PROGRAMS");
    expect(t.rows[0]!.row.id).toBe(2); // within budget first
    expect(t.facts.some_options_above_budget).toBe(true);
  });
});

describe("alternatives_and_complaints", () => {
  it("shows other specializations and never repeats the earlier rows", () => {
    let s = start();
    s = turn(s, "MBA marketing", ex([{ field: "interested_course", value: "MBA", evidence: "MBA", confidence: "HIGH" }, { field: "specialization", value: "Marketing", evidence: "marketing", confidence: "HIGH" }]), MBA_ALL).state;
    const t1 = turn(s, "graduation 65%", ex([{ field: "highest_qualification", value: "graduation", evidence: "graduation", confidence: "HIGH" }, { field: "academic_score", value: "65", evidence: "65%", scale: "percent", confidence: "HIGH" }]), MBA_ALL);
    expect(t1.rows.map((r) => r.row.specialization)).toEqual(["Marketing", "Marketing"]);
    const msg = "marketing nahi, kuch aur dikhao";
    const accepted = acceptFacts(t1.state, ex([{ field: "specialization", value: "marketing", evidence: "marketing nahi", op: "negate", confidence: "HIGH" }], ["wants_alternatives"]), msg);
    const t2 = planTurn({ state: accepted.state, accepted, message: msg, search: search(MBA_ALL), alternatives: search(MBA_ALL) });
    expect(t2.mode).toBe("PROGRAMS");
    expect(t2.facts.alternatives_to).toBe("Marketing");
    expect(t2.rows.every((r) => r.row.specialization !== "Marketing")).toBe(true);
    expect(t2.rows.some((r) => t1.rows.some((o) => o.row.id === r.row.id))).toBe(false);
  });
});

describe("eligibility and matches", () => {
  it("NOT_ELIGIBLE for a 12th pass asking for an MBA", () => {
    const t = turn(start(), "MBA karna hai, 12th pass hu", ex([{ field: "interested_course", value: "MBA", evidence: "MBA karna hai", confidence: "HIGH" }, { field: "highest_qualification", value: "12th", evidence: "12th pass", confidence: "HIGH" }, { field: "specialization", value: "Finance", evidence: "MBA", confidence: "HIGH" }]), MBA_ALL);
    expect(t.state.language).toBe("hinglish");
    // score unknown and qualification below the requirement: asks the score first, then NOT_ELIGIBLE once known
    const t2 = turn(t.state, "60%", ex([{ field: "academic_score", value: "60", evidence: "60%", scale: "percent", confidence: "HIGH" }]), MBA_ALL);
    expect(t2.mode).toBe("NOT_ELIGIBLE");
    expect(t2.state.eligibility).toBe("NOT_ELIGIBLE");
    expect(t2.askText).toBe("Kya aap koi aur course dekhna chahenge?");
  });
  it("NO_MATCH when the catalogue has no such course", () => {
    const accepted = acceptFacts(start(), ex([{ field: "interested_course", value: "B.Arch", evidence: "B.Arch", confidence: "HIGH" }]), "I want B.Arch");
    const t = planTurn({ state: accepted.state, accepted, message: "I want B.Arch", search: search([], { total_for_course: 0, visible_total: 0, specializations: [] }) });
    expect(t.mode).toBe("NO_MATCH");
    expect(t.state.eligibility).toBe("PROGRAM_MISMATCH");
    expect(t.state.classification).toBe("PROGRAM_MISMATCH");
  });
});

describe("hand-off, opt-out and fact rules", () => {
  it("asks_human hands off with the live fixed text", () => {
    const t = turn(start(), "can I talk to a counsellor?", ex([], ["asks_human"]), null);
    expect(t.mode).toBe("HANDOFF");
    expect(t.fixedReply).toBe("Thank you Rohit. An academic counsellor will contact you shortly about your programme.");
    expect(t.eventType).toBe("lead.escalated");
  });
  it("accepting the counsellor offer hands off", () => {
    const s: WittyState = { ...start(), pending_question: "OFFER_HANDOFF", profile: { ...start().profile, interested_course: { value: "MBA", confirmed: true } } };
    expect(turn(s, "haan please", ex([]), MBA_ALL).mode).toBe("HANDOFF");
  });
  it("erasure requests route to the opt-out flow; stop opts out", () => {
    const e = turn(start(), "delete my data", ex([], ["erasure_request"]), null);
    expect(e.route).toBe("opt_out");
    expect(e.fixedReply).toContain("Delete my data");
    const st = turn(start(), "stop", ex([], ["stop"]), null);
    expect(st.state.flags?.opted_out).toBe(true);
    expect(leadPayload(st.state, ["stop"]).is_opted_out).toBe(true);
  });
  it("rejects facts without exact evidence and never overwrites the verified email", () => {
    const r = acceptFacts(start(), ex([{ field: "interested_course", value: "MBA", evidence: "masters in business", confidence: "HIGH" }, { field: "email_id", value: "x@y.com", evidence: "x@y.com", confidence: "HIGH" }]), "send to x@y.com");
    expect(r.rejected.map((x) => x.reason)).toEqual(["evidence_not_in_message", "verified_on_web"]);
    expect(r.state.profile.email_id?.value).toBe("rohit@example.org");
  });
  it("LOW confidence becomes unsure and is confirmed before use", () => {
    const t = turn(start(), "BBA ya BCOM, dono theek hain", ex([{ field: "interested_course", value: "BBA", evidence: "BBA ya BCOM", op: "unsure", confidence: "LOW" }]), MBA_ALL);
    expect(t.ask).toBe("CONFIRM_COURSE");
    expect(t.askText).toContain("BBA");
  });
  it("chosen_program resolves against the rows shown", () => {
    const s: WittyState = { ...start(), flags: { shown_rows: [2, 1], shown_names: { "2": "Beta", "1": "Alpha" } } };
    expect(acceptFacts(s, ex([{ field: "chosen_program", value: "the second one", evidence: "the second one", confidence: "HIGH" }]), "the second one").state.flags?.final_program_id).toBe(1);
    expect(acceptFacts(s, ex([{ field: "chosen_program", value: "Beta wala", evidence: "Beta wala", confidence: "HIGH" }]), "Beta wala").state.flags?.final_program_id).toBe(2);
  });
});

describe("classification table (witty.md §4.4)", () => {
  const full = { student_name: { value: "A" }, email_id: { value: "a@b.c" }, interested_course: { value: "MBA" } };
  it.each([
    ["ELIGIBLE", "READY_NOW", true, "HOT"],
    ["ELIGIBLE", "PLANNING", true, "WARM"],
    ["ELIGIBLE", "EXPLORING", true, "COLD"],
    ["ELIGIBLE", "EXPLORING", false, "UNQUALIFIED"],
    ["LIKELY_ELIGIBLE", "READY_NOW", true, "UNQUALIFIED"],
    ["PROGRAM_MISMATCH", "READY_NOW", true, "PROGRAM_MISMATCH"],
  ] as const)("%s + %s (timeline known %s) → %s", (e, r, k, c) => {
    expect(classify(full, e, r, k)).toBe(c);
  });
  it("is unqualified without the course", () => {
    expect(classify({ student_name: { value: "A" }, email_id: { value: "a@b.c" } }, "ELIGIBLE", "READY_NOW", true)).toBe("UNQUALIFIED");
  });
});

describe("lead payload (w2_crm_payload keys)", () => {
  it("maps the profile to lead_intake keys only", () => {
    const s: WittyState = {
      ...start(),
      language: "english",
      classification: "WARM",
      readiness: "PLANNING",
      eligibility: "ELIGIBLE",
      phase: "ENRICH_IT",
      profile: {
        ...start().profile,
        interested_course: { value: "MBA", confirmed: true },
        academic_score: { value: "7.8", scale: "cgpa10" },
        annual_budget: { value: "1-1.5 lakh" },
        work_experience_years: { value: "4" },
      },
    };
    const l = leadPayload(s, ["asks_fees"]);
    expect(l).toMatchObject({
      full_name: "Rohit Sen",
      interested_course: "MBA",
      academic_score_raw: "7.8",
      academic_score_pct: 74.1,
      annual_budget_inr: 150000,
      work_experience_years_num: 4,
      classification: "WARM",
      classification_ai: "WARM",
      conversation_phase: "ENRICH_IT",
      last_intent: "asks_fees",
      preferred_language: "english",
    });
    const allowed = new Set(["full_name", "is_name_confirmed", "email", "is_email_confirmed", "interested_course", "interested_specialization", "field_of_interest", "university_preference", "interested_university", "programme_level", "study_mode_preference", "highest_qualification", "current_study", "academic_score_raw", "academic_score_pct", "work_experience_raw", "work_experience_years_num", "current_job_role", "annual_budget_raw", "annual_budget_inr", "enrollment_timeline", "primary_motivation", "location_raw", "preferred_language", "enquirer_relation", "guardian_name", "classification", "classification_ai", "readiness", "eligibility", "conversation_phase", "last_intent", "is_opted_out"]);
    expect(Object.keys(l).every((k) => allowed.has(k))).toBe(true);
  });
});
