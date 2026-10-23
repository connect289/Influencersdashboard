import type { OneDb } from "../db.ts";
import type { Clients, ClientMode } from "../clients/types.ts";
import type { HeartbeatReport, ResultReport, TickState } from "../state.ts";

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
