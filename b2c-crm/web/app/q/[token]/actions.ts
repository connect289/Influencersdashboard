"use server";
import { headers } from "next/headers";
import { cleanAnswers } from "@/lib/qualify";
import { rateCheck } from "@/lib/rate-limit";
import { adminClient } from "@/lib/supabase/admin";

/** The student's answers from the public form: the token is the only credential and names one open request (b2c.qualify_submit). */
export async function qualifySubmit(token: string, answers: Record<string, string>): Promise<{ ok: boolean; error?: string }> {
  const limited = await rateCheck("q:submit", await headers(), "qualify_submit");
  if (!limited.ok) return { ok: false, error: `Too many tries. Please wait ${limited.retryAfter} seconds and try again.` };
  if (!/^[0-9a-f]{64}$/.test(token)) return { ok: false, error: "This link is not valid." };
  const clean = cleanAnswers(answers);
  if (Object.keys(clean).length === 0) return { ok: false, error: "Please answer at least one question." };
  const { error } = await adminClient().rpc("qualify_submit", { p_token: token, p_answers: clean });
  if (!error) return { ok: true };
  if (/no longer open/i.test(error.message)) return { ok: false, error: "This link is no longer open. Reply on WhatsApp and we will help." };
  if (/email/i.test(error.message)) return { ok: false, error: "That email does not look right." };
  console.error("qualify_submit failed", error.code);
  return { ok: false, error: "That did not go through. Please try again in a minute." };
}
