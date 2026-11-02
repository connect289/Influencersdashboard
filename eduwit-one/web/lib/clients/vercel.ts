import { z } from "zod";
import { fetchJson } from "../http.ts";
import type { VercelClient, VercelDeployment } from "./types.ts";

// Vercel REST API, read only: the latest production deployment of a project that was built (canceled ones skipped).

const deployment = z.object({
  uid: z.string(),
  state: z.string().optional(),
  readyState: z.string().optional(),
  created: z.number(),
  url: z.string().nullable().optional(),
});
export const vercelDeploymentsFixture = z.object({ deployments: z.array(deployment) });
export type VercelDeploymentsFixture = z.infer<typeof vercelDeploymentsFixture>;

// The newest production deployment that was built. A CANCELED one is a build Vercel skipped (the ignored-build step,
// D-111, cancels docs-only pushes) or one a newer push superseded; it never served traffic, so it says nothing about
// production and is passed over. ERROR stays a failure. Only when every listed deployment is canceled is one returned.
function latest(body: VercelDeploymentsFixture): VercelDeployment | null {
  const d = body.deployments.find((x) => (x.readyState ?? x.state) !== "CANCELED") ?? body.deployments[0];
  if (!d) return null;
  return { uid: d.uid, state: d.readyState ?? d.state ?? "UNKNOWN", createdAt: d.created, url: d.url ?? null };
}

export class RealVercelClient implements VercelClient {
  private readonly apiBase: string;
  private readonly token: string;

  constructor(apiBase: string, token: string) {
    this.apiBase = apiBase;
    this.token = token;
  }

  /** Raw (validated) list, used by the fixture recorder. */
  async deployments(project: string, team: string): Promise<VercelDeploymentsFixture> {
    const q = new URLSearchParams({ projectId: project, target: "production", limit: "10", slug: team });
    const { json } = await fetchJson("vercel", `${this.apiBase}/v6/deployments?${q}`, {
      headers: { authorization: `Bearer ${this.token}` },
    });
    const parsed = vercelDeploymentsFixture.parse(json);
    return {
      deployments: parsed.deployments.map((d) => ({
        uid: d.uid,
        state: d.state,
        readyState: d.readyState,
        created: d.created,
        url: d.url ?? null,
      })),
    };
  }

  async latestProduction(project: string, team: string) {
    return latest(await this.deployments(project, team));
  }
}

export class MockVercelClient implements VercelClient {
  private readonly byProject: Record<string, VercelDeploymentsFixture>;

  constructor(byProject: Record<string, VercelDeploymentsFixture>) {
    this.byProject = byProject;
  }

  async latestProduction(project: string) {
    const f = this.byProject[project];
    return f ? latest(f) : null;
  }
}
