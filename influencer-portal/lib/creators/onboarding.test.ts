import { describe, expect, it } from "vitest";
import { currentStep, progressPct, type OnboardingState } from "./onboarding";

const base: OnboardingState = {
  creator_id: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  status: "onboarding",
  approved: false,
  submitted_at: null,
  step: "profile",
  steps: { profile: true, platforms: true, kyc: false, terms: false, course: false },
  kyc_status: "pending",
  kyc_required: true,
  complete: false,
};

describe("onboarding wizard", () => {
  it("opens the first unfinished step", () => {
    expect(currentStep(base, undefined)).toBe("kyc");
  });
  it("honours a valid requested step and ignores an invalid one", () => {
    expect(currentStep(base, "profile")).toBe("profile");
    expect(currentStep(base, "admin")).toBe("kyc");
  });
  it("goes to submit when everything is done, and reports progress", () => {
    const all = {
      ...base,
      steps: { profile: true, platforms: true, kyc: true, terms: true, course: true },
    };
    expect(currentStep(all, undefined)).toBe("submit");
    expect(progressPct(base)).toBe(40);
    expect(progressPct(all)).toBe(100);
  });
});
