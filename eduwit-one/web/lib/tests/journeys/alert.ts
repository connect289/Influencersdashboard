import { Failed, type TestDef } from "../types.ts";
import type { JourneyIo } from "./io.ts";

// T-ALERT (spec §10): a synthetic P2 incident gets a delivery to the test recipient; the alert sender (each minute,
// before the tests) sends it; Resend reports it delivered; the test acknowledges and resolves the incident. Eduwit One
// only: nothing is written to an app.

export const tAlert: TestDef<JourneyIo> = {
  id: "T-ALERT",
  needs: ["email"],
  guard: async (c) => (c.io.email ? null : "the email client is not configured (Setup item email)"),
  steps: [
    {
      key: "open",
      title: "Open a synthetic P2 incident with a test delivery",
      timeoutS: 10,
      act: async (c) => {
        const r = await c.io.seams.act(c.run.id, "alert.open");
        return { incident_id: r.incident_id, delivery_id: r.delivery_id, recipient: r.recipient };
      },
    },
    {
      key: "sent",
      title: "The email is sent",
      timeoutS: 180,
      until: async (c) => {
        const d = await c.io.seams.fact(c.run.id, "alert.delivery");
        if (d.status === "failed" && Number(d.attempts) >= 2)
          throw new Failed(`the delivery failed: ${String(d.error ?? "")}`);
        return d.status === "sent" && typeof d.provider_id === "string"
          ? { done: true, artefacts: { provider_id: d.provider_id } }
          : { done: false, detail: `delivery ${String(d.status ?? "missing")}` };
      },
    },
    {
      key: "delivered",
      title: "The email is delivered",
      timeoutS: 300,
      until: async (c) => {
        const id = c.artefacts.provider_id;
        if (typeof id !== "string" || !c.io.email) throw new Failed("no provider id to follow");
        const { lastEvent } = await c.io.email.status(id);
        if (lastEvent === "bounced" || lastEvent === "complained") throw new Failed(`Resend reports ${lastEvent}`);
        return lastEvent === "delivered"
          ? { done: true, detail: "delivered" }
          : { done: false, detail: `last event ${lastEvent ?? "none"}` };
      },
    },
    {
      key: "ack",
      title: "Acknowledge and resolve it",
      timeoutS: 10,
      act: async (c) => {
        const r = await c.io.seams.act(c.run.id, "alert.close", { incident_id: c.artefacts.incident_id });
        if (r.closed !== true) throw new Failed("the synthetic incident was not open");
        return undefined;
      },
    },
  ],
};
