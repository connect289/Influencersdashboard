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

// The public page's guard (security review m5, D-137): one server instance keeps its verdict for 10 s, so a burst
// costs one database read and every request in it gets the same status; a read already in flight is shared; and the
// database is read at most READ_LIMIT times a minute. Past that limit a request gets the last verdict with its real
// status, however old, never a refusal: answering 429 {"ok":false} let anyone make the external monitor report "down"
// by calling the page 21 times a minute (the audit of 13 Nov). The uptime monitor polls every 5 minutes.
export const VERDICT_TTL_MS = 10_000;
export const READ_LIMIT = 20;
export const LIMIT_WINDOW_MS = 60_000;

/** cached: answer with this verdict; fresh: read the database; unknown: over the limit with no verdict read yet. */
export type GateAnswer = { kind: "cached"; ok: boolean } | { kind: "fresh" } | { kind: "unknown" };

export class WatchdogGate {
  private verdict: { ok: boolean; at: number } | null = null;
  private reads: number[] = [];
  private inflight: Promise<boolean> | null = null;

  /** Says whether to answer from the cache or read the database (epoch ms); a read is counted when it is granted. */
  take(now: number): GateAnswer {
    if (this.verdict && now - this.verdict.at < VERDICT_TTL_MS) return { kind: "cached", ok: this.verdict.ok };
    this.reads = this.reads.filter((t) => now - t < LIMIT_WINDOW_MS);
    if (this.reads.length >= READ_LIMIT) {
      return this.verdict ? { kind: "cached", ok: this.verdict.ok } : { kind: "unknown" };
    }
    this.reads.push(now);
    return { kind: "fresh" };
  }

  /** Keeps a verdict just read for the next VERDICT_TTL_MS. */
  remember(ok: boolean, now: number): void {
    this.verdict = { ok, at: now };
  }

  /**
   * The verdict for one request: from the cache, from the read another request already started, or from a new read
   * (`read` resolves to the verdict; a read that throws is "down"). Over the read limit with no verdict ever read on
   * this instance the answer is "down": nothing else is known.
   */
  async verdictFor(now: number, read: () => Promise<boolean>, clock: () => number = Date.now): Promise<boolean> {
    if (this.inflight) return this.inflight;
    const answer = this.take(now);
    if (answer.kind === "cached") return answer.ok;
    if (answer.kind === "unknown") return false;
    const pending = (async () => {
      let ok = false;
      try {
        ok = await read();
      } catch {
        ok = false;
      }
      this.remember(ok, clock());
      return ok;
    })();
    this.inflight = pending;
    try {
      return await pending;
    } finally {
      this.inflight = null;
    }
  }
}
