import { z } from "zod";
import { fetchJson } from "../http.ts";
import type { N8nClient, N8nExecution } from "./types.ts";

// n8n public API, read only: a workflow's active flag and its recent executions. Execution data (which can hold
// message text) is never requested: only id, status and times.

export const n8nWorkflowFixture = z.object({ id: z.string(), name: z.string(), active: z.boolean() });
const execution = z.object({
  id: z.union([z.string(), z.number()]).transform(String),
  status: z.string(),
  startedAt: z.string().nullable(),
  stoppedAt: z.string().nullable(),
});
export const n8nExecutionsFixture = z.object({ data: z.array(execution) });

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
}
