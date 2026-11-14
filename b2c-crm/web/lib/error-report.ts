// Counts the server errors this app throws and reports the counts to Eduwit One (one.app_error_report, Eduwit One's
// migration 0041, decision D-141). The same file is copied into every Eduwit app; only the caller differs
// (instrumentation.ts: which app, which service client). The host's logs keep the detail; this adds the number, so that
// Eduwit One's check can tell someone when an app starts throwing. No third-party service.
//
// Rules this file keeps:
//  - It reports only what the app's error log line already holds: the route as its file names it (never the address,
//    its ids or its query), the error's name, the masked message when the app logs one, Next's digest and the kind of
//    render. No user, header, cookie or body. The database masks and cuts every field again.
//  - It never throws and never makes a request wait: a flush runs in the background and is cut after 3 seconds.
//  - One flush a minute per server instance at most (the first error after a quiet minute goes at once, the rest wait
//    for the minute), or sooner when 50 different route and error pairs are waiting, never under 5 seconds apart.
//  - A flush that fails is dropped, and nothing is sent for 5 minutes: a failure to report is not an error to report.
//  - It does nothing unless the caller says it is enabled (a production build with a hosted Supabase address and the
//    service key), so tests, CI and local development report nothing.
//  - No imports, no Node-only API: it also runs where the middleware does (the edge runtime).

export type ErrorReportInput = {
  route: string;
  name?: string | null;
  message?: string | null;
  digest?: string | null;
  kind?: string | null;
};

export type ErrorReportItem = {
  route: string;
  name: string;
  n: number;
  message: string | null;
  digest: string | null;
  kind: string | null;
};

export type ErrorReporterOptions = {
  /** Whether this deployment reports at all; asked on every error, so it may read the environment lazily. */
  enabled: () => boolean;
  /** One call of one.app_error_report with the app's service client; it must stop when the signal aborts. */
  send: (items: ErrorReportItem[], signal: AbortSignal) => Promise<void>;
  /** Told once when a flush fails, with a short code (never the error's text). */
  onFailure?: (code: string) => void;
  now?: () => number;
};

export type ErrorReporter = {
  /** Counts one error. Never throws. */
  record: (input: ErrorReportInput) => void;
  /** Sends what is waiting, if a flush is allowed now. Never rejects. */
  flush: () => Promise<void>;
  /** How many route and error pairs are waiting. */
  pending: () => number;
};

export const FLUSH_INTERVAL_MS = 60_000;
export const MIN_FLUSH_GAP_MS = 5_000;
export const SEND_TIMEOUT_MS = 3_000;
export const FAILURE_PAUSE_MS = 5 * 60_000;
/** Pairs sent in one report (the database refuses more than 50); the last one is the overflow pair when it is needed. */
export const MAX_PAIRS = 50;
/** The most one pair counts in one report (the database caps a count at the same number). */
export const MAX_COUNT = 10_000;
export const OVERFLOW = "(overflow)";

const cut = (v: unknown, max: number): string | null =>
  typeof v === "string" && v.length > 0 ? v.slice(0, max) : null;

