// Every database call ends (D-137): Supabase's clients wait as long as the platform lets a function run, so a stalled
// database held a page, the tick or the middleware until Vercel's ceiling and was billed for it (D-133). The clients
// get a fetch that gives up after DB_TIMEOUT_MS; a caller's own signal still aborts sooner. No server-only import: the
// middleware uses it too.

export const DB_TIMEOUT_MS = 15_000;

/** A signal that aborts at the timeout or when `existing` aborts, whichever comes first. */
export function timeoutSignal(ms: number, existing?: AbortSignal | null): AbortSignal {
  const timeout = AbortSignal.timeout(ms);
  if (!existing) return timeout;
  if (typeof AbortSignal.any === "function") return AbortSignal.any([existing, timeout]);
  // Runtimes without AbortSignal.any: the first of the two to abort aborts this one, with its reason.
  const c = new AbortController();
  for (const s of [existing, timeout]) {
    if (s.aborted) {
      c.abort(s.reason);
      break;
    }
    s.addEventListener("abort", () => c.abort(s.reason), { once: true });
  }
  return c.signal;
}

/** `fetch` with a time limit, for a Supabase client's `global.fetch`. */
export function fetchWithTimeout(ms: number = DB_TIMEOUT_MS, base?: typeof fetch): typeof fetch {
  return (input, init) => {
    const existing = init?.signal ?? (input instanceof Request ? input.signal : undefined);
    return (base ?? globalThis.fetch)(input, { ...init, signal: timeoutSignal(ms, existing) });
  };
}
