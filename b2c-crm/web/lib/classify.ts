import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";

/**
 * Reply classification, the Claude step (spec B6.6): the keyword rules in the database decide first; what they cannot
 * decide comes here. Only the reply text and the course interest are sent: no name, phone or email. Below 0.8
 * confidence the database sends the reply to the Replies inbox. Without ANTHROPIC_API_KEY nothing is sent and the
 * replies go to the inbox after 10 minutes.
 */
const Result = z.object({
  class: z.enum(["positive", "question", "negative", "opt_out", "other"]),
  confidence: z.number(),
});

export const CLASSIFY_SYSTEM = `You classify a student's reply to an education counselling message (online degrees in India). Replies may be in English, Hindi or Hinglish.
Classes:
- positive: wants a call, wants details, asks about fees, admission, eligibility or applying, says they are interested.
- question: asks something without showing clear interest (timings, location, what Eduwit is).
- negative: not interested, already joined elsewhere, not now, do not contact.
- opt_out: asks to stop all messages (stop, unsubscribe, block).
- other: greetings, thanks, emojis, unclear.
Give confidence between 0 and 1. Be conservative: use below 0.8 when unsure.`;

export async function runClassify(): Promise<{ classified: number; skipped?: string }> {
  if (!process.env.ANTHROPIC_API_KEY) return { classified: 0, skipped: "ANTHROPIC_API_KEY is not set" };
  const db = adminClient();
  const { data, error } = await db.rpc("reply_classify_take", { p_limit: 20 });
  if (error) throw new Error(`reply_classify_take: ${error.message}`);
  const items = (data ?? []) as { id: number; text: string; course: string | null }[];
  if (items.length === 0) return { classified: 0 };
  const { data: setting } = await db.from("settings").select("value").eq("key", "nurture").maybeSingle();
  const model = (setting?.value as { classify_model?: string } | null)?.classify_model || "claude-haiku-4-5";
  const client = new Anthropic({ maxRetries: 1, timeout: 20_000 });
  const results: { id: number; class: string; confidence: number; model: string }[] = [];
  for (const it of items) {
    try {
      const res = await client.messages.parse({
        model,
        max_tokens: 256,
        system: CLASSIFY_SYSTEM,
        messages: [{ role: "user", content: `Course interest: ${it.course ?? "unknown"}\nReply: ${it.text}` }],
        output_config: { format: zodOutputFormat(Result) },
      });
      const out = res.stop_reason === "refusal" ? null : res.parsed_output;
      results.push(out ? { id: it.id, class: out.class, confidence: Math.max(0, Math.min(1, out.confidence)), model }
                       : { id: it.id, class: "other", confidence: 0, model });
    } catch (e) {
      if (e instanceof Anthropic.RateLimitError || e instanceof Anthropic.APIConnectionError) break; // try again next minute
      console.error("classify failed", e instanceof Error ? e.message : e);
      results.push({ id: it.id, class: "other", confidence: 0, model });
    }
  }
  if (results.length) {
    const { error: doneError } = await db.rpc("reply_classify_done", { p_results: results });
    if (doneError) throw new Error(`reply_classify_done: ${doneError.message}`);
  }
  return { classified: results.length };
}
