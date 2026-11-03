import { z } from "zod";
import { checkDue, heartbeatDue } from "../due.ts";
import { defineProbe, type ProbeOutcome } from "../types.ts";
import { type HeartbeatReport, healthPathsSchema, hostsSchema, type ResultReport } from "../../state.ts";

// The apps' own health endpoints (spec §7 heartbeats website, spark, b2b-app, influencer; checks WEB-02, INF-04).
// The host and path come from one.settings.hosts and health_paths; a path other than /api/health is a reachability
// check (Spark has no health endpoint yet). Every app is called once in 5 minutes (D-133: the owner's rule after the
// Vercel pause of 3 Nov 2026; a health call that waits on a slow database runs on the app's side long after this probe
// gave up, so each call costs the app far more than it costs here). WEB-02 and INF-04 run at the same cadence (0036).

export const APP_PROBE_INTERVAL_S = 300;

const TARGETS = [
  { app: "website", component: "website", intervalS: APP_PROBE_INTERVAL_S, check: "WEB-02" },
  { app: "influencer", component: "influencer", intervalS: APP_PROBE_INTERVAL_S, check: "INF-04" },
  { app: "b2b_app", component: "b2b-app", intervalS: APP_PROBE_INTERVAL_S, check: null },
  { app: "spark", component: "spark", intervalS: APP_PROBE_INTERVAL_S, check: null },
] as const;

export const appHealthProbe = defineProbe({
  name: "app-health",
  client: "appHealth",
  checks: TARGETS.flatMap((t) => (t.check ? [t.check] : [])),
  settings: z.object({
    hosts: hostsSchema.pick({ website: true, spark: true, b2b_app: true, influencer: true }),
    health_paths: healthPathsSchema,
  }),
  async run({ state, settings, clients, now }): Promise<ProbeOutcome> {
    const heartbeats: HeartbeatReport[] = [];
    const results: ResultReport[] = [];
    const due = TARGETS.filter(
      (t) => heartbeatDue(state, t.component, t.intervalS, now) || (t.check && checkDue(state, t.check, now)),
    );
    if (due.length === 0) return { status: "not_due", mode: clients.appHealth.mode, heartbeats, results };
    await Promise.all(
      due.map(async (t) => {
        const host = settings.hosts[t.app];
        const path = settings.health_paths[t.app] ?? "/api/health";
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
});
