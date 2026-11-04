import type { OneDb } from "../db.ts";
import type { Clients } from "../clients/types.ts";
import type { Report } from "../state.ts";
import { appHealthProbe } from "./probes/app-health.ts";
import { chatwootProbe } from "./probes/chatwoot.ts";
import { n8nProbe } from "./probes/n8n.ts";
import { vercelProbe } from "./probes/vercel.ts";
import { whatsappProbe } from "./probes/whatsapp.ts";
import type { Probe, ProbeOutcome } from "./types.ts";

// One tick of the app (called by one.tick_job through /api/internal/tick): read the state, run every due probe in
// parallel, each under its own deadline so a slow vendor affects only its own heartbeat (spec standard 6), then write
// everything in one call. The one:app heartbeat says the app answered.

export const PROBES: Probe[] = [appHealthProbe, vercelProbe, chatwootProbe, n8nProbe, whatsappProbe];
const PROBE_DEADLINE_MS = 15_000;

export type TickSummary = {
  probes: Record<
    string,
    { status: ProbeOutcome["status"]; mode: string; heartbeats: number; results: number; error?: string }
  >;
  written: Record<string, unknown>;
};

async function withDeadline(p: Promise<ProbeOutcome>, ms: number, mode: ProbeOutcome["mode"]): Promise<ProbeOutcome> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<ProbeOutcome>((resolve) => {
    timer = setTimeout(() => resolve({ status: "error", mode, heartbeats: [], results: [], error: "deadline" }), ms);
  });
  try {
    return await Promise.race([p, late]);
  } finally {
    clearTimeout(timer);
  }
}

export type TickDeps = {
  db: OneDb;
  clients: (state: Awaited<ReturnType<OneDb["tickState"]>>) => Clients;
  requestId: string;
  now?: Date;
  probes?: Probe[];
  probeDeadlineMs?: number;
};

export async function runTick(deps: TickDeps): Promise<TickSummary> {
  const state = await deps.db.tickState();
  const clients = deps.clients(state);
  const now = deps.now ?? new Date();
  const ctx = { state, clients, db: deps.db, now };
  const probes = deps.probes ?? PROBES;
  const outcomes = await Promise.all(
    probes.map(async (probe) => {
      const out = await withDeadline(
        probe.run(ctx).catch((e: unknown) => ({
          status: "error" as const,
          mode: "real" as const,
          heartbeats: [],
          results: [],
          error: e instanceof Error ? e.name : "error",
        })),
        deps.probeDeadlineMs ?? PROBE_DEADLINE_MS,
        "real",
      );
      return [probe.name, out] as const;
    }),
  );
  const report: Report = {
    heartbeats: [
      { component: "one:app", ok: true, detail: { probes: outcomes.length }, expected_interval_s: 60 },
      ...outcomes.flatMap(([, o]) => o.heartbeats),
    ],
    results: outcomes.flatMap(([, o]) => o.results),
  };
  const written = await deps.db.report(report, "app:tick", deps.requestId);
  return {
    probes: Object.fromEntries(
      outcomes.map(([name, o]) => [
        name,
        {
          status: o.status,
          mode: o.mode,
          heartbeats: o.heartbeats.length,
          results: o.results.length,
          ...(o.error ? { error: o.error } : {}),
        },
      ]),
    ),
    written,
  };
}
