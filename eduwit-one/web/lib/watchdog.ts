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
