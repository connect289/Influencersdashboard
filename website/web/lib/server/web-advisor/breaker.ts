import "server-only";
import { rpc } from "../db";
import { kv } from "../kv";
import { log } from "../log";

/**
 * Circuit breaker for the AI provider (spec 3A): 5 failed or timed-out turns within 2 minutes open the breaker for 60 s;
 * while open, the hero shows the guided finder + "Get free counselling" and /api/witty answers with a fallback. After
 * the cool-down one trial turn is allowed (half-open); success closes it. State lives in the shared KV store.
 */
const FAIL_KEY = "wa:breaker:fails";
const OPEN_KEY = "wa:breaker:open";
const LIMIT = 5;

export async function breakerOpen(): Promise<boolean> {
  try {
    return (await kv().get<number>(OPEN_KEY)) !== null;
  } catch {
    return false;
  }
}

export async function recordFailure(reason: string) {
  try {
    const n = await kv().incr(FAIL_KEY, 120);
    if (n >= LIMIT) {
      await kv().set(OPEN_KEY, Date.now(), 60);
      await kv().del(FAIL_KEY);
      log("error", "web_advisor.breaker_open", { reason, failures: n });
    }
  } catch {
    // KV unavailable: no breaker, turns still time out individually
  }
}

/**
 * Site-wide daily ceiling on Witty turns and model spend (web_settings web_advisor_daily_cap, counted per India day in
 * web_advisor_daily, web14). Checked before every turn; at the ceiling the breaker opens (re-checked every 10 minutes,
 * so a raised ceiling takes effect soon) and the alert is logged. A failed check lets the turn run: the turn itself
 * needs the database.
 */
export async function dailyCapReached(): Promise<boolean> {
  let r: { ok: boolean; turns?: number; cost_usd?: number; max_turns?: number; max_cost_usd?: number; reset_seconds?: number };
  try {
    r = await rpc("web_advisor_daily_check");
  } catch {
    return false;
  }
  if (r.ok) return false;
  try {
    await kv().set(OPEN_KEY, Date.now(), Math.max(1, Math.min(r.reset_seconds ?? 600, 600)));
  } catch {
    // KV unavailable: every turn is refused by this check instead
  }
  log("error", "web_advisor.daily_cap_reached", { turns: r.turns, cost_usd: r.cost_usd, max_turns: r.max_turns, max_cost_usd: r.max_cost_usd });
  return true;
}

export async function recordSuccess() {
  try {
    await kv().del(FAIL_KEY);
  } catch {
    // ignore
  }
}
