import { z } from "zod";
import { HttpError } from "../../http.ts";
import { checkDue, heartbeatDue, threshold } from "../due.ts";
import { defineProbe, notConfiguredBeats, type ProbeOutcome } from "../types.ts";
import { chatwootSchema, type HeartbeatReport, type ResultReport, thresholdsSchema } from "../../state.ts";

// Chatwoot (heartbeat chatwoot; check WITTY-05). The heartbeat detail carries incoming_recent, the incoming message
// count over the last witty_silence_h hours, which the SQL check WITTY-03 compares with Witty's inbox (D-035).

const INTERVAL_S = 300;
const HANDOFF_LABEL = "witty-handoff";

export const chatwootProbe = defineProbe({
  name: "chatwoot",
  client: "chatwoot",
  checks: ["WITTY-05"],
  settings: z.object({ chatwoot: chatwootSchema, thresholds: thresholdsSchema }),
  async run({ state, settings, clients, db, now }): Promise<ProbeOutcome> {
    const { mode, client, missing } = clients.chatwoot;
    if (!client) {
      const beats = notConfiguredBeats({ state, now }, missing ?? "the Chatwoot client", [
        { component: "chatwoot", intervalS: INTERVAL_S },
      ]);
      return { status: "not_configured", mode, heartbeats: beats, results: [] };
    }
    const heartbeats: HeartbeatReport[] = [];
    const results: ResultReport[] = [];
    const account = settings.chatwoot.account_id;
    if (heartbeatDue(state, "chatwoot", INTERVAL_S, now)) {
      try {
        const until = Math.floor(now.getTime() / 1000);
        const hours = threshold(settings.thresholds, "witty_silence_h", 3);
        const [inboxes, incoming] = await Promise.all([
          client.inboxCount(account),
          client.incomingMessages(account, until - hours * 3600, until),
        ]);
        heartbeats.push({
          component: "chatwoot",
          ok: inboxes > 0,
          detail: { inboxes, incoming_recent: incoming, window_h: hours },
          expected_interval_s: INTERVAL_S,
        });
      } catch (e) {
        heartbeats.push({
          component: "chatwoot",
          ok: false,
          detail: {},
          error: e instanceof HttpError ? e.message : "error",
          expected_interval_s: INTERVAL_S,
        });
      }
    }
    if (checkDue(state, "WITTY-05", now)) {
      const started = Date.now();
      try {
        const escalated = await db.wittyEscalations(50);
        const missing: number[] = [];
        for (const c of escalated) {
          const labels = await client.conversationLabels(String(c.account_id), c.conversation_id);
          if (!labels.includes(HANDOFF_LABEL)) missing.push(c.conversation_id);
        }
        results.push({
          check_id: "WITTY-05",
          status: missing.length === 0 ? "ok" : "fail",
          duration_ms: Date.now() - started,
          value: {
            escalated: escalated.length,
            missing_label: missing.slice(0, 20),
            subjects: missing.slice(0, 20).map(String),
          },
        });
      } catch (e) {
        results.push({
          check_id: "WITTY-05",
          status: "skipped",
          value: {},
          error: e instanceof HttpError ? e.message : "error",
        });
      }
    }
    return { status: heartbeats.length + results.length === 0 ? "not_due" : "ran", mode, heartbeats, results };
  },
});
