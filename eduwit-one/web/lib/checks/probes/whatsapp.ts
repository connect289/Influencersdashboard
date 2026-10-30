import { z } from "zod";
import { HttpError } from "../../http.ts";
import { heartbeatDue } from "../due.ts";
import { defineProbe, notConfiguredBeats, type ProbeOutcome } from "../types.ts";
import { type HeartbeatReport, whatsappSchema } from "../../state.ts";

// WhatsApp Cloud API (heartbeats whatsapp:witty, whatsapp:b2c): the business numbers' status and quality rating.
// The phone number ids come from one.settings.whatsapp.phone_ids (Setup item whatsapp).

const INTERVAL_S = 900;

export const whatsappProbe = defineProbe({
  name: "whatsapp",
  client: "whatsapp",
  checks: [],
  settings: z.object({ whatsapp: whatsappSchema.pick({ phone_ids: true }) }),
  async run({ state, settings, clients, now }): Promise<ProbeOutcome> {
    const { mode, client, missing } = clients.whatsapp;
    const ids = settings.whatsapp.phone_ids ?? {};
    // No phone ids: there is no component to name. Ids but no client: each line says what is missing (D-108).
    if (Object.keys(ids).length === 0) return { status: "not_configured", mode, heartbeats: [], results: [] };
    if (!client) {
      const beats = notConfiguredBeats(
        { state, now },
        missing ?? "the WhatsApp client",
        Object.keys(ids).map((line) => ({ component: `whatsapp:${line}`, intervalS: INTERVAL_S })),
      );
      return { status: "not_configured", mode, heartbeats: beats, results: [] };
    }
    const heartbeats: HeartbeatReport[] = [];
    for (const [line, id] of Object.entries(ids)) {
      const component = `whatsapp:${line}`;
      if (!heartbeatDue(state, component, INTERVAL_S, now)) continue;
      try {
        const p = await client.phoneNumber(id);
        const ok = p.status === "CONNECTED" && p.quality_rating !== "RED";
        heartbeats.push({
          component,
          ok,
          detail: p,
          error: ok ? undefined : `status ${p.status}, quality ${p.quality_rating}`,
          expected_interval_s: INTERVAL_S,
        });
      } catch (e) {
        heartbeats.push({
          component,
          ok: false,
          detail: {},
          error: e instanceof HttpError ? e.message : "error",
          expected_interval_s: INTERVAL_S,
        });
      }
    }
    return { status: heartbeats.length === 0 ? "not_due" : "ran", mode, heartbeats, results: [] };
  },
});
