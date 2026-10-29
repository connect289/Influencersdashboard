import { z } from "zod";
import { AnthropicChatClient } from "@/lib/ai/chat/client.ts";
import { SupabaseChatDb } from "@/lib/ai/chat/db.ts";
import { runTurn, type ChatEvent } from "@/lib/ai/chat/engine.ts";
import { SupabaseAiDb } from "@/lib/ai/db.ts";
import type { N8nReader } from "@/lib/ai/read-tools.ts";
import { credentialsFrom, vaultSecrets } from "@/lib/clients/credentials.ts";
import { clientsFor } from "@/lib/clients/index.ts";
import { SupabaseOneDb } from "@/lib/db.ts";
import { log } from "@/lib/log.ts";
import { assertUser } from "@/lib/session.ts";
import { runValidate } from "@/lib/setup/run.ts";
import { clientSettingsSchema, n8nSchema, readSettings } from "@/lib/state.ts";
import { ui } from "@/lib/ui/api.ts";
import { okSchema } from "@/lib/ui/schemas.ts";

// One turn of the command centre (D-094), streamed back as one JSON event per line. The caller is the signed-in
// person (their session cookies; the middleware does not cover /api, so the gate is here): the turn's database calls
// run as them (one.ui_chat_*, and the acts through one.ui_*), the model calls' budget rows through the service role
// against the task the turn opened. Vercel Pro with Fluid compute allows the 300 s limit (owner, 24 Oct).
export const dynamic = "force-dynamic";
export const maxDuration = 300;

const bodySchema = z.object({
  thread_id: z.number().int().positive().nullable().optional(),
  text: z.string().min(1).max(4000),
});

export async function POST(request: Request) {
  let me;
  try {
    me = await assertUser();
  } catch {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return Response.json({ error: "bad_request" }, { status: 400 });
  const ai = SupabaseAiDb.fromEnv();
  const oneDb = SupabaseOneDb.fromEnv();
  if (!ai || !oneDb) return Response.json({ error: "not_configured" }, { status: 503 });
  const requestId = crypto.randomUUID();
  const started = Date.now();
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emit = (e: ChatEvent) => controller.enqueue(encoder.encode(`${JSON.stringify(e)}\n`));
      try {
        const credentials = credentialsFrom(await vaultSecrets(oneDb));
        const state = await oneDb.tickState();
        const settings = readSettings(clientSettingsSchema.extend({ n8n: n8nSchema }), state.settings);
        if (!settings.ok) throw new Error(settings.error);
        const mock = process.env.ONE_CLIENT_MODE === "mock";
        const client = !mock && credentials.anthropic ? new AnthropicChatClient(credentials.anthropic) : null;
        const n8nClient = clientsFor(settings.value, credentials).n8n.client;
        const wittyWorkflow = settings.value.n8n.witty_workflow_id;
        const n8n: N8nReader | null = n8nClient
          ? { executions: (limit) => n8nClient.executions(wittyWorkflow, limit) }
          : null;
        await runTurn(
          { thread: parsed.data.thread_id ?? null, text: parsed.data.text },
          {
            chat: new SupabaseChatDb(),
            ai,
            client,
            n8n,
            act: (fn, args, rid) => ui(fn, okSchema, { ...args, p_request_id: rid }),
            validateSetup: (item) => runValidate(item, me.email),
            holder: `chat-${requestId.replaceAll("-", "").slice(0, 16)}`,
            deadline: started + 150_000,
          },
          emit,
        );
        log("info", "chat.turn", { requestId, ms: Date.now() - started });
      } catch (e) {
        log("error", "chat.failed", { requestId, error: e instanceof Error ? e.message : "error" });
        emit({ t: "error", message: "The chat could not answer. Try again." });
      } finally {
        controller.close();
      }
    },
  });
  return new Response(stream, {
    headers: {
      "content-type": "application/x-ndjson; charset=utf-8",
      "cache-control": "no-store",
      "x-request-id": requestId,
    },
  });
}
