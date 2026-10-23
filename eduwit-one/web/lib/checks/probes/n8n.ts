import { HttpError } from "../../http.ts";
import { checkDue, heartbeatDue } from "../due.ts";
import type { Probe, ProbeOutcome } from "../types.ts";
import type { HeartbeatReport, ResultReport } from "../../state.ts";
import type { N8nExecution } from "../../clients/types.ts";

// n8n (heartbeats n8n:instance and n8n:<Witty workflow id>; checks WITTY-02, WITTY-08). The Witty workflow has a
// 1-minute timer, so its heartbeat is good while its latest execution started within two minutes.

const BAD = new Set(["error", "crashed"]);
const minsAgo = (iso: string | null, now: Date) => (iso ? (now.getTime() - Date.parse(iso)) / 60_000 : Infinity);

function witty02(active: boolean, runs: N8nExecution[], now: Date): ResultReport {
  const latest = runs[0]?.startedAt ?? null;
  const failed = runs.filter((r) => BAD.has(r.status) && minsAgo(r.startedAt, now) <= 15).map((r) => r.id);
  const ok = active && minsAgo(latest, now) <= 5 && failed.length === 0;
  return {
    check_id: "WITTY-02",
    status: ok ? "ok" : "fail",
    value: { active, latest_started_at: latest, failed_15m: failed.slice(0, 10) },
  };
}

export const n8nProbe: Probe = {
  name: "n8n",
  async run({ state, clients, now }): Promise<ProbeOutcome> {
    const { mode, client } = clients.n8n;
    if (!client) return { status: "not_configured", mode, heartbeats: [], results: [] };
    const heartbeats: HeartbeatReport[] = [];
    const results: ResultReport[] = [];
    const ids = state.settings.n8n;
    const wittyComponent = `n8n:${ids.witty_workflow_id}`;
    const wantWitty = heartbeatDue(state, wittyComponent, 60, now) || checkDue(state, "WITTY-02", now);
    try {
      if (wantWitty) {
        const [wf, runs] = await Promise.all([
          client.workflow(ids.witty_workflow_id),
          client.executions(ids.witty_workflow_id, 20),
        ]);
        heartbeats.push({ component: "n8n:instance", ok: true, detail: {}, expected_interval_s: 300 });
        const fresh = wf.active && minsAgo(runs[0]?.startedAt ?? null, now) <= 2;
        heartbeats.push({
          component: wittyComponent,
          ok: fresh,
          detail: { active: wf.active, latest_started_at: runs[0]?.startedAt ?? null },
          error: fresh ? undefined : "no recent execution",
          expected_interval_s: 60,
        });
        if (checkDue(state, "WITTY-02", now)) results.push(witty02(wf.active, runs, now));
      }
      if (checkDue(state, "WITTY-08", now)) {
        const expected = [
          state.settings.witty.expect_nurture ? ids.nurture_workflow_id : undefined,
          state.settings.witty.expect_learning ? ids.learning_workflow_id : undefined,
        ].filter((x): x is string => Boolean(x));
        const inactive: string[] = [];
        for (const id of expected) if (!(await client.workflow(id)).active) inactive.push(id);
        results.push({
          check_id: "WITTY-08",
          status: inactive.length === 0 ? "ok" : "fail",
          value: { expected, inactive, subjects: inactive },
        });
      }
    } catch (e) {
      const error = e instanceof HttpError ? e.message : "error";
      heartbeats.push({ component: "n8n:instance", ok: false, detail: {}, error, expected_interval_s: 300 });
      return { status: "error", mode, heartbeats, results, error };
    }
    return { status: heartbeats.length + results.length === 0 ? "not_due" : "ran", mode, heartbeats, results };
  },
};
