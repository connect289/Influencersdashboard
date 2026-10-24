import type { z } from "zod";
import type { OneDb } from "../db.ts";
import type { Clients, ClientMode } from "../clients/types.ts";
import { type HeartbeatReport, readSettings, type ResultReport, type TickState } from "../state.ts";
import { checkDue } from "./due.ts";

export type ProbeContext = {
  state: TickState;
  clients: Clients;
  db: Pick<OneDb, "wittyEscalations">;
  now: Date;
};

/** What one probe found this tick. "ran" with an empty report means nothing was due. */
export type ProbeOutcome = {
  status: "ran" | "not_due" | "not_configured" | "error";
  mode: ClientMode;
  heartbeats: HeartbeatReport[];
  results: ResultReport[];
  error?: string;
};

export type Probe = {
  name: string;
  run(ctx: ProbeContext): Promise<ProbeOutcome>;
};

/**
 * A probe that declares the settings it reads (F6). It gets them parsed; when they do not parse it does not run, and
 * each of its checks that is due gets an error result naming the key, so a bad edit to one key is one probe's problem
 * and the other probes and the tick go on.
 */
export function defineProbe<S>(def: {
  name: string;
  /** The vendor client it uses: its mode is what the outcome reports. */
  client: keyof Clients;
  /** The app-run checks it reports. */
  checks: readonly string[];
  settings: z.ZodType<S>;
  run(ctx: ProbeContext & { settings: S }): Promise<ProbeOutcome>;
}): Probe {
  return {
    name: def.name,
    async run(ctx) {
      const read = readSettings(def.settings, ctx.state.settings);
      if (!read.ok) {
        const results: ResultReport[] = def.checks
          .filter((id) => checkDue(ctx.state, id, ctx.now))
          .map((check_id) => ({ check_id, status: "error", value: {}, error: read.error }));
        return { status: "error", mode: ctx.clients[def.client].mode, heartbeats: [], results, error: read.error };
      }
      return def.run({ ...ctx, settings: read.value });
    },
  };
}
