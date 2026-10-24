import { type Watchdog } from "./db.ts";

// The external monitor's verdict (D-018). Down when the last tick that finished its alert step and app call is five
// minutes old or more (a tick whose later steps are killed keeps its heartbeat fresh, so the heartbeat is not read;
// B1 of the second review), or when an alert email has waited ten minutes or more: the app may be unreachable from the
// database while the monitor still reaches it, and then this is the only page anyone gets (M2).
export const MAX_TICK_AGE_S = 300;
export const MAX_DELIVERY_WAIT_S = 600;

export function watchdogOk(w: Watchdog | undefined): boolean {
  if (!w || w.tick_age_s == null || w.tick_age_s >= MAX_TICK_AGE_S) return false;
  return w.delivery_wait_s == null || w.delivery_wait_s < MAX_DELIVERY_WAIT_S;
}

// The public page's guard (security review m5): one server instance keeps its verdict for 10 s, so a burst costs one
// database read and every request in it gets the same status, and refuses more than 20 requests a minute with a 429.
// The uptime monitor polls every 5 minutes, so it never meets either.
export const VERDICT_TTL_MS = 10_000;
export const REQUEST_LIMIT = 20;
export const LIMIT_WINDOW_MS = 60_000;

export type GateAnswer = { kind: "limited" } | { kind: "cached"; ok: boolean } | { kind: "fresh" };

export class WatchdogGate {
  private verdict: { ok: boolean; at: number } | null = null;
  private requests: number[] = [];

  /** Counts this request (epoch ms) and says whether to refuse it, answer from the cache or read the database. */
  take(now: number): GateAnswer {
    this.requests = this.requests.filter((t) => now - t < LIMIT_WINDOW_MS);
    if (this.requests.length >= REQUEST_LIMIT) return { kind: "limited" };
    this.requests.push(now);
    if (this.verdict && now - this.verdict.at < VERDICT_TTL_MS) return { kind: "cached", ok: this.verdict.ok };
    return { kind: "fresh" };
  }

  /** Keeps a verdict just read for the next VERDICT_TTL_MS. */
  remember(ok: boolean, now: number): void {
    this.verdict = { ok, at: now };
  }
}
