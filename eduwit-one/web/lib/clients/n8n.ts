import { z } from "zod";
import { fetchJson } from "../http.ts";
import type { N8nClient, N8nExecution } from "./types.ts";

// n8n public API: a workflow's active flag and its recent executions, and one write, the retry of a failed execution
// (FIX-N8N-RETRY, switched on by the owner only). Execution data (which can hold message text) is never requested:
// only id, status and times.

export const n8nWorkflowFixture = z.object({ id: z.string(), name: z.string(), active: z.boolean() });
const execution = z.object({
  id: z.union([z.string(), z.number()]).transform(String),
  status: z.string(),
  startedAt: z.string().nullable(),
  stoppedAt: z.string().nullable(),
});
export const n8nExecutionsFixture = z.object({ data: z.array(execution) });

const retried = z.looseObject({
  id: z.union([z.string(), z.number()]).transform(String).optional(),
  status: z.string().optional(),
});

export type N8nFixtures = {
  workflows: Record<string, z.infer<typeof n8nWorkflowFixture>>;
  executions: Record<string, z.infer<typeof n8nExecutionsFixture>>;
};

export class RealN8nClient implements N8nClient {
  private readonly base: string;
  private readonly apiKey: string;

  constructor(base: string, apiKey: string) {
    this.base = base;
    this.apiKey = apiKey;
  }

  private get(path: string) {
    return fetchJson("n8n", `${this.base}${path}`, { headers: { "X-N8N-API-KEY": this.apiKey } }).then((r) => r.json);
  }

  async workflow(id: string) {
    const w = n8nWorkflowFixture.parse(await this.get(`/api/v1/workflows/${encodeURIComponent(id)}`));
    return { id: w.id, name: w.name, active: w.active };
  }

  async executions(workflowId: string, limit: number): Promise<N8nExecution[]> {
    const q = new URLSearchParams({ workflowId, limit: String(limit), includeData: "false" });
    return n8nExecutionsFixture.parse(await this.get(`/api/v1/executions?${q}`)).data;
  }

  /** Never retried by the HTTP layer: a second POST could run the execution twice. With the run's own workflow version. */
  async retry(executionId: string) {
    const r = await fetchJson(
      "n8n",
      `${this.base}/api/v1/executions/${encodeURIComponent(executionId)}/retry`,
      { method: "POST", headers: { "X-N8N-API-KEY": this.apiKey }, body: { loadWorkflow: false } },
      { timeoutMs: 15_000, retries: 0, breakerFailures: 3, breakerCooldownMs: 120_000 },
    );
    const body = retried.parse(r.json);
    return { id: body.id ?? null, status: body.status ?? null };
  }
}

export class MockN8nClient implements N8nClient {
  private readonly f: N8nFixtures;

  constructor(f: N8nFixtures) {
    this.f = f;
  }

  async workflow(id: string) {
    const w = this.f.workflows[id] ?? this.f.workflows.default;
    if (!w) throw new Error("mock n8n: no workflow fixture");
    return { ...w, id };
  }

  async executions(workflowId: string) {
    return (this.f.executions[workflowId] ?? this.f.executions.default ?? { data: [] }).data;
  }

  async retry(executionId: string) {
    return { id: `${executionId}-retry`, status: "success" };
  }
}
