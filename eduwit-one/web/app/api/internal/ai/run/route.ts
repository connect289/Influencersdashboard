import { internalAuthorized } from "@/lib/auth.ts";
import { AnthropicModelClient, GEMINI_API, GeminiModelClient } from "@/lib/ai/client.ts";
import { SupabaseAiDb } from "@/lib/ai/db.ts";
import type { Provider } from "@/lib/ai/models.ts";
import { runWorker, type N8nReader } from "@/lib/ai/worker.ts";
import { credentialsFrom, vaultSecrets } from "@/lib/clients/credentials.ts";
import { clientsFor } from "@/lib/clients/index.ts";
import { SupabaseOneDb } from "@/lib/db.ts";
import { log } from "@/lib/log.ts";

// The AI worker (spec §11), called by the database through one.ai_step() while a task is due (D-075), or by an
// operator with the internal key. Runs tasks for up to four minutes, inside pg_net's 290 s wait; a task still running
// when an invocation dies is taken back by the claim after 10 minutes. Mock mode has no model: tasks wait as deferred.
// Needs Vercel's Fluid compute (on by default for new projects) for a 300 s limit.
export const dynamic = "force-dynamic";
export const maxDuration = 300;

export async function POST(request: Request) {
  if (!internalAuthorized(request)) return Response.json({ error: "unauthorized" }, { status: 401 });
  const db = SupabaseAiDb.fromEnv();
  const oneDb = SupabaseOneDb.fromEnv();
  if (!db || !oneDb) return Response.json({ error: "not_configured" }, { status: 503 });
  const requestId = crypto.randomUUID();
  const started = Date.now();
  try {
    const credentials = credentialsFrom(await vaultSecrets(oneDb));
    const state = await oneDb.tickState();
    const mock = process.env.ONE_CLIENT_MODE === "mock";
    const gemini = (state.settings.vendors as Record<string, string>).gemini_api ?? GEMINI_API;
    const clientFor = (p: Provider) => {
      if (mock) return null;
      if (p === "anthropic") return credentials.anthropic ? new AnthropicModelClient(credentials.anthropic) : null;
      return credentials.gemini ? new GeminiModelClient(credentials.gemini, gemini) : null;
    };
    const n8nClient = clientsFor(state.settings, credentials).n8n.client;
    const wittyWorkflow = state.settings.n8n.witty_workflow_id;
    const n8n: N8nReader | null = n8nClient
      ? { executions: (limit) => n8nClient.executions(wittyWorkflow, limit) }
      : null;
    const summary = await runWorker({
      db,
      clientFor,
      n8n,
      holder: `ai-${requestId.slice(0, 8)}`,
      deadline: started + 240_000,
    });
    log("info", "ai.done", { requestId, ...summary, ms: Date.now() - started });
    return Response.json({ requestId, ...summary });
  } catch (e) {
    log("error", "ai.failed", { requestId, error: e instanceof Error ? e.message : "error" });
    return Response.json({ requestId, error: "ai_failed" }, { status: 500 });
  }
}