/** The fields as they are sent: the route without query or fragment, a name that is an identifier, everything cut. */
export function reportItem(input: ErrorReportInput): Omit<ErrorReportItem, "n"> {
  const route = cut((typeof input.route === "string" ? input.route : "").split(/[?#]/)[0], 200) ?? "(unknown)";
  const name = cut(input.name, 60);
  const digest = cut(input.digest, 64);
  const kind = cut(input.kind, 20);
  return {
    route,
    name: name && /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name) ? name : "Error",
    message: cut(typeof input.message === "string" ? input.message.replace(/\s+/g, " ").trim() : null, 200),
    digest: digest && /^[A-Za-z0-9_.:;-]+$/.test(digest) ? digest : null,
    kind: kind && /^[a-z][a-z_-]*$/.test(kind) ? kind : null,
  };
}

/** A Supabase address that is a hosted project: https, and not this machine, a container name or a private network. */
export function isHostedSupabaseUrl(url: string | undefined | null): boolean {
  if (!url) return false;
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  const host = parsed.hostname.toLowerCase();
  if (parsed.protocol !== "https:") return false;
  if (!host.includes(".") || host.endsWith(".local") || host.endsWith(".localhost") || host.endsWith(".internal"))
    return false;
  return !/^(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|0\.0\.0\.0$|\[)/.test(host);
}

/** What `enabled` is in every app: a production build, a hosted Supabase address and the service key. */
export function reportingEnabled(env: {
  nodeEnv: string | undefined;
  url: string | undefined;
  serviceKey: string | undefined;
}): boolean {
  return env.nodeEnv === "production" && Boolean(env.serviceKey) && isHostedSupabaseUrl(env.url);
}

/** A short code for a failed flush: the error's code or name when it looks like one, never its message. */
export function failureCode(error: unknown): string {
  const e = (typeof error === "object" && error !== null ? error : {}) as { code?: unknown; name?: unknown };
  for (const v of [e.code, e.name]) {
    if (typeof v === "string" && /^[A-Za-z0-9_.-]{1,40}$/.test(v)) return v;
  }
  return "error";
}

export function createErrorReporter(options: ErrorReporterOptions): ErrorReporter {
  const now = options.now ?? (() => Date.now());
  let waiting = new Map<string, ErrorReportItem>();
  let lastFlushAt = Number.NEGATIVE_INFINITY;
  let pausedUntil = Number.NEGATIVE_INFINITY;
  let sending = false;
  let timer: ReturnType<typeof setTimeout> | undefined;

  const arm = (): void => {
    if (timer !== undefined || waiting.size === 0) return;
    const wait = Math.max(lastFlushAt + FLUSH_INTERVAL_MS, pausedUntil) - now();
    timer = setTimeout(
      () => {
        timer = undefined;
        void flush();
      },
      Math.min(Math.max(wait, 0), FAILURE_PAUSE_MS),
    );
    // A waiting report must not keep a server process alive (Node); the edge runtime's timers have no unref.
    (timer as { unref?: () => void }).unref?.();
  };

  const send = async (items: ErrorReportItem[]): Promise<void> => {
    const controller = new AbortController();
    let cutTimer: ReturnType<typeof setTimeout> | undefined;
    const cutOff = new Promise<never>((_, reject) => {
      cutTimer = setTimeout(() => {
        controller.abort();
        reject(Object.assign(new Error("report timed out"), { code: "timeout" }));
      }, SEND_TIMEOUT_MS);
    });
    try {
      // The race ends the wait even when a client ignores the signal.
      await Promise.race([options.send(items, controller.signal), cutOff]);
    } finally {
      if (cutTimer !== undefined) clearTimeout(cutTimer);
    }
  };

  async function flush(): Promise<void> {
    try {
      const at = now();
      if (sending || waiting.size === 0) return;
      if (at < pausedUntil || at - lastFlushAt < MIN_FLUSH_GAP_MS) return arm();
      const items = [...waiting.values()];
      waiting = new Map();
      lastFlushAt = at;
      sending = true;
      if (timer !== undefined) {
        clearTimeout(timer);
        timer = undefined;
      }
      try {
        await send(items);
      } catch (error) {
        // Dropped, not kept: a database that refuses must not be asked again with a growing batch.
        pausedUntil = now() + FAILURE_PAUSE_MS;
        try {
          options.onFailure?.(failureCode(error));
        } catch {
          // nothing more to do
        }
      } finally {
        sending = false;
        arm();
      }
    } catch {
      // nothing more to do
    }
  }

  function record(input: ErrorReportInput): void {
    try {
      if (!options.enabled()) return;
      const item = reportItem(input);
      let key = `${item.route}\n${item.name}`;
      let slot = waiting.get(key);
      if (!slot && waiting.size >= MAX_PAIRS - 1) {
        // No room for another pair: the count is kept, the detail is not.
        key = OVERFLOW;
        slot = waiting.get(key);
        if (!slot) {
          slot = { route: OVERFLOW, name: OVERFLOW, n: 0, message: null, digest: null, kind: null };
          waiting.set(key, slot);
        }
      }
      if (slot) {
        slot.n = Math.min(slot.n + 1, MAX_COUNT);
      } else {
        waiting.set(key, { ...item, n: 1 });
      }
      const sinceFlush = now() - lastFlushAt;
      if (sinceFlush >= FLUSH_INTERVAL_MS || (waiting.size >= MAX_PAIRS - 1 && sinceFlush >= MIN_FLUSH_GAP_MS)) {
        void flush();
      } else {
        arm();
      }
    } catch {
      // Counting an error must never become a second one.
    }
  }

  return { record, flush, pending: () => waiting.size };
}
