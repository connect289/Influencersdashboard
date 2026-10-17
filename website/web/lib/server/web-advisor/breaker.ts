import "server-only";
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

export async function recordSuccess() {
  try {
    await kv().del(FAIL_KEY);
  } catch {
    // ignore
  }
}
