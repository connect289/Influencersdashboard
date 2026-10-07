import { createClient } from "@supabase/supabase-js";
import { anthropicMessages, runOnce, type Db, type Usage } from "@/lib/ai/worker";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * The AI optimiser's worker (spec B7.8.2). The database wakes it (pg_net) when a run is queued; anyone calling it can
 * only make queued runs start sooner, because the database decides what runs and enforces the daily budget. Needs two
 * server-side environment variables: ANTHROPIC_API_KEY and AI_WORKER_KEY (an API key with the ai_worker scope).
 */
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 300;

type Answer = { ok: boolean; status?: number; result?: unknown; error?: string };

function db(key: string): Db {
  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const call = async <T>(fn: string, args: Record<string, unknown>): Promise<T> => {
    const { data, error } = await supabase.schema("b2b").rpc(fn, args);
    if (error) throw new Error(`${fn}: database error (${error.code ?? "unknown"})`);
    const a = data as Answer;
    if (!a.ok) throw new Error(`${fn}: ${a.error ?? "refused"}`);
    return a.result as T;
  };
  return {
    claim: (info) => call("api_ai_claim", { p_key: key, p_info: info }),
    tool: (runId, name, input) => call("api_ai_tool", { p_key: key, p_run_id: runId, p_name: name, p_input: input }),
    finish: (runId, body) => call("api_ai_finish", { p_key: key, p_run_id: runId, p: body }),
    fail: (runId, error, usage: Usage) => call("api_ai_fail", { p_key: key, p_run_id: runId, p_error: error, p_usage: usage }),
  };
}

async function tick(): Promise<Response> {
  const workerKey = process.env.AI_WORKER_KEY;
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!workerKey) return Response.json({ ok: false, error: "AI_WORKER_KEY is not set on the server" }, { status: 503 });
  const d = db(workerKey);
  if (!apiKey) {
    // report in, so the Admin screen can say what is missing; claim nothing
    await d.claim({ has_anthropic_key: false, prompt: "unset" }).catch(() => null);
    return Response.json({ ok: false, error: "ANTHROPIC_API_KEY is not set on the server" }, { status: 503 });
  }
  const messages = anthropicMessages(apiKey);
  const done: unknown[] = [];
  const started = Date.now();
  // up to 3 runs per wake-up, while there is time left
  for (let i = 0; i < 3 && Date.now() - started < 150_000; i++) {
    try {
      const r = await runOnce(d, messages, { has_anthropic_key: true });
      if (r.run === null) break;
      done.push({ run: r.run, status: r.status });
    } catch (e) {
      return Response.json({ ok: false, error: e instanceof Error ? e.message : "worker error", done }, { status: 502 });
    }
  }
  return Response.json({ ok: true, done });
}

export const POST = tick;
export const GET = tick;
