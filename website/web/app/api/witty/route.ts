import { z } from "zod";
import { encodeEvent, type WittyEvent } from "@/lib/web-advisor/events";
import { errorFields, log } from "@/lib/server/log";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { ipFrom } from "@/lib/server/request";
import { getSettings } from "@/lib/server/settings";
import { currentStudent } from "@/lib/server/student-session";
import { breakerOpen } from "@/lib/server/web-advisor/breaker";
import { failTurn, openSession, runTurn } from "@/lib/server/web-advisor/turn";

/**
 * Witty on the website (internal: web_advisor) — streaming turn endpoint (Node.js runtime, the default; bom1). Server-Sent Events:
 * thinking, cards, token, replace, done, error. Requires a verified student session (the gate). Off unless the
 * `web_advisor_enabled` flag is on; the circuit breaker sends the client to the guided finder while the provider is degraded.
 */
export const maxDuration = 60;

const body = z.object({ message: z.string().trim().min(1).max(1000), message_id: z.string().regex(/^[\w-]{8,64}$/) });

const json = (status: number, data: Record<string, unknown>) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export async function POST(req: Request) {
  const settings = await getSettings();
  if (!settings.web_advisor_enabled) return json(404, { error: "not_available", fallback: true });
  if (await breakerOpen()) return json(503, { error: "degraded", fallback: true });
  const student = await currentStudent();
  if (!student) return json(401, { error: "verify_first" });
  const parsed = body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return json(400, { error: "invalid" });
  const ip = ipFrom(req);
  for (const [limit, id] of [
    [LIMITS.chatTurnPerSession, student.studentId],
    [LIMITS.chatTurnPerIp, ip],
  ] as const) {
    if (!(await rateLimit(limit, id)).ok) return json(429, { error: "slow_down" });
  }

  const session = await openSession(student);
  if (!session) return json(401, { error: "verify_first" });
  const { message, message_id } = parsed.data;

  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emit = (e: WittyEvent) => {
        try {
          controller.enqueue(encoder.encode(encodeEvent(e)));
        } catch {
          // client went away; the turn still completes and is stored, so a retry replays it
        }
      };
      // Retry of a message already answered (network loss): replay the stored reply instead of running it again.
      const i = session.messages.findIndex((m) => m.direction === "in" && m.meta?.client_id === message_id);
      if (i !== -1) {
        const reply = session.messages.slice(i + 1).find((m) => m.direction === "out");
        if (reply) {
          emit({ type: "token", text: reply.content });
          emit({ type: "done", messageId: reply.id, chips: (reply.meta?.chips as string[]) ?? [], mode: reply.answer_mode ?? "ACK" });
          controller.close();
          return;
        }
      }
      const ac = new AbortController();
      const timer = setTimeout(() => ac.abort(), settings.web_advisor_budget.turn_timeout_ms);
      try {
        await runTurn({ student, session, message, messageId: message_id, settings, emit, signal: ac.signal });
      } catch (err) {
        await failTurn(ac.signal.aborted ? "timeout" : "error");
        log("error", "web_advisor.turn_failed", { timeout: ac.signal.aborted, ...errorFields(err) });
        emit({
          type: "error",
          fallback: true,
          message: "Sorry, I couldn't answer just now. Please try again, or talk to a counsellor on WhatsApp.",
        });
      } finally {
        clearTimeout(timer);
        controller.close();
      }
    },
  });
  return new Response(stream, {
    headers: { "content-type": "text/event-stream; charset=utf-8", "cache-control": "no-store, no-transform", "x-accel-buffering": "no" },
  });
}
