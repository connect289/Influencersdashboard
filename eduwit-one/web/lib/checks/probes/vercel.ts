import { z } from "zod";
import { HttpError } from "../../http.ts";
import { checkDue, heartbeatDue } from "../due.ts";
import { defineProbe, type ProbeOutcome } from "../types.ts";
import { type HeartbeatReport, type ResultReport, vercelSchema } from "../../state.ts";

// Vercel: the latest production deployment of the website and of Eduwit One (heartbeats vercel:website, vercel:one;
// check WEB-07). The function error rate half of WEB-07 has no public API; it is a proposal (D-049).

const TARGETS = [
  { key: "website", component: "vercel:website", check: "WEB-07" },
  { key: "one", component: "vercel:one", check: null },
] as const;
const INTERVAL_S = 600;

export const vercelProbe = defineProbe({
  name: "vercel",
  client: "vercel",
  checks: TARGETS.flatMap((t) => (t.check ? [t.check] : [])),
  settings: z.object({ vercel: vercelSchema }),
  async run({ state, settings, clients, now }): Promise<ProbeOutcome> {
    const { mode, client } = clients.vercel;
    if (!client) return { status: "not_configured", mode, heartbeats: [], results: [] };
    const heartbeats: HeartbeatReport[] = [];
    const results: ResultReport[] = [];
    const due = TARGETS.filter(
      (t) => heartbeatDue(state, t.component, INTERVAL_S, now) || (t.check && checkDue(state, t.check, now)),
    );
    if (due.length === 0) return { status: "not_due", mode, heartbeats, results };
    await Promise.all(
      due.map(async (t) => {
        const project = settings.vercel.projects[t.key];
        if (!project) return;
        try {
          const d = await client.latestProduction(project, settings.vercel.team);
          const ready = d?.state === "READY";
          const detail = {
            project,
            state: d?.state ?? "none",
            deployment: d?.uid ?? null,
            created_at: d ? new Date(d.createdAt).toISOString() : null,
          };
          heartbeats.push({
            component: t.component,
            ok: ready,
            detail,
            error: ready ? undefined : `deployment ${d?.state ?? "missing"}`,
            expected_interval_s: INTERVAL_S,
          });
          if (t.check && checkDue(state, t.check, now))
            results.push({ check_id: t.check, status: ready ? "ok" : "fail", value: detail });
        } catch (e) {
          const error = e instanceof HttpError ? e.message : "error";
          heartbeats.push({
            component: t.component,
            ok: false,
            detail: { project },
            error,
            expected_interval_s: INTERVAL_S,
          });
          if (t.check && checkDue(state, t.check, now))
            results.push({ check_id: t.check, status: "skipped", value: { project }, error });
        }
      }),
    );
    return { status: "ran", mode, heartbeats, results };
  },
});
