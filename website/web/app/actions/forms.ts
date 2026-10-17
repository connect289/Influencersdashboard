"use server";

import { z } from "zod";
import { academicLead, preferencesLead, workLead } from "@/lib/forms/lead-fields";
import { validateAcademic, validatePreferences, validateWork, type AcademicInput, type PreferencesInput, type WorkInput } from "@/lib/forms/validate";
import { rpc } from "@/lib/server/db";
import { resendCode, startVerification, verifyCode, type StartInput, type StartOutcome, type VerifyOutcome } from "@/lib/server/gate";
import { errorFields, log } from "@/lib/server/log";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { requestContext } from "@/lib/server/request";
import { offeringCards } from "@/lib/server/search";
import { currentStudent } from "@/lib/server/student-session";

/**
 * Server actions behind the application form, the enquiry form and the Witty gate (spec 9.1A, 9.1, 7.2). Every input
 * is re-validated here; the browser never decides what reaches lead_intake.
 */
const contextSchema = z
  .object({
    offering_id: z.number().int().positive().optional(),
    group_key: z.string().max(200).optional(),
    university_slug: z.string().max(120).optional(),
    programme_label: z.string().max(200).optional(),
    creator_handle: z.string().max(60).optional(),
  })
  .strict();

const startSchema = z.object({
  surface: z.enum(["gate", "application", "enquiry", "signin"]),
  context: contextSchema.optional(),
  name: z.string().max(120).optional(),
  phone: z.string().max(20).optional(),
  email: z.string().max(254),
  consentVersion: z.string().max(60).optional(),
  marketing: z.boolean().optional(),
  turnstileToken: z.string().max(4096).optional(),
  website: z.string().max(200).optional(),
  idempotencyKey: z.string().max(80),
});

export async function startFormAction(input: StartInput): Promise<StartOutcome> {
  const p = startSchema.safeParse(input);
  if (!p.success) return { status: "error", reason: "invalid_input", message: "Please check your details and try again." };
  return startVerification(p.data);
}

export async function resendCodeAction(attemptId: string): Promise<StartOutcome> {
  return resendCode(String(attemptId).slice(0, 40));
}

export async function verifyCodeAction(attemptId: string, code: string): Promise<VerifyOutcome> {
  return verifyCode(String(attemptId).slice(0, 40), String(code).slice(0, 6));
}

const str = (max: number) => z.string().max(max).default("");
const academicSchema = z.object({
  qualification: str(40),
  stream: str(120),
  scoreType: z.enum(["percent", "cgpa"]).default("percent"),
  score: str(10),
  currentlyStudying: z.boolean().default(false),
  yearOfPassing: str(6),
  board: str(160),
});
const workSchema = z.object({
  working: z.enum(["yes", "no", ""]).default(""),
  years: str(4),
  role: str(160),
  industry: str(160),
  goal: str(80),
  goalLabel: str(80).optional(),
  why: str(1000),
});
const prefsSchema = z.object({
  intake: str(60),
  budget: str(60),
  emi: z.enum(["yes", "no", ""]).default(""),
  universities: z.array(z.string().max(20)).max(10).default([]),
  city: str(80),
  state: str(80),
  contactMode: z.enum(["call", "whatsapp", "email", ""]).default(""),
  bestTime: str(60),
  questions: str(1000),
});

async function universityNames(ids: string[]): Promise<{ ids: number[]; names: string[] }> {
  const nums = ids.map(Number).filter((n) => Number.isInteger(n) && n > 0);
  if (!nums.length) return { ids: [], names: [] };
  const cards = await offeringCards(nums).catch(() => []);
  return { ids: cards.map((c) => c.id), names: [...new Set(cards.map((c) => c.university.name))] };
}

type StepResult = { ok: true } | { ok: false; message: string };

/** Steps 2–4 of the application form: stored on the application and enriching the same lead (spec 9.1A). */
export async function saveStepAction(attemptId: string, step: number, data: Record<string, unknown>): Promise<StepResult> {
  const student = await currentStudent();
  if (!student) return { ok: false, message: "Your session has ended. Please verify your email again." };
  const { ip, requestId } = await requestContext();
  if (!(await rateLimit(LIMITS.formSubmitPerIp, ip)).ok) return { ok: false, message: "Too many attempts. Please wait a few minutes." };
  let stored: Record<string, unknown>;
  let lead: Record<string, unknown>;
  let extra: Record<string, unknown> = {};
  if (step === 2) {
    const a = academicSchema.safeParse(data);
    if (!a.success || Object.keys(validateAcademic(a.data as AcademicInput)).length) return { ok: false, message: "Please check your academic details." };
    stored = a.data;
    lead = academicLead(a.data as AcademicInput);
  } else if (step === 3) {
    const w = workSchema.safeParse(data);
    if (!w.success || Object.keys(validateWork(w.data as WorkInput)).length) return { ok: false, message: "Please check your work details." };
    stored = w.data;
    lead = workLead(w.data as WorkInput, w.data.goal ? w.data.goalLabel || w.data.goal : undefined);
  } else if (step === 4) {
    const pr = prefsSchema.safeParse(data);
    if (!pr.success || Object.keys(validatePreferences(pr.data as PreferencesInput, false)).length)
      return { ok: false, message: "Please check your preferences." };
    const unis = await universityNames(pr.data.universities);
    stored = pr.data;
    lead = preferencesLead(pr.data as PreferencesInput, unis.names);
    extra = { preferred_offering_ids: unis.ids };
  } else {
    return { ok: false, message: "Unknown step." };
  }
  try {
    const r = await rpc<{ ok: boolean; reason?: string }>("web_application_save_step", {
      p: { attempt_id: attemptId, student_id: student.studentId, step, data: stored, lead, ...extra },
    });
    if (!r.ok) return { ok: false, message: "We couldn't find your application. Please start again." };
    return { ok: true };
  } catch (e) {
    log("error", "form.save_step_failed", { step, requestId, ...errorFields(e) });
    return { ok: false, message: "We couldn't save this step. Please try again." };
  }
}

const submitSchema = z
  .object({
    programme: str(200).optional(),
    message: str(1500).optional(),
  })
  .passthrough();

/** Final submit: application request (or enquiry), confirmation email and SubmitApplication via the outbox. */
export async function submitFormAction(
  attemptId: string,
  data: Record<string, unknown>,
): Promise<{ ok: true; reference: string } | { ok: false; message: string }> {
  const student = await currentStudent();
  if (!student) return { ok: false, message: "Your session has ended. Please verify your email again." };
  const { requestId } = await requestContext();
  const d = submitSchema.safeParse(data);
  if (!d.success) return { ok: false, message: "Please check your details." };
  const lead: Record<string, unknown> = {};
  if (d.data.programme) lead.interested_course = d.data.programme;
  // Store only the enquiry's own fields; the application's steps are already saved step by step.
  const final = { programme: d.data.programme || undefined, message: d.data.message || undefined };
  try {
    const r = await rpc<{ ok: boolean; reason?: string; reference?: string }>("web_application_submit", {
      p: { attempt_id: attemptId, student_id: student.studentId, data: final, lead },
    });
    if (!r.ok || !r.reference) return { ok: false, message: "We couldn't find your application. Please start again." };
    log("info", "form.submitted", { requestId });
    return { ok: true, reference: r.reference };
  } catch (e) {
    log("error", "form.submit_failed", { requestId, ...errorFields(e) });
    return { ok: false, message: "We couldn't submit just now. Please try again." };
  }
}
