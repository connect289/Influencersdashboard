"use server";

import { z } from "zod";
import { rpc } from "@/lib/server/db";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { getSettings } from "@/lib/server/settings";
import { currentStudent } from "@/lib/server/student-session";
import { breakerOpen } from "@/lib/server/web-advisor/breaker";
import { openSession } from "@/lib/server/web-advisor/turn";

/** Chat helpers for Witty on the website (spec 7.4): bootstrap and history, restart, feedback, "Book a callback". */
export interface WittyMessage {
  id: number;
  role: "student" | "witty";
  text: string;
  chips?: string[];
  rating?: number | null;
  rows?: number[];
}
export interface WittyBootstrap {
  enabled: boolean;
  degraded: boolean;
  signedIn: boolean;
  firstName: string | null;
  messages: WittyMessage[];
}

export async function wittyBootstrapAction(fresh = false): Promise<WittyBootstrap> {
  const settings = await getSettings();
  const degraded = await breakerOpen();
  const student = await currentStudent();
  if (!settings.web_advisor_enabled || !student) {
    return { enabled: settings.web_advisor_enabled, degraded, signedIn: !!student, firstName: student?.name?.split(" ")[0] ?? null, messages: [] };
  }
  if (fresh && !(await rateLimit(LIMITS.savePerStudent, `fresh:${student.studentId}`)).ok) fresh = false;
  const s = await openSession(student, fresh);
  const messages: WittyMessage[] = (s?.messages ?? []).map((m) => ({
    id: m.id,
    role: m.direction === "in" ? "student" : "witty",
    text: m.content,
    chips: (m.meta?.chips as string[] | undefined) ?? undefined,
    rating: m.rating,
    rows: (m.meta?.rows as number[] | undefined) ?? undefined,
  }));
  return { enabled: true, degraded, signedIn: true, firstName: student.name?.split(" ")[0] ?? null, messages };
}

export async function wittyFeedbackAction(messageId: number, rating: 1 | -1): Promise<boolean> {
  const student = await currentStudent();
  if (!student || !Number.isInteger(messageId) || (rating !== 1 && rating !== -1)) return false;
  return rpc<boolean>("web_advisor_feedback_add", { p_student: student.studentId, p_message: messageId, p_rating: rating, p_comment: null });
}

const callbackSchema = z.object({ date: z.iso.date(), slot: z.enum(["morning", "afternoon", "evening"]) });

export async function wittyCallbackAction(input: { date: string; slot: string }): Promise<{ ok: boolean; label?: string; message?: string }> {
  const student = await currentStudent();
  if (!student) return { ok: false, message: "Please verify your email first." };
  const p = callbackSchema.safeParse(input);
  if (!p.success) return { ok: false, message: "Pick a day and a time." };
  // Each request updates the shared lead through lead_intake, so it is capped per student (and once per day and slot
  // in the database).
  if (!(await rateLimit(LIMITS.callbackPerStudent, String(student.studentId))).ok)
    return { ok: false, message: "You've already asked for a callback. Our counsellor will call you; for anything urgent, use WhatsApp." };
  const s = await openSession(student);
  const r = await rpc<{ ok: boolean; label?: string; reason?: string }>("web_callback_request", {
    p_student: student.studentId,
    p_session: s?.session.id ?? null,
    p_date: p.data.date,
    p_slot: p.data.slot,
  });
  if (r.ok) return { ok: true, label: r.label };
  const message =
    r.reason === "bad_date"
      ? "Pick a day in the next two weeks."
      : r.reason === "too_many"
        ? "You've already asked for a callback. Our counsellor will call you; for anything urgent, use WhatsApp."
        : "We couldn't book that. Please try WhatsApp.";
  return { ok: false, message };
}
