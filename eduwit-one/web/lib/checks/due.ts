import type { TickState } from "../state.ts";

// When a reading is due. The minute tick calls the app every minute; each component and each app-run check keeps its
// own interval, read from one.heartbeats and one.checks, so no schedule lives in the app (spec §16.3).

const SLACK_MS = 10_000;

/** A heartbeat component is due when its last reading, good or bad, is older than its interval. */
export function heartbeatDue(
  state: Pick<TickState, "heartbeats">,
  component: string,
  intervalS: number,
  now: Date,
): boolean {
  const hb = state.heartbeats.find((h) => h.component === component);
  const last = Math.max(
    hb?.last_ok_at ? Date.parse(hb.last_ok_at) : 0,
    hb?.last_error_at ? Date.parse(hb.last_error_at) : 0,
  );
  return now.getTime() - last >= intervalS * 1000 - SLACK_MS;
}

/** An app-run check is due when it is enabled and its cadence has passed since it last ran. */
export function checkDue(state: Pick<TickState, "checks">, checkId: string, now: Date): boolean {
  const c = state.checks.find((x) => x.id === checkId);
  if (!c || !c.enabled) return false;
  if (!c.last_ran_at) return true;
  return now.getTime() - Date.parse(c.last_ran_at) >= c.cadence_s * 1000 - SLACK_MS;
}

/** A threshold from settings.thresholds (the probe's parsed settings), or the probe's own default. */
export function threshold(thresholds: Record<string, number>, key: string, fallback: number): number {
  return thresholds[key] ?? fallback;
}
