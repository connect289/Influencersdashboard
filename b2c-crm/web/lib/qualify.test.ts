import { describe, expect, it } from "vitest";
import { cleanAnswers, DEFAULT_QUESTIONS, questionsFor } from "./qualify";

describe("qualification questions", () => {
  it("asks for what is missing, in order, once each", () => {
    expect(questionsFor(["programme of interest", "highest education", "programme", "when to start"])).toEqual(["course", "highest_qualification", "enrollment_timeline"]);
    expect(questionsFor(["email", "budget"])).toEqual(["email", "annual_budget_inr"]);
  });

  it("falls back to the default three", () => {
    expect(questionsFor([])).toEqual(DEFAULT_QUESTIONS);
    expect(questionsFor(null)).toEqual(DEFAULT_QUESTIONS);
    expect(questionsFor(["phone"])).toEqual(DEFAULT_QUESTIONS);
  });

  it("keeps known answers only, trimmed and short", () => {
    expect(cleanAnswers({ course: "  MBA ", email: "", hacker: "x", name: "a".repeat(300), study_mode: null })).toEqual({ course: "MBA", name: "a".repeat(200) });
  });
});
