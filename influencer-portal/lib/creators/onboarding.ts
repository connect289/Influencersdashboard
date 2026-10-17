import { z } from "zod";

export const ONBOARDING_STEPS = ["profile", "platforms", "kyc", "terms", "course"] as const;
export type OnboardingStep = (typeof ONBOARDING_STEPS)[number];
export const WIZARD_STEPS = [...ONBOARDING_STEPS, "submit"] as const;
export type WizardStep = (typeof WIZARD_STEPS)[number];

export const onboardingState = z.object({
  creator_id: z.uuid(),
  status: z.string(),
  approved: z.boolean(),
  submitted_at: z.string().nullable(),
  step: z.string(),
  steps: z.object({
    profile: z.boolean(),
    platforms: z.boolean(),
    kyc: z.boolean(),
    terms: z.boolean(),
    course: z.boolean(),
  }),
  kyc_status: z.string(),
  kyc_required: z.boolean(),
  complete: z.boolean(),
});
export type OnboardingState = z.infer<typeof onboardingState>;

/** The step to open: the requested one if valid, else the first unfinished one, else submit. */
export function currentStep(state: OnboardingState, requested: string | undefined): WizardStep {
  if (requested && (WIZARD_STEPS as readonly string[]).includes(requested)) return requested as WizardStep;
  return ONBOARDING_STEPS.find((s) => !state.steps[s]) ?? "submit";
}

export function progressPct(state: OnboardingState): number {
  const done = ONBOARDING_STEPS.filter((s) => state.steps[s]).length;
  return Math.round((done / ONBOARDING_STEPS.length) * 100);
}
