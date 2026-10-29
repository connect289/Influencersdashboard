import { DOCS } from "./docs.generated.ts";
import { findSections } from "./docs-source.ts";
import { OPERATE } from "../operate/index.ts";

// The read tools the app answers itself (the rest are the database's, through one.ai_tool): the runbook sections, the
// Operate pages' text and Witty's n8n executions. Shared by the AI worker's Ask (lib/ai/worker.ts) and the command
// centre chat (lib/ai/chat/engine.ts).

export type N8nReader = {
  executions(
    limit: number,
  ): Promise<Array<{ id: string; status: string; startedAt: string | null; stoppedAt: string | null }>>;
};

export type ToolResult = { ok: boolean; data?: unknown; error?: string };

const clamp = (v: unknown, lo: number, hi: number, dflt: number) => {
  const n = typeof v === "number" ? Math.trunc(v) : dflt;
  return Math.min(Math.max(Number.isFinite(n) ? n : dflt, lo), hi);
};

export const LOCAL_READ_TOOLS = new Set(["runbook", "operate", "n8n_executions"]);

/** Answers a local read tool, or null when the tool is the database's. */
export async function localReadTool(
  tool: string,
  args: Record<string, unknown>,
  n8n: N8nReader | null | undefined,
): Promise<ToolResult | null> {
  if (tool === "runbook") {
    // The hand-over documents, from the generated module (D-083): the sections a question's words point at.
    const query = typeof args.query === "string" ? args.query : "";
    const found = findSections(DOCS, query, 3);
    return {
      ok: true,
      data: found.length
        ? found.map((d) => ({ file: `${d.file}.md`, section: d.title, text: d.text.slice(0, 3000) }))
        : { sections: DOCS.map((d) => `${d.file}: ${d.title}`), note: "no section matches; pick one by name" },
    };
  }
  if (tool === "operate") {
    // What each app needs and where to look, as the Operate pages say it (lib/operate; static, no data).
    const app = typeof args.app === "string" ? OPERATE[args.app] : undefined;
    return app
      ? {
          ok: true,
          data: {
            app: app.key,
            needs: app.needs,
            first_time: app.firstTime,
            daily: app.daily,
            when_fires: app.whenFires,
            in_the_app: app.inTheApp,
            fixes: app.fixes,
            tests: app.tests,
          },
        }
      : { ok: false, error: `app is one of ${Object.keys(OPERATE).join(", ")}` };
  }
  if (tool === "n8n_executions") {
    if (!n8n) return { ok: false, error: "n8n is not configured (Setup item n8n_api)" };
    const status = typeof args.status === "string" ? args.status : null;
    const rows = await n8n.executions(20);
    return {
      ok: true,
      data: rows.filter((r) => !status || r.status === status).slice(0, clamp(args.limit, 1, 20, 10)),
    };
  }
  return null;
}
