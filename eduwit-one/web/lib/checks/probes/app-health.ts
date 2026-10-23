import { checkDue, heartbeatDue } from "../due.ts";
import type { Probe, ProbeOutcome } from "../types.ts";
import type { HeartbeatReport, ResultReport } from "../../state.ts";

// The apps' own health endpoints (spec §7 heartbeats website, spark, b2b-app, influencer; checks WEB-02, INF-04).
// The host and path come from one.settings.hosts and health_paths; a path other than /api/health is a reachability
// check (Spark has no health endpoint yet).

const TARGETS = [
  { app: "website", component: "website", intervalS: 60, check: "WEB-02" },
  { app: "influencer", component: "influencer", intervalS: 120, check: "INF-04" },
  { app: "b2b_app", component: "b2b-app", intervalS: 120, check: null },
  { app: "spark", component: "spark", intervalS: 120, check: null },
] as const;

export const appHealthProbe: Probe = {
  name: "app-health",
  async run({ state, clients, now }): Promise<ProbeOutcome> {
    const heartbeats: HeartbeatReport[] = [];
    const results: ResultReport[] = [];
    const due = TARGETS.filter(
      (t) => heartbeatDue(state, t.component, t.intervalS, now) || (t.check && checkDue(state, t.check, now)),
    );
    if (due.length === 0) return { status: "not_due", mode: clients.appHealth.mode, heartbeats, results };
    await Promise.all(
      due.map(async (t) => {
        const host = state.settings.hosts[t.app];
        const path = state.settings.health_paths[t.app] ?? "/api/health";
        const r = await clients.appHealth.client.health(
          `${host}${path}`,
          path === "/api/health" ? "json_ok" : "reachable",
        );
        const detail = { status: r.status, ms: r.ms, path };
        heartbeats.push({
          component: t.component,
          ok: r.ok,
          detail,
          error: r.ok ? undefined : `health ${r.status}`,
          expected_interval_s: t.intervalS,
        });
        if (t.check && checkDue(state, t.check, now)) {
          results.push({ check_id: t.check, status: r.ok ? "ok" : "fail", value: detail, duration_ms: r.ms });
        }
      }),
    );
    return { status: "ran", mode: clients.appHealth.mode, heartbeats, results };
  },
};
