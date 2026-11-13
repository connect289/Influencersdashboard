import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { bootEnv } from "./env.ts";
import { fetchWithTimeout } from "./fetch-timeout.ts";

// The signed-in person's Supabase client: the publishable key plus their session cookies, schema one. Every page read
// and write goes through it, so one.ui_require() sees the person's own JWT (D-058). Create one per request.

export class NotConfigured extends Error {
  constructor() {
    super("ONE_SUPABASE_URL or ONE_SUPABASE_ANON_KEY is not set");
  }
}

export async function userClient() {
  const env = bootEnv();
  if (!env.ONE_SUPABASE_URL || !env.ONE_SUPABASE_ANON_KEY) throw new NotConfigured();
  const store = await cookies();
  return createServerClient(env.ONE_SUPABASE_URL, env.ONE_SUPABASE_ANON_KEY, {
    db: { schema: "one" },
    // Every call ends at 15 s (D-137): a stalled database fails the page with its error instead of holding it.
    global: { fetch: fetchWithTimeout() },
    cookies: {
      getAll: () => store.getAll(),
      setAll(toSet) {
        try {
          for (const { name, value, options } of toSet) store.set(name, value, options);
        } catch {
          // A Server Component cannot set cookies; the middleware refreshes the session on every request.
        }
      },
    },
  });
}

export type UserClient = Awaited<ReturnType<typeof userClient>>;
